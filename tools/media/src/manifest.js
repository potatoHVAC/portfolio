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

function semanticErrors(manifest) {
  const errors = [];
  const paths = new Set();

  for (const [assetId, asset] of Object.entries(manifest.assets)) {
    for (const [format, descriptors] of Object.entries(asset.sources)) {
      let previousWidth = 0;
      for (const descriptor of descriptors) {
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
        if (paths.has(descriptor.path)) {
          errors.push(`Duplicate manifest path: ${descriptor.path}`);
        }
        previousWidth = descriptor.width;
        paths.add(descriptor.path);
      }
    }
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
