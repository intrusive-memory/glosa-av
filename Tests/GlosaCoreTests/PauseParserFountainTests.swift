import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s Fountain pause extraction — the inline
/// `[[<pause/>]]` notes defined by the `<pause>` element spec.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed. Offsets are measured against the notes-stripped paragraph
/// (the "prose the actor reads"), matching the Fountain breath-offset convention
/// in `BreathParserFountainTests`.
@Suite("GlosaParser Fountain pause extraction")
struct PauseParserFountainTests {

  let parser = GlosaParser()

  // MARK: - Minimal fixture helpers

  /// Wraps a single dialogue line in a minimal SceneContext + Intent.
  private func notes(dialogue: String) -> [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  // MARK: - Basic pause parsing

  @Test("Bare <pause/> defaults to length=.period")
  func barePauseDefaults() throws {
    let dialogue = "Hold:[[<pause/>]] then speak."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("Bare <pause/> offset is measured against the stripped prose")
  func barePauseOffset() throws {
    // "Hold:" is 5 characters; the pause follows it at offset 5.
    let dialogue = "Hold:[[<pause/>]] then speak."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].characterOffset == 5)
  }

  @Test("<pause length=\"period\"/> parses as .period")
  func pauseLengthPeriod() throws {
    let dialogue = "Wait.[[<pause length=\"period\"/>]] Continue."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"beat\"/> parses as .beat")
  func pauseLengthBeat() throws {
    let dialogue = "Silence.[[<pause length=\"beat\"/>]] Resume."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .beat)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"comma\"/> parses as .comma")
  func pauseLengthComma() throws {
    let dialogue = "Word,[[<pause length=\"comma\"/>]] next."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .comma)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"semicolon\"/> parses as .semicolon")
  func pauseLengthSemicolon() throws {
    let dialogue = "First clause;[[<pause length=\"semicolon\"/>]] second clause."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .semicolon)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"em-dash\"/> parses as .emDash")
  func pauseLengthEmDash() throws {
    let dialogue = "The answer[[<pause length=\"em-dash\"/>]] is no."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .emDash)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"350ms\"/> parses as .explicit(0.35)")
  func pauseLengthExplicitMilliseconds() throws {
    let dialogue = "Listen.[[<pause length=\"350ms\"/>]] Now."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .explicit(0.35))
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<pause length=\"0.4s\"/> parses as .explicit(0.4)")
  func pauseLengthExplicitSeconds() throws {
    let dialogue = "Ready?[[<pause length=\"0.4s\"/>]] Go."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .explicit(0.4))
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Multiple pauses in one line

  @Test("Two pause markers in one line are parsed in order with correct offsets")
  func multiplePausesInOneLine() throws {
    // "First" = 5 chars, pause at 5; "First pause " = 12 chars + another pause at 12.
    let dialogue = "First[[<pause/>]] pause, then[[<pause length=\"beat\"/>]] done."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 2)
    // Offsets ascending.
    let offsets = result.score.pauses.map(\.characterOffset)
    #expect(offsets == offsets.sorted())
    // First pause at "First" (5), second at "First pause, then" (18).
    #expect(result.score.pauses[0].characterOffset == 5)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.score.pauses[1].length == .beat)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Pause and breath co-located on the same line

  @Test("Pause and breath can appear in the same line at different offsets")
  func pauseAndBreathSameLine() throws {
    // Breath at "Hello" (5), pause at "Hello world" (11).
    let dialogue = "Hello[[<breath/>]] world[[<pause/>]] done."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.breaths.count == 1)
    #expect(result.score.pauses.count == 1)
    // The pause offset is measured against the fully stripped prose (both
    // breath and pause markers removed), so breath strips first.
    #expect(result.score.breaths[0].characterOffset == 5)
    // "Hello world" = 11 characters before the pause.
    #expect(result.score.pauses[0].characterOffset == 11)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Pause stripped text

  @Test("Pause markers are stripped from the stored dialogue text")
  func pauseMarkersStrippedFromStoredText() throws {
    let dialogue = "Bishop is freighted:[[<pause length=\"period\"/>]] authority."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.scenes.count == 1)
    let intent = result.score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    // The stored prose must not contain any `[[ ]]` markers.
    #expect(intent.dialogueLines[0] == "Bishop is freighted: authority.")
    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].characterOffset == 20)
  }

  // MARK: - Scene-local indexing

  @Test("Pause dialogueLineIndex is scene-local across intents")
  func pauseDialogueLineIndexScoping() throws {
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      "First paragraph[[<pause/>]] in first intent.",
      "Second paragraph[[<pause/>]] in first intent.",
      "</Intent>",
      #"<Intent from="b" to="c">"#,
      "Third paragraph[[<pause/>]] in second intent.",
      "</Intent>",
      "</SceneContext>",
      // Second scene resets the counter.
      #"<SceneContext location="z" time="now">"#,
      #"<Intent from="a" to="b">"#,
      "Fresh paragraph[[<pause/>]] in new scene.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.pauses.count == 4)
    // Scene 1: paragraphs 0, 1, 2 (across both intents).
    #expect(result.score.pauses[0].sceneIndex == 0)
    #expect(result.score.pauses[0].dialogueLineIndex == 0)
    #expect(result.score.pauses[1].sceneIndex == 0)
    #expect(result.score.pauses[1].dialogueLineIndex == 1)
    #expect(result.score.pauses[2].sceneIndex == 0)
    #expect(result.score.pauses[2].dialogueLineIndex == 2)
    // Scene 2: counter reset to 0.
    #expect(result.score.pauses[3].sceneIndex == 1)
    #expect(result.score.pauses[3].dialogueLineIndex == 0)
  }

  // MARK: - Error paths

  @Test("Unknown length value emits a warning and skips the pause (no Pause in score)")
  func unknownLengthValue() throws {
    let dialogue = "Wait[[<pause length=\"banana\"/>]] then speak."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("banana"))
  }

  @Test("Malformed explicit duration emits a warning and skips the pause")
  func malformedExplicitDuration() throws {
    let dialogue = "Wait[[<pause length=\"abcms\"/>]] then speak."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
  }

  @Test("Pause note outside any dialogue paragraph emits one warning and zero pauses")
  func pauseOutsideDialogue() throws {
    // A bare `[[<pause/>]]` note appearing between structural tags but before
    // any `<Intent>` opens. Per the parser contract this is ignored with a warning.
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      "[[<pause/>]]",
      #"<Intent from="a" to="b">"#,
      "Inside intent — this dialogue has no pauses.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.lowercased().contains("outside"))
  }

  // MARK: - <breath length="…"> → Breath with warning (D-1)

  /// Decision D-1: `<breath>` no longer accepts `length`. When `length` is
  /// present on `<breath>`, the parser emits a warning and still produces a
  /// `Breath` (phrasing hint only — the length is discarded). No `Pause` is
  /// created from the ignored attribute.
  @Test("<breath length=\"period\"/> parses to a Breath with a warning; no Pause created")
  func breathLengthAttributeEmitsWarningAndProduceBreathNotPause() throws {
    let dialogue = "Bishop is freighted:[[<breath length=\"period\"/>]] authority."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    // A Breath is still produced (the element is a valid phrasing hint).
    #expect(result.score.breaths.count == 1)

    // No Pause is created — `length` on `<breath>` is not migrated (D-1).
    #expect(result.score.pauses.isEmpty)

    // Exactly one warning about the invalid attribute.
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("length"))
  }

  @Test("<breath/> (no length) parses to a Breath with no diagnostics")
  func breathWithoutLengthHasNoDiagnostics() throws {
    let dialogue = "A line[[<breath/>]] with one bare breath."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.breaths.count == 1)
    #expect(result.score.pauses.isEmpty)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("parseFountain shim returns same pauses as parseFountainWithDiagnostics")
  func parseFountainShimPreservesPauses() throws {
    let notesList = notes(dialogue: "Go.[[<pause length=\"beat\"/>]] Stop.")
    let shimScore = parser.parseFountain(notes: notesList)
    let diagResult = parser.parseFountainWithDiagnostics(notes: notesList)

    #expect(shimScore == diagResult.score)
    #expect(shimScore.pauses.count == 1)
    #expect(shimScore.pauses[0].length == .beat)
  }
}
