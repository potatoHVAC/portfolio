#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import path from "node:path";
import { parseArgs } from "node:util";
import sharp from "sharp";
import { createManifestValidator, loadManifest } from "./manifest.js";
import { publishImage } from "./publisher.js";
import { S3Store } from "./s3.js";
import { hydrateManifest, verifyRemoteManifest } from "./verify.js";

const workingDirectory = process.cwd();
const manifestPath = path.join(workingDirectory, "config/media.json");
const schemaPath = path.join(workingDirectory, "config/media.schema.json");
const sourceRoot = path.join(workingDirectory, "media-source");
const temporaryRoot = path.join(workingDirectory, "tmp/media");
const hydrateRoot = path.join(workingDirectory, "public/media");

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exitCode = 2;
}

function requireBinary(name) {
  const result = spawnSync(name, ["-version"], { stdio: "ignore" });
  if (result.error) throw new Error(`${name} is unavailable`, { cause: result.error });
}

async function check(validateManifest) {
  for (const binary of ["aws", "exiftool", "ffmpeg", "ffprobe", "file", "jq"]) {
    requireBinary(binary);
  }
  await sharp({ create: { width: 1, height: 1, channels: 3, background: "black" } })
    .jpeg()
    .toBuffer();
  await loadManifest(manifestPath, validateManifest);
  process.stdout.write("Media tool check passed.\n");
}

function parseRemoteOptions(values) {
  return parseArgs({
    args: values,
    options: { remote: { type: "string" } },
    strict: true,
  }).values;
}

async function run() {
  const [command, ...arguments_] = process.argv.slice(2);
  const validateManifest = await createManifestValidator(schemaPath);

  if (command === "check") return check(validateManifest);

  if (command === "verify-manifest") {
    const { remote } = parseRemoteOptions(arguments_);
    const manifest = await loadManifest(manifestPath, validateManifest);
    if (remote) await verifyRemoteManifest(manifest, remote);
    process.stdout.write(`Manifest verified${remote ? " remotely" : ""}.\n`);
    return;
  }

  if (command === "hydrate") {
    const { remote = "https://speerd.com" } = parseRemoteOptions(arguments_);
    const manifest = await loadManifest(manifestPath, validateManifest);
    await hydrateManifest(manifest, remote, hydrateRoot);
    process.stdout.write("Manifest media hydrated.\n");
    return;
  }

  if (command === "publish") {
    const [kind, inputPath, ...optionArguments] = arguments_;
    if (kind === "video") throw new Error("Video publication is implemented in Chunk 5");
    if (kind !== "image" || !inputPath) {
      throw new Error("Usage: bin/media publish image media-source/path --alt TEXT");
    }
    const { values } = parseArgs({
      args: optionArguments,
      options: {
        alt: { type: "string" },
        decorative: { type: "boolean", default: false },
        replace: { type: "boolean", default: false },
        verbose: { type: "boolean", default: false },
      },
      strict: true,
    });
    const originalsBucket = process.env.SPEERD_MEDIA_ORIGINALS_BUCKET;
    const deliveryBucket = process.env.SPEERD_MEDIA_DELIVERY_BUCKET;
    if (!originalsBucket || !deliveryBucket) throw new Error("Media bucket configuration is missing");

    const result = await publishImage({
      inputPath,
      alt: values.alt,
      decorative: values.decorative,
      replace: values.replace,
      sourceRoot,
      temporaryRoot,
      manifestPath,
      validateManifest,
      store: new S3Store({ originalsBucket, deliveryBucket }),
    });
    const state = result.changed ? "published" : "already current";
    process.stdout.write(`Image ${result.assetId} ${state} (${result.sourceSha256}).\n`);
    return;
  }

  throw new Error("Usage: bin/media <check|publish|verify-manifest|hydrate>");
}

run().catch((error) => fail(error.message));
