# GLOSA — Requirements Specification

**GLOSA** (*gloss / marginal annotation*) is an SGML-variant markup language for semantic performance direction of generated voice actors. It encodes how dialogue should be performed — pacing, emotion, behavioral limits — in a form that is invisible in the rendered screenplay but machine-readable by a compiler that produces natural-language instruct strings for the TTS generation pipeline.

**glosa-av** implements GLOSA through two complementary roles:

1. **Compiler** — parses existing GLOSA annotations from screenplay files, resolves scope and state, and outputs per-dialogue-line instruct strings. Foundation-only, deterministic, no external dependencies. Its sole output is `String`.

2. **Stage Director** — analyzes a raw (unannotated) screenplay via local LLM inference and generates GLOSA annotations automatically. It operates directly on SwiftCompartido's parsed element model, attaching instruct directives to screenplay elements that can then be serialized back to disk or sent directly to the audio generation pipeline. Depends on SwiftCompartido (element model), SwiftBruja (LLM inference), and SwiftAcervo (model management).

---

## 1. Language Elements

GLOSA defines three elements. `<SceneContext>` requires a closing tag. `<Intent>` has an **optional closing tag** — scoped when closed (precise gradient), marker when unclosed (applies forward). `<Constraint>` is a **marker tag** (no closing tag) — it applies forward until replaced or the enclosing scope closes.

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

Defines the emotional arc and delivery pacing for dialogue. **Optional closing tag** — supports two usage modes:

- **Scoped** (`<Intent ...>...</Intent>`): The emotional arc covers exactly the enclosed dialogue. The resolver knows how many lines fall within the arc and can calculate precise gradient position (e.g., line 3 of 7 = 43% through the `from→to` trajectory).
- **Marker** (`<Intent ...>`, no closing tag): Applies forward until the next `<Intent>` or until the enclosing `<SceneContext>` closes. Gradient position is approximate (linear interpolation against remaining lines in scope).

After `</Intent>` closes, **no Intent is active** — delivery returns to neutral until the next `<Intent>` appears. A new `<Intent>` always supersedes any previous one; Intents do not nest.

| Attribute | Required | Description |
|---|---|---|
| `from` | yes | Starting emotional state (e.g., `"calm"`, `"frustrated"`, `"guarded"`) |
| `to` | yes | Target emotional state (e.g., `"angry"`, `"resigned"`, `"vulnerable"`) |
| `pace` | no | Delivery speed: `slow`, `moderate`, `fast`, `accelerating`, `decelerating` |
| `spacing` | no | Pause/gap between this character's line and the next line (e.g., `"beat"`, `"long pause"`, `"immediate"`, `"overlapping"`) |

**Scope**: The emotional arc is a gradient from `from` to `to` across the affected lines — not a binary switch.

```
<!-- Scoped: arc covers exactly these lines, gradient position is precise -->
<Intent from="composed" to="frustrated" pace="accelerating">
...dialogue lines that escalate (resolver knows exact arc position)...
</Intent>

<!-- Marker: applies forward until next Intent or end of SceneContext -->
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

`<SceneContext>` requires a closing tag. `<Intent>` has an **optional** closing tag (scoped or marker mode). `<Constraint>` is a forward-applying marker (no closing tag).

```
<SceneContext location="..." time="..." ambience="...">   <- opens scope

  <!-- Scoped Intent: precise gradient over enclosed lines -->
  <Intent from="calm" to="tense" pace="accelerating">     <- scoped: opens arc
    <Constraint character="A" direction="...">             <- marker: applies to A forward
    <Constraint character="B" direction="...">             <- marker: applies to B forward

    (dialogue -- governed by scoped Intent + each character's Constraint)
    (resolver knows exact arc position: line N of M)

  </Intent>                                                <- closes arc, Intent goes neutral

  (dialogue here has NO active Intent -- neutral delivery)
  (A and B constraints still active until replaced or SceneContext closes)

  <!-- Marker Intent: applies forward to end of SceneContext -->
  <Intent from="tense" to="resigned">                     <- marker: applies forward
  <Constraint character="A" direction="...">               <- replaces A's constraint

  (dialogue -- marker Intent active, gradient approximate)

</SceneContext>                                            <- closes scope, all markers expire
```

Rules:
- `<SceneContext>` requires a closing tag. It defines the outermost scope.
- `<Intent>` supports two modes:
  - **Scoped** (`<Intent ...>...</Intent>`): Arc covers exactly the enclosed dialogue. Gradient position is precise.
  - **Marker** (`<Intent ...>`, no closing tag): Applies forward until the next `<Intent>` or `</SceneContext>`. Gradient is approximate.
- After `</Intent>` closes, **no Intent is active** — delivery returns to neutral until the next `<Intent>`.
- A new `<Intent>` always supersedes any previous one. **Intents do not nest** — a scoped Intent cannot contain another Intent.
- `<Constraint>` is a marker keyed by `character`. It applies to that character's dialogue until a new `<Constraint>` for the same character appears, or `</SceneContext>`.
- `<Intent>` and `<Constraint>` can appear inside `<SceneContext>` or at the top level (if no scene context wrapping is needed — markers apply until EOF or the next marker).
- Multiple `<Constraint>` markers for different characters coexist independently.
- A new `<Constraint>` for a character replaces only that character's previous constraint.

---

## 3. Format Integration

GLOSA must be embeddable in both major screenplay formats without breaking their syntax or rendering.

### 3.1 Fountain Integration

GLOSA directives live inside **Fountain notes** — double-bracket syntax `[[ ]]`. Notes are invisible in rendered screenplays but preserved in source.

```fountain
[[ <SceneContext location="the study" time="late night" ambience="quiet hum of electronics"> ]]

[[ <Constraint character="THE PRACTITIONER" direction="thinking aloud, halting delivery"> ]]
[[ <Constraint character="ESPECTRO FAMILIAR" direction="patient, measured, slightly amused"> ]]

.Scoped Intent -- precise gradient across 3 dialogue lines:

[[ <Intent from="curious" to="frustrated" pace="moderate"> ]]

THE PRACTITIONER
I've been staring at this struct for an hour.

ESPECTRO FAMILIAR
And the metadata?

THE PRACTITIONER
Key-value pairs. Right now the only one that matters is "instruct."

[[ </Intent> ]]

.After </Intent>, delivery is neutral. New marker Intent for the resolution:

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
        <Text>INT. THE STUDY - NIGHT</Text>
      </Paragraph>

      <glosa:Constraint character="THE PRACTITIONER"
                        direction="thinking aloud, halting delivery"/>
      <glosa:Constraint character="ESPECTRO FAMILIAR"
                        direction="patient, measured, slightly amused"/>

      <!-- Scoped Intent: precise gradient across enclosed dialogue -->
      <glosa:Intent from="curious" to="frustrated" pace="moderate">

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

      </glosa:Intent>

      <!-- After </Intent>, delivery is neutral. Marker Intent for resolution: -->
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

Note: In FDX, `<Intent>` supports both **scoped** (`<glosa:Intent ...>...</glosa:Intent>`) and **self-closing marker** (`<glosa:Intent .../>`) forms. `<Constraint>` uses self-closing tags (`/>`) since it is always a marker. `<SceneContext>` always requires its closing tag.

**Requirements**:
- GLOSA elements use a dedicated XML namespace (`glosa:`).
- FDX parsers that don't understand the namespace ignore GLOSA elements per standard XML namespace rules.
- The FDX file remains valid Final Draft with or without GLOSA.
- SwiftCompartido's `FDXParser` and `FDXDocumentWriter` must be extended to read/write GLOSA namespace elements.

### 3.3 Highland Integration

Highland 2 files (`.highland`) are ZIP archives containing a Fountain-formatted screenplay. GLOSA integration follows the Fountain rules (Section 3.1) — the extracted Fountain content contains `[[ ]]` note blocks with GLOSA tags.

---

## 4. Architecture

### 4.1 Package Structure

glosa-av is a Swift package with multiple library targets that separate concerns by dependency weight:

```
glosa-av (Swift package)
|
+-- GlosaCore (Foundation only -- zero external dependencies)
|   +-- GlosaScore          -- data model: SceneContext, Intent, Constraint
|   +-- GlosaParser         -- extracts GLOSA tags from Fountain notes or FDX XML
|   +-- ScoreResolver       -- stateful scope tracker: resolves active directives per line
|   +-- InstructComposer    -- template-based: resolved directives -> instruct string
|   +-- GlosaCompiler       -- public API: parser + resolver + composer
|   +-- GlosaValidator      -- well-formedness and nesting rule checks
|
+-- GlosaAnnotation (depends on: GlosaCore, SwiftCompartido)
|   +-- GlosaAnnotatedElement      -- pairs a GuionElement with resolved GLOSA directives
|   +-- GlosaAnnotatedScreenplay   -- wraps GuionParsedElementCollection with resolved instructs
|   +-- GlosaSerializer            -- writes annotated elements back to Fountain/FDX with GLOSA embedded
|
+-- GlosaDirector (depends on: GlosaAnnotation, SwiftBruja, SwiftAcervo)
|   +-- StageDirector       -- LLM-powered annotation generator
|   +-- SceneAnalyzer       -- feeds scenes to LLM, receives structured GLOSA annotations
|   +-- VocabularyGlossary  -- curated terms the TTS model responds to well
|
+-- glosa (CLI executable, depends on: GlosaDirector)
    +-- GlosaCommand        -- `glosa score`, `glosa compile`, `glosa preview`
```

**GlosaCore** is the compiler. It has no knowledge of SwiftCompartido's element model, TTS, audio, models, or voices. Its input is strings and indices; its output is strings.

**GlosaAnnotation** bridges the compiler to the screenplay element model. It extends SwiftCompartido's `GuionElement` with GLOSA instruct data, so annotated elements can flow directly to Produciesta for audio generation or serialize back to disk with GLOSA embedded.

**GlosaDirector** is the Stage Director — the LLM-powered utility that reads a raw screenplay and generates GLOSA annotations. It uses SwiftBruja for local inference and SwiftAcervo for model management.

### 4.2 Role Separation

Five packages participate. The compiler core communicates via plain `String`. The annotation layer communicates via extended `GuionElement`. The Stage Director communicates via `GlosaAnnotatedScreenplay`.

| Package | Role | Dependencies |
|---|---|---|
| **GlosaCore** | Compiler: GLOSA tags -> instruct strings | Foundation only |
| **GlosaAnnotation** | Element bridge: attaches instructs to parsed screenplay elements | GlosaCore, SwiftCompartido |
| **GlosaDirector** | Stage Director: raw screenplay -> GLOSA-annotated screenplay | GlosaAnnotation, SwiftBruja, SwiftAcervo |
| **Produciesta** | Orchestrator: screenplay -> audio files | SwiftCompartido, glosa-av, SwiftVoxAlta |
| **SwiftVoxAlta** | Synthesizer: `GenerationContext(phrase:instruct:)` -> WAV | mlx-audio-swift, SwiftAcervo, SwiftHablare |

**glosa-av has no dependency on SwiftVoxAlta. SwiftVoxAlta has no dependency on glosa-av.** They communicate through a plain `String` — the instruct — with Produciesta as the orchestrator in between.

### 4.3 GlosaCore — The Compiler

The compiler is deterministic, Foundation-only, and has no knowledge of the screenplay element model.

#### GlosaParser

Extracts GLOSA elements from either screenplay format:

- **Fountain input**: Raw note strings extracted from `[[ ]]` blocks (by SwiftCompartido or by the parser itself from raw Fountain text).
- **FDX input**: XML fragments containing `glosa:` namespace elements.
- **Output**: A `GlosaScore` — structured representation of all directives with scoping relationships.
- For **scoped** `<Intent>...</Intent>`, records the enclosed dialogue line count.
- For **marker** `<Intent>` (no closing tag), marks the Intent as open-ended.

```
GlosaScore
+-- scenes: [SceneContext]
|   +-- location, time, ambience
|   +-- intents: [Intent]
|   |   +-- from, to, pace, spacing
|   |   +-- scoped: Bool          <- true if closing tag present
|   |   +-- lineCount: Int?       <- number of enclosed dialogue lines (scoped only)
|   |   +-- constraints: [Constraint]
|   |       +-- character, direction, register, ceiling
|   |       +-- dialogueLines: [String]
```

#### ScoreResolver

A **stateful** iterator that walks through dialogue lines and resolves the active directives for each:

- Tracks current `SceneContext`, active `Intent` (with arc position), and per-character `Constraint` map.
- For **scoped Intents**: calculates precise gradient position (line N of M -> N/M progress through the `from->to` arc).
- For **marker Intents**: estimates gradient position via linear interpolation against remaining lines in scope, or treats as a steady blend.
- After `</Intent>` closes, returns no active Intent (neutral) until the next `<Intent>`.
- Output per line: `ResolvedDirectives` containing active `SceneContext?`, `ResolvedIntent?` (with `arcPosition: Float`), and `Constraint?`.

#### InstructComposer

Template-based composition that turns `ResolvedDirectives` into a natural-language instruct string:

- Combines SceneContext environment, Intent emotional arc (with gradient position), and Constraint behavioral limits.
- Deterministic and fast — no LLM, no network, no external dependencies.
- Produces strings suitable for Qwen3-TTS's ChatML instruct format (natural language, not structured data).

**Example output** for line 1 of a 3-line scoped Intent:

```
Late night in the study, quiet hum of electronics.
Curious, early in arc toward frustrated, moderate pace.
Thinking aloud, halting delivery. Ceiling: moderate.
```

#### GlosaCompiler (Public API)

The top-level entry point that combines all components:

```swift
public struct GlosaCompiler {
    /// Compile a scored Fountain screenplay into per-line instruct strings.
    ///
    /// - Parameters:
    ///   - fountainNotes: Array of note strings extracted from [[ ]] blocks, in document order.
    ///   - dialogueLines: Array of (characterName, text) tuples, in document order.
    /// - Returns: CompilationResult with per-line instructs and diagnostics.
    public func compile(
        fountainNotes: [String],
        dialogueLines: [(character: String, text: String)]
    ) throws -> CompilationResult
}

public struct CompilationResult {
    /// Per-line instruct strings, keyed by dialogue line index.
    /// Lines with no active directives have no entry (nil = neutral/fallback to parenthetical).
    public let instructs: [Int: String]

    /// Diagnostics: warnings about unclosed tags, unknown characters, etc.
    public let diagnostics: [GlosaDiagnostic]
}
```

### 4.4 GlosaAnnotation — Element Bridge

This layer extends SwiftCompartido's parsed element model so that GLOSA directives live directly on screenplay elements rather than in a separate index.

#### GlosaAnnotatedElement

Since `GuionElement` is a struct defined in SwiftCompartido, glosa-av cannot add stored properties via extension. Instead, `GlosaAnnotation` provides a wrapper:

```swift
/// A screenplay element paired with its resolved GLOSA directives.
public struct GlosaAnnotatedElement: Sendable {
    /// The original parsed screenplay element.
    public let element: GuionElement

    /// Resolved GLOSA directives active at this element's position.
    /// Nil for non-dialogue elements or dialogue with no active directives.
    public let directives: ResolvedDirectives?

    /// The compiled instruct string, ready for TTS generation.
    /// Nil means no GLOSA conditioning -- fall back to parenthetical or neutral.
    public let instruct: String?
}
```

#### GlosaAnnotatedScreenplay

Wraps a `GuionParsedElementCollection` with the full annotation context:

```swift
/// A screenplay with GLOSA directives resolved and attached to every element.
public struct GlosaAnnotatedScreenplay: Sendable {
    /// The original parsed screenplay.
    public let screenplay: GuionParsedElementCollection

    /// All elements with their resolved GLOSA directives and instruct strings.
    public let annotatedElements: [GlosaAnnotatedElement]

    /// The underlying GLOSA score (for inspection/debugging).
    public let score: GlosaScore

    /// Compilation diagnostics.
    public let diagnostics: [GlosaDiagnostic]

    /// Provenance data for every instructed line.
    public let provenance: [InstructProvenance]
}
```

This type is the primary exchange format between glosa-av and Produciesta. Produciesta iterates `annotatedElements` and uses `element.instruct` directly — no separate compilation step, no index lookup.

#### GlosaSerializer

Writes annotated elements back to screenplay formats with GLOSA embedded:

- **To Fountain**: Inserts `[[ <SceneContext ...> ]]`, `[[ <Intent ...> ]]`, `[[ <Constraint ...> ]]` note blocks at the correct positions relative to dialogue elements. Uses SwiftCompartido's `FountainWriter` for the base screenplay, interleaving GLOSA comment elements.
- **To FDX**: Inserts `glosa:` namespace elements into the XML structure via SwiftCompartido's `FDXDocumentWriter`.
- **Round-trip fidelity**: Parsing an annotated file and re-serializing it produces the same GLOSA annotations. The screenplay content is untouched.

```swift
public struct GlosaSerializer {
    /// Write an annotated screenplay back to Fountain format with GLOSA embedded.
    public func writeFountain(_ annotated: GlosaAnnotatedScreenplay) -> String

    /// Write an annotated screenplay back to FDX format with GLOSA embedded.
    public func writeFDX(_ annotated: GlosaAnnotatedScreenplay) -> Data

    /// Write to the same format as the source file.
    public func write(_ annotated: GlosaAnnotatedScreenplay, to url: URL) throws
}
```

### 4.5 GlosaDirector — The Stage Director

The Stage Director is a single-purpose utility that reads a raw screenplay and generates GLOSA annotations via local LLM inference. It is the automated counterpart to a human screenwriter manually adding `[[ ]]` note blocks.

#### How It Works

```
Raw Screenplay (.fountain / .fdx / .highland)
  |
  v
SwiftCompartido -- parse to [GuionElement]
  |
  v
SceneAnalyzer -- segment elements into scenes (by sceneHeading boundaries)
  |
  v
For each scene:
  |
  +-- Build scene context: location, time (from scene heading), character list
  |
  +-- SwiftBruja.query(as: SceneAnnotation.self)
  |   +-- System prompt: GLOSA spec + VocabularyGlossary (effective TTS terms)
  |   +-- User prompt: scene text (all elements as readable screenplay)
  |   +-- Structured output: SceneAnnotation (Codable)
  |       +-- sceneContext: SceneContext
  |       +-- intents: [IntentAnnotation] (with line ranges)
  |       +-- constraints: [ConstraintAnnotation] (per character)
  |
  +-- Validate: GlosaValidator checks well-formedness
  |
  +-- Attach: map annotations onto GuionElements -> [GlosaAnnotatedElement]
  |
  v
GlosaAnnotatedScreenplay
  |
  +-- Path A: GlosaSerializer.writeFountain() -> annotated .fountain file on disk
  |
  +-- Path B: Pass directly to Produciesta for audio generation
```

#### SceneAnalyzer

Segments a parsed screenplay into scenes and prepares each for LLM analysis:

```swift
public struct SceneAnalyzer {
    /// Analyze a parsed screenplay and generate GLOSA annotations for every scene.
    ///
    /// - Parameters:
    ///   - screenplay: Parsed screenplay from SwiftCompartido.
    ///   - model: HuggingFace model ID for LLM inference (default: auto-select).
    ///   - glossary: Optional vocabulary glossary of effective TTS direction terms.
    /// - Returns: Fully annotated screenplay with GLOSA directives on every element.
    public func annotate(
        _ screenplay: GuionParsedElementCollection,
        model: String? = nil,
        glossary: VocabularyGlossary? = nil
    ) async throws -> GlosaAnnotatedScreenplay
}
```

The LLM sees each scene as readable screenplay text (not raw `GuionElement` structs). It returns structured output — a `SceneAnnotation` Codable struct — which the analyzer maps back onto element indices. The LLM never sees or generates raw SGML tags; it fills in structured fields (emotion names, direction phrases, pace values) that the serializer later renders as GLOSA markup.

#### VocabularyGlossary

A curated, evolving collection of direction terms that produce good TTS results. The glossary is built through the feedback loop (Section 5.3) and fed to the LLM as part of the system prompt, biasing it toward vocabulary the model responds to well.

```swift
public struct VocabularyGlossary: Codable, Sendable {
    /// Emotion terms known to produce good TTS results.
    /// e.g., ["guarded", "vulnerable", "conspiratorial calm", "grim resolve"]
    public var emotions: [String]

    /// Direction phrases known to produce good TTS results.
    /// e.g., ["bracing, matter-of-fact to keep distance", "dam breaking, voice thinning"]
    public var directions: [String]

    /// Pace terms. Fixed vocabulary: slow, moderate, fast, accelerating, decelerating.
    public let paceTerms: [String]

    /// Register terms. Fixed vocabulary: low, mid, high.
    public let registerTerms: [String]

    /// Ceiling terms. Fixed vocabulary: subdued, moderate, intense, explosive.
    public let ceilingTerms: [String]
}
```

The glossary ships with a default set and grows as the feedback loop identifies effective terms. It is stored as a JSON file in the glosa-av package and can be overridden per-project.

#### LLM Prompt Design

The Stage Director's prompt has three parts:

1. **System prompt**: The GLOSA element definitions (Section 1), scope rules (Section 2), and the VocabularyGlossary. This is static per invocation.

2. **Few-shot examples**: 2-3 annotated scenes showing raw screenplay -> `SceneAnnotation` structured output. These are drawn from EXAMPLES.md or from previously annotated screenplays in the project.

3. **User prompt**: The raw scene text, formatted as readable screenplay. The LLM returns a `SceneAnnotation` via SwiftBruja's structured output (`Bruja.query(as: SceneAnnotation.self)`).

The LLM's job is **dramatic analysis** — identifying emotional arcs, character behavioral states, and scene atmosphere. The grammar and serialization are handled by code. The LLM never emits raw SGML.

### 4.6 Pipeline Integration

#### Path A: Annotation -> Disk -> Later Generation

The CLI workflow for pre-annotating screenplays:

```
$ glosa score episode_38.fountain -o episode_38_scored.fountain

Raw Fountain file
  |
  v
SwiftCompartido.parse() -> GuionParsedElementCollection
  |
  v
StageDirector.annotate() -> GlosaAnnotatedScreenplay
  |
  v
GlosaSerializer.writeFountain() -> annotated .fountain file on disk
```

The annotated file is a valid Fountain screenplay with GLOSA directives in `[[ ]]` notes. It can be opened in any Fountain editor, reviewed, hand-tuned, and later fed to Produciesta for audio generation. The human screenwriter can edit, override, or remove any annotation.

#### Path B: Annotation -> Direct Generation (in Produciesta)

The in-memory workflow when Produciesta generates audio:

```
Fountain file
  |
  v
SwiftCompartido.parse() -> GuionParsedElementCollection
  |
  +-- Already has GLOSA [[ ]] notes? -> GlosaCompiler.compile() -> CompilationResult
  |                                      |
  |   No GLOSA notes? ----------------> StageDirector.annotate()
  |                                      |
  v                                      v
GlosaAnnotatedScreenplay
  |
  v
For each annotatedElement where element.elementType == .dialogue:
  instruct = annotatedElement.instruct ?? parenthetical fallback
  |
  v
GenerationContext(phrase: text, instruct: instruct)
  |
  v
VoxAltaVoiceProvider.generateAudio(context:voiceId:)  <- unchanged
  |
  v
VoiceLockManager -> Qwen3-TTS -> WAV audio              <- unchanged
```

**Key points**:
- If the screenplay already contains GLOSA annotations (hand-written or from a previous `glosa score` pass), the compiler resolves them deterministically — no LLM needed.
- If the screenplay has no GLOSA annotations, Produciesta can optionally invoke the Stage Director for on-the-fly annotation via LLM.
- Either path produces a `GlosaAnnotatedScreenplay` with instruct strings on every dialogue element.
- **SwiftVoxAlta does not change.** It receives `GenerationContext(phrase:instruct:)` exactly as it does today.
- **VoiceLockManager does not change.** It extracts `context.instruct` and passes it to Qwen3-TTS.

### 4.7 What Qwen3-TTS Receives

The model's input format is fixed. glosa-av's output must produce natural-language strings that work well as ChatML user messages:

```
Model prompt (constructed by mlx-audio-swift, NOT by glosa-av):

<|im_start|>user
{instruct string from glosa-av}<|im_end|>
<|im_start|>assistant
{dialogue text to synthesize}<|im_end|>
```

glosa-av controls only the content of the instruct string. The ChatML wrapping is handled by mlx-audio-swift's `prepareICLInputs()` / `prepareBaseInputs()` methods, which glosa-av never touches.

### 4.8 Fallback Behavior

When a screenplay has **no GLOSA annotations** and the Stage Director is not invoked:

- `GlosaCompiler.compile()` returns an empty `instructs` dictionary.
- Produciesta falls back to parentheticals for every line.
- Lines with no parenthetical get `instruct: nil` -> VoiceLockManager generates with no instruct conditioning.

When a screenplay has **partial GLOSA annotations** (e.g., only some scenes scored):

- Scored lines get GLOSA-compiled instructs.
- Unscored lines fall back to parentheticals.
- The transition is seamless — the model doesn't know or care where the instruct string came from.

When the **Stage Director** annotates a screenplay:

- Every dialogue line gets an instruct string (the LLM annotates every scene).
- The annotations can be reviewed and hand-tuned before generation.
- Subsequent `glosa compile` runs use the embedded annotations deterministically — no LLM needed.

---

## 5. Observability & Feedback

### 5.1 Compilation Diagnostics

`GlosaCompiler.compile()` returns diagnostics alongside instruct strings:

- **Warnings**: Unclosed `<SceneContext>`, `<Intent>` with closing tag but zero enclosed dialogue lines, `<Constraint>` referencing a character name not found in the dialogue line list.
- **Info**: Number of scored lines, number of unscored lines (will use parenthetical fallback), active directive summary per scene.

### 5.2 Instruct Provenance

Every compiled instruct string must be traceable to the directives that produced it. `CompilationResult` includes provenance data:

```swift
public struct InstructProvenance {
    public let lineIndex: Int
    public let characterName: String
    public let sceneContext: SceneContext?     // active scene, if any
    public let intent: ResolvedIntent?         // active intent with arc position
    public let constraint: Constraint?         // active constraint for this character
    public let composedInstruct: String        // the output string
}
```

This supports review: *"this instruct string, for this character's line, was composed from these directives — was the resulting audio good?"*

### 5.3 Feedback Loop

Produciesta (or `diga`) logs provenance alongside generated audio. The workflow:

1. Generate audio from a scored screenplay.
2. Review: listen to each line, compare instruct provenance with audio quality.
3. Identify effective directions (vocabulary that the model responds to well).
4. Encode findings back into GLOSA annotations — adjust attribute values, refine `direction` phrases, tune `ceiling` levels.
5. Update the `VocabularyGlossary` with newly discovered effective terms so the Stage Director uses them in future annotation passes.

This feedback loop spans both roles: the **compiler** provides provenance data for review; the **Stage Director** consumes the updated glossary to generate better annotations. Produciesta orchestrates the loop.

---

## 6. Extensibility

- The three core elements (SceneContext, Intent, Constraint) are the grammar.
- Attribute values (emotion names, pace values, direction phrases) are the vocabulary.
- New attributes can be added to existing elements without grammar changes.
- New element types (e.g., `<Transition>` for scene-to-scene emotional bridges) can be added as the language matures.
- Attribute values are **open vocabulary** — not restricted to an enum. The model interprets natural language.
- `InstructComposer` templates can be versioned and swapped without changing the parser or resolver.
- The `VocabularyGlossary` evolves independently of the grammar — new effective terms are discovered through the feedback loop and immediately available to the Stage Director.

---

## 7. Implementation Plan

### Phase 1: GlosaCore — Data Model & Parser
- [ ] `Package.swift` — Swift 6.2+, macOS 26+ / iOS 26+, multi-target layout
- [ ] `GlosaScore`, `SceneContext`, `Intent`, `Constraint` data model (Swift structs, `Sendable`)
- [ ] `Intent.scoped: Bool` and `Intent.lineCount: Int?` for optional closing tag support
- [ ] `GlosaParser` — Fountain extraction: regex to pull GLOSA tags from `[[ ]]` note strings
- [ ] `GlosaParser` — FDX extraction: XMLParser delegate for `glosa:` namespace
- [ ] `GlosaValidator` — well-formedness and nesting rule checks, diagnostic output
- [ ] Tests: parse scored Fountain/FDX examples, verify `GlosaScore` structure

### Phase 2: GlosaCore — Score Resolver & Instruct Composer
- [ ] `ScoreResolver` — stateful scope tracker: given a character + line index, returns `ResolvedDirectives`
- [ ] Scoped Intent gradient: precise arc position (line N of M)
- [ ] Marker Intent gradient: linear interpolation or steady blend
- [ ] Neutral delivery when no Intent active (returns `nil` intent)
- [ ] Per-character Constraint tracking (independent, keyed by character name)
- [ ] `InstructComposer` — template-based composition: `ResolvedDirectives` -> `String`
- [ ] `InstructProvenance` — traceable mapping from directives to output
- [ ] Tests: verify scope resolution at each line position across multiple scenes

### Phase 3: GlosaCore — Public API & Compiler
- [ ] `GlosaCompiler` — public API combining parser + resolver + composer
- [ ] `CompilationResult` — `instructs: [Int: String]`, `diagnostics: [GlosaDiagnostic]`, `provenance: [InstructProvenance]`
- [ ] Fallback behavior: empty instructs dict when no GLOSA annotations present
- [ ] Tests: end-to-end compilation from scored Fountain -> instruct strings

### Phase 4: GlosaAnnotation — Element Bridge
- [ ] Add SwiftCompartido dependency to `Package.swift` (GlosaAnnotation target only)
- [ ] `GlosaAnnotatedElement` — wrapper pairing `GuionElement` with `ResolvedDirectives` and `instruct: String?`
- [ ] `GlosaAnnotatedScreenplay` — wraps `GuionParsedElementCollection` with annotated elements, score, diagnostics, provenance
- [ ] `GlosaSerializer` — write `GlosaAnnotatedScreenplay` back to Fountain with `[[ ]]` GLOSA notes
- [ ] `GlosaSerializer` — write `GlosaAnnotatedScreenplay` back to FDX with `glosa:` namespace elements
- [ ] Round-trip test: parse annotated Fountain -> `GlosaAnnotatedScreenplay` -> serialize -> parse again -> verify identical annotations
- [ ] Tests: verify `GlosaAnnotatedElement.instruct` matches `CompilationResult.instructs[index]` for all dialogue elements

### Phase 5: GlosaDirector — Stage Director
- [ ] Add SwiftBruja and SwiftAcervo dependencies to `Package.swift` (GlosaDirector target only)
- [ ] `SceneAnalyzer` — segment `GuionParsedElementCollection` into scenes by `sceneHeading` boundaries
- [ ] `SceneAnnotation` Codable struct — structured output schema for LLM response
- [ ] LLM system prompt: GLOSA spec (Sections 1-2) + VocabularyGlossary + few-shot examples
- [ ] `StageDirector.annotate()` — per-scene LLM call via `Bruja.query(as: SceneAnnotation.self)`, validation, element mapping
- [ ] `VocabularyGlossary` — default glossary JSON, project-level override support
- [ ] Tests: annotate a known screenplay, verify all dialogue lines receive instruct strings, verify GLOSA well-formedness

### Phase 6: CLI — `glosa` Command
- [ ] `glosa score <file>` — annotate a raw screenplay, write scored version to disk
- [ ] `glosa compile <file>` — compile an already-scored screenplay, print instruct table
- [ ] `glosa preview <file>` — show resolved directives per line with arc positions (no audio)
- [ ] `--model <id>` flag for LLM model override
- [ ] `--glossary <path>` flag for custom vocabulary glossary
- [ ] `--format fountain|fdx` flag for output format override

### Phase 7: Produciesta Integration
- [ ] Add glosa-av (GlosaAnnotation target) dependency to Produciesta `Package.swift`
- [ ] In `HeadlessAudioGenerator`: detect GLOSA annotations in parsed screenplay
- [ ] If annotations present: compile via `GlosaCompiler` -> `GlosaAnnotatedScreenplay`
- [ ] If no annotations: optionally invoke `StageDirector.annotate()` (requires GlosaDirector target)
- [ ] Instruct resolution: `annotatedElement.instruct ?? element.instruct` (GLOSA wins, parenthetical fallback)
- [ ] Provenance logging alongside audio generation
- [ ] End-to-end test: scored Fountain file -> audio with directed performance
- [ ] **SwiftVoxAlta requires ZERO changes** — receives `GenerationContext(phrase:instruct:)` as always

### Phase 8: Vocabulary Discovery & Feedback
- [ ] Provenance-linked audio review workflow in Produciesta
- [ ] Glossary update tooling: mark effective/ineffective terms from review
- [ ] `glosa glossary` subcommand: list, add, remove terms
- [ ] Compare output quality: template-only vs. LLM-annotated instruct strings

---

## 8. Design Principles

1. **The screenplay IS the score** — one file, one source of truth.
2. **Compiler, not component** — GlosaCore compiles annotations into instruct strings. It is not part of the TTS engine and has no audio/model dependencies.
3. **Stage Director, not ghostwriter** — the LLM generates structured annotations, not prose. The grammar and serialization are handled by code; the LLM contributes dramatic analysis.
4. **Directives live on elements** — GLOSA annotations attach to SwiftCompartido's parsed elements via `GlosaAnnotatedElement`, flowing naturally through the pipeline without index lookups.
5. **Invisible in performance, visible in rehearsal** — the audience never sees GLOSA; the pipeline always does.
6. **Director, not controller** — GLOSA sets boundaries and trajectory; the model fills in the micro-performance.
7. **Transparent downstream** — SwiftVoxAlta and VoiceLockManager never know GLOSA exists. They receive a `GenerationContext` with an instruct string, same as always.
8. **Connected by String** — GlosaCore and SwiftVoxAlta have no dependency on each other. They communicate through a plain `String` (the instruct), with Produciesta as the orchestrator.
9. **Graceful fallback** — Screenplays without GLOSA annotations work identically to today. Partially scored screenplays fall back to parentheticals for unscored lines.
10. **Format-agnostic** — same semantics whether embedded in Fountain or FDX. The `GlosaSerializer` handles format-specific encoding.
11. **Discovered vocabulary** — attribute values are empirical, co-evolving with the model. The grammar is stable; the vocabulary is alive. The `VocabularyGlossary` captures what works.
12. **Layered dependencies** — GlosaCore depends on nothing. GlosaAnnotation adds SwiftCompartido. GlosaDirector adds SwiftBruja. Each consumer imports only the layer it needs.
