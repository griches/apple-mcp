#!/usr/bin/env node
import { join } from "node:path";
import {
  resolveConfig,
  type CliOptions,
  type HydrationCommand,
  type MessagesSourceMode,
  type TranscriptSourceMode,
} from "./config.js";
import { ensureArtifactDirectories } from "./output/artifactPaths.js";
import { writeJsonArtifact } from "./output/writeArtifacts.js";
import { bootstrapCorpusContext } from "./providers/corpusSource.js";
import { harvestMail } from "./providers/mailSource.js";
import { harvestMessages } from "./providers/messagesSource.js";
import { harvestNotes } from "./providers/notesSource.js";
import { normalizeMailHarvest, selectDavidFirstPersonMail } from "./normalize/mailNormalization.js";
import {
  normalizeMessagesHarvest,
  selectDavidFirstPersonMessages,
} from "./normalize/messagesNormalization.js";
import { normalizeNotesHarvest, selectDavidFirstPersonNotes } from "./normalize/notesNormalization.js";

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
  --inbox-limit <n>                Mail inbox messages per persona to fetch (default: 3)
  --sent-limit <n>                 Mail sent messages per persona to fetch (default: 1)
  --notes-limit <n>                Notes to fetch per folder (default: 2)
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

function parsePositiveInt(flag: string, value: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid value for ${flag}: ${value}`);
  }
  return parsed;
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
      case "--inbox-limit":
        options.inboxLimit = parsePositiveInt(token, value);
        break;
      case "--sent-limit":
        options.sentLimit = parsePositiveInt(token, value);
        break;
      case "--notes-limit":
        options.notesLimit = parsePositiveInt(token, value);
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
          inboxLimit: config.inboxLimit,
          sentLimit: config.sentLimit,
          notesLimit: config.notesLimit,
          artifactPaths: config.artifactPaths,
        },
      },
      null,
      2,
    ),
  );
  process.stdout.write("\n");
}

async function runHarvest(config: ReturnType<typeof resolveConfig>): Promise<void> {
  ensureArtifactDirectories(config.artifactPaths);

  const bootstrap = await bootstrapCorpusContext(config.repoRoot);
  const mailHarvest = await harvestMail(config.repoRoot, {
    bootstrap,
    inboxLimit: config.inboxLimit,
    sentLimit: config.sentLimit,
    includeSent: config.sentLimit > 0,
  });
  const normalizedMail = normalizeMailHarvest(mailHarvest);
  const davidFirstPersonMail = selectDavidFirstPersonMail(normalizedMail);
  const messagesHarvest = await harvestMessages(config.repoRoot, {
    sourceMode: config.messagesSource,
    limitPerChat: config.inboxLimit,
  });
  const normalizedMessages = normalizeMessagesHarvest(messagesHarvest);
  const davidFirstPersonMessages = selectDavidFirstPersonMessages(normalizedMessages);
  const notesHarvest = await harvestNotes(config.repoRoot, {
    limitPerFolder: config.notesLimit,
  });
  const normalizedNotes = normalizeNotesHarvest(notesHarvest);
  const davidFirstPersonNotes = selectDavidFirstPersonNotes(normalizedNotes);

  writeJsonArtifact(join(config.artifactPaths.harvestDir, "bootstrap.json"), bootstrap);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "mail-harvest.json"), mailHarvest);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "mail-normalized.json"), normalizedMail);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "david-first-person-mail.json"), davidFirstPersonMail);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "messages-harvest.json"), messagesHarvest);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "messages-normalized.json"), normalizedMessages);
  writeJsonArtifact(
    join(config.artifactPaths.harvestDir, "david-first-person-messages.json"),
    davidFirstPersonMessages,
  );
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "notes-harvest.json"), notesHarvest);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "notes-normalized.json"), normalizedNotes);
  writeJsonArtifact(join(config.artifactPaths.harvestDir, "david-first-person-notes.json"), davidFirstPersonNotes);

  process.stdout.write(
    `${JSON.stringify(
      {
        status: "harvest_complete",
        runId: config.runId,
        outputDir: config.artifactPaths.baseDir,
        bootstrap: {
          corpus: bootstrap.overview.corpus_name,
          personas: bootstrap.personas.length,
          meetingIntelHints: bootstrap.meetingIntelHints.length,
        },
        mail: {
          personaAccounts: mailHarvest.accounts.length,
          normalizedDocuments: normalizedMail.length,
          davidFirstPersonDocuments: davidFirstPersonMail.length,
          errors: mailHarvest.errors,
        },
        messages: {
          sourceMode: messagesHarvest.sourceMode,
          chats: messagesHarvest.chats.length,
          normalizedDocuments: normalizedMessages.length,
          davidFirstPersonDocuments: davidFirstPersonMessages.length,
          errors: messagesHarvest.errors,
        },
        notes: {
          folders: notesHarvest.discoveredFolders.length,
          harvestedNotes: notesHarvest.harvestedNotes.length,
          skippedNotes: notesHarvest.skippedNotes.length,
          normalizedDocuments: normalizedNotes.length,
          davidFirstPersonDocuments: davidFirstPersonNotes.length,
          errors: notesHarvest.errors,
        },
      },
      null,
      2,
    )}\n`,
  );
}

async function main(): Promise<void> {
  try {
    const parsed = parseArgs(process.argv.slice(2));

    if (!parsed) {
      printHelp();
      return;
    }

    const config = resolveConfig(parsed);
    if (config.command === "harvest") {
      await runHarvest(config);
      return;
    }

    printPlannedRun(config);
  } catch (error) {
    process.stderr.write(`Error: ${(error as Error).message}\n\n`);
    printHelp();
    process.exitCode = 1;
  }
}

main().catch((error) => {
  process.stderr.write(`Fatal error: ${(error as Error).message}\n`);
  process.exit(1);
});
