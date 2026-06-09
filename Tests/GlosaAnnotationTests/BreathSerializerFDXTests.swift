import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s FDX `<glosa:breath/>` element
/// serialization.
///
/// `BreathPoint` no longer carries `length` (OPERATION CLEAVING BREATH, Sortie 1);
/// duration moved to `PausePoint`. Canonical FDX breath form is:
/// - Bare `<glosa:breath/>` when `strength=.medium` (default).
/// - `<glosa:breath strength="…"/>` when non-default strength.
/// - `length=` is never emitted on breath elements.
@Suite("BreathSerializer FDX — round-trip and canonical form")
struct BreathSerializerFDXTests {

  // MARK: - Shared helpers

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  // MARK: - Bishop FDX fixture

  /// The Bishop FDX fixture using `strength="strong"` only on the first breath.
  /// `length=` attributes are removed since `<breath>` no longer accepts them.
  private let bishopFDX = """
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

  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  private func makeBishopAnnotated() throws -> GlosaAnnotatedScreenplay {
    let fdxData = bishopFDX.data(using: .utf8)!

    let parseResult = parser.parseFDXWithDiagnostics(data: fdxData)
    let fdxScore = parseResult.score

    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: bishopStripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)

    let bishopNotes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      "Bishop is freighted:[[<breath strength=\"strong\"/>]] authority,"
        + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.",
      "</Intent>",
      "</SceneContext>",
    ]

    let result = try compiler.compile(
      fountainNotes: bishopNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: bishopStripped)]
    )

    return GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: result,
      score: fdxScore
    )
  }

  // MARK: - Test 1: Bishop round-trip

  @Test("Bishop FDX fixture round-trips: re-parsed breathPoints equal original")
  func bishopRoundTrip() throws {
    let annotated = try makeBishopAnnotated()

    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 3)
    #expect(originalPoints[0].offset == 20)
    #expect(originalPoints[0].strength == .strong)
    #expect(originalPoints[1].offset == 31)
    #expect(originalPoints[1].strength == .medium)
    #expect(originalPoints[2].offset == 43)
    #expect(originalPoints[2].strength == .medium)

    let serializedData = serializer.writeFDX(annotated)

    let reparsedResult = parser.parseFDXWithDiagnostics(data: serializedData)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    #expect(
      reparsedBreaths.count == originalPoints.count,
      "Reparsed breath count \(reparsedBreaths.count) ≠ original \(originalPoints.count)"
    )

    for (original, reparsed) in zip(originalPoints, reparsedBreaths) {
      #expect(
        original.offset == reparsed.characterOffset,
        "Offset mismatch: original \(original.offset) ≠ reparsed \(reparsed.characterOffset)"
      )
      #expect(
        original.strength == reparsed.strength,
        "Strength mismatch at offset \(original.offset)"
      )
    }

    // Re-parsing breath elements with no length= produces no diagnostics.
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 2: No length= on breath elements

  @Test("Serialized <glosa:breath/> never emits length= attribute")
  func breathElementNeverEmitsLength() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    // Verify no breath element carries a length attribute.
    let lines = xmlString.components(separatedBy: "\n")
    for line in lines where line.contains("<glosa:breath") {
      #expect(!line.contains("length="), "length= must never appear on <glosa:breath>: \(line)")
    }
  }

  // MARK: - Test 3: Namespace declared when breaths present

  @Test("xmlns:glosa is declared when breath elements are present")
  func namespaceDeclaredWhenBreathsPresent() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(
      xmlString.contains("xmlns:glosa="),
      "xmlns:glosa declaration not found in serialized FDX with breath elements"
    )
  }

  // MARK: - Test 4: Namespace omitted when no GLOSA elements

  @Test("xmlns:glosa is omitted when no GLOSA elements are present")
  func namespaceOmittedWhenNoGlosaElements() {
    let prose = "I noticed."
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(element: element)
    let screenplay = GuionParsedElementCollection(elements: [element])
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [annotatedElement],
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )

    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(
      !xmlString.contains("xmlns:glosa="),
      "xmlns:glosa must be omitted when no GLOSA elements are present"
    )
    #expect(!xmlString.contains("<glosa:breath"))
    #expect(xmlString.contains(prose))
  }

  // MARK: - Test 5: Default breath emits bare element

  @Test("Default breath (medium strength) serializes as bare <glosa:breath/>")
  func defaultBreathEmitsBareElement() throws {
    let prose = "Halt and listen."
    let breathPoint = BreathPoint(offset: 4, strength: .medium)
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(
      element: element,
      breathPoints: [breathPoint]
    )
    let screenplay = GuionParsedElementCollection(elements: [element])
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [annotatedElement],
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )

    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(
      xmlString.contains("<glosa:breath/>"),
      "Expected bare <glosa:breath/> for default medium breath"
    )
    #expect(xmlString.contains("xmlns:glosa="))
    let lines = xmlString.components(separatedBy: "\n")
    for line in lines where line.contains("<glosa:breath") {
      #expect(!line.contains("length="), "length= must not be emitted")
      #expect(!line.contains("strength="), "strength= must not be emitted for default .medium")
    }
  }

  // MARK: - Test 6: Self-closing form

  @Test("<glosa:breath/> is always self-closing, never open+close")
  func breathElementIsSelfClosing() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(!xmlString.contains("</glosa:breath>"))
    #expect(xmlString.contains("<glosa:breath"))
  }

  // MARK: - Test 7: Whitespace in following <Text> run

  @Test("Whitespace after breath offset goes into the following <Text> run")
  func whitespaceInFollowingTextRun() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(
      xmlString.contains("<Text>Bishop is freighted:</Text>"),
      "Expected <Text>Bishop is freighted:</Text> before first breath"
    )

    #expect(
      xmlString.contains("<Text> authority,</Text>"),
      "Expected <Text> authority,</Text> after first breath (space in following run)"
    )
  }

  // MARK: - Test 8: Non-default strength round-trips

  @Test("Non-default strength round-trips in FDX serialization")
  func nonDefaultStrengthRoundTrips() throws {
    let prose = "Halt and listen carefully."
    let breathPoint = BreathPoint(offset: 5, strength: .strong)
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(
      element: element,
      breathPoints: [breathPoint]
    )
    let screenplay = GuionParsedElementCollection(elements: [element])
    let intent = GlosaScore.IntentEntry(
      intent: Intent(from: "a", to: "b", pace: nil, spacing: nil, scoped: true, lineCount: 1),
      constraints: [],
      dialogueLines: [prose]
    )
    let score = GlosaScore(
      scenes: [
        GlosaScore.SceneEntry(
          context: SceneContext(location: "x", time: "y"),
          intents: [intent]
        )
      ]
    )
    let charElement = GuionElement(elementType: .character, elementText: "C")
    let charAnnotated = GlosaAnnotatedElement(element: charElement)
    let screenplay2 = GuionParsedElementCollection(elements: [charElement, element])
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay2,
      annotatedElements: [charAnnotated, annotatedElement],
      score: score,
      diagnostics: [],
      provenance: []
    )

    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(
      xmlString.contains("strength=\"strong\""),
      "Expected strength=\"strong\" in serialized output"
    )
    #expect(!xmlString.contains("length="), "length= must not appear on breath elements")

    // Round-trip: re-parse and verify strength survived.
    let reparsedResult = parser.parseFDXWithDiagnostics(data: serializedData)
    let reparsedBreaths = reparsedResult.score.breaths
    #expect(reparsedBreaths.count == 1)
    #expect(reparsedBreaths[0].strength == .strong)
    #expect(reparsedBreaths[0].characterOffset == 5)
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 9: Valid XML output

  @Test("Serialized FDX with breaths is valid XML")
  func serializedFDXIsValidXML() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)

    let xmlParser = XMLParser(data: serializedData)
    let delegate = FDXValidationDelegate()
    xmlParser.delegate = delegate
    let success = xmlParser.parse()

    #expect(success, "Serialized FDX is not valid XML: \(delegate.errorMessage ?? "unknown error")")
  }
}

// MARK: - XML Validation Helper

private final class FDXValidationDelegate: NSObject, XMLParserDelegate {
  var errorMessage: String?

  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    errorMessage = parseError.localizedDescription
  }

  func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
    errorMessage = validationError.localizedDescription
  }
}
