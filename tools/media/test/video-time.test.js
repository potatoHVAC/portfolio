import assert from "node:assert/strict";
import test from "node:test";
import { parseTime, resolveClipBounds, resolvePosterTime } from "../src/video/time.js";

test("video times accept seconds and clock notation", () => {
  assert.equal(parseTime("12.345", "time"), 12_345);
  assert.equal(parseTime("01:02:03.4", "time"), 3_723_400);
  assert.deepEqual(resolveClipBounds({ start: "1", end: "2.5", sourceDurationMs: 3000 }), {
    clipStartMs: 1000,
    clipEndMs: 2500,
    expectedDurationMs: 1500,
  });
  assert.deepEqual(resolveClipBounds({ sourceDurationMs: 3000 }), {
    clipStartMs: 0,
    clipEndMs: 3000,
    expectedDurationMs: 3000,
  });
});

test("video clip bounds are paired, ordered, in range, and at least one second", () => {
  assert.throws(() => resolveClipBounds({ start: "0", sourceDurationMs: 3000 }), /together/);
  assert.throws(
    () => resolveClipBounds({ start: "2", end: "1", sourceDurationMs: 3000 }),
    /before/,
  );
  assert.throws(
    () => resolveClipBounds({ start: "0", end: "4", sourceDurationMs: 3000 }),
    /exceeds/,
  );
  assert.throws(
    () => resolveClipBounds({ start: "0", end: "0.999", sourceDurationMs: 3000 }),
    /at least one second/,
  );
  assert.throws(() => parseTime("1:02", "time"), /seconds or HH/);
});

test("poster defaults are relative to the published video", () => {
  assert.equal(resolvePosterTime(undefined, 3000), 1000);
  assert.equal(resolvePosterTime(undefined, 1500), 750);
  assert.equal(resolvePosterTime("0.25", 1500), 250);
  assert.throws(() => resolvePosterTime("1.5", 1500), /within/);
});
