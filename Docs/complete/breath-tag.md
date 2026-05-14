---
state: complete
updated: 2026-05-13
title: "<breath> tag — sub-utterance chunk hints"
kind: feature-spec
---

# `<breath>` — Sub-Utterance Chunk Hints

**State:** complete — implemented in GlosaCore, GlosaAnnotation, GlosaDirector, and the `glosa` CLI (compile path). Cross-repo consumer wiring (SwiftVoxAlta `chunkHints`, Produciesta `HeadlessAudioGenerator`) is future work in a paired mission.

A new GLOSA element that marks where a single dialogue line should be split into sub-utterances before being sent to the TTS model. The writer's prose is unchanged; the *delivery* to the model is changed. This closes the gap flagged in `Docs/REQUIREMENTS.md` §4.8 (Downstream Chunking) for sentences that are structurally tangled below the auto-chunker's sentence-boundary horizon.

---

## 1. Problem statement

See `../../../podcast-confessions/episodes/episode_55.fountain` ("PROSODY TRAP") for the full root-cause discussion. The short version:

- Qwen3-TTS (and similar ICL-cloned voices) maintain speaker conditioning by predicting cadence, breath, and pitch contour from **local syntactic structure** — commas, periods, conjunctions, clause boundaries, parallel members.
- When the local structure is ambiguous (a colon followed by an asyndetic list with non-parallel members; a run-on chaining five clauses with "and"; a 600-character single sentence with no internal stops), the model's prosody prediction error compounds.
- Breath lands inside a phrase instead of between phrases. Pitch contour goes flat where it should rise. By the time you reach the end of the long span, the speaker prompt has drifted into a different prosodic register.
- SwiftVoxAlta's auto-chunker (see [REQUIREMENTS.md §4.8](../REQUIREMENTS.md)) splits at sentence boundaries (period/question/exclamation). It does **not** help when the structurally-tangled span is a single sentence.

**Episode 55's conclusion**, which is the design constraint for this feature:

> "The writer's text is unchanged. What the model receives is a sequence of smaller utterances, each with the same speaker prompt, each well inside the drift horizon. … The tool serves the writer. Not the reverse."

The writer doesn't fix run-ons. The tool inserts sub-utterance breaks before the model sees the text, audio reassembles seamlessly, the listener hears prose.

---

## 2. Goals and non-goals

**In scope:**
- A new GLOSA element, `<breath>`, that marks a sub-utterance break point inside a dialogue line.
- LLM (Stage Director) auto-placement of `<breath>` markers at syntactic breakpoints in long/tangled sentences.
- Optional hand-authoring of `<breath>` markers by the writer.
- A new output channel in `CompilationResult` and `GlosaAnnotatedElement` that exposes breath-point offsets per line.
- Round-trip serialization in Fountain and FDX.

**Out of scope (for v1):**
- Audible breath synthesis (inhale sounds, sighs) — `<breath>` is a *silent* chunk hint, not a vocalization directive. If audible breath becomes desirable later, it joins via an attribute (e.g., `kind="audible"`).
- Intra-line emotional gradient — flagged in §4.8 as future work. `<breath>` is orthogonal: it changes chunking, not instruct content.
- Downstream playback / drift-detection / re-take logic — Episode 55 sketches that loop, but it lives in Produciesta / SwiftVoxAlta, not glosa-av.

---

## 3. Naming question

Episode 55 calls the phenomenon "breath." That is the semantic intent (a place where a human reader would draw breath), so the element is named `<breath>`.

**Inconsistency to flag**: the existing three GLOSA elements use PascalCase (`<SceneContext>`, `<Intent>`, `<Constraint>`). Strict consistency would name the new one `<Breath>`. The lower-case form is preferred here because:

1. The existing three describe *who/what/how* — they are nominal categories.
2. `<breath>` describes a *moment* — it is a marker punctuation more than a directive. HTML uses `<br/>` lowercase for the same reason.
3. Lowercase reads naturally inline: `Bishop is freighted: [[<breath/>]] authority, [[<breath/>]] patriarchy, …`

If consistency wins out, rename to `<Breath>` is trivial — single token in the parser. The rest of this document uses `<breath>`.

---

## 4. Element specification

### 4.1 Grammar

`<breath>` is a **marker tag** with no closing tag, written self-closing.

```xml
<breath/>
```

In Fountain: embedded in a note block at the desired position.
In FDX: a self-closing XML element in the `glosa:` namespace.

### 4.2 Attributes

| Attribute | Required | Default | Description |
|---|---|---|---|
| `length` | no | `comma` | Target perceived pause duration. Named presets are punctuation-mapped so writers can reason about them without ms math. `comma` (default — same gap a comma would produce, ~150 ms perceived), `semicolon` (~250 ms), `period` (~400 ms), `em-dash` (~600 ms), `beat` (~1000 ms). Explicit values also accepted: `length="350ms"` or `length="0.4s"`. |
| `strength` | no | `medium` | Relative weight when downstream chunkers must trade off competing breath candidates against the chunker's character-budget heuristics. Orthogonal to `length`. `weak` (only chunk here if necessary to fit the budget), `medium` (default — chunk here when the run exceeds the budget), `strong` (always chunk here regardless of budget). |

All attributes are optional. A bare `<breath/>` is a comma-length, medium-strength chunk hint.

**Note on the named values:** the punctuation labels describe *intent*, not exact ms values — the calibration of "what does a comma actually sound like at this voice / this model" lives downstream and may differ between voices. The requirements only commit to the relative ordering (`comma < semicolon < period < em-dash < beat`) and the user-facing mental model. Concrete millisecond defaults are a SwiftVoxAlta tuning parameter.

**Future-reserved:** audible breath (a vocalized inhale sound, not just silence) is intentionally **not** an option for `length` — it's a different axis. If/when it ships, it joins via a separate attribute (e.g., `voice="inhale"`) so a writer can say "inhale, period-length" without overloading either attribute.

### 4.3 Scope

`<breath>` is a **positional marker** scoped to a single dialogue line. It applies at the exact textual offset where it appears within the dialogue, between the `[[ ]]` notes that precede and follow it (Fountain), or as an inline child of `<Dialogue>` (FDX).

`<breath>` does **not** nest inside `<Intent>` or `<Constraint>` semantically — it lives at a different layer (chunking, not instruct content). Multiple `<breath/>` markers can appear in one dialogue line.

A `<breath/>` outside any dialogue line is a parser warning and is ignored.

---

## 5. Format integration

### 5.1 Fountain

`<breath/>` lives inside an inline `[[ ]]` note placed at the breath position within the dialogue text. The Fountain renderer strips `[[ ]]` notes; the on-page text is the writer's original prose. The GLOSA parser uses the inline note positions to anchor breath offsets to the dialogue text.

**Example 1 — colon followed by an asyndetic list (the Bishop case from episode 51).** A dramatic stop after the colon, then chunking-only breaths between list items:

```fountain
THE PRACTITIONER
Bishop is freighted:[[<breath length="period" strength="strong"/>]] authority,[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.
```

The first breath is `length="period"`, `strength="strong"` — the writer (or Stage Director) is calling for a dramatic pause that the chunker must honor regardless of budget. The remaining two are bare `<breath/>` (defaults: `length="comma"`, `strength="medium"`) — they exist mainly to give the model clean clause boundaries to predict against.

**Example 2 — run-on with chained coordinating conjunctions (the episode 51 case).** All breaks are commas; the goal is just to keep each sub-utterance well inside the drift horizon:

```fountain
THE PRACTITIONER
He kept the parish quiet[[<breath/>]] and he kept the families quiet[[<breath/>]] and he kept the press quiet[[<breath/>]] and he kept the diocese quiet for thirty-two years[[<breath/>]] and then a single deposition undid every one of those silences in a single afternoon.
```

Each `<breath/>` is bare — comma length, medium strength — placed immediately before the coordinating conjunction (per §6.2 rule 3, the breath goes after the previous clause, before the `and`).

**Example 3 — mixed lengths and explicit ms.** Hand-authored, showing the full attribute surface:

```fountain
ESPECTRO FAMILIAR
The model has been making bad predictions for nine seconds.[[<breath length="em-dash" strength="strong"/>]] The speaker prompt has drifted because the local cues have been pulling the model into a different prosodic register the whole time.[[<breath length="350ms"/>]] You wrote a run-on.
```

**Upstream dependency to verify:** SwiftCompartido's `FountainParser` must surface the character offset of each `[[ ]]` note within its enclosing dialogue paragraph. If the current parser collapses notes without preserving position, we need to extend it before this feature can ship. (See Open Questions.)

**Alternative encoding** if inline positioning isn't viable: a sibling note block with explicit positioning:

```fountain
THE PRACTITIONER
Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
[[<breath after="Bishop is freighted:"/>]]
[[<breath after="authority,"/>]]
[[<breath after="patriarchy,"/>]]
```

`after=` matches a substring; the breath is placed at the end of the first occurrence. This is more brittle to writer edits but doesn't depend on inline-position support.

Recommended path: support inline `[[<breath/>]]` as primary; allow `after=` as fallback.

### 5.2 FDX

In FDX, `<glosa:breath/>` appears as a self-closing element inline within `<Paragraph Type="Dialogue"><Text>`:

```xml
<Paragraph Type="Dialogue">
  <Text>Bishop is freighted: </Text>
  <glosa:breath/>
  <Text>authority, </Text>
  <glosa:breath/>
  <Text>patriarchy, </Text>
  <glosa:breath/>
  <Text>a history of cover-ups and anti-queer theology.</Text>
</Paragraph>
```

FDX `<Text>` elements already support being broken up for formatting (style runs). The `<glosa:breath/>` element inserts cleanly between `<Text>` runs and is ignored by Final Draft (unknown namespace, per FDX namespace rules).

### 5.3 Highland

Highland files contain Fountain inside a ZIP; the Fountain rules in §5.1 apply unchanged.

---

## 6. LLM placement rules (Stage Director)

The Stage Director (`GlosaDirector.StageDirector`) is responsible for analyzing each dialogue line and emitting `<breath/>` annotations when warranted. The placement logic is encoded in the LLM's system prompt and the structured-output schema; the LLM never emits raw SGML — it returns offset-keyed annotations that the serializer renders.

### 6.1 Trigger conditions

The LLM considers a dialogue line as a `<breath>` candidate when **any** of the following hold:

1. The line exceeds a character threshold. Suggested initial threshold: **180 characters** (matches VoxAlta's per-chunk budget at 0.055 s/char ≈ 10 s). Tunable in `VocabularyGlossary` or a per-project config.
2. The line is a single sentence (no internal `.`, `?`, `!`) longer than **120 characters** and contains at least one of:
   - A colon followed by a list (asyndetic or otherwise).
   - Three or more clauses joined by coordinating conjunctions (`and`, `but`, `or`, `so`, `yet`).
   - A semicolon-joined compound sentence.
3. The line contains a coordinating conjunction whose scope ambiguity is detectable — e.g., a final list item that contains its own `and` (the "Bishop" case: `authority, patriarchy, a history of cover-ups and anti-queer theology`).

Lines that don't satisfy any trigger get no `<breath/>` annotations. Short, structurally clean sentences (`I noticed.`, `Yeah.`) never need them.

**Negative example.** The Stage Director sees this dialogue line:

```fountain
THE PRACTITIONER
I noticed.
```

11 characters, single clause, no list, no chained conjunctions, no colon. None of §6.1's conditions fire. The LLM emits zero `BreathAnnotation` records for this line. Auto-chunking does not engage. The model receives the line verbatim and synthesizes it as a single utterance, well below its drift horizon.

### 6.2 Placement rules (where to put the break)

When a line triggers, the LLM places `<breath/>` markers at syntactic breakpoints, in priority order:

1. **After a colon that introduces a list.** Always insert here if the colon-list pattern exists. (Bishop case.)
2. **After a semicolon.** Sentence-internal stops are natural breath points.
3. **Between clauses of a compound sentence**, immediately before the coordinating conjunction. Two sub-cases:
   - **With a comma** (`, and` / `, but` / `, or` / `, so` / `, yet`): the breath goes *after* the comma, *before* the conjunction word.
   - **Polysyndetic without commas** (`… quiet and he kept …`, the episode 55 run-on case): the breath goes between the previous clause and the conjunction word — i.e., before the conjunction directly.
   In both forms, the conjunction stays in the second chunk.
4. **Between list items** in an asyndetic or polysyndetic list, after each comma separating top-level items. Do **not** chunk inside a list item even if it contains commas internally.
5. **Before a long subordinate clause** introduced by `which`, `that`, `because`, `although`, `when`, `while`, when the matrix clause is itself ≥ 60 characters.

The LLM should **not** place `<breath/>`:

- Between an adjective and the noun it modifies.
- Between a verb and a short direct object (< 30 chars).
- Inside a noun phrase.
- Inside a quoted string.
- Within 10 characters of the line's start or end.
- Closer than 30 characters to another `<breath/>`.

### 6.3 LLM structured-output schema

Extend `SceneAnnotation` (defined in `Sources/GlosaDirector/SceneAnnotation.swift`) with a `breaths` field:

```swift
public struct SceneAnnotation: Codable, Sendable {
    public let sceneContext: SceneContext
    public let intents: [IntentAnnotation]
    public let constraints: [ConstraintAnnotation]
    public let breaths: [BreathAnnotation]    // NEW
}

public struct BreathAnnotation: Codable, Sendable {
    /// Index of the dialogue line (within the scene) this breath applies to.
    public let dialogueLineIndex: Int

    /// Character offset within the dialogue line text where the break goes.
    /// 0 = before first character; line.count = after last character (invalid).
    public let characterOffset: Int

    /// Optional: target pause duration (default .comma).
    public let length: BreathLength?

    /// Optional: chunker priority (default .medium).
    public let strength: BreathStrength?
}
```

Few-shot examples in the prompt should include at least one positive case (the Bishop sentence, decomposed) and one negative case (a short line with no breaths).

### 6.4 Worked example: structured output for the Bishop scene

Given this raw dialogue line (line index 0 within its scene):

```
Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
```

…the Stage Director should emit the following `SceneAnnotation` (rendered as the JSON the LLM returns via SwiftBruja's structured output, then decoded by `GlosaDirector`):

```json
{
  "sceneContext": {
    "location": "the rectory office",
    "time": "late afternoon",
    "ambience": "muted, formal"
  },
  "intents": [
    {
      "from": "controlled",
      "to": "indicting",
      "pace": "moderate",
      "scoped": true,
      "lineRange": [0, 0]
    }
  ],
  "constraints": [
    {
      "character": "THE PRACTITIONER",
      "direction": "measured, cataloging — the prosecutor reading a charge sheet",
      "ceiling": "moderate"
    }
  ],
  "breaths": [
    {
      "dialogueLineIndex": 0,
      "characterOffset": 20,
      "length": "period",
      "strength": "strong"
    },
    {
      "dialogueLineIndex": 0,
      "characterOffset": 31,
      "length": "comma",
      "strength": "medium"
    },
    {
      "dialogueLineIndex": 0,
      "characterOffset": 43,
      "length": "comma",
      "strength": "medium"
    }
  ]
}
```

Offset reading (using the convention from §6.3 — `characterOffset` is the index of the character that comes **after** the break):

- `20` — break immediately after the colon (between `:` at index 19 and the space at index 20). The first chunk ends with the colon; the second chunk starts with ` authority,…`. `length: "period"` calls for a dramatic stop the chunker must honor (`strength: "strong"`).
- `31` — break between `,` (index 30) and the space at index 31. First chunk: `…authority,`. Second chunk: ` patriarchy,…`. Default comma length.
- `43` — break between `,` (index 42) and the space at index 43. First chunk: `…patriarchy,`. Second chunk: ` a history of cover-ups and anti-queer theology.`. Default comma length.

The downstream pipeline reassembles the four chunks with the calibrated extra-silence per `length` (see §8.2). The listener hears clean enumeration; the writer's prose is preserved on the page exactly as written.

### 6.5 Glossary integration

Add a `breathThreshold: Int` field to `VocabularyGlossary` so projects can tune the trigger character-budget per podcast (some voices and some content survive longer single utterances better than others).

---

## 7. Compiler / Annotation impact

### 7.1 GlosaCore: data model

Add `Breath` to `GlosaScore`:

```swift
public struct Breath: Sendable, Equatable {
    public let dialogueLineIndex: Int
    public let characterOffset: Int
    public let length: BreathLength        // .comma (default) | .semicolon | .period | .emDash | .beat | .explicit(TimeInterval)
    public let strength: BreathStrength    // .weak | .medium | .strong
}

public enum BreathLength: Sendable, Equatable {
    case comma                             // default — ~150 ms perceived pause
    case semicolon                         // ~250 ms
    case period                            // ~400 ms
    case emDash                            // ~600 ms
    case beat                              // ~1000 ms
    case explicit(TimeInterval)            // exact value from `length="350ms"` / `length="0.4s"`
}
```

`GlosaScore` gains a `breaths: [Breath]` collection alongside `scenes`.

### 7.2 GlosaCore: parser

`GlosaParser` extracts `<breath/>` from both Fountain (inline `[[ ]]` notes) and FDX (`glosa:breath` elements). For Fountain, the parser needs the inline-note character offset (see §5.1 dependency note); for FDX, the offset is derived from the text run that precedes the element.

### 7.3 GlosaCore: resolver

`ScoreResolver` does **not** consume `<breath/>` directly — breath is structural, not directive. The resolver produces `ResolvedDirectives` unchanged; breath flows through a parallel channel.

### 7.4 GlosaCore: compiler output

Extend `CompilationResult`:

```swift
public struct CompilationResult {
    public let instructs: [Int: String]
    public let diagnostics: [GlosaDiagnostic]
    public let provenance: [InstructProvenance]

    /// NEW: per-line breath points, as character offsets into the dialogue text,
    /// sorted ascending. Empty array means no chunk hints for that line.
    public let breathPoints: [Int: [BreathPoint]]
}

public struct BreathPoint: Sendable, Equatable {
    public let offset: Int
    public let length: BreathLength
    public let strength: BreathStrength
}
```

Per [REQUIREMENTS.md §4.8](../REQUIREMENTS.md), this extends the contract but does not break it — `instructs` keeps its current per-line shape, and downstream consumers that ignore `breathPoints` behave identically to today.

### 7.5 GlosaAnnotation: element bridge

Extend `GlosaAnnotatedElement` so every dialogue element carries its breath points:

```swift
public struct GlosaAnnotatedElement: Sendable {
    public let element: GuionElement
    public let directives: ResolvedDirectives?
    public let instruct: String?
    public let breathPoints: [BreathPoint]   // NEW. Empty for non-dialogue.
}
```

### 7.6 GlosaSerializer

Round-trip: `GlosaAnnotatedScreenplay` → Fountain (with inline `[[<breath/>]]` notes at the right offsets) → parse again → identical `breathPoints`. Same for FDX. Round-trip tests are mandatory.

### 7.7 GlosaValidator

Diagnostics:
- **Warning**: `<breath/>` outside any dialogue line.
- **Warning**: two `<breath/>` markers at the same offset.
- **Info**: a dialogue line that triggers §6.1 conditions but has no `<breath/>` annotations (suggests Stage Director missed it).

---

## 8. Downstream contract (SwiftVoxAlta / Produciesta)

This is a cross-package coordination item. The `<breath>` feature is useless unless SwiftVoxAlta honors the chunk hints.

### 8.1 Today's contract

Per [REQUIREMENTS.md §4.8](../REQUIREMENTS.md): VoxAlta auto-chunks at sentence boundaries inside `VoiceLockManager.generateAudio()`. The chunker is invisible to Produciesta.

### 8.2 Proposed contract change

`GenerationContext` (defined in SwiftVoxAlta) grows an optional field:

```swift
public struct GenerationContext {
    public let phrase: String
    public let instruct: String?
    public let chunkHints: [ChunkHint]?    // NEW. Nil = auto-chunk at sentence boundaries (today's behavior).
}

public struct ChunkHint {
    public let offset: Int                  // Character offset into `phrase`.
    public let strength: ChunkStrength      // weak | medium | strong
    public let extraSilence: TimeInterval?  // For kind=.pause/.beat, additional silence to pad on reassembly.
}
```

When `chunkHints` is non-nil, the VoxAlta chunker uses them as candidate split points (filtered by the chunker's char-budget heuristics, respecting `strength`). When nil, current behavior is preserved.

Produciesta's `HeadlessAudioGenerator` constructs `chunkHints` from `GlosaAnnotatedElement.breathPoints` when GLOSA annotations are present, mapping each `BreathPoint.length` to a `ChunkHint.extraSilence` per the SwiftVoxAlta-side calibration table (initial suggestion: `.comma` → 0 ms, `.semicolon` → ~100 ms, `.period` → ~250 ms, `.emDash` → ~450 ms, `.beat` → ~850 ms, `.explicit(t)` → `t` minus the model's natural chunk-end trailing silence). The exact numbers are SwiftVoxAlta's responsibility to calibrate against the model's measured natural inter-chunk gap.

### 8.3 Backwards compatibility

Existing screenplays without `<breath/>` annotations get `chunkHints: nil` (or `[]`) → unchanged behavior. The feature is purely additive.

---

## 9. CLI surface

`glosa preview` should display breath points alongside resolved directives so authors can sanity-check what the Stage Director did:

```
Line 12: THE PRACTITIONER
  text:    Bishop is freighted: authority, patriarchy, a history of cover-ups …
  intent:  controlled → indicting (arc 0.3)
  breaths: at 20 (period, strong)
           at 31 (comma, medium)
           at 43 (comma, medium)
  instruct: "Controlled, early in arc toward indicting, moderate pace. …"
```

`glosa score` writes breaths into the output Fountain/FDX file alongside other GLOSA annotations. No new flags or subcommands are required.

---

## 10. Implementation plan (sortie-sized chunks)

1. **Data model + parser** — Add `Breath`, `BreathKind`, `BreathStrength` to `GlosaCore`. Extend `GlosaParser` for Fountain (inline `[[ ]]` notes) and FDX (`glosa:breath` namespace element). Tests: parse fixtures with breaths, verify offsets.
2. **Compiler output** — Extend `CompilationResult.breathPoints`. Resolver unchanged. Tests: end-to-end compile produces correct offsets per line.
3. **Annotation bridge** — Extend `GlosaAnnotatedElement.breathPoints`. Update `GlosaSerializer` round-trip for both formats. Tests: round-trip fidelity.
4. **Stage Director** — Extend `SceneAnnotation` Codable schema with `breaths`. Update system prompt with the trigger and placement rules from §6. Few-shot examples. Tests: annotate the Bishop fixture, verify expected breath positions.
5. **CLI** — `glosa preview` displays breath points.
6. **Documentation** — Promote this doc into `REQUIREMENTS.md` as a new §1.4 (`<breath>` element) and update §4.8 to reference the now-implemented contract extension.
7. **Cross-repo: SwiftVoxAlta** — Add optional `chunkHints` to `GenerationContext`, plumb into `VoiceLockManager` chunker.
8. **Cross-repo: Produciesta** — In `HeadlessAudioGenerator`, build `chunkHints` from `breathPoints` and pass through.

Sortie boundary suggestion: 1–6 in one glosa-av mission; 7–8 in a paired Produciesta/SwiftVoxAlta mission. Steps 1–6 are testable independently of the cross-repo work (the breath points end up in `CompilationResult` and round-trip through serialization regardless of whether anyone consumes them yet).

---

## 11. Open questions

1. **SwiftCompartido inline-note positions.** Does `FountainParser` surface the character offset of inline `[[ ]]` notes within their enclosing dialogue paragraph? If not, this is an upstream PR that must land first. If yes, what's the API surface?
2. **FDX inline elements.** Some FDX parsers may not handle mixed content inside `<Text>` cleanly. Verify against Final Draft 13's actual emitted XML for screenplays with style runs.
3. **PascalCase vs lowercase.** `<breath>` (per §3) or `<Breath>` for consistency with the existing three elements? Trivial to flip late, but the spec needs to commit before the few-shot examples are written.
4. **Audible breath as v2.** A vocalized inhale would be a separate attribute (`voice="inhale"` or similar), orthogonal to `length`, so a writer can say "inhale, period-length." But Qwen3-TTS may or may not respond well to instructions about audible breath inside ICL voice cloning — worth a small experiment before locking the attribute name. For v1, breath is silent only.
5. **Threshold defaults.** §6.1's 180-char trigger, §6.2's 30-char minimum-gap, and §4.2's ms-per-length values are guesses. They should be calibrated empirically against `podcast-confessions/episodes/episode_50.fountain` (Bishop case) and `episode_51.fountain` (run-on case) once the feature ships.
6. **Validator severity for missing breaths.** §7.7 proposes an "info" diagnostic when a line triggers §6.1 but has no annotations. Is that the right severity, or should it be a warning that fails CI?

---

## 12. Cross-references

- Root-cause analysis and design conversation: `../../../podcast-confessions/episodes/episode_55.fountain` ("PROSODY TRAP").
- Existing downstream chunking contract: [`../REQUIREMENTS.md`](../REQUIREMENTS.md) §4.8.
- SwiftVoxAlta chunking specification (already shipped): `../../../SwiftVoxAlta/docs/complete/FIXME-sentence-chunking.md`.
- Bishop-case original audio drift: `../../../podcast-confessions/episodes/episode_50.fountain`.
- Run-on-case original audio drift: `../../../podcast-confessions/episodes/episode_51.fountain`.
