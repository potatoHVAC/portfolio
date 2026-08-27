import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { resolvePrimarySource } from "../src/paths.js";
import { assertSourceUntracked } from "../src/tracked.js";

async function workspace() {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-paths-"));
  await mkdir(path.join(root, "media-source/rings/home"), { recursive: true });
  return root;
}

async function inDirectory(directory, callback) {
  const previous = process.cwd();
  process.chdir(directory);
  try {
    return await callback();
  } finally {
    process.chdir(previous);
  }
}

test("nested image and video sources may share a directory", async () => {
  const root = await workspace();
  try {
    await writeFile(path.join(root, "media-source/rings/home/hero.jpg"), "image");
    await writeFile(path.join(root, "media-source/rings/home/demo.mov"), "video");
    await writeFile(path.join(root, "media-source/rings/home/demo.en.vtt"), "WEBVTT\n");

    await inDirectory(root, async () => {
      const source = await resolvePrimarySource({
        sourceRoot: path.join(root, "media-source"),
        inputPath: "media-source/rings/home/hero.jpg",
        kind: "image",
      });
      assert.equal(source.assetId, "rings/home/hero");
      assert.equal(source.relativePath, "rings/home/hero.jpg");
      const video = await resolvePrimarySource({
        sourceRoot: path.join(root, "media-source"),
        inputPath: "media-source/rings/home/demo.mov",
        kind: "video",
      });
      assert.equal(video.assetId, "rings/home/demo");
      assert.equal(video.expectedFormat, "mov");
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("same-stem primary sources fail preflight", async () => {
  const root = await workspace();
  try {
    await writeFile(path.join(root, "media-source/rings/home/hero.jpg"), "image");
    await writeFile(path.join(root, "media-source/rings/home/hero.mp4"), "video");
    await inDirectory(root, () =>
      assert.rejects(
        resolvePrimarySource({
          sourceRoot: path.join(root, "media-source"),
          inputPath: "media-source/rings/home/hero.jpg",
          kind: "image",
        }),
        /Multiple primary sources/,
      ),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("unsafe, unsupported, uppercase, absolute, and symlink paths fail", async () => {
  const root = await workspace();
  try {
    const sourceRoot = path.join(root, "media-source");
    const unsafeDirectory = path.join(sourceRoot, "Bad_Name");
    await mkdir(unsafeDirectory);
    await writeFile(path.join(unsafeDirectory, "hero.jpg"), "image");
    await writeFile(path.join(sourceRoot, "hero.JPG"), "image");
    await writeFile(path.join(sourceRoot, "hero.gif"), "image");
    const outside = path.join(root, "outside.jpg");
    await writeFile(outside, "image");
    await symlink(outside, path.join(sourceRoot, "linked.jpg"));

    await inDirectory(root, async () => {
      const resolve = (inputPath) => resolvePrimarySource({ sourceRoot, inputPath, kind: "image" });
      await assert.rejects(resolve("media-source/Bad_Name/hero.jpg"), /kebab-case/);
      await assert.rejects(resolve("media-source/hero.JPG"), /lowercase/);
      await assert.rejects(resolve("media-source/hero.gif"), /Unsupported/);
      await assert.rejects(resolve(outside), /relative/);
      await assert.rejects(resolve("outside.jpg"), /beneath/);
      await assert.rejects(resolve("media-source/rings/../hero.JPG"), /unsafe segment/);
      await assert.rejects(resolve("media-source/linked.jpg"), /symlinks/);
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("Git-tracked sources are rejected", async () => {
  const root = await workspace();
  try {
    const tracked = "media-source/rings/home/hero.jpg";
    await writeFile(path.join(root, tracked), "image");
    await mkdir(path.join(root, ".git"));
    await assert.rejects(
      assertSourceUntracked(root, tracked, async () => ({ stdout: tracked })),
      /must not be tracked/,
    );
    const notTracked = async () => {
      const error = new Error("not tracked");
      error.code = 1;
      throw error;
    };
    await assert.doesNotReject(assertSourceUntracked(root, "media-source/new.jpg", notTracked));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
