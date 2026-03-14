# Memory

## Repo
`apple-mcp` contains standalone MCP servers for Apple apps plus higher-level automation packages built on top of Mail and Notes.

## Current Plan
- `docs/plans/2026-03-13-apple-mcp-governed-roadmap.md` | governed sequencing document for hydration, shell, intelligence, and packaging work
- `docs/plans/2026-03-13-deterministic-hydration-spine-implementation-packet.md` | immediate implementation packet scoped to source spine, SignalDocument, Desktop/filesystem ingest, evidence, and compiler skeleton

## Canonical Brain
| System | Role |
|------|------|
| `knowledge-corpus/data/mojosolo_operating_brain.json` | Canonical brain and single source of truth |
| `mail-intelligence` | Live Apple Mail sensor and Daily Intel generator that reads from the canonical brain |
| Laravel | Primary application and API layer projected from the canonical brain |

## Email Personas
| Account | Persona | Role |
|-----|------|------|
| `mojosolo@mac.com` | The Author | Curated creative and intellectual intake |
| `david@mojosolo.com` | The Operator | Primary human-facing reply-from account for clients, partners, and deals |
| `info@mojosolo.com` | The Machine | Catch-all campaign aliases, client workflow intake, and automated/platform signals |
| -> Full context | `memory/context/email-personas.md` | Durable account architecture and routing assumptions |

## Terms
| Term | Meaning |
|------|---------|
| Daily Intel | Superhuman-style synthesized daily brief generated from all three inboxes |
| The Author | `mojosolo@mac.com`, used for curated reading and creative input |
| The Operator | `david@mojosolo.com`, used for human relationships and primary outbound identity |
| The Machine | `info@mojosolo.com`, used for catch-all aliases, campaigns, client ops, and automated signals |
| -> Full glossary | `memory/glossary.md` | Additional durable shorthand |

## Preferences
- Default output sink for inbox intelligence is Apple Notes.
- `david@mojosolo.com` is the primary address given to people.
- `info@mojosolo.com` is intentionally a catch-all and should support creative alias routing.
