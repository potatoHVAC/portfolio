import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function assertSourceUntracked(repositoryRoot, inputPath, runGit = execFileAsync) {
  try {
    await access(path.join(repositoryRoot, ".git"));
  } catch {
    return;
  }

  try {
    await runGit(
      "git",
      ["-C", repositoryRoot, "ls-files", "--error-unmatch", "--", inputPath],
      { maxBuffer: 64 * 1024 },
    );
  } catch (error) {
    if (error.code === 1) return;
    throw new Error("Could not verify that the source is untracked", { cause: error });
  }
  throw new Error("Source media must not be tracked by Git");
}
