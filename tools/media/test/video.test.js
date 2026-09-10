import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import sharp from "sharp";
import { checkMediaMetadata } from "../src/metadata.js";
import { inspectVideo, probeMedia } from "../src/video/probe.js";
import { resolveRotation, transformVideo } from "../src/video/transform.js";

const execFileAsync = promisify(execFile);

async function makeSource(
  filePath,
  { audio = true, dirty = false, duration = 2.5, size = "64x36" } = {},
) {
  const arguments_ = [
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "lavfi",
    "-i",
    `testsrc=size=${size}:rate=24:duration=${duration}`,
  ];
  if (audio) {
    arguments_.push("-f", "lavfi", "-i", `sine=frequency=1000:duration=${duration}`);
  }
  arguments_.push("-map", "0:v:0");
  if (audio) arguments_.push("-map", "1:a:0");
  arguments_.push("-c:v", "libx264", "-pix_fmt", "yuv420p");
  if (audio) arguments_.push("-c:a", "aac", "-ac", "1");
  if (dirty) {
    arguments_.push(
      "-metadata",
      "location=37.7749-122.4194/",
      "-metadata",
      "creation_time=2026-08-27T12:00:00Z",
      "-metadata",
      "comment=private source",
    );
  }
  arguments_.push("-y", filePath);
  await execFileAsync("ffmpeg", arguments_, { maxBuffer: 4 * 1024 * 1024 });
}

function source(filePath, assetId) {
  return {
    absolutePath: filePath,
    relativePath: `${assetId}.mp4`,
    assetId,
    extension: ".mp4",
    expectedFormat: "mov",
  };
}

test("dirty source fails the gate while an accurately clipped derivative passes", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-video-"));
  const sourcePath = path.join(root, "dirty.mp4");
  try {
    await makeSource(sourcePath, { dirty: true });
    await assert.rejects(checkMediaMetadata([sourcePath]));
    const input = source(sourcePath, "rings/demo");
    const inspection = await inspectVideo(input);
    const transformed = await transformVideo({
      source: input,
      inspection,
      bounds: {
        clipStartMs: 250,
        clipEndMs: 1750,
        expectedDurationMs: 1500,
      },
      posterAtMs: 750,
      temporaryRoot: root,
    });
    try {
      assert.match(transformed.video.path, /-64x36\.mp4$/);
      assert.equal(transformed.durationMs, 1500);
      const outputProbe = await probeMedia(transformed.video.localPath);
      assert.equal(outputProbe.streams[0].codec_name, "h264");
      assert.equal(outputProbe.streams[0].pix_fmt, "yuv420p");
      assert.equal(outputProbe.streams[1].codec_name, "aac");
      assert.equal(outputProbe.streams[1].channels, 2);
      assert.ok(Number(outputProbe.streams[1].bit_rate) >= 150_000);
      assert.ok(Number(outputProbe.streams[1].bit_rate) <= 170_000);
      const poster = await sharp(transformed.poster.data).metadata();
      assert.equal(poster.format, "jpeg");
      assert.equal(poster.isProgressive, true);
      await checkMediaMetadata([
        transformed.video.localPath,
        path.join(path.dirname(transformed.video.localPath), "poster.jpg"),
      ]);
    } finally {
      await transformed.cleanup();
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("full publication preserves silence and does not upscale", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-video-"));
  const sourcePath = path.join(root, "silent.mp4");
  try {
    await makeSource(sourcePath, { audio: false, duration: 1.25, size: "2000x20" });
    const input = source(sourcePath, "rings/silent");
    const inspection = await inspectVideo(input);
    const transformed = await transformVideo({
      source: input,
      inspection,
      bounds: {
        clipStartMs: 0,
        clipEndMs: inspection.sourceDurationMs,
        expectedDurationMs: inspection.sourceDurationMs,
      },
      posterAtMs: 625,
      temporaryRoot: root,
    });
    try {
      const outputProbe = await probeMedia(transformed.video.localPath);
      assert.equal(outputProbe.streams.length, 1);
      assert.equal(outputProbe.streams[0].width, 1920);
      assert.ok(outputProbe.streams[0].height <= 20);
      assert.equal(outputProbe.streams[0].height % 2, 0);
    } finally {
      await transformed.cleanup();
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("10-bit and HDR inputs fail before transformation", async () => {
  const input = source("source.mp4", "rings/demo");
  const probe = (video) => async () => ({
    format: { format_name: "mov,mp4,m4a,3gp,3g2,mj2", duration: "2" },
    streams: [{
      index: 0,
      codec_type: "video",
      codec_name: "h264",
      width: 64,
      height: 36,
      disposition: {},
      ...video,
    }],
    chapters: [],
  });
  await assert.rejects(inspectVideo(input, probe({ pix_fmt: "yuv420p10le" })), /10-bit/);
  await assert.rejects(
    inspectVideo(input, probe({ pix_fmt: "yuv420p", color_transfer: "smpte2084" })),
    /HDR/,
  );
  await assert.rejects(
    inspectVideo(input, async () => ({
      format: { format_name: "webm", duration: "2" },
      streams: [],
    })),
    /does not match/,
  );
});

test("clockwise rotation turns the frame before the delivery cap applies", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-video-"));
  const sourcePath = path.join(root, "portrait.mp4");
  try {
    await makeSource(sourcePath, { audio: false, duration: 1, size: "64x36" });
    const input = source(sourcePath, "rings/rotated");
    const inspection = await inspectVideo(input);
    const transformed = await transformVideo({
      source: input,
      inspection,
      bounds: {
        clipStartMs: 0,
        clipEndMs: inspection.sourceDurationMs,
        expectedDurationMs: inspection.sourceDurationMs,
      },
      posterAtMs: 500,
      rotation: 90,
      temporaryRoot: root,
    });
    try {
      const outputProbe = await probeMedia(transformed.video.localPath);
      assert.equal(outputProbe.streams[0].width, 36);
      assert.equal(outputProbe.streams[0].height, 64);
      assert.match(transformed.video.path, /-36x64\.mp4$/);
      const poster = await sharp(transformed.poster.data).metadata();
      assert.equal(poster.width, 36);
      assert.equal(poster.height, 64);
    } finally {
      await transformed.cleanup();
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("rotation accepts only quarter turns", () => {
  assert.equal(resolveRotation(undefined), 0);
  assert.equal(resolveRotation(""), 0);
  assert.equal(resolveRotation("90"), 90);
  assert.equal(resolveRotation("270"), 270);
  assert.throws(() => resolveRotation("45"), /--rotate must be/);
  assert.throws(() => resolveRotation("clockwise"), /--rotate must be/);
});
