import { execFile } from "node:child_process";
import { open } from "node:fs/promises";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const HDR_TRANSFER = new Set(["arib-std-b67", "smpte2084"]);
const SAFE_OUTPUT_TAGS = new Set([
  "compatible_brands",
  "encoder",
  "handler_name",
  "language",
  "major_brand",
  "minor_version",
  "vendor_id",
]);

export async function probeMedia(filePath, runner = execFileAsync) {
  try {
    const { stdout } = await runner(
      "ffprobe",
      [
        "-v",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        "-show_chapters",
        filePath,
      ],
      { maxBuffer: 4 * 1024 * 1024 },
    );
    return JSON.parse(stdout);
  } catch (error) {
    throw new Error(`Could not inspect video: ${error.message}`, { cause: error });
  }
}

function durationMilliseconds(probe) {
  const seconds = Number(probe.format?.duration);
  if (!Number.isFinite(seconds) || seconds <= 0) throw new Error("Video duration is invalid");
  return Math.round(seconds * 1000);
}

function assertInputFormat(source, probe) {
  const formats = new Set((probe.format?.format_name ?? "").split(","));
  const valid = source.expectedFormat === "webm" ? formats.has("webm") : formats.has("mov");
  if (!valid) throw new Error(`Video content does not match ${source.extension}`);
}

function isTenBit(stream) {
  return (
    Number(stream.bits_per_raw_sample ?? 0) > 8 ||
    /(p010|p012|10le|10be|12le|12be|p10|p12)/i.test(stream.pix_fmt ?? "")
  );
}

export async function inspectVideo(source, prober = probeMedia) {
  const probe = await prober(source.absolutePath);
  assertInputFormat(source, probe);
  const video = probe.streams?.find(
    (stream) => stream.codec_type === "video" && stream.disposition?.attached_pic !== 1,
  );
  if (!video || !video.width || !video.height) throw new Error("Video has no readable picture stream");
  if (isTenBit(video)) throw new Error("10-bit video is unsupported in version 1");
  if (HDR_TRANSFER.has(video.color_transfer)) throw new Error("HDR video is unsupported in version 1");
  const audio = probe.streams.find((stream) => stream.codec_type === "audio");
  return {
    probe,
    video,
    audio,
    sourceDurationMs: durationMilliseconds(probe),
  };
}

function assertNoForbiddenMetadata(probe) {
  const tagged = [probe.format, ...(probe.streams ?? []), ...(probe.chapters ?? [])];
  for (const item of tagged) {
    for (const key of Object.keys(item?.tags ?? {})) {
      if (!SAFE_OUTPUT_TAGS.has(key)) throw new Error(`Forbidden video metadata remains: ${key}`);
    }
  }
}

export async function validateVideoDerivative(
  filePath,
  { expectedDurationMs, prober = probeMedia } = {},
) {
  const probe = await prober(filePath);
  const videos = probe.streams?.filter((stream) => stream.codec_type === "video") ?? [];
  const audios = probe.streams?.filter((stream) => stream.codec_type === "audio") ?? [];
  if (videos.length !== 1 || audios.length > 1 || videos.length + audios.length !== probe.streams.length) {
    throw new Error("Published video must contain one video and at most one audio stream");
  }
  const video = videos[0];
  if (video.codec_name !== "h264" || video.pix_fmt !== "yuv420p") {
    throw new Error("Published video must be H.264 with yuv420p pixels");
  }
  if (
    video.width > 1920 ||
    video.height > 1080 ||
    video.width % 2 !== 0 ||
    video.height % 2 !== 0
  ) {
    throw new Error("Published video dimensions are invalid");
  }
  if (
    audios[0] &&
    (audios[0].codec_name !== "aac" || audios[0].profile !== "LC" || audios[0].channels !== 2)
  ) {
    throw new Error("Published audio must be stereo AAC-LC");
  }
  if ((probe.chapters ?? []).length > 0) throw new Error("Published video contains chapters");
  assertNoForbiddenMetadata(probe);
  const durationMs = durationMilliseconds(probe);
  if (Math.abs(durationMs - expectedDurationMs) > 100) {
    throw new Error("Published video duration is outside the 100ms tolerance");
  }
  const startSeconds = Number(probe.format?.start_time ?? 0);
  if (!Number.isFinite(startSeconds) || Math.abs(startSeconds) > 0.001) {
    throw new Error("Published video does not start at zero");
  }
  return { probe, video, audio: audios[0], durationMs };
}

async function readHeader(handle, position, length) {
  const buffer = Buffer.alloc(length);
  const { bytesRead } = await handle.read(buffer, 0, length, position);
  if (bytesRead !== length) throw new Error("MP4 box header is truncated");
  return buffer;
}

export async function assertFaststart(filePath) {
  const handle = await open(filePath, "r");
  try {
    const { size: fileSize } = await handle.stat();
    let position = 0;
    let moovPosition;
    let mediaPosition;
    for (let boxes = 0; position < fileSize && boxes < 10_000; boxes += 1) {
      const header = await readHeader(handle, position, 8);
      let size = header.readUInt32BE(0);
      const type = header.toString("ascii", 4, 8);
      let headerSize = 8;
      if (size === 1) {
        size = Number((await readHeader(handle, position + 8, 8)).readBigUInt64BE(0));
        headerSize = 16;
      } else if (size === 0) {
        size = fileSize - position;
      }
      if (!Number.isSafeInteger(size) || size < headerSize || position + size > fileSize) {
        throw new Error("MP4 contains an invalid top-level box");
      }
      if (type === "moov") moovPosition = position;
      if (type === "mdat") mediaPosition = position;
      position += size;
    }
    if (moovPosition === undefined || mediaPosition === undefined || moovPosition > mediaPosition) {
      throw new Error("Published MP4 is not faststart");
    }
  } finally {
    await handle.close();
  }
}
