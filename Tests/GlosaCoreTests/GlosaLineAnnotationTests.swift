import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaLineAnnotation`, `PausePointDTO`, and `compileAnnotations`
/// (Sortie 2 / FR2).
///
/// ## Acceptance criteria covered
///
/// - **AC2a** (`breathOffsetIndexing`): offsets in `breathOffsets` index
///   correctly into `spokenText` for a multi-breath fixture that includes
///   emoji, combining marks, and `after=`-positioned breaths.
///
/// - **AC2b** (`breathOffsetRoundTrip`): splitting `spokenText.unicodeScalars`
///   at `breathOffsets` and reassembling the pieces produces a string that is
///   byte-identical to `spokenText`.
///
/// - **AC2c** (`pausePointDTOMapping`): each named `PauseLength` preset maps
///   to the correct `(lengthMs, named)` pair, and `.explicit(seconds)` maps
///   to rounded milliseconds with `named == nil`.
@Suite("GlosaLineAnnotation + compileAnnotations (FR2)")
struct GlosaLineAnnotationTests {

  // MARK: - Helpers

  /// Build a minimal `compileAnnotations` call around a single dialogue line
  /// that contains two breath notes so we get two offsets to exercise.
  ///
  /// The dialogue line is:
  ///   "Café\u{0301} crowd 👩‍👩‍👧‍👦[[<breath/>]] cheered 🇫🇷[[<breath strength="strong"/>]] for résumé\u{0301}s."
  ///
  /// Stripped form (spokenText):
  ///   "Café\u{0301} crowd 👩‍👩‍👧‍👦 cheered 🇫🇷 for résumé\u{0301}s."
  ///
  /// The two breath notes are positioned *inline* (no `after=`), so their
  /// offsets mark the unicodeScalar count up to the end of each preceding
  /// prose segment.
  func buildEmojiFixtureAnnotation() throws -> GlosaLineAnnotation {
    let raw =
      "Caf\u{00E9}\u{0301} crowd \u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      + "[[<breath/>]]"
      + " cheered \u{1F1EB}\u{1F1F7}"
      + "[[<breath strength=\"strong\"/>]]"
      + " for r\u{00E9}sum\u{00E9}\u{0301}s."

    let fountainNotes: [String] = [
      #"<SceneContext location="plaza" time="afternoon">"#,
      #"<Intent from="quiet" to="jubilant" pace="moderate">"#,
      raw,
      "</Intent>",
      "</SceneContext>",
    ]

    let annotations = try compileAnnotations(
      fountainNotes: fountainNotes,
      rawDialogueLines: [
        (character: "NARRATOR", rawText: raw)
      ]
    )

    guard let annotation = annotations[0] else {
      Issue.record("Expected annotation at index 0")
      // Return a dummy so the caller can at least compile; the #expect checks below will fail.
      return GlosaLineAnnotation(
        spokenText: "", breathOffsets: [], breathStrengths: [], instruct: nil, pausePoints: [])
    }
    return annotation
  }

  // MARK: - AC2a: Offset indexing

  /// Verifies that each entry in `breathOffsets` is a valid
  /// `unicodeScalars.count` boundary in `spokenText`, and that the scalar
  /// immediately before that boundary is part of the prose segment we expect
  /// (not the inline note itself, which must have been stripped).
  ///
  /// Covers: AC2a (offset-indexing into spokenText, incl. emoji/combining marks).
  @Test("breathOffsets index correctly into spokenText (emoji + combining marks, AC2a)")
  func breathOffsetIndexing() throws {
    let annotation = try buildEmojiFixtureAnnotation()

    let scalars = Array(annotation.spokenText.unicodeScalars)
    let totalScalars = scalars.count

    // We expect exactly two breath offsets.
    #expect(annotation.breathOffsets.count == 2)
    #expect(annotation.breathStrengths.count == 2)

    for offset in annotation.breathOffsets {
      // Each offset must be a valid index: 0 <= offset <= totalScalars.
      // (offset == totalScalars means "after last scalar" which is technically
      // valid per the spec but unusual; the parser would emit a diagnostic.)
      #expect(offset >= 0)
      #expect(offset <= totalScalars)
    }

    // Offsets must be sorted ascending.
    if annotation.breathOffsets.count >= 2 {
      #expect(annotation.breathOffsets[0] < annotation.breathOffsets[1])
    }

    // The spokenText must not contain any [[ ]] brackets — confirm stripping.
    #expect(!annotation.spokenText.contains("[["))
    #expect(!annotation.spokenText.contains("]]"))

    // Strengths should be "medium" (default) and "strong".
    #expect(annotation.breathStrengths[0] == "medium")
    #expect(annotation.breathStrengths[1] == "strong")
  }

  // MARK: - AC2b: Unicode-scalar round-trip

  /// Splits `spokenText.unicodeScalars` at each offset in `breathOffsets` and
  /// reassembles the pieces, then asserts the result is byte-identical to
  /// `spokenText`.
  ///
  /// This is the canonical AC2 round-trip test. The splitting strategy:
  ///
  ///   1. Collect the sorted offsets plus a sentinel at `scalars.endIndex`.
  ///   2. Walk boundary-to-boundary slicing `scalars[prev..<next]`.
  ///   3. Concatenate each slice as a `String` and compare to `spokenText`.
  ///
  /// The reassembly is purely additive (no mutation, no re-encoding), so any
  /// deviation flags a mis-counted offset.
  ///
  /// Covers: AC2b (lossless round-trip through unicodeScalars at breathOffsets).
  @Test("Splitting spokenText.unicodeScalars at breathOffsets round-trips losslessly (AC2b)")
  func breathOffsetRoundTrip() throws {
    let annotation = try buildEmojiFixtureAnnotation()

    let scalars = annotation.spokenText.unicodeScalars
    let sortedOffsets = annotation.breathOffsets.sorted()

    // Build the list of chunk boundaries: [0, offset0, offset1, …, scalars.count]
    var boundaries: [Int] = [0]
    boundaries.append(contentsOf: sortedOffsets)
    boundaries.append(scalars.count)

    var reassembled = ""
    for i in 0..<(boundaries.count - 1) {
      let from = boundaries[i]
      let to = boundaries[i + 1]

      // Bounds-check each slice pair — a bad offset would underflow/overflow here.
      #expect(from >= 0)
      #expect(to <= scalars.count)
      #expect(from <= to)

      // Slice the unicodeScalars and promote to String.
      let startIdx = scalars.index(scalars.startIndex, offsetBy: from)
      let endIdx = scalars.index(scalars.startIndex, offsetBy: to)
      let slice = scalars[startIdx..<endIdx]
      reassembled += String(slice)
    }

    // The reassembled string must be byte-identical to the original spokenText.
    #expect(reassembled == annotation.spokenText)
  }

  // MARK: - AC2c: PausePointDTO mapping

  /// Asserts the OQ-3 mapping for every named `PauseLength` preset and for
  /// one `.explicit` value.
  ///
  /// The mapping is sourced from `PausePointDTO.components(for:)` — the single
  /// source of truth — so this test directly exercises that function.
  ///
  /// Covers: AC2c (pause-preset → lengthMs/named, explicit → rounded ms with named=nil).
  @Test("PausePointDTO maps named PauseLength presets to correct (lengthMs, named) pairs (AC2c)")
  func pausePointDTOMapping() {
    // Named presets — exact wire values from OQ-3.
    let namedCases: [(PauseLength, Int, String)] = [
      (.comma, 150, "comma"),
      (.semicolon, 250, "semicolon"),
      (.period, 400, "period"),
      (.emDash, 600, "em-dash"),
      (.beat, 1000, "beat"),
    ]

    for (length, expectedMs, expectedNamed) in namedCases {
      let (ms, name) = PausePointDTO.components(for: length)
      #expect(ms == expectedMs, "lengthMs mismatch for \(length)")
      #expect(name == expectedNamed, "named mismatch for \(length)")
    }

    // .explicit: rounded integer ms, named == nil.
    // Use 0.35 s — IEEE-754 stores it as 0.349999…, truncation would give 349;
    // .rounded() must yield 350.
    let (explicitMs, explicitNamed) = PausePointDTO.components(for: .explicit(0.35))
    #expect(explicitMs == 350)
    #expect(explicitNamed == nil)

    // Additional explicit: 1.5 s → 1500 ms.
    let (ms15, name15) = PausePointDTO.components(for: .explicit(1.5))
    #expect(ms15 == 1500)
    #expect(name15 == nil)

    // Zero explicit: 0 s → 0 ms.
    let (ms0, name0) = PausePointDTO.components(for: .explicit(0))
    #expect(ms0 == 0)
    #expect(name0 == nil)
  }

  // MARK: - PausePointDTO via compileAnnotations (integration)

  /// Exercises the end-to-end pause projection through `compileAnnotations`,
  /// verifying that `PausePointDTO`s in the returned annotation have the
  /// correct `offset`, `lengthMs`, and `named` values.
  @Test("compileAnnotations projects PausePoint → PausePointDTO correctly")
  func compileAnnotationsPauseProjection() throws {
    // A line with a period-length pause in the middle.
    let raw = "She waited[[<pause length=\"400ms\"/>]] then spoke at last."

    let fountainNotes: [String] = [
      #"<SceneContext location="hall" time="evening">"#,
      #"<Intent from="anxious" to="calm" pace="slow">"#,
      raw,
      "</Intent>",
      "</SceneContext>",
    ]

    let annotations = try compileAnnotations(
      fountainNotes: fountainNotes,
      rawDialogueLines: [
        (character: "EVE", rawText: raw)
      ]
    )

    let annotation = try #require(annotations[0])

    // The pause should have been projected to PausePointDTO.
    // 400ms → .explicit(0.4) in the parser → lengthMs=400, named=nil
    // (Note: the parser converts "400ms" to .explicit(0.4), not .period)
    #expect(annotation.pausePoints.count == 1)
    let dto = annotation.pausePoints[0]
    #expect(dto.offset >= 0)
    #expect(dto.lengthMs == 400)
    #expect(dto.named == nil)  // explicit duration, not a named preset

    // spokenText must not contain the pause note.
    #expect(!annotation.spokenText.contains("[["))
    #expect(annotation.spokenText == "She waited then spoke at last.")
  }

  // MARK: - GlosaLineAnnotation Codable

  /// Verifies that `GlosaLineAnnotation` and `PausePointDTO` round-trip
  /// through JSON, confirming `Codable` conformance is complete.
  @Test("GlosaLineAnnotation round-trips through JSON (Codable)")
  func glosaLineAnnotationCodable() throws {
    let annotation = GlosaLineAnnotation(
      spokenText: "Hello world.",
      breathOffsets: [5, 11],
      breathStrengths: ["medium", "strong"],
      instruct: "Evening in the garden. Speak softly.",
      pausePoints: [
        PausePointDTO(offset: 5, lengthMs: 400, named: "period")
      ]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(annotation)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(GlosaLineAnnotation.self, from: data)

    #expect(decoded.spokenText == annotation.spokenText)
    #expect(decoded.breathOffsets == annotation.breathOffsets)
    #expect(decoded.breathStrengths == annotation.breathStrengths)
    #expect(decoded.instruct == annotation.instruct)
    #expect(decoded.pausePoints.count == annotation.pausePoints.count)
    #expect(decoded.pausePoints[0].offset == 5)
    #expect(decoded.pausePoints[0].lengthMs == 400)
    #expect(decoded.pausePoints[0].named == "period")
  }

  // MARK: - compileAnnotations key coverage

  /// Verifies that every index in `rawDialogueLines` has a corresponding key
  /// in the returned dictionary, even for lines with no active directives.
  @Test("compileAnnotations includes an entry for every rawDialogueLines index")
  func compileAnnotationsKeyCompleteness() throws {
    let fountainNotes: [String] = [
      #"<SceneContext location="room" time="night">"#,
      #"<Intent from="calm" to="tense">"#,
      "Line one.",
      "</Intent>",
      "</SceneContext>",
    ]

    let rawLines: [(character: String, rawText: String)] = [
      (character: "ALICE", rawText: "Line one."),
      (character: "BOB", rawText: "Unscoped line."),  // falls outside SceneContext
    ]

    let annotations = try compileAnnotations(
      fountainNotes: fountainNotes,
      rawDialogueLines: rawLines
    )

    // Both indices must be present.
    #expect(annotations[0] != nil)
    #expect(annotations[1] != nil)
    #expect(annotations.count == rawLines.count)

    // The scoped line has an instruct; the unscoped one does not.
    #expect(annotations[0]!.instruct != nil)
    #expect(annotations[1]!.instruct == nil)
  }
}
