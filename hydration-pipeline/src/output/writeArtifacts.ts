import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export function writeJsonArtifact(targetPath: string, value: unknown): void {
  mkdirSync(dirname(targetPath), { recursive: true });
  writeFileSync(targetPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
