import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s FDX pause extraction — the `<glosa:pause/>`
/// self-closing elements in FDX XML.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed. Offset semantics mirror the Fountain path exactly: the
/// offset of a `<glosa:pause/>` in FDX is the `unicodeScalars.count` of all
/// `<Text>` runs that precede it within the enclosing `<Paragraph>`.
@Suite("GlosaParser FDX pause extraction")
struct PauseParserFDXTests {

  let parser = GlosaParser()

  // MARK: - Minimal FDX helper

  /// Builds a minimal FDX XML document around a single `<Paragraph Type="Dialogue">`.
  private func fdxXML(dialogueParagraphContent: String) -> Data {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="the rectory office" time="late afternoon">
            <glosa:Intent from="controlled" to="indicting" pace="moderate">
              <Paragraph Type="Character">
                <Text>THE PRACTITIONER</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                \(dialogueParagraphContent)
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    return xml.data(using: .utf8)!
  }

  // MARK: - Basic pause parsing

  @Test("Bare <glosa:pause/> defaults to length=.period")
  func barePauseDefaults() throws {
    let data = fdxXML(
      dialogueParagraphContent: "<Text>Halt</Text><glosa:pause/><Text> and listen.</Text>")
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.score.pauses[0].characterOffset == 4)  // after "Halt"
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<glosa:pause length=\"beat\"/> parses as .beat")
  func pauseLengthBeat() throws {
    let data = fdxXML(
      dialogueParagraphContent: "<Text>Wait.</Text><glosa:pause length=\"beat\"/><Text> Now.</Text>"
    )
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .beat)
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<glosa:pause length=\"350ms\"/> parses as .explicit(0.35)")
  func pauseLengthExplicitMilliseconds() throws {
    let data = fdxXML(
      dialogueParagraphContent: "<Text>One</Text><glosa:pause length=\"350ms\"/><Text> two.</Text>")
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .explicit(0.35))
    #expect(result.diagnostics.isEmpty)
  }

  @Test("<glosa:pause length=\"em-dash\"/> parses as .emDash")
  func pauseLengthEmDash() throws {
    let data = fdxXML(
      dialogueParagraphContent:
        "<Text>The truth</Text><glosa:pause length=\"em-dash\"/><Text> is clear.</Text>")
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].length == .emDash)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Pause offset in mixed-content paragraph

  /// Pauses interleaved with breath markers must each record their offset
  /// against the accumulated `<Text>` content preceding them.
  @Test("Pause after breath uses cumulative text offset")
  func pauseOffsetAfterBreath() throws {
    // "Bishop is freighted:" (20 chars) → breath → " authority," → pause.
    let content = """
      <Text>Bishop is freighted:</Text>
      <glosa:breath length="period" strength="strong"/>
      <Text> authority,</Text>
      <glosa:pause length="period"/>
      <Text> done.</Text>
      """
    let data = fdxXML(dialogueParagraphContent: content)
    let result = parser.parseFDXWithDiagnostics(data: data)

    // One breath (with length warning per D-1) and one pause.
    #expect(result.score.breaths.count == 1)
    #expect(result.score.pauses.count == 1)
    // Breath offset = 20 (after "Bishop is freighted:").
    #expect(result.score.breaths[0].characterOffset == 20)
    // Pause offset = 20 + 10 = 30 (after "Bishop is freighted:" + " authority,").
    #expect(result.score.pauses[0].characterOffset == 30)
    // One warning from the `length` attribute on `<breath>` (D-1).
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("length"))
  }

  // MARK: - FDX Bishop case with pauses

  @Test("FDX Bishop case with pause after colon yields correct offset and length")
  func bishopFDXWithPause() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="the rectory office" time="late afternoon">
            <glosa:Intent from="controlled" to="indicting" pace="moderate">
              <Paragraph Type="Character">
                <Text>THE PRACTITIONER</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Bishop is freighted:</Text>
                <glosa:pause length="period"/>
                <Text> authority, patriarchy, done.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let data = xml.data(using: .utf8)!
    let result = parser.parseFDXWithDiagnostics(data: data)
    let score = result.score

    // Exactly one pause.
    #expect(score.pauses.count == 1)
    // No breaths in this variant.
    #expect(score.breaths.isEmpty)
    // Pause at offset 20 (after "Bishop is freighted:").
    #expect(score.pauses[0].characterOffset == 20)
    #expect(score.pauses[0].length == .period)
    // All structural fields correct.
    #expect(score.pauses[0].sceneIndex == 0)
    #expect(score.pauses[0].dialogueLineIndex == 0)
    // No diagnostics on the happy path.
    #expect(result.diagnostics.isEmpty)
    // The stored dialogue text must not contain any pause markers.
    let intent = score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    #expect(
      intent.dialogueLines[0]
        == "Bishop is freighted: authority, patriarchy, done."
    )
  }

  // MARK: - Error paths

  @Test("Invalid length attribute emits warning and skips the pause")
  func invalidLengthAttribute() throws {
    let data = fdxXML(
      dialogueParagraphContent:
        "<Text>Halt</Text><glosa:pause length=\"nonsense\"/><Text> and listen.</Text>")
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].severity == .warning)
    #expect(result.diagnostics[0].message.contains("length"))
  }

  @Test("Malformed explicit length emits warning and skips the pause")
  func malformedExplicitLength() throws {
    let data = fdxXML(
      dialogueParagraphContent:
        "<Text>Halt</Text><glosa:pause length=\"abcms\"/><Text> and listen.</Text>")
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.pauses.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].severity == .warning)
  }

  // MARK: - Pause outside a dialogue paragraph

  @Test("Pause inside Action paragraph emits warning and is dropped")
  func pauseOutsideDialogue() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="a" time="b">
            <glosa:Intent from="x" to="y">
              <Paragraph Type="Action">
                <Text>The room</Text>
                <glosa:pause/>
                <Text> is silent.</Text>
              </Paragraph>
              <Paragraph Type="Character">
                <Text>C</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Hello.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)
    #expect(result.score.pauses.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].severity == .warning)
    #expect(result.diagnostics[0].message.lowercased().contains("dialogue"))
  }

  // MARK: - <glosa:breath length="…"> in FDX → Breath + warning, no Pause (D-1)

  /// Decision D-1: `<glosa:breath length="…"/>` in FDX emits a warning and
  /// still produces a `Breath`. No `Pause` is created from the ignored attribute.
  @Test("<glosa:breath length=\"period\"/> in FDX produces Breath with warning, no Pause")
  func fdxBreathLengthEmitsWarningAndProducesBreathNotPause() throws {
    let data = fdxXML(
      dialogueParagraphContent:
        "<Text>Bishop is freighted:</Text><glosa:breath length=\"period\" strength=\"strong\"/><Text> authority.</Text>"
    )
    let result = parser.parseFDXWithDiagnostics(data: data)

    // One breath produced — the element is still a valid phrasing hint.
    #expect(result.score.breaths.count == 1)
    // No pause created from the discarded length attribute.
    #expect(result.score.pauses.isEmpty)
    // Exactly one warning about the invalid length attribute on <breath>.
    let warnings = result.diagnostics.filter { $0.severity == .warning }
    #expect(warnings.count == 1)
    #expect(warnings[0].message.contains("length"))
  }

  // MARK: - parseFDX shim

  @Test("parseFDX shim returns same pauses as parseFDXWithDiagnostics")
  func parseFDXShimPreservesPauses() throws {
    let data = fdxXML(dialogueParagraphContent: "<Text>One</Text><glosa:pause/><Text> two.</Text>")
    let shimScore = parser.parseFDX(data: data)
    let diagScore = parser.parseFDXWithDiagnostics(data: data).score
    #expect(shimScore == diagScore)
    #expect(shimScore.pauses.count == 1)
  }
}
