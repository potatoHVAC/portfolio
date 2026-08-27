import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { sha256Buffer } from "../src/hash.js";
import { IMMUTABLE_CACHE_CONTROL } from "../src/s3.js";
import { hydrateManifest, verifyRemoteManifest } from "../src/verify.js";

function fixture() {
  const data = Buffer.from("hydrated derivative");
  const hash = sha256Buffer(data).hex;
  const descriptor = {
    path: `/media/rings/hero/${hash}-w20.webp`,
    contentType: "image/webp",
    bytes: data.byteLength,
    width: 20,
    height: 10,
  };
  return {
    data,
    descriptor,
    manifest: {
      version: 1,
      assets: {
        "rings/hero": {
          kind: "image",
          sources: { avif: [], webp: [descriptor], jpeg: [] },
        },
      },
    },
  };
}

function headers(descriptor) {
  return {
    "content-type": descriptor.contentType,
    "content-length": String(descriptor.bytes),
    "cache-control": IMMUTABLE_CACHE_CONTROL,
  };
}

test("remote verification checks every immutable delivery header", async () => {
  const { manifest, descriptor } = fixture();
  let requested;
  await verifyRemoteManifest(manifest, "https://speerd.com", async (url, options) => {
    requested = { url, options };
    return new Response(null, { status: 200, headers: headers(descriptor) });
  });
  assert.equal(requested.url, `https://speerd.com${descriptor.path}`);
  assert.equal(requested.options.method, "HEAD");

  await assert.rejects(
    verifyRemoteManifest(manifest, "https://speerd.com", async () =>
      new Response(null, {
        status: 200,
        headers: { ...headers(descriptor), "content-type": "application/octet-stream" },
      }),
    ),
    /wrong Content-Type/,
  );
});

test("hydrate preserves the manifest hierarchy and verifies final bytes", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-hydrate-"));
  const { manifest, descriptor, data } = fixture();
  try {
    await hydrateManifest(manifest, "https://speerd.com", root, async () =>
      new Response(data, { status: 200, headers: headers(descriptor) }),
    );
    const hydrated = path.join(root, descriptor.path.replace(/^\/media\//, ""));
    assert.deepEqual(await readFile(hydrated), data);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("an empty manifest performs no remote requests", async () => {
  let requests = 0;
  const fetcher = async () => {
    requests += 1;
    throw new Error("unexpected request");
  };
  const manifest = { version: 1, assets: {} };
  await verifyRemoteManifest(manifest, "https://speerd.com", fetcher);
  await hydrateManifest(manifest, "https://speerd.com", "/tmp/unused", fetcher);
  assert.equal(requests, 0);
});
