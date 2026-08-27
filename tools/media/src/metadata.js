import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function checkImageMetadata(paths, checker = process.env.MEDIA_METADATA_CHECK) {
  if (!checker) throw new Error("MEDIA_METADATA_CHECK is not configured");
  await execFileAsync(checker, paths, { maxBuffer: 1024 * 1024 });
}
