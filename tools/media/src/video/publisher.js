import path from "node:path";
import { sha256FileWithParts } from "../hash.js";
import { loadManifest, serializeManifest, writeManifestAtomic } from "../manifest.js";
import { resolvePrimarySource } from "../paths.js";
import { multipartPartSize } from "../s3.js";
import { assertSourceUntracked } from "../tracked.js";
import { prepareCaptions } from "./captions.js";
import { inspectVideo } from "./probe.js";
import { resolveClipBounds, resolvePosterTime } from "./time.js";
import { resolveRotation, transformVideo } from "./transform.js";

const SOURCE_CONTENT_TYPES = {
  ".m4v": "video/mp4",
  ".mov": "video/quicktime",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
};

function requiredText(value, option) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${option} is required`);
  return value;
}

function publicDescriptor(descriptor) {
  return Object.fromEntries(
    Object.entries(descriptor).filter(
      ([key]) => !["checksum", "data", "localPath"].includes(key),
    ),
  );
}

function captionDescriptor(assetId, caption) {
  return {
    path: `/media/${assetId}/${caption.checksum.hex}-${caption.languageKey}.vtt`,
    contentType: "text/vtt; charset=utf-8",
    bytes: caption.data.byteLength,
    language: caption.language,
    label: caption.label,
    checksum: caption.checksum,
    data: caption.data,
  };
}

function publicVideoEntry({
  transformed,
  captions,
  sourceSha256,
  title,
  description,
}) {
  return {
    kind: "video",
    sourceSha256,
    title,
    description,
    sourceDurationMs: transformed.sourceDurationMs,
    clipStartMs: transformed.clipStartMs,
    clipEndMs: transformed.clipEndMs,
    durationMs: transformed.durationMs,
    video: publicDescriptor(transformed.video),
    poster: publicDescriptor(transformed.poster),
    captions: captions.map(publicDescriptor),
  };
}

function obviousOptionsMatch(existing, options) {
  if (!existing) return true;
  return (
    existing.kind === "video" &&
    existing.sourceSha256 === options.sourceSha256 &&
    existing.title === options.title &&
    existing.description === options.description &&
    existing.sourceDurationMs === options.sourceDurationMs &&
    existing.clipStartMs === options.bounds.clipStartMs &&
    existing.clipEndMs === options.bounds.clipEndMs &&
    serializeManifest(existing.captions) === serializeManifest(options.publicCaptions)
  );
}

function entryDescriptors(entry) {
  return [entry.video, entry.poster, ...entry.captions];
}

export async function publishVideo({
  inputPath,
  title,
  description,
  start,
  end,
  posterAt,
  rotate,
  captionSpecifications = [],
  captionLabelSpecifications = [],
  replace = false,
  sourceRoot,
  temporaryRoot,
  manifestPath,
  validateManifest,
  store,
  transformer = transformVideo,
}) {
  title = requiredText(title, "--title");
  description = requiredText(description, "--description");
  const rotation = resolveRotation(rotate);
  await assertSourceUntracked(process.cwd(), inputPath);
  const source = await resolvePrimarySource({ sourceRoot, inputPath, kind: "video" });
  const inspection = await inspectVideo(source);
  const bounds = resolveClipBounds({ start, end, sourceDurationMs: inspection.sourceDurationMs });
  const posterAtMs = resolvePosterTime(posterAt, bounds.expectedDurationMs);
  const captions = await prepareCaptions({
    specifications: captionSpecifications,
    labelSpecifications: captionLabelSpecifications,
    sourceRoot,
    videoSource: source,
    durationMs: bounds.expectedDurationMs,
  });
  for (const caption of captions) {
    await assertSourceUntracked(
      process.cwd(),
      path.posix.join(path.posix.basename(sourceRoot), caption.source.relativePath),
    );
  }

  const partSize = multipartPartSize(source.bytes);
  const sourceChecksum = await sha256FileWithParts(source.absolutePath, partSize);
  if (sourceChecksum.bytes !== source.bytes) throw new Error("Source changed during preflight");
  const manifest = await loadManifest(manifestPath, validateManifest);
  const existing = manifest.assets[source.assetId];
  const captionDescriptors = captions.map((caption) => captionDescriptor(source.assetId, caption));
  const options = {
    sourceSha256: sourceChecksum.hex,
    sourceDurationMs: inspection.sourceDurationMs,
    title,
    description,
    bounds,
    publicCaptions: captionDescriptors.map(publicDescriptor),
  };
  if (!obviousOptionsMatch(existing, options) && !replace) {
    throw new Error(`Asset ${source.assetId} already exists; use --replace`);
  }

  await store.archiveFile({
    key: source.relativePath,
    filePath: source.absolutePath,
    bytes: sourceChecksum.bytes,
    checksum: sourceChecksum,
    contentType: SOURCE_CONTENT_TYPES[source.extension],
    partSize,
    replace,
  });
  for (const caption of captions) {
    await store.archive({
      key: caption.source.relativePath,
      data: caption.originalData,
      checksum: caption.originalChecksum,
      contentType: "text/vtt",
      replace,
    });
  }

  const transformed = await transformer({
    source,
    inspection,
    bounds,
    posterAtMs,
    rotation,
    temporaryRoot,
  });
  try {
    const entry = publicVideoEntry({
      transformed,
      captions: captionDescriptors,
      sourceSha256: sourceChecksum.hex,
      title,
      description,
    });
    if (existing && serializeManifest(existing) === serializeManifest(entry)) {
      for (const descriptor of entryDescriptors(existing)) await store.verifyDescriptor(descriptor);
      return { assetId: source.assetId, sourceSha256: sourceChecksum.hex, changed: false };
    }
    if (existing && !replace) throw new Error(`Asset ${source.assetId} already exists; use --replace`);

    for (const descriptor of [transformed.video, transformed.poster, ...captionDescriptors]) {
      await store.putDerivative(descriptor);
    }
    await writeManifestAtomic(
      manifestPath,
      { ...manifest, assets: { ...manifest.assets, [source.assetId]: entry } },
      validateManifest,
    );
    return { assetId: source.assetId, sourceSha256: sourceChecksum.hex, changed: true };
  } finally {
    await transformed.cleanup();
  }
}
