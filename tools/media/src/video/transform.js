import { execFile } from "node:child_process";
import { mkdtemp, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import sharp from "sharp";
import { sha256Buffer, sha256File } from "../hash.js";
import { checkMediaMetadata } from "../metadata.js";
import { assertFaststart, probeMedia, validateVideoDerivative } from "./probe.js";
import { ffmpegSeconds } from "./time.js";

const execFileAsync = promisify(execFile);

// Clockwise degrees. Sources carry no rotation metadata to honour, so the
// filter is the only thing that turns a frame.
const ROTATION_FILTERS = new Map([
  [90, "transpose=1"],
  [180, "transpose=1,transpose=1"],
  [270, "transpose=2"],
]);

export function resolveRotation(rotate) {
  if (rotate === undefined || rotate === null || rotate === "") return 0;
  const degrees = Number(rotate);
  if (!ROTATION_FILTERS.has(degrees)) throw new Error("--rotate must be 90, 180, or 270");
  return degrees;
}

async function runFfmpeg(arguments_, runner) {
  try {
    await runner("ffmpeg", ["-hide_banner", "-loglevel", "error", ...arguments_], {
      maxBuffer: 4 * 1024 * 1024,
    });
  } catch (error) {
    const detail = error.stderr?.trim() || error.message;
    throw new Error(`FFmpeg failed: ${detail}`, { cause: error });
  }
}

function videoArguments(source, inspection, bounds, rotation, outputPath) {
  const arguments_ = [];
  if (bounds.clipStartMs > 0) arguments_.push("-ss", ffmpegSeconds(bounds.clipStartMs));
  arguments_.push("-i", source.absolutePath);
  if (
    bounds.clipStartMs > 0 ||
    bounds.expectedDurationMs !== inspection.sourceDurationMs
  ) {
    arguments_.push("-t", ffmpegSeconds(bounds.expectedDurationMs));
  }
  arguments_.push("-map", `0:${inspection.video.index}`);
  if (inspection.audio) arguments_.push("-map", `0:${inspection.audio.index}`);
  arguments_.push(
    "-sn",
    "-dn",
    "-map_metadata",
    "-1",
    "-map_chapters",
    "-1",
    "-vf",
    [
      ROTATION_FILTERS.get(rotation),
      "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
      "setsar=1",
      "setpts=PTS-STARTPTS",
    ]
      .filter(Boolean)
      .join(","),
    "-c:v",
    "libx264",
    "-preset",
    "slow",
    "-crf",
    "22",
    "-pix_fmt",
    "yuv420p",
    "-fflags",
    "+bitexact",
    "-flags:v",
    "+bitexact",
    "-metadata",
    "encoder=",
    "-metadata:s:v:0",
    "encoder=",
    "-metadata:s:v:0",
    "title=",
  );
  if (inspection.audio) {
    arguments_.push(
      "-c:a",
      "aac",
      "-b:a",
      "160k",
      "-ac",
      "2",
      "-af",
      "asetpts=PTS-STARTPTS",
      "-flags:a",
      "+bitexact",
      "-metadata:s:a:0",
      "encoder=",
      "-metadata:s:a:0",
      "title=",
    );
  }
  arguments_.push("-movflags", "+faststart", "-y", outputPath);
  return arguments_;
}

export async function transformVideo({
  source,
  inspection,
  bounds,
  posterAtMs,
  rotation = 0,
  temporaryRoot,
  runner = execFileAsync,
  prober = probeMedia,
  metadataChecker = checkMediaMetadata,
}) {
  const workDirectory = await mkdtemp(path.join(temporaryRoot, "video-"));
  const outputPath = path.join(workDirectory, "published.mp4");
  const framePath = path.join(workDirectory, "poster-frame.png");
  const posterPath = path.join(workDirectory, "poster.jpg");
  try {
    await runFfmpeg(videoArguments(source, inspection, bounds, rotation, outputPath), runner);
    const validated = await validateVideoDerivative(outputPath, {
      expectedDurationMs: bounds.expectedDurationMs,
      prober,
    });
    await assertFaststart(outputPath);

    await runFfmpeg(
      [
        "-i",
        outputPath,
        "-ss",
        ffmpegSeconds(posterAtMs),
        "-map",
        "0:v:0",
        "-frames:v",
        "1",
        "-an",
        "-sn",
        "-dn",
        "-y",
        framePath,
      ],
      runner,
    );
    const { data: posterData, info: posterInfo } = await sharp(framePath)
      .keepIccProfile()
      .jpeg({ quality: 82, progressive: true })
      .toBuffer({ resolveWithObject: true });
    await writeFile(posterPath, posterData);
    await metadataChecker([outputPath, posterPath]);

    const videoChecksum = await sha256File(outputPath);
    const videoStat = await stat(outputPath);
    const posterChecksum = sha256Buffer(posterData);
    const prefix = `media/${source.assetId}`;
    return {
      sourceDurationMs: inspection.sourceDurationMs,
      clipStartMs: bounds.clipStartMs,
      clipEndMs: bounds.clipEndMs,
      durationMs: validated.durationMs,
      video: {
        path: `/${prefix}/${videoChecksum.hex}-${validated.video.width}x${validated.video.height}.mp4`,
        contentType: "video/mp4",
        bytes: videoStat.size,
        width: validated.video.width,
        height: validated.video.height,
        checksum: videoChecksum,
        localPath: outputPath,
      },
      poster: {
        path: `/${prefix}/${posterChecksum.hex}-poster.jpg`,
        contentType: "image/jpeg",
        bytes: posterData.byteLength,
        width: posterInfo.width,
        height: posterInfo.height,
        checksum: posterChecksum,
        data: posterData,
      },
      cleanup: () => rm(workDirectory, { recursive: true, force: true }),
    };
  } catch (error) {
    await rm(workDirectory, { recursive: true, force: true });
    throw error;
  }
}
