---
state: completed
updated: 2026-06-09
source: TODO.md
title: "Split <breath> into <breath> (phrasing) + <pause> (timed silence)"
kind: execution-plan
feature_name: OPERATION CLEAVING BREATH
starting_point_commit: 1672036493f163794a16e2bd2f2030df9bea8c67
mission_branch: mission/cleaving-breath/01
iteration: 1
---

# EXECUTION_PLAN.md — glosa-av: `<pause>` + `<breath>` split

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Summary

Separate the overloaded `<breath/>` element into two first-class GLOSA elements:

- **`<breath/>`** — silent sentence phrasing (chunk hint, `strength` only, ~0 silence).
- **`<pause/>`** — deliberate audible silence (`length` only, forces a chunk seam, always honored).

All decisions are **locked** in TODO.md §2/§7 (five original open questions resolved). This is an implementation-only mission. Cross-repo work (SwiftVoxAlta, Produciesta — TODO §6) is **out of scope** and tracked only.

**Build gate** (per CLAUDE.md): `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`
**Test gate**: `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'`
**Format before commit**: `swift format -i -r Sources/ Tests/`

---

## Decisions Resolved During Refinement

<!-- Pass 1 (refine-blockers) — these supersede the cited TODO decisions for this execution plan. -->

| # | Decision | Source | Supersedes |
|---|----------|--------|-----------|
| D-1 | **No migration.** Glosa is pre-release with no corpus to migrate. `<breath>` simply no longer accepts `length`; if present it is ignored with a parser warning. No `migrate-breath` CLI subcommand, no `<breath length>`→`Pause` conversion, no deprecation window, no `MigrationTests`. | User override of OQ-1 | TODO §2 Decision 3 (auto-migrate), Decision 6 (migration window), §3.7 |
| D-2 | **Split the docs.** `Docs/complete/breath-tag.md` splits into `breath-tag.md` (phrasing) + new `pause-tag.md` (timed silence); the conflated `length`-on-breath design is marked superseded inside `breath-tag.md`. | Accept OQ-2 recommendation | n/a |

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| GlosaCore | `Sources/GlosaCore` | 3 (S1–S3) | 1 | none |
| GlosaAnnotation | `Sources/GlosaAnnotation` | 1 (S4) | 2 | GlosaCore |
| GlosaDirector | `Sources/GlosaDirector` | 2 (S5–S6) | 3 | GlosaCore, GlosaAnnotation |
| glosa CLI | `Sources/glosa` | 1 (S7) | 4 | GlosaCore, GlosaAnnotation, GlosaDirector |
| Tests | `Tests/` | 2 (S8–S9) | 5 | all implementation work units |
| Docs | `Docs/`, repo root | 1 (S10) | 4 | GlosaDirector |

---

## Sortie Definitions

### Sortie 1: GlosaCore — data model (PauseLength, Pause, GlosaScore)

**Priority**: 32.0 — Highest. Transitively blocks all 9 downstream sorties; foundation sortie establishing `Pause`/`PauseLength` types reused everywhere. Must run first.

**Entry criteria**:
- [ ] First sortie — no prerequisites.

**Tasks** (TODO §3.1):
1. `Sources/GlosaCore/Breath.swift` — rename `BreathLength` → `PauseLength`, keeping every case, `explicit(TimeInterval)`, the `ms`/`s` parsing, and canonical encoding verbatim. Update the doc comment to describe it as a duration type owned by pause.
2. `Sources/GlosaCore/Breath.swift` — drop `length` from `struct Breath`; keep `sceneIndex`, `dialogueLineIndex`, `characterOffset`, `strength`; update the initializer accordingly.
3. `Sources/GlosaCore/Breath.swift` — keep `BreathStrength` unchanged (verify no `length` coupling remains).
4. New `Sources/GlosaCore/Pause.swift` — `struct Pause: Sendable, Equatable, Codable` with `sceneIndex`, `dialogueLineIndex`, `characterOffset`, `length: PauseLength` defaulting to `.period`; no `strength`. Mirror `Breath`'s doc style.
5. `Sources/GlosaCore/GlosaScore.swift` (~lines 52–58) — add `pauses: [Pause]` alongside `breaths: [Breath]`; update the memberwise init and Codable conformance as needed.

**Exit criteria**:
- [ ] `Sources/GlosaCore/Pause.swift` exists and declares `struct Pause` with `length: PauseLength`.
- [ ] `grep -r "BreathLength" Sources/` returns no matches; `PauseLength` is defined.
- [ ] `struct Breath` no longer has a `length` member; `GlosaScore` exposes both `breaths` and `pauses`.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 2: GlosaCore — parser (pause parsing + breath-length drop)

**Priority**: 27.5 — Transitively blocks 8 sorties; high-risk regex/parser work on the critical path.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met (`Pause`, `PauseLength`, `GlosaScore.pauses` exist; build green).

**Tasks** (TODO §3.2, §3.7 parser rule, as amended by D-1):
1. `Sources/GlosaCore/GlosaParser.swift` — Fountain: add a `<pause\b[^>]*/?>` branch to the inline `[[ ]]`-note regex (~line 420).
2. Add `extractPauses()` mirroring `extractBreaths()` (~lines 447–586), reusing the offset / `after=`-fallback machinery.
3. Add `parsePauseTag()` mirroring `parseBreathTag()` (~lines 608–710): parse `length` only; unknown `length` → warning diagnostic.
4. Update `parseBreathTag()` to **drop** `length` parsing entirely. `<breath>` no longer accepts `length`; if a `length` attribute is present, ignore it and emit a warning diagnostic ("`length` is not valid on `<breath>`; use `<pause>`"). **No migration to `Pause`** (D-1: glosa is pre-release, no corpus to migrate).
5. FDX: handle `<glosa:pause/>` in `FDXParserDelegate` alongside `<glosa:breath/>`.
6. Diagnostics: add a "`<pause/>` outside any dialogue line" warning mirroring breath's (~line 220).

**Exit criteria**:
- [ ] Parsing a Fountain line with `[[<pause length="period"/>]]` yields a `Pause` in the score's `pauses`.
- [ ] Parsing `[[<breath length="period"/>]]` yields a `Breath` (the `length` is ignored) plus a warning diagnostic; `[[<breath/>]]` yields a `Breath` with no diagnostic.
- [ ] FDX `<glosa:pause/>` is recognized by `FDXParserDelegate`.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 3: GlosaCore — compiler output (PausePoint + same-offset collapse)

**Priority**: 26.0 — Transitively blocks 7 sorties; establishes `PausePoint`; contains the same-offset collapse algorithm (moderate risk).

**Entry criteria**:
- [ ] Sortie 2 exit criteria met (parser emits `Pause`; build green).

**Tasks** (TODO §3.3):
1. `Sources/GlosaCore/CompilationResult.swift` — add `struct PausePoint { offset: Int; length: PauseLength }`.
2. `Sources/GlosaCore/CompilationResult.swift` — `struct BreathPoint`: drop `length`, keep `offset` + `strength`.
3. `Sources/GlosaCore/CompilationResult.swift` — add `pausePoints: [Int: [PausePoint]]` next to `breathPoints` (~lines 64–74).
4. `Sources/GlosaCore/GlosaCompiler.swift` (~lines 133–209) — add `mapPausesToAbsoluteLines()` mirroring `mapBreathsToAbsoluteLines()` (same scene-local → absolute projection, sorted by offset).
5. Same-offset collapse (Decision 4): after both projections, drop any `BreathPoint` whose `(line, offset)` coincides with a `PausePoint`, emitting an info diagnostic. Guarantee exactly one chunk seam per offset.

**Exit criteria**:
- [ ] `CompilationResult` exposes `pausePoints`; `BreathPoint` no longer carries `length`.
- [ ] Compiling a score with a `Pause` populates `pausePoints` with absolute-line keys.
- [ ] A co-located `<breath>`+`<pause>` compiles to a single `PausePoint` (no `BreathPoint`) plus an info diagnostic.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 4: GlosaAnnotation — bridge + serializer (pause round-trip)

**Priority**: 20.0 — Transitively blocks 5 sorties; establishes `pausePoints` on the annotated element (reused by S6/S9).

**Entry criteria**:
- [ ] Sortie 3 exit criteria met (`PausePoint`, `pausePoints`, collapse logic exist; build green).

**Tasks** (TODO §3.4):
1. `Sources/GlosaAnnotation/GlosaAnnotatedElement.swift` (~line 42) — add `pausePoints: [PausePoint]` next to `breathPoints` (empty for non-dialogue elements).
2. `Sources/GlosaAnnotation/GlosaSerializer.swift` — Fountain: add `injectPauseNotes()` + `pauseNoteTag()` mirroring `injectBreathNotes()` (~781–795) / `breathNoteTag()` (~813–828). Canonical form omits defaults (`length="period"` omitted for pause). No ordering tie-break needed — the compiler already collapsed co-located breaths.
3. `Sources/GlosaAnnotation/GlosaSerializer.swift` — update `breathNoteTag()` to no longer emit `length`; omit `strength="medium"` (the default) in canonical form.
4. `Sources/GlosaAnnotation/GlosaSerializer.swift` — FDX: emit `<glosa:pause/>` between `<Text>` runs (mirror `<glosa:breath/>`, ~860+).

**Exit criteria**:
- [ ] `GlosaAnnotatedElement` exposes `pausePoints`.
- [ ] Serializing a score with a `Pause` emits `[[<pause .../>]]` (Fountain) and `<glosa:pause/>` (FDX); a default-length pause omits `length`.
- [ ] `breathNoteTag()` emits no `length` attribute and omits default `strength`.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 5: GlosaDirector — annotation model + prompts

**Priority**: 18.0 — Transitively blocks 4 sorties; highest LLM-behavior risk (prompt rewrite); establishes `PauseAnnotation`.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met (annotation bridge + serializer carry pauses; build green).

**Tasks** (TODO §3.5, model + prompt portions):
1. `Sources/GlosaDirector/SceneAnnotation.swift` — `BreathAnnotation` (~69–121): drop `length`; keep `dialogueLineIndex`, `characterOffset`, `strength`.
2. `Sources/GlosaDirector/SceneAnnotation.swift` — add `PauseAnnotation` with `dialogueLineIndex`, `characterOffset`, `length`.
3. `Sources/GlosaDirector/SceneAnnotation.swift` — `SceneAnnotation`: add `pauses: [PauseAnnotation]` defaulting to `[]` for backward-compatible decode (same pattern as `breaths`).
4. `Sources/GlosaDirector/Prompts.swift` (~167–280) — split `breathPlacementSection`: keep breath trigger/placement rules but remove all `length` guidance (breath is now silent phrasing only).
5. `Sources/GlosaDirector/Prompts.swift` — add a new pause section: when to call a deliberate dramatic stop (colon-before-list, post-declaration beat) and which `length` to choose; re-cast the Bishop few-shot so the colon → `<pause length="period">` and the list commas → `<breath>`.

**Exit criteria**:
- [ ] `BreathAnnotation` has no `length`; `PauseAnnotation` exists with `length`; `SceneAnnotation.pauses` decodes as `[]` when absent.
- [ ] `Prompts.swift` breath guidance contains no `length` references; a distinct pause section exists with the re-cast Bishop few-shot.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 6: GlosaDirector — wire LLM annotation → annotated elements (Decision 7)

**Priority**: 12.0 — Transitively blocks 3 sorties (S7, S9, S10 entry); closes the known-broken breath mapping.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met (`PauseAnnotation`, `SceneAnnotation.pauses`, split prompts exist; build green).

**Tasks** (TODO §3.5 final bullet, Decision 7):
1. Wire `SceneAnnotation.breaths` → `GlosaAnnotatedElement.breathPoints`, closing the known-broken mapping flagged in REQUIREMENTS §1.4.
2. Wire `SceneAnnotation.pauses` → `GlosaAnnotatedElement.pausePoints`.
3. Ensure scene-local `characterOffset` values project correctly into the annotated elements, reusing the compiler's offset-projection conventions (no double-mapping).

**Exit criteria**:
- [ ] A `SceneAnnotation` carrying breaths and pauses produces a `GlosaAnnotatedElement` with populated `breathPoints` and `pausePoints` (verifiable via build + a smoke check in Sortie 9 tests).
- [ ] No code path leaves `breathPoints`/`pausePoints` empty when the annotation supplies them.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 7: glosa CLI — preview + score round-trip

**Priority**: 1.5 — Lowest. A leaf sortie that blocks nothing downstream; thin CLI surface. Kept in layer 4 for work-unit coherence, but may be deferred to run alongside or after the test sorties (see Parallelism Structure).

**Entry criteria**:
- [ ] Sortie 6 exit criteria met (LLM annotation path wired; build green).

**Tasks** (TODO §3.6):
1. `Sources/glosa/PreviewCommand.swift` — display pauses alongside breaths on their own line, formatted `at <offset> (<length>)`.
2. `Sources/glosa/ScoreCommand.swift` — confirm pauses round-trip (score already writes via the serializer); add no regression.

> **D-1**: the `glosa migrate-breath` subcommand from the original TODO §3.7 is **dropped** — glosa is pre-release with no corpus to migrate.

**Exit criteria**:
- [ ] `glosa preview` on a fixture containing a `<pause/>` prints a pause line with offset and length.
- [ ] `glosa score` on a file with pauses round-trips without loss.
- [ ] Build succeeds: `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 8: Tests — GlosaCore (parser, compiler, validator, codec)

**Priority**: 5.0 — Blocks S9. Depends only on S1–S3, so it can begin as soon as GlosaCore is green — earlier than its sortie number suggests (see Parallelism Structure).

**Entry criteria**:
- [ ] Sorties 1–3 exit criteria met (GlosaCore data model, parser, compiler complete).

**Tasks** (TODO §4, GlosaCore portion, as amended by D-1):
1. `Tests/GlosaCoreTests/PauseParserFountainTests.swift` — Fountain pause parsing.
2. `Tests/GlosaCoreTests/PauseParserFDXTests.swift` — FDX `<glosa:pause/>` parsing.
3. `Tests/GlosaCoreTests/PauseCompilerTests.swift` — pause projection **and** the same-offset collapse test (a `<breath>` at a `<pause>`'s offset is dropped with an info diagnostic; only the pause survives).
4. `Tests/GlosaCoreTests/PauseValidatorTests.swift` — "outside dialogue line" warning, unknown `length` warning, and the "`length` not valid on `<breath>`" warning (D-1).
5. `Tests/GlosaCoreTests/PauseTests.swift` — `PauseLength` codec (cases, `explicit`, `ms`/`s` parse, canonical encoding).
6. Update all `Tests/GlosaCoreTests/Breath*Tests` to remove `length` assertions.

> **D-1**: the original `MigrationTests.swift` is **dropped** — there is no migration behavior to test. The breath-`length`-ignored warning is covered by task 4 instead.

**Exit criteria**:
- [ ] All new and updated GlosaCore test files exist and assert the behaviors above.
- [ ] No `Breath*Tests` reference a `length` on `Breath`.
- [ ] A test asserts `[[<breath length="period"/>]]` parses to a `Breath` with a warning (no `Pause`).
- [ ] Tests pass: `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 9: Tests — downstream (annotation serializer/bridge/render, director, Bishop fixture)

**Priority**: 3.5 — Leaf sortie on the critical path's tail; verifies the full pipeline end-to-end.

**Entry criteria**:
- [ ] Sorties 4–6 exit criteria met (annotation + director paths complete).
- [ ] Sortie 8 exit criteria met (GlosaCore tests green).

**Tasks** (TODO §4, GlosaAnnotation + GlosaDirector portions):
1. `Tests/GlosaAnnotationTests/PauseSerializerFountainTests.swift` — Fountain emission, default-length omission.
2. `Tests/GlosaAnnotationTests/PauseSerializerFDXTests.swift` — FDX `<glosa:pause/>` emission.
3. `Tests/GlosaAnnotationTests/PauseBridgeTests.swift` — `pausePoints` on `GlosaAnnotatedElement`.
4. `Tests/GlosaAnnotationTests/PauseRenderTests.swift` — end-to-end render of pause markers.
5. `Tests/GlosaDirectorTests/PausePromptTests.swift` — pause section present, breath section length-free.
6. `Tests/GlosaDirectorTests/PauseSchemaTests.swift` — `PauseAnnotation` / `SceneAnnotation.pauses` schema + backward-compatible decode.
7. Mixed Bishop fixture: the new-vocabulary Bishop case (colon → `<pause length="period">`, list commas → `<breath>`) parses and round-trips parse → compile → serialize.

**Exit criteria**:
- [ ] All listed downstream test files exist and assert the behaviors above.
- [ ] The Bishop round-trip fixture test passes.
- [ ] Tests pass: `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'`.

---

### Sortie 10: Docs — element docs, REQUIREMENTS, README, AGENTS, changelog

**Priority**: 2.0 — Leaf, no build/test gate. **Sub-agent eligible** (the only no-build sortie); can run in parallel with S7–S9 once S6 is complete.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met (LLM wiring closed, so the "not yet wired" limitation can be retired).

**Tasks** (TODO §5, as amended by D-1 and D-2):
1. `Docs/complete/breath-tag.md` — per D-2, split into `breath-tag.md` (phrasing) + new `pause-tag.md` (timed silence); mark the conflated `length`-on-breath design as superseded.
2. `Docs/REQUIREMENTS.md` §1.4 — rewrite to describe two elements (add a §1.5 for pause or fold both under one "phrasing & pause" section); remove the LLM "not yet wired" limitation note now closed by Sortie 6 (Decision 7).
3. `README.md` — update the element list / architecture table.
4. `AGENTS.md` — update any GLOSA element reference.
5. `CHANGELOG.md` — record that `<breath/>` no longer accepts `length` (use `<pause/>` instead) as a change in the next development release. Per D-1 there is **no deprecation window** — glosa is pre-release, so the old `length`-on-breath form is dropped outright rather than migrated.

**Exit criteria**:
- [ ] `Docs/pause-tag.md` exists; `breath-tag.md` describes phrasing only and marks the old design superseded.
- [ ] `REQUIREMENTS.md` describes both elements and no longer claims the breath LLM→annotated mapping is unwired.
- [ ] `README.md` and `AGENTS.md` list both `<breath/>` and `<pause/>`.
- [ ] `CHANGELOG.md` records that `<breath/>` no longer accepts `length` (breaking change, no migration window).

---

## Parallelism Structure

**Critical Path**: Sortie 1 → 2 → 3 → 4 → 5 → 6 → 9 (length: **7 sorties**). S8 overlaps the S4–S6 stretch; S10 overlaps via a sub-agent; S7 is a leaf.

**Hard constraint — builds serialize on the supervising agent.** Every sortie except S10 carries a `xcodebuild build`/`test` gate, so they are **supervising-agent-only** and cannot be farmed to sub-agents. Sub-agents do not build. This caps real parallelism sharply.

**Parallel Execution Groups**:
- **Group A — GlosaCore chain (sequential, supervising agent)**: S1 → S2 → S3. Each builds on the prior; no intra-parallelism.
- **Group B — downstream impl (sequential, supervising agent)**: S4 → S5 → S6. Begins after S3.
- **Group C — GlosaCore tests (supervising agent)**: S8 depends only on S1–S3, so it can run **as soon as S3 is green**, concurrently with Group B on a second build-capable lane if available; otherwise interleaved by the supervising agent before S9.
- **Group D — docs (sub-agent)**: S10 has **no build/test gate** and depends only on S6. Once S6 is green, dispatch S10 to a sub-agent in parallel with S7/S8/S9.
- **Tail (supervising agent)**: S7 (leaf, after S6) and S9 (after S4–S6 + S8).

**Agent Constraints**:
- **Supervising agent**: all of S1–S9 (every one has a build or test step).
- **Sub-agents (up to 4, no build)**: S10 only. Documentation is the single farm-outable unit in this mission.

**Maximum useful parallelism**: 1 supervising agent + 1 sub-agent (S10). The build-gate constraint prevents wider fan-out; this is inherent to the mission, not a planning miss.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 6 |
| Total sorties | 10 |
| Open questions | 0 (both resolved — see Decisions Resolved During Refinement) |
| Critical path length | 7 sorties (S1→2→3→4→5→6→9) |
| Parallelism | 1 supervising agent + 1 sub-agent (S10 docs) |
| Dependency structure | layered (5 layers, sequential within GlosaCore) |
