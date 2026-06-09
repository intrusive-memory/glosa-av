import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s FDX `<glosa:pause/>` element
/// serialization (OPERATION CLEAVING BREATH, Sortie 9).
///
/// Canonical FDX pause form (serializer `fdxPauseElement(_:)`):
/// - Bare `<glosa:pause/>` when `length=.period` (the default).
/// - `<glosa:pause length="…"/>` when a non-default length is set.
/// - The element is always self-closing and lives between `<Text>` runs.
///
/// ## Methodology
/// - **Deterministic / hermetic**: no `Date()`, `UUID()`, network, or filesystem.
/// - Offsets are computed by hand against the notes-stripped prose.
@Suite("PauseSerializer FDX — <glosa:pause/> emission")
struct PauseSerializerFDXTests {

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()

  // MARK: - Helpers

  /// A single dialogue paragraph with one character cue, carrying the given
  /// pause points. A non-empty score is supplied so the namespace is declared.
  private func makeAnnotated(
    prose: String,
    pausePoints: [PausePoint]
  ) -> GlosaAnnotatedScreenplay {
    let charElement = GuionElement(elementType: .character, elementText: "VOICE")
    let dialogueElement = GuionElement(elementType: .dialogue, elementText: prose)
    let charAnnotated = GlosaAnnotatedElement(element: charElement)
    let dialogueAnnotated = GlosaAnnotatedElement(
      element: dialogueElement,
      pausePoints: pausePoints
    )
    let screenplay = GuionParsedElementCollection(elements: [charElement, dialogueElement])
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
    return GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [charAnnotated, dialogueAnnotated],
      score: score,
      diagnostics: [],
      provenance: []
    )
  }

  // MARK: - Test 1: default-length pause emits bare <glosa:pause/>

  @Test("Default-length (.period) pause serializes as bare <glosa:pause/>")
  func defaultLengthBareElement() {
    let annotated = makeAnnotated(
      prose: "Hold: then speak.",
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!

    #expect(xml.contains("<glosa:pause/>"))
    for line in xml.components(separatedBy: "\n") where line.contains("<glosa:pause") {
      #expect(!line.contains("length="), "length= must be omitted for default .period pause")
    }
    #expect(xml.contains("xmlns:glosa="))
  }

  // MARK: - Test 2: non-default length included

  @Test("Non-default length emits <glosa:pause length=\"beat\"/>")
  func nonDefaultLengthIncluded() {
    let annotated = makeAnnotated(
      prose: "Silence. Resume.",
      pausePoints: [PausePoint(offset: 8, length: .beat)]
    )
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!
    #expect(xml.contains("<glosa:pause length=\"beat\"/>"))
  }

  // MARK: - Test 3: text runs split around the pause

  @Test("Prose is split into <Text> runs around the pause; trailing space follows")
  func textRunsSplitAroundPause() {
    // "Hold:" = 5 scalars; pause after the colon. The following run carries the
    // leading space (the S3 forward-hint convention).
    let annotated = makeAnnotated(
      prose: "Hold: then speak.",
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!
    #expect(xml.contains("<Text>Hold:</Text>"))
    #expect(xml.contains("<Text> then speak.</Text>"))
  }

  // MARK: - Test 4: self-closing form

  @Test("<glosa:pause/> is always self-closing, never open+close")
  func pauseElementIsSelfClosing() {
    let annotated = makeAnnotated(
      prose: "Hold: then speak.",
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!
    #expect(!xml.contains("</glosa:pause>"))
    #expect(xml.contains("<glosa:pause"))
  }

  // MARK: - Test 5: round-trip through the FDX parser

  @Test("Default-length FDX pause round-trips: re-parsed pause is .period at offset 5")
  func defaultLengthRoundTrips() throws {
    let annotated = makeAnnotated(
      prose: "Hold: then speak.",
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let data = serializer.writeFDX(annotated)

    let reparsed = parser.parseFDXWithDiagnostics(data: data)
    #expect(reparsed.score.pauses.count == 1)
    #expect(reparsed.score.pauses[0].characterOffset == 5)
    #expect(reparsed.score.pauses[0].length == .period)
    #expect(reparsed.diagnostics.isEmpty)
  }

  @Test("Non-default FDX pause round-trips: re-parsed pause keeps .beat at offset 8")
  func nonDefaultLengthRoundTrips() throws {
    let annotated = makeAnnotated(
      prose: "Silence. Resume.",
      pausePoints: [PausePoint(offset: 8, length: .beat)]
    )
    let data = serializer.writeFDX(annotated)

    let reparsed = parser.parseFDXWithDiagnostics(data: data)
    #expect(reparsed.score.pauses.count == 1)
    #expect(reparsed.score.pauses[0].characterOffset == 8)
    #expect(reparsed.score.pauses[0].length == .beat)
    #expect(reparsed.diagnostics.isEmpty)
  }

  // MARK: - Test 6: serialized FDX is valid XML

  @Test("Serialized FDX with a pause is valid XML")
  func serializedFDXIsValidXML() {
    let annotated = makeAnnotated(
      prose: "Hold: then speak.",
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let data = serializer.writeFDX(annotated)
    let xmlParser = XMLParser(data: data)
    let delegate = PauseFDXValidationDelegate()
    xmlParser.delegate = delegate
    let success = xmlParser.parse()
    #expect(success, "Serialized FDX is not valid XML: \(delegate.errorMessage ?? "unknown")")
  }

  // MARK: - Test 7: namespace omitted when no GLOSA elements

  @Test("xmlns:glosa is omitted when there are no GLOSA elements")
  func namespaceOmittedWhenNoGlosa() {
    let element = GuionElement(elementType: .dialogue, elementText: "I noticed.")
    let annotatedElement = GlosaAnnotatedElement(element: element)
    let screenplay = GuionParsedElementCollection(elements: [element])
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [annotatedElement],
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!
    #expect(!xml.contains("xmlns:glosa="))
    #expect(!xml.contains("<glosa:pause"))
  }
}

// MARK: - XML Validation Helper

private final class PauseFDXValidationDelegate: NSObject, XMLParserDelegate {
  var errorMessage: String?

  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    errorMessage = parseError.localizedDescription
  }

  func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
    errorMessage = validationError.localizedDescription
  }
}
