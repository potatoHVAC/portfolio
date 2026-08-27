const SECONDS_PATTERN = /^(\d+)(?:\.(\d{1,3}))?$/;
const CLOCK_PATTERN = /^(\d{2,}):([0-5]\d):([0-5]\d)(?:\.(\d{1,3}))?$/;

export function parseTime(value, label) {
  if (typeof value !== "string") throw new Error(`${label} is required`);
  let milliseconds;
  const seconds = value.match(SECONDS_PATTERN);
  const clock = value.match(CLOCK_PATTERN);
  if (seconds) {
    milliseconds = Number(seconds[1]) * 1000 + Number((seconds[2] ?? "").padEnd(3, "0"));
  } else if (clock) {
    milliseconds =
      (Number(clock[1]) * 3600 + Number(clock[2]) * 60 + Number(clock[3])) * 1000 +
      Number((clock[4] ?? "").padEnd(3, "0"));
  } else {
    throw new Error(`${label} must be seconds or HH:MM:SS.mmm`);
  }
  if (!Number.isSafeInteger(milliseconds)) throw new Error(`${label} is too large`);
  return milliseconds;
}

export function resolveClipBounds({ start, end, sourceDurationMs }) {
  if ((start === undefined) !== (end === undefined)) {
    throw new Error("--start and --end must be supplied together");
  }
  if (start === undefined) {
    return { clipStartMs: 0, clipEndMs: sourceDurationMs, expectedDurationMs: sourceDurationMs };
  }

  const clipStartMs = parseTime(start, "--start");
  const clipEndMs = parseTime(end, "--end");
  if (clipStartMs >= clipEndMs) throw new Error("--start must be before --end");
  if (clipEndMs > sourceDurationMs) throw new Error("--end exceeds the source duration");
  if (clipEndMs - clipStartMs < 1000) throw new Error("A selected clip must be at least one second");
  return {
    clipStartMs,
    clipEndMs,
    expectedDurationMs: clipEndMs - clipStartMs,
  };
}

export function resolvePosterTime(value, durationMs) {
  const posterAtMs =
    value === undefined ? (durationMs < 2000 ? Math.floor(durationMs / 2) : 1000) : parseTime(value, "--poster-at");
  if (posterAtMs < 0 || posterAtMs >= durationMs) {
    throw new Error("--poster-at must fall within the published video");
  }
  return posterAtMs;
}

export function ffmpegSeconds(milliseconds) {
  return (milliseconds / 1000).toFixed(3);
}
