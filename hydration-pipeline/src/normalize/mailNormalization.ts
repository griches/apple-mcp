import type { HarvestedMailMessage, MailHarvestResult } from "../providers/mailSource.js";

export interface MailSignalDocument {
  id: string;
  sourceType: "mail";
  sourceId: string;
  channel: string;
  authoredBy: "david" | "external" | "mixed" | "unknown";
  personaHint: "author" | "operator" | "machine" | "unknown";
  timestamp: string;
  rawDate: string;
  title: string;
  participants: string[];
  text: string;
  tags: string[];
  mailbox: string;
  account: string;
  configuredAccount: string;
  direction: "inbound" | "outbound";
  sender: string;
  toRecipients: string[];
  ccRecipients: string[];
  matchedRuleLabels: string[];
  matchedDomains: string[];
  matchedLanes: string[];
  provenance: {
    collector: string;
    directness: "direct" | "quoted" | "third_party" | "inferred";
    freshness: string;
  };
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\r/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function parseTimestamp(rawDate: string): string {
  const parsed = Date.parse(rawDate);
  return Number.isNaN(parsed) ? rawDate : new Date(parsed).toISOString();
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

function extractEmail(text: string): string | null {
  const match = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  return match ? match[0].toLowerCase() : null;
}

function classifyAuthoredBy(message: HarvestedMailMessage): "david" | "external" | "mixed" | "unknown" {
  if (message.direction === "inbound") {
    return "external";
  }

  if (message.catchAll) {
    return "mixed";
  }

  if (message.primaryReplyFrom || message.personaId === "author" || message.personaId === "operator") {
    return "david";
  }

  return "unknown";
}

function buildParticipants(message: HarvestedMailMessage): string[] {
  const senderEmail = extractEmail(message.sender);
  return unique([
    message.sender,
    ...(senderEmail ? [senderEmail] : []),
    ...message.toRecipients,
    ...message.ccRecipients,
    ...message.accountEmails,
  ]);
}

function deriveTags(message: HarvestedMailMessage): string[] {
  return unique([
    "mail",
    `persona:${message.personaId}`,
    `lane:${message.defaultLane}`,
    `direction:${message.direction}`,
    `mailbox:${message.mailbox}`,
    `account:${message.actualAccountName}`,
    ...message.matchedRules.map((rule) => `rule:${rule.label}`),
    ...message.matchedRules.map((rule) => `domain:${rule.domain}`),
    ...message.matchedRules.map((rule) => `matched_lane:${rule.lane}`),
  ]).sort((left, right) => left.localeCompare(right));
}

export function normalizeMailMessage(message: HarvestedMailMessage): MailSignalDocument {
  const text = normalizeWhitespace(message.content || message.subject);
  const personaHint = ["author", "operator", "machine"].includes(message.personaId)
    ? (message.personaId as "author" | "operator" | "machine")
    : "unknown";

  return {
    id: `mail:${message.actualAccountName}:${message.mailbox}:${message.id}`,
    sourceType: "mail",
    sourceId: String(message.id),
    channel: `mail:${message.personaId}:${message.direction}`,
    authoredBy: classifyAuthoredBy(message),
    personaHint,
    timestamp: parseTimestamp(message.date),
    rawDate: message.date,
    title: message.subject,
    participants: buildParticipants(message),
    text,
    tags: deriveTags(message),
    mailbox: message.mailbox,
    account: message.actualAccountName,
    configuredAccount: message.configuredAccount,
    direction: message.direction,
    sender: message.sender,
    toRecipients: [...message.toRecipients],
    ccRecipients: [...message.ccRecipients],
    matchedRuleLabels: unique(message.matchedRules.map((rule) => rule.label)),
    matchedDomains: unique(message.matchedRules.map((rule) => rule.domain)),
    matchedLanes: unique(message.matchedRules.map((rule) => rule.lane)),
    provenance: {
      collector: "hydration-pipeline/mailSource",
      directness: message.direction === "outbound" ? "direct" : "third_party",
      freshness: new Date().toISOString(),
    },
  };
}

export function normalizeMailHarvest(result: MailHarvestResult): MailSignalDocument[] {
  return result.accounts.flatMap((account) =>
    [...account.inboxMessages, ...account.sentMessages].map(normalizeMailMessage),
  );
}

export function selectDavidFirstPersonMail(documents: MailSignalDocument[]): MailSignalDocument[] {
  return documents.filter((document) => document.authoredBy === "david");
}
