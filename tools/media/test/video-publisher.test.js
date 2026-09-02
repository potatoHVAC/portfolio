import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { sha256Buffer } from "../src/hash.js";
import { publishVideo } from "../src/video/publisher.js";

const execFileAsync = promisify(execFile);

async function workspace() {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-video-publisher-"));
  await mkdir(path.join(root, "media-source/rings"), { recursive: true });
  await mkdir(path.join(root, "tmp"));
  await mkdir(path.join(root, "config"));
  await writeFile(path.join(root, "config/media.json"), '{"version":1,"assets":{}}\n');
  await writeFile(
    path.join(root, "media-source/rings/demo.en.vtt"),
    "WEBVTT\r\n\r\n00:00:00.000 --> 00:00:01.000\r\nDemo\r\n",
  );
  await execFileAsync("ffmpeg", [
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "lavfi",
    "-i",
    "testsrc=size=64x36:rate=24:duration=1.25",
    "-c:v",
    "libx264",
    "-pix_fmt",
    "yuv420p",
    "-y",
    path.join(root, "media-source/rings/demo.mp4"),
  ]);
  return root;
}

function transformedFixture(assetId, inspection, bounds, cleanup = async () => {}) {
  const videoData = Buffer.from("published video");
  const posterData = Buffer.from("published poster");
  const videoChecksum = sha256Buffer(videoData);
  const posterChecksum = sha256Buffer(posterData);
  return {
    sourceDurationMs: inspection.sourceDurationMs,
    clipStartMs: bounds.clipStartMs,
    clipEndMs: bounds.clipEndMs,
    durationMs: bounds.expectedDurationMs,
    video: {
      path: `/media/${assetId}/${videoChecksum.hex}-64x36.mp4`,
      contentType: "video/mp4",
      bytes: videoData.byteLength,
      width: 64,
      height: 36,
      checksum: videoChecksum,
      data: videoData,
    },
    poster: {
      path: `/media/${assetId}/${posterChecksum.hex}-poster.jpg`,
      contentType: "image/jpeg",
      bytes: posterData.byteLength,
      width: 64,
      height: 36,
      checksum: posterChecksum,
      data: posterData,
    },
    cleanup,
  };
}

async function inWorkspace(root, callback) {
  const previous = process.cwd();
  process.chdir(root);
  try {
    return await callback();
  } finally {
    process.chdir(previous);
  }
}

function options(root, store, transformer) {
  return {
    inputPath: "media-source/rings/demo.mp4",
    title: "Demo",
    description: "A short demo",
    captionSpecifications: ["en:media-source/rings/demo.en.vtt"],
    sourceRoot: path.join(root, "media-source"),
    temporaryRoot: path.join(root, "tmp"),
    manifestPath: path.join(root, "config/media.json"),
    validateManifest: (manifest) => manifest,
    store,
    transformer,
  };
}

test("video publication archives complete inputs and commits normalized public descriptors", async () => {
  const root = await workspace();
  try {
    const sourceBytes = await readFile(path.join(root, "media-source/rings/demo.mp4"));
    const captionBytes = await readFile(path.join(root, "media-source/rings/demo.en.vtt"));
    const archives = [];
    const derivatives = [];
    const verified = [];
    const store = {
      archiveFile: async (request) => {
        archives.push({ ...request, data: await readFile(request.filePath) });
      },
      archive: async (request) => archives.push(request),
      putDerivative: async (descriptor) => derivatives.push(descriptor),
      verifyDescriptor: async (descriptor) => verified.push(descriptor),
    };
    const publisherOptions = options(root, store, async ({ source, inspection, bounds }) =>
        transformedFixture(source.assetId, inspection, bounds),
    );
    const result = await inWorkspace(root, () => publishVideo(publisherOptions));
    assert.equal(result.changed, true);
    assert.deepEqual(archives[0].data, sourceBytes);
    assert.deepEqual(archives[1].data, captionBytes);
    assert.equal(derivatives.length, 3);
    const manifest = JSON.parse(await readFile(path.join(root, "config/media.json"), "utf8"));
    const entry = manifest.assets["rings/demo"];
    assert.equal(entry.kind, "video");
    assert.equal(entry.captions[0].language, "en");
    assert.equal(entry.captions[0].label, "en");
    assert.match(entry.captions[0].path, /-en\.vtt$/);
    assert.equal("checksum" in entry.video, false);
    const second = await inWorkspace(root, () => publishVideo(publisherOptions));
    assert.equal(second.changed, false);
    assert.equal(derivatives.length, 3);
    assert.equal(verified.length, 3);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a failed video derivative upload preserves the manifest and cleans temporary output", async () => {
  const root = await workspace();
  try {
    const manifestPath = path.join(root, "config/media.json");
    const before = await readFile(manifestPath, "utf8");
    let puts = 0;
    let cleaned = false;
    const store = {
      archiveFile: async () => {},
      archive: async () => {},
      putDerivative: async () => {
        puts += 1;
        if (puts === 2) throw new Error("upload failed");
      },
    };
    await inWorkspace(root, () =>
      assert.rejects(
        publishVideo(options(root, store, async ({ source, inspection, bounds }) =>
          transformedFixture(source.assetId, inspection, bounds, async () => {
            cleaned = true;
          }),
        )),
        /upload failed/,
      ),
    );
    assert.equal(await readFile(manifestPath, "utf8"), before);
    assert.equal(cleaned, true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
