---
title: "EXECUTION_PLAN — <breath> tag — sub-utterance chunk hints"
kind: execution-plan
state: in_progress
source: Docs/incomplete/breath-tag.md
updated: 2026-05-13
refinement_state: ready_to_execute
feature_name: OPERATION SIGHING SCRIBE
starting_point_commit: c61e954c9ff63a5fcafbe6b76e85140defbe1973
mission_branch: mission/sighing-scribe/01
iteration: 1
---

# EXECUTION_PLAN.md — `<breath>` Sub-Utterance Chunk Hints

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission scope

Introduce the `<breath/>` GLOSA element end-to-end inside the glosa-av repository: data model, Fountain + FDX parsing, compiler output, annotation bridge, serializer round-trip, Stage Director auto-placement, validator diagnostics, CLI surface, and requirements-doc promotion. The cross-repo plumbing into SwiftVoxAlta's `GenerationContext.chunkHints` and Produciesta's `HeadlessAudioGenerator` (steps 7–8 in the source spec §10) is **out of scope** for this mission — it lives in a separate paired mission across the SwiftVoxAlta and Produciesta repos.

Source spec: [`Docs/incomplete/breath-tag.md`](Docs/incomplete/breath-tag.md). The spec itself defers a handful of open questions (§11); they are surfaced in this plan as entry criteria or as refinement-pass discussion points rather than blocking sorties.

---

## Open questions blocking dispatch

These should be resolved before Sortie 2 (Fountain parser) and Sortie 9 (Director schema) dispatch. The `refine-questions` pass should pull these forward for the user:

1. **PascalCase vs lowercase** (spec §3, §11.3). Spec body uses `<breath>` for consistency with HTML marker-tag convention; the existing three GLOSA elements use PascalCase (`<SceneContext>`, `<Intent>`, `<Constraint>`). The decision must be locked before Sortie 2's parser fixtures and Sortie 9's few-shot examples are written. **This plan proceeds on the assumption of lowercase `<breath/>`** as the spec recommends.
2. **SwiftCompartido `FountainParser` inline-note offsets** (spec §5.1, §11.1). Sortie 2 needs the character offset of each `[[ ]]` note within its enclosing dialogue paragraph. If the current parser collapses notes without preserving position, an upstream PR to SwiftCompartido must land first. The Sortie 2 entry criteria require this to be verified.
3. **FDX inline-mixed content** (spec §5.2, §11.2). Sortie 3 must verify Final Draft 13's emitted XML preserves `<glosa:breath/>` between `<Text>` runs.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU1 — GlosaCore Foundation | `Sources/GlosaCore/` | 1 | 0 | none |
| WU2 — Parser (Fountain + FDX) | `Sources/GlosaCore/` | 2 | 1 | WU1 |
| WU3 — Compiler Output | `Sources/GlosaCore/` | 1 | 2 | WU2 |
| WU4 — Annotation & Serialization | `Sources/GlosaAnnotation/` | 3 | 3 | WU3 |
| WU5 — Validator | `Sources/GlosaCore/` | 1 | 3 | WU3 |
| WU6 — Stage Director | `Sources/GlosaDirector/` | 2 | 1 | WU1 |
| WU7 — CLI | `Sources/glosa/` | 1 | 4 | WU4, WU6 |
| WU8 — Documentation | `Docs/` | 1 | 5 | WU1–WU7 |

Layers 1 (WU2) and 1 (WU6) are independent and may be dispatched in parallel after WU1 lands. WU4 and WU5 are independent and may run in parallel after WU3.

---

## Parallelism Structure

**Critical path** (longest dependency chain): `S1 → S2 → S4 → S5 → S6 → S11 → S12` — 7 sorties. `S3` runs in parallel with `S2` on the same critical-path layer.

**Parallel execution groups** (each dispatched as a fan-out after the previous group's exit criteria are met):

| Group | Sorties | Agent count | Notes |
|-------|---------|-------------|-------|
| **G0** | S1 | 1 (supervising) | Foundation; no parallelism possible. |
| **G1** | S2, S3, S9 | 3 (1 supervising + 2 sub-agents) | All three depend only on S1. **All three include `xcodebuild test` build steps**, so sub-agents MUST run in isolated worktrees (`isolation: worktree`) to avoid clobbering `.build/`. |
| **G2** | S4 | 1 (supervising) | Joins WU2 results before WU3 compiles. |
| **G3** | S5, S8, S10 | 3 (1 supervising + 2 sub-agents in worktrees) | S5 ← S4. S8 ← S4 (parallel to WU4). S10 ← S9 — and S9 typically completes during G1/G2, so S10 is queued for dispatch as soon as S5 starts. |
| **G4** | S6, S7 | 2 (1 supervising + 1 sub-agent in a worktree) | Both depend on S5; independent of each other. |
| **G5** | S11 | 1 (supervising) | Needs S5, S6, S7. |
| **G6** | S12 | 1 (supervising) | Docs sortie; depends on all of S1–S11. |

**Agent constraints**:
- **Every sortie in this plan has a build/test step** (`xcodebuild test ...`). Sub-agents that run in parallel groups MUST be dispatched with worktree isolation; otherwise concurrent `xcodebuild` invocations against the same `.build/` directory will corrupt incremental state. The supervising agent always works on the main mission branch.
- **Maximum sub-agent fan-out**: 2 sub-agents per group (3 total including the supervising agent). G1 is the only group that could theoretically run 3 sub-agents (S2 + S3 + S9), capped at 2 to stay within the documented 4-sub-agent ceiling without overcommitting CPU/RAM on parallel xcodebuilds.

**Sequential dispatch fallback**: If worktree isolation is unavailable, dispatch all sorties sequentially in priority order. Total mission length without parallelism: 12 sorties.

---

## Testing methodology (applies to every sortie)

These rules are inherited by every sortie below. Per-sortie test sections may add to them, but must not relax them. A test that violates any of these rules is a defect — fix it, do not quarantine it.

1. **Deterministic.** No `Date()`, no un-injected `UUID()`, no random seeds, no assertions whose result depends on `Dictionary` / `Set` iteration order. When asserting against a collection with a natural order (breath offsets ascending), assert on a sorted array; when comparing unordered collections, sort both sides first.

2. **Hermetic.** No network, no filesystem access outside the test bundle's resources or `NSTemporaryDirectory()`, no `ProcessInfo.environment` reads, no shared module-level mutable state. Tests must pass under `xcodebuild test -parallel-testing-enabled YES`.

3. **Untimed.** No `Thread.sleep`, no `Task.sleep`, no `XCTestExpectation` with timeouts, no `wait(for:timeout:)`, no `XCTest` `measure {}` blocks, no wall-clock assertions of any kind. `BreathLength.explicit(TimeInterval)` is *authored data*, not a measurement — its value comes from the source attribute (`350ms`, `0.4s`), never from a clock.

4. **No retries, no quarantine.** A flake is a defect — fix the root cause, never wrap a test in retry logic or mark it as "known flaky."

5. **`TimeInterval` ↔ milliseconds uses `.rounded()`, not truncation.** The serializer converts `.explicit(seconds)` to integer milliseconds via `Int((seconds * 1000).rounded())`. IEEE 754 represents `0.35` as `0.349999…`, so truncation would emit `349ms` and break the `350ms` ↔ `.explicit(0.35)` round-trip the spec example requires. Tests asserting this round-trip depend on `.rounded()`; agents must not replace it with `Int(_:)` truncation. This rule applies to S1, S2, S6, S7.

6. **Serialization tests assert canonical form, not source bytes.** "Round-trip" in this plan means *parse → serialize → re-parse → ASTs compare equal*, never *bytes compare equal to the original source*. The serializer's canonical form is fixed by spec: attribute order `length` then `strength`; attributes omitted when equal to defaults (`length="comma"`, `strength="medium"`); no inner whitespace inside `<breath/>` or `<glosa:breath/>`. Byte-level assertions are allowed only against this canonical form, never against arbitrary input text.

7. **Snapshot / substring tests (S10 prompt, S11 CLI) are deliberately tight.** Drift fails CI by design. Update a snapshot only when the spec changes — never to silence a noisy test. Inputs to snapshot tests must be assembled from ordered string templates, never from dictionary iteration that could shift between Swift versions.

8. **No performance tests.** None of the breath sorties have an O(n²) hazard worth guarding. Do not add `measure {}` blocks, duration assertions, or "regression guard" timing. If a future sortie identifies a real algorithmic hazard, that sortie may add a *count-based* guard (e.g. assert a memoization cache is consulted N times for input of size M) — never a wall-clock duration.

---

## WU1 — GlosaCore Foundation

### Sortie 1: Add breath data model to GlosaCore

**Priority**: 36.5 — Blocks all other sorties; establishes foundation types reused everywhere.
**Context budget**: ~19 turns (right-sized for default 50-turn budget).
**Parallel group**: G0 (single).

**Entry criteria**:
- [ ] First sortie — no prerequisites.

> **Note on Open Question #1** (PascalCase vs lowercase): Sortie 1 only introduces Swift types and is **not affected** by the casing decision. The decision must be locked before Sortie 2 (Fountain parser fixtures) and Sortie 9 (Director schema/few-shots) dispatch — see those sorties' entry criteria.

**Tasks**:
1. Create `Sources/GlosaCore/Breath.swift` containing the `BreathLength`, `BreathStrength`, and `Breath` types defined below. (One file rather than three to keep the breath data model co-located.)
2. Add `BreathLength` enum with cases `.comma`, `.semicolon`, `.period`, `.emDash`, `.beat`, `.explicit(TimeInterval)`. `Sendable`, `Equatable`, `Codable`.
3. Add `BreathStrength` enum with cases `.weak`, `.medium`, `.strong`. `Sendable`, `Equatable`, `Codable`.
4. Add `Breath` struct with fields `dialogueLineIndex: Int`, `characterOffset: Int`, `length: BreathLength`, `strength: BreathStrength`. `Sendable`, `Equatable`, `Codable`.
5. Extend `GlosaScore` (in `Sources/GlosaCore/GlosaScore.swift`) with a `breaths: [Breath]` collection alongside the existing `scenes` collection. The new field must default to `[]` so existing call sites compile unchanged.
6. Write `Tests/GlosaCoreTests/BreathTests.swift` covering: default initialization, codable round-trip for each `BreathLength` case (including `.explicit(0.35)`), codable round-trip for each `BreathStrength`, and a `GlosaScore` with mixed breath collection.

**Exit criteria**:
- [ ] `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'` succeeds.
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaCoreTests/BreathTests` passes with at least 5 test methods.
- [ ] `grep -r "public struct Breath" Sources/GlosaCore/` returns exactly one match.
- [ ] `grep -r "public enum BreathLength" Sources/GlosaCore/` returns exactly one match.
- [ ] `swift format -i -r Sources/GlosaCore/ Tests/GlosaCoreTests/` produces zero diff after the sortie.

---

## WU2 — Parser (Fountain + FDX)

### Sortie 2: Parse `<breath/>` from Fountain inline notes

**Priority**: 29 — Blocks WU3/WU4/WU5/WU7/WU8; foundation for Fountain breath data flow.
**Context budget**: ~20 turns (right-sized).
**Parallel group**: G1 (dispatch in parallel with S3 and S9).

**Entry criteria**:
- [ ] Sortie 1 exit criteria met.
- [ ] Open question #2 (SwiftCompartido `FountainParser` inline-note offsets) is verified — either the parser already surfaces per-note offsets within dialogue paragraphs, or the upstream PR has landed and is on a tag this repo can depend on.
- [ ] Open question #1 (PascalCase vs lowercase) resolved so the parser knows which tag name to recognize.

**Tasks**:
1. Extend `Sources/GlosaCore/GlosaParser.swift` to detect inline `[[<breath/>]]` notes inside dialogue paragraphs. The inline note's character offset within the enclosing dialogue paragraph becomes `Breath.characterOffset`; the paragraph's index among dialogue paragraphs in the current scene becomes `Breath.dialogueLineIndex`.
2. Parse `length` attribute: named values (`comma`, `semicolon`, `period`, `em-dash`, `beat`) map to the corresponding `BreathLength` case; explicit forms (`350ms`, `0.4s`) map to `.explicit(TimeInterval)`; missing attribute defaults to `.comma`.
3. Parse `strength` attribute: `weak`/`medium`/`strong` map to the corresponding case; missing attribute defaults to `.medium`.
4. Support the alternative `after="substring"` fallback encoding (spec §5.1): when present, locate the first occurrence of the substring in the enclosing dialogue paragraph and place the breath at the end of that occurrence. If no match, emit a parser warning and skip the breath.
5. Reject malformed input — invalid `length` value, invalid `strength` value, malformed explicit time string — by emitting a parser diagnostic and skipping the breath.
6. Write `Tests/GlosaCoreTests/BreathParserFountainTests.swift` with fixtures verbatim from spec §5.1: the Bishop case (Example 1), the run-on case (Example 2), the mixed-lengths case (Example 3), the `after=` fallback case, and at least three error-path cases (bad length value, bad strength value, breath outside dialogue).

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaCoreTests/BreathParserFountainTests` passes.
- [ ] Parsing Example 1 from spec §5.1 yields exactly three `Breath` values matching the offsets in spec §6.4 (`20` period/strong, `31` comma/medium, `43` comma/medium).
- [ ] Parsing Example 2 yields exactly four bare `Breath` values, each `length: .comma`, `strength: .medium`.
- [ ] A `[[<breath/>]]` note outside any dialogue paragraph produces one diagnostic and zero `Breath` values.
- [ ] `swift format -i -r Sources/GlosaCore/ Tests/GlosaCoreTests/` produces zero diff.

### Sortie 3: Parse `<glosa:breath/>` from FDX

**Priority**: 30 — Same dep-depth as S2; slightly higher risk score (FDX XML parsing).
**Context budget**: ~19 turns (right-sized).
**Parallel group**: G1 (dispatch in parallel with S2 and S9).

**Entry criteria**:
- [ ] Sortie 1 exit criteria met.
- [ ] Open question #3 (FDX inline mixed-content support) verified against a Final Draft 13 sample file.

**Tasks**:
1. Extend `Sources/GlosaCore/GlosaParser.swift` to detect `<glosa:breath/>` self-closing elements appearing as children of `<Paragraph Type="Dialogue">` interleaved between `<Text>` runs.
2. Compute `Breath.characterOffset` by summing the character length of all preceding `<Text>` runs within the same paragraph.
3. Parse `length` and `strength` attributes using the same value-mapping rules as Sortie 2.
4. Treat `<glosa:breath/>` outside `<Paragraph Type="Dialogue">` as a parser warning (consistent with Fountain behavior).
5. Write `Tests/GlosaCoreTests/BreathParserFDXTests.swift` with a fixture mirroring spec §5.2 (the Bishop case in FDX form), plus error-path fixtures for malformed attributes and a `<glosa:breath/>` outside a dialogue paragraph.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaCoreTests/BreathParserFDXTests` passes.
- [ ] Parsing the Bishop FDX fixture yields the same three `Breath` offsets as the Fountain equivalent.
- [ ] `swift format -i -r Sources/GlosaCore/ Tests/GlosaCoreTests/` produces zero diff.

---

## WU3 — Compiler Output

### Sortie 4: Surface breath points in CompilationResult

**Priority**: 22.75 — Critical-path join after both parsers complete.
**Context budget**: ~20 turns (right-sized).
**Parallel group**: G2 (supervising agent only — joins parser outputs).

**Entry criteria**:
- [ ] Sortie 2 and Sortie 3 exit criteria met.

**Tasks**:
1. Add `BreathPoint` struct to `Sources/GlosaCore/CompilationResult.swift` with fields `offset: Int`, `length: BreathLength`, `strength: BreathStrength`. `Sendable`, `Equatable`.
2. Extend `CompilationResult` with `breathPoints: [Int: [BreathPoint]]`, keyed by absolute dialogue-line index within the screenplay. Empty array (or missing key) means no chunk hints for that line.
3. Update `Sources/GlosaCore/GlosaCompiler.swift` to populate `breathPoints` from `GlosaScore.breaths`, mapping each `Breath.dialogueLineIndex` (scene-local) to the absolute screenplay-line index, and sorting each per-line array ascending by offset.
4. Confirm `ScoreResolver` and `ResolvedDirectives` remain unchanged — breath is structural, not directive (spec §7.3).
5. Write `Tests/GlosaCoreTests/BreathCompilerTests.swift`: feed a screenplay containing the Bishop dialogue line through `GlosaCompiler`, assert `breathPoints` for the line index contains exactly three sorted `BreathPoint`s matching the offsets in spec §6.4.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaCoreTests/BreathCompilerTests` passes.
- [ ] `CompilationResult.breathPoints` is publicly accessible (`grep -n "public let breathPoints" Sources/GlosaCore/CompilationResult.swift` returns one match).
- [ ] Lines with no breaths return either an empty array or a missing key — verified by an assertion in the test.
- [ ] `swift format -i -r Sources/GlosaCore/ Tests/GlosaCoreTests/` produces zero diff.

---

## WU4 — Annotation & Serialization

### Sortie 5: Extend GlosaAnnotatedElement with breathPoints

**Priority**: 15.5 — Bridges compiler output to annotation layer; blocks WU4's other sorties and WU7.
**Context budget**: ~19 turns (right-sized).
**Parallel group**: G3 (dispatch in parallel with S8 and S10 in worktrees).

**Entry criteria**:
- [ ] Sortie 4 exit criteria met.

**Tasks**:
1. Add `breathPoints: [BreathPoint]` field to `Sources/GlosaAnnotation/GlosaAnnotatedElement.swift`. Non-dialogue elements receive `[]`.
2. Wire the field through whatever bridge constructs `GlosaAnnotatedElement` from `CompilationResult` (locate via `grep -r "GlosaAnnotatedElement(" Sources/`).
3. Write `Tests/GlosaAnnotationTests/BreathBridgeTests.swift`: compile a Bishop-bearing screenplay and assert the corresponding dialogue element exposes three sorted `BreathPoint`s; assert a non-dialogue element (action/scene heading) exposes `[]`.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaAnnotationTests/BreathBridgeTests` passes.
- [ ] `grep -n "public let breathPoints" Sources/GlosaAnnotation/GlosaAnnotatedElement.swift` returns one match.
- [ ] `swift format -i -r Sources/GlosaAnnotation/ Tests/GlosaAnnotationTests/` produces zero diff.

### Sortie 6: Fountain round-trip in GlosaSerializer

**Priority**: 9 — Blocks S11 (CLI score command) and S12 (docs).
**Context budget**: ~17 turns (right-sized).
**Parallel group**: G4 (dispatch in parallel with S7 in a worktree).

**Entry criteria**:
- [ ] Sortie 5 exit criteria met.

**Tasks**:
1. Extend `Sources/GlosaAnnotation/GlosaSerializer.swift` to emit `[[<breath/>]]` inline notes at the correct offsets when serializing dialogue lines that carry `breathPoints`.
2. Emit `length` attribute only when not equal to the default `.comma`; emit `strength` attribute only when not equal to the default `.medium`. `.explicit(TimeInterval)` serializes as `length="<ms>ms"` rounded to integer milliseconds.
3. Write `Tests/GlosaAnnotationTests/BreathSerializerFountainTests.swift`: round-trip test for the Bishop fixture and the run-on fixture — parse → serialize → re-parse → `breathPoints` lists compare equal and re-parsed `GlosaScore` AST compares equal to the original. Do **not** assert byte-equality against the original screenplay source (see methodology rule 6); a Fountain source can contain whitespace and ordering that the upstream parser normalizes on re-emission. Test the contract this sortie owns: the inline-note serialization is canonical and re-parses identically.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaAnnotationTests/BreathSerializerFountainTests` passes.
- [ ] Round-tripping the Bishop fixture emits all three breaths in canonical inline-note form: `[[<breath length="period" strength="strong"/>]]`, `[[<breath/>]]`, `[[<breath/>]]` — attributes in order `length` then `strength`, no inner whitespace inside the tag, defaults omitted.
- [ ] Re-parsing the serializer output yields a `breathPoints` list identical to the input (same count, same offsets, same lengths, same strengths).
- [ ] A dialogue line with all-default breaths (bare `<breath/>`) round-trips without emitting `length=` or `strength=` attributes.
- [ ] `.explicit(0.35)` round-trips through the serializer as `length="350ms"` (relies on `.rounded()` per methodology rule 5).
- [ ] `swift format -i -r Sources/GlosaAnnotation/ Tests/GlosaAnnotationTests/` produces zero diff.

### Sortie 7: FDX round-trip in GlosaSerializer

**Priority**: 7 — Blocks S11 and S12.
**Context budget**: ~17 turns (right-sized).
**Parallel group**: G4 (dispatch in parallel with S6 in a worktree).

**Entry criteria**:
- [ ] Sortie 5 exit criteria met. (Independent of Sortie 6 — may run in parallel.)

**Tasks**:
1. Extend `Sources/GlosaAnnotation/GlosaSerializer.swift` to emit `<glosa:breath/>` elements at the correct text-run positions when serializing FDX-form dialogue paragraphs with breath points.
2. Emit `length` and `strength` attributes using the same default-omission rule as Sortie 6. Attributes are added to the `XMLElement` in canonical order (`length` first, `strength` second) so the resulting serialized XML is byte-deterministic across runs and Foundation versions.
3. Ensure the `glosa:` XML namespace is declared in the document root if any breath element is present.
4. Write `Tests/GlosaAnnotationTests/BreathSerializerFDXTests.swift`: round-trip test for the Bishop FDX fixture — parse → serialize → re-parse → `breathPoints` lists compare equal. Do not assert byte-equality against the original FDX source (see methodology rule 6) — XML libraries normalize whitespace and quoting in ways outside this serializer's contract.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaAnnotationTests/BreathSerializerFDXTests` passes.
- [ ] Re-parsing the serializer output yields a `breathPoints` list identical to the input (same count, same offsets, same lengths, same strengths).
- [ ] Serialized `<glosa:breath/>` elements emit attributes in the canonical order `length` then `strength` — verified by a string-search assertion that any `strength=` substring on a `<glosa:breath` line is preceded by a `length=` substring on the same line.
- [ ] The serialized FDX document declares `xmlns:glosa` when breaths are present and omits it when no breaths exist.
- [ ] `swift format -i -r Sources/GlosaAnnotation/ Tests/GlosaAnnotationTests/` produces zero diff.

---

## WU5 — Validator

### Sortie 8: Breath validator diagnostics

**Priority**: 4.75 — Independent leaf; only S12 (docs) waits on it.
**Context budget**: ~19 turns (right-sized).
**Parallel group**: G3 (dispatch in parallel with S5 and S10 in worktrees).

**Entry criteria**:
- [ ] Sortie 4 exit criteria met. (Independent of WU4 — may run in parallel with Sorties 5–7.)

**Tasks**:
1. Extend `Sources/GlosaCore/GlosaValidator.swift` with three diagnostics per spec §7.7:
   - **Warning** when a `<breath/>` is detected outside any dialogue line (must be surfaced even though the parser already drops such breaths — validator wraps the parser diagnostic).
   - **Warning** when two `<breath/>` markers share the same `(dialogueLineIndex, characterOffset)` pair on the same line.
   - **Info** when a dialogue line satisfies any of spec §6.1's trigger conditions (>180 chars, single-sentence colon-list, etc.) but has zero breath annotations.
2. Add the three new diagnostic codes to whatever enum/registry `GlosaDiagnostic` exposes.
3. Write `Tests/GlosaCoreTests/BreathValidatorTests.swift`: one fixture per diagnostic, asserting the correct severity and code.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaCoreTests/BreathValidatorTests` passes.
- [ ] Each of the three diagnostics fires on its dedicated fixture and only on that fixture.
- [ ] `swift format -i -r Sources/GlosaCore/ Tests/GlosaCoreTests/` produces zero diff.

---

## WU6 — Stage Director

### Sortie 9: SceneAnnotation schema extension

**Priority**: 9.75 — Foundation score (Codable schema reused by S10). Independent of WU2/WU3.
**Context budget**: ~20 turns (right-sized).
**Parallel group**: G1 (dispatch in parallel with S2 and S3 in a worktree, once S1 lands).

**Entry criteria**:
- [ ] Sortie 1 exit criteria met. (Independent of WU2/WU3 — may run in parallel.)
- [ ] Open question #1 (PascalCase vs lowercase) resolved so the schema field name and JSON keys are stable.

**Tasks**:
1. Add `BreathAnnotation` struct to `Sources/GlosaDirector/SceneAnnotation.swift` with fields `dialogueLineIndex: Int`, `characterOffset: Int`, `length: BreathLength?`, `strength: BreathStrength?`. `Sendable`, `Equatable`, `Codable`.
2. Add `breaths: [BreathAnnotation]` to `SceneAnnotation`. The new field is non-optional and defaults to `[]` for backward compatibility with previously emitted JSON.
3. Update the structured-output JSON schema fed to SwiftBruja (locate via `grep -r "SceneAnnotation" Sources/GlosaDirector/`) to advertise the `breaths` field with the property descriptions matching spec §6.3.
4. Add `breathThreshold: Int` field to `Sources/GlosaDirector/VocabularyGlossary.swift` (default value 180 per spec §6.1). Make it `Codable` so it round-trips through glossary YAML/JSON.
5. Write `Tests/GlosaDirectorTests/BreathSchemaTests.swift`: codable round-trip for `BreathAnnotation`, `SceneAnnotation` with non-empty `breaths`, and the Bishop JSON payload from spec §6.4.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaDirectorTests/BreathSchemaTests` passes.
- [ ] Decoding the verbatim Bishop JSON payload from spec §6.4 produces a `SceneAnnotation` whose `breaths` array has three entries with the expected offsets and attributes.
- [ ] Encoding then decoding an old-format `SceneAnnotation` (no `breaths` key) produces a value with `breaths == []`.
- [ ] `swift format -i -r Sources/GlosaDirector/ Tests/GlosaDirectorTests/` produces zero diff.

### Sortie 10: Stage Director prompts and few-shots for breath placement

**Priority**: 5.75 — Blocks S12 only; depends on S9.
**Context budget**: ~16 turns (right-sized).
**Parallel group**: G3 (dispatch in parallel with S5 and S8 in a worktree, once S9 lands).

**Entry criteria**:
- [ ] Sortie 9 exit criteria met.

**Tasks**:
1. Update the Stage Director system prompt in `Sources/GlosaDirector/Prompts.swift` (or its `Resources/` companion if prompts are externalized) to include the trigger conditions from spec §6.1 (180-char threshold, colon-list pattern, polysyndetic conjunctions, etc.).
2. Encode the placement rules from spec §6.2 verbatim in the prompt — priority order (colon-list, semicolon, between clauses, between list items, before long subordinate clauses) and the explicit prohibitions (inside noun phrases, inside quoted strings, within 10 chars of line edges, closer than 30 chars to another breath).
3. Add a positive few-shot example using the Bishop input/output pair from spec §6.4 (input text → expected `breaths` array).
4. Add a negative few-shot example using the "I noticed." line from spec §6.1 (input → empty `breaths` array).
5. Add a unit test in `Tests/GlosaDirectorTests/BreathPromptTests.swift` that snapshots the rendered system prompt and asserts it contains: the substring "180", the rule "Always insert here if the colon-list pattern exists", the prohibition "Closer than 30 characters", both few-shot inputs, and both few-shot expected outputs.

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS' -only-testing:GlosaDirectorTests/BreathPromptTests` passes.
- [ ] The rendered system prompt includes both few-shot examples, verified by the test.
- [ ] `swift format -i -r Sources/GlosaDirector/ Tests/GlosaDirectorTests/` produces zero diff.

---

## WU7 — CLI

### Sortie 11: `glosa preview` and `glosa score` surface breaths

**Priority**: 4.75 — Last code-touching sortie before docs; blocks only S12.
**Context budget**: ~20 turns (right-sized; slightly elevated by the test-target decision below).
**Parallel group**: G5 (supervising agent only).

**Entry criteria**:
- [ ] Sortie 5 exit criteria met (so `GlosaAnnotatedElement.breathPoints` is populated).
- [ ] Sortie 6 exit criteria met (so `glosa score` Fountain output emits breaths).
- [ ] Sortie 7 exit criteria met (so `glosa score` FDX output emits breaths). *(Added in refinement Pass 4 — Task 3 below cross-references S6 and S7.)*

**Tasks**:
1. Update `Sources/glosa/PreviewCommand.swift` to render a `breaths:` section per dialogue line that has any. Format exactly per spec §9:
   ```
   breaths: at <offset> (<length>, <strength>)
            at <offset> (<length>, <strength>)
   ```
2. Render breath lines only when `breathPoints` is non-empty. Suppress the section entirely otherwise.
3. Confirm `Sources/glosa/ScoreCommand.swift` writes breaths into the output file via the GlosaSerializer changes from Sorties 6–7 (no new flags or options).
4. **Resolve the CLI test target gap** (see Pass-4 finding below): the `glosa` executable target currently has no companion test target. Pick the lowest-cost option: (a) add a `glosaTests` test target in `Package.swift` (depends on `GlosaDirector`, `GlosaAnnotation`, `GlosaCore`) and place `PreviewCommandBreathTests.swift` there, OR (b) refactor `PreviewCommand`'s breath-rendering into a pure helper inside `GlosaAnnotation` and test the helper in `GlosaAnnotationTests`. Option (b) is preferred — it avoids spawning a new target and keeps the CLI a thin wrapper. The chosen option must be stated in the sortie commit message.
5. Add the breath-rendering test (per the option chosen in Task 4) that feeds the Bishop fixture through the rendering path and snapshot-asserts the breath block output. Snapshot must include the literal three lines `breaths: at 20 (period, strong)`, `         at 31 (comma, medium)`, `         at 43 (comma, medium)` (or the precise indentation the implementation produces, captured byte-for-byte in the snapshot).

**Exit criteria**:
- [ ] `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'` passes (run full suite to catch cross-cutting regressions).
- [ ] The new test asserts that rendering the Bishop fixture produces exactly three breath lines whose `at <offset>` values are `20`, `31`, `43` in that order.
- [ ] The new test asserts that rendering a screenplay with no breaths produces no `breaths:` substring in the output.
- [ ] `swift format -i -r Sources/glosa/ Sources/GlosaAnnotation/ Tests/` produces zero diff.

---

## WU8 — Documentation

### Sortie 12: Promote breath-tag.md into REQUIREMENTS.md

**Priority**: 1.5 — Pure cleanup/promotion; no downstream sorties.
**Context budget**: ~18 turns (right-sized).
**Parallel group**: G6 (single, supervising agent only).

**Entry criteria**:
- [ ] Sorties 1–11 all `COMPLETED`.

**Tasks**:
1. Add a new §1.4 to `Docs/REQUIREMENTS.md` titled `<breath>` element. The section summarizes (without restating verbatim) the element grammar, attributes, scope, format integration, LLM placement rules, and compilation output contract from `Docs/incomplete/breath-tag.md` §§4–7.
2. Update `Docs/REQUIREMENTS.md` §4.8 (Downstream Chunking) to reference §1.4 and note that the `CompilationResult.breathPoints` channel is now implemented in this repo. Cross-repo consumer wiring remains future work.
3. Update the spec source frontmatter: change `Docs/incomplete/breath-tag.md` frontmatter `state: incomplete` → `state: complete`, set `updated:` to today's date.
4. Move the file from `Docs/incomplete/breath-tag.md` to `Docs/complete/breath-tag.md` using `git mv`.
5. Update any cross-reference to `Docs/incomplete/breath-tag.md` in the repo (verify via `grep -r "Docs/incomplete/breath-tag.md"` after the move).

**Exit criteria**:
- [ ] `Docs/REQUIREMENTS.md` contains a `## 1.4` (or equivalent) section whose heading mentions `<breath>`.
- [ ] `Docs/REQUIREMENTS.md` §4.8 contains a link or reference to the new §1.4.
- [ ] `git ls-files Docs/incomplete/breath-tag.md` is empty; `git ls-files Docs/complete/breath-tag.md` returns the moved file.
- [ ] `grep -r "Docs/incomplete/breath-tag.md" . --exclude-dir=.git --exclude-dir=.build` returns no results.
- [ ] `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'` still succeeds (no Swift regressions from docs work).

---

## Open Questions & Missing Documentation

The three top-of-plan **open questions** (PascalCase casing, Fountain inline-note offsets, FDX mixed-content) are listed at the top and gated as entry criteria on the sorties that need them. They block dispatch until resolved.

Additional Pass-4 findings, classified per the refinement-pass schema:

| Sortie | Type | Description | Resolution |
|--------|------|-------------|------------|
| S1 | Vague criterion | "passes with at least 5 test methods" — acceptable lower bound but agents may game it. | Acceptable. Lower bound + the explicit list of cases (defaults, codable per `BreathLength` case, codable per `BreathStrength`, score round-trip) gives a clear floor. **Auto-resolved**: no change needed beyond the explicit case list already in Task 5. |
| S1 | Open question (entry) | Original entry mixed an informational note ("this sortie does not depend on the answer") with a blocking checkbox. | **Auto-fixed in Pass 4**: moved Q#1 to an informational note; entry checklist now only contains hard preconditions. |
| S10 | Vague criterion | "the rule 'Always insert here if the colon-list pattern exists'" — this is a literal substring assertion against the prompt, which depends on the spec wording surviving verbatim into the prompt. | Acceptable. The test grep is intentionally tied to spec §6.2 verbiage so prompt drift triggers a test failure. **No change**. |
| S11 | Missing test target | The `glosa` executable target has no companion `glosaTests` target. Sortie 11 originally hedged the test location ("wherever existing CLI tests live"). | **Auto-fixed in Pass 4**: Sortie 11 Task 4 now requires the agent to either (a) create a `glosaTests` target, or (b) refactor rendering into a `GlosaAnnotation` helper and test it there. Option (b) is preferred. Decision recorded in commit message. |
| S11 | Vague criterion | "snapshot-asserts the breath block" was not byte-precise. | **Auto-fixed in Pass 4**: exit criteria now name the specific `at <offset>` values (20, 31, 43) and the literal absence of `breaths:` for breath-free input. |
| S12 | External dependency (low) | `git mv Docs/incomplete/breath-tag.md Docs/complete/breath-tag.md` requires that the working tree is clean. | Acceptable. The sortie agent will be dispatched into a clean checkout per supervisor convention. **No change**. |

**No blocking issues remain.** All four refinement passes have completed.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 8 |
| Total sorties | 12 |
| Dependency structure | layered (Layer 0 → 5), with parallelism in groups G1, G3, G4 |
| Critical path length | 7 sorties (`S1 → S2 → S4 → S5 → S6 → S11 → S12`) |
| Max parallel sub-agents per group | 2 (supervising + 2, in worktree isolation) |
| Total context budget across sorties | ~224 turns; mean ~18.7 turns/sortie (budget 50) |
| In-scope packages | GlosaCore, GlosaAnnotation, GlosaDirector, glosa (CLI) |
| Out-of-scope | SwiftVoxAlta `chunkHints`, Produciesta `HeadlessAudioGenerator` (paired cross-repo mission) |
| Open questions blocking dispatch | 3 (see top of plan) — all gated as sortie entry criteria |
| Refinement passes complete | 1. Atomicity ✓ 2. Priority ✓ 3. Parallelism ✓ 4. Open questions ✓ |
