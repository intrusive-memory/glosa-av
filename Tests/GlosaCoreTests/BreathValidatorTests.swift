import Foundation
import Testing

@testable import GlosaCore

/// Tests for the three breath-specific diagnostics in `GlosaValidator`
/// (spec §7.7, OPERATION SIGHING SCRIBE Sortie 8).
///
/// Each test exercises exactly one diagnostic code and asserts:
/// - The expected diagnostic fires on its dedicated fixture.
/// - No other breath diagnostic codes appear on the same fixture ("only on that fixture").
///
/// All tests are deterministic, hermetic, and untimed per the mission methodology.
/// `#require` is used for count assertions before subscripting so a wrong count
/// terminates the test immediately rather than crashing on a bad subscript.
@Suite("Breath Validator Diagnostics")
struct BreathValidatorTests {

  let validator = GlosaValidator()

  // MARK: - Fixture helpers

  /// Minimal valid score with one scene, one intent, one dialogue line.
  private func singleLineScore(line: String, breaths: [Breath] = []) -> GlosaScore {
    GlosaScore(
      scenes: [
        .init(
          context: SceneContext(location: "the rectory office", time: "late afternoon"),
          intents: [
            .init(
              intent: Intent(from: "controlled", to: "indicting"),
              dialogueLines: [line]
            )
          ]
        )
      ],
      breaths: breaths
    )
  }

  // MARK: - Diagnostic 1: breathOutsideDialogue

  /// A `<breath/>` note that the parser found outside any dialogue paragraph
  /// causes a `.breathOutsideDialogue` warning when the corresponding parser
  /// diagnostic is passed to `validateBreaths(score:parserDiagnostics:)`.
  ///
  /// The score itself is empty (the parser drops out-of-dialogue breaths);
  /// the validator wraps the pre-existing parser warning and re-emits it with
  /// the machine-readable code.
  @Test("breathOutsideDialogue: wraps parser warning with correct code")
  func breathOutsideDialogue() throws {
    // Simulate the diagnostic the Fountain parser emits for an out-of-dialogue
    // breath note. The canonical message substring is "outside any dialogue paragraph".
    let parserWarning = GlosaDiagnostic(
      severity: .warning,
      message: "Breath note found outside any dialogue paragraph; ignoring",
      line: 3
    )

    let score = GlosaScore()  // empty — parser already dropped the breath
    let diagnostics = validator.validateBreaths(
      score: score,
      parserDiagnostics: [parserWarning]
    )

    // Must fire exactly one breathOutsideDialogue warning.
    let outOfDialogue = diagnostics.filter { $0.code == .breathOutsideDialogue }
    try #require(outOfDialogue.count == 1)
    #expect(outOfDialogue[0].severity == .warning)
    #expect(outOfDialogue[0].line == 3)

    // Must NOT fire duplicate or missing-breath codes on this fixture.
    #expect(!diagnostics.contains { $0.code == .breathDuplicateOffset })
    #expect(!diagnostics.contains { $0.code == .breathMissingOnLongLine })
  }

  /// FDX parser variant: "Breath element found outside any dialogue paragraph"
  /// also matches the substring check and is wrapped identically.
  @Test("breathOutsideDialogue: wraps FDX parser variant message")
  func breathOutsideDialogueFDX() throws {
    let fdxWarning = GlosaDiagnostic(
      severity: .warning,
      message: "Breath element found outside any dialogue paragraph; ignoring",
      line: nil
    )

    let score = GlosaScore()
    let diagnostics = validator.validateBreaths(
      score: score,
      parserDiagnostics: [fdxWarning]
    )

    let outOfDialogue = diagnostics.filter { $0.code == .breathOutsideDialogue }
    try #require(outOfDialogue.count == 1)
    #expect(outOfDialogue[0].severity == .warning)
    #expect(outOfDialogue[0].line == nil)
  }

  /// A clean score with no parser diagnostics produces no breathOutsideDialogue warning.
  @Test("breathOutsideDialogue: no warning when parser reports no out-of-dialogue breath")
  func noOutOfDialogueWithCleanInput() {
    let score = singleLineScore(
      line: "Hello.",
      breaths: [Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 5)]
    )
    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(!diagnostics.contains { $0.code == .breathOutsideDialogue })
  }

  // MARK: - Diagnostic 2: breathDuplicateOffset

  /// Two `<breath/>` markers on the same dialogue line that share the same
  /// `(dialogueLineIndex, characterOffset)` pair produce one `.breathDuplicateOffset`
  /// warning.
  @Test("breathDuplicateOffset: fires when two breaths share offset on same line")
  func breathDuplicateOffset() throws {
    // Both breaths target dialogueLineIndex 0, characterOffset 20.
    let score = singleLineScore(
      line:
        "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.",
      breaths: [
        Breath(
          sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .period,
          strength: .strong),
        Breath(
          sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .comma,
          strength: .medium),
      ]
    )

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])

    let duplicates = diagnostics.filter { $0.code == .breathDuplicateOffset }
    try #require(duplicates.count == 1)
    #expect(duplicates[0].severity == .warning)

    // Must NOT fire out-of-dialogue or missing-breath codes on this fixture.
    // (The line has breaths, so the missing-breath info should not fire.)
    #expect(!diagnostics.contains { $0.code == .breathOutsideDialogue })
    #expect(!diagnostics.contains { $0.code == .breathMissingOnLongLine })
  }

  /// Two breaths with the SAME `dialogueLineIndex` but DIFFERENT `characterOffset`
  /// values on the same line are not flagged as duplicates.
  @Test("breathDuplicateOffset: no warning when offsets differ on same line")
  func noFalsePositiveDifferentOffsets() {
    let score = singleLineScore(
      line:
        "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.",
      breaths: [
        Breath(
          sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .period,
          strength: .strong),
        Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 31),
        Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 43),
      ]
    )

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(!diagnostics.contains { $0.code == .breathDuplicateOffset })
  }

  /// One scene with two dialogue lines: breaths on different lines that
  /// share a `characterOffset` are NOT duplicates (different positions).
  @Test("breathDuplicateOffset: no false positive for breaths on different lines in same scene")
  func noFalsePositiveDifferentLines() {
    // One scene, two dialogue lines. Breaths are on DIFFERENT lines (index 0 and 1),
    // same characterOffset — NOT a duplicate since they are distinct positions.
    let score = GlosaScore(
      scenes: [
        .init(
          context: SceneContext(location: "the study", time: "evening"),
          intents: [
            .init(
              intent: Intent(from: "calm", to: "tense"),
              dialogueLines: [
                "First line of dialogue here.",
                "Second line of dialogue here.",
              ]
            )
          ]
        )
      ],
      breaths: [
        Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 5),
        // Same character offset as the breath above, but on a different
        // dialogue line — must not be flagged as a duplicate.
        Breath(sceneIndex: 0, dialogueLineIndex: 1, characterOffset: 5),
      ]
    )

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(!diagnostics.contains { $0.code == .breathDuplicateOffset })
  }

  // MARK: - Diagnostic 3: breathMissingOnLongLine

  /// A dialogue line that exceeds 180 characters but has no breath annotations
  /// produces one `.breathMissingOnLongLine` info diagnostic.
  @Test("breathMissingOnLongLine: fires info for long line with no breaths")
  func breathMissingOnLongLine() throws {
    // 181+ character dialogue line — safely over the 180-char threshold.
    let longLine =
      "He kept the parish quiet and he kept the families quiet and he kept the press quiet "
      + "and he kept the diocese quiet for thirty-two years and then a single deposition undid "
      + "every single one of those silences in a single afternoon."

    #expect(longLine.count > 180)

    let score = singleLineScore(line: longLine, breaths: [])

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])

    let missing = diagnostics.filter { $0.code == .breathMissingOnLongLine }
    try #require(missing.count == 1)
    #expect(missing[0].severity == .info)

    // Must NOT fire out-of-dialogue or duplicate codes on this fixture.
    #expect(!diagnostics.contains { $0.code == .breathOutsideDialogue })
    #expect(!diagnostics.contains { $0.code == .breathDuplicateOffset })
  }

  /// A long line WITH breath annotations must NOT produce a breathMissingOnLongLine
  /// info diagnostic — the condition checks for ZERO annotations.
  @Test("breathMissingOnLongLine: no info when long line has at least one breath")
  func noInfoWhenLongLineHasBreath() {
    let longLine =
      "He kept the parish quiet and he kept the families quiet and he kept the press quiet "
      + "and he kept the diocese quiet for thirty-two years and then a single deposition undid "
      + "every single one of those silences in a single afternoon."

    #expect(longLine.count > 180)

    let score = singleLineScore(
      line: longLine,
      breaths: [Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 85)]
    )

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(!diagnostics.contains { $0.code == .breathMissingOnLongLine })
  }

  /// A short, clean line (well under 180 characters) never triggers the info diagnostic.
  @Test("breathMissingOnLongLine: no info for short clean line")
  func noInfoForShortLine() {
    let score = singleLineScore(line: "I noticed.", breaths: [])
    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(!diagnostics.contains { $0.code == .breathMissingOnLongLine })
  }

  /// A single-sentence colon-list line of 120+ characters with no breaths
  /// triggers the info diagnostic (trigger condition 2 from spec §6.1).
  @Test("breathMissingOnLongLine: fires info for colon-list pattern at 120+ chars")
  func breathMissingColonListPattern() throws {
    // 120+ characters, single sentence (no terminal punctuation), colon + comma list.
    // Manually verified to be >= 120 chars and < 181 chars.
    let colonListLine =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology and many other grievances here"

    #expect(colonListLine.count >= 120)
    // Verify single-sentence (no internal . ? !)
    #expect(!colonListLine.contains("."))
    #expect(!colonListLine.contains("?"))
    #expect(!colonListLine.contains("!"))
    // Verify colon-list pattern (colon present, followed by comma-separated content)
    #expect(colonListLine.contains(":"))

    let score = singleLineScore(line: colonListLine, breaths: [])
    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])

    let missing = diagnostics.filter { $0.code == .breathMissingOnLongLine }
    try #require(missing.count == 1)
    #expect(missing[0].severity == .info)

    #expect(!diagnostics.contains { $0.code == .breathOutsideDialogue })
    #expect(!diagnostics.contains { $0.code == .breathDuplicateOffset })
  }

  // MARK: - Cross-fixture isolation

  /// A perfectly annotated Bishop line (three breaths, correct offsets) produces
  /// zero breath diagnostics of any kind.
  @Test("No diagnostics on a well-annotated Bishop line")
  func noBreathDiagnosticsOnWellAnnotatedLine() {
    let bishopLine =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    let score = singleLineScore(
      line: bishopLine,
      breaths: [
        Breath(
          sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .period,
          strength: .strong),
        Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 31),
        Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 43),
      ]
    )

    let diagnostics = validator.validateBreaths(score: score, parserDiagnostics: [])
    #expect(diagnostics.isEmpty)
  }
}
