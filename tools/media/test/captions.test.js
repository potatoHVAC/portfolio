import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { normalizeWebVtt, prepareCaptions } from "../src/video/captions.js";

async function inDirectory(directory, callback) {
  const previous = process.cwd();
  process.chdir(directory);
  try {
    return await callback();
  } finally {
    process.chdir(previous);
  }
}

test("captions are canonicalized, normalized, checksummed, and labelled", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-captions-"));
  const relative = "media-source/rings/demo.en-us.vtt";
  try {
    await mkdir(path.dirname(path.join(root, relative)), { recursive: true });
    await writeFile(
      path.join(root, relative),
      "WEBVTT\r\n\r\n00:00:00.000 --> 00:00:01.000\r\nHello\r\n",
    );
    const captions = await inDirectory(root, () =>
      prepareCaptions({
        specifications: [`en-us:${relative}`],
        labelSpecifications: ["en-US:English"],
        sourceRoot: path.join(root, "media-source"),
        videoSource: { relativePath: "rings/demo.mp4", extension: ".mp4" },
        durationMs: 1500,
      }),
    );
    assert.equal(captions[0].language, "en-US");
    assert.equal(captions[0].languageKey, "en-us");
    assert.equal(captions[0].label, "English");
    assert.equal(captions[0].data.toString(), "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n");
    assert.notEqual(captions[0].checksum.hex, captions[0].originalChecksum.hex);
    await inDirectory(root, () =>
      assert.rejects(
        prepareCaptions({
          specifications: [`en-US:${relative}`, `en-us:${relative}`],
          sourceRoot: path.join(root, "media-source"),
          videoSource: { relativePath: "rings/demo.mp4", extension: ".mp4" },
          durationMs: 1500,
        }),
        /Duplicate caption language/,
      ),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("captions reject malformed UTF-8, timing, unsupported blocks, and duplicates", () => {
  assert.throws(() => normalizeWebVtt(Buffer.from([0xff]), 1000), /UTF-8/);
  assert.throws(
    () => normalizeWebVtt(Buffer.from("WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nLate\n"), 1000),
    /exceeds/,
  );
  assert.throws(() => normalizeWebVtt(Buffer.from("WEBVTT\n\nSTYLE\n::cue {}\n"), 1000), /unsupported/);
  assert.throws(
    () => normalizeWebVtt(Buffer.from(
      "WEBVTT\n\n00:00:00.500 --> 00:00:00.900\nLater\n\n00:00:00.100 --> 00:00:00.400\nEarlier\n",
    ), 1000),
    /ordered/,
  );
});

test("caption filename and language must match the video contract", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-captions-"));
  const relative = "media-source/rings/wrong.vtt";
  try {
    await mkdir(path.dirname(path.join(root, relative)), { recursive: true });
    await writeFile(path.join(root, relative), "WEBVTT\n");
    await inDirectory(root, () =>
      assert.rejects(
        prepareCaptions({
          specifications: [`en:${relative}`],
          sourceRoot: path.join(root, "media-source"),
          videoSource: { relativePath: "rings/demo.mp4", extension: ".mp4" },
          durationMs: 1000,
        }),
        /must be named/,
      ),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
