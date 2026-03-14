import type { HarvestedChatMessage, MessagesHarvestResult } from "../providers/messagesSource.js";

export interface MessageSignalDocument {
  id: string;
  sourceType: "message";
  sourceId: string;
  channel: string;
  authoredBy: "david" | "external" | "mixed" | "unknown";
  personaHint: "author" | "operator" | "machine" | "unknown";
  timestamp: string;
  rawDate: string;
  participants: string[];
  text: string;
  tags: string[];
  chatId: string;
  displayName: string | null;
  sender: string | null;
  service: string | null;
  fromMe: boolean;
  provenance: {
    collector: string;
    directness: "direct" | "quoted" | "third_party" | "inferred";
    freshness: string;
  };
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

function parseTimestamp(rawDate: string): string {
  const parsed = Date.parse(rawDate);
  return Number.isNaN(parsed) ? rawDate : new Date(parsed).toISOString();
}

function normalizeWhitespace(value: string): string {
  return value.replace(/\r/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function derivePersonaHint(chatId: string): "author" | "operator" | "machine" | "unknown" {
  const normalized = chatId.toLowerCase();
  if (normalized.includes("mojosolo@mac.com")) {
    return "author";
  }
  if (normalized.includes("david@mojosolo.com")) {
    return "operator";
  }
  return "unknown";
}

function classifyAuthoredBy(message: HarvestedChatMessage): "david" | "external" | "mixed" | "unknown" {
  return message.fromMe ? "david" : "external";
}

function deriveTags(message: HarvestedChatMessage, personaHint: string): string[] {
  return unique([
    "messages",
    `chat:${message.chatId}`,
    `persona:${personaHint}`,
    `direction:${message.fromMe ? "outbound" : "inbound"}`,
    ...(message.service ? [`service:${message.service}`] : []),
  ]).sort((left, right) => left.localeCompare(right));
}

export function normalizeHarvestedMessage(message: HarvestedChatMessage): MessageSignalDocument {
  const personaHint = derivePersonaHint(message.chatId);
  return {
    id: `message:${message.chatId}:${message.messageId}`,
    sourceType: "message",
    sourceId: message.messageId,
    channel: `messages:${personaHint}`,
    authoredBy: classifyAuthoredBy(message),
    personaHint,
    timestamp: parseTimestamp(message.date),
    rawDate: message.date,
    participants: unique([message.chatId, message.sender ?? ""]),
    text: normalizeWhitespace(message.text),
    tags: deriveTags(message, personaHint),
    chatId: message.chatId,
    displayName: message.displayName,
    sender: message.sender,
    service: message.service,
    fromMe: message.fromMe,
    provenance: {
      collector: "hydration-pipeline/messagesSource",
      directness: message.fromMe ? "direct" : "third_party",
      freshness: new Date().toISOString(),
    },
  };
}

export function normalizeMessagesHarvest(result: MessagesHarvestResult): MessageSignalDocument[] {
  return result.chats.flatMap((chat) => chat.messages.map(normalizeHarvestedMessage));
}

export function selectDavidFirstPersonMessages(documents: MessageSignalDocument[]): MessageSignalDocument[] {
  return documents.filter((document) => document.authoredBy === "david");
}
