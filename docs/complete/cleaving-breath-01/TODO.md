---
state: ready
updated: 2026-06-08
title: "Split <breath> into <breath> (phrasing) + <pause> (timed silence)"
kind: implementation-todo
---

# TODO — First-class `<pause>` + `<breath>` for sentence phrasing

The current `<breath/>` element conflates two unrelated concerns:

- **`length`** (`comma | semicolon | period | em-dash | beat | <n>ms`) — a *perceived
  pause duration*: how much silence to insert. This is really a **pause**.
- **`strength`** (`weak | medium | strong`) — *chunker priority*: where a long or
  structurally-tangled line gets split so the TTS model's speaker conditioning
  doesn't drift. This is really **phrasing / breath**.

This mission separates them into two first-class elements with distinct intent.

---

## 1. The two usages (definitions)

### 1.1 `<breath/>` — sentence phrasing (chunk hint)

A **silent** sub-utterance break point. It marks *where a long/tangled dialogue
line should be split* before the text reaches the TTS model, so each sub-utterance
stays inside the model's prosody-drift horizon. It adds **no audible silence** — it
only changes how the line is delivered to the model; the listener hears continuous
prose.

| Attribute | Required | Default | Values |
|---|---|---|---|
| `strength` | no | `medium` | `weak` (split only if needed to fit the budget), `medium` (split when the run exceeds the budget), `strong` (always split here) |

- **No `length` attribute.** Duration is never a breath concern. (Decision 2.)
- Positional marker, scoped to one dialogue line. Multiple per line allowed.
- A `<breath/>` outside any dialogue line is a parser warning and is ignored.
- Downstream: becomes a `ChunkHint` with `extraSilence = 0`, honored per `strength`.

```fountain
THE PRACTITIONER
He kept the parish quiet[[<breath/>]] and he kept the families quiet[[<breath/>]] and he kept the press quiet for thirty-two years.
```

### 1.2 `<pause/>` — first-class timed silence

A **deliberate, audible gap** of measured duration at a position. Because silence
can only be inserted at a chunk seam, a `<pause/>` **also forces a chunk boundary**
at its offset (it implies a split) and **always honored** (no `strength` knob — an
authored pause is intentional). (Decision 1.)

| Attribute | Required | Default | Values |
|---|---|---|---|
| `length` | no | `period` | `comma` (~150 ms), `semicolon` (~250 ms), `period` (~400 ms), `em-dash` (~600 ms), `beat` (~1000 ms), explicit `length="350ms"` / `length="0.4s"` |

- Punctuation-named durations describe *intent*; concrete ms calibration lives
  downstream (SwiftVoxAlta). Only the relative ordering is committed here.
- Default length is `period` (a bare `<pause/>` is a clear dramatic stop; `comma`
  is the breath-equivalent and barely audible, so it's a poor default for an
  element whose whole point is audible silence).
- Positional marker, scoped to one dialogue line. Multiple per line allowed.
- A `<pause/>` outside any dialogue line is a parser warning and is ignored.
- Downstream: becomes a `ChunkHint` with `extraSilence > 0` (length→ms map), always
  honored (effectively `strength = strong`).

```fountain
THE PRACTITIONER
Bishop is freighted:[[<pause length="period"/>]] authority,[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.
```

The colon gets a real dramatic stop (`<pause>`); the list commas get silent phrasing
breaks (`<breath>`) so the model has clean clause boundaries to predict against.

### 1.3 Downstream contract (single channel)

Both elements converge on **one** chunk-hint channel at the Produciesta/SwiftVoxAlta
boundary. Within glosa-av they stay distinct (for round-trip fidelity); the merge —
ordering by offset and mapping `Pause.length → ChunkHint.extraSilence`, breath →
`extraSilence = 0` — happens in Produciesta's `HeadlessAudioGenerator`. The symbolic
`length` is carried unmapped through glosa-av so the ms calibration stays downstream.

---

## 2. Decisions locked

1. **Pause splits + adds silence; breath splits with ~0 silence.** Both feed the one
   downstream `chunkHints` channel.
2. **`<breath>` is phrasing-only** — `strength` attribute only, no `length`.
3. **Auto-migrate** existing `<breath length=X>` where `X ≠ comma` → `<pause length=X>`;
   bare / `length="comma"` breaths stay `<breath/>`.
4. **Same-offset → collapse.** A `<pause>` already forces an unconditional chunk seam, so
   a `<breath>` at the identical offset is operationally redundant (its `strength` is moot
   when the seam is guaranteed). The parser/compiler drops the co-located breath and emits
   an info diagnostic. One `ChunkHint` per offset downstream. (Resolves Q1.)
5. **Default pause length = `period`** (~400 ms). A bare `<pause/>` is meant to be an
   audibly clear stop; `comma` is barely perceptible and a poor default for an element
   whose purpose is audible silence. (Resolves Q2.)
6. **Migration window: accept-with-warning through 0.4.x, remove in 0.5.0.** Breath shipped
   in 0.3.0 (weeks ago); corpus usage of `<breath length>` is minimal, so a one-minor-cycle
   deprecation is low-risk and avoids carrying dead parsing code forever. (Resolves Q3.)
7. **Fix the LLM→annotated wiring in this mission.** We're already editing `SceneAnnotation`,
   `Prompts.swift`, and the annotation bridge; wire both `breaths` and `pauses` from
   `SceneAnnotation` into `GlosaAnnotatedElement` rather than doubling a known-broken path.
   This is a deliberate (bounded) scope addition. (Resolves Q4.)
8. **Name the duration type `PauseLength`**, not a shared `SilenceLength`. Breath will never
   carry duration again (Decision 2), so a shared type is speculative generality. The
   public-API rename is acceptable pre-1.0 with no deprecation shim. (Resolves Q5.)

---

## 3. Implementation changes (by target / file)

### 3.1 GlosaCore — data model

- [ ] `Sources/GlosaCore/Breath.swift`
  - [ ] Rename `BreathLength` → `PauseLength` (keep cases + `explicit(TimeInterval)`
        + `ms`/`s` parsing + canonical encoding verbatim — it's a duration type, now
        owned by pause). Update doc comment.
  - [ ] Drop `length` from `struct Breath`; keep `sceneIndex`, `dialogueLineIndex`,
        `characterOffset`, `strength`. Update initializer.
  - [ ] Keep `BreathStrength` as-is.
- [ ] New `Sources/GlosaCore/Pause.swift`
  - [ ] `struct Pause: Sendable, Equatable, Codable` with `sceneIndex`,
        `dialogueLineIndex`, `characterOffset`, `length: PauseLength` (default `.period`).
        No `strength`. Mirror `Breath`'s doc style.
- [ ] `Sources/GlosaCore/GlosaScore.swift:52-58` — add `pauses: [Pause]` alongside
      `breaths: [Breath]`. Update memberwise init / Codable as needed.

### 3.2 GlosaCore — parser

- [ ] `Sources/GlosaCore/GlosaParser.swift`
  - [ ] Fountain: add a `<pause\b[^>]*/?>` branch to the inline-`[[ ]]`-note regex
        (currently `~line 420`) and an `extractPauses()` mirroring `extractBreaths()`
        (`447-586`), reusing the offset/`after=`-fallback machinery.
  - [ ] Add `parsePauseTag()` mirroring `parseBreathTag()` (`608-710`): parse `length`
        only; unknown `length` → warning.
  - [ ] Update `parseBreathTag()` to **drop** `length` parsing; if a `length` attr is
        present on `<breath>`, apply the migration rule (§3.7) and emit an info/deprecation
        diagnostic.
  - [ ] FDX: handle `<glosa:pause/>` in `FDXParserDelegate` alongside `<glosa:breath/>`.
  - [ ] Diagnostics: add "`<pause/>` outside any dialogue line" warning (mirror
        breath's, `~line 220`).

### 3.3 GlosaCore — compiler output

- [ ] `Sources/GlosaCore/CompilationResult.swift`
  - [ ] Add `struct PausePoint { offset: Int; length: PauseLength }`.
  - [ ] `struct BreathPoint` — drop `length`, keep `offset` + `strength`.
  - [ ] Add `pausePoints: [Int: [PausePoint]]` next to `breathPoints` (`64-74`).
- [ ] `Sources/GlosaCore/GlosaCompiler.swift:133-209` — add `mapPausesToAbsoluteLines()`
      mirroring `mapBreathsToAbsoluteLines()` (same scene-local→absolute projection,
      sort by offset).
- [ ] Same-offset collapse (Decision 4): after both projections, drop any `BreathPoint`
      whose `(line, offset)` coincides with a `PausePoint`, emitting an info diagnostic.
      Guarantees one chunk seam per offset downstream.

### 3.4 GlosaAnnotation — bridge + serializer

- [ ] `Sources/GlosaAnnotation/GlosaAnnotatedElement.swift:42` — add
      `pausePoints: [PausePoint]` next to `breathPoints` (empty for non-dialogue).
- [ ] `Sources/GlosaAnnotation/GlosaSerializer.swift`
  - [ ] Fountain: add `injectPauseNotes()` + `pauseNoteTag()` mirroring
        `injectBreathNotes()` (`781-795`) / `breathNoteTag()` (`813-828`). Per Decision 4
        the compiler has already collapsed any co-located breath into the pause, so the
        serializer never sees both at one offset — no ordering tie-break needed. Canonical
        form omits defaults (`length="period"` omitted for pause; `strength="medium"`
        omitted for breath).
  - [ ] FDX: emit `<glosa:pause/>` between `<Text>` runs (mirror `<glosa:breath/>`, `860+`).
  - [ ] Update `breathNoteTag()` to no longer emit `length`.

### 3.5 GlosaDirector — LLM annotation

- [ ] `Sources/GlosaDirector/SceneAnnotation.swift`
  - [ ] `BreathAnnotation` (`69-121`) — drop `length`; keep `dialogueLineIndex`,
        `characterOffset`, `strength`.
  - [ ] Add `PauseAnnotation` (`dialogueLineIndex`, `characterOffset`, `length`).
  - [ ] `SceneAnnotation` — add `pauses: [PauseAnnotation]` (default `[]` for
        backward-compatible decode, same pattern as breaths).
- [ ] `Sources/GlosaDirector/Prompts.swift:167-280` — split `breathPlacementSection`:
  - [ ] Breath section: keep trigger/placement rules, but breath is now *silent phrasing
        only* — remove all `length` guidance.
  - [ ] New pause section: when to call a deliberate dramatic stop (colon-before-list,
        post-declaration beat, etc.) and which `length` to choose. Re-cast the Bishop
        few-shot: colon → `<pause length="period">`, list commas → `<breath>`.
- [ ] Wire `SceneAnnotation.breaths` **and** `.pauses` → `GlosaAnnotatedElement.breathPoints`
      / `.pausePoints` (Decision 7). REQUIREMENTS §1.4 flags the breath LLM→annotated mapping
      as *not yet wired*; close that gap here for both elements and drop the limitation note
      from REQUIREMENTS (§5 below).

### 3.6 CLI

- [ ] `glosa preview` — display pauses alongside breaths (own line, `at <offset> (<length>)`).
- [ ] `glosa score` — already writes via serializer; confirm pauses round-trip.

### 3.7 Migration (`<breath length=X>` → `<pause length=X>`)

- [ ] Parser rule: `<breath>` with `length` present and `≠ comma` → emit a `Pause` at that
      offset with that `length`. Any `strength` on such a tag is **dropped** — at a pause
      seam strength is moot (Decision 4), so there is no "emit both" case. `length="comma"`
      or absent → plain `<breath/>` (strength preserved). Emit a deprecation diagnostic so
      the corpus gets flagged.
- [ ] One-shot rewrite: a `glosa migrate-breath` subcommand (or a documented `glosa score`
      pass) that reads → parses → serializes so files land on the new vocabulary.
- [ ] Migration window (Decision 6): parser accepts `<breath length>` with a deprecation
      warning through **0.4.x**, removed in **0.5.0**. Add a CHANGELOG note and a removal
      tracking item for 0.5.0.

---

## 4. Tests

Mirror the 11 existing breath test files with pause equivalents, update breath tests
to drop `length`, and add migration tests.

- [ ] `GlosaCoreTests/PauseParserFountainTests.swift`, `PauseParserFDXTests.swift`,
      `PauseCompilerTests.swift`, `PauseValidatorTests.swift`, `PauseTests.swift`
      (PauseLength codec).
- [ ] `GlosaAnnotationTests/PauseSerializerFountainTests.swift`,
      `PauseSerializerFDXTests.swift`, `PauseBridgeTests.swift`, `PauseRenderTests.swift`.
- [ ] `GlosaDirectorTests/PausePromptTests.swift`, `PauseSchemaTests.swift`.
- [ ] Update all `Breath*Tests` to remove `length` assertions.
- [ ] New `MigrationTests`: `<breath length="period" strength="strong"/>` →
      `<pause length="period"/>` (strength dropped); `<breath/>` and `<breath length="comma"/>`
      → unchanged `<breath/>` (strength preserved).
- [ ] Collapse test: a `<breath>` at the same offset as a `<pause>` is dropped (info
      diagnostic), and only the `<pause>` survives parse → compile → serialize.
- [ ] Mixed fixture: Bishop case in the new vocabulary parses + round-trips.

## 5. Docs

- [ ] `Docs/complete/breath-tag.md` — supersede or split into `breath-tag.md`
      (phrasing) + new `pause-tag.md` (timed silence). Mark the conflated `length`-on-breath
      design as superseded.
- [ ] `Docs/REQUIREMENTS.md` §1.4 — rewrite to describe two elements; add a §1.5 for pause
      or fold both under one "phrasing & pause" section.
- [ ] `README.md` — update the element list / architecture table.
- [ ] `AGENTS.md` — update any GLOSA element reference.

## 6. Cross-repo (paired mission — out of scope here, track only)

- [ ] SwiftVoxAlta `GenerationContext.chunkHints` — already specced (breath-tag.md §8.2);
      `ChunkHint.extraSilence` carries the pause duration, breath → 0.
- [ ] Produciesta `HeadlessAudioGenerator` — merge `breathPoints` + `pausePoints` into a
      single offset-ordered `chunkHints`, mapping `PauseLength → extraSilence` per
      SwiftVoxAlta's calibration table.

---

## 7. Resolved decisions (rationale log)

All five original open questions are resolved; the answers are wired into §2 (Decisions
locked) and the implementation/test sections above. Rationale preserved here.

1. **Same-offset → collapse** (was: collapse vs keep both). A `<pause>` forces an
   unconditional seam, so a co-located `<breath>` adds nothing — its `strength` only ever
   matters as a tie-break for *optional* seams. Drop the breath, emit an info diagnostic.
   Cascade: simplifies migration (no "emit both") and the serializer (no tie-break order).
2. **Default pause length `period`** (was: confirm `period`). Bare `<pause/>` must read as a
   clear audible stop; `comma` is sub-perceptible and a bad default for a silence element.
3. **Deprecate, don't keep forever** (was: window vs permanent alias). `<breath length>`
   accepted-with-warning through 0.4.x, removed 0.5.0. Breath shipped weeks ago (0.3.0), so
   corpus exposure is tiny; a permanent alias would freeze dead parsing code and let mixed
   vocabulary persist indefinitely.
4. **Fix LLM wiring now** (was: fix vs defer). We're already in `SceneAnnotation`,
   `Prompts.swift`, and the bridge; closing the existing breath gap (REQUIREMENTS §1.4)
   while adding pauses is cheaper than shipping two half-wired paths. The one deliberate
   scope addition.
5. **`PauseLength`, no shared type** (was: `PauseLength` vs `SilenceLength`). Breath never
   carries duration again (Decision 2), so a shared type is speculative generality. Pre-1.0
   public-API rename is acceptable without a deprecation shim.
