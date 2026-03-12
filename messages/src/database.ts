import { DatabaseSync } from "node:sqlite";
import { homedir } from "node:os";
import { join } from "node:path";

const DB_PATH = join(homedir(), "Library", "Messages", "chat.db");

// Apple's epoch: 2001-01-01 00:00:00 UTC
// Offset from Unix epoch (1970-01-01) in seconds
const APPLE_EPOCH_OFFSET = 978307200;

// SQL expression to convert Apple nanosecond timestamps to ISO strings.
// Apple timestamps in chat.db are nanoseconds since 2001-01-01 and exceed
// Number.MAX_SAFE_INTEGER, so we must convert in SQL to avoid BigInt errors.
const DATE_SQL = (col: string) =>
  `datetime(${col} / 1000000000 + ${APPLE_EPOCH_OFFSET}, 'unixepoch')`;

/**
 * Convert an Apple Core Data timestamp (nanoseconds since 2001-01-01) to an ISO string.
 * For use with values that are already safe JavaScript numbers (e.g. in unit tests).
 * Returns null for null/zero/undefined timestamps.
 */
export function appleTimestampToISO(timestamp: number | null | undefined): string | null {
  if (timestamp == null || timestamp === 0) return null;
  const unixSeconds = timestamp / 1e9 + APPLE_EPOCH_OFFSET;
  return new Date(unixSeconds * 1000).toISOString();
}

/**
 * Extract plain text from an NSAttributedString binary blob (attributedBody column).
 *
 * The blob contains a serialized NSAttributedString. The plain text is stored
 * after a "NSString" marker followed by a length-prefixed UTF-8 string.
 * Length encoding: if the first byte after the marker is < 0x80, it's the length directly.
 * Otherwise, (byte & 0x0f) gives the number of following bytes that encode the length
 * in little-endian order.
 */
export function extractTextFromAttributedBody(blob: Buffer | Uint8Array | null | undefined): string | null {
  if (!blob || blob.length === 0) return null;

  const buf = Buffer.isBuffer(blob) ? blob : Buffer.from(blob);
  const marker = Buffer.from("NSString");
  let idx = buf.indexOf(marker);
  if (idx === -1) return null;

  // Skip past the marker and some overhead bytes
  // The pattern is: ...NSString...{type indicator byte}{length}{UTF-8 text}
  // We need to find the length-prefixed text after the marker.
  // Typically there are 5 bytes between "NSString" and the start of the length prefix:
  //   marker(8 bytes) + overhead(5 bytes) + length + text
  idx += marker.length + 5;
  if (idx >= buf.length) return null;

  const lengthByte = buf[idx];
  let textLength: number;
  let textStart: number;

  if ((lengthByte & 0x80) === 0) {
    // Simple case: length fits in one byte
    textLength = lengthByte;
    textStart = idx + 1;
  } else {
    // Extended case: low nibble tells how many bytes encode the length
    const numLengthBytes = lengthByte & 0x0f;
    textStart = idx + 1 + numLengthBytes;
    textLength = 0;
    for (let i = 0; i < numLengthBytes; i++) {
      textLength |= buf[idx + 1 + i] << (8 * i);
    }
  }

  if (textStart + textLength > buf.length) {
    // Fallback: return whatever we can
    textLength = buf.length - textStart;
  }
  if (textLength <= 0) return null;

  return buf.subarray(textStart, textStart + textLength).toString("utf-8");
}

/**
 * Get the message text, preferring the text column and falling back to attributedBody blob parsing.
 */
export function getMessageText(text: string | null, attributedBody: Buffer | Uint8Array | null): string | null {
  if (text) return text;
  return extractTextFromAttributedBody(attributedBody);
}

/**
 * Open chat.db in read-only mode and return the database handle.
 */
export function openDb(): DatabaseSync {
  return new DatabaseSync(DB_PATH, { readOnly: true });
}

export interface Chat {
  chat_id: string;
  display_name: string | null;
  last_message_date: string | null;
  last_message_text: string | null;
}

/**
 * List recent chats with last message preview.
 */
export function listChats(limit: number = 50): Chat[] {
  const db = openDb();
  try {
    const rows = db.prepare(`
      SELECT
        c.chat_identifier as chat_id,
        c.display_name,
        ${DATE_SQL("m.date")} as last_message_date,
        m.text,
        m.attributedBody
      FROM chat c
      LEFT JOIN (
        SELECT
          cmj.chat_id,
          m.date,
          m.text,
          m.attributedBody,
          ROW_NUMBER() OVER (PARTITION BY cmj.chat_id ORDER BY m.date DESC) as rn
        FROM chat_message_join cmj
        JOIN message m ON m.ROWID = cmj.message_id
      ) m ON m.chat_id = c.ROWID AND m.rn = 1
      ORDER BY m.date DESC NULLS LAST
      LIMIT ?
    `).all(limit) as Array<{
      chat_id: string;
      display_name: string | null;
      last_message_date: string | null;
      text: string | null;
      attributedBody: Buffer | null;
    }>;

    return rows.map((row) => ({
      chat_id: row.chat_id,
      display_name: row.display_name || null,
      last_message_date: row.last_message_date,
      last_message_text: getMessageText(row.text, row.attributedBody),
    }));
  } finally {
    db.close();
  }
}

export interface Message {
  rowid: number;
  text: string | null;
  is_from_me: boolean;
  date: string | null;
  sender: string | null;
  service: string | null;
}

/**
 * Get messages for a specific chat, ordered by date descending.
 * Optionally filter by date range (ISO 8601 strings like '2025-01-01' or '2025-03-15T14:00:00').
 */
export function getChatMessages(chatId: string, limit: number = 100, fromDate?: string, toDate?: string): Message[] {
  const db = openDb();
  try {
    let dateFilter = "";
    const params: (string | number)[] = [chatId];

    if (fromDate) {
      // Convert ISO date to Apple timestamp (nanoseconds since 2001-01-01)
      const fromUnix = new Date(fromDate).getTime() / 1000;
      const fromApple = (fromUnix - APPLE_EPOCH_OFFSET) * 1e9;
      dateFilter += " AND m.date >= ?";
      params.push(fromApple);
    }
    if (toDate) {
      const toUnix = new Date(toDate).getTime() / 1000;
      const toApple = (toUnix - APPLE_EPOCH_OFFSET) * 1e9;
      dateFilter += " AND m.date <= ?";
      params.push(toApple);
    }

    params.push(limit);

    const rows = db.prepare(`
      SELECT
        m.ROWID as rowid,
        m.text,
        m.attributedBody,
        m.is_from_me,
        ${DATE_SQL("m.date")} as date,
        m.service,
        h.id as sender
      FROM message m
      JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
      JOIN chat c ON c.ROWID = cmj.chat_id
      LEFT JOIN handle h ON h.ROWID = m.handle_id
      WHERE c.chat_identifier = ?${dateFilter}
      ORDER BY m.date DESC
      LIMIT ?
    `).all(...params) as Array<{
      rowid: number;
      text: string | null;
      attributedBody: Buffer | null;
      is_from_me: number;
      date: string | null;
      service: string | null;
      sender: string | null;
    }>;

    return rows.map((row) => ({
      rowid: row.rowid,
      text: getMessageText(row.text, row.attributedBody),
      is_from_me: row.is_from_me === 1,
      date: row.date,
      sender: row.sender,
      service: row.service,
    }));
  } finally {
    db.close();
  }
}

export interface SearchResult {
  rowid: number;
  text: string | null;
  is_from_me: boolean;
  date: string | null;
  sender: string | null;
  chat_id: string;
}

/**
 * Search messages by text content using LIKE.
 */
export function searchMessages(query: string, chatId?: string, limit: number = 50): SearchResult[] {
  const db = openDb();
  try {
    const likePattern = `%${query}%`;
    let sql: string;
    let params: (string | number)[];

    if (chatId) {
      sql = `
        SELECT
          m.ROWID as rowid,
          m.text,
          m.attributedBody,
          m.is_from_me,
          ${DATE_SQL("m.date")} as date,
          h.id as sender,
          c.chat_identifier as chat_id
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE c.chat_identifier = ?
          AND (m.text LIKE ? OR m.attributedBody LIKE ?)
        ORDER BY m.date DESC
        LIMIT ?
      `;
      params = [chatId, likePattern, likePattern, limit];
    } else {
      sql = `
        SELECT
          m.ROWID as rowid,
          m.text,
          m.attributedBody,
          m.is_from_me,
          ${DATE_SQL("m.date")} as date,
          h.id as sender,
          c.chat_identifier as chat_id
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        JOIN chat c ON c.ROWID = cmj.chat_id
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE m.text LIKE ? OR m.attributedBody LIKE ?
        ORDER BY m.date DESC
        LIMIT ?
      `;
      params = [likePattern, likePattern, limit];
    }

    const rows = db.prepare(sql).all(...params) as Array<{
      rowid: number;
      text: string | null;
      attributedBody: Buffer | null;
      is_from_me: number;
      date: string | null;
      sender: string | null;
      chat_id: string;
    }>;

    return rows.map((row) => ({
      rowid: row.rowid,
      text: getMessageText(row.text, row.attributedBody),
      is_from_me: row.is_from_me === 1,
      date: row.date,
      sender: row.sender,
      chat_id: row.chat_id,
    }));
  } finally {
    db.close();
  }
}

export interface Participant {
  handle_id: string;
  service: string | null;
}

export interface MessageFromHandle extends Message {
  chat_id: string;
  display_name: string | null;
  sender_handle: string | null;
}

/**
 * List handle IDs that contain any of the given substrings (for discovering handle format).
 */
export function findHandlesContaining(substrings: string[]): string[] {
  const db = openDb();
  try {
    const conditions = substrings.map(() => "h.id LIKE ?").join(" OR ");
    const params = substrings.flatMap((s) => `%${s}%`);
    const rows = db.prepare(`
      SELECT DISTINCT h.id FROM handle h
      WHERE ${conditions}
    `).all(...params) as Array<{ id: string }>;
    return rows.map((r) => r.id);
  } finally {
    db.close();
  }
}

/**
 * Get all messages where the sender handle is one of the given addresses
 * (e.g. mojosolo@mac.com, david@mojosolo.com).
 * Returns messages ordered by date ascending (oldest first) for chronological history.
 */
export function getMessagesFromHandles(handles: string[]): MessageFromHandle[] {
  if (handles.length === 0) return [];

  const db = openDb();
  try {
    const placeholders = handles.map(() => "?").join(", ");

    const rows = db.prepare(`
      SELECT
        m.ROWID as rowid,
        m.text,
        m.attributedBody,
        m.is_from_me,
        ${DATE_SQL("m.date")} as date,
        m.service,
        h.id as sender_handle,
        c.chat_identifier as chat_id,
        c.display_name
      FROM message m
      JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
      JOIN chat c ON c.ROWID = cmj.chat_id
      JOIN handle h ON h.ROWID = m.handle_id
      WHERE ${handles.map(() => "h.id = ?").join(" OR ")}
      ORDER BY m.date ASC
    `).all(...handles) as Array<{
      rowid: number;
      text: string | null;
      attributedBody: Buffer | null;
      is_from_me: number;
      date: string | null;
      service: string | null;
      sender_handle: string | null;
      chat_id: string;
      display_name: string | null;
    }>;

    return rows.map((row) => ({
        rowid: row.rowid,
        text: getMessageText(row.text, row.attributedBody),
        is_from_me: row.is_from_me === 1,
        date: row.date,
        sender: row.sender_handle,
        service: row.service,
        chat_id: row.chat_id,
        display_name: row.display_name,
        sender_handle: row.sender_handle,
      }));
  } finally {
    db.close();
  }
}

/**
 * Get participants of a chat.
 */
export function getChatParticipants(chatId: string): Participant[] {
  const db = openDb();
  try {
    const rows = db.prepare(`
      SELECT
        h.id as handle_id,
        h.service
      FROM handle h
      JOIN chat_handle_join chj ON chj.handle_id = h.ROWID
      JOIN chat c ON c.ROWID = chj.chat_id
      WHERE c.chat_identifier = ?
    `).all(chatId) as Array<{
      handle_id: string;
      service: string | null;
    }>;

    return rows;
  } finally {
    db.close();
  }
}
