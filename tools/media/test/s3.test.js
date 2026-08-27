import assert from "node:assert/strict";
import test from "node:test";
import { sha256Buffer } from "../src/hash.js";
import { IMMUTABLE_CACHE_CONTROL, S3Store } from "../src/s3.js";

class FakeS3Client {
  constructor() {
    this.objects = new Map();
    this.puts = [];
    this.versions = new Map();
    this.corruptReadback = new Set();
  }

  objectKey(input) {
    return `${input.Bucket}/${input.Key}`;
  }

  async send(command) {
    const input = command.input;
    const objectKey = this.objectKey(input);
    if (command.constructor.name === "HeadObjectCommand") {
      const object = this.objects.get(objectKey);
      if (!object) {
        const error = new Error("missing");
        error.name = "NotFound";
        error.$metadata = { httpStatusCode: 404 };
        throw error;
      }
      return {
        ...object,
        ...(this.corruptReadback.has(objectKey) ? { ChecksumSHA256: "wrong" } : {}),
      };
    }

    if (command.constructor.name === "PutObjectCommand") {
      if (input.IfNoneMatch === "*" && this.objects.has(objectKey)) {
        const error = new Error("exists");
        error.name = "PreconditionFailed";
        error.$metadata = { httpStatusCode: 412 };
        throw error;
      }
      const version = (this.versions.get(objectKey) ?? 0) + 1;
      this.versions.set(objectKey, version);
      this.puts.push(input);
      this.objects.set(objectKey, {
        ContentLength: input.ContentLength,
        ChecksumSHA256: input.ChecksumSHA256,
        ContentType: input.ContentType,
        CacheControl: input.CacheControl,
        VersionId: String(version),
      });
      return { VersionId: String(version) };
    }
    throw new Error(`Unexpected command: ${command.constructor.name}`);
  }
}

test("archive is checksum-idempotent and replacement creates a new version", async () => {
  const client = new FakeS3Client();
  const store = new S3Store({ originalsBucket: "originals", deliveryBucket: "delivery", client });
  const first = Buffer.from("complete source one");
  const request = {
    key: "rings/hero.jpg",
    data: first,
    checksum: sha256Buffer(first),
    contentType: "image/jpeg",
  };

  assert.equal((await store.archive(request)).created, true);
  assert.equal((await store.archive(request)).created, false);
  assert.equal(client.versions.get("originals/rings/hero.jpg"), 1);

  const second = Buffer.from("complete source two");
  const replacement = { ...request, data: second, checksum: sha256Buffer(second) };
  await assert.rejects(store.archive(replacement), /use --replace/);
  assert.equal((await store.archive({ ...replacement, replace: true })).created, true);
  assert.equal(client.versions.get("originals/rings/hero.jpg"), 2);
});

test("derivatives are immutable, idempotent, typed, and checksum-verified", async () => {
  const client = new FakeS3Client();
  const store = new S3Store({ originalsBucket: "originals", deliveryBucket: "delivery", client });
  const data = Buffer.from("derivative");
  const checksum = sha256Buffer(data);
  const descriptor = {
    path: `/media/rings/hero/${checksum.hex}-w480.webp`,
    contentType: "image/webp",
    bytes: data.byteLength,
    width: 480,
    height: 270,
    checksum,
    data,
  };

  assert.equal((await store.putDerivative(descriptor)).created, true);
  assert.equal((await store.putDerivative(descriptor)).created, false);
  const put = client.puts.at(-1);
  assert.equal(put.CacheControl, IMMUTABLE_CACHE_CONTROL);
  assert.equal(put.IfNoneMatch, "*");
  assert.equal(put.ContentType, "image/webp");
  assert.equal(put.ChecksumSHA256, checksum.base64);

  client.objects.get(`delivery/${descriptor.path.slice(1)}`).ContentLength += 1;
  await assert.rejects(store.putDerivative(descriptor), /verification failed/);
});

test("failed checksum readback rejects an upload", async () => {
  const client = new FakeS3Client();
  const store = new S3Store({ originalsBucket: "originals", deliveryBucket: "delivery", client });
  const data = Buffer.from("source");
  client.corruptReadback.add("originals/rings/hero.jpg");
  await assert.rejects(
    store.archive({
      key: "rings/hero.jpg",
      data,
      checksum: sha256Buffer(data),
      contentType: "image/jpeg",
    }),
    /ChecksumSHA256/,
  );
});
