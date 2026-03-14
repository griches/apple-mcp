# Apple MCP Governed Roadmap

Last verified: 2026-03-13

## Status

- `Status`: planning packet
- `Execution authority`: none
- `Primary repo`: `apple-mcp`
- `Plan scope`: governed roadmap for the repo as it exists on committed branch head `e3b2539`
- `Current local reality at planning time`: active work is continuing on local branch `feat/macos-shell` with uncommitted hydration-pipeline changes that must be preserved

## Canonical Inputs

This roadmap is grounded in the current repo and its existing design documents.

- `README.md`
- `CLAUDE.md`
- `docs/macos-shell-architecture.md`
- `docs/plans/2026-03-12-macos-operator-roadmap.md`
- `docs/plans/2026-03-13-north-star-hydration-repo-pipeline-plan.md`
- `docs/plans/2026-03-13-north-star-hydration-rebuild-request.md`
- `docs/plans/2026-03-13-david-mojosolo-skill-output-spec.md`
- `hydration-pipeline/src/cli.ts`
- `knowledge-corpus/data/mojosolo_operating_brain.json`

If this roadmap and the repo diverge, the repo wins for current-state facts and this roadmap remains the intended sequencing document.

## Executive Thesis

`apple-mcp` is not one product.

It is a governed monorepo with four distinct layers that must not be collapsed into one another:

1. deterministic Apple-app MCP servers
2. a canonical brain and intelligence layer
3. a hydration and skill-compilation pipeline
4. a future macOS shell product layer

The biggest mistake available to this repo is trying to make the shell, the hydration compiler, the MCP servers, and downstream Laravel exports all behave like one fused application.

They should instead be sequenced like this:

`deterministic sensors -> normalized artifacts -> grounded extraction -> skill compilation -> validation -> shell / operator product`

That is the governing rule for the roadmap.

## Repo Facts

These facts were verified from the repo at plan time and determine the roadmap shape.

1. The repo already ships Apple-app MCP packages for Notes, Messages, Contacts, Mail, Reminders, Calendar, Maps, and Music.
2. `knowledge-corpus` already exists and serves the canonical MojoSolo operating brain.
3. `mail-intelligence` already exists and generates Daily Intel using the three-persona inbox model.
4. The repo already contains a repo-local `hydration-pipeline` package with explicit commands for `harvest`, `extract`, `compile`, `validate`, and `all`.
5. The repo already contains multiple hydration planning documents that say the terminal artifact must be deployable `SKILL.md` outputs, not only intermediate evidence bundles.
6. The repo already has a separate macOS shell architecture document that explicitly says the shell is a product layer on top of the MCP foundation, not a rewrite of it.
7. The current local branch posture is `feat/macos-shell`, and the working tree contains active, uncommitted hydration-related work. That in-flight work must be preserved and treated as live context, not overwritten by governance cleanup.

## Product Boundaries

### 1. MCP Foundation

Purpose:

- read and mutate native Apple applications through deterministic local tooling
- stay independently usable
- remain local-first and safety-aware

What it is not:

- the skill compiler
- the shell UI
- the canonical long-term storage layer

### 2. Canonical Brain and Intelligence

Purpose:

- store structured operating context
- seed persona and company context
- support mail intelligence and downstream exports

What it is not:

- the primary evidence source for voice truth
- the final product UI

### 3. Hydration Pipeline

Purpose:

- harvest real signal
- normalize it
- extract evidence bundles
- compile deployable skills
- emit validation surfaces

What it is not:

- a generic AI summarizer
- a replacement for the MCP servers
- a shell application

### 4. macOS Shell

Purpose:

- provide a native operator cockpit on top of the deterministic foundation
- supervise MCP daemons
- route intents
- fall back to computer-use only where direct automation is inadequate

What it is not:

- the first milestone the repo must finish
- an excuse to skip deterministic pipeline work

## Strategic Priority Order

The repo should be built in this order:

1. govern and stabilize the repo as a recognized KOSMOS surface
2. harden deterministic harvest sources
3. finish evidence extraction and skill compilation
4. finish validation and review loops
5. only then accelerate the macOS shell into an active build stream

Reasoning:

- the MCP foundation already exists
- the hydration pipeline is where current leverage and current ambiguity both sit
- the shell is valuable, but it is downstream of trustworthy data, evidence, and compiled operating artifacts

## Workstreams

| Workstream | Purpose | Priority | Governing rule |
| --- | --- | --- | --- |
| `WS1` MCP package foundation | keep Notes/Messages/Mail/etc. reliable and shippable | High | do not break standalone server usability |
| `WS2` Hydration pipeline | build the deterministic harvest -> compile spine | Highest | deterministic before LLM; evidence before skill |
| `WS3` Canonical brain + mail intelligence | keep brain and Daily Intel coherent with persona model | High | brain seeds context; harvested evidence grounds behavior |
| `WS4` macOS shell | build cockpit, router, daemon supervision, computer-use seam | Medium | shell depends on stable lower layers |
| `WS5` packaging and commercialization | publishing, onboarding, safety posture, distribution | Medium | package after layers are coherent |

## Now / Next / Later

### Now

Friday, March 13, 2026 through Tuesday, March 31, 2026

- register and govern the repo
- preserve and rationalize active hydration-pipeline work
- make the deterministic source model explicit
- choose and implement the first filesystem/Desktop ingestion path
- finish the minimum normalized artifact contract
- prove one end-to-end hydration run can produce evidence and at least one skill artifact target

### Next

April 2026

- finish compiler outputs for David voice, MojoSolo brand, and unified wrapper
- build validation mirrors and rule audits
- refine transcript provider seams without coupling the repo to one transcript vendor
- improve knowledge-corpus projection and mail-intelligence alignment

### Later

After the hydration compiler and validation loop are trustworthy

- accelerate SwiftUI shell build-out
- add local daemon supervision and routing
- add computer-use provider runtime where no deterministic MCP surface exists
- harden packaging and operator onboarding

## Phase Roadmap

## Phase 0: Governance and Repo Grounding

Status:

- partially complete

Completed:

- repo registered in the local KOSMOS registry
- repo-onboard state adopted
- `kosmos knock apple-mcp` now resolves and reports repo truth

Still open:

- `mojoOS` has no persisted portfolio row for `apple-mcp`
- the repo remains `warn` because active work is intentionally in flight

Exit criteria:

- `apple-mcp` remains registered with a stable onboard fingerprint
- the team agrees that in-flight `feat/macos-shell` work is preserved, not overwritten
- this roadmap exists as a committed repo-local planning packet

## Phase 1: Deterministic Source and Harvest Spine

Window:

- immediate priority for March 13-31, 2026

Objective:

Make the hydration pipeline unquestionably deterministic at the source and normalization layers.

Must-haves:

- formalize source taxonomy:
  - Apple Mail
  - Apple Messages
  - Apple Notes
  - canonical brain
  - transcript provider seam
  - direct filesystem/Desktop source
- add a first-class filesystem/Desktop provider that performs recursive inventory, MIME/type detection, hashing, and ignore rules
- keep Mail, Notes, and Messages as separate adapters rather than pretending they are generic files
- define a single normalized `SignalDocument` shape with provenance and channel semantics
- ensure artifact runs write into `artifacts/north-star-hydration/<run-id>/`

Non-goals:

- do not build the shell UI in this phase
- do not overfit the pipeline to Otter or Fireflies
- do not collapse the canonical brain into harvested evidence

Exit criteria:

- one repeatable `harvest` run succeeds across the chosen source mix
- normalized artifacts are deterministic and inspectable
- Desktop/filesystem ingestion exists as a separate provider, not an ad hoc hack inside another source

## Phase 2: Evidence Extraction and Skill Compilation

Window:

- April 2026

Objective:

Turn normalized source material into grounded evidence bundles and then into deployable skills.

Must-haves:

- `DavidVoiceEvidenceBundle`
- `MojoSoloBrandEvidenceBundle`
- compiler outputs for:
  - `david-voice-skill/SKILL.md`
  - `mojosolo-brand-skill/SKILL.md`
  - `david-mojosolo-unified-skill/SKILL.md`
- separation between evidence artifact and skill artifact
- explicit uncertainty policy and anti-pattern extraction

Non-goals:

- do not stop at YAML
- do not emit skill rules that cannot be tied back to evidence
- do not let shell design work preempt compiler completeness

Exit criteria:

- the pipeline can run `harvest -> extract -> compile`
- the output skills are actually loadable by downstream agents
- evidence, provenance, and freshness are included in supporting artifacts

## Phase 3: Validation and Review Loop

Window:

- immediately after compiler viability, likely late April 2026

Objective:

Create a human-review layer that can refine or reject compiled behavior without corrupting provenance.

Must-haves:

- review mirrors for generated skills
- rule audit outputs
- explicit flags such as:
  - too polished
  - too corporate
  - wrong persona mode
  - low-confidence rule
  - unsupported inference
- correction workflow that feeds the compiler rather than bypassing it

Exit criteria:

- a human can review a generated skill and understand why each major rule exists
- low-confidence rules are visible and removable
- validation becomes a standard run stage, not an ad hoc note

## Phase 4: macOS Shell Alpha

Window:

- only after the lower layers are trustworthy

Objective:

Build the native shell as an operator product on top of the stable repo foundation.

Must-haves:

- SwiftUI shell scaffold
- daemon manager for local MCP processes
- deterministic intent router
- computer-use provider seam
- cockpit, terminal, and production dashboard primitives

Rules:

- deterministic MCP tools first
- computer-use only when direct automation is insufficient
- shell depends on interfaces and structured outputs, not repo internals

Exit criteria:

- shell can launch and supervise the local MCP stack
- shell can route a defined set of intents against existing MCP tools
- shell can surface structured outputs without inventing its own shadow logic

## Phase 5: Packaging and Productization

Window:

- after shell alpha and validated compiler flows

Objective:

Turn the repo into a repeatable product surface for personal-first use and later commercial hardening.

Must-haves:

- package and distribution strategy per module
- onboarding and permissions guidance
- secrets and account isolation posture
- clear boundary between personal defaults and distributable defaults

## Immediate Sprint: March 13-31, 2026

This is the working sprint the repo should run right now.

### Sprint Name

`Deterministic Hydration Spine`

### Sprint Goal

Prove that `apple-mcp` can harvest from deterministic local sources, normalize them into inspectable evidence artifacts, and compile toward deployable skill outputs without letting the shell work overtake the pipeline.

### Must-Have Outcomes

1. one explicit Desktop/filesystem source implementation
2. one normalized source registry and `SignalDocument` contract
3. one harvest run that writes complete artifacts for the selected sources
4. one extraction layer that outputs evidence bundles with provenance
5. one compiler skeleton that points to real `SKILL.md` outputs, not only placeholder YAML

### Sprint Tracks

#### Track A: Source model and provider seams

- define source taxonomy and interfaces
- separate filesystem/Desktop ingest from Mail/Notes/Messages providers
- preserve transcript providers as a seam, not a hardcoded assumption

#### Track B: Deterministic harvest and normalization

- implement or harden Desktop/filesystem provider
- unify normalization around a common signal contract
- preserve provenance, timestamps, source identity, and hashes

#### Track C: Evidence extraction

- emit David and MojoSolo evidence bundles
- make first-person / third-person and persona separation explicit
- score evidence without overclaiming

#### Track D: Compiler path

- connect evidence bundles to skill compiler outputs
- write artifact destinations and terminal file layout
- guarantee compiler output is the endpoint, not an optional afterthought

#### Track E: Validation path

- freeze the validation contract and review vocabulary
- define review mirror output shape and correction loop
- defer validation implementation until the extraction and compiler path is real

### Explicit Cuts For This Sprint

If time compresses, cut in this order:

1. shell implementation work
2. transcript-vendor expansion
3. richer UI or cockpit ideas
4. packaging polish

Do not cut:

1. deterministic source boundaries
2. normalized artifact contract
3. evidence bundle extraction
4. compiler endpoint for skills

Deferred from this sprint:

- validation implementation beyond contract and output-shape design
- review UI or rich human-facing validation surfaces

## Key Decisions

These decisions are now locked unless new evidence forces a change.

1. The hydration bundle is an intermediate artifact, not the final artifact.
2. The final artifacts for the hydration path are deployable skills.
3. Mail, Notes, Messages, and Desktop/filesystem are distinct source types.
4. The canonical brain is seed context and operating context, not the sole source of voice truth.
5. The shell is a downstream product layer, not the first critical milestone.

## Open Questions

1. Should Desktop/filesystem ingest focus on `~/Desktop` first, or a broader local-source registry from day one?
2. Which normalized source schema should become canonical across Mail, Messages, Notes, files, and transcripts?
3. Should transcript support stay `Otter`-first because of current repo truth, or move immediately to a cleaner generic seam with fixtures only?
4. Which artifacts should be committed versus treated as generated run output only?
5. When should `apple-mcp` be exported into `mojoOS` portfolio state so KOSMOS knock can reach `current` instead of `warn`?

## Success Metrics

- one new source can be added without rewriting the pipeline
- one hydration run can be replayed deterministically against the same input window
- generated skill outputs are grounded in evidence and usable by downstream agents
- human review focuses on rules and evidence quality, not on reconstructing what happened
- shell work is clearly sequenced behind lower-layer trust rather than competing with it

## Failure Modes To Avoid

- treating the shell as the repo's main objective before the compiler path is trustworthy
- mixing filesystem harvest into Mail or Notes adapters instead of giving it a real provider
- letting transcript-vendor assumptions shape the entire architecture
- using the canonical brain as if it were enough evidence for a voice compiler
- stopping at intermediate YAML bundles and calling the system done
- burying provenance so a human cannot tell where a generated rule came from

## Recommended Next Moves

1. preserve the active `feat/macos-shell` changes as the live workstream
2. land this roadmap packet in the repo
3. write the follow-on implementation packet for `Deterministic Hydration Spine`
4. if needed, split shell work and hydration work into clearly separate branches or worktrees
5. export `apple-mcp` into persisted `mojoOS` portfolio state after the roadmap and immediate packet exist
