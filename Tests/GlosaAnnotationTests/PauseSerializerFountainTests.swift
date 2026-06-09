import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s Fountain `[[<pause …/>]]` inline-note
/// serialization (OPERATION CLEAVING BREATH, Sortie 9).
///
/// Canonical pause form (spec §4.2, serializer `pauseNoteTag(for:)`):
/// - Bare `[[<pause/>]]` when `length=.period` (the pause default).
/// - `[[<pause length="…"/>]]` when a non-default length is set.
/// - Named lengths use the wire tokens (`comma`, `semicolon`, `period`,
///   `em-dash`, `beat`); explicit durations serialize as `"<ms>ms"`.
///
/// ## Methodology
/// - **Deterministic**: no `Date()`, no `UUID()`, no random seeds.
/// - **Hermetic**: no network, no filesystem.
/// - Every asserted offset is computed by hand against the notes-stripped prose.
@Suite("PauseSerializer Fountain — emission and default-length omission")
struct PauseSerializerFountainTests {

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  // MARK: - Helpers

  /// Build a single-dialogue annotated screenplay from explicit pause points,
  /// bypassing the parser so the test owns the exact offsets/lengths.
  private func makeAnnotated(
    prose: String,
    pausePoints: [PausePoint]
  ) -> GlosaAnnotatedScreenplay {
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(
      element: element,
      pausePoints: pausePoints
    )
    let screenplay = GuionParsedElementCollection(elements: [element])
    return GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [annotatedElement],
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )
  }

  // MARK: - Test 1: default-length pause omits length=

  /// A `.period` pause is the default — its `length=` attribute must be omitted,
  /// producing the bare `[[<pause/>]]` form.
  @Test("Default-length (.period) pause emits bare [[<pause/>]] with no length=")
  func defaultLengthOmitsLength() {
    // Prose: "Hold:" is 5 scalars; the pause sits at offset 5 (after the colon).
    let prose = "Hold: then speak."
    let annotated = makeAnnotated(
      prose: prose,
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )

    let output = serializer.writeFountain(annotated)

    #expect(output.contains("[[<pause/>]]"))
    let pauseLines = output.components(separatedBy: "\n").filter { $0.contains("[[<pause") }
    for line in pauseLines {
      #expect(!line.contains("length="), "length= must be omitted for default .period pause")
    }
    // The pause sits immediately after "Hold:".
    #expect(output.contains("Hold:[[<pause/>]] then speak."))
  }

  // MARK: - Test 2: non-default length is included

  @Test("Non-default length (.beat) emits [[<pause length=\"beat\"/>]]")
  func nonDefaultLengthIncluded() {
    let prose = "Silence. Resume."
    let annotated = makeAnnotated(
      prose: prose,
      pausePoints: [PausePoint(offset: 8, length: .beat)]
    )

    let output = serializer.writeFountain(annotated)

    #expect(output.contains("[[<pause length=\"beat\"/>]]"))
    // "Silence." is 8 scalars; the pause follows it.
    #expect(output.contains("Silence.[[<pause length=\"beat\"/>]] Resume."))
  }

  @Test("Each named length emits its wire token (comma/semicolon/em-dash/beat)")
  func namedLengthTokens() {
    let cases: [(PauseLength, String)] = [
      (.comma, "comma"),
      (.semicolon, "semicolon"),
      (.emDash, "em-dash"),
      (.beat, "beat"),
    ]
    for (length, token) in cases {
      let annotated = makeAnnotated(
        prose: "AB done.",
        pausePoints: [PausePoint(offset: 2, length: length)]
      )
      let output = serializer.writeFountain(annotated)
      #expect(
        output.contains("[[<pause length=\"\(token)\"/>]]"),
        "Expected length=\"\(token)\" for \(length)"
      )
    }
  }

  @Test("Explicit length serializes as <ms>ms (0.35s → 350ms)")
  func explicitLengthMilliseconds() {
    let annotated = makeAnnotated(
      prose: "AB done.",
      pausePoints: [PausePoint(offset: 2, length: .explicit(0.35))]
    )
    let output = serializer.writeFountain(annotated)
    #expect(output.contains("[[<pause length=\"350ms\"/>]]"))
  }

  // MARK: - Test 3: round-trip through the parser

  @Test("Default-length pause round-trips: re-parsed pause is .period at same offset")
  func defaultLengthRoundTrips() throws {
    let prose = "Hold: then speak."
    let annotated = makeAnnotated(
      prose: prose,
      pausePoints: [PausePoint(offset: 5, length: .period)]
    )
    let output = serializer.writeFountain(annotated)

    // Re-parse the emitted inline note. The single dialogue line is the only
    // note relevant to pause extraction.
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      "Hold:[[<pause/>]] then speak.",
      "</Intent>",
      "</SceneContext>",
    ]
    // Sanity: the serialized dialogue line matches what we re-feed.
    #expect(output.contains("Hold:[[<pause/>]] then speak."))

    let reparsed = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(reparsed.score.pauses.count == 1)
    #expect(reparsed.score.pauses[0].characterOffset == 5)
    #expect(reparsed.score.pauses[0].length == .period)
    #expect(reparsed.diagnostics.isEmpty)
  }

  @Test("Non-default length round-trips: re-parsed pause keeps .beat")
  func nonDefaultLengthRoundTrips() throws {
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      "Silence.[[<pause length=\"beat\"/>]] Resume.",
      "</Intent>",
      "</SceneContext>",
    ]
    let reparsed = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(reparsed.score.pauses.count == 1)
    #expect(reparsed.score.pauses[0].characterOffset == 8)
    #expect(reparsed.score.pauses[0].length == .beat)
    #expect(reparsed.diagnostics.isEmpty)
  }

  // MARK: - Test 4: pause-free dialogue emits no pause notes

  @Test("Dialogue with no pause points emits no [[<pause notes")
  func pauseFreeDialogueEmitsNoNotes() {
    let prose = "I noticed."
    let annotated = makeAnnotated(prose: prose, pausePoints: [])
    let output = serializer.writeFountain(annotated)
    #expect(!output.contains("[[<pause"))
    #expect(output.contains(prose))
  }

  // MARK: - Test 5: pause + breath co-exist on one line at different offsets

  @Test("A breath and a pause on one line both serialize at their offsets")
  func breathAndPauseCoExist() {
    // Prose: "Hold:" = 5 scalars (pause after colon); "Hold: a," = 8 scalars,
    // breath after the comma at offset 8.
    let prose = "Hold: a, b."
    let element = GuionElement(elementType: .dialogue, elementText: prose)
    let annotatedElement = GlosaAnnotatedElement(
      element: element,
      breathPoints: [BreathPoint(offset: 8, strength: .medium)],
      pausePoints: [PausePoint(offset: 5, length: .period)]
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
    #expect(output.contains("[[<pause/>]]"))
    #expect(output.contains("[[<breath/>]]"))
    // pause after "Hold:" (offset 5), breath after "Hold: a," (offset 8).
    #expect(output.contains("Hold:[[<pause/>]] a,[[<breath/>]] b."))
  }
}
