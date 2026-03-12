# Knowledge Corpus MCP Server

An MCP server that exposes a bundled structured knowledge corpus and companion research report.

The package now defaults to the MojoSolo operating brain and also includes a Laravel projection layer so the same corpus can drive an application backend.

## Tools

| Tool | Description |
|------|-------------|
| `get_corpus_overview` | Return corpus metadata, available sections, source counts, and report availability |
| `list_corpus_sections` | List the top-level corpus sections with lightweight summaries |
| `get_corpus_section` | Return a full top-level corpus section by name |
| `get_mail_intelligence_config` | Return the mail-intelligence config embedded in the canonical brain |
| `search_corpus` | Search the structured corpus, the bundled report, or both |
| `get_laravel_brain_blueprint` | Return Laravel tables, routes, and seed data derived from the brain |
| `export_laravel_brain_pack` | Write a Laravel integration pack to a target directory |
| `list_sources` | List all `source_registry` entries with ids, URLs, and trust levels |
| `get_source` | Return a single `source_registry` entry by id |
| `list_report_sections` | List the sections available in the bundled markdown report |
| `get_report_section` | Return one bundled markdown report section by title or slug |

## Requirements

- Node.js 18+

## Quick Start

```bash
cd knowledge-corpus
npm install
npm run build
node build/index.js
```

### Claude Desktop

```json
{
  "mcpServers": {
    "knowledge-corpus": {
      "command": "node",
      "args": ["/absolute/path/to/apple-mcp/knowledge-corpus/build/index.js"]
    }
  }
}
```

### Claude Code

```bash
claude mcp add knowledge-corpus -- node /absolute/path/to/apple-mcp/knowledge-corpus/build/index.js
```

## Custom Corpus Files

By default, the server reads the bundled files in `knowledge-corpus/data/`.

You can point the server at a different structured corpus and markdown report:

```bash
KNOWLEDGE_CORPUS_PATH=/absolute/path/to/corpus.yaml \
KNOWLEDGE_REPORT_PATH=/absolute/path/to/report.md \
node build/index.js
```

- `KNOWLEDGE_CORPUS_PATH` supports `.yaml`, `.yml`, and `.json` structured corpora.
- `KNOWLEDGE_REPORT_PATH` is optional. If omitted, report tools use the bundled markdown file when present.

## Laravel Export

Export a Laravel-ready brain pack:

```bash
cd knowledge-corpus
npm install
npm run export:laravel -- /absolute/path/to/laravel-app
```

The export writes:

- `config/brain.php`
- `database/migrations/2026_03_12_000000_create_brain_tables.php`
- `database/seeders/BrainSeeder.php`
- `app/Http/Controllers/BrainController.php`
- `routes/brain.php`

## Example Queries

- "Show me the persona_architecture section"
- "Show me the mail-intelligence config"
- "Give me the Laravel brain blueprint"
- "Export the Laravel brain pack into my app"
