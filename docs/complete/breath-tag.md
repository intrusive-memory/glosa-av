---
state: complete
updated: 2026-06-09
title: "<breath> tag — sub-utterance phrasing hints"
kind: feature-spec
---

# `<breath>` — Sub-Utterance Phrasing Hints

**State:** complete — implemented in GlosaCore, GlosaAnnotation, GlosaDirector, and the `glosa` CLI. Cross-repo consumer wiring (SwiftVoxAlta `chunkHints`, Produciesta `HeadlessAudioGenerator`) is future work in a paired mission.

> **SUPERSEDED DESIGN NOTE — `length` on `<breath>` (pre-CLEAVING BREATH era)**
>
> Earlier versions of this document described a `length` attribute on `<breath>` that controlled audible pause duration (comma/semicolon/period/em-dash/beat). That design conflated two orthogonal concerns — phrasing chunk hints and timed silence — into one element. As of the CLEAVING BREATH mission (v0.4.x), `<breath>` is a **silent** phrasing/chunking hint only; it carries no `length` and produces ~0 actual silence. Timed deliberate silence is now the responsibility of the separate **`<pause>`** element (see [`Docs/complete/pause-tag.md`](pause-tag.md)). A `length` attribute on `<breath>` is **ignored** by the parser and emits a warning diagnostic: "`length` is not valid on `<breath>`; use `<pause>`". There is no migration path — glosa is pre-release.

`<breath>` marks where a single dialogue line should be split into sub-utterances before being sent to the TTS model. The writer's prose is unchanged; the *delivery* to the model changes. This closes the gap flagged in `Docs/REQUIREMENTS.md` §4.8 (Downstream Chunking) for sentences that are structurally tangled below the auto-chunker's sentence-boundary horizon.

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

**Out of scope:**
- Audible breath synthesis (inhale sounds, sighs) — `<breath>` is a *silent* chunk hint, not a vocalization directive.
- Timed deliberate silence — use `<pause>` (see [`pause-tag.md`](pause-tag.md)) for audible/deliberate gaps.
- Intra-line emotional gradient — flagged in §4.8 as future work. `<breath>` is orthogonal: it changes chunking, not instruct content.
- Downstream playback / drift-detection / re-take logic — that lives in Produciesta / SwiftVoxAlta, not glosa-av.

---

## 3. Naming

Episode 55 calls the phenomenon "breath." That is the semantic intent (a place where a human reader would draw breath), so the element is named `<breath>`. Lowercase is preferred because `<breath>` describes a *moment* — marker punctuation rather than a directive category. HTML uses `<br/>` lowercase for the same reason.

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
| `strength` | no | `medium` | Relative weight when downstream chunkers must trade off competing breath candidates against the chunker's character-budget heuristics. `weak` (only chunk here if necessary to fit the budget), `medium` (default — chunk here when the run exceeds the budget), `strong` (always chunk here regardless of budget). |

`<breath>` accepts **no `length` attribute**. A `length` attribute on `<breath>` is silently ignored by the parser and emits a warning diagnostic: "`length` is not valid on `<breath>`; use `<pause>`". For deliberate audible silence, use the `<pause>` element (see [`pause-tag.md`](pause-tag.md)).

A bare `<breath/>` is a medium-strength chunk hint with ~0 actual silence.

### 4.3 Scope

`<breath>` is a **positional marker** scoped to a single dialogue line. It applies at the exact textual offset where it appears within the dialogue, between the `[[ ]]` notes that precede and follow it (Fountain), or as an inline child of `<Dialogue>` (FDX).

`<breath>` does **not** nest inside `<Intent>` or `<Constraint>` semantically — it lives at a different layer (chunking, not instruct content). Multiple `<breath/>` markers can appear in one dialogue line.

A `<breath/>` outside any dialogue line is a parser warning and is ignored.

---

## 5. Format integration

### 5.1 Fountain

`<breath/>` lives inside an inline `[[ ]]` note placed at the breath position within the dialogue text. The Fountain renderer strips `[[ ]]` notes; the on-page text is the writer's original prose. The GLOSA parser uses the inline note positions to anchor breath offsets to the dialogue text.

**Example — colon followed by an asyndetic list (the Bishop case from episode 51).** A dramatic pause after the colon uses `<pause>` (see [`pause-tag.md`](pause-tag.md)); chunking-only breaths between list items use `<breath/>`:

```fountain
THE PRACTITIONER
Bishop is freighted:[[<pause length="period"/>]] authority,[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.
```

The first element is a `<pause>` with explicit length — the writer is calling for a deliberate dramatic stop (a timed silence the chunker must honor). The remaining two are bare `<breath/>` (default: `strength="medium"`) — they exist to give the model clean clause boundaries without adding deliberate silence.

**Example — run-on with chained coordinating conjunctions (the episode 55 case).** All breaks are phrasing hints only; the goal is just to keep each sub-utterance well inside the drift horizon:

```fountain
THE PRACTITIONER
He kept the parish quiet[[<breath/>]] and he kept the families quiet[[<breath/>]] and he kept the press quiet[[<breath/>]] and he kept the diocese quiet for thirty-two years[[<breath/>]] and then a single deposition undid every one of those silences in a single afternoon.
```

Each `<breath/>` is bare — medium strength — placed immediately before the coordinating conjunction (per §6.2 rule 3, the breath goes after the previous clause, before the `and`).

**Alternative encoding** if inline positioning isn't viable: a sibling note block with explicit positioning:

```fountain
THE PRACTITIONER
Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
[[<breath after="authority,"/>]]
[[<breath after="patriarchy,"/>]]
```

`after=` matches a substring; the breath is placed at the end of the first occurrence. This is more brittle to writer edits but doesn't depend on inline-position support.

### 5.2 FDX

In FDX, `<glosa:breath/>` appears as a self-closing element inline within `<Paragraph Type="Dialogue"><Text>`:

```xml
<Paragraph Type="Dialogue">
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

The Stage Director (`GlosaDirector.StageDirector`) analyzes each dialogue line and emits `<breath/>` annotations when warranted. The placement logic is encoded in the LLM's system prompt and the structured-output schema; the LLM never emits raw SGML — it returns offset-keyed annotations that the serializer renders.

### 6.1 Trigger conditions

The LLM considers a dialogue line as a `<breath>` candidate when **any** of the following hold:

1. The line exceeds a character threshold. Suggested initial threshold: **180 characters** (matches VoxAlta's per-chunk budget at 0.055 s/char ≈ 10 s). Tunable in `VocabularyGlossary` or a per-project config.
2. The line is a single sentence (no internal `.`, `?`, `!`) longer than **120 characters** and contains at least one of:
   - Three or more clauses joined by coordinating conjunctions (`and`, `but`, `or`, `so`, `yet`).
   - A semicolon-joined compound sentence.
   - An asyndetic list.
3. The line contains a coordinating conjunction whose scope ambiguity is detectable.

Lines that don't satisfy any trigger get no `<breath/>` annotations.

> **Note on colon-list cases**: A colon introducing a list may warrant a `<pause>` (deliberate dramatic stop) at the colon rather than a bare `<breath/>`. The Stage Director emits `<pause>` for deliberate audible silence and `<breath/>` for phrasing-only chunk hints. See [`pause-tag.md`](pause-tag.md) §6 for the pause placement rules.

### 6.2 Placement rules (where to put the break)

When a line triggers, the LLM places `<breath/>` markers at syntactic breakpoints, in priority order:

1. **After a semicolon.** Sentence-internal stops are natural breath points.
2. **Between clauses of a compound sentence**, immediately before the coordinating conjunction.
   - **With a comma** (`, and` / `, but` / `, or` / `, so` / `, yet`): the breath goes *after* the comma, *before* the conjunction word.
   - **Polysyndetic without commas** (`… quiet and he kept …`): the breath goes between the previous clause and the conjunction word.
   In both forms, the conjunction stays in the second chunk.
3. **Between list items** in an asyndetic or polysyndetic list, after each comma separating top-level items. Do **not** chunk inside a list item even if it contains commas internally.
4. **Before a long subordinate clause** introduced by `which`, `that`, `because`, `although`, `when`, `while`, when the matrix clause is itself ≥ 60 characters.

The LLM should **not** place `<breath/>`:

- Between an adjective and the noun it modifies.
- Between a verb and a short direct object (< 30 chars).
- Inside a noun phrase.
- Inside a quoted string.
- Within 10 characters of the line's start or end.
- Closer than 30 characters to another `<breath/>`.

### 6.3 LLM structured-output schema

`SceneAnnotation` carries a `breaths` field and a `pauses` field (see [`pause-tag.md`](pause-tag.md) §6.3 for `PauseAnnotation`):

```swift
public struct BreathAnnotation: Codable, Sendable {
    /// Index of the dialogue line (within the scene) this breath applies to.
    public let dialogueLineIndex: Int

    /// Character offset within the dialogue line text where the break goes.
    /// 0 = before first character; line.count = after last character (invalid).
    public let characterOffset: Int

    /// Optional: chunker priority (default .medium).
    public let strength: BreathStrength?
}
```

Note: `BreathAnnotation` carries no `length` field. Length was removed in the CLEAVING BREATH migration. Any `length` field in legacy JSON is silently ignored during decode.

### 6.4 Same-offset collapse

If a `<breath>` and a `<pause>` land at the same character offset in the same dialogue line, the compiler drops the `<breath>` and retains the `<pause>` (pause wins). An info diagnostic is emitted noting the collapse. This guarantees exactly one chunk seam per offset.

---

## 7. Compiler / Annotation impact

### 7.1 GlosaCore: data model

`struct Breath` holds `sceneIndex`, `dialogueLineIndex`, `characterOffset`, and `strength`. It carries no `length`. `GlosaScore` exposes both `breaths: [Breath]` and `pauses: [Pause]` (see [`pause-tag.md`](pause-tag.md)).

### 7.2 GlosaCore: parser

`GlosaParser` extracts `<breath/>` from both Fountain (inline `[[ ]]` notes) and FDX (`glosa:breath` elements). A `length` attribute on `<breath/>` is ignored with a warning diagnostic.

### 7.3 GlosaCore: compiler output

`CompilationResult` carries both `breathPoints: [Int: [BreathPoint]]` and `pausePoints: [Int: [PausePoint]]`. `BreathPoint` holds `offset` and `strength` (no `length`). Same-offset collapse ensures a given `(line, offset)` has at most one entry — a `PausePoint` wins over a `BreathPoint`.

### 7.4 GlosaAnnotation: element bridge

`GlosaAnnotatedElement` exposes `breathPoints: [BreathPoint]` and `pausePoints: [PausePoint]`. Both are empty for non-dialogue elements. The LLM annotation path (via `SceneAnnotation.breaths` and `SceneAnnotation.pauses`) is fully wired to these fields (wiring was completed in the CLEAVING BREATH mission, Sortie 6).

### 7.5 GlosaSerializer

Round-trip: `GlosaAnnotatedScreenplay` → Fountain (with inline `[[<breath/>]]` and `[[<pause/>]]` notes) → parse again → identical `breathPoints` and `pausePoints`. Same for FDX. Default `strength="medium"` is omitted in the canonical form.

---

## 8. CLI surface

`glosa preview` displays breath points alongside resolved directives:

```
Line 12: THE PRACTITIONER
  text:    Bishop is freighted: authority, patriarchy, a history of cover-ups …
  intent:  controlled → indicting (arc 0.3)
  breaths: at 20 (medium)
           at 31 (medium)
           at 43 (medium)
  pauses:  (none)
  instruct: "Controlled, early in arc toward indicting, moderate pace. …"
```

`glosa score` writes both breaths and pauses into the output Fountain/FDX file.

---

## 9. Cross-references

- Root-cause analysis and design conversation: `../../../podcast-confessions/episodes/episode_55.fountain` ("PROSODY TRAP").
- Timed silence element: [`Docs/complete/pause-tag.md`](pause-tag.md).
- Existing downstream chunking contract: [`../REQUIREMENTS.md`](../REQUIREMENTS.md) §4.8.
- SwiftVoxAlta chunking specification (already shipped): `../../../SwiftVoxAlta/docs/complete/FIXME-sentence-chunking.md`.
- Bishop-case original audio drift: `../../../podcast-confessions/episodes/episode_50.fountain`.
- Run-on-case original audio drift: `../../../podcast-confessions/episodes/episode_51.fountain`.
