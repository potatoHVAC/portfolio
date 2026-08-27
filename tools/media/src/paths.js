import { lstat, readdir, realpath } from "node:fs/promises";
import path from "node:path";

const SEGMENT_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export const IMAGE_EXTENSIONS = new Map([
  [".avif", "heif"],
  [".jpeg", "jpeg"],
  [".jpg", "jpeg"],
  [".png", "png"],
  [".tif", "tiff"],
  [".tiff", "tiff"],
  [".webp", "webp"],
]);

export const VIDEO_EXTENSIONS = new Set([".m4v", ".mov", ".mp4", ".webm"]);
const PRIMARY_EXTENSIONS = new Set([
  ...IMAGE_EXTENSIONS.keys(),
  ...VIDEO_EXTENSIONS,
]);

function assertSafeRelative(relativePath) {
  if (
    !relativePath ||
    relativePath === "." ||
    relativePath.startsWith(`..${path.sep}`) ||
    relativePath === ".." ||
    path.isAbsolute(relativePath)
  ) {
    throw new Error("Source must be beneath media-source/");
  }

  const parts = relativePath.split(path.sep);
  if (parts.some((part) => !part || part === "." || part === "..")) {
    throw new Error("Source path contains an unsafe segment");
  }
  return parts;
}

async function assertNoSymlink(root, relativePath) {
  let current = root;
  for (const part of relativePath.split(path.sep)) {
    current = path.join(current, part);
    if ((await lstat(current)).isSymbolicLink()) {
      throw new Error("Source paths may not contain symlinks");
    }
  }
}

function extensionKind(extension) {
  if (IMAGE_EXTENSIONS.has(extension)) return "image";
  if (VIDEO_EXTENSIONS.has(extension)) return "video";
  return undefined;
}

export async function resolvePrimarySource({ sourceRoot, inputPath, kind }) {
  if (path.isAbsolute(inputPath)) {
    throw new Error("Source path must be relative to the repository");
  }
  if (inputPath.split(/[\\/]/).some((part) => !part || part === "." || part === "..")) {
    throw new Error("Source path contains an unsafe segment");
  }

  const root = await realpath(sourceRoot);
  const candidate = path.resolve(process.cwd(), inputPath);
  const relativePath = path.relative(root, candidate);
  const parts = assertSafeRelative(relativePath);
  await assertNoSymlink(root, relativePath);

  const resolved = await realpath(candidate);
  if (path.relative(root, resolved) !== relativePath) {
    throw new Error("Source path resolves outside media-source/");
  }

  const sourceStat = await lstat(resolved);
  if (!sourceStat.isFile()) {
    throw new Error("Source must be a regular file");
  }

  const filename = parts.at(-1);
  const extension = path.extname(filename);
  if (!extension || extension !== extension.toLowerCase()) {
    throw new Error("Source extension must be lowercase");
  }
  if (!PRIMARY_EXTENSIONS.has(extension)) {
    throw new Error(`Unsupported source extension: ${extension}`);
  }
  if (extensionKind(extension) !== kind) {
    throw new Error(`Source extension does not identify a ${kind}`);
  }

  const stem = path.basename(filename, extension);
  const assetParts = [...parts.slice(0, -1), stem];
  if (assetParts.some((part) => !SEGMENT_PATTERN.test(part))) {
    throw new Error("Source path must use lowercase kebab-case segments");
  }

  const siblings = await readdir(path.dirname(resolved), { withFileTypes: true });
  const collisions = siblings.filter((entry) => {
    const siblingExtension = path.extname(entry.name).toLowerCase();
    return (
      (entry.isFile() || entry.isSymbolicLink()) &&
      PRIMARY_EXTENSIONS.has(siblingExtension) &&
      path.basename(entry.name, path.extname(entry.name)) === stem
    );
  });
  if (collisions.length !== 1) {
    throw new Error(`Multiple primary sources use asset ID ${assetParts.join("/")}`);
  }

  return {
    absolutePath: resolved,
    relativePath: parts.join("/"),
    assetId: assetParts.join("/"),
    extension,
    expectedFormat: IMAGE_EXTENSIONS.get(extension),
    bytes: sourceStat.size,
  };
}

export function deliveryKey(assetId, hash, width, extension) {
  return `media/${assetId}/${hash}-w${width}.${extension}`;
}
