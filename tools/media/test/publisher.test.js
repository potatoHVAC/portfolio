import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import sharp from "sharp";
import { sha256Buffer } from "../src/hash.js";
import { publishImage } from "../src/publisher.js";

async function workspace() {
  const root = await mkdtemp(path.join(os.tmpdir(), "media-publisher-"));
  await mkdir(path.join(root, "media-source/rings"), { recursive: true });
  await mkdir(path.join(root, "tmp"));
  await mkdir(path.join(root, "config"));
  await writeFile(path.join(root, "config/media.json"), '{"version":1,"assets":{}}\n');
  await sharp({ create: { width: 20, height: 10, channels: 3, background: "blue" } })
    .jpeg()
    .toFile(path.join(root, "media-source/rings/hero.jpg"));
  return root;
}

function transformedFixture(assetId, seed = "first") {
  const make = (format, contentType, extension) => {
    const data = Buffer.from(`${seed}-${format}`);
    const checksum = sha256Buffer(data);
    return {
      path: `/media/${assetId}/${checksum.hex}-w20.${extension}`,
      contentType,
      bytes: data.byteLength,
      width: 20,
      height: 10,
      checksum,
      data,
    };
  };
  return {
    width: 20,
    height: 10,
    placeholder: "data:image/jpeg;base64,AA==",
    sources: {
      avif: [make("avif", "image/avif", "avif")],
      webp: [make("webp", "image/webp", "webp")],
      jpeg: [make("jpeg", "image/jpeg", "jpg")],
    },
    cleanup: async () => {},
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

function publishOptions(root, store, transformer) {
  return {
    inputPath: "media-source/rings/hero.jpg",
    alt: "Portrait",
    sourceRoot: path.join(root, "media-source"),
    temporaryRoot: path.join(root, "tmp"),
    manifestPath: path.join(root, "config/media.json"),
    validateManifest: (manifest) => manifest,
    store,
    transformer,
  };
}

test("a failed derivative upload leaves the manifest byte-for-byte unchanged", async () => {
  const root = await workspace();
  try {
    const manifestPath = path.join(root, "config/media.json");
    const before = await readFile(manifestPath, "utf8");
    let puts = 0;
    let cleaned = false;
    const transformed = transformedFixture("rings/hero");
    transformed.cleanup = async () => {
      cleaned = true;
    };
    const store = {
      archive: async () => {},
      putDerivative: async () => {
        puts += 1;
        if (puts === 2) throw new Error("upload failed");
      },
    };

    await inWorkspace(root, () =>
      assert.rejects(
        publishImage(publishOptions(root, store, async () => transformed)),
        /upload failed/,
      ),
    );
    assert.equal(await readFile(manifestPath, "utf8"), before);
    assert.equal(cleaned, true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("same-stem collisions fail before an archive write", async () => {
  const root = await workspace();
  try {
    await writeFile(path.join(root, "media-source/rings/hero.mp4"), "video");
    let archives = 0;
    const store = {
      archive: async () => {
        archives += 1;
      },
    };
    await inWorkspace(root, () =>
      assert.rejects(
        publishImage(publishOptions(root, store, async () => transformedFixture("rings/hero"))),
        /Multiple primary sources/,
      ),
    );
    assert.equal(archives, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("identical publication verifies existing objects without rewriting", async () => {
  const root = await workspace();
  try {
    let transforms = 0;
    let archives = 0;
    let verifies = 0;
    const store = {
      archive: async () => {
        archives += 1;
      },
      putDerivative: async () => {},
      verifyDescriptor: async () => {
        verifies += 1;
      },
    };
    const options = publishOptions(root, store, async ({ source }) => {
      transforms += 1;
      return transformedFixture(source.assetId);
    });

    const first = await inWorkspace(root, () => publishImage(options));
    const afterFirst = await readFile(path.join(root, "config/media.json"), "utf8");
    const second = await inWorkspace(root, () => publishImage(options));
    assert.equal(first.changed, true);
    assert.equal(second.changed, false);
    assert.equal(await readFile(path.join(root, "config/media.json"), "utf8"), afterFirst);
    assert.equal(transforms, 1);
    assert.equal(archives, 2);
    assert.equal(verifies, 3);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("changed source requires replacement before archive or manifest writes", async () => {
  const root = await workspace();
  try {
    let archives = 0;
    const store = {
      archive: async () => {
        archives += 1;
      },
      putDerivative: async () => {},
      verifyDescriptor: async () => {},
    };
    const transformer = async ({ source }) => transformedFixture(source.assetId, String(archives));
    const options = publishOptions(root, store, transformer);
    await inWorkspace(root, () => publishImage(options));

    await sharp({ create: { width: 20, height: 10, channels: 3, background: "red" } })
      .jpeg()
      .toFile(path.join(root, "media-source/rings/hero.jpg"));
    await inWorkspace(root, () =>
      assert.rejects(publishImage(options), /use --replace/),
    );
    assert.equal(archives, 1);

    const replaced = await inWorkspace(root, () => publishImage({ ...options, replace: true }));
    assert.equal(replaced.changed, true);
    assert.equal(archives, 2);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
