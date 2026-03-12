import { loadConfig, type IntelligenceAccount, type SourceRule } from "./config.js";
import { getMessageContent, listMessagesSince } from "./mail.js";
import { upsertNote } from "./notes.js";

export interface ClassifiedMessage {
  account: string;
  mailbox: string;
  personaId: string;
  persona: string;
  role: string;
  id: number;
  subject: string;
  sender: string;
  senderName: string;
  senderEmail: string | null;
  date: string;
  isRead: boolean;
  snippet: string;
  domain: string;
  lane: string;
  sourceLabel: string | null;
  priority: "high" | "medium" | "low";
  score: number;
}

interface ScanOptions {
  lookbackDays?: number;
  limitPerAccount?: number;
  includeSnippets?: boolean;
}

interface LaneSummary {
  lane: string;
  count: number;
  high_priority: number;
  top_messages: ClassifiedMessage[];
}

interface PersonaSummary {
  account: string;
  persona: string;
  persona_id: string;
  role: string;
  total_messages: number;
  high_priority: number;
  domains: { domain: string; count: number }[];
  lanes: LaneSummary[];
}

export interface ScanSummary {
  lookback_days: number;
  limit_per_account: number;
  total_messages: number;
  personas: PersonaSummary[];
  top_signals: ClassifiedMessage[];
}

interface RawScanResult {
  scanned: Array<{ account: IntelligenceAccount; messages: ClassifiedMessage[] }>;
  allMessages: ClassifiedMessage[];
  options: Required<ScanOptions>;
}

export interface BriefResult {
  note_title: string;
  note_folder: string;
  note_status: "created" | "updated" | "not_saved";
  note_error?: string;
  summary: ScanSummary;
  html: string;
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function stripHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;/gi, "'")
    .replace(/&quot;/gi, '"');
}

function toSnippet(value: string, maxLength = 220): string {
  const normalized = normalizeWhitespace(stripHtml(value));
  if (!normalized) {
    return "";
  }
  return normalized.length <= maxLength
    ? normalized
    : `${normalized.slice(0, maxLength - 3).trim()}...`;
}

function parseSender(value: string): { name: string; email: string | null } {
  const trimmed = normalizeWhitespace(value);
  const angleMatch = trimmed.match(/^(.*?)(?:\s*<([^>]+)>)$/);
  if (angleMatch) {
    return {
      name: angleMatch[1].trim() || angleMatch[2].trim(),
      email: angleMatch[2].trim().toLowerCase(),
    };
  }

  const plainEmailMatch = trimmed.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  if (plainEmailMatch) {
    return { name: trimmed.replace(plainEmailMatch[0], "").trim() || plainEmailMatch[0], email: plainEmailMatch[0].toLowerCase() };
  }

  return { name: trimmed, email: null };
}

function includesAny(haystack: string, patterns: string[]): boolean {
  return patterns.some((pattern) => haystack.includes(pattern.toLowerCase()));
}

function findSourceRule(account: IntelligenceAccount, haystack: string): SourceRule | null {
  return account.sourceRules.find((rule) => includesAny(haystack, rule.matches)) ?? null;
}

function inferDomain(account: IntelligenceAccount, haystack: string, sourceRule: SourceRule | null): string {
  if (sourceRule) {
    return sourceRule.domain;
  }

  const config = loadConfig();
  const match = config.domains.find((domain) => includesAny(haystack, domain.matches));
  if (match) {
    return match.name;
  }

  if (account.personaId === "author") {
    return "Creative/Strategic";
  }
  if (account.personaId === "operator") {
    return "Human/Operations";
  }
  return "Machine Signals";
}

function inferLane(
  account: IntelligenceAccount,
  haystack: string,
  sourceRule: SourceRule | null,
  senderEmail: string | null
): string {
  if (sourceRule) {
    return sourceRule.lane;
  }

  const config = loadConfig();
  const senderText = `${haystack} ${senderEmail ?? ""}`;
  const automated = includesAny(senderText, config.scoring.automatedSenderKeywords) || includesAny(haystack, config.scoring.newsletterKeywords);
  const humanish = includesAny(haystack, config.scoring.humanReplyKeywords);

  if (account.personaId === "author") {
    return "creative_intake";
  }

  if (account.personaId === "operator") {
    return automated && !humanish ? "ops_signals" : "human_replies_required";
  }

  return automated ? "machine_signals" : "campaign_inbound";
}

function scoreMessage(
  account: IntelligenceAccount,
  subject: string,
  haystack: string,
  sourceRule: SourceRule | null,
  lane: string,
  isRead: boolean
): number {
  const config = loadConfig();
  let score = 0;

  if (!isRead) {
    score += 1;
  }
  if (sourceRule?.priority === "high") {
    score += 3;
  } else if (sourceRule) {
    score += 1;
  }
  if (includesAny(subject.toLowerCase(), config.scoring.urgentSubjectKeywords)) {
    score += 2;
  }
  if (account.primaryReplyFrom && lane === "human_replies_required") {
    score += 2;
  }
  if (lane === "client_work" || lane === "meeting_intel" || lane === "platform_alerts") {
    score += 2;
  }
  return score;
}

function toPriority(score: number): "high" | "medium" | "low" {
  if (score >= 6) {
    return "high";
  }
  if (score >= 3) {
    return "medium";
  }
  return "low";
}

function sortMessages(messages: ClassifiedMessage[]): ClassifiedMessage[] {
  return [...messages].sort((left, right) => right.score - left.score || left.subject.localeCompare(right.subject));
}

async function scanAccount(account: IntelligenceAccount, options: Required<ScanOptions>): Promise<ClassifiedMessage[]> {
  const summaries = await listMessagesSince(
    account.mailbox,
    account.account,
    options.lookbackDays,
    options.limitPerAccount
  );

  const results: ClassifiedMessage[] = [];

  for (const summary of summaries) {
    let snippet = "";
    if (options.includeSnippets) {
      try {
        snippet = toSnippet(await getMessageContent(account.mailbox, account.account, summary.id));
      } catch {
        snippet = "";
      }
    }

    const parsedSender = parseSender(summary.sender);
    const haystack = normalizeWhitespace(
      `${summary.subject} ${summary.sender} ${parsedSender.email ?? ""} ${snippet}`
    ).toLowerCase();
    const sourceRule = findSourceRule(account, haystack);
    const domain = inferDomain(account, haystack, sourceRule);
    const lane = inferLane(account, haystack, sourceRule, parsedSender.email);
    const score = scoreMessage(account, summary.subject, haystack, sourceRule, lane, summary.isRead);

    results.push({
      account: account.account,
      mailbox: account.mailbox,
      personaId: account.personaId,
      persona: account.persona,
      role: account.role,
      id: summary.id,
      subject: summary.subject,
      sender: summary.sender,
      senderName: parsedSender.name,
      senderEmail: parsedSender.email,
      date: summary.date,
      isRead: summary.isRead,
      snippet,
      domain,
      lane,
      sourceLabel: sourceRule?.label ?? null,
      priority: toPriority(score),
      score,
    });
  }

  return sortMessages(results);
}

function countBy<T extends string>(values: T[]): { name: T; count: number }[] {
  const counts = new Map<T, number>();
  values.forEach((value) => counts.set(value, (counts.get(value) ?? 0) + 1));
  return Array.from(counts.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((left, right) => right.count - left.count || left.name.localeCompare(right.name));
}

function summarizePersona(account: IntelligenceAccount, messages: ClassifiedMessage[]): PersonaSummary {
  const domains = countBy(messages.map((message) => message.domain)).map((item) => ({
    domain: item.name,
    count: item.count,
  }));

  const lanes = countBy(messages.map((message) => message.lane)).map((item) => {
    const laneMessages = messages.filter((message) => message.lane === item.name);
    return {
      lane: item.name,
      count: item.count,
      high_priority: laneMessages.filter((message) => message.priority === "high").length,
      top_messages: laneMessages.slice(0, 4),
    };
  });

  return {
    account: account.account,
    persona: account.persona,
    persona_id: account.personaId,
    role: account.role,
    total_messages: messages.length,
    high_priority: messages.filter((message) => message.priority === "high").length,
    domains,
    lanes,
  };
}

export async function scanPersonaInboxes(options?: ScanOptions): Promise<ScanSummary> {
  const config = loadConfig();
  const resolvedOptions: Required<ScanOptions> = {
    lookbackDays: options?.lookbackDays ?? config.notes.defaultLookbackDays,
    limitPerAccount: options?.limitPerAccount ?? config.notes.defaultLimitPerAccount,
    includeSnippets: options?.includeSnippets ?? true,
  };

  const raw = await scanAllAccounts(resolvedOptions);
  const personas = raw.scanned.map(({ account, messages }) => summarizePersona(account, messages));

  return {
    lookback_days: raw.options.lookbackDays,
    limit_per_account: raw.options.limitPerAccount,
    total_messages: raw.allMessages.length,
    personas,
    top_signals: raw.allMessages.slice(0, 8),
  };
}

async function scanAllAccounts(options: Required<ScanOptions>): Promise<RawScanResult> {
  const config = loadConfig();
  // Sequential - concurrent AppleScript calls deadlock/timeout under osascript
  const scanned: Array<{ account: IntelligenceAccount; messages: ClassifiedMessage[] }> = [];
  for (const account of config.accounts) {
    scanned.push({ account, messages: await scanAccount(account, options) });
  }
  const allMessages = sortMessages(scanned.flatMap((entry) => entry.messages));

  return {
    scanned,
    allMessages,
    options,
  };
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatSignal(message: ClassifiedMessage): string {
  const source = message.sourceLabel ?? message.senderName;
  const snippet = message.snippet ? ` - ${message.snippet}` : "";
  return `<strong>${escapeHtml(source)}</strong>: ${escapeHtml(message.subject)}${escapeHtml(snippet)}`;
}

function buildBriefHtml(summary: ScanSummary): string {
  const config = loadConfig();
  const today = new Date().toISOString().slice(0, 10);
  const personaSections = summary.personas
    .map((persona) => {
      const laneSections = persona.lanes
        .filter((lane) => lane.count > 0)
        .map((lane) => {
          const items = lane.top_messages.map((message) => `<li>${formatSignal(message)}</li>`).join("");
          return `<h3>${escapeHtml(lane.lane)}</h3><ul>${items}</ul>`;
        })
        .join("");

      const domainSummary = persona.domains
        .slice(0, 3)
        .map((domain) => `${domain.domain} (${domain.count})`)
        .join(", ");

      return `
        <h2>${escapeHtml(persona.persona)} - ${escapeHtml(persona.account)}</h2>
        <p>${escapeHtml(persona.role)}. ${escapeHtml(persona.total_messages.toString())} messages scanned, ${escapeHtml(persona.high_priority.toString())} high-priority. Top domains: ${escapeHtml(domainSummary || "none")}.</p>
        ${laneSections}
      `;
    })
    .join("");

  const tlDr = summary.top_signals
    .slice(0, 5)
    .map((message) => `<li>[${escapeHtml(message.persona)} / ${escapeHtml(message.domain)}] ${formatSignal(message)}</li>`)
    .join("");

  return `
    <h1>${escapeHtml(config.notes.titlePrefix)} - ${today}</h1>
    <p>Generated from ${escapeHtml(summary.personas.length.toString())} inbox personas and ${escapeHtml(summary.total_messages.toString())} recent messages.</p>
    <h2>TL;DR</h2>
    <ul>${tlDr}</ul>
    ${personaSections}
  `.trim();
}

const MAX_BRIEF_SNIPPETS = 8;
const MAX_BRIEF_SNIPPET_BUDGET_MS = 15_000;

/** Fetch snippets only for messages that will appear in the brief. Keeps the brief responsive when Mail body reads stall. */
async function fetchSnippetsForDisplaySet(summary: ScanSummary): Promise<void> {
  const seen = new Set<number>();
  const toFetch: ClassifiedMessage[] = [];

  for (const msg of summary.top_signals) {
    if (!seen.has(msg.id)) {
      seen.add(msg.id);
      toFetch.push(msg);
    }
  }
  for (const persona of summary.personas) {
    for (const lane of persona.lanes) {
      for (const msg of lane.top_messages) {
        if (!seen.has(msg.id)) {
          seen.add(msg.id);
          toFetch.push(msg);
        }
      }
    }
  }

  const deadline = Date.now() + MAX_BRIEF_SNIPPET_BUDGET_MS;
  for (const [index, msg] of toFetch.entries()) {
    if (index >= MAX_BRIEF_SNIPPETS || Date.now() >= deadline) {
      msg.snippet = "";
      continue;
    }

    try {
      msg.snippet = toSnippet(await getMessageContent(msg.mailbox, msg.account, msg.id));
    } catch {
      msg.snippet = "";
    }
  }
}

export async function generateDailyBrief(options?: {
  lookbackDays?: number;
  limitPerAccount?: number;
  saveToNotes?: boolean;
}): Promise<BriefResult> {
  const config = loadConfig();
  // Scan without snippets first - classification uses subject+sender; snippets are only needed for display
  const summary = await scanPersonaInboxes({
    lookbackDays: options?.lookbackDays ?? config.notes.defaultLookbackDays,
    limitPerAccount: options?.limitPerAccount ?? config.notes.defaultLimitPerAccount,
    includeSnippets: false,
  });

  await fetchSnippetsForDisplaySet(summary);

  const date = new Date().toISOString().slice(0, 10);
  const noteTitle = `${config.notes.titlePrefix} - ${date}`;
  const html = buildBriefHtml(summary);

  let noteStatus: "created" | "updated" | "not_saved" = "not_saved";
  let noteError: string | undefined;
  if (options?.saveToNotes ?? true) {
    try {
      noteStatus = await upsertNote(noteTitle, html, config.notes.folder);
    } catch (error) {
      noteError = (error as Error).message;
    }
  }

  return {
    note_title: noteTitle,
    note_folder: config.notes.folder,
    note_status: noteStatus,
    note_error: noteError,
    summary,
    html,
  };
}

export async function analyzeSignalTrends(options?: {
  windows?: number[];
  limitPerAccount?: number;
}): Promise<{
  windows: Array<{
    days: number;
    total_messages: number;
    top_domains: { domain: string; count: number }[];
    top_lanes: { lane: string; count: number }[];
    top_sources: { source: string; count: number }[];
  }>;
}> {
  const config = loadConfig();
  const windows = (options?.windows?.length ? options.windows : [30, 60, 90])
    .map((days) => Math.max(1, Math.floor(days)));

  const analyses = [];

  for (const days of windows) {
    const raw = await scanAllAccounts({
      lookbackDays: days,
      limitPerAccount: options?.limitPerAccount ?? Math.max(config.notes.defaultLimitPerAccount, 80),
      includeSnippets: false,
    });
    const summary = {
      total_messages: raw.allMessages.length,
      personas: raw.scanned.map(({ account, messages }) => summarizePersona(account, messages)),
    };
    const allMessages = raw.allMessages;

    const topDomains = countBy(
      summary.personas.flatMap((persona) =>
        persona.domains.flatMap((domain) => Array.from({ length: domain.count }, () => domain.domain))
      )
    )
      .slice(0, 5)
      .map((item) => ({ domain: item.name, count: item.count }));

    const topLanes = countBy(
      summary.personas.flatMap((persona) =>
        persona.lanes.flatMap((lane) => Array.from({ length: lane.count }, () => lane.lane))
      )
    )
      .slice(0, 5)
      .map((item) => ({ lane: item.name, count: item.count }));

    const topSources = countBy(
      allMessages.map((message) => message.sourceLabel ?? message.senderName ?? "Unknown")
    )
      .slice(0, 5)
      .map((item) => ({ source: item.name, count: item.count }));

    analyses.push({
      days,
      total_messages: summary.total_messages,
      top_domains: topDomains,
      top_lanes: topLanes,
      top_sources: topSources,
    });
  }

  return { windows: analyses };
}
