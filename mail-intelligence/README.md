# Apple Mail Intelligence MCP Server

An MCP server for the three-persona inbox architecture:

- `mojosolo@mac.com` -> The Author
- `david@mojosolo.com` -> The Operator
- `info@mojosolo.com` -> The Machine

It reads configured Apple Mail accounts, classifies signals into domains and lanes, and generates a Notes-first "Daily Intel" brief.

## Tools

| Tool | Description |
|------|-------------|
| `discover_mail_accounts` | List Apple Mail account object names and email addresses present on the machine |
| `get_persona_map` | Return the configured persona/account map and output settings |
| `scan_persona_inboxes` | Scan recent mail and classify messages by persona, domain, lane, and priority |
| `analyze_signal_trends` | Compare cumulative signal distributions across windows such as 30/60/90 days |
| `generate_daily_brief` | Build the Daily Intel brief and optionally save it to Apple Notes |

If Apple Notes automation is unavailable or slow on the local machine, `generate_daily_brief` still returns the brief HTML and summary with `note_status: "not_saved"` plus `note_error`.

## Requirements

- macOS
- Node.js 18+
- Apple Mail running with the configured accounts available
- Apple Notes running if you want to save briefs there

## Quick Start

```bash
cd mail-intelligence
npm install
npm run build
node build/index.js
```

### Claude Code

```bash
claude mcp add apple-mail-intelligence -- node /absolute/path/to/apple-mcp/mail-intelligence/build/index.js
```

### Claude Desktop

```json
{
  "mcpServers": {
    "apple-mail-intelligence": {
      "command": "node",
      "args": ["/absolute/path/to/apple-mcp/mail-intelligence/build/index.js"]
    }
  }
}
```

## Configuration

The server loads its defaults from the canonical brain at `knowledge-corpus/data/mojosolo_operating_brain.json`.

Set `MAIL_INTELLIGENCE_CONFIG_PATH` to use a different config file or a different corpus file:

```bash
MAIL_INTELLIGENCE_CONFIG_PATH=/absolute/path/to/custom-mail-intel.json \
node build/index.js
```

The canonical brain encodes the current three-persona model:

- `mojosolo@mac.com` is curated creative intake.
- `david@mojosolo.com` is the primary human-facing operator inbox.
- `info@mojosolo.com` is the catch-all machine inbox for campaigns, client workflows, meeting intel, and alerts.

If Apple Mail uses account object names like `iCloud` or `Google` instead of the raw email address, use `discover_mail_accounts` first. The server also tries to resolve configured accounts by matching either account name or one of the account's email addresses.

The default mailbox for each persona is `INBOX`. If your Apple Mail setup uses a different mailbox object name, change the `mailbox` field in the config.

## Default Output

- Apple Notes folder: `Daily Intel`
- Note title format: `Daily Intel - YYYY-MM-DD`

## Example Queries

- "Show me the persona map"
- "Show me the Apple Mail accounts on this machine"
- "Scan the last day of inbox intelligence"
- "Compare signals over 30, 60, and 90 days"
- "Generate today's Daily Intel and save it to Notes"
