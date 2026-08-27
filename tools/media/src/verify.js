import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { sha256Buffer } from "./hash.js";
import { IMMUTABLE_CACHE_CONTROL } from "./s3.js";

function allDescriptors(manifest) {
  return Object.values(manifest.assets).flatMap((asset) => Object.values(asset.sources).flat());
}

function originUrl(origin, resourcePath) {
  const parsed = new URL(origin);
  if (parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw new Error("Remote origin may not include a path, query, or fragment");
  }
  return new URL(resourcePath, parsed).toString();
}

function verifyHeaders(response, descriptor) {
  if (!response.ok) throw new Error(`${descriptor.path} returned HTTP ${response.status}`);
  if (response.headers.get("content-type") !== descriptor.contentType) {
    throw new Error(`${descriptor.path} returned the wrong Content-Type`);
  }
  if (Number(response.headers.get("content-length")) !== descriptor.bytes) {
    throw new Error(`${descriptor.path} returned the wrong Content-Length`);
  }
  if (response.headers.get("cache-control") !== IMMUTABLE_CACHE_CONTROL) {
    throw new Error(`${descriptor.path} returned the wrong Cache-Control`);
  }
}

export async function verifyRemoteManifest(manifest, origin, fetcher = fetch) {
  for (const descriptor of allDescriptors(manifest)) {
    const response = await fetcher(originUrl(origin, descriptor.path), { method: "HEAD" });
    verifyHeaders(response, descriptor);
  }
}

export async function hydrateManifest(manifest, origin, outputRoot, fetcher = fetch) {
  for (const descriptor of allDescriptors(manifest)) {
    const response = await fetcher(originUrl(origin, descriptor.path));
    verifyHeaders(response, descriptor);
    const data = Buffer.from(await response.arrayBuffer());
    const expectedHash = path.posix.basename(descriptor.path).split("-")[0];
    if (sha256Buffer(data).hex !== expectedHash) {
      throw new Error(`${descriptor.path} returned bytes with the wrong checksum`);
    }

    const relativePath = descriptor.path.replace(/^\/media\//, "");
    if (!relativePath || relativePath.startsWith("../") || path.isAbsolute(relativePath)) {
      throw new Error(`Unsafe hydrate path: ${descriptor.path}`);
    }
    const destination = path.join(outputRoot, relativePath);
    const temporary = `${destination}.${process.pid}.tmp`;
    await mkdir(path.dirname(destination), { recursive: true });
    try {
      await writeFile(temporary, data);
      await rename(temporary, destination);
    } finally {
      await rm(temporary, { force: true });
    }
  }
}

export async function readAndValidateManifest(manifestPath, validateManifest) {
  return validateManifest(JSON.parse(await readFile(manifestPath, "utf8")));
}
