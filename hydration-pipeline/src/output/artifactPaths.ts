import { mkdirSync } from "node:fs";
import { join } from "node:path";

export interface ArtifactPaths {
  baseDir: string;
  harvestDir: string;
  evidenceDir: string;
  skillsDir: string;
  validationDir: string;
  logsDir: string;
}

export function createArtifactPaths(outputRoot: string, runId: string): ArtifactPaths {
  const baseDir = join(outputRoot, runId);

  return {
    baseDir,
    harvestDir: join(baseDir, "harvest"),
    evidenceDir: join(baseDir, "evidence"),
    skillsDir: join(baseDir, "skills"),
    validationDir: join(baseDir, "validation"),
    logsDir: join(baseDir, "logs"),
  };
}

export function ensureArtifactDirectories(paths: ArtifactPaths): void {
  mkdirSync(paths.harvestDir, { recursive: true });
  mkdirSync(paths.evidenceDir, { recursive: true });
  mkdirSync(paths.skillsDir, { recursive: true });
  mkdirSync(paths.validationDir, { recursive: true });
  mkdirSync(paths.logsDir, { recursive: true });
}
