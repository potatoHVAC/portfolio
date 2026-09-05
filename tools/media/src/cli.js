#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";
import sharp from "sharp";
import { checkMediaMetadata } from "./metadata.js";
import { createManifestValidator, loadManifest } from "./manifest.js";
import { publishImage } from "./publisher.js";
import { S3Store } from "./s3.js";
import { assertNoTrackedMedia } from "./tracked.js";
import { hydrateManifest, verifyRemoteManifest } from "./verify.js";
import { publishVideo } from "./video/publisher.js";

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

function runTool(name, arguments_, options = {}) {
  const result = spawnSync(name, arguments_, { stdio: "inherit", ...options });
  if (result.error) throw new Error(`${name} is unavailable`, { cause: result.error });
  if (result.status !== 0) throw new Error(`${name} failed with status ${result.status}`);
}

function firstLine(name, arguments_) {
  const result = spawnSync(name, arguments_, { encoding: "utf8" });
  if (result.error || result.status !== 0) return null;
  return `${result.stdout}${result.stderr}`.trim().split("\n")[0];
}

function toolVersion(name, arguments_) {
  const line = firstLine(name, arguments_);
  if (line === null) return null;
  return (/(?:version )?v?(\d[\w.+~-]*)/.exec(line) ?? ["", line])[1];
}

async function selftest() {
  const metadataCheck = process.env.MEDIA_METADATA_CHECK ?? "";
  let metadataCheckExecutable;
  try {
    fs.accessSync(metadataCheck, fs.constants.X_OK);
    metadataCheckExecutable = true;
  } catch {
    metadataCheckExecutable = false;
  }

  const report = {
    node: process.versions.node,
    libvips: sharp.versions.vips,
    ffmpeg: toolVersion("ffmpeg", ["-version"]),
    ffprobe: toolVersion("ffprobe", ["-version"]),
    exiftool: toolVersion("exiftool", ["-ver"]),
    aws: toolVersion("aws", ["--version"]),
    file: toolVersion("file", ["--version"]),
    jq: toolVersion("jq", ["--version"]),
    metadata_check: metadataCheckExecutable,
  };

  const missing = Object.entries(report)
    .filter(([, value]) => value === null || value === false)
    .map(([key]) => key);
  if (missing.length > 0) throw new Error(`Missing from the image: ${missing.join(", ")}`);

  await sharp({ create: { width: 1, height: 1, channels: 3, background: "black" } })
    .jpeg()
    .toBuffer();

  process.stdout.write(`${JSON.stringify(report)}\n`);
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

async function ci(validateManifest) {
  await check(validateManifest);
  const environment = { ...process.env, MEDIA_SCHEMA_PATH: schemaPath };
  runTool("npm", ["run", "lint"], { cwd: "/app", env: environment });
  runTool("npm", ["test"], { cwd: "/app", env: environment });
  await checkMediaMetadata(["app/assets/images", "public"]);
  await assertNoTrackedMedia(workingDirectory);
  process.stdout.write("Media CI checks passed.\n");
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

  // The image carries no repository, so this answers before
  // createManifestValidator reads config/ out of the working directory.
  if (command === "selftest") return selftest();

  const validateManifest = await createManifestValidator(schemaPath);

  if (command === "check") return check(validateManifest);
  if (command === "ci") return ci(validateManifest);

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
    if (!inputPath || !["image", "video"].includes(kind)) {
      throw new Error("Usage: bin/media publish <image|video> media-source/path [options]");
    }
    const originalsBucket = process.env.SPEERD_MEDIA_ORIGINALS_BUCKET;
    const deliveryBucket = process.env.SPEERD_MEDIA_DELIVERY_BUCKET;
    if (!originalsBucket || !deliveryBucket) throw new Error("Media bucket configuration is missing");
    const store = new S3Store({ originalsBucket, deliveryBucket });

    let result;
    if (kind === "image") {
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
      result = await publishImage({
        inputPath,
        alt: values.alt,
        decorative: values.decorative,
        replace: values.replace,
        sourceRoot,
        temporaryRoot,
        manifestPath,
        validateManifest,
        store,
      });
    } else {
      const { values } = parseArgs({
        args: optionArguments,
        options: {
          title: { type: "string" },
          description: { type: "string" },
          start: { type: "string" },
          end: { type: "string" },
          "poster-at": { type: "string" },
          captions: { type: "string", multiple: true, default: [] },
          "caption-label": { type: "string", multiple: true, default: [] },
          replace: { type: "boolean", default: false },
          verbose: { type: "boolean", default: false },
        },
        strict: true,
      });
      result = await publishVideo({
        inputPath,
        title: values.title,
        description: values.description,
        start: values.start,
        end: values.end,
        posterAt: values["poster-at"],
        captionSpecifications: values.captions,
        captionLabelSpecifications: values["caption-label"],
        replace: values.replace,
        sourceRoot,
        temporaryRoot,
        manifestPath,
        validateManifest,
        store,
      });
    }
    const state = result.changed ? "published" : "already current";
    process.stdout.write(`${kind === "image" ? "Image" : "Video"} ${result.assetId} ${state} (${result.sourceSha256}).\n`);
    return;
  }

  throw new Error("Usage: bin/media <check|ci|publish|verify-manifest|hydrate>");
}

run().catch((error) => fail(error.message));
