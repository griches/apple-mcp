import { resolve } from "node:path";
import { createArtifactPaths, type ArtifactPaths } from "./output/artifactPaths.js";

export type HydrationCommand = "harvest" | "extract" | "compile" | "validate" | "all";
export type MessagesSourceMode = "live" | "export";
export type TranscriptSourceMode = "otter_mail" | "fireflies_vector" | "none";

export interface HydrationConfig {
  repoRoot: string;
  outputRoot: string;
  runId: string;
  command: HydrationCommand;
  profile: string;
  brand: string;
  from?: string;
  to?: string;
  messagesSource: MessagesSourceMode;
  transcriptSource: TranscriptSourceMode;
  inboxLimit: number;
  sentLimit: number;
  artifactPaths: ArtifactPaths;
}

export interface CliOptions {
  command: HydrationCommand;
  profile?: string;
  brand?: string;
  from?: string;
  to?: string;
  output?: string;
  runId?: string;
  messagesSource?: MessagesSourceMode;
  transcriptSource?: TranscriptSourceMode;
  inboxLimit?: number;
  sentLimit?: number;
}

export function resolveRepoRoot(cwd = process.cwd()): string {
  return cwd.endsWith("/hydration-pipeline") ? resolve(cwd, "..") : cwd;
}

export function createDefaultRunId(now = new Date()): string {
  return now.toISOString().replace(/[:]/g, "-").replace(/\..+/, "Z");
}

export function resolveConfig(options: CliOptions, cwd = process.cwd()): HydrationConfig {
  const repoRoot = resolveRepoRoot(cwd);
  const outputRoot = resolve(repoRoot, options.output ?? "artifacts/north-star-hydration");
  const runId = options.runId ?? createDefaultRunId();

  return {
    repoRoot,
    outputRoot,
    runId,
    command: options.command,
    profile: options.profile ?? "david",
    brand: options.brand ?? "mojosolo",
    from: options.from,
    to: options.to,
    messagesSource: options.messagesSource ?? "export",
    transcriptSource: options.transcriptSource ?? "otter_mail",
    inboxLimit: options.inboxLimit ?? 3,
    sentLimit: options.sentLimit ?? 1,
    artifactPaths: createArtifactPaths(outputRoot, runId),
  };
}
