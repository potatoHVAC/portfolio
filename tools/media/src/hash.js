import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";

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
