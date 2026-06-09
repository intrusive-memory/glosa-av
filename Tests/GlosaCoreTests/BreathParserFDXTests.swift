import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s FDX breath extraction — the `<glosa:breath/>`
/// self-closing elements.
///
/// `Breath` is now a silent phrasing hint with no duration; `length` assertions
/// have been removed (OPERATION CLEAVING BREATH, Sortie 8). Strength is the
/// only per-breath attribute tested here.
///
/// The Bishop offsets in §6.4 (`20`, `31`, `43`) are the canonical fixture and
/// must match the Fountain equivalent in `BreathParserFountainTests` byte-for-byte.
/// The mixed-content shape this suite parses (interleaved `<Text>` runs with
/// `<glosa:breath/>` siblings) also exercises the Q#3 per-`<Text>`-reset bug fix.
@Suite("GlosaParser FDX breath extraction")
struct BreathParserFDXTests {

  let parser = GlosaParser()

  // MARK: - Spec §5.2 — the Bishop case in FDX form

  /// The Bishop dialogue paragraph translated from Fountain inline notes to FDX
  /// mixed content. All three breaths are bare (no `length` attribute) to match
  /// the D-1 contract; the first is `strength="strong"`.
  @Test("Bishop FDX fixture yields three breaths at offsets 20/31/43")
  func bishopFDXExample() throws {
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
                <glosa:breath strength="strong"/>
                <Text> authority,</Text>
                <glosa:breath/>
                <Text> patriarchy,</Text>
                <glosa:breath/>
                <Text> a history of cover-ups and anti-queer theology.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let data = xml.data(using: .utf8)!
    let result = parser.parseFDXWithDiagnostics(data: data)
    let score = result.score

    // Exactly three breaths.
    #expect(score.breaths.count == 3)

    // Document order is already ascending by offset.
    let sorted = score.breaths.sorted { $0.characterOffset < $1.characterOffset }
    #expect(sorted == score.breaths)

    // Offsets verbatim from spec §6.4 — same numbers the Fountain Bishop fixture asserts.
    #expect(score.breaths[0].characterOffset == 20)
    #expect(score.breaths[1].characterOffset == 31)
    #expect(score.breaths[2].characterOffset == 43)

    // Strength: first is strong, rest default to medium.
    #expect(score.breaths[0].strength == .strong)
    #expect(score.breaths[1].strength == .medium)
    #expect(score.breaths[2].strength == .medium)

    // All three breaths reference the same scene-local dialogue paragraph.
    #expect(score.breaths.allSatisfy { $0.sceneIndex == 0 })
    #expect(score.breaths.allSatisfy { $0.dialogueLineIndex == 0 })

    // The stored dialogue text concatenates every `<Text>` run in the paragraph.
    #expect(score.scenes.count == 1)
    let intent = score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    #expect(
      intent.dialogueLines[0]
        == "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."
    )

    // Happy path (no length attribute): no diagnostics.
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Multiple `<Text>` runs without breaths (Q#3 regression guard)

  @Test("Multiple <Text> runs in one Dialogue paragraph concatenate")
  func multipleTextRunsConcatenate() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="lab" time="noon">
            <glosa:Intent from="calm" to="focused">
              <Paragraph Type="Character">
                <Text>ALEX</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Part one </Text>
                <Text>part two </Text>
                <Text>part three.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)
    let intent = result.score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    #expect(intent.dialogueLines[0] == "Part one part two part three.")
    #expect(result.score.breaths.isEmpty)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Default attributes

  @Test("Bare <glosa:breath/> uses medium-strength default")
  func bareBreathDefaults() throws {
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
                <glosa:breath/>
                <Text> and listen.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)
    #expect(result.score.breaths.count == 1)
    #expect(result.score.breaths[0].strength == .medium)
    #expect(result.score.breaths[0].characterOffset == 4)  // after "Halt"
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Error paths

  @Test("Invalid strength attribute emits warning and skips the breath")
  func invalidStrengthAttribute() throws {
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
                <glosa:breath strength="loud"/>
                <Text> and listen.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)
    #expect(result.score.breaths.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].severity == .warning)
    #expect(result.diagnostics[0].message.contains("strength"))
  }

  // MARK: - Breath outside a dialogue paragraph

  @Test("Breath inside Action paragraph emits warning and is dropped")
  func breathOutsideDialogue() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="a" time="b">
            <glosa:Intent from="x" to="y">
              <Paragraph Type="Action">
                <Text>The room</Text>
                <glosa:breath/>
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
    #expect(result.score.breaths.isEmpty)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].severity == .warning)
    #expect(result.diagnostics[0].message.contains("dialogue"))
  }

  // MARK: - parseFDX shim drops diagnostics but preserves breaths

  @Test("parseFDX shim returns same breaths as parseFDXWithDiagnostics")
  func parseFDXShimPreservesBreaths() throws {
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
                <Text>One</Text>
                <glosa:breath/>
                <Text> two.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let data = xml.data(using: .utf8)!
    let shimScore = parser.parseFDX(data: data)
    let diagScore = parser.parseFDXWithDiagnostics(data: data).score
    #expect(shimScore == diagScore)
    #expect(shimScore.breaths.count == 1)
  }
}
