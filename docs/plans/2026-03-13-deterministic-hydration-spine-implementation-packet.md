# Deterministic Hydration Spine Implementation Packet

Last verified: 2026-03-13

## Status

- `Status`: implementation packet
- `Execution authority`: none until explicitly approved
- `Parent roadmap`: `docs/plans/2026-03-13-apple-mcp-governed-roadmap.md`
- `Target repo area`: `hydration-pipeline`
- `Planning base`: committed repo head `e3b2539`

## Objective

Build the first trustworthy spine of the hydration system:

`source taxonomy -> deterministic harvest -> canonical SignalDocument -> evidence bundle -> skill compiler skeleton`

This packet intentionally stops before validation implementation and before more shell work.

## Scope Lock

This packet covers only:

1. deterministic source boundaries
2. a unified normalized document contract
3. a first Desktop/filesystem provider
4. one evidence-bundle path
5. one compiler skeleton that emits real skill-file targets

This packet does not cover:

- validation UI
- shell implementation
- transcript-vendor expansion beyond the existing seam
- packaging or distribution work

## Current Starting Point

At `e3b2539`, the repo already has:

- `hydration-pipeline/src/cli.ts`
- `hydration-pipeline/src/config.ts`
- source providers for:
  - `mailSource.ts`
  - `messagesSource.ts`
  - `notesSource.ts`
  - `corpusSource.ts`
- per-channel normalization files for:
  - `mailNormalization.ts`
  - `messagesNormalization.ts`
  - `notesNormalization.ts`
- run artifact folder creation in `output/artifactPaths.ts`

What is still missing for the actual target system:

- one canonical `SignalDocument` contract shared across all sources
- a first-class Desktop/filesystem source
- extraction modules
- compiler modules
- a unified artifact manifest that ties harvest -> evidence -> skills together

## Governing Decisions

1. Desktop/filesystem ingest is a separate deterministic provider.
2. Mail, Messages, Notes, and files are distinct source types and stay that way.
3. The canonical brain is seed context and metadata, not proof of voice on its own.
4. The endpoint of this sprint is skill-oriented compiler output, not only harvest JSON.
5. Validation is contract-only in this packet and should not expand into another build stream yet.

## P0 Deliverables

### Deliverable 1: Source taxonomy and canonical registry

Create one source taxonomy that every harvested item can map to.

Required source types for this sprint:

- `mail`
- `message`
- `note`
- `filesystem`
- `corpus_seed`

Required output:

- one canonical source registry artifact per run

Proposed new file:

- `hydration-pipeline/src/normalize/sourceRegistry.ts`

Responsibilities:

- define source-type metadata
- define collector identifiers
- emit the run-local source registry artifact

### Deliverable 2: Canonical `SignalDocument`

Unify the current per-channel normalization outputs under one shared document shape.

Proposed new files:

- `hydration-pipeline/src/normalize/signalDocument.ts`
- `hydration-pipeline/src/normalize/provenance.ts`

Current channel-specific normalizers should map into the shared shape instead of each inventing their own schema.

Required minimum fields:

```ts
export interface SignalDocument {
  id: string;
  sourceType: "mail" | "message" | "note" | "filesystem" | "corpus_seed";
  sourceId: string;
  collector: string;
  channel: string;
  authoredBy: "david" | "external" | "mixed" | "unknown";
  personaHint: "author" | "operator" | "machine" | "unknown";
  timestamp: string;
  rawTimestamp: string;
  title: string | null;
  text: string;
  participants: string[];
  tags: string[];
  evidenceHash: string;
  provenance: {
    directness: "direct" | "quoted" | "third_party" | "inferred";
    sourcePath?: string;
    sourceApp?: string;
    freshnessCapturedAt: string;
  };
  metadata: Record<string, unknown>;
}
```

Acceptance rule:

- mail, messages, notes, and filesystem documents must all serialize to this one interface

### Deliverable 3: Desktop/filesystem provider

Implement the first deterministic filesystem source.

Proposed new files:

- `hydration-pipeline/src/providers/filesystemSource.ts`
- `hydration-pipeline/src/providers/filesystemRules.ts`

Required behaviors:

- root path defaults to `~/Desktop` unless overridden
- recursive inventory
- ignore rules
- MIME/type detection
- size capture
- modification timestamp capture
- content hashing
- UTF-8 text extraction for supported text-like files
- binary-safe metadata-only handling for unsupported binaries

Required config additions in `hydration-pipeline/src/config.ts`:

- `filesystemRoot?: string`
- `filesystemLimit?: number`
- `filesystemMode?: "desktop" | "path"`

Required CLI additions in `hydration-pipeline/src/cli.ts`:

- `--filesystem-root <path>`
- `--filesystem-limit <n>`
- `--filesystem-mode <desktop|path>`

Required output artifacts:

- `harvest/filesystem-harvest.json`
- `harvest/filesystem-normalized.json`

### Deliverable 4: Unified harvest manifest

After harvest, each run should emit one manifest that describes what was actually captured.

Proposed new file:

- `hydration-pipeline/src/output/runManifest.ts`

Artifact:

- `logs/run-manifest.json`

Required contents:

- run id
- config summary
- source registry summary
- counts by source type
- errors by source
- artifact paths produced

### Deliverable 5: Evidence extraction v1

Build one real extraction layer.

Proposed new files:

- `hydration-pipeline/src/extract/davidVoiceEvidence.ts`
- `hydration-pipeline/src/extract/mojosoloBrandEvidence.ts`
- `hydration-pipeline/src/extract/evidenceScoring.ts`

Required outputs:

- `evidence/david_voice_evidence.json`
- `evidence/mojosolo_brand_evidence.json`

Required v1 behavior:

- select candidate `SignalDocument`s
- separate first-person from third-person signal
- separate David voice evidence from company/brand evidence
- preserve provenance references back to source document ids
- emit confidence notes without inventing certainty

Acceptance rule:

- each major extracted rule or observation must point back to source evidence ids

### Deliverable 6: Compiler skeleton v1

Build the first compiler endpoint, but keep it intentionally narrow.

Proposed new files:

- `hydration-pipeline/src/compile/davidSkillCompiler.ts`
- `hydration-pipeline/src/compile/mojosoloSkillCompiler.ts`
- `hydration-pipeline/src/compile/unifiedSkillCompiler.ts`

Required outputs:

- `skills/david-voice-skill/SKILL.md`
- `skills/mojosolo-brand-skill/SKILL.md`
- `skills/david-mojosolo-unified-skill/SKILL.md`

Compiler v1 requirement:

- emit skeletal but real `SKILL.md` artifacts with:
  - mission
  - source-of-truth / evidence window
  - working modes
  - voice or brand rules sections
  - anti-pattern or uncertainty placeholders if evidence is incomplete

The compiler does not need final polish in this sprint.
It does need to prove that the endpoint is a skill, not only a bundle.

## P1 Design-Only Deliverables

These should be designed now but not fully implemented in this sprint:

- `validation/` mirror file layout
- human correction vocabulary
- low-confidence rule audit format
- correction-loop file contract

Proposed design placeholder files only:

- `hydration-pipeline/src/validate/validationMirror.ts`
- `hydration-pipeline/src/validate/ruleAudit.ts`

These may remain stubs if the compiler path is not yet complete.

## File-Level Plan

### Files to add

- `hydration-pipeline/src/normalize/signalDocument.ts`
- `hydration-pipeline/src/normalize/provenance.ts`
- `hydration-pipeline/src/normalize/sourceRegistry.ts`
- `hydration-pipeline/src/providers/filesystemSource.ts`
- `hydration-pipeline/src/providers/filesystemRules.ts`
- `hydration-pipeline/src/extract/davidVoiceEvidence.ts`
- `hydration-pipeline/src/extract/mojosoloBrandEvidence.ts`
- `hydration-pipeline/src/extract/evidenceScoring.ts`
- `hydration-pipeline/src/compile/davidSkillCompiler.ts`
- `hydration-pipeline/src/compile/mojosoloSkillCompiler.ts`
- `hydration-pipeline/src/compile/unifiedSkillCompiler.ts`
- `hydration-pipeline/src/output/runManifest.ts`

### Files to modify

- `hydration-pipeline/src/cli.ts`
- `hydration-pipeline/src/config.ts`
- `hydration-pipeline/src/output/artifactPaths.ts`
- `hydration-pipeline/src/output/writeArtifacts.ts`
- `hydration-pipeline/src/normalize/mailNormalization.ts`
- `hydration-pipeline/src/normalize/messagesNormalization.ts`
- `hydration-pipeline/src/normalize/notesNormalization.ts`

## Execution Order

### Step 1: shared contract first

- add `SignalDocument`
- add shared provenance helpers
- refactor the three existing normalizers to emit the shared shape

### Step 2: filesystem provider

- add Desktop/filesystem provider
- add ignore rules and hashing
- connect harvest and normalization outputs

### Step 3: run manifest

- emit one run-local manifest that captures counts, errors, and outputs

### Step 4: evidence extraction

- build David and MojoSolo evidence bundles
- keep provenance attached

### Step 5: compiler endpoint

- compile evidence into real `SKILL.md` file destinations
- allow imperfect content, but enforce real terminal artifacts

### Step 6: validation design only

- define shapes and output paths
- do not let validation UI or correction tooling delay the compiler path

## Acceptance Criteria

- one run can harvest mail, messages, notes, corpus seed, and filesystem inputs without changing code between runs
- all normalized documents conform to one canonical `SignalDocument` interface
- filesystem/Desktop ingest is a real source provider rather than logic hidden inside another adapter
- evidence bundles contain source-document references
- compiler output writes at least one real `SKILL.md` artifact
- run artifacts are grouped under one run id with a machine-readable manifest
- validation remains clearly downstream of extraction and compile

## Verification

Minimum required verification for implementation work against this packet:

- `cd hydration-pipeline && npm run build`
- one harvest run with bounded limits
- inspect generated artifacts under `artifacts/north-star-hydration/<run-id>/`

Suggested smoke command shape after implementation:

```bash
cd hydration-pipeline
npm run hydrate -- all \
  --output ../artifacts/north-star-hydration \
  --messages-source export \
  --transcript-source none \
  --inbox-limit 2 \
  --sent-limit 1 \
  --notes-limit 2 \
  --filesystem-mode desktop \
  --filesystem-limit 25
```

## Risks

- filesystem ingest can sprawl if ignore rules are weak
- per-channel normalizers may resist unification if the shared contract is underspecified
- compiler work can drift back into “just another YAML bundle” if output requirements are not enforced
- validation work can prematurely consume the sprint if not held to design-only

## Explicit Deferrals

- validation implementation
- review UI
- shell feature work
- transcript-vendor expansion beyond the seam
- broad repo packaging changes

## Recommended Next Move After This Packet

1. approve this packet as the immediate build scope
2. implement `SignalDocument` and filesystem source first
3. then wire evidence extraction and one compiler output path
4. only after that open the next packet for validation implementation
