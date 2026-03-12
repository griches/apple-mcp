import fs from "node:fs";
import path from "node:path";
import { z } from "zod";

const sourceRuleSchema = z.object({
  label: z.string(),
  matches: z.array(z.string()).min(1),
  domain: z.string(),
  lane: z.string(),
  priority: z.enum(["high", "normal"]).default("normal"),
});

const accountSchema = z.object({
  account: z.string(),
  mailbox: z.string().default("INBOX"),
  personaId: z.string(),
  persona: z.string(),
  role: z.string(),
  summary: z.string(),
  primaryReplyFrom: z.boolean().default(false),
  catchAll: z.boolean().default(false),
  defaultLane: z.string(),
  sourceRules: z.array(sourceRuleSchema).default([]),
});

const domainSchema = z.object({
  name: z.string(),
  matches: z.array(z.string()).min(1),
});

const configSchema = z.object({
  notes: z.object({
    folder: z.string(),
    titlePrefix: z.string(),
    defaultLookbackDays: z.number().int().min(1).default(1),
    defaultLimitPerAccount: z.number().int().min(1).default(20),
  }),
  scoring: z.object({
    urgentSubjectKeywords: z.array(z.string()).default([]),
    automatedSenderKeywords: z.array(z.string()).default([]),
    newsletterKeywords: z.array(z.string()).default([]),
    humanReplyKeywords: z.array(z.string()).default([]),
  }),
  domains: z.array(domainSchema),
  accounts: z.array(accountSchema).min(1),
});

export type IntelligenceConfig = z.infer<typeof configSchema>;
export type IntelligenceAccount = IntelligenceConfig["accounts"][number];
export type SourceRule = IntelligenceAccount["sourceRules"][number];

let cache: IntelligenceConfig | null = null;

function runtimeRoot(): string {
  return path.resolve(__dirname, "..");
}

function resolveConfigPath(): string {
  return process.env.MAIL_INTELLIGENCE_CONFIG_PATH
    ? path.resolve(process.env.MAIL_INTELLIGENCE_CONFIG_PATH)
    : path.resolve(runtimeRoot(), "..", "knowledge-corpus", "data", "mojosolo_operating_brain.json");
}

export function loadConfig(): IntelligenceConfig {
  if (cache) {
    return cache;
  }

  const configPath = resolveConfigPath();
  const raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const candidate = raw.mail_intelligence ?? raw;
  cache = configSchema.parse(candidate);
  return cache;
}

export function getConfigSummary() {
  const config = loadConfig();
  return {
    config_path: resolveConfigPath(),
    note_output: config.notes,
    accounts: config.accounts.map((account) => ({
      account: account.account,
      persona: account.persona,
      persona_id: account.personaId,
      role: account.role,
      primary_reply_from: account.primaryReplyFrom,
      catch_all: account.catchAll,
      default_lane: account.defaultLane,
      source_rule_count: account.sourceRules.length,
    })),
    domains: config.domains.map((domain) => domain.name),
  };
}
