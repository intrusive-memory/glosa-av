import Foundation
import GlosaCore

/// Static prompt templates for the Stage Director's LLM interaction.
///
/// The system prompt contains GLOSA element definitions, scope rules,
/// and a placeholder for ``VocabularyGlossary`` injection. Few-shot
/// examples show the LLM how to produce ``SceneAnnotation`` JSON from
/// scene text.
///
/// ## Design
///
/// Prompts are composed of three layers:
/// 1. **System prompt** — GLOSA spec + glossary terms (static text with glossary interpolation).
/// 2. **Few-shot examples** — (scene text, SceneAnnotation JSON) pairs in the user prompt.
/// 3. **Scene text** — the actual scene for the LLM to annotate.
public enum Prompts {

  // MARK: - System Prompt

  /// Build the LLM system prompt with GLOSA spec and glossary terms.
  ///
  /// - Parameter glossary: The vocabulary glossary to inject into the prompt.
  ///   If `nil`, the glossary section is omitted.
  /// - Returns: A system prompt string ready for ``SwiftBruja/Bruja``.
  public static func systemPrompt(glossary: VocabularyGlossary? = nil) -> String {
    var parts: [String] = []

    parts.append(glosaSpecSection)
    parts.append(scopeRulesSection)
    parts.append(outputFormatSection)
    parts.append(breathPlacementSection)
    parts.append(pausePlacementSection)

    if let glossary {
      parts.append(glossarySection(glossary))
    }

    return parts.joined(separator: "\n\n")
  }

  // MARK: - GLOSA Spec Section

  static let glosaSpecSection = """
    You are a Stage Director for screenplay performance annotation. Your job is to \
    analyze a scene from a screenplay and produce GLOSA annotations that direct how \
    dialogue should be performed by a text-to-speech system.

    GLOSA defines three element types:

    ## SceneContext — Scene-Level Environment
    Establishes the physical and atmospheric environment for a scene.
    - `location` (required): Physical setting (e.g., "cramped office", "open field at night")
    - `time` (required): Time of day / temporal context (e.g., "late night", "early morning")
    - `ambience` (optional): Background audio / environmental sound (e.g., "rain on windows", "distant traffic")

    ## Intent — Emotional Trajectory
    Defines the emotional arc and delivery pacing for a range of dialogue lines.
    - `from` (required): Starting emotional state (e.g., "calm", "frustrated", "guarded")
    - `to` (required): Target emotional state (e.g., "angry", "resigned", "vulnerable")
    - `pace` (optional): Delivery speed — slow, moderate, fast, accelerating, decelerating
    - `spacing` (optional): Pause/gap between lines — "beat", "long pause", "immediate", "overlapping"
    - `startLine` (required): Zero-based dialogue line index where this intent begins
    - `endLine` (required): Zero-based dialogue line index where this intent ends (inclusive)
    - `scoped` (required): true if the intent covers a precise range, false for marker-style

    The emotional arc is a gradient from `from` to `to` across the affected lines — not a binary switch. \
    Intents do NOT nest. A new Intent always supersedes any previous one.

    ## Constraint — Character Behavioral Limits
    Sets the performative boundaries for a specific character's dialogue.
    - `character` (required): Character name this constraint applies to
    - `direction` (required): Natural-language performance direction
    - `register` (optional): Vocal register — low, mid, high
    - `ceiling` (optional): Emotional intensity ceiling — subdued, moderate, intense, explosive

    Constraints apply to all subsequent dialogue for the named character. \
    Multiple constraints for different characters coexist independently.
    """

  // MARK: - Scope Rules Section

  static let scopeRulesSection = """
    ## Scope Rules

    1. SceneContext is the outermost scope. All dialogue within a scene inherits its environment.
    2. Intent defines emotional arcs within a scene:
       - Scoped intents cover exactly the specified line range (startLine to endLine). \
    Gradient position is precise.
       - After an intent ends, delivery returns to neutral until the next intent begins.
    3. Intents do NOT nest — a new Intent always supersedes any previous one. \
    Never place one Intent range inside another.
    4. Constraint is a forward-applying marker keyed by character name. \
    It applies until replaced by a new Constraint for the same character.
    5. Multiple Constraints for different characters coexist independently.
    """

  // MARK: - Output Format Section

  static let outputFormatSection = """
    ## Output Format

    Respond with a JSON object matching this exact structure (SceneAnnotation):

    ```json
    {
      "sceneContext": {
        "location": "string",
        "time": "string",
        "ambience": "string or null"
      },
      "intents": [
        {
          "from": "string",
          "to": "string",
          "pace": "string or null",
          "spacing": "string or null",
          "startLine": 0,
          "endLine": 2,
          "scoped": true
        }
      ],
      "constraints": [
        {
          "character": "CHARACTER NAME",
          "direction": "string",
          "register": "string or null",
          "ceiling": "string or null"
        }
      ],
      "breaths": [
        {
          "dialogueLineIndex": 0,
          "characterOffset": 31,
          "strength": "medium"
        }
      ],
      "pauses": [
        {
          "dialogueLineIndex": 0,
          "characterOffset": 20,
          "length": "period"
        }
      ]
    }
    ```

    Rules for line indices:
    - Line indices are zero-based and refer to DIALOGUE lines only (not action, \
    character names, or parentheticals).
    - `startLine` and `endLine` are inclusive.
    - Intent ranges must not overlap.
    - Every dialogue line should be covered by exactly one intent (no gaps unless \
    neutral delivery is appropriate for that beat).

    Rules for `breaths` (silent phrasing hints — no duration):
    - `dialogueLineIndex`: zero-based index of the dialogue line (same indexing as \
    intent line indices) this breath applies to.
    - `characterOffset`: character offset within the dialogue line text where the \
    sub-utterance break goes. 0 = before the first character. The break is placed \
    between the character at offset-1 and the character at offset.
    - `strength` (optional): chunker priority — `weak` (only if necessary), \
    `medium` (default — when run exceeds budget), or `strong` (always chunk here). \
    Omit the field to use the default.
    - A breath inserts NO audible silence; it is purely a phrasing seam hint. \
    For deliberate audible silence, use `pauses` instead.
    - Omit the `breaths` array entirely (or emit `[]`) for short, structurally clean \
    lines that need no sub-utterance splitting.

    Rules for `pauses` (deliberate audible silence — always honored):
    - `dialogueLineIndex`: zero-based index of the dialogue line (same indexing as \
    intent line indices) this pause applies to.
    - `characterOffset`: character offset within the dialogue line text where the \
    silence goes. 0 = before the first character. The pause is placed between the \
    character at offset-1 and the character at offset.
    - `length` (optional): target silence duration — one of `comma` (~150 ms), \
    `semicolon` (~250 ms), `period` (default, ~400 ms), `em-dash` (~600 ms), \
    `beat` (~1000 ms), or an explicit value such as `"350ms"` or `"0.4s"`. Omit the \
    field to use the default (`period`).
    - A pause always forces a chunk seam and is always honored, regardless of the \
    chunk budget.
    - Omit the `pauses` array entirely (or emit `[]`) for lines that need no \
    deliberate dramatic stop.
    """

  // MARK: - Breath Placement Section

  static let breathPlacementSection = """
    ## Breath Placement — Silent Sub-Utterance Chunk Hints

    A `<breath/>` is a SILENT phrasing seam: it tells the chunker where a \
    sub-utterance may split, but inserts no audible silence (~0 s). It carries \
    only an optional `strength`, never a duration. For a deliberate audible stop, \
    use a `<pause/>` instead (see the Pause Placement section).

    ### When to place breaths (trigger conditions)

    Consider a dialogue line as a <breath/> candidate when ANY of the following hold:

    1. The line exceeds 180 characters (the 180-character threshold matches VoxAlta's \
    per-chunk budget at ~0.055 s/char ≈ 10 s).
    2. The line is a single sentence (no internal `.`, `?`, `!`) longer than 120 characters \
    and contains at least one of:
       - A colon followed by a list (asyndetic or otherwise) — the colon-list pattern.
       - Three or more clauses joined by coordinating conjunctions (`and`, `but`, `or`, \
    `so`, `yet`) — polysyndetic conjunctions.
       - A semicolon-joined compound sentence.
    3. The line contains a coordinating conjunction whose scope ambiguity is detectable \
    (e.g., a final list item that itself contains `and`).

    Lines that satisfy none of these conditions get no <breath/> annotations. Short, \
    structurally clean sentences (`I noticed.`, `Yeah.`) never need them.

    ### Where to place breaths (placement rules — follow priority order)

    When a line triggers, place <breath/> markers at syntactic breakpoints in this \
    priority order:

    1. **After a semicolon.** Sentence-internal stops are natural breath points.
    2. **Between clauses of a compound sentence**, immediately before the coordinating \
    conjunction:
       - With a comma (`, and` / `, but` / `, or` / `, so` / `, yet`): the breath goes \
    *after* the comma, *before* the conjunction word.
       - Polysyndetic without commas (`… quiet and he kept …`): the breath goes before \
    the conjunction directly.
       In both forms, the conjunction stays in the second chunk.
    3. **Between list items** in an asyndetic or polysyndetic list, after each comma \
    separating top-level items. Do NOT chunk inside a list item even if it contains \
    commas internally.
    4. **Before a long subordinate clause** introduced by `which`, `that`, `because`, \
    `although`, `when`, `while`, when the matrix clause is itself ≥ 60 characters.

    ### Prohibitions — do NOT place a breath:

    - Between an adjective and the noun it modifies.
    - Between a verb and a short direct object (< 30 chars).
    - Inside a noun phrase.
    - Inside a quoted string.
    - Within 10 characters of the line's start or end.
    - Closer than 30 characters to another `<breath/>`.

    ### Breath few-shot examples

    #### Positive example — list commas (the Bishop case)

    **Input dialogue line (line index 0):**
    ```
    Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
    ```

    The colon that introduces the list is a deliberate dramatic stop — it becomes a \
    `<pause>`, not a `<breath>` (see the Pause Placement section's matching Bishop \
    example). The SILENT phrasing seams between the list items are the `<breath>` \
    markers:

    **Expected `breaths` output:**
    ```json
    [
      {
        "dialogueLineIndex": 0,
        "characterOffset": 31,
        "strength": "medium"
      },
      {
        "dialogueLineIndex": 0,
        "characterOffset": 43,
        "strength": "medium"
      }
    ]
    ```

    Offset reading: offset 31 is between `authority,` and ` patriarchy,` (rule 3 — \
    between list items). Offset 43 is between `patriarchy,` and ` a history…` (rule 3). \
    Breaths carry no `length` — they are silent seams. The final list item \
    `a history of cover-ups and anti-queer theology` is not chunked even though it \
    contains `and` — the internal `and` is inside a noun phrase, and the gap between \
    offset 43 and the end of the line is under the Closer than 30 characters \
    minimum-gap prohibition. The colon at offset 20 is NOT a breath here; it is a \
    `<pause>` (see Pause Placement).

    #### Negative example — short, structurally clean sentence

    **Input dialogue line (line index 0):**
    ```
    I noticed.
    ```

    **Expected `breaths` output:**
    ```json
    []
    ```

    11 characters, single clause, no list, no chained conjunctions, no colon. None of \
    the trigger conditions fire. Emit an empty `breaths` array.
    """

  // MARK: - Pause Placement Section

  static let pausePlacementSection = """
    ## Pause Placement — Deliberate Audible Silence

    A `<pause/>` is an AUDIBLE stop with a duration. Unlike a `<breath/>` (a silent \
    phrasing seam), a pause is always honored and always forces a chunk seam, \
    regardless of the chunk budget. Use it for dramatic, intentional silence — not \
    for routine phrasing.

    ### When to place a pause (trigger conditions)

    Place a `<pause/>` when the line calls for a deliberate beat of silence:

    1. **Colon before a list or enumeration.** The colon sets up an audible \
    anticipatory beat before the items land. Insert the pause immediately after the \
    colon. (The Bishop case.)
    2. **Post-declaration beat.** After a short, weighty declarative statement that \
    lands and is meant to hang in the air before the next thought \
    (`It's over.  …  We're done here.`), insert a pause at the sentence boundary.
    3. **A dash or ellipsis marking a hesitation or trailing-off** that the writer \
    clearly intends as silence, not mere phrasing.

    Do NOT use a pause for ordinary list-item or clause phrasing — those are \
    `<breath/>` seams. Reserve pauses for moments the silence itself is doing \
    dramatic work.

    ### Which `length` to choose

    - `comma` (~150 ms) — a barely-there catch; rarely warranted for a pause.
    - `semicolon` (~250 ms) — a brief held beat.
    - `period` (default, ~400 ms) — a clear declarative stop; the colon-before-list \
    and most post-declaration beats.
    - `em-dash` (~600 ms) — an interruption or sharp cut.
    - `beat` (~1000 ms) — a long, loaded silence; use sparingly for maximum weight.
    - Explicit values (`"350ms"`, `"0.4s"`) when a preset does not fit.

    ### Pause few-shot example — colon before a list (the Bishop case)

    **Input dialogue line (line index 0):**
    ```
    Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
    ```

    The colon introduces the list, so it earns a deliberate `period`-length pause. \
    The commas between the list items are SILENT breath seams, not pauses (see the \
    Breath Placement section's matching Bishop example).

    **Expected `pauses` output:**
    ```json
    [
      {
        "dialogueLineIndex": 0,
        "characterOffset": 20,
        "length": "period"
      }
    ]
    ```

    Offset reading: offset 20 is immediately after the colon (trigger 1 — colon \
    before a list; `length: "period"` for the dramatic anticipatory beat). The list \
    commas at offsets 31 and 43 are handled as `<breath>` markers, not pauses.

    #### Negative example — no deliberate stop

    **Input dialogue line (line index 0):**
    ```
    I noticed.
    ```

    **Expected `pauses` output:**
    ```json
    []
    ```

    A short, clean line with no colon-before-list, no weighty post-declaration beat, \
    and no dramatic hesitation. Emit an empty `pauses` array.
    """

  // MARK: - Glossary Section

  /// Build the glossary section of the system prompt.
  ///
  /// - Parameter glossary: The vocabulary glossary to inject.
  /// - Returns: A formatted glossary section string.
  static func glossarySection(_ glossary: VocabularyGlossary) -> String {
    var parts: [String] = []
    parts.append("## Preferred Vocabulary")
    parts.append("")
    parts.append(
      "When choosing terms for annotations, prefer the following vocabulary. "
        + "These terms are known to produce good results with the TTS system."
    )

    if !glossary.emotions.isEmpty {
      parts.append("")
      parts.append("### Emotion Terms")
      parts.append(glossary.emotions.joined(separator: ", "))
    }

    if !glossary.directions.isEmpty {
      parts.append("")
      parts.append("### Direction Phrases")
      parts.append(glossary.directions.joined(separator: "; "))
    }

    parts.append("")
    parts.append("### Pace Terms (fixed vocabulary)")
    parts.append(glossary.paceTerms.joined(separator: ", "))

    parts.append("")
    parts.append("### Register Terms (fixed vocabulary)")
    parts.append(glossary.registerTerms.joined(separator: ", "))

    parts.append("")
    parts.append("### Ceiling Terms (fixed vocabulary)")
    parts.append(glossary.ceilingTerms.joined(separator: ", "))

    return parts.joined(separator: "\n")
  }

  // MARK: - Few-Shot Examples

  /// Build few-shot example pairs for the user prompt.
  ///
  /// Returns 2 annotated scene examples formatted as (scene text, SceneAnnotation JSON)
  /// pairs that teach the LLM the expected output format.
  ///
  /// - Returns: A string containing the few-shot examples section.
  public static func fewShotExamples() -> String {
    var parts: [String] = []

    parts.append("Here are examples of how to annotate scenes:\n")

    // Example 1: The Steam Room (Scoped Intent)
    parts.append("### Example 1: Scoped Intent with Per-Character Constraints\n")
    parts.append("**Scene text:**")
    parts.append("```")
    parts.append(example1SceneText)
    parts.append("```\n")
    parts.append("**Expected annotation:**")
    parts.append("```json")
    parts.append(example1AnnotationJSON)
    parts.append("```\n")

    // Example 2: Marker Intent + Constraint Replacement
    parts.append("### Example 2: Multiple Intents with Neutral Gap\n")
    parts.append("**Scene text:**")
    parts.append("```")
    parts.append(example2SceneText)
    parts.append("```\n")
    parts.append("**Expected annotation:**")
    parts.append("```json")
    parts.append(example2AnnotationJSON)
    parts.append("```\n")

    return parts.joined(separator: "\n")
  }

  // MARK: - Example 1: The Steam Room

  static let example1SceneText = """
    INT. STEAM ROOM - DAY

    BERNARD and KILLIAN (40's M) sit in a steam room, towels wrapped around their waist.

    BERNARD
    Have you thought about how I'm going to do it?

    KILLIAN
    I can't think about anything else.

    BERNARD
    And?

    KILLIAN
    Insulin. You need to give him a mega dose of the fast acting stuff.

    BERNARD
    Yeah, but doesn't that take a few minutes--

    KILLIAN
    He needs to be far enough away from anyone or anything that can help him.
    """

  static let example1AnnotationJSON = """
    {
      "sceneContext": {
        "location": "steam room",
        "time": "morning",
        "ambience": "hissing steam, echoing tile"
      },
      "intents": [
        {
          "from": "conspiratorial calm",
          "to": "grim resolve",
          "pace": "slow",
          "spacing": null,
          "startLine": 0,
          "endLine": 5,
          "scoped": true
        }
      ],
      "constraints": [
        {
          "character": "BERNARD",
          "direction": "nervous amateur, out of his depth, trying to sound casual",
          "register": null,
          "ceiling": "moderate"
        },
        {
          "character": "KILLIAN",
          "direction": "clinical detachment, this is business, calm and methodical",
          "register": null,
          "ceiling": "subdued"
        }
      ]
    }
    """

  // MARK: - Example 2: Bernard and Sylvia

  static let example2SceneText = """
    INT. HOME - FRONT ROOM - CONTINUOUS

    He makes it almost to the front door when her voice stops him.

    SYLVIA
    Bernard!

    BERNARD
    Yes, Satan?

    He turns.

    BERNARD
    Oh, sorry, I thought you were someone else.

    SYLVIA
    What in the name of Daisy Duke are you wearing?

    BERNARD
    They're jogging shorts, mother.

    SYLVIA
    I suppose they're fine if you're into amateur urology.

    BERNARD
    What do you want mother?
    """

  static let example2AnnotationJSON = """
    {
      "sceneContext": {
        "location": "cluttered front room, ceramic figurines on shelves",
        "time": "pre-dawn",
        "ambience": "quiet house, distant pool filter"
      },
      "intents": [
        {
          "from": "startled",
          "to": "sardonic",
          "pace": "fast",
          "spacing": null,
          "startLine": 0,
          "endLine": 3,
          "scoped": true
        },
        {
          "from": "accusatory",
          "to": "grudging surrender",
          "pace": "accelerating",
          "spacing": null,
          "startLine": 6,
          "endLine": 7,
          "scoped": true
        }
      ],
      "constraints": [
        {
          "character": "BERNARD",
          "direction": "impatient, trying to escape, dry wit as defense mechanism",
          "register": null,
          "ceiling": "moderate"
        },
        {
          "character": "SYLVIA",
          "direction": "imperious matriarch, weaponized passive aggression, every word a power move",
          "register": null,
          "ceiling": "intense"
        }
      ]
    }
    """

  // MARK: - User Prompt Construction

  /// Build the user prompt for a single scene annotation request.
  ///
  /// Combines few-shot examples with the actual scene text the LLM should annotate.
  ///
  /// - Parameters:
  ///   - sceneText: The readable scene text extracted from screenplay elements.
  ///   - dialogueLineCount: The number of dialogue lines in the scene.
  /// - Returns: A user prompt string ready for ``SwiftBruja/Bruja``.
  public static func userPrompt(sceneText: String, dialogueLineCount: Int) -> String {
    var parts: [String] = []

    parts.append(fewShotExamples())

    parts.append("---\n")
    parts.append(
      "Now annotate this scene. It contains \(dialogueLineCount) dialogue lines (indices 0 to \(dialogueLineCount - 1)).\n"
    )
    parts.append("**Scene text:**")
    parts.append("```")
    parts.append(sceneText)
    parts.append("```")

    return parts.joined(separator: "\n")
  }
}
