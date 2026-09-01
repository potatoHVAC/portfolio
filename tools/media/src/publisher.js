import { readFile } from "node:fs/promises";
import { inspectImage, publicImageEntry, transformImage } from "./image.js";
import { sha256Buffer } from "./hash.js";
import { loadManifest, writeManifestAtomic } from "./manifest.js";
import { resolvePrimarySource } from "./paths.js";
import { assertSourceUntracked } from "./tracked.js";

const SOURCE_CONTENT_TYPES = {
  heif: "image/avif",
  jpeg: "image/jpeg",
  png: "image/png",
  tiff: "image/tiff",
  webp: "image/webp",
};

function accessibilityOptions({ alt, decorative }) {
  if (decorative && alt !== undefined) {
    throw new Error("--alt and --decorative are mutually exclusive");
  }
  if (decorative) return { alt: "", decorative: true };
  if (alt === undefined || alt.length === 0) {
    throw new Error("A nonempty --alt or explicit --decorative is required");
  }
  return { alt };
}

function samePublication(existing, sourceSha256, accessibility) {
  return (
    existing?.kind === "image" &&
    existing.sourceSha256 === sourceSha256 &&
    existing.alt === accessibility.alt &&
    Boolean(existing.decorative) === Boolean(accessibility.decorative)
  );
}

function descriptors(entry) {
  return Object.values(entry.sources).flat();
}

export async function publishImage({
  inputPath,
  alt,
  decorative = false,
  replace = false,
  sourceRoot,
  temporaryRoot,
  manifestPath,
  validateManifest,
  store,
  transformer = transformImage,
}) {
  const accessibility = accessibilityOptions({ alt, decorative });
  await assertSourceUntracked(process.cwd(), inputPath);
  const source = await resolvePrimarySource({ sourceRoot, inputPath, kind: "image" });
  await inspectImage(source);
  const sourceData = await readFile(source.absolutePath);
  const sourceChecksum = sha256Buffer(sourceData);
  const manifest = await loadManifest(manifestPath, validateManifest);
  const existing = manifest.assets[source.assetId];
  const unchanged = samePublication(existing, sourceChecksum.hex, accessibility);

  if (existing && !unchanged && !replace) {
    throw new Error(`Asset ${source.assetId} already exists; use --replace`);
  }

  await store.archive({
    key: source.relativePath,
    data: sourceData,
    checksum: sourceChecksum,
    contentType: SOURCE_CONTENT_TYPES[source.expectedFormat],
    replace,
  });

  if (unchanged) {
    for (const descriptor of descriptors(existing)) {
      await store.verifyDescriptor(descriptor);
    }
    return { assetId: source.assetId, sourceSha256: sourceChecksum.hex, changed: false };
  }

  const transformed = await transformer({ source, temporaryRoot });
  try {
    for (const descriptor of Object.values(transformed.sources).flat()) {
      await store.putDerivative(descriptor);
    }
    const entry = publicImageEntry(transformed, sourceChecksum.hex, accessibility);
    await writeManifestAtomic(
      manifestPath,
      {
        ...manifest,
        assets: { ...manifest.assets, [source.assetId]: entry },
      },
      validateManifest,
    );
    return { assetId: source.assetId, sourceSha256: sourceChecksum.hex, changed: true };
  } finally {
    await transformed.cleanup();
  }
}
