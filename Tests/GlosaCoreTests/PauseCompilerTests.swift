import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaCompiler`'s pause-points projection — taking the scene-local
/// `Pause` values that `GlosaParser` emits and re-keying them into the
/// absolute-line-indexed `CompilationResult.pausePoints` dictionary.
///
/// Also covers the same-offset collapse (Decision 4): when a `<breath/>` and a
/// `<pause/>` coincide at the exact same `(line, offset)`, the compiler drops
/// the breath, keeps the pause, and emits an `.info` diagnostic with code
/// `.breathCollapsedByPause`.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed.
@Suite("GlosaCompiler pause-points projection + same-offset collapse")
struct PauseCompilerTests {

  let compiler = GlosaCompiler()

  // MARK: - Fixture helpers

  /// A single scene/intent/line Fountain note fixture with one `<pause/>`.
  private func singlePauseNotes(pauseLength: String = "period") -> [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      "Bishop is freighted:[[<pause length=\"\(pauseLength)\"/>]] authority, patriarchy, done.",
      "</Intent>",
      "</SceneContext>",
    ]
  }

  // MARK: - Test 1 — basic pause projection (single scene)

  @Test("Single pause projects onto absolute line 0")
  func singlePauseProjectsToLine0() throws {
    let notes = singlePauseNotes()
    let strippedLine =
      "Bishop is freighted: authority, patriarchy, done."

    let dialogueLines: [(character: String, text: String)] = [
      (character: "THE PRACTITIONER", text: strippedLine)
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // Exactly one key in pausePoints — absolute line 0.
    #expect(result.pausePoints.keys.sorted() == [0])

    let pts = result.pausePoints[0] ?? []
    #expect(pts.count == 1)
    #expect(pts[0].offset == 20)  // offset of "Bishop is freighted:" (20 chars)
    #expect(pts[0].length == .period)
  }

  @Test("Pause length=beat is preserved in PausePoint")
  func pauseLengthBeatPreserved() throws {
    let notes = singlePauseNotes(pauseLength: "beat")
    let strippedLine = "Bishop is freighted: authority, patriarchy, done."
    let dialogueLines: [(character: String, text: String)] = [
      (character: "THE PRACTITIONER", text: strippedLine)
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    let pts = result.pausePoints[0] ?? []
    #expect(pts.count == 1)
    #expect(pts[0].length == .beat)
  }

  // MARK: - Test 2 — multi-scene pause projection

  @Test("Multi-scene — pause in scene 2 lands on absolute line 1")
  func pauseInScene2LandsOnAbsoluteLine1() throws {
    let notes: [String] = [
      // Scene 1: one short dialogue line, no pauses.
      #"<SceneContext location="the corridor" time="earlier">"#,
      #"<Intent from="neutral" to="curious" pace="moderate">"#,
      "Hi.",
      "</Intent>",
      "</SceneContext>",
      // Scene 2: dialogue line with a pause.
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      "Bishop is freighted:[[<pause length=\"period\"/>]] authority, done.",
      "</Intent>",
      "</SceneContext>",
    ]

    let dialogueLines: [(character: String, text: String)] = [
      (character: "PRACTITIONER", text: "Hi."),
      (
        character: "THE PRACTITIONER",
        text: "Bishop is freighted: authority, done."
      ),
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // The pause must land on absolute line 1 (scene 2 maps to absolute index 1).
    #expect(result.pausePoints.keys.sorted() == [1])

    let pts = result.pausePoints[1] ?? []
    #expect(pts.count == 1)
    #expect(pts[0].offset == 20)
    #expect(pts[0].length == .period)

    // No pause on line 0 (scene 1's short line).
    #expect(result.pausePoints[0] == nil)
  }

  // MARK: - Test 3 — no key for lines with no pauses

  @Test("Line with no pauses has no key in pausePoints")
  func noKeyForLinewithNoPauses() throws {
    let notes: [String] = [
      #"<SceneContext location="anywhere" time="anytime">"#,
      #"<Intent from="neutral" to="neutral" pace="moderate">"#,
      "A line with no pause markers at all.",
      "</Intent>",
      "</SceneContext>",
    ]
    let dialogueLines: [(character: String, text: String)] = [
      (character: "VOICE", text: "A line with no pause markers at all.")
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    #expect(result.pausePoints.isEmpty)
    #expect(result.pausePoints[0] == nil)
    #expect((result.pausePoints[0] ?? []).isEmpty)
  }

  // MARK: - Test 4 — mapPausesToAbsoluteLines static method directly

  @Test("mapPausesToAbsoluteLines sorts per-line pause arrays ascending by offset")
  func mapPausesToAbsoluteLinesSort() throws {
    let strippedBishop =
      "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

    let sceneContext = SceneContext(
      location: "the rectory office",
      time: "late afternoon",
      ambience: nil
    )
    let intent = Intent(from: "controlled", to: "indicting", pace: "moderate", spacing: nil)
    let intentEntry = GlosaScore.IntentEntry(
      intent: intent,
      constraints: [],
      dialogueLines: [strippedBishop]
    )
    let sceneEntry = GlosaScore.SceneEntry(context: sceneContext, intents: [intentEntry])

    // Pauses in non-ascending order to confirm sorting.
    let unsortedPauses: [Pause] = [
      Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 43, length: .beat),
      Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .period),
      Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 31, length: .comma),
    ]
    let score = GlosaScore(scenes: [sceneEntry], pauses: unsortedPauses)

    let pausePoints = GlosaCompiler.mapPausesToAbsoluteLines(
      score: score,
      dialogueLines: [strippedBishop]
    )

    #expect(pausePoints.keys.sorted() == [0])
    let pts = pausePoints[0] ?? []
    #expect(pts.map(\.offset) == [20, 31, 43])
    #expect(pts[0].length == .period)
    #expect(pts[1].length == .comma)
    #expect(pts[2].length == .beat)
  }

  // MARK: - Test 5 — same-offset collapse (Decision 4)

  /// The key behavior of same-offset collapse: a `<breath/>` and a `<pause/>`
  /// at the exact same `(line, offset)` causes the breath to be dropped and
  /// only the pause to survive in the result. An `.info` diagnostic with code
  /// `.breathCollapsedByPause` is emitted.
  @Test("Co-located breath and pause collapses to PausePoint only; info diagnostic emitted")
  func sameOffsetCollapseBreathDropped() throws {
    // Both the breath and pause land at offset 20 in the stripped prose.
    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      "Bishop is freighted:[[<breath strength=\"strong\"/>]][[<pause length=\"period\"/>]] authority.",
      "</Intent>",
      "</SceneContext>",
    ]

    let strippedLine = "Bishop is freighted: authority."
    let dialogueLines: [(character: String, text: String)] = [
      (character: "THE PRACTITIONER", text: strippedLine)
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // The pause survives.
    let pausePts = result.pausePoints[0] ?? []
    #expect(pausePts.count == 1)
    #expect(pausePts[0].offset == 20)
    #expect(pausePts[0].length == .period)

    // The co-located breath is dropped: key 0 must be absent from breathPoints.
    #expect(result.breathPoints[0] == nil)

    // Exactly one info diagnostic with the breathCollapsedByPause code.
    let infos = result.diagnostics.filter {
      $0.code == .breathCollapsedByPause && $0.severity == .info
    }
    #expect(infos.count == 1)
    #expect(infos[0].message.contains("pause"))
  }

  @Test("Non-co-located breath and pause on same line both survive")
  func nonCoLocatedBreathAndPauseSurvive() throws {
    // Breath at offset 5 ("Hello"), pause at offset 11 ("Hello world").
    let notes: [String] = [
      #"<SceneContext location="stage" time="dusk">"#,
      #"<Intent from="a" to="b">"#,
      "Hello[[<breath/>]] world[[<pause/>]] done.",
      "</Intent>",
      "</SceneContext>",
    ]

    let strippedLine = "Hello world done."
    let dialogueLines: [(character: String, text: String)] = [
      (character: "VOICE", text: strippedLine)
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // Both breath and pause survive at different offsets.
    let breathPts = result.breathPoints[0] ?? []
    let pausePts = result.pausePoints[0] ?? []
    #expect(breathPts.count == 1)
    #expect(breathPts[0].offset == 5)
    #expect(pausePts.count == 1)
    #expect(pausePts[0].offset == 11)

    // No collapse diagnostic.
    let collapses = result.diagnostics.filter { $0.code == .breathCollapsedByPause }
    #expect(collapses.isEmpty)
  }

  @Test("Same-offset collapse: only the co-located breath is dropped; others survive")
  func sameOffsetCollapseOnlyColocatedBreathDropped() throws {
    // Three breaths on the line: one co-located with a pause (offset 20),
    // two at different offsets (31, 43). Only the co-located breath is dropped.
    let bishopDialogue =
      "Bishop is freighted:[[<breath strength=\"strong\"/>]][[<pause length=\"period\"/>]] authority,"
      + "[[<breath/>]] patriarchy,[[<breath/>]] done."

    let notes: [String] = [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopDialogue,
      "</Intent>",
      "</SceneContext>",
    ]

    let strippedLine =
      "Bishop is freighted: authority, patriarchy, done."
    let dialogueLines: [(character: String, text: String)] = [
      (character: "THE PRACTITIONER", text: strippedLine)
    ]

    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // The pause at offset 20 survives.
    let pausePts = result.pausePoints[0] ?? []
    #expect(pausePts.count == 1)
    #expect(pausePts[0].offset == 20)

    // The two breaths at 31 and 43 survive; the one at 20 is collapsed.
    let breathPts = result.breathPoints[0] ?? []
    #expect(breathPts.count == 2)
    #expect(breathPts.map(\.offset) == [31, 43])

    // Exactly one collapse diagnostic.
    let collapses = result.diagnostics.filter { $0.code == .breathCollapsedByPause }
    #expect(collapses.count == 1)
  }

  // MARK: - Test 6 — empty notes returns empty pause dict

  @Test("Empty notes yields empty pausePoints")
  func emptyNotesYieldsEmptyPausePoints() throws {
    let result = try compiler.compile(fountainNotes: [], dialogueLines: [])
    #expect(result.pausePoints.isEmpty)
  }
}
