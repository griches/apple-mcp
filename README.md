# MCP Servers

A collection of [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers, primarily for native Apple applications on macOS, plus a canonical knowledge-brain server and a mail-intelligence layer built on top of it.

## Servers

| Server | Status | Description |
|--------|--------|-------------|
| [Apple Notes](#apple-notes) | Done | Read, create, update, move, and delete notes and folders |
| [Apple Messages](#apple-messages) | Done | Read message history, search conversations, and send messages |
| [Apple Contacts](#apple-contacts) | Done | Manage contacts, groups, and contact details |
| [Apple Mail](#apple-mail) | Done | Read, send, search, flag, and manage email |
| [Apple Reminders](#apple-reminders) | Done | Create, update, complete, and manage reminders and lists |
| [Apple Calendar](#apple-calendar) | Done | Create, update, and manage calendar events |
| [Apple Maps](#apple-maps) | Done | Search locations, get directions, and drop pins (visual only — limited by Apple's automation support) |
| [Knowledge Corpus](#knowledge-corpus) | Done | Query the canonical MojoSolo operating brain and export a Laravel projection |
| [Apple Mail Intelligence](#apple-mail-intelligence) | Done | Read three configured inbox personas from the canonical brain, classify signals, and write a Daily Intel brief to Apple Notes |

## Requirements

- **Node.js** 18+ (22+ for Apple Messages)
- **Apple app servers only:** macOS, Full Disk Access for Messages, and the associated Apple app running
- **Knowledge Corpus only:** no macOS dependency; it reads bundled or configured local corpus files

## Safety Modes

Apple app servers (except Apple Maps, which is UI-only) support two optional safety flags:

| Mode | Flag | Behaviour |
|------|------|-----------|
| **Normal** (default) | _(none)_ | All tools available, no restrictions |
| **Read-only** | `--read-only` | Destructive/write tools are not registered at all |
| **Confirm** | `--confirm-destructive` | Destructive tools require a `confirm: true` parameter; without it they return a warning asking the AI to check with the user first |

### Claude Desktop

```json
{
  "mcpServers": {
    "apple-notes": {
      "command": "npx",
      "args": ["@griches/apple-notes-mcp", "--read-only"]
    },
    "apple-messages": {
      "command": "npx",
      "args": ["@griches/apple-messages-mcp", "--confirm-destructive"]
    }
  }
}
```

### Claude Code

```bash
claude mcp add apple-notes -- npx @griches/apple-notes-mcp --read-only
claude mcp add apple-messages -- npx @griches/apple-messages-mcp --confirm-destructive
```

### Destructive tools by server

| Server | Destructive tools |
|--------|-------------------|
| Notes | `delete_note`, `delete_folder` |
| Contacts | `delete_contact`, `delete_group` |
| Reminders | `delete_reminder`, `delete_list` |
| Calendar | `delete_event` |

## Quick Start

No cloning or building required — install and run directly with `npx`:

```bash
# Apple Notes
npx @griches/apple-notes-mcp

# Apple Messages
npx @griches/apple-messages-mcp

# Apple Contacts
npx @griches/apple-contacts-mcp

# Apple Reminders
npx @griches/apple-reminders-mcp

# Apple Calendar
npx @griches/apple-calendar-mcp

# Apple Maps
npx @griches/apple-maps-mcp

# Apple Mail
npx @griches/apple-mail-mcp
```

### Claude Code

```bash
claude mcp add apple-notes -- npx @griches/apple-notes-mcp
claude mcp add apple-messages -- npx @griches/apple-messages-mcp
claude mcp add apple-contacts -- npx @griches/apple-contacts-mcp
claude mcp add apple-reminders -- npx @griches/apple-reminders-mcp
claude mcp add apple-calendar -- npx @griches/apple-calendar-mcp
claude mcp add apple-maps -- npx @griches/apple-maps-mcp
claude mcp add apple-mail -- npx @griches/apple-mail-mcp
```

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-notes": {
      "command": "npx",
      "args": ["@griches/apple-notes-mcp"]
    },
    "apple-messages": {
      "command": "npx",
      "args": ["@griches/apple-messages-mcp"]
    },
    "apple-contacts": {
      "command": "npx",
      "args": ["@griches/apple-contacts-mcp"]
    },
    "apple-reminders": {
      "command": "npx",
      "args": ["@griches/apple-reminders-mcp"]
    },
    "apple-calendar": {
      "command": "npx",
      "args": ["@griches/apple-calendar-mcp"]
    },
    "apple-maps": {
      "command": "npx",
      "args": ["@griches/apple-maps-mcp"]
    },
    "apple-mail": {
      "command": "npx",
      "args": ["@griches/apple-mail-mcp"]
    }
  }
}
```

## Install from Source

If you prefer to build from source:

```bash
git clone https://github.com/griches/apple-mcp.git
cd apple-mcp

# Apple Notes
cd notes && npm install && npm run build

# Apple Messages
cd ../messages && npm install && npm run build

# Apple Contacts
cd ../contacts && npm install && npm run build

# Apple Reminders
cd ../reminders && npm install && npm run build

# Apple Calendar
cd ../calendar && npm install && npm run build

# Apple Maps
cd ../maps && npm install && npm run build

# Apple Mail
cd ../mail && npm install && npm run build

# Knowledge Corpus
cd ../knowledge-corpus && npm install && npm run build

# Apple Mail Intelligence
cd ../mail-intelligence && npm install && npm run build
```

Then configure your MCP client to run the built files directly:

```json
{
  "mcpServers": {
    "apple-notes": {
      "command": "node",
      "args": ["/absolute/path/to/notes/build/index.js"]
    },
    "apple-messages": {
      "command": "node",
      "args": ["/absolute/path/to/messages/build/index.js"]
    },
    "apple-contacts": {
      "command": "node",
      "args": ["/absolute/path/to/contacts/build/index.js"]
    },
    "apple-reminders": {
      "command": "node",
      "args": ["/absolute/path/to/reminders/build/index.js"]
    },
    "apple-calendar": {
      "command": "node",
      "args": ["/absolute/path/to/calendar/build/index.js"]
    },
    "apple-maps": {
      "command": "node",
      "args": ["/absolute/path/to/maps/build/index.js"]
    },
    "apple-mail": {
      "command": "node",
      "args": ["/absolute/path/to/mail/build/index.js"]
    },
    "knowledge-corpus": {
      "command": "node",
      "args": ["/absolute/path/to/knowledge-corpus/build/index.js"]
    },
    "apple-mail-intelligence": {
      "command": "node",
      "args": ["/absolute/path/to/mail-intelligence/build/index.js"]
    }
  }
}
```

---

## Apple Notes

An MCP server that interacts with Apple Notes via AppleScript.

### Tools

| Tool | Description |
|------|-------------|
| `list_folders` | List all folders in Apple Notes |
| `create_folder` | Create a new folder |
| `list_notes` | List all notes in a folder |
| `get_note` | Get the full content of a note by title |
| `create_note` | Create a new note (HTML body) in a folder |
| `update_note` | Update the body of an existing note |
| `move_note` | Move a note from one folder to another |
| `append_to_note` | Append HTML content to an existing note |
| `delete_note` | Delete a note |
| `delete_folder` | Delete a folder and all its notes |
| `search_notes` | Search notes by keyword in titles and body content |

### Usage Examples

- "List my Apple Notes folders"
- "Get my Shopping note"
- "Create a note called Meeting Notes in my Work folder"
- "Search my notes for recipes"

---

## Apple Messages

An MCP server that reads messages from the macOS Messages database (SQLite) and sends messages via AppleScript.

### Tools

| Tool | Description |
|------|-------------|
| `list_chats` | List recent chats with last message preview |
| `get_chat_messages` | Get message history for a specific chat (with optional date range filtering) |
| `search_messages` | Search messages by text content |
| `send_message` | Send an iMessage or SMS |
| `get_chat_participants` | Get participants of a chat |

### Permissions

- **Reading messages**: Requires Full Disk Access for your terminal app to read `~/Library/Messages/chat.db`
- **Sending messages**: macOS will prompt you to allow your terminal app to control the Messages app via AppleScript

### Usage Examples

- "Show my recent messages"
- "Search my messages for flight confirmation"
- "Send a message to +1234567890 saying I'm on my way"

---

## Apple Contacts

An MCP server that interacts with Apple Contacts via AppleScript.

### Tools

| Tool | Description |
|------|-------------|
| `list_groups` | List all groups in Apple Contacts |
| `list_contacts` | List all contacts, optionally filtered by group |
| `get_contact` | Get full details of a contact (emails, phones, addresses, etc.) |
| `search_contacts` | Search contacts by name |
| `create_contact` | Create a new contact with optional email, phone, organization |
| `update_contact` | Update an existing contact's details |
| `delete_contact` | Delete a contact by name |
| `create_group` | Create a new group |
| `delete_group` | Delete a contact group |
| `add_contact_to_group` | Add a contact to a group |
| `remove_contact_from_group` | Remove a contact from a group |

### Usage Examples

- "List all my contacts"
- "Find contacts named John"
- "Get details for Jane Smith"
- "Create a contact for Bob Jones at Acme Corp"

---

## Apple Reminders

An MCP server that interacts with Apple Reminders via AppleScript.

### Tools

| Tool | Description |
|------|-------------|
| `list_lists` | List all reminder lists |
| `create_list` | Create a new reminder list |
| `list_reminders` | List reminders in a list (optionally include completed) |
| `get_reminder` | Get full details of a reminder by name |
| `create_reminder` | Create a new reminder with optional due date, notes, and priority |
| `update_reminder` | Update an existing reminder's details |
| `complete_reminder` | Mark a reminder as completed |
| `uncomplete_reminder` | Mark a completed reminder as incomplete |
| `delete_reminder` | Delete a reminder |
| `delete_list` | Delete a reminder list and all its reminders |
| `search_reminders` | Search reminders by name across lists |

### Usage Examples

- "Show my reminder lists"
- "List reminders in my Shopping list"
- "Create a reminder to buy milk in my Groceries list"
- "Mark the dentist appointment reminder as done"

---

## Apple Calendar

An MCP server that interacts with Apple Calendar. Read operations use a compiled Swift EventKit binary for fast access (~0.1s vs 50-140s via AppleScript). Write operations use AppleScript.

### Permissions

- **Calendar access**: macOS will prompt you to grant calendar access the first time a read operation is used (System Settings > Privacy & Security > Calendars)
- **Creating/deleting events**: macOS will prompt you to allow your terminal app to control the Calendar app via AppleScript

### Tools

| Tool | Description |
|------|-------------|
| `list_calendars` | List all calendars |
| `list_all_events` | List events across all calendars within a date range |
| `list_events` | List events in a specific calendar within a date range |
| `get_event` | Get full details of an event by summary/title |
| `create_event` | Create a new event with date, time, location, and description |
| `update_event` | Update an existing event's details |
| `delete_event` | Delete an event by summary/title |
| `search_events` | Search events by summary/title across calendars |

### Usage Examples

- "List my calendars"
- "Show events in my Work calendar for next week"
- "Create a meeting tomorrow at 2pm in my Work calendar"
- "Search for events about standup"

---

## Apple Maps

An MCP server that interacts with Apple Maps using Maps URL schemes.

> **Note:** Apple Maps has a very limited AppleScript/automation dictionary compared to other Apple apps. There is no supported way to programmatically read back search results, route details, or location data from Maps. As a result, these tools open Apple Maps with the requested query but cannot return structured data (e.g. addresses, coordinates, distances) to the agent. The results are visual — you'll see them in the Maps app.

### Tools

| Tool | Description |
|------|-------------|
| `search_location` | Search for a location in Apple Maps |
| `get_directions` | Get directions between two locations (driving, walking, or transit) |
| `drop_pin` | Drop a pin at specific coordinates |
| `open_address` | Open a specific address in Apple Maps |
| `save_to_favorites` | Open a location in Maps so you can save it as a favorite |

### Usage Examples

- "Search for coffee shops near Times Square"
- "Get walking directions from Central Park to the Met"
- "Show me 1 Apple Park Way, Cupertino on a map"
- "Drop a pin at 48.8584, 2.2945"

---

## Apple Mail

An MCP server that interacts with Apple Mail via AppleScript.

### Tools

| Tool | Description |
|------|-------------|
| `list_mailboxes` | List all mailboxes across accounts with unread counts |
| `list_messages` | List recent messages in a mailbox |
| `get_message` | Get the full content of an email by ID |
| `search_messages` | Search emails by subject or sender across mailboxes |
| `send_email` | Send an email with optional CC/BCC (supports multiple recipients) |
| `get_unread_count` | Get unread count for a mailbox or all mailboxes |
| `move_message` | Move an email to a different mailbox |
| `mark_read` | Mark an email as read or unread |
| `delete_message` | Delete an email (moves to trash) |
| `flag_message` | Flag or unflag an email message |

### Usage Examples

- "How many unread emails do I have?"
- "Show my recent emails in INBOX"
- "Search my email for invoices"
- "Send an email to bob@example.com about the meeting"

---

## Knowledge Corpus

An MCP server that serves the canonical MojoSolo operating brain plus a companion markdown report and a Laravel export layer.

### Tools

| Tool | Description |
|------|-------------|
| `get_corpus_overview` | Return corpus metadata, available sections, source counts, and report availability |
| `list_corpus_sections` | List the top-level structured corpus sections |
| `get_corpus_section` | Return a full top-level section by name |
| `get_mail_intelligence_config` | Return the embedded mail-intelligence config used by the live sensor layer |
| `search_corpus` | Search the structured corpus, the report, or both |
| `get_laravel_brain_blueprint` | Return Laravel tables, routes, and seed data derived from the brain |
| `export_laravel_brain_pack` | Write a Laravel integration pack to a target directory |
| `list_sources` | List all source registry entries |
| `get_source` | Return one source registry entry by id |
| `list_report_sections` | List available markdown report sections |
| `get_report_section` | Return one markdown report section by title or slug |

### Usage Examples

- "Show me the persona_architecture section"
- "Show me the mail-intelligence config"
- "Give me the Laravel brain blueprint"
- "Export the Laravel brain pack into my app"

---

## Apple Mail Intelligence

An MCP server that treats `mojosolo@mac.com`, `david@mojosolo.com`, and `info@mojosolo.com` as distinct personas, loads its rules from the canonical brain, classifies their signals, and generates a Notes-first Daily Intel brief.

### Tools

| Tool | Description |
|------|-------------|
| `get_persona_map` | Return the configured persona/account map and note output settings |
| `scan_persona_inboxes` | Scan recent mail and classify messages by persona, domain, lane, and priority |
| `analyze_signal_trends` | Compare cumulative signal distributions across windows such as 30/60/90 days |
| `generate_daily_brief` | Build the Daily Intel brief and optionally save it to Apple Notes |

If Apple Notes automation stalls on the local machine, `generate_daily_brief` still returns the brief content and reports the Notes problem through `note_status` and `note_error`.

### Usage Examples

- "Show me the persona map"
- "Scan the last day of inbox intelligence"
- "Compare signals over 30, 60, and 90 days"
- "Generate today's Daily Intel and save it to Notes"

---

## Development

Each server is a standalone TypeScript project in its own directory.

```bash
# Run tests for Notes
cd notes
npm test

# Run tests for Messages
cd messages
npm test
```

## License

MIT
