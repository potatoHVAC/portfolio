import { randomBytes } from "node:crypto";
import { readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import Ajv from "ajv";

const CONTENT_TYPES = {
  avif: "image/avif",
  webp: "image/webp",
  jpeg: "image/jpeg",
};
const EXTENSIONS = { avif: "avif", webp: "webp", jpeg: "jpg" };

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

export function serializeManifest(manifest) {
  return `${JSON.stringify(stableValue(manifest), null, 2)}\n`;
}

function addUniquePath(paths, descriptor, errors) {
  if (!descriptor || typeof descriptor.path !== "string") return;
  if (paths.has(descriptor.path)) errors.push(`Duplicate manifest path: ${descriptor.path}`);
  paths.add(descriptor.path);
}

function imageSemanticErrors(assetId, asset, paths) {
  const errors = [];
  for (const [format, descriptors] of Object.entries(asset.sources ?? {})) {
    if (!EXTENSIONS[format] || !Array.isArray(descriptors)) continue;
    let previousWidth = 0;
    for (const descriptor of descriptors) {
      if (
        !descriptor ||
        typeof descriptor.path !== "string" ||
        !Number.isInteger(descriptor.width)
      ) {
        continue;
      }
      const expectedPrefix = `/media/${assetId}/`;
      const hash = path.posix.basename(descriptor.path).split("-")[0];
      const expectedPath = `${expectedPrefix}${hash}-w${descriptor.width}.${EXTENSIONS[format]}`;

      if (descriptor.path !== expectedPath) {
        errors.push(`${assetId} has a ${format} descriptor outside its content-addressed prefix`);
      }
      if (descriptor.contentType !== CONTENT_TYPES[format]) {
        errors.push(`${assetId} has the wrong ${format} content type`);
      }
      if (descriptor.width <= previousWidth) {
        errors.push(`${assetId} ${format} widths must be strictly ascending`);
      }
      previousWidth = descriptor.width;
      addUniquePath(paths, descriptor, errors);
    }
  }
  return errors;
}

function videoSemanticErrors(assetId, asset, paths) {
  const errors = [];
  const expectedPrefix = `/media/${assetId}/`;
  if (asset.video?.path) {
    const filename = path.posix.basename(asset.video.path);
    const hash = filename.split("-")[0];
    const expected = `${expectedPrefix}${hash}-${asset.video.width}x${asset.video.height}.mp4`;
    if (asset.video.path !== expected) errors.push(`${assetId} has an invalid video path`);
    addUniquePath(paths, asset.video, errors);
  }
  if (asset.poster?.path) {
    const hash = path.posix.basename(asset.poster.path).split("-")[0];
    if (asset.poster.path !== `${expectedPrefix}${hash}-poster.jpg`) {
      errors.push(`${assetId} has an invalid poster path`);
    }
    if (
      asset.video &&
      (asset.poster.width !== asset.video.width || asset.poster.height !== asset.video.height)
    ) {
      errors.push(`${assetId} poster dimensions do not match its video`);
    }
    addUniquePath(paths, asset.poster, errors);
  }
  const languages = new Set();
  for (const caption of Array.isArray(asset.captions) ? asset.captions : []) {
    if (typeof caption?.path !== "string" || typeof caption.language !== "string") continue;
    const language = caption.language.toLowerCase();
    const hash = path.posix.basename(caption.path).split("-")[0];
    if (caption.path !== `${expectedPrefix}${hash}-${language}.vtt`) {
      errors.push(`${assetId} has an invalid ${caption.language} caption path`);
    }
    if (languages.has(language)) errors.push(`${assetId} has duplicate caption language ${language}`);
    languages.add(language);
    addUniquePath(paths, caption, errors);
  }
  if (
    Number.isInteger(asset.clipStartMs) &&
    Number.isInteger(asset.clipEndMs) &&
    Number.isInteger(asset.sourceDurationMs)
  ) {
    if (asset.clipStartMs >= asset.clipEndMs || asset.clipEndMs > asset.sourceDurationMs) {
      errors.push(`${assetId} has invalid clip bounds`);
    }
    if (
      Number.isInteger(asset.durationMs) &&
      Math.abs(asset.durationMs - (asset.clipEndMs - asset.clipStartMs)) > 100
    ) {
      errors.push(`${assetId} duration does not match its clip bounds`);
    }
  }
  return errors;
}

function semanticErrors(manifest) {
  const errors = [];
  const paths = new Set();
  for (const [assetId, asset] of Object.entries(manifest.assets ?? {})) {
    if (asset?.kind === "image") errors.push(...imageSemanticErrors(assetId, asset, paths));
    if (asset?.kind === "video") errors.push(...videoSemanticErrors(assetId, asset, paths));
  }
  return errors;
}

export async function createManifestValidator(schemaPath) {
  const schema = JSON.parse(await readFile(schemaPath, "utf8"));
  const validateSchema = new Ajv({ allErrors: true }).compile(schema);

  return (manifest) => {
    const valid = validateSchema(manifest);
    const errors = valid
      ? []
      : validateSchema.errors.map((error) => `${error.instancePath || "/"} ${error.message}`);
    errors.push(...semanticErrors(manifest));
    if (errors.length > 0) {
      throw new Error(`Invalid media manifest:\n${errors.join("\n")}`);
    }
    return manifest;
  };
}

export async function loadManifest(manifestPath, validate) {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  return validate(manifest);
}

export async function writeManifestAtomic(manifestPath, manifest, validate) {
  validate(manifest);
  const temporaryPath = path.join(
    path.dirname(manifestPath),
    `.${path.basename(manifestPath)}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`,
  );
  try {
    await writeFile(temporaryPath, serializeManifest(manifest), { flag: "wx" });
    await rename(temporaryPath, manifestPath);
  } finally {
    await rm(temporaryPath, { force: true });
  }
}
