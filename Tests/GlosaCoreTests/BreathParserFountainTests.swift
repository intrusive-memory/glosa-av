import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s Fountain breath extraction — the inline
/// `[[<breath/>]]` notes defined in `breath-tag.md` §5.1.
///
/// All tests follow the OPERATION SIGHING SCRIBE methodology: deterministic,
/// hermetic, untimed. The Bishop offsets in §6.4 (`20`, `31`, `43`) are the
/// canonical fixture and are asserted byte-exactly against the stripped prose
/// the actor would read. Per the supervising agent's Q#2 resolution, breath
/// offsets are measured against the notes-stripped paragraph, never the raw
/// `[[ ]]`-bearing text.
@Suite("GlosaParser Fountain breath extraction")
struct BreathParserFountainTests {

  let parser = GlosaParser()

  // MARK: - Spec §5.1 Example 1 — the Bishop case

  /// The Bishop dialogue line from breath-tag.md §5.1 Example 1. Three
  /// inline `[[<breath/>]]` notes:
  /// 1. After the colon — `length="period"`, `strength="strong"`.
  /// 2. After `authority,` — bare (defaults: comma, medium).
  /// 3. After `patriarchy,` — bare (defaults: comma, medium).
  ///
  /// Exit-criterion fixture: offsets `20`, `31`, `43` per spec §6.4.
  @Test("Example 1 — Bishop case yields three breaths at offsets 20/31/43")
  func bishopExample() throws {
    let bishopDialogue =
      "Bishop is freighted:[[<breath length=\"period\" strength=\"strong\"/>]] authority,"
      + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopDialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let score = result.score

    // The score collects all breaths discovered. Three exactly.
    #expect(score.breaths.count == 3)

    // Sorted by offset ascending (parser preserves document order, which
    // is already ascending for inline notes).
    let sorted = score.breaths.sorted { $0.characterOffset < $1.characterOffset }
    #expect(sorted == score.breaths)

    // Offsets verbatim from spec §6.4.
    #expect(score.breaths[0].characterOffset == 20)
    #expect(score.breaths[1].characterOffset == 31)
    #expect(score.breaths[2].characterOffset == 43)

    // Attributes verbatim from spec §6.4.
    #expect(score.breaths[0].length == .period)
    #expect(score.breaths[0].strength == .strong)
    #expect(score.breaths[1].length == .comma)
    #expect(score.breaths[1].strength == .medium)
    #expect(score.breaths[2].length == .comma)
    #expect(score.breaths[2].strength == .medium)

    // All three breaths reference the same scene-local dialogue paragraph.
    #expect(score.breaths.allSatisfy { $0.dialogueLineIndex == 0 })

    // The notes-stripped dialogue stored in the score is the prose the
    // actor reads — `[[ ]]` markers removed, surrounding spaces preserved.
    #expect(score.scenes.count == 1)
    let intent = score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    #expect(
      intent.dialogueLines[0]
        == "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."
    )

    // No diagnostics on the happy path.
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Spec §5.1 Example 2 — run-on with chained conjunctions

  @Test("Example 2 — run-on yields four bare comma/medium breaths")
  func runOnExample() throws {
    let runOnDialogue =
      "He kept the parish quiet[[<breath/>]] and he kept the families quiet"
      + "[[<breath/>]] and he kept the press quiet"
      + "[[<breath/>]] and he kept the diocese quiet for thirty-two years"
      + "[[<breath/>]] and then a single deposition undid every one of those silences in a single afternoon."

    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      runOnDialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let score = result.score

    // Exit criterion: exactly four bare breaths, comma length, medium strength.
    #expect(score.breaths.count == 4)
    for breath in score.breaths {
      #expect(breath.length == .comma)
      #expect(breath.strength == .medium)
      #expect(breath.dialogueLineIndex == 0)
    }

    // Offsets ascending (parser emits in document order).
    let offsets = score.breaths.map { $0.characterOffset }
    #expect(offsets == offsets.sorted())

    // No diagnostics.
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Spec §5.1 Example 3 — mixed lengths and explicit ms

  @Test("Example 3 — mixed lengths including em-dash, strong, and explicit 350ms")
  func mixedLengthsExample() throws {
    // Two dialogue paragraphs; breaths land in the first only. Use a
    // single paragraph that combines both spec §5.1 Example 3 sentences
    // so we get both an em-dash/strong breath and an explicit-350ms breath
    // on the same paragraph (dialogueLineIndex 0).
    let dialogue =
      "The model has been making bad predictions for nine seconds."
      + "[[<breath length=\"em-dash\" strength=\"strong\"/>]] The speaker prompt has drifted "
      + "because the local cues have been pulling the model into a different prosodic register "
      + "the whole time.[[<breath length=\"350ms\"/>]] You wrote a run-on."

    let notes: [String] = [
      #"<SceneContext location="the editing bay" time="3 a.m.">"#,
      #"<Intent from="patient" to="exasperated">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let score = result.score

    #expect(score.breaths.count == 2)
    #expect(score.breaths[0].length == .emDash)
    #expect(score.breaths[0].strength == .strong)
    // Explicit 350ms → .explicit(0.35) per BreathLength encoder contract.
    #expect(score.breaths[1].length == .explicit(0.35))
    // strength missing → default .medium.
    #expect(score.breaths[1].strength == .medium)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("Explicit length=\"0.4s\" parses as .explicit(0.4)")
  func explicitSecondsLength() throws {
    let dialogue = "Halt[[<breath length=\"0.4s\"/>]] and listen."
    let notes: [String] = [
      #"<SceneContext location="quiet" time="now">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 1)
    #expect(result.score.breaths[0].length == .explicit(0.4))
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - after= fallback encoding (spec §5.1)

  @Test("after=\"substring\" places the breath at the end of the first occurrence")
  func afterFallbackEncoding() throws {
    let bishopProse =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    // The dialogue is the bare prose; the breaths arrive as standalone
    // `[[<breath after="…"/>]]` notes interleaved AFTER the dialogue line,
    // mimicking the sibling-note-block encoding shown in spec §5.1.
    // Sibling notes are themselves dialogue paragraphs in the same intent
    // scope, so they share dialogueLineIndex with the prose.
    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting">"#,
      bishopProse,
      // Each sibling [[<breath …/>]] is itself a "dialogue" string in the
      // notes stream; the parser treats it like any other paragraph but
      // the regex strips the inline note and the after= substring resolver
      // anchors the breath into THIS paragraph's stripped prose (which is
      // empty after stripping). The breath ends up at offset 0 of that
      // paragraph. To exercise the after=-into-prose path on the Bishop
      // line, we put the after= note INLINE in the prose paragraph.
      "[[<breath after=\"Bishop is freighted:\"/>]]",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    // The sibling-note approach above puts the breath in a new dialogue
    // paragraph (paragraph index 1) where the prose after stripping is
    // empty, so the after= substring won't match — the parser emits a
    // warning. That's the documented behavior for an after= substring
    // that doesn't match.
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(result.score.breaths.count == 0)

    // Now exercise the success path: an inline `[[<breath after="…"/>]]`
    // riding alongside the prose it anchors into. The breath should land
    // at the end of `"Bishop is freighted:"` in the stripped prose —
    // offset 20.
    let inlineAfter =
      "Bishop is freighted: authority.[[<breath after=\"Bishop is freighted:\"/>]]"
    let notes2: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting">"#,
      inlineAfter,
      "</Intent>",
      "</SceneContext>",
    ]
    let result2 = parser.parseFountainWithDiagnostics(notes: notes2)
    #expect(result2.score.breaths.count == 1)
    #expect(result2.score.breaths[0].characterOffset == 20)
    #expect(result2.score.breaths[0].length == .comma)
    #expect(result2.score.breaths[0].strength == .medium)
    #expect(result2.diagnostics.isEmpty)
  }

  @Test("after=\"…\" with no match emits a warning and produces zero breaths")
  func afterFallbackNoMatch() throws {
    let dialogue =
      "Some prose without the anchor."
      + "[[<breath after=\"this substring is absent\"/>]]"
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 0)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
  }

  // MARK: - Error paths

  @Test("Invalid length value emits a warning and skips the breath")
  func invalidLengthValue() throws {
    let dialogue = "Some words[[<breath length=\"banana\"/>]] more words."
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 0)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("banana"))
  }

  @Test("Invalid strength value emits a warning and skips the breath")
  func invalidStrengthValue() throws {
    let dialogue = "Some words[[<breath strength=\"ultra\"/>]] more words."
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 0)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("ultra"))
  }

  @Test("Malformed explicit time string emits a warning and skips the breath")
  func malformedExplicitDuration() throws {
    let dialogue = "Some words[[<breath length=\"abcms\"/>]] more words."
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 0)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
  }

  @Test("Breath note outside any dialogue paragraph emits one warning and zero breaths")
  func breathOutsideDialogue() throws {
    // A bare `[[<breath/>]]` note appearing between structural tags but
    // before any <Intent> opens. Per spec §4.3 this is ignored with a
    // warning.
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      "[[<breath/>]]",
      #"<Intent from="a" to="b">"#,
      "Inside intent — this dialogue has no breaths.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 0)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.lowercased().contains("outside"))
  }

  // MARK: - Defaults

  @Test("Bare <breath/> defaults to length=.comma and strength=.medium")
  func bareBreathDefaults() throws {
    let dialogue = "A simple line[[<breath/>]] with one bare breath."
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 1)
    #expect(result.score.breaths[0].length == .comma)
    #expect(result.score.breaths[0].strength == .medium)
  }

  // MARK: - Scene-local dialogueLineIndex

  @Test("dialogueLineIndex counts paragraphs scene-local across intents")
  func dialogueLineIndexScoping() throws {
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      "First paragraph[[<breath/>]] in first intent.",
      "Second paragraph[[<breath/>]] in first intent.",
      "</Intent>",
      #"<Intent from="b" to="c">"#,
      "Third paragraph[[<breath/>]] in second intent.",
      "</Intent>",
      "</SceneContext>",
      // Second scene resets the counter.
      #"<SceneContext location="z" time="now">"#,
      #"<Intent from="a" to="b">"#,
      "Fresh paragraph[[<breath/>]] in new scene.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.breaths.count == 4)
    // Scene 1: paragraphs 0, 1, 2 (across both intents).
    #expect(result.score.breaths[0].sceneIndex == 0)
    #expect(result.score.breaths[0].dialogueLineIndex == 0)
    #expect(result.score.breaths[1].sceneIndex == 0)
    #expect(result.score.breaths[1].dialogueLineIndex == 1)
    #expect(result.score.breaths[2].sceneIndex == 0)
    #expect(result.score.breaths[2].dialogueLineIndex == 2)
    // Scene 2: counter reset to 0, sceneIndex advances to 1.
    #expect(result.score.breaths[3].sceneIndex == 1)
    #expect(result.score.breaths[3].dialogueLineIndex == 0)
  }
}
