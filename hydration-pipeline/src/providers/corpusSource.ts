import { extractText, parseToolResult, type McpSession, type McpToolResult } from "../mcp/client.js";
import { connectToServer } from "../mcp/localServers.js";

export interface CorpusOverview {
  corpus_name: string;
  corpus_version: string;
  generated_on: string;
  target_company: string;
  target_domain: string;
  section_count: number;
  sections: string[];
  source_count: number;
  report_available: boolean;
  report_section_count: number;
  machine_ingest_entities: string[];
  corpus_path: string;
  report_path: string;
}

export interface CanonicalProfile {
  brand_name: string;
  operating_frame: string[];
  public_identity_summary: string;
  canonical_brain_location: string;
  primary_application_layer: string;
  primary_output_layer: string;
}

export interface CorpusSourceRecord {
  id: string;
  title: string;
  organization: string;
  source_class: string;
  role_in_corpus: string;
  trust_level: string;
  url: string;
}

export interface MailIntelligenceDomain {
  name: string;
  matches: string[];
}

export interface MailIntelligenceSourceRule {
  label: string;
  matches: string[];
  domain: string;
  lane: string;
  priority: "high" | "normal";
}

export interface MailIntelligenceAccount {
  account: string;
  mailbox: string;
  personaId: string;
  persona: string;
  role: string;
  summary: string;
  primaryReplyFrom: boolean;
  catchAll: boolean;
  defaultLane: string;
  sourceRules: MailIntelligenceSourceRule[];
}

export interface MailIntelligenceConfig {
  notes: {
    folder: string;
    titlePrefix: string;
    defaultLookbackDays: number;
    defaultLimitPerAccount: number;
  };
  scoring: Record<string, string[]>;
  domains: MailIntelligenceDomain[];
  accounts: MailIntelligenceAccount[];
}

export interface PersonaMapAccount {
  account: string;
  persona: string;
  persona_id: string;
  role: string;
  primary_reply_from: boolean;
  catch_all: boolean;
  default_lane: string;
  source_rule_count: number;
}

export interface PersonaMapSummary {
  config_path: string;
  note_output: {
    folder: string;
    titlePrefix: string;
    defaultLookbackDays: number;
    defaultLimitPerAccount: number;
  };
  accounts: PersonaMapAccount[];
  domains: string[];
}

export interface PersonaAnchor {
  personaId: string;
  persona: string;
  account: string;
  role: string;
  defaultLane: string;
  primaryReplyFrom: boolean;
  catchAll: boolean;
  sourceRuleCount: number;
}

export interface MeetingIntelHint {
  account: string;
  label: string;
  lane: string;
  matches: string[];
}

export interface CorpusBootstrapSnapshot {
  capturedAt: string;
  overview: CorpusOverview;
  canonicalProfile: CanonicalProfile;
  sourceRegistry: CorpusSourceRecord[];
  mailIntelligenceConfig: MailIntelligenceConfig;
  personaMap: PersonaMapSummary;
  personas: PersonaAnchor[];
  vocabularyAnchors: string[];
  meetingIntelHints: MeetingIntelHint[];
}

interface ToolCaller {
  callTool(name: string, args?: Record<string, unknown>): Promise<McpToolResult>;
}

function requireParsedResult<T>(label: string, result: McpToolResult): T {
  const parsed = parseToolResult<T>(result);
  if (parsed !== null) {
    return parsed;
  }

  const raw = extractText(result);
  throw new Error(`[CorpusBootstrap] Failed to parse ${label}. Raw result: ${raw || "<empty>"}`);
}

export async function loadCorpusOverview(session: ToolCaller): Promise<CorpusOverview> {
  return requireParsedResult<CorpusOverview>("knowledge-corpus:get_corpus_overview", await session.callTool("get_corpus_overview"));
}

export async function loadCanonicalProfile(session: ToolCaller): Promise<CanonicalProfile> {
  return requireParsedResult<CanonicalProfile>(
    "knowledge-corpus:get_corpus_section(canonical_profile)",
    await session.callTool("get_corpus_section", { section: "canonical_profile" }),
  );
}

export async function loadSourceRegistry(session: ToolCaller): Promise<CorpusSourceRecord[]> {
  return requireParsedResult<CorpusSourceRecord[]>("knowledge-corpus:list_sources", await session.callTool("list_sources"));
}

export async function loadMailIntelligenceConfig(session: ToolCaller): Promise<MailIntelligenceConfig> {
  return requireParsedResult<MailIntelligenceConfig>(
    "knowledge-corpus:get_mail_intelligence_config",
    await session.callTool("get_mail_intelligence_config"),
  );
}

export async function loadPersonaMap(session: ToolCaller): Promise<PersonaMapSummary> {
  return requireParsedResult<PersonaMapSummary>("mail-intelligence:get_persona_map", await session.callTool("get_persona_map"));
}

export function derivePersonaAnchors(personaMap: PersonaMapSummary): PersonaAnchor[] {
  return personaMap.accounts.map((account) => ({
    personaId: account.persona_id,
    persona: account.persona,
    account: account.account,
    role: account.role,
    defaultLane: account.default_lane,
    primaryReplyFrom: account.primary_reply_from,
    catchAll: account.catch_all,
    sourceRuleCount: account.source_rule_count,
  }));
}

export function deriveMeetingIntelHints(config: MailIntelligenceConfig): MeetingIntelHint[] {
  return config.accounts.flatMap((account) =>
    account.sourceRules
      .filter((rule) => rule.domain === "Meeting Intel")
      .map((rule) => ({
        account: account.account,
        label: rule.label,
        lane: rule.lane,
        matches: [...rule.matches],
      })),
  );
}

export function deriveVocabularyAnchors(
  overview: CorpusOverview,
  profile: CanonicalProfile,
  config: MailIntelligenceConfig,
  personaMap: PersonaMapSummary,
): string[] {
  const values = new Set<string>();

  values.add(profile.brand_name);
  values.add(profile.primary_application_layer);
  values.add(profile.primary_output_layer);

  for (const value of profile.operating_frame) {
    values.add(value);
  }

  for (const value of overview.machine_ingest_entities) {
    values.add(value);
  }

  for (const account of config.accounts) {
    values.add(account.persona);
    values.add(account.personaId);
    values.add(account.defaultLane);
    for (const rule of account.sourceRules) {
      values.add(rule.label);
      values.add(rule.domain);
      values.add(rule.lane);
    }
  }

  for (const domain of personaMap.domains) {
    values.add(domain);
  }

  return [...values].filter(Boolean).sort((left, right) => left.localeCompare(right));
}

export async function bootstrapCorpusContext(repoRoot: string, env?: Record<string, string>): Promise<CorpusBootstrapSnapshot> {
  const knowledgeCorpus = await connectToServer("knowledge-corpus", repoRoot, env);
  const mailIntelligence = await connectToServer("mail-intelligence", repoRoot, env);

  try {
    return await bootstrapCorpusContextFromSessions({
      knowledgeCorpus,
      mailIntelligence,
    });
  } finally {
    await Promise.allSettled([knowledgeCorpus.close(), mailIntelligence.close()]);
  }
}

export async function bootstrapCorpusContextFromSessions(sessions: {
  knowledgeCorpus: McpSession;
  mailIntelligence: McpSession;
}): Promise<CorpusBootstrapSnapshot> {
  const [overview, canonicalProfile, sourceRegistry, mailIntelligenceConfig, personaMap] = await Promise.all([
    loadCorpusOverview(sessions.knowledgeCorpus),
    loadCanonicalProfile(sessions.knowledgeCorpus),
    loadSourceRegistry(sessions.knowledgeCorpus),
    loadMailIntelligenceConfig(sessions.knowledgeCorpus),
    loadPersonaMap(sessions.mailIntelligence),
  ]);

  return {
    capturedAt: new Date().toISOString(),
    overview,
    canonicalProfile,
    sourceRegistry,
    mailIntelligenceConfig,
    personaMap,
    personas: derivePersonaAnchors(personaMap),
    vocabularyAnchors: deriveVocabularyAnchors(overview, canonicalProfile, mailIntelligenceConfig, personaMap),
    meetingIntelHints: deriveMeetingIntelHints(mailIntelligenceConfig),
  };
}
