# David + MojoSolo Skill Output Specification

**Goal:** Define the terminal artifacts emitted by the North Star hydration pipeline so the extractor is designing toward deployable cross-tool skills, not just an intermediate YAML bundle.

**Consumers:** Claude Code, Codex, Cursor, and any future agent runtime that can load a local `SKILL.md`.

**Core rule:** The hydration bundle is an evidence artifact. It is not the final artifact. The final artifact is one or more deployable skills.

---

## Required Output Artifacts

The pipeline must emit these artifacts:

1. `david-voice-skill/SKILL.md`
2. `mojosolo-brand-skill/SKILL.md`
3. `david-mojosolo-unified-skill/SKILL.md` (recommended wrapper)

Optional supporting artifacts:

- `evidence/david_hydration_bundle.yaml`
- `evidence/mojosolo_brand_bundle.yaml`
- `evidence/source_registry.yaml`
- `validation/david_skill_review.md`
- `validation/mojosolo_skill_review.md`

The evidence artifacts exist to justify the skill. The skill is the thing downstream agents actually load.

---

## Skill Architecture

### Layer 1: Evidence Extraction

Input sources:

- Apple Mail threads
- Apple Messages history
- Apple Notes writing samples
- Fireflies transcripts
- Vector-search recall over Fireflies transcripts
- `knowledge-corpus/data/mojosolo_operating_brain.json` as seed context

Output:

- person-level evidence bundle
- brand-level evidence bundle
- provenance and confidence metadata

### Layer 2: Skill Compilation

Compiler input:

- extracted evidence bundle
- explicit target artifact type
- optional validation corrections

Compiler output:

- `SKILL.md` files with executable operating guidance
- optional reference files and templates if the resulting skill needs them

---

## Artifact 1: `david-voice-skill/SKILL.md`

### Purpose

This skill lets an agent write as David with enough fidelity that the result sounds plausibly authored by him, while preserving safety and uncertainty boundaries.

### Trigger Scope

Use this skill when the task is:

- writing an email as David
- drafting a text or DM as David
- rewriting a note into David's real voice
- responding to a client or collaborator in David's tone
- producing first-person writing where David is the speaker

Do not use it for broad company positioning unless the request is explicitly personal-first.

### Required Sections

#### 1. Frontmatter

Must define:

- `name`
- `description`

Description must mention:

- write as David
- email, text, notes, proposals, responses
- voice fidelity over polish
- when not to use the skill

#### 2. Mission

One concise paragraph stating:

- the job is to sound like David, not a polished corporate approximation
- authentic roughness is preserved when grounded in evidence
- confidence must track available signal

#### 3. Source of Truth

Must define:

- skill version
- evidence window
- freshness date
- dominant source types
- known blind spots
- what was inferred vs directly observed

#### 4. Voice Rules

Must include explicit instructions for:

- cadence
- sentence length tendencies
- setup phrases
- qualifiers and hedges
- how David transitions into the actual point
- when he is direct vs elliptical
- how much polish is too much

#### 5. Phrase Bank

Must contain:

- signature phrases
- setup phrases
- transition phrases
- emphasis repeaters
- closers
- phrases to avoid because they sound too clean or too corporate

#### 6. Channel Rules

Separate rules for:

- email
- text / iMessage
- notes / memos
- proposals or client-facing writing

Each channel must specify:

- expected level of polish
- expected brevity
- whether fragments are acceptable
- whether explicit CTA language is natural

#### 7. Do / Don't Transform Rules

Must include examples of:

- too-corporate -> David-like
- too-marketing -> David-like
- too-clean -> David-like
- too-vague -> David-like

These should be transformation patterns, not generic style advice.

#### 8. Anti-Patterns

Must explicitly forbid:

- corporate abstraction
- inflated certainty
- generic sales language
- sounding like a polished ghostwriter
- removing all rough edges
- fake confidence where evidence is thin

#### 9. Uncertainty Policy

Must tell the agent what to do when:

- the request needs domain content but evidence is thin
- the request conflicts with known voice patterns
- the request is high-stakes or reputationally risky

#### 10. Working Modes

The David voice skill must support at least:

- `reply_as_david`
- `draft_as_david`
- `rewrite_into_david_voice`
- `audit_for_david_voice`

---

## Artifact 2: `mojosolo-brand-skill/SKILL.md`

### Purpose

This skill lets an agent write for MojoSolo as a company and switch deliberately among the repo's three operating personas.

### Trigger Scope

Use this skill when the task is:

- writing company positioning
- creating website or brand copy
- drafting proposals for MojoSolo
- describing methodology, systems, or product logic
- writing in one of the company personas

Do not use it for first-person David ghostwriting unless the request is explicitly personal.

### Required Modes

This skill must support four explicit output modes:

1. `write_for_mojosolo_author`
2. `write_for_mojosolo_operator`
3. `write_for_mojosolo_machine`
4. `brand_audit`

### Required Sections

#### 1. Brand Thesis

Define:

- what MojoSolo is
- what category language it accepts and rejects
- what makes the brand distinct
- what kind of intelligence/product posture it projects

#### 2. Persona Map

Define all three personas explicitly.

For each persona include:

- role in the business
- tonal center
- vocabulary bias
- preferred sentence shape
- what it should never sound like
- ideal use cases

#### 3. Language Map

Must define what MojoSolo calls:

- the company
- the system
- the brain
- the inbox layer
- extraction / hydration work
- agent / AI behavior
- products, offers, and workflows

This section is mandatory because named concepts are part of brand consistency.

#### 4. Messaging Pillars

Must define:

- primary claims the brand can make
- supporting proof patterns
- what counts as overclaiming
- what kind of transformation language is valid

#### 5. Anti-Patterns

Must explicitly prohibit:

- SaaS boilerplate
- startup hype language
- generic AI future-talk
- consultant cliches
- benefit-density without mechanism
- empty premium-brand language

#### 6. Offer Framing

Must define how MojoSolo should talk about:

- services
- systems
- automation
- media workflows
- operator intelligence
- implementation boundaries

#### 7. Audience Adaptation

Must define how the brand shifts for:

- clients
- internal use
- collaborators
- technical builders
- creative partners

The mode should change, but the brand should remain recognizable.

#### 8. Calibration Examples

Must include:

- on-brand snippets
- off-brand snippets
- transforms from generic copy to MojoSolo copy

---

## Artifact 3: `david-mojosolo-unified-skill/SKILL.md`

### Purpose

This wrapper skill gives downstream agents one entry point while preserving explicit mode switches.

### Required Modes

The unified skill must expose these exact modes:

1. `write_as_david`
2. `write_for_mojosolo_author`
3. `write_for_mojosolo_operator`
4. `write_for_mojosolo_machine`
5. `audit_output_against_source_voice`

### Required Behavior

- It must route personal-first writing to David rules.
- It must route company writing to MojoSolo brand rules.
- It must refuse silent blending between personal and company voices.
- It must tell the caller which mode it selected when the request is ambiguous.
- It must surface low-confidence warnings when evidence is thin.

---

## Compiler Input Contract

The compiler stage must consume evidence organized around these domains:

### Personal Voice Domain

- phrasing patterns
- cadence patterns
- channel-specific behavior
- confidence-weighted quotes
- anti-patterns inferred from real writing

### Brand Domain

- core concepts
- named systems
- methodology terms
- persona distinctions
- offer and positioning language

### Provenance Domain

- source registry
- date coverage
- confidence per claim
- direct quote inventory
- validation corrections

The compiler must not emit a rule that cannot be tied back to evidence, pattern extraction, or explicit human correction.

---

## Validation Requirements

A generated skill is only acceptable if it passes all of these checks:

1. A reviewer can identify the intended mode without being told.
2. The David skill does not collapse into generic founder voice.
3. The MojoSolo skill preserves the three-persona distinction.
4. The wrapper skill does not silently blur personal and company voice.
5. Claims and wording rules are traceable to evidence.
6. The skill is usable by an agent without loading the raw evidence bundle.
7. The skill contains explicit anti-patterns and uncertainty behavior.

---

## Non-Goals

These are not acceptable terminal artifacts:

- a YAML-only hydration bundle with no skill output
- a flat biography of David
- a CRM-style contact profile
- a generic brand guide with no agent instructions
- a single blended voice that erases the Author / Operator / Machine distinction

---

## Immediate Implication For North Star Hydration

The current packet can remain the extractor if desired, but it is incomplete for this use case. A second-stage compiler is mandatory unless the packet itself is upgraded to emit deployable skills.
