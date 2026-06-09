import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// End-to-end rendering tests for pause markers (OPERATION CLEAVING BREATH,
/// Sortie 9).
///
/// Unlike breaths, pauses have no dedicated CLI block renderer — they are
/// "rendered" by the serializer, which injects `[[<pause …/>]]` Fountain notes
/// and `<glosa:pause/>` FDX elements at the compiled offsets. These tests drive
/// the full bridge → serialize path and assert the markers land in the rendered
/// output, then round-trip cleanly.
///
/// ## Methodology
/// - **Deterministic / hermetic / untimed**. Offsets computed by hand.
@Suite("Pause rendering — end-to-end serializer output")
struct PauseRenderTests {

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  // MARK: - Fixture

  /// One pause (after the colon, offset 20) and two breaths (list commas).
  private let mixedRaw =
    "Bishop is freighted:[[<pause length=\"period\"/>]] authority,"
    + "[[<breath/>]] patriarchy,[[<breath/>]] done."

  private let mixedStripped =
    "Bishop is freighted: authority, patriarchy, done."

  private var mixedNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      mixedRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  private func makeAnnotated() throws -> GlosaAnnotatedScreenplay {
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: mixedStripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)
    let result = try compiler.compile(
      fountainNotes: mixedNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: mixedStripped)]
    )
    let score = parser.parseFountain(notes: mixedNotes)
    return GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: result,
      score: score
    )
  }

  // MARK: - Test 1: Fountain output renders the pause marker at the colon

  @Test("Fountain render places [[<pause/>]] right after the colon")
  func fountainRendersPauseAfterColon() throws {
    let annotated = try makeAnnotated()
    let output = serializer.writeFountain(annotated)

    // The pause is .period (default) → bare form, immediately after the colon.
    #expect(output.contains("Bishop is freighted:[[<pause/>]] authority,"))
    // The list-comma breaths render too.
    let bareBreaths = output.components(separatedBy: "[[<breath/>]]").count - 1
    #expect(bareBreaths == 2)
  }

  // MARK: - Test 2: FDX output renders <glosa:pause/> between text runs

  @Test("FDX render emits <glosa:pause/> between the colon and the list")
  func fdxRendersPauseElement() throws {
    let annotated = try makeAnnotated()
    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!

    #expect(xml.contains("<glosa:pause/>"))
    #expect(xml.contains("<Text>Bishop is freighted:</Text>"))
    // The two list-comma breaths render as bare <glosa:breath/> elements.
    let breathCount = xml.components(separatedBy: "<glosa:breath/>").count - 1
    #expect(breathCount == 2)
  }

  // MARK: - Test 3: Fountain render round-trips (pause + breaths preserved)

  @Test("Fountain render round-trips: one .period pause + two breaths re-parse")
  func fountainRoundTrip() throws {
    let annotated = try makeAnnotated()
    let output = serializer.writeFountain(annotated)

    let reparsed = try GuionParsedElementCollection(string: output)
    var reparsedNotes: [String] = []
    var lastCharacter = ""
    for element in reparsed.elements {
      switch element.elementType {
      case .comment:
        let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { reparsedNotes.append(trimmed) }
      case .character:
        lastCharacter = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = lastCharacter
      case .dialogue:
        reparsedNotes.append(element.elementText)
      default:
        break
      }
    }

    let reparsedResult = parser.parseFountainWithDiagnostics(notes: reparsedNotes)
    #expect(reparsedResult.score.pauses.count == 1)
    #expect(reparsedResult.score.pauses[0].characterOffset == 20)
    #expect(reparsedResult.score.pauses[0].length == .period)
    #expect(reparsedResult.score.breaths.count == 2)
    #expect(
      reparsedResult.score.breaths.map(\.characterOffset).sorted() == [31, 43])
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 4: FDX render round-trips

  @Test("FDX render round-trips: one .period pause + two breaths re-parse")
  func fdxRoundTrip() throws {
    let annotated = try makeAnnotated()
    let data = serializer.writeFDX(annotated)

    let reparsed = parser.parseFDXWithDiagnostics(data: data)
    #expect(reparsed.score.pauses.count == 1)
    #expect(reparsed.score.pauses[0].characterOffset == 20)
    #expect(reparsed.score.pauses[0].length == .period)
    #expect(reparsed.score.breaths.count == 2)
    #expect(reparsed.score.breaths.map(\.characterOffset).sorted() == [31, 43])
    #expect(reparsed.diagnostics.isEmpty)
  }

  // MARK: - Test 5: pause-free render emits no pause markers

  @Test("A pause-free line renders no [[<pause or <glosa:pause markers")
  func pauseFreeRendersNothing() {
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

    let fountain = serializer.writeFountain(annotated)
    #expect(!fountain.contains("[[<pause"))

    let xml = String(data: serializer.writeFDX(annotated), encoding: .utf8)!
    #expect(!xml.contains("<glosa:pause"))
  }
}
