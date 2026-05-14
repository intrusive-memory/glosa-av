import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s FDX `<glosa:breath/>` element
/// serialization — the contract introduced by Sortie 7 of OPERATION SIGHING
/// SCRIBE.
///
/// ## Contract under test
///
/// When a `GlosaAnnotatedElement` with non-empty `breathPoints` is serialized
/// to FDX via `GlosaSerializer.writeFDX(_:)`, the serializer must emit
/// `<glosa:breath/>` self-closing elements interleaved between `<Text>` runs
/// inside the `<Paragraph Type="Dialogue">`. Re-parsing the serialized XML
/// through `GlosaParser.parseFDXWithDiagnostics(data:)` must yield a
/// `breathPoints` list that compares equal to the original.
///
/// ## What is NOT asserted
///
/// Per methodology rule 6, byte equality against the original FDX source is
/// NOT asserted. XML libraries normalize whitespace and attribute quoting.
/// Only the semantic contract (correct `<glosa:breath/>` positions, correct
/// attributes, namespace, attribute order) is verified.
///
/// ## Canonical form rules (spec §4.2, methodology rule 6)
///
/// - `length` attribute first, `strength` attribute second; attributes
///   omitted when equal to defaults (`length="comma"`, `strength="medium"`).
/// - `.explicit(TimeInterval)` serializes as `length="<ms>ms"` using
///   `Int((seconds * 1000).rounded())` — never truncation (methodology rule 5).
/// - Self-closing form: `<glosa:breath/>` or `<glosa:breath length="…"/>`, etc.
///   Never `<glosa:breath></glosa:breath>`.
/// - Whitespace (spaces following commas/colons) goes in the **following**
///   `<Text>` run so FDX parser offset arithmetic matches Fountain (S3 hint).
@Suite("BreathSerializer FDX — round-trip and canonical form")
struct BreathSerializerFDXTests {

  // MARK: - Shared helpers

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  // MARK: - Bishop FDX fixture

  /// The raw Bishop FDX XML fixture, as defined in spec §5.2 and matching
  /// the Fountain fixture in `BreathParserFDXTests`. Spaces that follow the
  /// colon and commas are placed in the FOLLOWING `<Text>` run (S3
  /// forward-hint) so FDX parser offset arithmetic yields 20/31/43.
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

  /// The notes-stripped Bishop prose (what the actor reads).
  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  /// Build a `GlosaAnnotatedScreenplay` for the Bishop FDX fixture by
  /// parsing the FDX, building a matching screenplay, and compiling.
  private func makeBishopAnnotated() throws -> GlosaAnnotatedScreenplay {
    let fdxData = bishopFDX.data(using: .utf8)!

    // Parse the FDX to extract GLOSA score and breaths.
    let parseResult = parser.parseFDXWithDiagnostics(data: fdxData)
    let fdxScore = parseResult.score

    // The Bishop fixture produces one scene with one intent containing one
    // dialogue line. Verify the fixture parses correctly before building.
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: bishopStripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)

    // Build notes for the compiler from the parsed score.
    let bishopNotes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      // Include the Fountain-style dialogue with inline breath notes so the
      // compiler can populate breathPoints:
      "Bishop is freighted:[[<breath length=\"period\" strength=\"strong\"/>]] authority,"
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

  /// Parse the Bishop FDX fixture → build annotated screenplay → serialize
  /// to FDX → re-parse → assert `breathPoints` equal to the originals.
  ///
  /// This is the primary exit criterion from the Sortie 7 spec:
  /// "Re-parsing the serializer output yields a `breathPoints` list
  /// identical to the input (same count, same offsets, same lengths,
  /// same strengths)."
  @Test("Bishop FDX fixture round-trips: re-parsed breathPoints equal original")
  func bishopRoundTrip() throws {
    let annotated = try makeBishopAnnotated()

    // Verify the annotated element carries the expected three breath points.
    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 3)
    #expect(originalPoints[0].offset == 20)
    #expect(originalPoints[0].length == .period)
    #expect(originalPoints[0].strength == .strong)
    #expect(originalPoints[1].offset == 31)
    #expect(originalPoints[1].length == .comma)
    #expect(originalPoints[1].strength == .medium)
    #expect(originalPoints[2].offset == 43)
    #expect(originalPoints[2].length == .comma)
    #expect(originalPoints[2].strength == .medium)

    // Serialize to FDX.
    let serializedData = serializer.writeFDX(annotated)

    // Re-parse through the FDX parser.
    let reparsedResult = parser.parseFDXWithDiagnostics(data: serializedData)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    // Count must match.
    #expect(
      reparsedBreaths.count == originalPoints.count,
      "Reparsed breath count \(reparsedBreaths.count) ≠ original \(originalPoints.count)"
    )

    // Each point must compare equal.
    for (original, reparsed) in zip(originalPoints, reparsedBreaths) {
      #expect(
        original.offset == reparsed.characterOffset,
        "Offset mismatch: original \(original.offset) ≠ reparsed \(reparsed.characterOffset)"
      )
      #expect(
        original.length == reparsed.length,
        "Length mismatch at offset \(original.offset): \(original.length) ≠ \(reparsed.length)"
      )
      #expect(
        original.strength == reparsed.strength,
        "Strength mismatch at offset \(original.offset): \(original.strength) ≠ \(reparsed.strength)"
      )
    }

    // No parse diagnostics expected.
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 2: Canonical attribute order (length before strength)

  /// When both `length` and `strength` attributes are emitted on a
  /// `<glosa:breath/>` element, `length` must appear before `strength`.
  ///
  /// Exit criterion: any `strength=` substring on a `<glosa:breath` line
  /// is preceded by a `length=` substring on the same line.
  @Test("Serialized <glosa:breath/> attributes are in canonical order: length before strength")
  func canonicalAttributeOrder() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    // Check every line that contains a <glosa:breath element with both attributes.
    let lines = xmlString.components(separatedBy: "\n")
    for line in lines {
      guard line.contains("<glosa:breath") else { continue }
      guard line.contains("strength=") else { continue }
      // strength= is present — length= must also be present and precede it.
      #expect(
        line.contains("length="),
        "Line has strength= but not length=: \(line)"
      )
      if let lengthRange = line.range(of: "length="),
        let strengthRange = line.range(of: "strength=")
      {
        #expect(
          lengthRange.lowerBound < strengthRange.lowerBound,
          "length= must precede strength= on line: \(line)"
        )
      }
    }

    // The Bishop fixture has exactly one breath with both attributes
    // (period/strong); verify it appears in canonical form.
    #expect(
      xmlString.contains("<glosa:breath length=\"period\" strength=\"strong\"/>"),
      "Expected canonical <glosa:breath length=\"period\" strength=\"strong\"/> not found"
    )
  }

  // MARK: - Test 3: Namespace declared when breaths present

  /// When any `<glosa:breath/>` element is present in the serialized
  /// document, the `xmlns:glosa` attribute must be declared on the root
  /// `<FinalDraft>` element.
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

  /// When a screenplay has no GLOSA elements (no scenes, no breath points),
  /// the serialized FDX must NOT declare the `glosa:` namespace.
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

  // MARK: - Test 5: Default attributes are omitted

  /// A breath with default length (.comma) and default strength (.medium)
  /// must be emitted as `<glosa:breath/>` with no attributes.
  @Test("Default breath (comma/medium) serializes as bare <glosa:breath/>")
  func defaultBreathEmitsBareElement() throws {
    let prose = "Halt and listen."
    // Offset 4 — after "Halt", which is "Halt".unicodeScalars.count = 4.
    let breathPoint = BreathPoint(offset: 4, length: .comma, strength: .medium)
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
      "Expected bare <glosa:breath/> for default comma/medium breath"
    )
    // Namespace is present because there is a breath element.
    #expect(xmlString.contains("xmlns:glosa="))
    // No length= or strength= emitted for defaults.
    let lines = xmlString.components(separatedBy: "\n")
    for line in lines where line.contains("<glosa:breath") {
      #expect(!line.contains("length="), "length= must not be emitted for default .comma")
      #expect(!line.contains("strength="), "strength= must not be emitted for default .medium")
    }
  }

  // MARK: - Test 6: Self-closing form (never open+close)

  /// All `<glosa:breath/>` elements must be self-closing. The open+close
  /// form `<glosa:breath></glosa:breath>` is not permitted.
  @Test("<glosa:breath/> is always self-closing, never open+close")
  func breathElementIsSelfClosing() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    #expect(!xmlString.contains("</glosa:breath>"))
    #expect(xmlString.contains("<glosa:breath"))
  }

  // MARK: - Test 7: Whitespace in following <Text> run (S3 forward-hint)

  /// When the serializer splits prose around a breath at offset N, the
  /// character at position N (typically a space) goes into the FOLLOWING
  /// `<Text>` run — not the preceding one. This matches the FDX parser's
  /// cumulative-offset arithmetic.
  ///
  /// For the Bishop fixture, the text before the first breath is
  /// `"Bishop is freighted:"` (20 scalars), and the next `<Text>` run
  /// starts with `" authority,"` (space first). Verified by asserting the
  /// split point.
  @Test("Whitespace after breath offset goes into the following <Text> run")
  func whitespaceInFollowingTextRun() throws {
    let annotated = try makeBishopAnnotated()
    let serializedData = serializer.writeFDX(annotated)
    let xmlString = String(data: serializedData, encoding: .utf8)!

    // The preceding Text run must end at the colon (offset 20 = "Bishop is freighted:").
    #expect(
      xmlString.contains("<Text>Bishop is freighted:</Text>"),
      "Expected <Text>Bishop is freighted:</Text> before first breath"
    )

    // The following Text run must start with a space (the space at offset 20
    // belongs to the next run, not the preceding one).
    #expect(
      xmlString.contains("<Text> authority,</Text>"),
      "Expected <Text> authority,</Text> after first breath (space in following run)"
    )
  }

  // MARK: - Test 8: .explicit(0.35) round-trips as length="350ms"

  /// Methodology rule 5: `.explicit(0.35)` must serialize as `length="350ms"`
  /// via `.rounded()`. Truncation would emit `349ms` because IEEE-754 stores
  /// `0.35` as `0.349999…`. The round-trip is verified by re-parsing.
  @Test(".explicit(0.35) serializes as length=\"350ms\" and FDX round-trips correctly")
  func explicitHalfSecondRoundTrip() throws {
    let prose = "Halt and listen carefully."
    let breathPoint = BreathPoint(offset: 5, length: .explicit(0.35), strength: .medium)
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(
      element: element,
      breathPoints: [breathPoint]
    )
    let screenplay = GuionParsedElementCollection(elements: [element])
    // Need a minimal scene/intent so the FDX parser picks up the breath.
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

    // Canonical form: 350ms, not 349ms.
    #expect(
      xmlString.contains("length=\"350ms\""),
      "Expected length=\"350ms\" but output was: \(xmlString)"
    )
    #expect(!xmlString.contains("349ms"), "Truncation detected — 349ms appeared in output")

    // strength omitted (it's .medium, the default).
    let lines = xmlString.components(separatedBy: "\n")
    for line in lines where line.contains("<glosa:breath") {
      #expect(!line.contains("strength="), "strength= must not be emitted for default .medium")
    }

    // Round-trip: re-parse and verify .explicit(0.35) survived.
    let reparsedResult = parser.parseFDXWithDiagnostics(data: serializedData)
    let reparsedBreaths = reparsedResult.score.breaths
    #expect(reparsedBreaths.count == 1)
    #expect(reparsedBreaths[0].length == .explicit(0.35))
    #expect(reparsedBreaths[0].strength == .medium)
    #expect(reparsedBreaths[0].characterOffset == 5)
  }

  // MARK: - Test 9: Valid XML output

  /// The serialized FDX must be parseable as well-formed XML.
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

/// A minimal `XMLParser` delegate that records whether parsing succeeded.
private final class FDXValidationDelegate: NSObject, XMLParserDelegate {
  var errorMessage: String?

  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    errorMessage = parseError.localizedDescription
  }

  func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
    errorMessage = validationError.localizedDescription
  }
}
