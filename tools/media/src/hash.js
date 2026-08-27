import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { open } from "node:fs/promises";

export function sha256Buffer(buffer) {
  const hash = createHash("sha256").update(buffer);
  return {
    hex: hash.digest("hex"),
    base64: createHash("sha256").update(buffer).digest("base64"),
  };
}

export async function sha256File(path) {
  const hex = createHash("sha256");
  const base64 = createHash("sha256");

  for await (const chunk of createReadStream(path)) {
    hex.update(chunk);
    base64.update(chunk);
  }

  return { hex: hex.digest("hex"), base64: base64.digest("base64") };
}

export async function sha256FileWithParts(filePath, partSize) {
  const handle = await open(filePath, "r");
  const full = createHash("sha256");
  const partDigests = [];
  try {
    const { size } = await handle.stat();
    let position = 0;
    while (position < size) {
      const length = Math.min(partSize, size - position);
      const buffer = Buffer.allocUnsafe(length);
      let offset = 0;
      while (offset < length) {
        const { bytesRead } = await handle.read(buffer, offset, length - offset, position + offset);
        if (bytesRead === 0) throw new Error("Source changed while checksums were calculated");
        offset += bytesRead;
      }
      full.update(buffer);
      partDigests.push(createHash("sha256").update(buffer).digest());
      position += length;
    }
    const fullDigest = full.digest();
    const compositeDigest = createHash("sha256")
      .update(Buffer.concat(partDigests))
      .digest("base64");
    return {
      bytes: size,
      hex: fullDigest.toString("hex"),
      base64: fullDigest.toString("base64"),
      compositeBase64: `${compositeDigest}-${partDigests.length}`,
      partCount: partDigests.length,
      partSize,
    };
  } finally {
    await handle.close();
  }
}
