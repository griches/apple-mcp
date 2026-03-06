import { execFile } from "node:child_process";

export function sanitize(input: string): string {
  return input
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\r\n/g, "\\n")
    .replace(/\r/g, "\\n")
    .replace(/\n/g, "\\n");
}

export function runAppleScript(script: string, timeout = 120000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("osascript", ["-e", script], { maxBuffer: 10 * 1024 * 1024, timeout }, (error, stdout, stderr) => {
      if (error) {
        if ((error as any).killed) {
          reject(new Error("AppleScript timed out — the Reminders query took too long"));
          return;
        }
        reject(new Error(`AppleScript error: ${stderr || error.message}`));
        return;
      }
      resolve(stdout.trimEnd());
    });
  });
}

/**
 * Parse a date string into components, handling various formats:
 * "March 9, 2026", "9 March 2026", "Monday, 9 March 2026",
 * "2026-03-09", "March 15, 2025 at 2:00 PM", etc.
 * Returns locale-independent AppleScript to build the date from components.
 */
export function dateToAppleScript(input: string, varName: string): string {
  // Strip day names like "Monday, " or "Friday, "
  const cleaned = input.replace(/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s*/i, "");

  // Extract time if present (e.g. "at 2:00 PM" or "at 14:00")
  let hours = 0, minutes = 0;
  const timeMatch = cleaned.match(/\bat\s+(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
  if (timeMatch) {
    hours = parseInt(timeMatch[1]);
    minutes = parseInt(timeMatch[2]);
    if (timeMatch[3]?.toUpperCase() === "PM" && hours < 12) hours += 12;
    if (timeMatch[3]?.toUpperCase() === "AM" && hours === 12) hours = 0;
  }

  // Remove the time portion for date parsing
  const dateOnly = cleaned.replace(/\s*\bat\s+\d{1,2}:\d{2}\s*(AM|PM)?/i, "").trim();

  // Try to parse with Date constructor
  const parsed = new Date(dateOnly);
  if (isNaN(parsed.getTime())) {
    throw new Error(`Invalid date: "${input}"`);
  }

  const year = parsed.getFullYear();
  const month = parsed.getMonth() + 1; // 1-indexed
  const day = parsed.getDate();

  const months = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];

  return `set ${varName} to current date
set year of ${varName} to ${year}
set month of ${varName} to ${months[month - 1]}
set day of ${varName} to ${day}
set hours of ${varName} to ${hours}
set minutes of ${varName} to ${minutes}
set seconds of ${varName} to 0`;
}

const FIELD_DELIM = "|||";
const RECORD_DELIM = "<<<>>>";

export async function listLists(): Promise<{ name: string; id: string }[]> {
  const script = `
tell application "Reminders"
  set props to properties of every list
  if (count of props) is 0 then return ""
  set listInfo to {}
  repeat with p in props
    set end of listInfo to (name of p) & "${FIELD_DELIM}" & (id of p)
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return listInfo as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [name, id] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { name, id };
  });
}

export async function createList(name: string): Promise<string> {
  const safeName = sanitize(name);
  const script = `
tell application "Reminders"
  make new list with properties {name:"${safeName}"}
  return "List created: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function listReminders(
  listName: string,
  includeCompleted?: boolean
): Promise<{ name: string; id: string; completed: boolean; dueDate: string | null; priority: number }[]> {
  const safeList = sanitize(listName);
  const filter = includeCompleted ? "" : " whose completed is false";
  const script = `
tell application "Reminders"
  set theList to list "${safeList}"
  set props to properties of (every reminder of theList${filter})
  if (count of props) is 0 then return ""
  set reminderList to {}
  repeat with p in props
    set rDueDate to ""
    try
      set rDueDate to (due date of p) as text
    end try
    set end of reminderList to (name of p) & "${FIELD_DELIM}" & (id of p) & "${FIELD_DELIM}" & ((completed of p) as text) & "${FIELD_DELIM}" & rDueDate & "${FIELD_DELIM}" & ((priority of p) as text)
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return reminderList as text
end tell`;
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [name, id, completed, dueDate, priority] = record.split(FIELD_DELIM).map((s) => s.trim());
    return {
      name,
      id,
      completed: completed === "true",
      dueDate: dueDate || null,
      priority: parseInt(priority, 10) || 0,
    };
  });
}

export async function getReminder(name: string, listName?: string): Promise<{
  name: string;
  id: string;
  completed: boolean;
  dueDate: string | null;
  body: string | null;
  priority: number;
  list: string;
}> {
  const safeName = sanitize(name);
  let scope: string;
  if (listName) {
    const safeList = sanitize(listName);
    scope = `reminders of list "${safeList}"`;
  } else {
    scope = "every reminder";
  }
  const script = `
tell application "Reminders"
  set matchedReminders to (${scope} whose name is "${safeName}")
  if (count of matchedReminders) is 0 then
    error "Reminder not found: ${safeName}"
  end if
  set r to item 1 of matchedReminders
  set rName to name of r
  set rId to id of r
  set rCompleted to completed of r
  set rPriority to priority of r
  set rBody to ""
  try
    set rBody to body of r
  end try
  set rDueDate to ""
  try
    set rDueDate to due date of r as text
  end try
  set rList to name of container of r
  return rName & "${RECORD_DELIM}" & rId & "${RECORD_DELIM}" & (rCompleted as text) & "${RECORD_DELIM}" & rDueDate & "${RECORD_DELIM}" & rBody & "${RECORD_DELIM}" & (rPriority as text) & "${RECORD_DELIM}" & rList
end tell`;
  const raw = await runAppleScript(script);
  const parts = raw.split(RECORD_DELIM);
  return {
    name: parts[0]?.trim() || "",
    id: parts[1]?.trim() || "",
    completed: parts[2]?.trim() === "true",
    dueDate: parts[3]?.trim() || null,
    body: parts[4]?.trim() || null,
    priority: parseInt(parts[5]?.trim() || "0", 10),
    list: parts[6]?.trim() || "",
  };
}

export async function createReminder(
  name: string,
  listName: string,
  options?: { body?: string; dueDate?: string; priority?: number }
): Promise<string> {
  const safeName = sanitize(name);
  const safeList = sanitize(listName);
  let props = `{name:"${safeName}"`;
  if (options?.body) props += `, body:"${sanitize(options.body)}"`;
  if (options?.priority !== undefined) props += `, priority:${options.priority}`;
  props += "}";

  let dateSetup = "";
  if (options?.dueDate) {
    const dateScript = dateToAppleScript(options.dueDate, "dueD");
    dateSetup = `\n  ${dateScript}\n  set due date of newReminder to dueD`;
  }

  const script = `
tell application "Reminders"
  set theList to list "${safeList}"
  set newReminder to make new reminder at end of reminders of theList with properties ${props}${dateSetup}
  return "Reminder created: ${safeName} in ${safeList}"
end tell`;
  return runAppleScript(script);
}

export async function completeReminder(name: string, listName?: string): Promise<string> {
  const safeName = sanitize(name);
  let scope: string;
  if (listName) {
    const safeList = sanitize(listName);
    scope = `reminders of list "${safeList}"`;
  } else {
    scope = "every reminder";
  }
  const script = `
tell application "Reminders"
  set matchedReminders to (${scope} whose name is "${safeName}")
  if (count of matchedReminders) is 0 then
    error "Reminder not found: ${safeName}"
  end if
  set r to item 1 of matchedReminders
  set completed of r to true
  return "Reminder completed: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function updateReminder(
  name: string,
  listName: string | undefined,
  updates: { newName?: string; body?: string; dueDate?: string; priority?: number }
): Promise<string> {
  const safeName = sanitize(name);
  let scope: string;
  if (listName) {
    const safeList = sanitize(listName);
    scope = `reminders of list "${safeList}"`;
  } else {
    scope = "every reminder";
  }
  let setStatements = "";
  if (updates.newName) setStatements += `\n  set name of r to "${sanitize(updates.newName)}"`;
  if (updates.body) setStatements += `\n  set body of r to "${sanitize(updates.body)}"`;
  if (updates.priority !== undefined) setStatements += `\n  set priority of r to ${updates.priority}`;

  let dateSetup = "";
  if (updates.dueDate) {
    const dateScript = dateToAppleScript(updates.dueDate, "dueD");
    dateSetup = `\n  ${dateScript}\n  set due date of r to dueD`;
  }

  const script = `
tell application "Reminders"
  set matchedReminders to (${scope} whose name is "${safeName}")
  if (count of matchedReminders) is 0 then
    error "Reminder not found: ${safeName}"
  end if
  set r to item 1 of matchedReminders${setStatements}${dateSetup}
  return "Reminder updated: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function uncompleteReminder(name: string, listName?: string): Promise<string> {
  const safeName = sanitize(name);
  let scope: string;
  if (listName) {
    const safeList = sanitize(listName);
    scope = `reminders of list "${safeList}"`;
  } else {
    scope = "every reminder";
  }
  const script = `
tell application "Reminders"
  set matchedReminders to (${scope} whose name is "${safeName}")
  if (count of matchedReminders) is 0 then
    error "Reminder not found: ${safeName}"
  end if
  set r to item 1 of matchedReminders
  set completed of r to false
  return "Reminder uncompleted: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function deleteList(name: string): Promise<string> {
  const safeName = sanitize(name);
  const script = `
tell application "Reminders"
  set matchedLists to (every list whose name is "${safeName}")
  if (count of matchedLists) is 0 then
    error "List not found: ${safeName}"
  end if
  delete item 1 of matchedLists
  return "List deleted: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function deleteReminder(name: string, listName?: string): Promise<string> {
  const safeName = sanitize(name);
  let scope: string;
  if (listName) {
    const safeList = sanitize(listName);
    scope = `reminders of list "${safeList}"`;
  } else {
    scope = "every reminder";
  }
  const script = `
tell application "Reminders"
  set matchedReminders to (${scope} whose name is "${safeName}")
  if (count of matchedReminders) is 0 then
    error "Reminder not found: ${safeName}"
  end if
  delete item 1 of matchedReminders
  return "Reminder deleted: ${safeName}"
end tell`;
  return runAppleScript(script);
}

export async function searchReminders(query: string, listName?: string): Promise<{ name: string; id: string; list: string; completed: boolean }[]> {
  const safeQuery = sanitize(query);
  let script: string;
  if (listName) {
    const safeList = sanitize(listName);
    script = `
tell application "Reminders"
  set props to properties of (reminders of list "${safeList}" whose name contains "${safeQuery}")
  if (count of props) is 0 then return ""
  set results to {}
  repeat with p in props
    set end of results to (name of p) & "${FIELD_DELIM}" & (id of p) & "${FIELD_DELIM}" & "${safeList}" & "${FIELD_DELIM}" & ((completed of p) as text)
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  } else {
    script = `
tell application "Reminders"
  set results to {}
  set listProps to properties of every list
  repeat with lp in listProps
    set lName to name of lp
    set matchedReminders to (reminders of list (id of lp) whose name contains "${safeQuery}")
    set reminderCount to count of matchedReminders
    if reminderCount > 0 then
      set props to properties of matchedReminders
      repeat with p in props
        set end of results to (name of p) & "${FIELD_DELIM}" & (id of p) & "${FIELD_DELIM}" & lName & "${FIELD_DELIM}" & ((completed of p) as text)
      end repeat
    end if
  end repeat
  set AppleScript's text item delimiters to "${RECORD_DELIM}"
  return results as text
end tell`;
  }
  const raw = await runAppleScript(script);
  if (!raw) return [];
  return raw.split(RECORD_DELIM).map((record) => {
    const [name, id, list, completed] = record.split(FIELD_DELIM).map((s) => s.trim());
    return { name, id, list, completed: completed === "true" };
  });
}
