# GLOSA — Requirements Specification

**GLOSA** (*gloss / marginal annotation*) is an SGML-variant markup language for semantic performance direction of generated voice actors. It encodes how dialogue should be performed — pacing, emotion, behavioral limits — in a form that is invisible in the rendered screenplay but machine-readable by the TTS generation pipeline.

---

## 1. Language Elements

GLOSA defines three elements. Only `<SceneContext>` requires a closing tag. `<Intent>` and `<Constraint>` are **marker tags** (no closing tag) — they apply forward until replaced by a new marker of the same type or until the enclosing `<SceneContext>` closes.

### 1.1 `<SceneContext>` — Scene-Level Environment

Establishes the physical and atmospheric environment for a scene or beat. **Required closing tag** `</SceneContext>`.

| Attribute | Required | Description |
|---|---|---|
| `location` | yes | Physical setting (e.g., `"cramped office"`, `"open field at night"`) |
| `time` | yes | Time of day / temporal context (e.g., `"late night"`, `"early morning"`, `"dusk"`) |
| `ambience` | no | Background audio / environmental sound (e.g., `"rain on windows"`, `"distant traffic"`, `"silence"`) |

**Scope**: All dialogue within the `<SceneContext>` tags inherits this environment. A new `<SceneContext>` replaces the previous one.

```
<SceneContext location="the study" time="late night" ambience="quiet hum of electronics">
  ...dialogue...
</SceneContext>
```

### 1.2 `<Intent>` — Emotional Trajectory

Defines the emotional arc and delivery pacing for subsequent dialogue. **No closing tag** — a marker that applies forward until the next `<Intent>` or until the enclosing `<SceneContext>` closes.

| Attribute | Required | Description |
|---|---|---|
| `from` | yes | Starting emotional state (e.g., `"calm"`, `"frustrated"`, `"guarded"`) |
| `to` | yes | Target emotional state (e.g., `"angry"`, `"resigned"`, `"vulnerable"`) |
| `pace` | no | Delivery speed: `slow`, `moderate`, `fast`, `accelerating`, `decelerating` |
| `spacing` | no | Pause/gap between this character's line and the next line (e.g., `"beat"`, `"long pause"`, `"immediate"`, `"overlapping"`) |

**Scope**: Applies to all subsequent dialogue until replaced by another `<Intent>` marker or the `<SceneContext>` closes. The emotional arc is a gradient from `from` to `to` across the affected lines — not a binary switch.

```
<Intent from="composed" to="frustrated" pace="accelerating">
...dialogue lines that escalate...
<Intent from="frustrated" to="resigned" pace="decelerating">
...dialogue lines that wind down...
```

### 1.3 `<Constraint>` — Character Behavioral Limits

Sets the performative boundaries for a character's dialogue. Maps directly to character dialogue — tells the model the *manner* of delivery regardless of emotional content. **No closing tag** — a marker that applies to the named character's dialogue until replaced by a new `<Constraint>` for that character, or until the enclosing `<SceneContext>` closes.

| Attribute | Required | Description |
|---|---|---|
| `character` | yes | Character name this constraint applies to |
| `direction` | yes | Natural-language performance constraint (e.g., `"angry but speaking softly and calmly on purpose"`, `"hiding excitement behind professional tone"`) |
| `register` | no | Vocal register: `low`, `mid`, `high` |
| `ceiling` | no | Emotional intensity ceiling: `subdued`, `moderate`, `intense`, `explosive` |

**Scope**: Applies to all subsequent dialogue for the named `character` until a new `<Constraint>` for that character appears, or the `<SceneContext>` closes. Multiple `<Constraint>` markers for different characters can coexist — each is keyed by `character` name.

```
<Constraint character="THE PRACTITIONER" direction="He's mad, but speaking softly and calmly on purpose" ceiling="moderate">
<Constraint character="ESPECTRO FAMILIAR" direction="patient, slightly amused">
...dialogue from both characters, each governed by their respective constraint...
```

---

## 2. Element Nesting & Scope Rules

Only `<SceneContext>` has explicit open/close scope. `<Intent>` and `<Constraint>` are forward-applying markers.

```
<SceneContext location="..." time="..." ambience="...">   ← opens scope
  <Intent from="calm" to="tense" pace="accelerating">     ← marker: applies forward
  <Constraint character="A" direction="...">               ← marker: applies to A forward
  <Constraint character="B" direction="...">               ← marker: applies to B forward

  (dialogue lines — governed by active Intent + each character's Constraint)

  <Intent from="tense" to="resigned">                     ← new marker: replaces previous Intent
  <Constraint character="A" direction="...">               ← new marker: replaces A's constraint

  (more dialogue — new Intent, new A constraint, B constraint unchanged)

</SceneContext>                                            ← closes scope, all markers expire
```

Rules:
- `<SceneContext>` is the only element with a required closing tag. It defines the outermost scope.
- `<Intent>` is a marker. It applies to all subsequent dialogue until the next `<Intent>` or `</SceneContext>`.
- `<Constraint>` is a marker keyed by `character`. It applies to that character's dialogue until a new `<Constraint>` for the same character appears, or `</SceneContext>`.
- `<Intent>` and `<Constraint>` can appear inside `<SceneContext>` or at the top level (if no scene context wrapping is needed — markers apply until EOF or the next marker).
- Multiple `<Constraint>` markers for different characters coexist independently.
- A new `<Intent>` replaces the previous one entirely. A new `<Constraint>` for a character replaces only that character's previous constraint.

---

## 3. Format Integration

GLOSA must be embeddable in both major screenplay formats without breaking their syntax or rendering.

### 3.1 Fountain Integration

GLOSA directives live inside **Fountain notes** — double-bracket syntax `[[ ]]`. Notes are invisible in rendered screenplays but preserved in source.

```fountain
[[ <SceneContext location="the study" time="late night" ambience="quiet hum of electronics"> ]]

[[ <Intent from="curious" to="frustrated" pace="moderate"> ]]
[[ <Constraint character="THE PRACTITIONER" direction="thinking aloud, halting delivery"> ]]
[[ <Constraint character="ESPECTRO FAMILIAR" direction="patient, measured, slightly amused"> ]]

THE PRACTITIONER
I've been staring at this struct for an hour.

ESPECTRO FAMILIAR
And the metadata?

THE PRACTITIONER
Key-value pairs. Right now the only one that matters is "instruct."

[[ <Intent from="frustrated" to="resolved" pace="decelerating"> ]]
[[ <Constraint character="THE PRACTITIONER" direction="dawning realization, voice steadying"> ]]

THE PRACTITIONER
I need a translator. A layer that sits between the score and the model.

ESPECTRO FAMILIAR
Now you are thinking like a language designer.

[[ </SceneContext> ]]
```

**Requirements**:
- Each GLOSA tag occupies its own `[[ ]]` note block.
- The Fountain file remains valid Fountain with or without GLOSA — removing all `[[ ]]` blocks produces a clean screenplay.
- GLOSA-unaware Fountain parsers silently ignore the directives.

### 3.2 FDX (Final Draft XML) Integration

FDX is already XML. GLOSA elements embed as **custom XML elements** within the FDX `<Content>` structure, using an XML namespace to avoid collision with Final Draft's own elements.

```xml
<FinalDraft DocumentType="Script" Template="No" Version="4"
            xmlns:glosa="https://intrusive-memory.productions/glosa">

  <Content>
    <glosa:SceneContext location="the study" time="late night" ambience="quiet hum of electronics">

      <Paragraph Type="Scene Heading">
        <Text>INT. THE STUDY – NIGHT</Text>
      </Paragraph>

      <glosa:Intent from="curious" to="frustrated" pace="moderate"/>
      <glosa:Constraint character="THE PRACTITIONER"
                        direction="thinking aloud, halting delivery"/>
      <glosa:Constraint character="ESPECTRO FAMILIAR"
                        direction="patient, measured, slightly amused"/>

      <Paragraph Type="Character">
        <Text>THE PRACTITIONER</Text>
      </Paragraph>
      <Paragraph Type="Dialogue">
        <Text>I've been staring at this struct for an hour.</Text>
      </Paragraph>

      <Paragraph Type="Character">
        <Text>ESPECTRO FAMILIAR</Text>
      </Paragraph>
      <Paragraph Type="Dialogue">
        <Text>And the metadata?</Text>
      </Paragraph>

      <!-- New beat: intent shifts, practitioner's constraint updated -->
      <glosa:Intent from="frustrated" to="resolved" pace="decelerating"/>
      <glosa:Constraint character="THE PRACTITIONER"
                        direction="dawning realization, voice steadying"/>

      <Paragraph Type="Character">
        <Text>THE PRACTITIONER</Text>
      </Paragraph>
      <Paragraph Type="Dialogue">
        <Text>I need a translator. A layer that sits between the score and the model.</Text>
      </Paragraph>

    </glosa:SceneContext>
  </Content>
</FinalDraft>
```

Note: In FDX, `<Intent>` and `<Constraint>` use **self-closing tags** (`/>`) since they have no content — they are markers, not containers. `<SceneContext>` retains its closing tag `</glosa:SceneContext>` to define scope.

**Requirements**:
- GLOSA elements use a dedicated XML namespace (`glosa:`).
- FDX parsers that don't understand the namespace ignore GLOSA elements per standard XML namespace rules.
- The FDX file remains valid Final Draft with or without GLOSA.
- SwiftCompartido's `FDXParser` and `FDXDocumentWriter` must be extended to read/write GLOSA namespace elements.

### 3.3 Highland Integration

Highland 2 files (`.highland`) are ZIP archives containing a Fountain-formatted screenplay. GLOSA integration follows the Fountain rules (Section 3.1) — the extracted Fountain content contains `[[ ]]` note blocks with GLOSA tags.

---

## 4. Processing Architecture

### 4.1 GLOSA Parser (in SwiftVoxAlta)

A dedicated parser that extracts GLOSA elements from either format:

- **Input**: Raw text (Fountain with `[[ ]]` notes) or XML (FDX with `glosa:` namespace elements).
- **Output**: A `GlosaScore` — a structured representation of all SceneContext, Intent, and Constraint directives with their scoping relationships.
- The parser must resolve nesting and associate each dialogue line with its active SceneContext, Intent, and Constraint(s).

```
GlosaScore
├── scenes: [SceneContext]
│   ├── location, time, ambience
│   ├── intents: [Intent]
│   │   ├── from, to, pace, spacing
│   │   └── constraints: [Constraint]
│   │       ├── character, direction, register, ceiling
│   │       └── dialogueLines: [String]
```

### 4.2 Score Processor (in SwiftVoxAlta)

A **stateful** component that translates `GlosaScore` into instruct strings:

- Reads the active SceneContext, Intent, and Constraint for each dialogue line.
- Synthesizes a natural-language instruct string that combines all three layers.
- Maintains **cross-line state**: tracks position within an Intent arc (beginning, middle, end of the from→to gradient), previous line delivery, cumulative emotional trajectory.
- Uses an LLM to compose the instruct string (not simple concatenation — this is inference).
- Outputs an enriched `GenerationContext` with the composed instruct string in `metadata["instruct"]`.

### 4.3 Pipeline Integration

```
Fountain (.fountain) or FDX (.fdx)
  │
  ▼
SwiftCompartido (screenplay parser)
  ├── Extracts dialogue, character names, scene headings
  │
  ▼
GLOSA Parser (new, in SwiftVoxAlta)
  ├── Extracts GLOSA directives from notes (Fountain) or namespace elements (FDX)
  ├── Builds GlosaScore with nesting/scope relationships
  │
  ▼
Score Processor (new, in SwiftVoxAlta)
  ├── For each dialogue line:
  │   ├── Resolves active SceneContext + Intent + Constraint
  │   ├── Composes natural-language instruct string (LLM-assisted)
  │   ├── Packs into GenerationContext.metadata["instruct"]
  │   └── Logs the generated direction
  │
  ▼
VoiceLockManager (unchanged)
  ├── Receives GenerationContext with enriched instruct string
  ├── Calls Qwen's generateWithClonePrompt
  │
  ▼
Audio output
```

**Key constraint**: VoiceLockManager does NOT change. It still receives a `GenerationContext` with an instruct string. GLOSA is fully transparent to downstream components.

---

## 5. Observability & Feedback

- Every instruct string the Score Processor generates must be **loggable** with its source directives (which SceneContext, Intent, and Constraint produced it).
- Log format should support review: "this instruct string, for this line, produced this audio — was it good?"
- Feedback loop: review logs, identify effective directions, encode them back into GLOSA vocabulary.

---

## 6. Extensibility

- The three core elements (SceneContext, Intent, Constraint) are the grammar.
- Attribute values (emotion names, pace values, direction phrases) are the vocabulary.
- New attributes can be added to existing elements without grammar changes.
- New element types (e.g., `<Transition>` for scene-to-scene emotional bridges) can be added as the language matures.
- Attribute values are **open vocabulary** — not restricted to an enum. The model interprets natural language.

---

## 7. Implementation Plan (SwiftVoxAlta)

### Phase 1: Language Definition
- [ ] GLOSA DTD or schema defining the three elements and their attributes
- [ ] Fountain extraction: regex/parser to pull GLOSA tags from `[[ ]]` notes
- [ ] FDX extraction: XMLParser delegate extension for `glosa:` namespace
- [ ] `GlosaScore` data model (Swift structs)

### Phase 2: Score Processing
- [ ] Score Processor that resolves active directives per dialogue line
- [ ] Cross-line state tracking (position in Intent arc)
- [ ] Instruct string composition (initially template-based, LLM-assisted later)
- [ ] Integration with `GenerationContext.metadata`

### Phase 3: Pipeline Integration
- [ ] Hook Score Processor between Produciesta and VoiceLockManager
- [ ] Logging infrastructure for generated instruct strings
- [ ] End-to-end test: scored Fountain file → audio with directed performance

### Phase 4: Tooling
- [ ] GLOSA validation (well-formedness, nesting rules)
- [ ] Score visualization / debug output
- [ ] Vocabulary tracking (which directions have been tried, which worked)

---

## 8. Design Principles

1. **The screenplay IS the score** — one file, one source of truth.
2. **Invisible in performance, visible in rehearsal** — the audience never sees GLOSA; the pipeline always does.
3. **Director, not controller** — GLOSA sets boundaries and trajectory; the model fills in the micro-performance.
4. **Transparent downstream** — VoiceLockManager never knows GLOSA exists.
5. **Format-agnostic** — same semantics whether embedded in Fountain or FDX.
6. **Discovered vocabulary** — attribute values are empirical, co-evolving with the model. The grammar is stable; the vocabulary is alive.
