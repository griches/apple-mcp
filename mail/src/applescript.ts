import { execFile } from "node:child_process";

export function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

export function runAppleScript(script: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("osascript", ["-e", script], { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`AppleScript error: ${stderr || error.message}`));
        return;
      }
      resolve(stdout.trimEnd());
    });
  });
}

const FIELD_DELIM = "|||";
const RECORD_DELIM = "<<<>>>";

export async function listMailboxes(): Promise<{ name: string; account: string; unreadCount: number }[]> {
  const script = `
tell application "Mail"
  set mbList to {}
  repeat with acct in accounts
    set acctName to name of acct
    repeat with mb in mailboxes of acct
      set mbName to name of mb
      set mbUnread to unread count of mb
      set end of mbList to mbName & "${FIELD_DELIM}" & acctName & "${FIELD_DELIM}" & (mbUnread as text)
    end repeat
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return mbList as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [name, account, unreadCount] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { name, account, unreadCount: parseInt(unreadCount, 10) || 0 };
  });
}

export async function listMessages(
  mailboxName: string,
  accountName: string,
  limit?: number
): Promise<{ id: number; subject: string; sender: string; date: string; isRead: boolean }[]> {
  const safeMb = sanitize(mailboxName);
  const safeAcct = sanitize(accountName);
  const maxMessages = limit || 25;
  const script = `
tell application "Mail"
  set mb to mailbox "${safeMb}" of account "${safeAcct}"
  set msgList to {}
  set msgCount to count of messages of mb
  set maxCount to ${maxMessages}
  if msgCount < maxCount then set maxCount to msgCount
  repeat with i from 1 to maxCount
    set m to message i of mb
    set mId to id of m
    set mSubject to subject of m
    set mSender to sender of m
    set mDate to date sent of m as text
    set mRead to read status of m
    set end of msgList to (mId as text) & "${FIELD_DELIM}" & mSubject & "${FIELD_DELIM}" & mSender & "${FIELD_DELIM}" & mDate & "${FIELD_DELIM}" & (mRead as text)
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return msgList as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [id, subject, sender, date, isRead] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { id: parseInt(id, 10), subject, sender, date, isRead: isRead === "true" };
  });
}

export async function getMessage(
  mailboxName: string,
  accountName: string,
  messageId: number
): Promise<{
  id: number;
  subject: string;
  sender: string;
  date: string;
  isRead: boolean;
  content: string;
  toRecipients: string[];
  ccRecipients: string[];
}> {
  const safeMb = sanitize(mailboxName);
  const safeAcct = sanitize(accountName);
  const script = `
tell application "Mail"
  set mb to mailbox "${safeMb}" of account "${safeAcct}"
  set matchedMsgs to (every message of mb whose id is ${messageId})
  if (count of matchedMsgs) is 0 then
    error "Message not found with id: ${messageId}"
  end if
  set m to item 1 of matchedMsgs
  set mId to id of m
  set mSubject to subject of m
  set mSender to sender of m
  set mDate to date sent of m as text
  set mRead to read status of m
  set mContent to content of m

  set toList to {}
  repeat with r in to recipients of m
    set end of toList to address of r
  end repeat
  set AppleScript's text item delimiters to ","
  set toString to toList as text

  set ccList to {}
  repeat with r in cc recipients of m
    set end of ccList to address of r
  end repeat
  set ccString to ccList as text

  return (mId as text) & "${RECORD_DELIM}" & mSubject & "${RECORD_DELIM}" & mSender & "${RECORD_DELIM}" & mDate & "${RECORD_DELIM}" & (mRead as text) & "${RECORD_DELIM}" & mContent & "${RECORD_DELIM}" & toString & "${RECORD_DELIM}" & ccString
end tell`;
  const raw = await runAppleScript(script);
  const parts = raw.split(RECORD_DELIM);
  return {
    id: parseInt(parts[0]?.trim() || "0", 10),
    subject: parts[1]?.trim() || "",
    sender: parts[2]?.trim() || "",
    date: parts[3]?.trim() || "",
    isRead: parts[4]?.trim() === "true",
    content: parts[5] || "",
    toRecipients: parts[6] ? parts[6].split(",").map((s) => s.trim()).filter(Boolean) : [],
    ccRecipients: parts[7] ? parts[7].split(",").map((s) => s.trim()).filter(Boolean) : [],
  };
}

export async function searchMessages(
  query: string,
  mailboxName?: string,
  accountName?: string,
  limit?: number
): Promise<{ id: number; subject: string; sender: string; date: string; mailbox: string; account: string }[]> {
  const safeQuery = sanitize(query);
  const maxResults = limit || 25;

  let script: string;
  if (mailboxName && accountName) {
    const safeMb = sanitize(mailboxName);
    const safeAcct = sanitize(accountName);
    script = `
tell application "Mail"
  set results to {}
  set mb to mailbox "${safeMb}" of account "${safeAcct}"
  set matchedMsgs to (every message of mb whose subject contains "${safeQuery}")
  set maxCount to ${maxResults}
  set msgCount to count of matchedMsgs
  if msgCount < maxCount then set maxCount to msgCount
  repeat with i from 1 to maxCount
    set m to item i of matchedMsgs
    set mId to id of m
    set mSubject to subject of m
    set mSender to sender of m
    set mDate to date sent of m as text
    set end of results to (mId as text) & "${FIELD_DELIM}" & mSubject & "${FIELD_DELIM}" & mSender & "${FIELD_DELIM}" & mDate & "${FIELD_DELIM}" & "${safeMb}" & "${FIELD_DELIM}" & "${safeAcct}"
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  } else {
    script = `
tell application "Mail"
  set results to {}
  set resultCount to 0
  repeat with acct in accounts
    set acctName to name of acct
    repeat with mb in mailboxes of acct
      set mbName to name of mb
      set matchedMsgs to (every message of mb whose subject contains "${safeQuery}")
      repeat with m in matchedMsgs
        if resultCount >= ${maxResults} then exit repeat
        set mId to id of m
        set mSubject to subject of m
        set mSender to sender of m
        set mDate to date sent of m as text
        set end of results to (mId as text) & "${FIELD_DELIM}" & mSubject & "${FIELD_DELIM}" & mSender & "${FIELD_DELIM}" & mDate & "${FIELD_DELIM}" & mbName & "${FIELD_DELIM}" & acctName
        set resultCount to resultCount + 1
      end repeat
      if resultCount >= ${maxResults} then exit repeat
    end repeat
    if resultCount >= ${maxResults} then exit repeat
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  }
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [id, subject, sender, date, mailbox, account] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { id: parseInt(id, 10), subject, sender, date, mailbox, account };
  });
}

export async function sendEmail(
  to: string,
  subject: string,
  body: string,
  options?: { cc?: string; bcc?: string; from?: string }
): Promise<string> {
  const safeTo = sanitize(to);
  const safeSubject = sanitize(subject);
  const safeBody = sanitize(body);

  let recipientBlock = `make new to recipient at end of to recipients with properties {address:"${safeTo}"}`;
  if (options?.cc) {
    const safeCc = sanitize(options.cc);
    recipientBlock += `\n    make new cc recipient at end of cc recipients with properties {address:"${safeCc}"}`;
  }
  if (options?.bcc) {
    const safeBcc = sanitize(options.bcc);
    recipientBlock += `\n    make new bcc recipient at end of bcc recipients with properties {address:"${safeBcc}"}`;
  }

  let accountPart = "";
  if (options?.from) {
    const safeFrom = sanitize(options.from);
    accountPart = ` of account "${safeFrom}"`;
  }

  const script = `
tell application "Mail"
  set newMessage to make new outgoing message${accountPart} with properties {subject:"${safeSubject}", content:"${safeBody}", visible:false}
  tell newMessage
    ${recipientBlock}
  end tell
  send newMessage
  return "Email sent to ${safeTo}: ${safeSubject}"
end tell`;
  return runAppleScript(script);
}

export async function getUnreadCount(mailboxName?: string, accountName?: string): Promise<number> {
  let script: string;
  if (mailboxName && accountName) {
    const safeMb = sanitize(mailboxName);
    const safeAcct = sanitize(accountName);
    script = `
tell application "Mail"
  return unread count of mailbox "${safeMb}" of account "${safeAcct}"
end tell`;
  } else {
    script = `
tell application "Mail"
  set totalUnread to 0
  repeat with acct in accounts
    repeat with mb in mailboxes of acct
      set totalUnread to totalUnread + (unread count of mb)
    end repeat
  end repeat
  return totalUnread
end tell`;
  }
  const raw = await runAppleScript(script);
  return parseInt(raw, 10) || 0;
}

export async function moveMessage(
  messageId: number,
  fromMailbox: string,
  fromAccount: string,
  toMailbox: string,
  toAccount?: string
): Promise<string> {
  const safeFromMb = sanitize(fromMailbox);
  const safeFromAcct = sanitize(fromAccount);
  const safeToMb = sanitize(toMailbox);
  const safeToAcct = sanitize(toAccount || fromAccount);
  const script = `
tell application "Mail"
  set sourceMb to mailbox "${safeFromMb}" of account "${safeFromAcct}"
  set destMb to mailbox "${safeToMb}" of account "${safeToAcct}"
  set matchedMsgs to (every message of sourceMb whose id is ${messageId})
  if (count of matchedMsgs) is 0 then
    error "Message not found with id: ${messageId}"
  end if
  set m to item 1 of matchedMsgs
  move m to destMb
  return "Message moved to ${safeToMb}"
end tell`;
  return runAppleScript(script);
}
