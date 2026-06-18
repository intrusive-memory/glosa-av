---
state: complete
updated: 2026-06-09
title: "<pause> tag — deliberate timed silence"
kind: feature-spec
---

# `<pause>` — Deliberate Timed Silence

**State:** complete — implemented in GlosaCore, GlosaAnnotation, GlosaDirector, and the `glosa` CLI. Cross-repo consumer wiring (SwiftVoxAlta `chunkHints`, Produciesta `HeadlessAudioGenerator`) is future work in a paired mission.

`<pause>` marks a deliberate audible silence within a dialogue line. Unlike `<breath/>` (which is a silent phrasing/chunking hint producing ~0 actual silence), `<pause>` always inserts an audible gap of the specified duration. It always forces a chunk seam at its position and is always honored regardless of the chunker's budget heuristics.

See also: [`breath-tag.md`](breath-tag.md) for the `<breath>` phrasing hint element.

---

## 1. Design rationale

GLOSA originally conflated two orthogonal concerns on the `<breath>` element:

1. **Phrasing / chunking** — where to split a long dialogue line into sub-utterances for TTS (with ~0 silence).
2. **Deliberate silence** — a dramatic stop or beat the writer/director explicitly calls for (with audible gap).

As of the CLEAVING BREATH mission, these are separated into two distinct elements:

- **`<breath/>`** — phrasing only, `strength` attribute, ~0 silence, a chunk hint.
- **`<pause/>`** — timed silence, `length` attribute, forces a chunk seam, always honored.

This split makes authoring intent unambiguous and lets the Stage Director reason about the two concerns independently.

---

## 2. Element specification

### 2.1 Grammar

`<pause>` is a **marker tag** with no closing tag, written self-closing.

```xml
<pause/>
```

In Fountain: embedded in a note block at the desired position.
In FDX: a self-closing XML element in the `glosa:` namespace.

### 2.2 Attributes

| Attribute | Required | Default | Description |
|---|---|---|---|
| `length` | no | `period` | Target audible pause duration. Named presets: `comma` (~150 ms), `semicolon` (~250 ms), `period` (~400 ms), `em-dash` (~600 ms), `beat` (~1000 ms). Explicit values also accepted: `length="350ms"` or `length="0.4s"`. Labels describe intent, not exact ms values — calibration lives downstream in SwiftVoxAlta. |

A bare `<pause/>` with no attributes uses `length="period"` (the default). The serializer omits `length` in the canonical form when it equals the default, so `[[<pause/>]]` round-trips as `[[<pause/>]]` (no `length` attribute emitted).

**Note on the named values:** the punctuation labels describe *intent*, not exact ms values. The calibration of "what does a period actually sound like at this voice / this model" lives downstream and may differ between voices. The requirements only commit to the relative ordering (`comma < semicolon < period < em-dash < beat`). Concrete millisecond defaults are a SwiftVoxAlta tuning parameter.

`<pause>` accepts **no `strength` attribute**. A pause is always honored — `strength` is a budget negotiation concept that applies only to `<breath/>` phrasing hints.

### 2.3 Scope

`<pause>` is a **positional marker** scoped to a single dialogue line. It always forces a chunk seam at the exact offset where it appears.

A `<pause/>` outside any dialogue line is a parser warning and is ignored.

---

## 3. Format integration

### 3.1 Fountain

`<pause/>` lives inside an inline `[[ ]]` note placed at the pause position within the dialogue text.

**Example — colon introducing a list (the Bishop case).** Dramatic stop at the colon, then phrasing-only `<breath/>` hints between list items:

```fountain
THE PRACTITIONER
Bishop is freighted:[[<pause length="period"/>]] authority,[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.
```

The first element is a `<pause length="period">` — a deliberate dramatic stop of ~400 ms. The remaining two are bare `<breath/>` — silent phrasing hints only.

**Example — post-declaration beat.** A `<pause/>` with the default length (period) is the canonical form:

```fountain
ESPECTRO FAMILIAR
The model has been making bad predictions for nine seconds.[[<pause/>]] The speaker prompt has drifted.[[<pause length="em-dash"/>]] You wrote a run-on.
```

**Alternative encoding** if inline positioning isn't viable:

```fountain
THE PRACTITIONER
Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
[[<pause after="Bishop is freighted:"/>]]
```

`after=` matches a substring; the pause is placed at the end of the first occurrence.

### 3.2 FDX

In FDX, `<glosa:pause/>` appears as a self-closing element inline within `<Paragraph Type="Dialogue"><Text>`:

```xml
<Paragraph Type="Dialogue">
  <Text>Bishop is freighted: </Text>
  <glosa:pause length="period"/>
  <Text>authority, </Text>
  <glosa:breath/>
  <Text>patriarchy, </Text>
  <glosa:breath/>
  <Text>a history of cover-ups and anti-queer theology.</Text>
</Paragraph>
```

`<glosa:pause/>` elements are ignored by Final Draft per standard XML namespace rules. The `glosa:` namespace must be declared on the document root.

### 3.3 Highland

Highland files contain Fountain inside a ZIP; the Fountain rules in §3.1 apply unchanged.

---

## 4. Compiler behavior

### 4.1 Always honored

A `<pause>` always forces a chunk seam. It is not subject to the chunker's budget heuristics. There is no `strength` override — pause always wins.

### 4.2 Same-offset collapse

If a `<breath>` and a `<pause>` land at the same character offset in the same dialogue line:

- The `<breath>` is dropped.
- The `<pause>` is retained (one chunk seam at that offset).
- An info diagnostic is emitted: "breath at offset N collapsed into pause at same offset".

This guarantees exactly one chunk seam per `(line, offset)` pair.

### 4.3 Compiler output

`CompilationResult` carries `pausePoints: [Int: [PausePoint]]`. Keys are absolute dialogue-line indices within the screenplay; values are ascending-sorted arrays of `PausePoint(offset: Int, length: PauseLength)`. An absent key or empty array means no pause for that line.

`GlosaAnnotatedElement` exposes `pausePoints: [PausePoint]` (empty for non-dialogue elements).

---

## 5. LLM placement rules (Stage Director)

### 5.1 When to emit `<pause>`

The Stage Director emits a `<pause>` (rather than a `<breath/>`) when a break point calls for deliberate, audible silence:

1. **After a colon that introduces a list or declaration.** A colon-list pattern always warrants a `<pause>` — the colon signals an enumeration or culmination that deserves a beat, not just a chunking hint.
2. **Post-declaration beat.** After a weighty statement that the speaker (and listener) needs a moment to land: "She's dead." → `<pause/>` → next thought.
3. **Dramatic ellipsis.** When the character is thinking on their feet, searching for words, or deliberately withholding.

A `<pause>` is **not** appropriate for:
- Pure structural/syntactic breaks where the goal is only to keep sub-utterances inside the chunker's budget — use `<breath/>` instead.
- Two pauses at the same offset (the second would collapse; use a longer `length` on the first).

### 5.2 Length selection guidance

| Situation | Recommended length |
|---|---|
| Colon before a list (Bishop case) | `period` |
| Post-declaration beat | `period` |
| Dramatic withholding / thinking aloud | `em-dash` or `beat` |
| Mild hesitation | `comma` or `semicolon` |
| Long deliberate silence | `beat` |
| Explicit precise value | `length="350ms"` etc. |

### 5.3 LLM structured-output schema

`SceneAnnotation` carries a `pauses` field:

```swift
public struct PauseAnnotation: Codable, Sendable {
    /// Index of the dialogue line (within the scene) this pause applies to.
    public let dialogueLineIndex: Int

    /// Character offset within the dialogue line text where the pause goes.
    public let characterOffset: Int

    /// Target pause duration (default .period).
    public let length: PauseLength?
}
```

### 5.4 Worked example: structured output for the Bishop scene

Given:
```
Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
```

The Stage Director emits (line index 0 within its scene):

```json
{
  "breaths": [
    { "dialogueLineIndex": 0, "characterOffset": 31, "strength": "medium" },
    { "dialogueLineIndex": 0, "characterOffset": 43, "strength": "medium" }
  ],
  "pauses": [
    { "dialogueLineIndex": 0, "characterOffset": 20, "length": "period" }
  ]
}
```

- Offset 20 — after the colon: `<pause length="period">` (deliberate dramatic stop).
- Offset 31 — between `authority,` and `patriarchy,`: bare `<breath/>` (phrasing hint only).
- Offset 43 — between `patriarchy,` and `a history of`: bare `<breath/>` (phrasing hint only).

---

## 6. CLI surface

`glosa preview` displays pause points alongside breath points:

```
Line 12: THE PRACTITIONER
  text:    Bishop is freighted: authority, patriarchy, a history of cover-ups …
  intent:  controlled → indicting (arc 0.3)
  breaths: at 31 (medium)
           at 43 (medium)
  pauses:  at 20 (period)
  instruct: "Controlled, early in arc toward indicting, moderate pace. …"
```

`glosa score` writes both breaths and pauses into the output Fountain/FDX file alongside other GLOSA annotations.

---

## 7. Cross-references

- Phrasing/chunking element: [`Docs/complete/breath-tag.md`](breath-tag.md).
- GLOSA language requirements: [`../REQUIREMENTS.md`](../REQUIREMENTS.md) §1.4 and §1.5.
- Downstream chunking contract: [`../REQUIREMENTS.md`](../REQUIREMENTS.md) §4.8.
- SwiftVoxAlta chunking specification: `../../../SwiftVoxAlta/docs/complete/FIXME-sentence-chunking.md`.
