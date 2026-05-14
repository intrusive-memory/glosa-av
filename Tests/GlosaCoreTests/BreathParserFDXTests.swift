import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s FDX breath extraction — the
/// `<glosa:breath/>` self-closing elements defined in `breath-tag.md` §5.2.
///
/// All tests follow the OPERATION SIGHING SCRIBE methodology: deterministic,
/// hermetic, untimed. The Bishop offsets in §6.4 (`20`, `31`, `43`) are the
/// canonical fixture and must match the Fountain equivalent in
/// `BreathParserFountainTests` byte-for-byte. The mixed-content shape this
/// suite parses (interleaved `<Text>` runs with `<glosa:breath/>` siblings)
/// also exercises the Q#3 per-`<Text>`-reset bug fix — without that fix,
/// `currentText` would drop every run except the last and the Bishop
/// assertion below would not parse correctly.
@Suite("GlosaParser FDX breath extraction")
struct BreathParserFDXTests {

  let parser = GlosaParser()

  // MARK: - Spec §5.2 — the Bishop case in FDX form

  /// The Bishop dialogue paragraph translated from Fountain inline notes
  /// to FDX mixed content. The XML structure interleaves `<Text>` runs
  /// with `<glosa:breath/>` siblings so the breaths appear at the same
  /// scalar offsets within the concatenated prose as the Fountain
  /// equivalent (spec §6.4: 20 / 31 / 43).
  ///
  /// Note on `<Text>` boundaries: the spaces that follow each `,` and the
  /// `:` are placed *after* the corresponding `<glosa:breath/>` (inside
  /// the next `<Text>` run) rather than before, so the cumulative prose
  /// preceding each breath element is exactly the same byte sequence
  /// that precedes the Fountain inline note in the equivalent fixture.
  /// The downstream stored dialogue text (`"Bishop is freighted: …"`) is
  /// identical regardless of where the spaces sit; only the breath
  /// offsets care.
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
                <glosa:breath length="period" strength="strong"/>
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

    // Offsets verbatim from spec §6.4 — same numbers the Fountain
    // Bishop fixture asserts.
    #expect(score.breaths[0].characterOffset == 20)
    #expect(score.breaths[1].characterOffset == 31)
    #expect(score.breaths[2].characterOffset == 43)

    // Attributes per spec §6.4: first is period/strong, rest default.
    #expect(score.breaths[0].length == .period)
    #expect(score.breaths[0].strength == .strong)
    #expect(score.breaths[1].length == .comma)
    #expect(score.breaths[1].strength == .medium)
    #expect(score.breaths[2].length == .comma)
    #expect(score.breaths[2].strength == .medium)

    // All three breaths reference the same scene-local dialogue
    // paragraph (the only Dialogue paragraph in the scene), in scene 0.
    #expect(score.breaths.allSatisfy { $0.sceneIndex == 0 })
    #expect(score.breaths.allSatisfy { $0.dialogueLineIndex == 0 })

    // The stored dialogue text concatenates every `<Text>` run in the
    // paragraph — the Q#3 fix removes the per-`<Text>` `currentText`
    // reset, so all four runs survive instead of just the last.
    #expect(score.scenes.count == 1)
    let intent = score.scenes[0].intents[0]
    #expect(intent.dialogueLines.count == 1)
    #expect(
      intent.dialogueLines[0]
        == "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."
    )

    // Happy path: no diagnostics.
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Multiple `<Text>` runs without breaths (Q#3 regression guard)

  /// Pure regression test for the per-`<Text>` `currentText` reset bug
  /// described in the Sortie 3 brief. Even without any breath markers,
  /// a dialogue paragraph with multiple `<Text>` siblings must
  /// concatenate all of them — not just the last. (No existing FDX
  /// fixture in the repo exercised this before Sortie 3.)
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

  /// A bare `<glosa:breath/>` (no attributes) parses with the spec §4.2
  /// defaults: `length=.comma`, `strength=.medium`.
  @Test("Bare <glosa:breath/> uses comma/medium defaults")
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
    #expect(result.score.breaths[0].length == .comma)
    #expect(result.score.breaths[0].strength == .medium)
    #expect(result.score.breaths[0].characterOffset == 4)  // after "Halt"
    #expect(result.diagnostics.isEmpty)
  }

  /// Explicit `length="350ms"` parses as `.explicit(0.35)` per the
  /// shared `parseLengthAttribute` rules (methodology rule 5).
  @Test("length=\"350ms\" parses as .explicit(0.35)")
  func explicitMillisecondLength() throws {
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
                <glosa:breath length="350ms"/>
                <Text> two.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    let result = parser.parseFDXWithDiagnostics(data: xml.data(using: .utf8)!)
    #expect(result.score.breaths.count == 1)
    #expect(result.score.breaths[0].length == .explicit(0.35))
    #expect(result.score.breaths[0].strength == .medium)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Error paths

  /// An invalid `length` value yields a warning diagnostic and zero
  /// breath records for that element (the bad breath is dropped; other
  /// well-formed breaths in the same paragraph would still be kept).
  @Test("Invalid length attribute emits warning and skips the breath")
  func invalidLengthAttribute() throws {
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
                <glosa:breath length="nonsense"/>
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
    #expect(result.diagnostics[0].message.contains("length"))
  }

  /// An invalid `strength` value yields a warning diagnostic and skips
  /// the breath.
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

  /// A malformed explicit-time `length` (e.g. `"abcms"`) is rejected
  /// just like an unknown named token.
  @Test("Malformed explicit length emits warning and skips the breath")
  func malformedExplicitLength() throws {
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
                <glosa:breath length="abcms"/>
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
  }

  // MARK: - Breath outside a dialogue paragraph

  /// A `<glosa:breath/>` appearing inside `<Paragraph Type="Action">`
  /// (or any non-Dialogue paragraph type) is rejected with a warning
  /// and produces no breath record. Mirrors the Fountain path's
  /// out-of-dialogue diagnostic per spec §4.3.
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

  /// The legacy `parseFDX(data:)` API is preserved as a thin shim that
  /// returns the same `GlosaScore` (including `breaths`) as
  /// `parseFDXWithDiagnostics(data:)` but drops the diagnostics. This
  /// mirrors the Fountain path's shim contract added by Sortie 2.
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
