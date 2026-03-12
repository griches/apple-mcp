import { execFile } from "node:child_process";

const FIELD_DELIM = "|||";
const RECORD_DELIM = "<<<>>>";

export interface MailAccount {
  name: string;
  emails: string[];
}

export interface MailMessageSummary {
  id: number;
  subject: string;
  sender: string;
  date: string;
  isRead: boolean;
}

export function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

function runAppleScript(script: string): Promise<string> {
  return runAppleScriptWithTimeout(script);
}

function runAppleScriptWithTimeout(script: string, timeoutMs = 30_000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(
      "osascript",
      ["-e", script],
      { maxBuffer: 10 * 1024 * 1024, timeout: timeoutMs },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`AppleScript error: ${stderr || error.message}`));
          return;
        }
        resolve(stdout.trimEnd());
      }
    );
  });
}

let _accountsCache: MailAccount[] | null = null;

export async function listAccounts(): Promise<MailAccount[]> {
  if (_accountsCache) return _accountsCache;
  const script = `
tell application "Mail"
  set results to {}
  repeat with acct in accounts
    set acctName to name of acct
    set AppleScript's text item delimiters to ","
    set emailList to (email addresses of acct) as text
    set end of results to acctName & "${FIELD_DELIM}" & emailList
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;

  const raw = await runAppleScript(script);
  if (!raw) {
    return [];
  }

  _accountsCache = raw.split(RECORD_DELIM).map((record) => {
    const [name, emails] = record.split(FIELD_DELIM).map((value) => value.trim());
    return {
      name,
      emails: emails ? emails.split(",").map((value) => value.trim()).filter(Boolean) : [],
    };
  });
  return _accountsCache;
}

async function resolveAccountName(accountIdentifier: string): Promise<string> {
  const accounts = await listAccounts();
  const normalized = accountIdentifier.toLowerCase();

  const exactName = accounts.find((account) => account.name.toLowerCase() === normalized);
  if (exactName) {
    return exactName.name;
  }

  const exactEmail = accounts.find((account) =>
    account.emails.some((email) => email.toLowerCase() === normalized)
  );
  if (exactEmail) {
    return exactEmail.name;
  }

  const partialEmail = accounts.find((account) =>
    account.emails.some((email) => email.toLowerCase().includes(normalized))
  );
  if (partialEmail) {
    return partialEmail.name;
  }

  const available = accounts.map((account) => `${account.name} [${account.emails.join(", ")}]`);
  throw new Error(
    `Mail account "${accountIdentifier}" not found. Available accounts: ${available.join("; ")}`
  );
}

export async function listMessagesSince(
  mailboxName: string,
  accountName: string,
  lookbackDays: number,
  limit: number
): Promise<MailMessageSummary[]> {
  const safeMailbox = sanitize(mailboxName);
  const resolvedAccountName = await resolveAccountName(accountName);
  const safeAccount = sanitize(resolvedAccountName);
  const safeDays = Math.max(1, Math.floor(lookbackDays));
  const safeLimit = Math.max(1, Math.floor(limit));
  const sampleSize = Math.min(Math.max(safeLimit, safeLimit * Math.min(safeDays, 10)), 250);

  // Indexed access avoids building a message range, which is much slower on large Mailboxes.
  const script = `
tell application "Mail"
  set mb to mailbox "${safeMailbox}" of account "${safeAccount}"
  set results to {}
  repeat with i from 1 to ${sampleSize}
    try
      set m to message i of mb
      set end of results to (id of m as text) & "${FIELD_DELIM}" & (subject of m) & "${FIELD_DELIM}" & (sender of m) & "${FIELD_DELIM}" & (date sent of m as text) & "${FIELD_DELIM}" & (read status of m as text)
    on error
      exit repeat
    end try
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;

  const raw = await runAppleScriptWithTimeout(script, 180_000);
  if (!raw) {
    return [];
  }

  const cutoff = Date.now() - safeDays * 24 * 60 * 60 * 1000;
  const messages = raw.split(RECORD_DELIM).map((record) => {
    const [id, subject, sender, date, isRead] = record.split(FIELD_DELIM).map((value) => value.trim());
    return {
      id: parseInt(id, 10),
      subject,
      sender,
      date,
      isRead: isRead === "true",
    };
  });

  return messages
    .filter((message) => {
      const parsed = Date.parse(message.date);
      return Number.isNaN(parsed) ? true : parsed >= cutoff;
    })
    .slice(0, safeLimit);
}

export async function getMessageContent(
  mailboxName: string,
  accountName: string,
  messageId: number
): Promise<string> {
  const safeMailbox = sanitize(mailboxName);
  const resolvedAccountName = await resolveAccountName(accountName);
  const safeAccount = sanitize(resolvedAccountName);
  const script = `
tell application "Mail"
  set mb to mailbox "${safeMailbox}" of account "${safeAccount}"
  set matchedMsgs to (every message of mb whose id is ${messageId})
  if (count of matchedMsgs) is 0 then
    error "Message not found with id: ${messageId}"
  end if
  set m to item 1 of matchedMsgs
  return content of m
end tell`;

  return runAppleScriptWithTimeout(script, 4_000);
}
