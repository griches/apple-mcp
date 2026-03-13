# North Star Hydration Rebuild Request

**Goal:** Give the author of the current North Star Hydration packet an exact change request so the packet can support David voice-skill generation and MojoSolo brand-skill generation instead of stopping at an intermediate YAML bundle.

**Current packet reviewed:** `/Users/david/Downloads/claude-code-northstar-hydration`

---

## Executive Summary

The current packet is a solid extraction engine, but it is not yet a skill-building system.

What works:

- strong voice-first doctrine
- good emphasis on provenance and confidence
- useful full-profile extraction behavior

What is broken or incomplete:

1. `SKILL.md` points to `references/schema-v2.md`, `references/intelligence.md`, and `references/validation-protocol.md`, but those files currently live at the root of the folder.
2. The packet's terminal artifact is `north_star_hydration_bundle.v2` YAML only.
3. The schema is centered on person profiles, not emitted skills.
4. The schema still contains leaked travel-domain fields in `scorecard_lens`:
   - `trip_context`
   - `booking_judgment`
   - `traveler_alignment`
5. The validation loop is designed for profile review, not generated-skill review.

The result is that the packet can extract evidence, but it cannot finish the job for the actual use case.

---

## Target Outcome

The rebuilt packet must support this pipeline:

1. harvest human signal
2. extract grounded evidence bundles
3. compile that evidence into deployable `SKILL.md` artifacts
4. validate the generated skills with a human review loop

Required final artifacts:

- `david-voice-skill/SKILL.md`
- `mojosolo-brand-skill/SKILL.md`
- optional `david-mojosolo-unified-skill/SKILL.md`

The hydration bundle becomes an intermediate artifact, not the endpoint.

---

## Required Changes

## 1. Fix the Broken File Layout

Choose one and make it consistent:

### Option A: Move the reference files

Create:

- `references/schema-v2.md`
- `references/intelligence.md`
- `references/validation-protocol.md`

### Option B: Update `SKILL.md`

Change the `Read:` instructions to the real current paths.

This is a correctness bug, not a design preference. The current skill will fail if the referenced files are not where `SKILL.md` says they are.

---

## 2. Separate Extraction From Compilation

The packet currently conflates extraction completion with system completion.

That has to change.

### Required architecture

Stage 1: Extractor

- reads source material
- emits evidence bundle(s)
- preserves provenance and confidence

Stage 2: Compiler

- reads the evidence bundle(s)
- emits deployable `SKILL.md` files
- includes rules, anti-patterns, mode switches, and uncertainty handling

You can implement this in one skill with multiple modes or as two coordinated skills. Either is acceptable. What is not acceptable is stopping at YAML.

---

## 3. Add a New Mode: `Skill Compiler`

Add a first-class mode with this job:

- consume hydration output
- compile personal voice rules
- compile brand voice rules
- emit deployable skill artifacts

### Minimum outputs

- personal voice skill
- brand skill
- optional unified wrapper skill

### Minimum compiler concerns

- mode switching
- phrase bank generation
- anti-pattern extraction
- uncertainty policy
- provenance/freshness section
- audience/channel adaptation

---

## 4. Replace or Generalize `scorecard_lens`

The current schema contains travel-domain leakage:

- `trip_context`
- `booking_judgment`
- `traveler_alignment`

That makes the schema look copied from another context.

### Required fix

Either:

- replace `scorecard_lens` with a configurable `compiler_lens` or `evaluation_lens`

Or:

- remove it entirely from the canonical schema and move domain-specific scoring into deployment-specific overlays

### Better replacement shape

Use fields like:

- `voice_fidelity`
- `brand_consistency`
- `judgment_transfer`
- `channel_fit`
- `persona_separation`
- `trust_preservation`

---

## 5. Add a Brand-Level Schema

The current schema is person-centric.

That is insufficient for MojoSolo because the output has to model:

- David as a person
- MojoSolo as a brand/company
- the Author / Operator / Machine persona system

### Required addition

Add a brand schema or brand bundle section covering:

- brand thesis
- named concepts / language map
- messaging pillars
- anti-patterns
- persona definitions
- offer framing
- audience adaptations

Without this, the system can produce a person profile but not a company skill.

---

## 6. Add Explicit Terminal Artifact Specs

The packet currently tells the model to output only YAML.

Replace that with explicit artifact choices.

### Required deliverables

#### `david-voice-skill/SKILL.md`

Must include:

- voice rules
- phrase banks
- channel rules
- anti-patterns
- uncertainty policy
- rewrite/audit modes

#### `mojosolo-brand-skill/SKILL.md`

Must include:

- brand thesis
- persona map
- language map
- messaging pillars
- anti-patterns
- offer framing
- audience adaptation

#### `david-mojosolo-unified-skill/SKILL.md`

Must expose exact modes:

- `write_as_david`
- `write_for_mojosolo_author`
- `write_for_mojosolo_operator`
- `write_for_mojosolo_machine`
- `audit_output_against_source_voice`

---

## 7. Expand Source Doctrine For Real Voice Recovery

The packet currently supports general human-signal extraction, which is useful, but the target use case requires a clearer doctrine for multi-source personal and brand voice building.

### Required source classes

- email threads
- SMS / iMessage history
- notes / private writing
- meeting transcripts
- vector-search retrieval over transcripts
- canonical brain / operator documents as context seed

### Required rule

The compiler must know the difference between:

- direct first-person voice
- spoken meeting behavior
- company/system language
- inferred behavior from third-party descriptions

Those should not be blended without provenance.

---

## 8. Add Skill Validation, Not Just Profile Validation

The current validation protocol is oriented around reviewing person profiles.

That is not enough.

### Add a generated-skill validation layer

A reviewer should be able to flag:

- sounds unlike David
- sounds unlike MojoSolo
- persona boundary collapse
- too polished
- too corporate
- overclaiming
- wrong phrase bank
- high-confidence claim with weak evidence

### Minimum validation output

For each generated skill, include:

- what evidence window it reflects
- what changed since prior version
- highest-confidence traits/rules
- lowest-confidence rules to review manually

---

## 9. Tighten Mode Semantics

Current modes are extraction-centric.

That is fine for the extractor, but insufficient for the terminal artifact.

### Keep if useful

- Full Extraction
- Profile Update
- Validation Deliverable
- Voice-Only Extraction
- Schema Audit

### Add or update

- `Brand Extraction`
- `Skill Compiler`
- `Skill Validation Deliverable`
- `Wrapper Skill Build`

The mode names should make it obvious whether the system is producing evidence or deployable instructions.

---

## 10. Suggested Folder Shape

A clean minimal rebuild could look like this:

```text
north-star-hydration/
├── SKILL.md
├── references/
│   ├── schema-v3.md
│   ├── intelligence.md
│   ├── validation-protocol.md
│   ├── brand-schema.md
│   └── skill-compiler.md
├── assets/
│   └── templates/
│       ├── david-voice-skill-template.md
│       ├── mojosolo-brand-skill-template.md
│       └── unified-wrapper-template.md
└── scripts/
    └── validate_bundle_or_skill.py
```

This is not mandatory, but the separation of extractor rules, brand rules, and compiler rules is.

---

## What The Rebuilt Packet Should Say Explicitly

The packet should state these rules clearly:

1. The hydration bundle is an evidence artifact, not the final artifact.
2. Voice extraction is highest priority, but brand/persona compilation is a required downstream step.
3. A generated skill must contain executable agent instructions, not just description.
4. Personal voice and company voice cannot be silently blended.
5. All emitted rules need evidence, pattern support, or explicit human correction.

---

## Acceptance Criteria

The rebuild is done when all of these are true:

1. The skill can run without broken path references.
2. The system can emit a valid evidence bundle.
3. The system can emit `david-voice-skill/SKILL.md`.
4. The system can emit `mojosolo-brand-skill/SKILL.md`.
5. The system can emit a unified wrapper with explicit mode switches.
6. Travel-domain leakage is removed from the canonical schema.
7. Validation supports generated-skill review, not just profile review.
8. The generated skills can be loaded directly by Claude Code, Codex, or Cursor without also loading the raw evidence bundle.

---

## Recommended Execution Order

1. Fix file layout and path correctness.
2. Define the terminal artifact spec.
3. Update the schema to support person plus brand compilation.
4. Add compiler mode.
5. Add generated-skill validation.
6. Test on David + MojoSolo as the reference use case.
