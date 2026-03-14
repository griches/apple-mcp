import { extractText, parseToolResult, type McpSession, type McpToolResult } from "../mcp/client.js";
import { connectToServer } from "../mcp/localServers.js";

export interface NotesFolder {
  name: string;
}

export interface NotesListItem {
  title: string;
  id: string;
  creationDate: string;
  modificationDate: string;
}

export interface NotesDetail {
  title: string;
  id: string;
  body: string;
  creationDate: string;
  modificationDate: string;
}

export interface HarvestedNote {
  folder: string;
  title: string;
  id: string;
  creationDate: string;
  modificationDate: string;
  body: string;
}

export interface SkippedNote {
  folder: string;
  title: string;
  reason: string;
}

export interface NotesHarvestResult {
  capturedAt: string;
  requestedFolders: string[] | null;
  discoveredFolders: string[];
  harvestedNotes: HarvestedNote[];
  skippedNotes: SkippedNote[];
  errors: string[];
}

export interface HarvestNotesOptions {
  folders?: string[];
  limitPerFolder?: number;
  env?: Record<string, string>;
}

interface ToolCaller {
  callTool(name: string, args?: Record<string, unknown>): Promise<McpToolResult>;
}

function requireParsedResult<T>(label: string, result: McpToolResult): T {
  const parsed = parseToolResult<T>(result);
  if (parsed !== null) {
    return parsed;
  }

  throw new Error(`[NotesSource] Failed to parse ${label}. Raw result: ${extractText(result) || "<empty>"}`);
}

export async function listFolders(session: ToolCaller): Promise<NotesFolder[]> {
  return requireParsedResult<NotesFolder[]>("apple-notes:list_folders", await session.callTool("list_folders"));
}

export async function listNotesInFolder(session: ToolCaller, folder: string): Promise<NotesListItem[]> {
  return requireParsedResult<NotesListItem[]>(
    `apple-notes:list_notes(${folder})`,
    await session.callTool("list_notes", { folder }),
  );
}

export async function getNote(session: ToolCaller, title: string, folder: string): Promise<NotesDetail> {
  return requireParsedResult<NotesDetail>(
    `apple-notes:get_note(${folder}/${title})`,
    await session.callTool("get_note", { title, folder }),
  );
}

function uniqueFolderNames(folders: NotesFolder[]): string[] {
  return [...new Set(folders.map((folder) => folder.name).filter(Boolean))].sort((left, right) => left.localeCompare(right));
}

function selectFolders(discoveredFolders: string[], requestedFolders?: string[]): string[] {
  if (!requestedFolders || requestedFolders.length === 0) {
    return discoveredFolders;
  }

  const requested = new Set(requestedFolders);
  return discoveredFolders.filter((folder) => requested.has(folder));
}

function groupByTitle(items: NotesListItem[]): Map<string, NotesListItem[]> {
  const grouped = new Map<string, NotesListItem[]>();
  for (const item of items) {
    const bucket = grouped.get(item.title) ?? [];
    bucket.push(item);
    grouped.set(item.title, bucket);
  }
  return grouped;
}

export async function harvestNotesFromSession(
  session: McpSession,
  options: Omit<HarvestNotesOptions, "env"> = {},
): Promise<NotesHarvestResult> {
  const limitPerFolder = options.limitPerFolder ?? 3;
  const errors: string[] = [];
  const skippedNotes: SkippedNote[] = [];
  const harvestedNotes: HarvestedNote[] = [];

  const discoveredFolders = uniqueFolderNames(await listFolders(session));
  const targetFolders = selectFolders(discoveredFolders, options.folders);

  for (const folder of targetFolders) {
    try {
      const listed = await listNotesInFolder(session, folder);
      const grouped = groupByTitle(listed);
      const candidates = listed.slice(0, limitPerFolder);

      for (const item of candidates) {
        const sameTitle = grouped.get(item.title) ?? [];
        if (sameTitle.length > 1) {
          skippedNotes.push({
            folder,
            title: item.title,
            reason: "duplicate_title_in_folder",
          });
          continue;
        }

        try {
          const detail = await getNote(session, item.title, folder);
          harvestedNotes.push({
            folder,
            title: detail.title,
            id: detail.id,
            creationDate: detail.creationDate,
            modificationDate: detail.modificationDate,
            body: detail.body,
          });
        } catch (error) {
          errors.push(`[NotesSource] Failed to fetch note ${folder}/${item.title}: ${(error as Error).message}`);
        }
      }
    } catch (error) {
      errors.push(`[NotesSource] Failed to list notes in folder ${folder}: ${(error as Error).message}`);
    }
  }

  return {
    capturedAt: new Date().toISOString(),
    requestedFolders: options.folders ?? null,
    discoveredFolders,
    harvestedNotes,
    skippedNotes,
    errors,
  };
}

export async function harvestNotes(repoRoot: string, options: HarvestNotesOptions = {}): Promise<NotesHarvestResult> {
  const session = await connectToServer("apple-notes", repoRoot, options.env);
  try {
    return await harvestNotesFromSession(session, options);
  } finally {
    await session.close();
  }
}
