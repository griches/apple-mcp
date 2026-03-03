# @griches/apple-mail-mcp

An [MCP](https://modelcontextprotocol.io) server that gives AI assistants access to Apple Mail on macOS via AppleScript.

## Quick Start

```bash
npx @griches/apple-mail-mcp
```

## Tools

| Tool | Description |
|------|-------------|
| `list_mailboxes` | List all mailboxes across accounts with unread counts |
| `list_messages` | List recent messages in a mailbox |
| `get_message` | Get the full content of an email by ID |
| `search_messages` | Search emails by subject across mailboxes |
| `send_email` | Send an email with optional CC/BCC |
| `get_unread_count` | Get unread count for a mailbox or all mailboxes |
| `move_message` | Move an email to a different mailbox |

## Configuration

### Claude Code

```bash
claude mcp add apple-mail -- npx @griches/apple-mail-mcp
```

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "npx",
      "args": ["@griches/apple-mail-mcp"]
    }
  }
}
```

## Requirements

- **macOS** (uses AppleScript)
- **Node.js** 18+

## License

MIT — see the [main repository](https://github.com/griches/apple-mcp) for full details.
