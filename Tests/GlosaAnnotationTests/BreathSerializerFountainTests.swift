import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s Fountain breath inline-note
/// serialization.
///
/// `BreathPoint` no longer carries `length` (OPERATION CLEAVING BREATH, Sortie 1);
/// duration moved to `PausePoint`. Canonical breath form is:
/// - Bare `[[<breath/>]]` when `strength=.medium` (default).
/// - `[[<breath strength="…"/>]]` when non-default strength.
/// - `length=` is never emitted on breath notes.
@Suite("BreathSerializer Fountain — round-trip and canonical form")
struct BreathSerializerFountainTests {

  // MARK: - Shared helpers

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  private func extractNotesAndDialogue(
    from screenplay: GuionParsedElementCollection
  ) -> (notes: [String], dialogueLines: [(character: String, text: String)]) {
    var notes: [String] = []
    var dialogueLines: [(character: String, text: String)] = []
    var lastCharacterName = ""

    for element in screenplay.elements {
      switch element.elementType {
      case .comment:
        let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          notes.append(trimmed)
        }
      case .character:
        lastCharacterName = element.elementText
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: " ^", with: "")
      case .dialogue:
        dialogueLines.append((character: lastCharacterName, text: element.elementText))
        notes.append(element.elementText)
      default:
        break
      }
    }
    return (notes, dialogueLines)
  }

  // MARK: - Bishop fixture (spec §5.1 Example 1 / §6.4)

  /// Raw Bishop dialogue — first breath uses `strength="strong"`, others bare.
  /// `length=` attributes are omitted since `<breath>` no longer accepts them.
  private let bishopRaw =
    "Bishop is freighted:[[<breath strength=\"strong\"/>]] authority,"
    + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  /// The expected canonical forms for the three Bishop breath notes.
  ///
  /// - Offset 20: `strength="strong"` (non-default) → `[[<breath strength="strong"/>]]`
  /// - Offset 31: default → `[[<breath/>]]`
  /// - Offset 43: default → `[[<breath/>]]`
  private let bishopExpectedTags = [
    "[[<breath strength=\"strong\"/>]]",
    "[[<breath/>]]",
    "[[<breath/>]]",
  ]

  private var bishopNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  private func makeBishopAnnotated() throws -> GlosaAnnotatedScreenplay {
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

  // MARK: - Test 1: Bishop canonical form

  @Test("Bishop fixture serializes to three canonical breath inline notes")
  func bishopCanonicalForm() throws {
    let annotated = try makeBishopAnnotated()
    let output = serializer.writeFountain(annotated)

    // All three canonical note strings must be present.
    for tag in bishopExpectedTags {
      #expect(
        output.contains(tag),
        "Expected canonical tag \(tag) not found in serialized output"
      )
    }

    // The first (non-default) breath carries strength only, no length.
    #expect(output.contains("[[<breath strength=\"strong\"/>]]"))
    // No length= on breath notes.
    let breathTagLines = output.components(separatedBy: "\n").filter { $0.contains("[[<breath") }
    for line in breathTagLines {
      #expect(!line.contains("length="), "length= must not appear in breath notes")
    }

    // Two bare [[<breath/>]] tags.
    let bareCount = output.components(separatedBy: "[[<breath/>]]").count - 1
    #expect(bareCount == 2, "Expected 2 bare [[<breath/>]] tags, found \(bareCount)")
  }

  // MARK: - Test 2: Bishop round-trip

  @Test("Bishop fixture round-trips: re-parsed breathPoints equal original")
  func bishopRoundTrip() throws {
    let annotated = try makeBishopAnnotated()

    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 3)

    let serializedFountain = serializer.writeFountain(annotated)

    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)

    let reparsedResult = parser.parseFountainWithDiagnostics(notes: reparsedNotes)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    #expect(
      reparsedBreaths.count == originalPoints.count,
      "Reparsed breath count \(reparsedBreaths.count) ≠ original \(originalPoints.count)"
    )

    for (original, reparsedBreath) in zip(originalPoints, reparsedBreaths) {
      #expect(
        original.offset == reparsedBreath.characterOffset,
        "Offset mismatch: original \(original.offset) ≠ reparsed \(reparsedBreath.characterOffset)"
      )
      #expect(
        original.strength == reparsedBreath.strength,
        "Strength mismatch at offset \(original.offset): \(original.strength) ≠ \(reparsedBreath.strength)"
      )
    }
    // Re-parsing breath notes with no length= attributes produces no diagnostics.
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 3: Bishop re-parsed GlosaScore compares equal to original

  @Test("Bishop round-trip: re-parsed GlosaScore equals original")
  func bishopRoundTripScoreEquality() throws {
    let originalScore = parser.parseFountain(notes: bishopNotes)
    #expect(originalScore.scenes.count == 1)
    #expect(originalScore.breaths.count == 3)

    let annotated = try makeBishopAnnotated()
    let serializedFountain = serializer.writeFountain(annotated)

    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)
    let reparsedScore = parser.parseFountain(notes: reparsedNotes)

    #expect(originalScore.scenes.count == reparsedScore.scenes.count)

    let origBreaths = originalScore.breaths.sorted { $0.characterOffset < $1.characterOffset }
    let reparsedBreaths = reparsedScore.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }
    #expect(origBreaths.count == reparsedBreaths.count)

    for (o, r) in zip(origBreaths, reparsedBreaths) {
      #expect(o.characterOffset == r.characterOffset)
      #expect(o.strength == r.strength)
      #expect(o.dialogueLineIndex == r.dialogueLineIndex)
    }
  }

  // MARK: - Test 4: Run-on fixture (spec §5.1 Example 2)

  private let runOnRaw =
    "He kept the parish quiet[[<breath/>]] and he kept the families quiet"
    + "[[<breath/>]] and he kept the press quiet"
    + "[[<breath/>]] and he kept the diocese quiet for thirty-two years"
    + "[[<breath/>]] and then a single deposition undid every one of those silences in a single afternoon."

  private let runOnStripped =
    "He kept the parish quiet and he kept the families quiet"
    + " and he kept the press quiet"
    + " and he kept the diocese quiet for thirty-two years"
    + " and then a single deposition undid every one of those silences in a single afternoon."

  private var runOnNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      runOnRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  private func makeRunOnAnnotated() throws -> GlosaAnnotatedScreenplay {
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: runOnStripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)

    let result = try compiler.compile(
      fountainNotes: runOnNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: runOnStripped)]
    )
    let score = parser.parseFountain(notes: runOnNotes)

    return GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: result,
      score: score
    )
  }

  @Test("Run-on fixture round-trips: four bare breath points survive")
  func runOnRoundTrip() throws {
    let annotated = try makeRunOnAnnotated()

    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 4)
    for point in originalPoints {
      // `BreathPoint` no longer has `length`; all are medium strength (the default).
      #expect(point.strength == .medium)
    }

    let serializedFountain = serializer.writeFountain(annotated)

    let bareCount = serializedFountain.components(separatedBy: "[[<breath/>]]").count - 1
    #expect(bareCount == 4, "Expected 4 bare [[<breath/>]] tags, got \(bareCount)")

    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)
    let reparsedResult = parser.parseFountainWithDiagnostics(notes: reparsedNotes)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    #expect(reparsedBreaths.count == 4)
    for (original, reparsedBreath) in zip(originalPoints, reparsedBreaths) {
      #expect(original.offset == reparsedBreath.characterOffset)
      #expect(original.strength == reparsedBreath.strength)
    }
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 5: All-default breaths emit bare [[<breath/>]]

  @Test("All-default breaths round-trip as bare [[<breath/>]] without attributes")
  func allDefaultBreathsEmitBareTag() throws {
    let prose = "A simple line with one bare breath."
    let breathPoint = BreathPoint(offset: 14, strength: .medium)
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

    let output = serializer.writeFountain(annotated)

    #expect(output.contains("[[<breath/>]]"))
    // No attributes at all on a default breath.
    #expect(!output.contains("length="))
    #expect(!output.contains("strength="))
  }

  // MARK: - Test 6: Non-default strength emits strength attribute only

  @Test("Non-default strength emits only strength attribute (no length=)")
  func nonDefaultStrengthEmitsStrengthOnly() throws {
    let prose = "Listen to this carefully."
    let breathPoint = BreathPoint(offset: 9, strength: .strong)
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

    let output = serializer.writeFountain(annotated)

    #expect(output.contains("[[<breath strength=\"strong\"/>]]"))
    #expect(!output.contains("length="))
  }

  // MARK: - Test 7: Weak strength emits only strength attribute

  @Test("Weak strength emits [[<breath strength=\"weak\"/>]]")
  func weakStrengthAttribute() throws {
    let prose = "A test of weak strength."
    let breathPoint = BreathPoint(offset: 5, strength: .weak)
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

    let output = serializer.writeFountain(annotated)

    #expect(output.contains("[[<breath strength=\"weak\"/>]]"))
    #expect(!output.contains("length="))
  }

  // MARK: - Test 8: Breath-free dialogue emits no inline notes

  @Test("Dialogue with no breath points emits no inline breath notes")
  func breathFreeDialogueEmitsNoNotes() throws {
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

    let output = serializer.writeFountain(annotated)

    #expect(!output.contains("[[<breath"))
    #expect(output.contains(prose))
  }
}
