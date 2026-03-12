import { execFile } from "node:child_process";

const FIELD_DELIM = "|||";

function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

function runAppleScript(script: string, timeoutMs = 20_000): Promise<string> {
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

export async function listFolders(): Promise<string[]> {
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
  return raw ? raw.split(FIELD_DELIM).map((item) => item.trim()).filter(Boolean) : [];
}

export async function createFolder(name: string): Promise<void> {
  const safeName = sanitize(name);
  await runAppleScript(`
tell application "Notes"
  make new folder with properties {name:"${safeName}"}
end tell`);
}

export async function ensureFolder(name: string): Promise<void> {
  const safeName = sanitize(name);
  await runAppleScript(`
tell application "Notes"
  try
    folder "${safeName}"
  on error
    make new folder with properties {name:"${safeName}"}
  end try
end tell`);
}

export async function createNote(title: string, body: string, folder: string): Promise<void> {
  const safeTitle = sanitize(title);
  const safeBody = sanitize(body);
  const safeFolder = sanitize(folder);
  await runAppleScript(`
tell application "Notes"
  set theFolder to folder "${safeFolder}"
  make new note at theFolder with properties {name:"${safeTitle}", body:"${safeBody}"}
end tell`);
}

export async function updateNote(title: string, body: string, folder: string): Promise<void> {
  const safeTitle = sanitize(title);
  const safeBody = sanitize(body);
  const safeFolder = sanitize(folder);
  await runAppleScript(`
tell application "Notes"
  set matchedNotes to (notes of folder "${safeFolder}" whose name is "${safeTitle}")
  if (count of matchedNotes) is 0 then
    error "Note not found: ${safeTitle}"
  end if
  set body of item 1 of matchedNotes to "${safeBody}"
end tell`);
}

export async function upsertNote(title: string, body: string, folder: string): Promise<"created" | "updated"> {
  await ensureFolder(folder);
  try {
    await updateNote(title, body, folder);
    return "updated";
  } catch {
    await createNote(title, body, folder);
    return "created";
  }
}
