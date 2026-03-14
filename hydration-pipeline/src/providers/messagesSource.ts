import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parseToolResult, type McpSession, type McpToolResult } from "../mcp/client.js";
import { connectToServer } from "../mcp/localServers.js";

export type MessagesHarvestMode = "live" | "export";

export interface ExportedChatMessage {
  date: string;
  from_me: boolean;
  sender: string | null;
  text: string;
}

export interface ExportedChat {
  chat_id: string;
  display_name: string | null;
  messages: ExportedChatMessage[];
}

export interface MessagesExportFile {
  exported_at: string;
  handles: string[];
  total_messages: number;
  chats: ExportedChat[];
}

export interface LiveChatSummary {
  chat_id: string;
  display_name: string | null;
  last_message_date: string | null;
  last_message_text: string | null;
}

export interface LiveChatMessage {
  rowid: number;
  text: string | null;
  is_from_me: boolean;
  date: string | null;
  sender: string | null;
  service: string | null;
}

export interface HarvestedChatMessage {
  messageId: string;
  date: string;
  fromMe: boolean;
  sender: string | null;
  text: string;
  service: string | null;
  chatId: string;
  displayName: string | null;
}

export interface HarvestedChat {
  chatId: string;
  displayName: string | null;
  messages: HarvestedChatMessage[];
}

export interface MessagesHarvestResult {
  capturedAt: string;
  sourceMode: MessagesHarvestMode;
  targetChatIds: string[];
  exportPath: string | null;
  chats: HarvestedChat[];
  errors: string[];
}

export interface HarvestMessagesOptions {
  sourceMode?: MessagesHarvestMode;
  exportPath?: string;
  targetChatIds?: string[];
  limitPerChat?: number;
  env?: Record<string, string>;
}

interface ToolCaller {
  callTool(name: string, args?: Record<string, unknown>): Promise<McpToolResult>;
}

const DEFAULT_TARGET_CHAT_IDS = ["mojosolo@mac.com", "david@mojosolo.com"];

function requireParsedResult<T>(label: string, result: McpToolResult): T {
  const parsed = parseToolResult<T>(result);
  if (parsed !== null) {
    return parsed;
  }

  throw new Error(`[MessagesSource] Failed to parse ${label}.`);
}

export function defaultMessagesExportPath(repoRoot: string): string {
  return join(repoRoot, "messages", "messages-export.json");
}

export function loadMessagesExport(exportPath: string): MessagesExportFile {
  return JSON.parse(readFileSync(exportPath, "utf8")) as MessagesExportFile;
}

export async function listChats(session: ToolCaller, limit = 50): Promise<LiveChatSummary[]> {
  return requireParsedResult<LiveChatSummary[]>("apple-messages:list_chats", await session.callTool("list_chats", { limit }));
}

export async function getChatMessages(session: ToolCaller, chatId: string, limit = 100): Promise<LiveChatMessage[]> {
  return requireParsedResult<LiveChatMessage[]>(
    `apple-messages:get_chat_messages(${chatId})`,
    await session.callTool("get_chat_messages", { chat_id: chatId, limit }),
  );
}

export function harvestMessagesFromExportFile(
  file: MessagesExportFile,
  options: Pick<HarvestMessagesOptions, "targetChatIds" | "limitPerChat"> = {},
): MessagesHarvestResult {
  const targetChatIds = options.targetChatIds ?? file.handles ?? DEFAULT_TARGET_CHAT_IDS;
  const limitPerChat = options.limitPerChat ?? 100;

  const chats = file.chats
    .filter((chat) => targetChatIds.includes(chat.chat_id))
    .map((chat) => ({
      chatId: chat.chat_id,
      displayName: chat.display_name,
      messages: chat.messages.slice(0, limitPerChat).map((message, index) => ({
        messageId: `${chat.chat_id}:${index}:${message.date}`,
        date: message.date,
        fromMe: message.from_me,
        sender: message.sender,
        text: message.text,
        service: null,
        chatId: chat.chat_id,
        displayName: chat.display_name,
      })),
    } satisfies HarvestedChat));

  return {
    capturedAt: new Date().toISOString(),
    sourceMode: "export",
    targetChatIds,
    exportPath: null,
    chats,
    errors: [],
  };
}

export async function harvestMessagesFromSession(
  session: McpSession,
  options: Pick<HarvestMessagesOptions, "targetChatIds" | "limitPerChat"> = {},
): Promise<MessagesHarvestResult> {
  const targetChatIds = options.targetChatIds ?? DEFAULT_TARGET_CHAT_IDS;
  const limitPerChat = options.limitPerChat ?? 100;
  const errors: string[] = [];
  const chatIndex = new Map((await listChats(session, 200)).map((chat) => [chat.chat_id, chat]));
  const chats: HarvestedChat[] = [];

  for (const chatId of targetChatIds) {
    try {
      const summary = chatIndex.get(chatId) ?? null;
      const messages = await getChatMessages(session, chatId, limitPerChat);
      chats.push({
        chatId,
        displayName: summary?.display_name ?? null,
        messages: messages.map((message) => ({
          messageId: String(message.rowid),
          date: message.date ?? "unknown",
          fromMe: message.is_from_me,
          sender: message.sender,
          text: message.text ?? "",
          service: message.service,
          chatId,
          displayName: summary?.display_name ?? null,
        })),
      });
    } catch (error) {
      errors.push(`[MessagesSource] Failed to harvest chat ${chatId}: ${(error as Error).message}`);
    }
  }

  return {
    capturedAt: new Date().toISOString(),
    sourceMode: "live",
    targetChatIds,
    exportPath: null,
    chats,
    errors,
  };
}

export async function harvestMessages(repoRoot: string, options: HarvestMessagesOptions = {}): Promise<MessagesHarvestResult> {
  const sourceMode = options.sourceMode ?? "export";
  const targetChatIds = options.targetChatIds ?? DEFAULT_TARGET_CHAT_IDS;
  const limitPerChat = options.limitPerChat ?? 100;

  if (sourceMode === "export") {
    const exportPath = options.exportPath ?? defaultMessagesExportPath(repoRoot);
    const result = harvestMessagesFromExportFile(loadMessagesExport(exportPath), { targetChatIds, limitPerChat });
    return { ...result, exportPath };
  }

  const session = await connectToServer("apple-messages", repoRoot, options.env);
  try {
    return await harvestMessagesFromSession(session, { targetChatIds, limitPerChat });
  } finally {
    await session.close();
  }
}
