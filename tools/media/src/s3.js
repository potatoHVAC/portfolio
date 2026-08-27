import {
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

export const IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable";

function isMissing(error) {
  return error?.$metadata?.httpStatusCode === 404 || error?.name === "NotFound";
}

function isPreconditionFailure(error) {
  return error?.$metadata?.httpStatusCode === 412 || error?.name === "PreconditionFailed";
}

function mismatch(fields) {
  return fields.filter(([, expectedValue, actualValue]) => expectedValue !== actualValue)
    .map(([name, expectedValue, actualValue]) => `${name} ${actualValue ?? "missing"} != ${expectedValue}`)
    .join(", ");
}

export class S3Store {
  constructor({ originalsBucket, deliveryBucket, client = new S3Client({}) }) {
    this.originalsBucket = originalsBucket;
    this.deliveryBucket = deliveryBucket;
    this.client = client;
  }

  async head(bucket, key) {
    try {
      return await this.client.send(
        new HeadObjectCommand({ Bucket: bucket, Key: key, ChecksumMode: "ENABLED" }),
      );
    } catch (error) {
      if (isMissing(error)) return undefined;
      throw error;
    }
  }

  assertObject(head, expected, { immutable = false } = {}) {
    const differences = mismatch([
      ["ContentLength", expected.ContentLength, head.ContentLength],
      ["ChecksumSHA256", expected.ChecksumSHA256, head.ChecksumSHA256],
      ["ContentType", expected.ContentType, head.ContentType],
      ...(immutable
        ? [["CacheControl", IMMUTABLE_CACHE_CONTROL, head.CacheControl]]
        : []),
    ]);
    if (differences) throw new Error(`S3 object verification failed: ${differences}`);
  }

  async archive({ key, data, checksum, contentType, replace = false }) {
    const expected = {
      ContentLength: data.byteLength,
      ChecksumSHA256: checksum.base64,
      ContentType: contentType,
    };
    const current = await this.head(this.originalsBucket, key);
    if (current) {
      try {
        this.assertObject(current, expected);
        return { created: false, versionId: current.VersionId };
      } catch (error) {
        if (!replace) {
          throw new Error(`Archived source differs; use --replace: ${error.message}`, {
            cause: error,
          });
        }
      }
    }

    const result = await this.client.send(
      new PutObjectCommand({
        Bucket: this.originalsBucket,
        Key: key,
        Body: data,
        ContentLength: data.byteLength,
        ContentType: contentType,
        ChecksumAlgorithm: "SHA256",
        ChecksumSHA256: checksum.base64,
      }),
    );
    const verified = await this.head(this.originalsBucket, key);
    if (!verified) throw new Error("Archived source was not readable after upload");
    this.assertObject(verified, expected);
    return { created: true, versionId: result.VersionId };
  }

  async putDerivative(descriptor) {
    const key = descriptor.path.slice(1);
    const expected = {
      ContentLength: descriptor.bytes,
      ChecksumSHA256: descriptor.checksum.base64,
      ContentType: descriptor.contentType,
    };
    const current = await this.head(this.deliveryBucket, key);
    if (current) {
      this.assertObject(current, expected, { immutable: true });
      return { created: false };
    }

    try {
      await this.client.send(
        new PutObjectCommand({
          Bucket: this.deliveryBucket,
          Key: key,
          Body: descriptor.data,
          ContentLength: descriptor.bytes,
          ContentType: descriptor.contentType,
          CacheControl: IMMUTABLE_CACHE_CONTROL,
          ChecksumAlgorithm: "SHA256",
          ChecksumSHA256: descriptor.checksum.base64,
          IfNoneMatch: "*",
        }),
      );
    } catch (error) {
      if (!isPreconditionFailure(error)) throw error;
    }

    const verified = await this.head(this.deliveryBucket, key);
    if (!verified) throw new Error("Derivative was not readable after upload");
    this.assertObject(verified, expected, { immutable: true });
    return { created: true };
  }

  async verifyDescriptor(descriptor) {
    const head = await this.head(this.deliveryBucket, descriptor.path.slice(1));
    if (!head) throw new Error(`Missing delivery object: ${descriptor.path}`);
    const hash = descriptor.path.split("/").at(-1).split("-")[0];
    this.assertObject(
      head,
      {
        ContentLength: descriptor.bytes,
        ChecksumSHA256: Buffer.from(hash, "hex").toString("base64"),
        ContentType: descriptor.contentType,
      },
      { immutable: true },
    );
  }
}
