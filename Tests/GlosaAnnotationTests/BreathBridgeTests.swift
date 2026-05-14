import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Tests for the breath-point bridge: verifies that
/// `GlosaAnnotatedScreenplay.build(from:compilationResult:)` correctly
/// propagates `CompilationResult.breathPoints` onto the `breathPoints`
/// field of each `GlosaAnnotatedElement`.
///
/// ## Methodology (OPERATION SIGHING SCRIBE)
///
/// - **Deterministic**: no `Date()`, no `UUID()`, no random seeds. Breath-point
///   arrays are asserted in ascending-offset order (which the compiler
///   guarantees per S4's spec §7.4 contract).
/// - **Hermetic**: no network, no filesystem, no shared mutable state.
/// - **Untimed**: no `Thread.sleep`, no `XCTestExpectation`, no `measure {}`.
///
/// ## Bishop fixture
///
/// The canonical fixture from spec §6.4 and reused across S2 / S4 tests:
///
/// ```
/// Bishop is freighted:[[<breath length="period" strength="strong"/>]] authority,
/// [[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology.
/// ```
///
/// Stripped prose (what the actor reads):
/// ```
/// Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology.
/// ```
///
/// Expected breath points at offsets `20` (period/strong), `31` (comma/medium),
/// `43` (comma/medium) per spec §6.4.
@Suite("BreathBridge — GlosaAnnotatedElement.breathPoints")
struct BreathBridgeTests {

  // MARK: - Fixture helpers

  /// The raw Bishop dialogue string, with inline `[[<breath…/>]]` notes.
  private let bishopRaw =
    "Bishop is freighted:[[<breath length=\"period\" strength=\"strong\"/>]] authority,"
    + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

  /// The notes-stripped Bishop prose that appears in the compiled screenplay.
  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  /// Minimal Fountain notes block for the Bishop case — one scene, one intent,
  /// the Bishop dialogue line carrying three inline breath notes.
  private var bishopNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  /// Build a minimal `GuionParsedElementCollection` that matches the
  /// Bishop fixture:
  ///
  ///   [0] sceneHeading  — "INT. RECTORY OFFICE - LATE AFTERNOON"
  ///   [1] action        — "The Bishop sits across the table."
  ///   [2] character     — "THE PRACTITIONER"
  ///   [3] dialogue      — bishopStripped        ← dialogue index 0
  ///
  /// Non-dialogue elements at indices 0, 1, and 2 must carry `breathPoints == []`.
  /// The dialogue element at index 3 must carry three sorted `BreathPoint`s.
  private func makeBishopScreenplay() -> GuionParsedElementCollection {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. RECTORY OFFICE - LATE AFTERNOON"),
      GuionElement(elementType: .action, elementText: "The Bishop sits across the table."),
      GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
      GuionElement(elementType: .dialogue, elementText: bishopStripped),
    ]
    return GuionParsedElementCollection(elements: elements)
  }

  // MARK: - Test 1: dialogue element exposes three sorted breath points

  /// Compile the Bishop notes and assert that the annotated dialogue element
  /// at absolute dialogue index 0 exposes exactly three `BreathPoint`s sorted
  /// ascending by offset — `20` (period/strong), `31` (comma/medium),
  /// `43` (comma/medium) — matching spec §6.4.
  @Test("Bishop dialogue element carries three sorted BreathPoints at offsets 20/31/43")
  func bishopDialogueElementHasThreeBreathPoints() throws {
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

    // The dialogue element is at element index 3 (absolute dialogue index 0).
    #expect(annotated.annotatedElements.count == 4)
    let dialogueElement = annotated.annotatedElements[3]
    #expect(dialogueElement.element.elementType == .dialogue)

    let points = dialogueElement.breathPoints
    #expect(points.count == 3)

    // Verify the array is already in ascending-offset order (compiler contract).
    #expect(points.map(\.offset) == points.sorted { $0.offset < $1.offset }.map(\.offset))

    // Offsets verbatim from spec §6.4.
    #expect(points.map(\.offset) == [20, 31, 43])

    // Attributes verbatim from spec §6.4.
    #expect(points[0].length == .period)
    #expect(points[0].strength == .strong)
    #expect(points[1].length == .comma)
    #expect(points[1].strength == .medium)
    #expect(points[2].length == .comma)
    #expect(points[2].strength == .medium)
  }

  // MARK: - Test 2: non-dialogue elements carry empty breathPoints

  /// All non-dialogue elements in the Bishop screenplay (scene heading,
  /// action, character cue) must expose `breathPoints == []`.
  @Test("Non-dialogue elements (sceneHeading, action, character) carry empty breathPoints")
  func nonDialogueElementsHaveEmptyBreathPoints() throws {
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

    // Indices 0, 1, 2 are sceneHeading, action, character — all non-dialogue.
    let sceneHeading = annotated.annotatedElements[0]
    #expect(sceneHeading.element.elementType == .sceneHeading)
    #expect(sceneHeading.breathPoints.isEmpty)

    let action = annotated.annotatedElements[1]
    #expect(action.element.elementType == .action)
    #expect(action.breathPoints.isEmpty)

    let character = annotated.annotatedElements[2]
    #expect(character.element.elementType == .character)
    #expect(character.breathPoints.isEmpty)
  }

  // MARK: - Test 3: dialogue element with no breaths carries empty breathPoints

  /// A dialogue element for a line that has no breath annotations must also
  /// carry `breathPoints == []`, confirming the missing-key contract from
  /// `CompilationResult.breathPoints` is bridged correctly.
  @Test("Dialogue element with no breath annotations carries empty breathPoints")
  func breathFreeDialogueElementHasEmptyBreathPoints() throws {
    let plainText = "A line with no breath markers at all."
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

    #expect(annotated.annotatedElements.count == 2)

    // Sanity-check: the compilation result has no breath points.
    #expect(compilationResult.breathPoints.isEmpty)

    // The annotated dialogue element must therefore carry an empty array.
    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    #expect(dialogueElement.breathPoints.isEmpty)
  }

  // MARK: - Test 4: breathPoints default is [] for direct construction

  /// Constructing a `GlosaAnnotatedElement` without providing `breathPoints`
  /// must produce an element with an empty array — confirming the default
  /// argument is in place.
  @Test("GlosaAnnotatedElement default breathPoints is empty")
  func defaultBreathPointsIsEmpty() {
    let element = GuionElement(elementType: .action, elementText: "She enters.")
    let annotatedElement = GlosaAnnotatedElement(element: element)
    #expect(annotatedElement.breathPoints.isEmpty)
  }
}
