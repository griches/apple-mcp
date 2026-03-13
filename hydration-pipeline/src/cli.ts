#!/usr/bin/env node
import { resolveConfig, type CliOptions, type HydrationCommand, type MessagesSourceMode, type TranscriptSourceMode } from "./config.js";

const HELP_TEXT = `North Star Hydration Pipeline

Usage:
  npm run hydrate -- <command> [options]

Commands:
  harvest     Harvest source material from local providers
  extract     Build evidence bundles from harvested material
  compile     Emit deployable SKILL.md artifacts
  validate    Emit human-review mirrors and rule audits
  all         Run harvest -> extract -> compile -> validate

Options:
  --profile <name>                 Profile target (default: david)
  --brand <name>                   Brand target (default: mojosolo)
  --from <YYYY-MM-DD>              Inclusive lower bound for source window
  --to <YYYY-MM-DD>                Inclusive upper bound for source window
  --messages-source <live|export>  Messages ingestion mode (default: export)
  --transcript-source <otter_mail|fireflies_vector|none>
                                   Transcript ingestion mode (default: otter_mail)
  --output <path>                  Output root relative to repo root
  --run-id <id>                    Override generated run id
  --help                           Show this help text
`;

function printHelp(): void {
  process.stdout.write(`${HELP_TEXT}\n`);
}

function isHydrationCommand(value: string): value is HydrationCommand {
  return ["harvest", "extract", "compile", "validate", "all"].includes(value);
}

function isMessagesSourceMode(value: string): value is MessagesSourceMode {
  return ["live", "export"].includes(value);
}

function isTranscriptSourceMode(value: string): value is TranscriptSourceMode {
  return ["otter_mail", "fireflies_vector", "none"].includes(value);
}

function parseArgs(argv: string[]): CliOptions | null {
  const [commandToken, ...rest] = argv;

  if (!commandToken || commandToken === "--help" || commandToken === "-h") {
    return null;
  }

  if (!isHydrationCommand(commandToken)) {
    throw new Error(`Unknown command: ${commandToken}`);
  }

  const options: CliOptions = { command: commandToken };

  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    const value = rest[index + 1];

    if (token === "--help" || token === "-h") {
      return null;
    }

    if (!value) {
      throw new Error(`Missing value for ${token}`);
    }

    switch (token) {
      case "--profile":
        options.profile = value;
        break;
      case "--brand":
        options.brand = value;
        break;
      case "--from":
        options.from = value;
        break;
      case "--to":
        options.to = value;
        break;
      case "--output":
        options.output = value;
        break;
      case "--run-id":
        options.runId = value;
        break;
      case "--messages-source":
        if (!isMessagesSourceMode(value)) {
          throw new Error(`Invalid messages source: ${value}`);
        }
        options.messagesSource = value;
        break;
      case "--transcript-source":
        if (!isTranscriptSourceMode(value)) {
          throw new Error(`Invalid transcript source: ${value}`);
        }
        options.transcriptSource = value;
        break;
      default:
        throw new Error(`Unknown option: ${token}`);
    }

    index += 1;
  }

  return options;
}

function printPlannedRun(config: ReturnType<typeof resolveConfig>): void {
  process.stdout.write(
    JSON.stringify(
      {
        status: "scaffold_only",
        message: `Command '${config.command}' is scaffolded but not implemented yet.`,
        config: {
          repoRoot: config.repoRoot,
          outputRoot: config.outputRoot,
          runId: config.runId,
          profile: config.profile,
          brand: config.brand,
          from: config.from ?? null,
          to: config.to ?? null,
          messagesSource: config.messagesSource,
          transcriptSource: config.transcriptSource,
          artifactPaths: config.artifactPaths,
        },
      },
      null,
      2,
    ),
  );
  process.stdout.write("\n");
}

function main(): void {
  try {
    const parsed = parseArgs(process.argv.slice(2));

    if (!parsed) {
      printHelp();
      return;
    }

    const config = resolveConfig(parsed);
    printPlannedRun(config);
  } catch (error) {
    process.stderr.write(`Error: ${(error as Error).message}\n\n`);
    printHelp();
    process.exitCode = 1;
  }
}

main();
