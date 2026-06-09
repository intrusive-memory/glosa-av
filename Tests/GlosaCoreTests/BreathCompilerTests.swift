import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaCompiler`'s breath-points projection — taking the
/// scene-local `Breath` values that `GlosaParser` emits and re-keying them
/// into the absolute-line-indexed `CompilationResult.breathPoints`
/// dictionary required by spec §7.4.
///
/// `BreathPoint` no longer carries `length` (OPERATION CLEAVING BREATH,
/// Sortie 1). Tests that previously asserted `points[n].length` have been
/// updated to assert `points[n].strength` instead.
///
/// ## Dictionary-key contract
///
/// This implementation **omits the key** for any dialogue line that has no
/// breath annotations — `breathPoints[lineIndex] == nil` and the
/// contract-equivalent `breathPoints[lineIndex] ?? []` both mean "no chunk
/// hints for that line." Spec §7.4 explicitly permits either form (empty
/// array OR missing key); key omission is chosen here so the dictionary
/// stays minimal for the common case of breath-free screenplays.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed. Per-line breath arrays are asserted in their sorted
/// (ascending-offset) form.
@Suite("GlosaCompiler breath-points projection")
struct BreathCompilerTests {

  let compiler = GlosaCompiler()

  // MARK: - Test 1 — single-scene Bishop case

  /// Bishop dialogue line as the only line in a single-scene screenplay.
  /// All three breaths land on absolute line 0, sorted ascending by offset
  /// (20 / 31 / 43 per spec §6.4), with strength preserved verbatim from
  /// the parser. Also pins the "no key when no breaths" contract by
  /// asserting `breathPoints.keys == {0}`.
  @Test("Single-scene Bishop — three breaths on absolute line 0")
  func bishopSingleScene() throws {
    let bishopDialogue =
      "Bishop is freighted:[[<breath strength=\"strong\"/>]] authority,"
      + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopDialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let strippedBishop =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    let dialogueLines: [(character: String, text: String)] = [
      (character: "THE PRACTITIONER", text: strippedBishop)
    ]

    let result = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    // Exactly one key in the breath-points dictionary — line 0.
    #expect(result.breathPoints.keys.sorted() == [0])

    let points = result.breathPoints[0] ?? []
    #expect(points.count == 3)

    // Offsets verbatim from spec §6.4, in ascending order.
    #expect(points.map(\.offset) == [20, 31, 43])

    // Strength verbatim from spec §6.4.
    #expect(points[0].strength == .strong)
    #expect(points[1].strength == .medium)
    #expect(points[2].strength == .medium)
  }

  // MARK: - Test 2 — multi-scene mapping guard

  /// Two scenes. Scene 1 has one (short) dialogue line and no breaths.
  /// Scene 2 has the Bishop line with three breaths at scene-local index 0.
  /// The compiler must map Bishop's breaths to **absolute** line 1, not
  /// line 0 — the scene-local→absolute projection is the contract this
  /// test guards.
  @Test("Multi-scene — Bishop in scene 2 lands on absolute line 1")
  func bishopInScene2WithPriorScene() throws {
    let bishopDialogue =
      "Bishop is freighted:[[<breath strength=\"strong\"/>]] authority,"
      + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

    let notes: [String] = [
      // Scene 1: one short dialogue line, no breaths.
      #"<SceneContext location="the corridor" time="earlier">"#,
      #"<Intent from="neutral" to="curious" pace="moderate">"#,
      "Hi.",
      "</Intent>",
      "</SceneContext>",
      // Scene 2: Bishop line, three breaths.
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopDialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let strippedBishop =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    let dialogueLines: [(character: String, text: String)] = [
      (character: "PRACTITIONER", text: "Hi."),
      (character: "THE PRACTITIONER", text: strippedBishop),
    ]

    let result = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    // Bishop's three breaths must land on absolute line 1, not line 0.
    #expect(result.breathPoints.keys.sorted() == [1])

    let points = result.breathPoints[1] ?? []
    #expect(points.count == 3)
    #expect(points.map(\.offset) == [20, 31, 43])
    #expect(points[0].strength == .strong)
  }

  // MARK: - Test 3 — line with no breaths has no key

  /// Dictionary-key contract test (see suite docstring). This sortie's
  /// implementation **omits the key** for lines with no breaths.
  @Test("Line with no breaths has no key in breathPoints (omit, not empty array)")
  func noBreathsLineHasNoKeyOmittedNotEmptyArray() throws {
    let notes: [String] = [
      #"<SceneContext location="anywhere" time="anytime">"#,
      #"<Intent from="neutral" to="neutral" pace="moderate">"#,
      "A line with no breath markers at all.",
      "</Intent>",
      "</SceneContext>",
    ]

    let dialogueLines: [(character: String, text: String)] = [
      (character: "VOICE", text: "A line with no breath markers at all.")
    ]

    let result = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    // The dictionary is empty (key 0 absent, not present-with-empty-array).
    #expect(result.breathPoints.isEmpty)
    #expect(result.breathPoints[0] == nil)
    // Defaulted lookup yields an empty array.
    #expect((result.breathPoints[0] ?? []).isEmpty)
  }

  // MARK: - Test 4 — unsorted input is sorted ascending on output

  /// Verify the compiler sorts per-line breath arrays ascending regardless
  /// of input order, by bypassing the parser and exercising
  /// `mapBreathsToAbsoluteLines` with a hand-built `GlosaScore` whose
  /// `breaths` array is `[31, 20, 43]`.
  @Test("Per-line breath arrays are sorted ascending by offset on output")
  func unsortedBreathsAreSortedOnOutput() throws {
    let strippedBishop =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    let sceneContext = SceneContext(
      location: "the rectory office",
      time: "late afternoon",
      ambience: nil
    )
    let intent = Intent(
      from: "controlled",
      to: "indicting",
      pace: "moderate",
      spacing: nil
    )
    let intentEntry = GlosaScore.IntentEntry(
      intent: intent,
      constraints: [],
      dialogueLines: [strippedBishop]
    )
    let sceneEntry = GlosaScore.SceneEntry(
      context: sceneContext,
      intents: [intentEntry]
    )

    // Breaths in non-ascending order.
    let unsortedBreaths: [Breath] = [
      Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 31),
      Breath(
        sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20,
        strength: .strong),
      Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 43),
    ]
    let score = GlosaScore(scenes: [sceneEntry], breaths: unsortedBreaths)

    let breathPoints = GlosaCompiler.mapBreathsToAbsoluteLines(
      score: score,
      dialogueLines: [strippedBishop]
    )

    #expect(breathPoints.keys.sorted() == [0])
    let points = breathPoints[0] ?? []
    #expect(points.map(\.offset) == [20, 31, 43])

    // Strength follows offset after sorting — confirms the sort is stable in spirit.
    #expect(points[0].strength == .strong)
    #expect(points[1].strength == .medium)
    #expect(points[2].strength == .medium)
  }
}
