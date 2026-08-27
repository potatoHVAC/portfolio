import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  createManifestValidator,
  serializeManifest,
  writeManifestAtomic,
} from "../src/manifest.js";

const schemaPath = process.env.MEDIA_SCHEMA_PATH ?? "/workspace/config/media.schema.json";

function imageEntry() {
  const hash = "a".repeat(64);
  const descriptor = (contentType, extension) => ({
    path: `/media/rings/home/hero/${hash}-w1.${extension}`,
    contentType,
    bytes: 1,
    width: 1,
    height: 1,
  });
  return {
    kind: "image",
    sourceSha256: "b".repeat(64),
    alt: "Portrait",
    width: 1,
    height: 1,
    placeholder: "data:image/jpeg;base64,AA==",
    sources: {
      webp: [descriptor("image/webp", "webp")],
      jpeg: [descriptor("image/jpeg", "jpg")],
      avif: [descriptor("image/avif", "avif")],
    },
  };
}

function videoEntry() {
  const videoHash = "c".repeat(64);
  const posterHash = "d".repeat(64);
  const captionHash = "e".repeat(64);
  return {
    kind: "video",
    sourceSha256: "f".repeat(64),
    title: "Demo",
    description: "A short demo",
    sourceDurationMs: 3000,
    clipStartMs: 500,
    clipEndMs: 2500,
    durationMs: 2000,
    video: {
      path: `/media/rings/demo/${videoHash}-320x180.mp4`,
      contentType: "video/mp4",
      bytes: 100,
      width: 320,
      height: 180,
    },
    poster: {
      path: `/media/rings/demo/${posterHash}-poster.jpg`,
      contentType: "image/jpeg",
      bytes: 20,
      width: 320,
      height: 180,
    },
    captions: [{
      path: `/media/rings/demo/${captionHash}-en-us.vtt`,
      contentType: "text/vtt; charset=utf-8",
      bytes: 10,
      language: "en-US",
      label: "English",
    }],
  };
}

test("empty and nested image manifests validate", async () => {
  const validate = await createManifestValidator(schemaPath);
  assert.doesNotThrow(() => validate({ version: 1, assets: {} }));
  assert.doesNotThrow(() =>
    validate({ version: 1, assets: { "rings/home/hero": imageEntry() } }),
  );
});

test("video manifests validate exact derivative, poster, caption, and timing paths", async () => {
  const validate = await createManifestValidator(schemaPath);
  assert.doesNotThrow(() => validate({ version: 1, assets: { "rings/demo": videoEntry() } }));

  const wrongDuration = videoEntry();
  wrongDuration.durationMs = 1500;
  assert.throws(
    () => validate({ version: 1, assets: { "rings/demo": wrongDuration } }),
    /duration does not match/,
  );
  const wrongCaption = videoEntry();
  wrongCaption.captions[0].path = wrongCaption.captions[0].path.replace("-en-us", "-fr");
  assert.throws(
    () => validate({ version: 1, assets: { "rings/demo": wrongCaption } }),
    /invalid en-US caption path/,
  );
  assert.throws(
    () => validate({ version: 1, assets: { "rings/demo": { kind: "video", captions: {} } } }),
    /Invalid media manifest/,
  );
});

test("manifest semantics reject unsafe and mismatched derivative paths", async () => {
  const validate = await createManifestValidator(schemaPath);
  const entry = imageEntry();
  entry.sources.jpeg[0].path = entry.sources.jpeg[0].path.replace(
    "/rings/home/hero/",
    "/other/",
  );
  assert.throws(
    () => validate({ version: 1, assets: { "rings/home/hero": entry } }),
    /content-addressed prefix/,
  );
  assert.throws(
    () => validate({ version: 1, assets: { "../unsafe": imageEntry() } }),
    /Invalid media manifest/,
  );
});

test("serialization is stable and atomic writes preserve the old file on failure", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-manifest-"));
  const manifestPath = path.join(root, "media.json");
  const manifest = {
    assets: { "rings/home/hero": imageEntry() },
    version: 1,
  };
  try {
    const serialized = serializeManifest(manifest);
    assert.ok(serialized.endsWith("\n"));
    assert.ok(serialized.indexOf('"assets"') < serialized.indexOf('"version"'));
    await writeFile(manifestPath, "original\n");
    await assert.rejects(
      writeManifestAtomic(manifestPath, manifest, () => {
        throw new Error("invalid");
      }),
      /invalid/,
    );
    assert.equal(await readFile(manifestPath, "utf8"), "original\n");

    const validate = await createManifestValidator(schemaPath);
    await writeManifestAtomic(manifestPath, manifest, validate);
    assert.equal(await readFile(manifestPath, "utf8"), serialized);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
