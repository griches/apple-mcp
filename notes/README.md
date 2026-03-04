# @griches/apple-notes-mcp

An [MCP](https://modelcontextprotocol.io) server that gives AI assistants access to Apple Notes on macOS via AppleScript.

## Quick Start

```bash
npx @griches/apple-notes-mcp
```

## Tools

| Tool | Description |
|------|-------------|
| `list_folders` | List all folders in Apple Notes |
| `create_folder` | Create a new folder |
| `list_notes` | List all notes in a folder |
| `get_note` | Get the full content of a note by title |
| `create_note` | Create a new note (HTML body) in a folder |
| `update_note` | Update the body of an existing note |
| `delete_note` | Delete a note |
| `delete_folder` | Delete a folder and all its notes |
| `search_notes` | Search notes by keyword across folders |

## Configuration

### Claude Code

```bash
claude mcp add apple-notes -- npx @griches/apple-notes-mcp
```

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-notes": {
      "command": "npx",
      "args": ["@griches/apple-notes-mcp"]
    }
  }
}
```

## Requirements

- **macOS** (uses AppleScript)
- **Node.js** 18+

## License

MIT — see the [main repository](https://github.com/griches/apple-mcp) for full details.
