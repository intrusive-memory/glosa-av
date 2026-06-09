import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Tests for the pause-point bridge: verifies that
/// `GlosaAnnotatedScreenplay.build(from:compilationResult:)` propagates
/// `CompilationResult.pausePoints` onto the `pausePoints` field of each
/// `GlosaAnnotatedElement` (OPERATION CLEAVING BREATH, Sortie 9).
///
/// Mirrors `BreathBridgeTests`. All offsets are computed by hand against the
/// notes-stripped prose the actor reads.
///
/// ## Methodology
/// - **Deterministic / hermetic / untimed**.
@Suite("PauseBridge — GlosaAnnotatedElement.pausePoints")
struct PauseBridgeTests {

  // MARK: - Fixture helpers

  /// Bishop dialogue with the colon → `<pause length="period">` and the two
  /// list commas → `<breath>` (the new vocabulary from Sortie 5).
  ///
  /// Stripped prose offsets:
  ///   "Bishop is freighted:" = 20 scalars  → pause at offset 20
  ///   "Bishop is freighted: authority," = 31 scalars → breath at 31
  ///   "Bishop is freighted: authority, patriarchy," = 43 scalars → breath at 43
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

  private func makeBishopScreenplay() -> GuionParsedElementCollection {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. RECTORY OFFICE - LATE AFTERNOON"),
      GuionElement(elementType: .action, elementText: "The Bishop sits across the table."),
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: bishopStripped),
    ]
    return GuionParsedElementCollection(elements: elements)
  }

  // MARK: - Test 1: dialogue element exposes the single pause point

  @Test("Bishop dialogue element carries one PausePoint at offset 20 (.period)")
  func bishopDialogueElementHasOnePausePoint() throws {
    let compiler = GlosaCompiler()
    let screenplay = makeBishopScreenplay()

    let compilationResult = try compiler.compile(
      fountainNotes: bishopNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: bishopStripped)]
    )

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult
    )

    #expect(annotated.annotatedElements.count == 4)
    let dialogueElement = annotated.annotatedElements[3]
    #expect(dialogueElement.element.elementType == .dialogue)

    let pausePoints = dialogueElement.pausePoints
    #expect(pausePoints.count == 1)
    #expect(pausePoints[0].offset == 20)
    #expect(pausePoints[0].length == .period)

    // The two list-comma breaths survive at 31 and 43 (no same-offset collapse:
    // the pause is at 20, breaths at 31/43).
    let breathPoints = dialogueElement.breathPoints
    #expect(breathPoints.map(\.offset) == [31, 43])
  }

  // MARK: - Test 2: non-dialogue elements carry empty pausePoints

  @Test("Non-dialogue elements (sceneHeading, action, character) carry empty pausePoints")
  func nonDialogueElementsHaveEmptyPausePoints() throws {
    let compiler = GlosaCompiler()
    let screenplay = makeBishopScreenplay()

    let compilationResult = try compiler.compile(
      fountainNotes: bishopNotes,
      dialogueLines: [(character: "THE PRACTITIONER", text: bishopStripped)]
    )

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult
    )

    #expect(annotated.annotatedElements[0].element.elementType == .sceneHeading)
    #expect(annotated.annotatedElements[0].pausePoints.isEmpty)
    #expect(annotated.annotatedElements[1].element.elementType == .action)
    #expect(annotated.annotatedElements[1].pausePoints.isEmpty)
    #expect(annotated.annotatedElements[2].element.elementType == .character)
    #expect(annotated.annotatedElements[2].pausePoints.isEmpty)
  }

  // MARK: - Test 3: pause-free dialogue carries empty pausePoints

  @Test("Dialogue element with no pause annotations carries empty pausePoints")
  func pauseFreeDialogueElementHasEmptyPausePoints() throws {
    let plainText = "A line with no pause markers at all."
    let notes: [String] = [
      #"<SceneContext location="anywhere" time="anytime">"#,
      #"<Intent from="neutral" to="neutral" pace="moderate">"#,
      plainText,
      "</Intent>",
      "</SceneContext>",
    ]
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "VOICE"),
      GuionElement(elementType: .dialogue, elementText: plainText),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)

    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: [(character: "VOICE", text: plainText)]
    )

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult
    )

    #expect(compilationResult.pausePoints.isEmpty)
    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    #expect(dialogueElement.pausePoints.isEmpty)
  }

  // MARK: - Test 4: default pausePoints is [] for direct construction

  @Test("GlosaAnnotatedElement default pausePoints is empty")
  func defaultPausePointsIsEmpty() {
    let element = GuionElement(elementType: .action, elementText: "She enters.")
    let annotatedElement = GlosaAnnotatedElement(element: element)
    #expect(annotatedElement.pausePoints.isEmpty)
  }

  // MARK: - Test 5: non-default-length pause survives the bridge

  @Test("A .beat pause survives the bridge with its length intact")
  func nonDefaultLengthPauseSurvivesBridge() throws {
    let stripped = "Silence. Resume."
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      "Silence.[[<pause length=\"beat\"/>]] Resume.",
      "</Intent>",
      "</SceneContext>",
    ]
    let elements: [GuionElement] = [
      GuionElement(elementType: .character, elementText: "VOICE"),
      GuionElement(elementType: .dialogue, elementText: stripped),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)

    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: [(character: "VOICE", text: stripped)]
    )

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult
    )

    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.pausePoints.count == 1)
    // "Silence." is 8 scalars; the pause follows it.
    #expect(dialogueElement.pausePoints[0].offset == 8)
    #expect(dialogueElement.pausePoints[0].length == .beat)
  }
}
