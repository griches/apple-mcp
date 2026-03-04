# @griches/apple-calendar-mcp

An [MCP](https://modelcontextprotocol.io) server that gives AI assistants access to Apple Calendar on macOS via AppleScript.

## Quick Start

```bash
npx @griches/apple-calendar-mcp
```

## Tools

| Tool | Description |
|------|-------------|
| `list_calendars` | List all calendars |
| `list_all_events` | List events across all calendars within a date range |
| `list_events` | List events in a specific calendar within a date range |
| `get_event` | Get full details of an event by summary/title |
| `create_event` | Create a new event with date, time, location, and description |
| `delete_event` | Delete an event by summary/title |
| `search_events` | Search events by summary/title across calendars |

## Configuration

### Claude Code

```bash
claude mcp add apple-calendar -- npx @griches/apple-calendar-mcp
```

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-calendar": {
      "command": "npx",
      "args": ["@griches/apple-calendar-mcp"]
    }
  }
}
```

## Requirements

- **macOS** (uses AppleScript)
- **Node.js** 18+

## License

MIT — see the [main repository](https://github.com/griches/apple-mcp) for full details.
