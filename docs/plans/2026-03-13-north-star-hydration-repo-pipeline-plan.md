# North Star Hydration Repo Pipeline Plan

**Goal:** Build a repo-local pipeline that harvests David and MojoSolo signal from the existing Apple MCP stack, extracts grounded evidence bundles, compiles deployable `SKILL.md` artifacts, and emits human-review deliverables.

**Depends on:**

- [2026-03-13-david-mojosolo-skill-output-spec.md](../plans/2026-03-13-david-mojosolo-skill-output-spec.md)
- [2026-03-13-north-star-hydration-rebuild-request.md](../plans/2026-03-13-north-star-hydration-rebuild-request.md)

**Primary outcome:** A deterministic local pipeline that can produce:

1. `david-voice-skill/SKILL.md`
2. `mojosolo-brand-skill/SKILL.md`
3. `david-mojosolo-unified-skill/SKILL.md`
4. evidence bundles and validation mirrors tied to exact source windows

---

## Repo Facts This Plan Is Built On

These are current, local facts in this repo and should drive the plan shape.

1. `apple-mail`, `apple-messages`, `apple-notes`, `knowledge-corpus`, and `apple-mail-intelligence` already exist as local MCP servers.
2. `knowledge-corpus/data/mojosolo_operating_brain.json` is the canonical brain and already models the three inbox personas and meeting-intel assumptions.
3. The current brain names `Otter.ai` and `meeting transcripts` inside the Machine persona flow. It does not name Fireflies.
4. `messages/messages-export.json` already contains a staged Apple Messages export with `348` messages.
5. `messages/scripts/export-from-handles.mjs` already provides a deterministic export path from `~/Library/Messages/chat.db` for `mojosolo@mac.com` and `david@mojosolo.com`.
6. There is no Fireflies MCP server or vector-search package in this repo today.
7. `mail-intelligence` already understands the three inbox model and can summarize signal windows, but it is not a voice-skill compiler.
8. Apple Notes is the default output sink for summaries today, but the architecture doc says Notes remain an output sink, not the source of truth.

That means the pipeline should treat Mail, Messages, Notes, and the canonical brain as first-class local inputs, while treating Fireflies/vector retrieval as a provider seam to be added cleanly.

---

## Product Shape

### Stage 1: Harvest

Read local human signal from:

- Apple Mail via MCP
- Apple Messages via MCP or staged export JSON
- Apple Notes via MCP
- canonical brain via `knowledge-corpus`
- transcript providers via a new adapter seam

### Stage 2: Normalize

Convert raw source material into a common evidence format with:

- source id
- source type
- date range
- speaker / author
- first-person vs third-party classification
- persona relevance
- channel classification
- text chunks and metadata

### Stage 3: Extract

Build two grounded intermediate bundles:

1. `DavidVoiceEvidenceBundle`
2. `MojoSoloBrandEvidenceBundle`

These are not the final artifacts. They are the grounded evidence layer for the compiler.

### Stage 4: Compile

Emit deployable skills:

- personal voice skill
- brand skill
- unified wrapper skill

### Stage 5: Validate

Emit review artifacts that let a human mark:

- sounds right / wrong
- too polished
- too corporate
- wrong phrase bank
- wrong persona mode
- overclaimed rule
- low-confidence rule that needs pruning

---

## Implementation Strategy

Create a new repo-local package:

- `hydration-pipeline/`

Reasoning:

- This keeps extraction/compiler logic separate from the MCP server packages.
- It avoids polluting `knowledge-corpus` with generated artifacts.
- It can consume MCP servers over stdio without forcing those servers to become library packages.
- It gives the repo one explicit place for harvest, normalization, extraction, compilation, and validation logic.

### Proposed Layout

```text
hydration-pipeline/
├── package.json
├── tsconfig.json
├── src/
│   ├── cli.ts
│   ├── config.ts
│   ├── mcp/
│   │   ├── client.ts
│   │   └── localServers.ts
│   ├── providers/
│   │   ├── mailSource.ts
│   │   ├── messagesSource.ts
│   │   ├── notesSource.ts
│   │   ├── corpusSource.ts
│   │   └── transcript/
│   │       ├── transcriptSource.ts
│   │       ├── otterMailTranscriptSource.ts
│   │       └── firefliesVectorSource.ts
│   ├── normalize/
│   │   ├── signalDocument.ts
│   │   ├── chunking.ts
│   │   └── provenance.ts
│   ├── extract/
│   │   ├── davidVoiceEvidence.ts
│   │   ├── mojosoloBrandEvidence.ts
│   │   └── evidenceScoring.ts
│   ├── compile/
│   │   ├── davidSkillCompiler.ts
│   │   ├── mojosoloSkillCompiler.ts
│   │   └── unifiedSkillCompiler.ts
│   ├── validate/
│   │   ├── validationMirror.ts
│   │   └── ruleAudit.ts
│   └── output/
│       ├── artifactPaths.ts
│       └── writeArtifacts.ts
└── tests/
```

### Artifact Output Location

Write generated outputs under:

- `artifacts/north-star-hydration/<run-id>/`

With subfolders:

- `harvest/`
- `evidence/`
- `skills/`
- `validation/`
- `logs/`

Reasoning:

- Generated artifacts should not live inside `knowledge-corpus/data/` because that directory is the canonical brain seed, not an execution log.
- This keeps run history inspectable and reversible.

---

## Runtime Interfaces

### Local MCP Access

Use stdio child processes against existing built packages:

- `mail/build/index.js`
- `messages/build/index.js`
- `notes/build/index.js`
- `knowledge-corpus/build/index.js`
- `mail-intelligence/build/index.js`

Build a minimal local MCP client in `hydration-pipeline/src/mcp/client.ts` that can:

- start a server
- call a tool by name with arguments
- parse JSON tool responses
- stop the server cleanly

This should reuse the same local-child-process assumption already present in the shell architecture.

### Transcript Provider Seam

Define a provider seam instead of hardcoding Fireflies:

```ts
export interface TranscriptSource {
  name: string;
  listSessions(query?: string): Promise<TranscriptSession[]>;
  fetchSession(sessionId: string): Promise<TranscriptDocument>;
  search(query: string, opts?: TranscriptSearchOptions): Promise<TranscriptHit[]>;
}
```

Initial provider implementations:

1. `OtterMailTranscriptSource`
   - harvests transcript-style summaries from the Machine inbox using Apple Mail / mail-intelligence conventions
   - grounded in the current brain's `Otter.ai` assumptions

2. `FirefliesVectorSource`
   - env-configured external adapter
   - not implemented against any repo-local server today
   - should ship initially as interface + fixture-backed tests + stub CLI validation

This is the correct seam because Fireflies/vector retrieval is not yet in-repo.

---

## Source Plan By Channel

### 1. Apple Mail

Use `apple-mail` as the primary long-form written-signal source.

Primary tools:

- `list_mailboxes`
- `list_messages`
- `get_message`
- `search_messages`
- `get_unread_count`

Use `apple-mail-intelligence` for persona-aware bootstrapping:

- `get_persona_map`
- `scan_persona_inboxes`
- `analyze_signal_trends`

Mail harvest must produce at least three partitions:

1. `author_mail`
2. `operator_mail`
3. `machine_mail`

And one explicit subset:

- `david_first_person_mail`

The extraction pipeline must separate mail written by David from mail written about David or merely received by him.

### 2. Apple Messages

Use two paths:

#### Live path

- `apple-messages` MCP
- `list_chats`
- `get_chat_messages`
- `search_messages`
- `get_chat_participants`

#### Staged path

- `messages/messages-export.json`
- refreshed by `messages/scripts/export-from-handles.mjs`

This gives the pipeline a deterministic fixture path for testing and a live path for fresh harvests.

### 3. Apple Notes

Use `apple-notes` as a private writing / output review channel, not the canonical truth store.

Primary tools:

- `list_folders`
- `list_notes`
- `get_note`
- `search_notes` if added later through MCP surface discovery
- `create_note` / `update_note` only for review-output emission, not evidence mutation

Notes should contribute:

- private writing samples
- working language and internal naming
- review sink material

Notes should not silently override stronger evidence from direct emails, texts, or transcripts.

### 4. Knowledge Corpus

Use `knowledge-corpus` as seed context, vocabulary context, and persona/brand scaffold.

Primary tools:

- `get_corpus_overview`
- `get_corpus_section`
- `search_corpus`
- `list_sources`
- `get_source`
- `get_mail_intelligence_config`

Use this layer for:

- named concepts
- persona map
- known language anchors
- inbox role definitions
- source registry grounding

Do not use it as proof of David's real voice. It is context scaffolding, not primary voice evidence.

### 5. Transcript / Meeting Intel

Short-term truth in this repo:

- meeting-intel is currently represented as `Otter.ai` style traffic in the Machine inbox and in the canonical brain

Future seam:

- Fireflies transcript retrieval
- vector-search recall over transcript corpus

The plan must support both without pretending both already exist.

---

## Data Model

### `SignalDocument`

Normalized unit of evidence.

```ts
interface SignalDocument {
  id: string;
  sourceType: "mail" | "message" | "note" | "transcript" | "brain_seed";
  sourceId: string;
  channel: string;
  authoredBy: "david" | "external" | "mixed" | "unknown";
  personaHint?: "author" | "operator" | "machine";
  timestamp: string;
  title?: string;
  participants: string[];
  text: string;
  tags: string[];
  provenance: {
    collector: string;
    directness: "direct" | "quoted" | "third_party" | "inferred";
    freshness: string;
  };
}
```

### `DavidVoiceEvidenceBundle`

Must include:

- dominant phrasing patterns
- direct quote bank
- setup/transition/closing phrases
- channel differences
- anti-patterns
- confidence-weighted rules
- blind spots and contradictions

### `MojoSoloBrandEvidenceBundle`

Must include:

- brand thesis candidates
- named concepts / language map
- persona separation evidence
- offer framing evidence
- anti-pattern evidence
- audience adaptation evidence

---

## CLI Shape

Provide one deterministic CLI with these commands:

```bash
npm run hydrate -- harvest
npm run hydrate -- extract
npm run hydrate -- compile
npm run hydrate -- validate
npm run hydrate -- all
```

Suggested flags:

```bash
--profile david
--brand mojosolo
--from 2024-01-01
--to 2026-03-13
--messages-source live|export
--transcript-source otter_mail|fireflies_vector|none
--output artifacts/north-star-hydration/manual-run
```

The CLI must make the selected evidence window and provider mix explicit in every run.

---

## Task Plan

## Task 1: Scaffold `hydration-pipeline/`

Create the package, CLI shell, artifact writer, and config loader.

Files:

- `hydration-pipeline/package.json`
- `hydration-pipeline/tsconfig.json`
- `hydration-pipeline/src/cli.ts`
- `hydration-pipeline/src/config.ts`
- `hydration-pipeline/src/output/artifactPaths.ts`

Verification:

- `npm run build`
- `npm run hydrate -- --help`

## Task 2: Implement local MCP client + server launcher

Build a minimal stdio client for local child-process MCP tools.

Files:

- `hydration-pipeline/src/mcp/client.ts`
- `hydration-pipeline/src/mcp/localServers.ts`
- tests with fixture responses

Verification:

- can call `knowledge-corpus:get_corpus_overview`
- can call `mail-intelligence:get_persona_map`

## Task 3: Implement corpus and persona bootstrap

Harvest seed context from the canonical brain and mail-intelligence.

Files:

- `hydration-pipeline/src/providers/corpusSource.ts`

Output:

- brain snapshot
- persona map snapshot
- source registry snapshot

Verification:

- extracts Author / Operator / Machine roles correctly
- captures `Otter.ai` / meeting-intel assumptions from the current brain

## Task 4: Implement Mail harvester

Build persona-aware mail collection and David-authored filtering.

Files:

- `hydration-pipeline/src/providers/mailSource.ts`
- `hydration-pipeline/src/normalize/mailNormalization.ts`

Output:

- raw mail harvest JSON
- normalized `SignalDocument[]`

Verification:

- separates received mail from authored/replied mail where possible
- preserves account/mailbox metadata

## Task 5: Implement Messages harvester

Support both live MCP reads and staged export JSON.

Files:

- `hydration-pipeline/src/providers/messagesSource.ts`
- `hydration-pipeline/src/normalize/messagesNormalization.ts`

Verification:

- reads `messages/messages-export.json`
- can classify `from_me` vs external messages
- handles the current 348-message export deterministically in tests

## Task 6: Implement Notes harvester

Read writing samples and emit review notes later.

Files:

- `hydration-pipeline/src/providers/notesSource.ts`
- `hydration-pipeline/src/normalize/notesNormalization.ts`

Verification:

- can load selected folders/notes
- can emit review-output notes without mutating evidence inputs

## Task 7: Implement transcript provider seam

Define the interface and ship two initial providers.

Files:

- `hydration-pipeline/src/providers/transcript/transcriptSource.ts`
- `hydration-pipeline/src/providers/transcript/otterMailTranscriptSource.ts`
- `hydration-pipeline/src/providers/transcript/firefliesVectorSource.ts`

Rules:

- `OtterMailTranscriptSource` is the only repo-grounded provider on day one.
- `FirefliesVectorSource` ships as env-driven adapter + fixtures until a real endpoint contract is wired.

Verification:

- provider selection works from CLI flags
- missing Fireflies env fails clearly, not silently

## Task 8: Normalize all sources into a common evidence corpus

Merge harvest results into deduplicated `SignalDocument[]` plus chunked evidence views.

Files:

- `hydration-pipeline/src/normalize/signalDocument.ts`
- `hydration-pipeline/src/normalize/chunking.ts`
- `hydration-pipeline/src/normalize/provenance.ts`

Verification:

- direct first-person evidence is tagged distinctly from third-party mentions
- duplicated transcript/mail summary content can be detected and marked

## Task 9: Extract David voice evidence bundle

Build a deterministic extraction pass focused on voice and channel behavior.

Files:

- `hydration-pipeline/src/extract/davidVoiceEvidence.ts`
- `hydration-pipeline/src/extract/evidenceScoring.ts`

Output:

- `evidence/david-voice-evidence.json`
- `evidence/david-voice-evidence.yaml`

Verification:

- phrase banks are evidence-linked
- low-signal rules remain low confidence

## Task 10: Extract MojoSolo brand evidence bundle

Build a separate extraction pass for company language, named concepts, and persona separation.

Files:

- `hydration-pipeline/src/extract/mojosoloBrandEvidence.ts`

Output:

- `evidence/mojosolo-brand-evidence.json`
- `evidence/mojosolo-brand-evidence.yaml`

Verification:

- Author / Operator / Machine distinctions are explicit
- named concepts reflect corpus + notes + mail evidence instead of generic brand filler

## Task 11: Compile the three skill artifacts

Transform evidence into deployable skills.

Files:

- `hydration-pipeline/src/compile/davidSkillCompiler.ts`
- `hydration-pipeline/src/compile/mojosoloSkillCompiler.ts`
- `hydration-pipeline/src/compile/unifiedSkillCompiler.ts`

Output:

- `skills/david-voice-skill/SKILL.md`
- `skills/mojosolo-brand-skill/SKILL.md`
- `skills/david-mojosolo-unified-skill/SKILL.md`

Verification:

- required modes from the spec are present
- wrapper does not silently blend David and company voice

## Task 12: Emit validation mirrors and audit reports

Produce human-review artifacts for each generated skill.

Files:

- `hydration-pipeline/src/validate/validationMirror.ts`
- `hydration-pipeline/src/validate/ruleAudit.ts`

Output:

- `validation/david-skill-review.md`
- `validation/mojosolo-skill-review.md`
- `validation/rule-audit.json`

Verification:

- every high-confidence rule can point back to evidence ids
- low-confidence rules are surfaced for manual review

---

## Testing Strategy

### Unit tests

Cover:

- MCP client response parsing
- mail normalization
- messages export normalization
- transcript provider selection
- evidence scoring
- compiler output sections

### Fixture tests

Use:

- `messages/messages-export.json`
- fixture mail payloads
- fixture note payloads
- fixture transcript payloads
- small corpus snapshots from `knowledge-corpus`

### Integration tests

Run only when the local machine can support them:

- Apple Mail access
- Apple Messages database access
- Apple Notes access

These should be opt-in because they depend on macOS permissions and local user data.

---

## Acceptance Criteria

This pipeline is done when:

1. it can harvest from the current local Apple MCP stack without hand editing code between runs
2. it can ingest the staged 348-message export deterministically
3. it can use the canonical brain as seed context without treating it as primary voice truth
4. it can emit separate David and MojoSolo evidence bundles
5. it can compile the three required `SKILL.md` artifacts
6. it can emit validation mirrors tied to evidence ids
7. Fireflies/vector retrieval is represented as a clean provider seam, not a fake in-repo dependency
8. generated artifacts live outside `knowledge-corpus/data/`

---

## Execution Order Recommendation

Build in this order:

1. scaffold package and MCP client
2. bootstrap corpus + persona map
3. messages staged-path ingestion
4. mail ingestion
5. notes ingestion
6. transcript provider seam
7. evidence extraction
8. compilers
9. validation outputs
10. live integration pass on the local Mac

This order front-loads the deterministic fixtures and delays the most permission-heavy and externally coupled work until the pipeline shape is already proven.
