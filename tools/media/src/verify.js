import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdir, readFile, rename, rm } from "node:fs/promises";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { IMMUTABLE_CACHE_CONTROL } from "./s3.js";

function allDescriptors(manifest) {
  return Object.values(manifest.assets).flatMap((asset) =>
    asset.kind === "video"
      ? [asset.video, asset.poster, ...asset.captions]
      : Object.values(asset.sources).flat(),
  );
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
    if (descriptor.contentType === "video/mp4") {
      const ranged = await fetcher(originUrl(origin, descriptor.path), {
        headers: { Range: "bytes=0-1023" },
      });
      const expectedLastByte = Math.min(1023, descriptor.bytes - 1);
      if (ranged.status !== 206) throw new Error(`${descriptor.path} did not honor Range`);
      if (ranged.headers.get("content-range") !== `bytes 0-${expectedLastByte}/${descriptor.bytes}`) {
        throw new Error(`${descriptor.path} returned the wrong Content-Range`);
      }
      const data = Buffer.from(await ranged.arrayBuffer());
      if (data.byteLength !== expectedLastByte + 1) {
        throw new Error(`${descriptor.path} returned the wrong Range length`);
      }
    }
  }
}

export async function hydrateManifest(manifest, origin, outputRoot, fetcher = fetch) {
  for (const descriptor of allDescriptors(manifest)) {
    const response = await fetcher(originUrl(origin, descriptor.path));
    verifyHeaders(response, descriptor);
    const expectedHash = path.posix.basename(descriptor.path).split("-")[0];

    const relativePath = descriptor.path.replace(/^\/media\//, "");
    if (!relativePath || relativePath.startsWith("../") || path.isAbsolute(relativePath)) {
      throw new Error(`Unsafe hydrate path: ${descriptor.path}`);
    }
    const destination = path.join(outputRoot, relativePath);
    const temporary = `${destination}.${process.pid}.tmp`;
    await mkdir(path.dirname(destination), { recursive: true });
    try {
      if (!response.body) throw new Error(`${descriptor.path} returned an empty body`);
      const hash = createHash("sha256");
      let bytes = 0;
      const hasher = async function* (source) {
        for await (const chunk of source) {
          bytes += chunk.byteLength;
          hash.update(chunk);
          yield chunk;
        }
      };
      await pipeline(response.body, hasher, createWriteStream(temporary, { flags: "wx" }));
      if (bytes !== descriptor.bytes) throw new Error(`${descriptor.path} returned the wrong size`);
      if (hash.digest("hex") !== expectedHash) {
        throw new Error(`${descriptor.path} returned bytes with the wrong checksum`);
      }
      await rename(temporary, destination);
    } finally {
      await rm(temporary, { force: true });
    }
  }
}

export async function readAndValidateManifest(manifestPath, validateManifest) {
  return validateManifest(JSON.parse(await readFile(manifestPath, "utf8")));
}
