import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// The mission's key end-to-end test (OPERATION CLEAVING BREATH, Sortie 9,
/// task 7): the new-vocabulary Bishop case where the colon becomes a
/// `<pause length="period">` and the two list commas become `<breath>` seams.
///
/// This drives the full pipeline — **parse → compile → serialize → re-parse** —
/// in both Fountain and FDX, and asserts the pause and breaths survive at their
/// hand-computed offsets with no loss and no spurious diagnostics.
///
/// ## Offset derivation (against the notes-stripped prose the actor reads)
///
/// Stripped prose:
/// ```
/// Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
/// ```
/// - `Bishop is freighted:` = 20 scalars → the **pause** sits at offset 20
///   (immediately after the colon).
/// - `Bishop is freighted: authority,` = 31 scalars → a **breath** at offset 31
///   (between `authority,` and ` patriarchy,`).
/// - `Bishop is freighted: authority, patriarchy,` = 43 scalars → a **breath**
///   at offset 43 (between `patriarchy,` and ` a history…`).
@Suite("Bishop mixed pause+breath end-to-end round-trip")
struct BishopMixedRoundTripTests {

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  /// Raw Bishop with the new vocabulary: colon → pause, list commas → breaths.
  private let bishopRaw =
    "Bishop is freighted:[[<pause length=\"period\"/>]] authority,"
    + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  private var bishopNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  private func makeAnnotated() throws -> GlosaAnnotatedScreenplay {
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: bishopStripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)
    let result = try compiler.compile(
      fountainNotes: bishopNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: bishopStripped)]
    )
    let score = parser.parseFountain(notes: bishopNotes)
    return GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: result,
      score: score
    )
  }

  private func extractNotesAndDialogue(
    from screenplay: GuionParsedElementCollection
  ) -> [String] {
    var notes: [String] = []
    for element in screenplay.elements {
      switch element.elementType {
      case .comment:
        let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { notes.append(trimmed) }
      case .dialogue:
        notes.append(element.elementText)
      default:
        break
      }
    }
    return notes
  }

  // MARK: - Test 1: parse step yields one pause + two breaths

  @Test("Parse: colon → one .period pause at 20; commas → two breaths at 31/43")
  func parseStep() throws {
    let result = parser.parseFountainWithDiagnostics(notes: bishopNotes)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].characterOffset == 20)
    #expect(result.score.pauses[0].length == .period)

    let breathOffsets = result.score.breaths.map(\.characterOffset).sorted()
    #expect(breathOffsets == [31, 43])

    // The stored prose is the clean actor-readable line.
    #expect(result.score.scenes[0].intents[0].dialogueLines[0] == bishopStripped)
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Test 2: compile step projects onto the annotated dialogue element

  @Test("Compile + bridge: dialogue element carries pause@20 and breaths@31/43")
  func compileAndBridgeStep() throws {
    let annotated = try makeAnnotated()
    let dialogue = annotated.annotatedElements[1]
    #expect(dialogue.element.elementType == .dialogue)

    #expect(dialogue.pausePoints.count == 1)
    #expect(dialogue.pausePoints[0].offset == 20)
    #expect(dialogue.pausePoints[0].length == .period)

    #expect(dialogue.breathPoints.map(\.offset) == [31, 43])
    // No same-offset collapse — pause and breaths are at distinct offsets.
    #expect(dialogue.breathPoints.allSatisfy { $0.offset != 20 })
  }

  // MARK: - Test 3: Fountain serialize → re-parse round-trip

  @Test("Fountain round-trip: serialize then re-parse preserves pause + breaths")
  func fountainRoundTrip() throws {
    let annotated = try makeAnnotated()
    let output = serializer.writeFountain(annotated)

    // Canonical forms: bare pause (default .period) right after the colon; two
    // bare breaths between list items.
    #expect(output.contains("Bishop is freighted:[[<pause/>]] authority,"))
    let bareBreaths = output.components(separatedBy: "[[<breath/>]]").count - 1
    #expect(bareBreaths == 2)

    let reparsed = try GuionParsedElementCollection(string: output)
    let reparsedNotes = extractNotesAndDialogue(from: reparsed)
    let result = parser.parseFountainWithDiagnostics(notes: reparsedNotes)

    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].characterOffset == 20)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.score.breaths.map(\.characterOffset).sorted() == [31, 43])
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Test 4: FDX serialize → re-parse round-trip

  @Test("FDX round-trip: serialize then re-parse preserves pause + breaths")
  func fdxRoundTrip() throws {
    let annotated = try makeAnnotated()
    let data = serializer.writeFDX(annotated)
    let xml = String(data: data, encoding: .utf8)!

    #expect(xml.contains("<glosa:pause/>"))
    let breathCount = xml.components(separatedBy: "<glosa:breath/>").count - 1
    #expect(breathCount == 2)

    let result = parser.parseFDXWithDiagnostics(data: data)
    #expect(result.score.pauses.count == 1)
    #expect(result.score.pauses[0].characterOffset == 20)
    #expect(result.score.pauses[0].length == .period)
    #expect(result.score.breaths.map(\.characterOffset).sorted() == [31, 43])
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Test 5: stripped prose is preserved through both serializations

  @Test("Round-trip preserves the exact actor-readable prose in both formats")
  func prosePreserved() throws {
    let annotated = try makeAnnotated()

    // Fountain.
    let fountain = serializer.writeFountain(annotated)
    let reFountain = try GuionParsedElementCollection(string: fountain)
    let fNotes = extractNotesAndDialogue(from: reFountain)
    let fResult = parser.parseFountainWithDiagnostics(notes: fNotes)
    #expect(fResult.score.scenes[0].intents[0].dialogueLines[0] == bishopStripped)

    // FDX.
    let data = serializer.writeFDX(annotated)
    let xResult = parser.parseFDXWithDiagnostics(data: data)
    #expect(xResult.score.scenes[0].intents[0].dialogueLines[0] == bishopStripped)
  }
}
