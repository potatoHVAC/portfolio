import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import sharp from "sharp";
import { sha256Buffer } from "../src/hash.js";
import { inspectImage, transformImage } from "../src/image.js";
import { checkImageMetadata } from "../src/metadata.js";
import { resolvePrimarySource } from "../src/paths.js";

const execFileAsync = promisify(execFile);
const checker = process.env.MEDIA_METADATA_CHECK ?? "/app/check-metadata.sh";

async function fixtureWorkspace() {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-image-"));
  await mkdir(path.join(root, "media-source/rings"), { recursive: true });
  await mkdir(path.join(root, "tmp"));
  return root;
}

test("dirty source fails and metadata-free responsive outputs pass", async () => {
  const root = await fixtureWorkspace();
  const previous = process.cwd();
  try {
    process.chdir(root);
    const input = path.join(root, "media-source/rings/hero.jpg");
    await sharp({
      create: { width: 640, height: 360, channels: 3, background: "#9b4dca" },
    })
      .withIccProfile("srgb")
      .jpeg({ quality: 90 })
      .toFile(input);
    await execFileAsync("exiftool", [
      "-overwrite_original",
      "-GPSLatitude=37.7749",
      "-GPSLatitudeRef=N",
      "-GPSLongitude=122.4194",
      "-GPSLongitudeRef=W",
      "-DateTimeOriginal=2026:08:27 12:00:00",
      input,
    ]);
    await assert.rejects(checkImageMetadata([input], checker));

    const source = await resolvePrimarySource({
      sourceRoot: path.join(root, "media-source"),
      inputPath: "media-source/rings/hero.jpg",
      kind: "image",
    });
    const transformed = await transformImage({
      source,
      temporaryRoot: path.join(root, "tmp"),
      metadataChecker: (paths) => checkImageMetadata(paths, checker),
    });
    try {
      assert.deepEqual(
        Object.fromEntries(
          Object.entries(transformed.sources).map(([format, entries]) => [
            format,
            entries.map((entry) => entry.width),
          ]),
        ),
        { avif: [480, 640], webp: [480, 640], jpeg: [480, 640] },
      );
      assert.equal(transformed.width, 640);
      assert.equal(transformed.height, 360);
      assert.match(transformed.placeholder, /^data:image\/jpeg;base64,/);

      for (const [format, entries] of Object.entries(transformed.sources)) {
        for (const entry of entries) {
          const metadata = await sharp(entry.data).metadata();
          assert.equal(metadata.width, entry.width);
          assert.equal(metadata.height, entry.height);
          assert.ok(metadata.width <= 640);
          assert.ok(metadata.icc?.length > 0);
          assert.equal(sha256Buffer(entry.data).hex, entry.checksum.hex);
          assert.match(entry.path, new RegExp(`/${entry.checksum.hex}-w${entry.width}\\.`));
          if (format === "jpeg") assert.equal(metadata.isProgressive, true);
        }
      }
    } finally {
      await transformed.cleanup();
    }
  } finally {
    process.chdir(previous);
    await rm(root, { recursive: true, force: true });
  }
});

test("image bytes must agree with the supported extension", async () => {
  const root = await fixtureWorkspace();
  const previous = process.cwd();
  try {
    process.chdir(root);
    const input = path.join(root, "media-source/rings/wrong.png");
    await sharp({ create: { width: 8, height: 8, channels: 3, background: "red" } })
      .jpeg()
      .toFile(input);
    const source = await resolvePrimarySource({
      sourceRoot: path.join(root, "media-source"),
      inputPath: "media-source/rings/wrong.png",
      kind: "image",
    });
    await assert.rejects(inspectImage(source), /Image content is jpeg, not png/);
  } finally {
    process.chdir(previous);
    await rm(root, { recursive: true, force: true });
  }
});

test("EXIF orientation is applied to output pixels", async () => {
  const root = await fixtureWorkspace();
  const previous = process.cwd();
  try {
    process.chdir(root);
    const input = path.join(root, "media-source/rings/oriented.jpg");
    await sharp({ create: { width: 80, height: 40, channels: 3, background: "green" } })
      .jpeg()
      .toFile(input);
    await execFileAsync("exiftool", ["-overwrite_original", "-Orientation#=6", input]);
    const source = await resolvePrimarySource({
      sourceRoot: path.join(root, "media-source"),
      inputPath: "media-source/rings/oriented.jpg",
      kind: "image",
    });
    const transformed = await transformImage({
      source,
      temporaryRoot: path.join(root, "tmp"),
      metadataChecker: (paths) => checkImageMetadata(paths, checker),
    });
    try {
      assert.equal(transformed.width, 40);
      assert.equal(transformed.height, 80);
      for (const entries of Object.values(transformed.sources)) {
        assert.equal(entries[0].width, 40);
        assert.equal(entries[0].height, 80);
      }
    } finally {
      await transformed.cleanup();
    }
  } finally {
    process.chdir(previous);
    await rm(root, { recursive: true, force: true });
  }
});
