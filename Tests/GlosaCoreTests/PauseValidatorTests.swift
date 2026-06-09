import Foundation
import Testing

@testable import GlosaCore

/// Tests for pause-related diagnostics in `GlosaParser` and `GlosaValidator`.
///
/// Coverage:
/// 1. "outside dialogue line" warning — the parser emits a warning when a
///    `[[<pause/>]]` note appears outside any dialogue paragraph.
/// 2. Unknown `length` warning — the parser emits a warning for an
///    unrecognized `length` value on `<pause>`.
/// 3. "`length` not valid on `<breath>`" warning (D-1) — the parser emits a
///    warning when `length` is present on `<breath>`, which no longer accepts it.
///    The breath is still produced (it becomes a phrasing hint only). No Pause
///    is created from the discarded attribute. This is the canonical D-1 test.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed. `#require` is used for count assertions before subscripting.
@Suite("Pause Validator Diagnostics")
struct PauseValidatorTests {

  let parser = GlosaParser()

  // MARK: - Fixture helpers

  private func notes(dialogue: String) -> [String] {
    [
      #"<SceneContext location="stage" time="now">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  // MARK: - Diagnostic 1: <pause/> outside dialogue paragraph

  @Test("Pause outside any dialogue paragraph emits warning; zero pauses in score")
  func pauseOutsideDialogueParagraphWarning() throws {
    // The `[[<pause/>]]` note appears between structural tags but before any
    // `<Intent>` is open. The parser must emit a warning and produce zero pauses.
    let notesOutside: [String] = [
      #"<SceneContext location="stage" time="now">"#,
      "[[<pause/>]]",
      #"<Intent from="a" to="b">"#,
      "Inside intent.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notesOutside)

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    try #require(warnings.count == 1)
    #expect(warnings[0].message.lowercased().contains("outside"))
  }

  @Test("Multiple pauses outside dialogue each produce a warning")
  func multiplePausesOutsideDialogueParagraph() throws {
    let notesOutside: [String] = [
      #"<SceneContext location="stage" time="now">"#,
      "[[<pause/>]]",
      "[[<pause length=\"beat\"/>]]",
      #"<Intent from="a" to="b">"#,
      "Inside intent.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notesOutside)

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 2)
  }

  @Test("Pause inside a dialogue paragraph does NOT emit an outside-dialogue warning")
  func pauseInsideDialogueParagraphNoWarning() throws {
    let dialogue = "A line[[<pause/>]] with one pause."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    let outsideWarnings = result.diagnostics.filter {
      $0.severity == .warning && $0.message.lowercased().contains("outside")
    }
    #expect(outsideWarnings.isEmpty)
  }

  // MARK: - Diagnostic 2: unknown length value on <pause/>

  @Test("Unknown length value on <pause/> emits warning and skips the pause")
  func unknownLengthValueOnPause() throws {
    let dialogue = "Wait[[<pause length=\"banana\"/>]] then speak."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    try #require(warnings.count == 1)
    #expect(warnings[0].message.lowercased().contains("banana"))
  }

  @Test("Unknown length on <pause/> in FDX emits warning and skips the pause")
  func unknownLengthValueOnFDXPause() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="a" time="b">
            <glosa:Intent from="x" to="y">
              <Paragraph Type="Character">
                <Text>C</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Halt</Text>
                <glosa:pause length="nonsense"/>
                <Text> and listen.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)

    #expect(result.score.pauses.isEmpty)
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    try #require(warnings.count == 1)
    #expect(warnings[0].message.lowercased().contains("length"))
  }

  // MARK: - Diagnostic 3: `length` not valid on `<breath>` (D-1)

  /// D-1 canonical test: `[[<breath length="period"/>]]` must produce:
  /// - One `Breath` in the score (the element is still a valid phrasing hint).
  /// - Zero `Pause` objects (no migration).
  /// - Exactly one `.warning` diagnostic whose message references "length".
  @Test("D-1: <breath length=\"period\"/> produces Breath + warning; no Pause")
  func breathLengthAttributeCanonicalD1Test() throws {
    let dialogue = "[[<breath length=\"period\"/>]]"
    // The breath-with-length appears as the entire dialogue paragraph;
    // after stripping the note, the stored text will be empty.
    let notesD1: [String] = [
      #"<SceneContext location="stage" time="now">"#,
      #"<Intent from="a" to="b">"#,
      dialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let result = parser.parseFountainWithDiagnostics(notes: notesD1)

    // A Breath is produced — the element remains a valid phrasing hint.
    #expect(result.score.breaths.count == 1)

    // No Pause created — `length` on `<breath>` is not migrated (D-1).
    #expect(result.score.pauses.isEmpty)

    // Exactly one warning about the invalid `length` attribute.
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    try #require(warnings.count == 1)
    #expect(warnings[0].severity == .warning)
    #expect(warnings[0].message.contains("length"))
    #expect(warnings[0].message.lowercased().contains("breath"))
  }

  @Test("D-1: <breath/> without length has no warning")
  func breathWithoutLengthNoWarning() throws {
    let dialogue = "A line[[<breath/>]] with one bare breath."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.breaths.count == 1)
    #expect(result.score.pauses.isEmpty)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("D-1: <breath length=\"beat\"/> in FDX produces Breath + warning; no Pause")
  func fdxBreathLengthAttributeWarning() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="a" time="b">
            <glosa:Intent from="x" to="y">
              <Paragraph Type="Character">
                <Text>C</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Halt</Text>
                <glosa:breath length="beat"/>
                <Text> and listen.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)

    // One breath produced (strength defaults to .medium).
    #expect(result.score.breaths.count == 1)
    // No pause.
    #expect(result.score.pauses.isEmpty)
    // Exactly one warning about `length` on `<breath>`.
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    try #require(warnings.count == 1)
    #expect(warnings[0].message.contains("length"))
  }

  @Test("D-1: <breath length> warning does not suppress the breath's strength")
  func breathLengthWarningDoesNotSuppressStrength() throws {
    // `<breath length="period" strength="strong"/>` must yield a `Breath` with
    // `.strong` strength and exactly one warning (for `length`).
    let dialogue = "Bishop is freighted:[[<breath length=\"period\" strength=\"strong\"/>]] done."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.breaths.count == 1)
    #expect(result.score.breaths[0].strength == .strong)
    #expect(result.score.pauses.isEmpty)

    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("length"))
  }

  // MARK: - Cross-diagnostic isolation

  @Test("Well-formed <pause/> inside dialogue produces no diagnostics")
  func wellFormedPauseNoDiagnostics() throws {
    let dialogue = "A line[[<pause length=\"period\"/>]] with one pause."
    let result = parser.parseFountainWithDiagnostics(notes: notes(dialogue: dialogue))

    #expect(result.score.pauses.count == 1)
    #expect(result.diagnostics.isEmpty)
  }
}
