# Email Personas

Last verified: 2026-03-12

## Canonical Model

This repo should treat the three accounts as distinct operating identities, not one inbox cleanup problem.

| Account | Persona | Function | Default lane |
|------|------|------|------|
| `mojosolo@mac.com` | The Author | Curated reading list and creative/intellectual intake | `creative_intake` |
| `david@mojosolo.com` | The Operator | Human relationships, clients, deals, partnerships, and primary reply-from address | `human_replies_required` |
| `info@mojosolo.com` | The Machine | Catch-all aliases, campaign intake, client workflows, meeting intel, and automated signals | `machine_signals` |

## Durable Facts

- `david@mojosolo.com` is the primary email David gives to people.
- `info@mojosolo.com` is a catch-all account used for creative campaigns via funny aliases and inbound routing.
- `mojosolo@mac.com` is the author/creative-intake persona.
- `info@mojosolo.com` contains active client-work signals, not just generic operations noise.

## Known High-Value Streams

### `mojosolo@mac.com`

- Seeking Alpha
- AI Builder Club
- Superhuman AI
- Glasp
- Business Insider
- Apple News

### `david@mojosolo.com`

- GitHub CI/CD for `mojoOS` and `voyani-brain`
- Replit
- New York Times
- LinkedIn
- Binance
- Existing labels include Axios, TechCrunch, Medium, Employee Benefit News, Donald Miller

### `info@mojosolo.com`

- ElanPresentation client work for credit union presentations
- Otter.ai meeting summaries, including Mojo standup transcripts
- MojoMosaicXYZ platform alerts
- Wisconsin Department of Agriculture regulatory updates
- WhatTheAI
- simple.ai

## Implementation Assumptions

- `knowledge-corpus/data/mojosolo_operating_brain.json` is the canonical brain.
- `mail-intelligence` should load config from the canonical brain instead of maintaining a parallel config file.
- Laravel is the intended primary application and API layer on top of the canonical brain.
- Default output location for synthesized daily intelligence should be Apple Notes.
- Notes should be structured by persona plus domain, not dumped as a flat mailbox digest.
- `info@mojosolo.com` should bias toward automated signals, client-work routing, and meeting intelligence instead of defaulting to a human-reply inbox.
