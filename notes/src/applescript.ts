import { execFile } from "node:child_process";

/**
 * Escape a string for safe embedding inside an AppleScript double-quoted string.
 * Handles backslashes, double quotes, and other characters that AppleScript
 * interprets specially.
 */
export function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

/**
 * Execute an AppleScript string via osascript and return stdout.
 */
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

// ---------------------------------------------------------------------------
// AppleScript template functions
// ---------------------------------------------------------------------------

const FIELD_DELIM = "|||";
const RECORD_DELIM = "<<<>>>";

export async function listFolders(): Promise<{ name: string }[]> {
  const script = `
tell application "Notes"
  set folderList to {}
  repeat with f in folders
    set end of folderList to name of f
  end repeat
  set AppleScript's text item delimiters to "${FIELD_DELIM}"
  return folderList as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(FIELD_DELIM).map((name) => ({ name: name.trim() }));
}

export async function createFolder(name: string): Promise<string> {
  const safeName = sanitize(name);
  const script = `
tell application "Notes"
  make new folder with properties {name:"${safeName}"}
  return "Folder created: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function deleteFolder(name: string): Promise<string> {
  const safeName = sanitize(name);
  const script = `
tell application "Notes"
  set targetFolder to first folder whose name is "${safeName}"
  delete targetFolder
  return "Folder deleted: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function listNotes(folder: string): Promise<{ title: string; id: string; creationDate: string; modificationDate: string }[]> {
  const safeFolder = sanitize(folder);
  const script = `
tell application "Notes"
  set noteList to {}
  set theFolder to folder "${safeFolder}"
  repeat with n in notes of theFolder
    set noteId to id of n
    set noteTitle to name of n
    set noteCreated to creation date of n as text
    set noteModified to modification date of n as text
    set end of noteList to noteTitle & "${FIELD_DELIM}" & noteId & "${FIELD_DELIM}" & noteCreated & "${FIELD_DELIM}" & noteModified
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return noteList as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [title, id, creationDate, modificationDate] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { title, id, creationDate, modificationDate };
  });
}

export async function getNote(title: string, folder?: string): Promise<{ title: string; id: string; body: string; creationDate: string; modificationDate: string }> {
  const safeTitle = sanitize(title);
  let scope: string;
  if (folder) {
    const safeFolder = sanitize(folder);
    scope = `notes of folder "${safeFolder}"`;
  } else {
    scope = "every note";
  }
  const script = `
tell application "Notes"
  set matchedNotes to (${scope} whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle}"
  end if
  set n to item 1 of matchedNotes
  set noteTitle to name of n
  set noteId to id of n
  set noteBody to body of n
  set noteCreated to creation date of n as text
  set noteModified to modification date of n as text
  return noteTitle & "${FIELD_DELIM}" & noteId & "${FIELD_DELIM}" & noteBody & "${FIELD_DELIM}" & noteCreated & "${FIELD_DELIM}" & noteModified
end tell`;
  const raw = await runAppleScript(script);
  const [noteTitle, id, body, creationDate, modificationDate] = raw.split(FIELD_DELIM);
  return { title: noteTitle, id, body, creationDate, modificationDate };
}

export async function createNote(title: string, body: string, folder: string): Promise<string> {
  const safeTitle = sanitize(title);
  const safeBody = sanitize(body);
  const safeFolder = sanitize(folder);
  const script = `
tell application "Notes"
  set theFolder to folder "${safeFolder}"
  make new note at theFolder with properties {name:"${safeTitle}", body:"${safeBody}"}
  return "Note created: ${safeTitle} in ${safeFolder}"
end tell`;
  return runAppleScript(script);
}

/**
 * Apple Notes derives a note's NAME from the first line of its BODY, so
 * `set body of n to <content>` does not merely replace content -- it silently
 * RENAMES the note whenever the new body does not lead with the existing title.
 *
 * createNote is unaffected: it sets `name` explicitly alongside `body`.
 * updateNote sets only `body`, so a caller that sends new content without
 * repeating the title as the first line loses the title. Observed against a
 * note called "Grocery List" whose name was replaced by whatever text happened
 * to lead the updated body.
 *
 * tests/applescript.test.ts already documents the coupling -- its fixtures keep
 * the title in an <h1> "to preserve it after updates" -- but that only protects
 * callers who remember to do it. This moves the guarantee into updateNote.
 *
 * Prepending the title when it is absent keeps name and body consistent the way
 * Notes itself models them. Setting `name` after the body would instead let the
 * name and the visible first line diverge.
 *
 * Exported because it is pure, so it can be unit-tested without touching a real
 * Notes database.
 */
export function bodyPreservingTitle(title: string, body: string): string {
  const leadingText = body.replace(/<[^>]*>/g, "").trimStart();
  if (leadingText.startsWith(title.trim())) {
    return body;
  }
  return `<h1>${title}</h1>${body}`;
}

export async function updateNote(title: string, body: string, folder?: string): Promise<string> {
  const safeTitle = sanitize(title);
  const safeBody = sanitize(bodyPreservingTitle(title, body));
  let scope: string;
  if (folder) {
    const safeFolder = sanitize(folder);
    scope = `notes of folder "${safeFolder}"`;
  } else {
    scope = "every note";
  }
  const script = `
tell application "Notes"
  set matchedNotes to (${scope} whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle}"
  end if
  set n to item 1 of matchedNotes
  set body of n to "${safeBody}"
  return "Note updated: ${safeTitle}"
end tell`;
  return runAppleScript(script);
}

export async function deleteNote(title: string, folder?: string): Promise<string> {
  const safeTitle = sanitize(title);
  let scope: string;
  if (folder) {
    const safeFolder = sanitize(folder);
    scope = `notes of folder "${safeFolder}"`;
  } else {
    scope = "every note";
  }
  const script = `
tell application "Notes"
  set matchedNotes to (${scope} whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle}"
  end if
  delete item 1 of matchedNotes
  return "Note deleted: ${safeTitle}"
end tell`;
  return runAppleScript(script);
}

export async function moveNote(title: string, fromFolder: string, toFolder: string): Promise<string> {
  const safeTitle = sanitize(title);
  const safeFrom = sanitize(fromFolder);
  const safeTo = sanitize(toFolder);
  const script = `
tell application "Notes"
  set matchedNotes to (notes of folder "${safeFrom}" whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle} in folder ${safeFrom}"
  end if
  set n to item 1 of matchedNotes
  move n to folder "${safeTo}"
  return "Note moved: ${safeTitle} from ${safeFrom} to ${safeTo}"
end tell`;
  return runAppleScript(script);
}

export async function appendToNote(title: string, content: string, folder?: string): Promise<string> {
  const safeTitle = sanitize(title);
  const safeContent = sanitize(content);
  let scope: string;
  if (folder) {
    const safeFolder = sanitize(folder);
    scope = `notes of folder "${safeFolder}"`;
  } else {
    scope = "every note";
  }
  const script = `
tell application "Notes"
  set matchedNotes to (${scope} whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle}"
  end if
  set n to item 1 of matchedNotes
  set body of n to (body of n) & "${safeContent}"
  return "Content appended to note: ${safeTitle}"
end tell`;
  return runAppleScript(script);
}

export async function searchNotes(query: string, folder?: string): Promise<{ title: string; folder: string; id: string }[]> {
  const safeQuery = sanitize(query);
  let script: string;
  if (folder) {
    const safeFolder = sanitize(folder);
    script = `
tell application "Notes"
  set results to {}
  set matchedNotes to (notes of folder "${safeFolder}" whose name contains "${safeQuery}" or body contains "${safeQuery}")
  repeat with n in matchedNotes
    set noteTitle to name of n
    set noteId to id of n
    set end of results to noteTitle & "${FIELD_DELIM}" & noteId & "${FIELD_DELIM}" & "${safeFolder}"
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  } else {
    script = `
tell application "Notes"
  set results to {}
  repeat with f in folders
    set folderName to name of f
    set matchedNotes to (notes of f whose name contains "${safeQuery}" or body contains "${safeQuery}")
    repeat with n in matchedNotes
      set noteTitle to name of n
      set noteId to id of n
      set end of results to noteTitle & "${FIELD_DELIM}" & noteId & "${FIELD_DELIM}" & folderName
    end repeat
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  }
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [title, id, folderName] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { title, id, folder: folderName };
  });
}
