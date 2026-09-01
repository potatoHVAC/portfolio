import path from "node:path";
import { readFile } from "node:fs/promises";
import { sha256Buffer } from "../hash.js";
import { resolveCompanionSource } from "../paths.js";

const CUE_TIME = /^(?:(\d{2,}):)?([0-5]\d):([0-5]\d)\.(\d{3})$/;

function canonicalLanguage(value) {
  if (!/^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$/.test(value)) {
    throw new Error(`Invalid caption language: ${value}`);
  }
  try {
    return Intl.getCanonicalLocales(value)[0];
  } catch (error) {
    throw new Error(`Invalid caption language: ${value}`, { cause: error });
  }
}

function parseSpecification(value, label) {
  const separator = value.indexOf(":");
  if (separator <= 0 || separator === value.length - 1) {
    throw new Error(`${label} must use language:value`);
  }
  return [value.slice(0, separator), value.slice(separator + 1)];
}

function cueMilliseconds(value) {
  const match = value.match(CUE_TIME);
  if (!match) throw new Error(`Invalid WebVTT cue timestamp: ${value}`);
  return (
    (Number(match[1] ?? 0) * 3600 + Number(match[2]) * 60 + Number(match[3])) * 1000 +
    Number(match[4])
  );
}

export function normalizeWebVtt(data, durationMs) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(data);
  } catch (error) {
    throw new Error("Caption file must be valid UTF-8", { cause: error });
  }
  if (text.includes("\0")) throw new Error("Caption file contains a NUL byte");
  const normalized = text.replace(/\r\n?/g, "\n").trimEnd();
  const blocks = normalized.split(/\n{2,}/);
  if (!/^WEBVTT(?:[ \t].*)?(?:\n|$)/.test(blocks[0])) {
    throw new Error("Caption file must begin with WEBVTT");
  }

  let previousStartMs = -1;
  for (const block of blocks.slice(1)) {
    const lines = block.split("\n");
    if (lines[0].startsWith("NOTE")) continue;
    if (["STYLE", "REGION"].includes(lines[0])) {
      throw new Error("STYLE and REGION WebVTT blocks are unsupported");
    }
    const timingIndex = lines[0].includes("-->") ? 0 : 1;
    const timing = lines[timingIndex]?.match(/^(\S+)\s+-->\s+(\S+)(?:\s+.*)?$/);
    if (!timing || lines.length <= timingIndex + 1) throw new Error("Invalid WebVTT cue");
    const startMs = cueMilliseconds(timing[1]);
    const endMs = cueMilliseconds(timing[2]);
    if (startMs >= endMs) throw new Error("WebVTT cue start must precede its end");
    if (startMs < previousStartMs) throw new Error("WebVTT cues must be ordered by start time");
    if (endMs > durationMs) throw new Error("WebVTT cue exceeds the published video");
    previousStartMs = startMs;
  }
  return Buffer.from(`${normalized}\n`, "utf8");
}

function labelsByLanguage(specifications) {
  const labels = new Map();
  for (const specification of specifications) {
    const [rawLanguage, label] = parseSpecification(specification, "--caption-label");
    const language = canonicalLanguage(rawLanguage);
    if (!label.trim()) throw new Error("Caption label must be nonempty");
    if (labels.has(language.toLowerCase())) throw new Error(`Duplicate caption label: ${language}`);
    labels.set(language.toLowerCase(), label);
  }
  return labels;
}

export async function prepareCaptions({
  specifications = [],
  labelSpecifications = [],
  sourceRoot,
  videoSource,
  durationMs,
}) {
  const labels = labelsByLanguage(labelSpecifications);
  const captions = [];
  const languages = new Set();
  for (const specification of specifications) {
    const [rawLanguage, inputPath] = parseSpecification(specification, "--captions");
    const language = canonicalLanguage(rawLanguage);
    const languageKey = language.toLowerCase();
    if (languages.has(languageKey)) throw new Error(`Duplicate caption language: ${language}`);
    languages.add(languageKey);

    const source = await resolveCompanionSource({ sourceRoot, inputPath });
    const videoStem = path.posix.basename(videoSource.relativePath, videoSource.extension);
    const expectedRelative = path.posix.join(
      path.posix.dirname(videoSource.relativePath),
      `${videoStem}.${languageKey}.vtt`,
    );
    if (source.relativePath !== expectedRelative) {
      throw new Error(`Caption must be named ${expectedRelative}`);
    }
    const originalData = await readFile(source.absolutePath);
    const data = normalizeWebVtt(originalData, durationMs);
    captions.push({
      source,
      originalData,
      originalChecksum: sha256Buffer(originalData),
      data,
      checksum: sha256Buffer(data),
      language,
      languageKey,
      label: labels.get(languageKey) ?? language,
    });
  }
  for (const language of labels.keys()) {
    if (!languages.has(language)) throw new Error(`Caption label has no matching track: ${language}`);
  }
  return captions;
}
