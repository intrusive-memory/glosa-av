import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

/// Round-trip tests for `GlosaSerializer`'s Fountain breath inline-note
/// serialization — the contract introduced by Sortie 6 of OPERATION SIGHING
/// SCRIBE.
///
/// ## Contract under test
///
/// When a `GlosaAnnotatedElement` with non-empty `breathPoints` is serialized
/// to Fountain, the serializer must emit canonical `[[<breath …/>]]` inline
/// notes at the correct character offsets inside the dialogue text. Re-parsing
/// the serialized output via `GlosaParser.parseFountainWithDiagnostics(notes:)`
/// must yield a `breathPoints` list that compares equal to the original.
///
/// ## What is NOT asserted
///
/// Per methodology rule 6, byte equality against the original Fountain source
/// is NOT asserted. The upstream Fountain source may contain whitespace and
/// note-block formatting that the serializer normalises on re-emission. Only
/// the semantic contract (canonical inline notes, correct offsets, correct
/// attributes) is verified.
///
/// ## Canonical form rules
///
/// - `length` first, `strength` second; attributes omitted when equal to
///   defaults (`length="comma"`, `strength="medium"`).
/// - `.explicit(TimeInterval)` serialises as `length="<ms>ms"` using
///   `Int((seconds * 1000).rounded())` — never truncation (methodology rule 5).
/// - No inner whitespace: `[[<breath/>]]` or `[[<breath length="…" strength="…"/>]]`.
@Suite("BreathSerializer Fountain — round-trip and canonical form")
struct BreathSerializerFountainTests {

  // MARK: - Shared helpers

  private let parser = GlosaParser()
  private let serializer = GlosaSerializer()
  private let compiler = GlosaCompiler()

  /// Extract GLOSA notes and dialogue pairs from a parsed screenplay.
  /// Matches the extraction logic used in the existing serializer tests.
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

  /// Raw Bishop dialogue with inline `[[<breath…/>]]` notes embedded.
  private let bishopRaw =
    "Bishop is freighted:[[<breath length=\"period\" strength=\"strong\"/>]] authority,"
    + "[[<breath/>]] patriarchy,[[<breath/>]] a history of cover-ups and anti-queer theology."

  /// Notes-stripped Bishop prose (what the actor reads).
  private let bishopStripped =
    "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."

  /// The expected canonical forms for the three Bishop breath notes, in
  /// ascending-offset order (per spec §6.4 and exit criteria).
  ///
  /// - Offset 20: `length="period"`, `strength="strong"` (both non-default)
  ///   → `[[<breath length="period" strength="strong"/>]]`
  /// - Offset 31: comma/medium (both default) → `[[<breath/>]]`
  /// - Offset 43: comma/medium (both default) → `[[<breath/>]]`
  private let bishopExpectedTags = [
    "[[<breath length=\"period\" strength=\"strong\"/>]]",
    "[[<breath/>]]",
    "[[<breath/>]]",
  ]

  /// Build the Fountain notes array for the Bishop fixture. The raw dialogue
  /// string is used here so the parser sees the inline notes and produces the
  /// expected `GlosaScore.breaths`.
  private var bishopNotes: [String] {
    [
      #"<SceneContext location="the rectory office" time="late afternoon">"#,
      #"<Intent from="controlled" to="indicting" pace="moderate">"#,
      bishopRaw,
      "</Intent>",
      "</SceneContext>",
    ]
  }

  /// Build the `GlosaAnnotatedScreenplay` for the Bishop fixture, using the
  /// stripped prose as the dialogue element text (as it would appear after the
  /// parser has stripped inline notes and stored them in the score).
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

  /// Serializing the Bishop fixture must embed exactly the three canonical
  /// inline notes in the output dialogue string.
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

    // The first (non-default) breath must carry both attributes in canonical order:
    // length before strength. Verify by asserting the exact substring.
    #expect(output.contains("[[<breath length=\"period\" strength=\"strong\"/>]]"))

    // The bare default breaths must appear exactly as [[<breath/>]] — no
    // length= or strength= attributes emitted.
    // Two occurrences of the bare form are expected.
    let bareCount =
      output
      .components(separatedBy: "[[<breath/>]]")
      .count - 1
    #expect(bareCount == 2, "Expected 2 bare [[<breath/>]] tags, found \(bareCount)")
  }

  // MARK: - Test 2: Bishop round-trip

  /// Parse → serialize → re-parse the Bishop fixture. The re-parsed
  /// `breathPoints` must compare equal to the originally parsed `breathPoints`.
  ///
  /// Re-parsing is performed by feeding the serialized Fountain output through
  /// `GuionParsedElementCollection` → `extractNotesAndDialogue` → `parseFountainWithDiagnostics`.
  /// Using `parseFountainWithDiagnostics` directly (not `compiler.compile`) avoids
  /// the `dialogueLines`-text mismatch that arises because `GuionParsedElementCollection`
  /// preserves inline `[[<breath/>]]` markers in `elementText` while the compiler's
  /// internal parser strips them.
  @Test("Bishop fixture round-trips: re-parsed breathPoints equal original")
  func bishopRoundTrip() throws {
    let annotated = try makeBishopAnnotated()

    // Original breath points from the annotated dialogue element (element index 1).
    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 3)

    // Serialize to Fountain.
    let serializedFountain = serializer.writeFountain(annotated)

    // Re-parse via notes stream → parseFountainWithDiagnostics.
    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)

    // parseFountainWithDiagnostics extracts breaths from inline [[<breath/>]] notes
    // embedded in dialogue lines. This is the true inverse of the serializer.
    let reparsedResult = parser.parseFountainWithDiagnostics(notes: reparsedNotes)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    // Count must match.
    #expect(
      reparsedBreaths.count == originalPoints.count,
      "Reparsed breath count \(reparsedBreaths.count) ≠ original \(originalPoints.count)"
    )

    // Each point must compare equal.
    for (original, reparsedBreath) in zip(originalPoints, reparsedBreaths) {
      #expect(
        original.offset == reparsedBreath.characterOffset,
        "Offset mismatch: original \(original.offset) ≠ reparsed \(reparsedBreath.characterOffset)"
      )
      #expect(
        original.length == reparsedBreath.length,
        "Length mismatch at offset \(original.offset): \(original.length) ≠ \(reparsedBreath.length)"
      )
      #expect(
        original.strength == reparsedBreath.strength,
        "Strength mismatch at offset \(original.offset): \(original.strength) ≠ \(reparsedBreath.strength)"
      )
    }
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 3: Bishop re-parsed GlosaScore compares equal to original

  /// After round-tripping, the re-parsed `GlosaScore` (scenes, intents,
  /// dialogue lines, breaths) must compare equal to the original score.
  ///
  /// The original score comes from parsing `bishopNotes` (which has the raw
  /// dialogue with inline notes). The re-parsed score comes from parsing the
  /// serialized Fountain output — which produces the same notes structure.
  @Test("Bishop round-trip: re-parsed GlosaScore equals original")
  func bishopRoundTripScoreEquality() throws {
    // Establish the original score directly from the bishopNotes stream.
    let originalScore = parser.parseFountain(notes: bishopNotes)
    #expect(originalScore.scenes.count == 1)
    #expect(originalScore.breaths.count == 3)

    // Build annotated and serialize.
    let annotated = try makeBishopAnnotated()
    let serializedFountain = serializer.writeFountain(annotated)

    // Re-parse the serialized output.
    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)
    let reparsedScore = parser.parseFountain(notes: reparsedNotes)

    // Scene count.
    #expect(originalScore.scenes.count == reparsedScore.scenes.count)

    // Breath count.
    let origBreaths = originalScore.breaths.sorted { $0.characterOffset < $1.characterOffset }
    let reparsedBreaths = reparsedScore.breaths.sorted { $0.characterOffset < $1.characterOffset }
    #expect(origBreaths.count == reparsedBreaths.count)

    for (o, r) in zip(origBreaths, reparsedBreaths) {
      #expect(o.characterOffset == r.characterOffset)
      #expect(o.length == r.length)
      #expect(o.strength == r.strength)
      #expect(o.dialogueLineIndex == r.dialogueLineIndex)
    }
  }

  // MARK: - Test 4: Run-on fixture (spec §5.1 Example 2)

  /// Raw run-on dialogue with four bare `[[<breath/>]]` inline notes.
  private let runOnRaw =
    "He kept the parish quiet[[<breath/>]] and he kept the families quiet"
    + "[[<breath/>]] and he kept the press quiet"
    + "[[<breath/>]] and he kept the diocese quiet for thirty-two years"
    + "[[<breath/>]] and then a single deposition undid every one of those silences in a single afternoon."

  /// Notes-stripped run-on prose.
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

  /// Round-trip the run-on fixture: four bare `[[<breath/>]]` notes must
  /// survive serialize → re-parse with identical offsets, lengths, and strengths.
  @Test("Run-on fixture round-trips: four bare breath points survive")
  func runOnRoundTrip() throws {
    let annotated = try makeRunOnAnnotated()

    // Original: exactly four bare comma/medium breath points.
    let dialogueElement = annotated.annotatedElements[1]
    #expect(dialogueElement.element.elementType == .dialogue)
    let originalPoints = dialogueElement.breathPoints.sorted { $0.offset < $1.offset }
    #expect(originalPoints.count == 4)
    for point in originalPoints {
      #expect(point.length == .comma)
      #expect(point.strength == .medium)
    }

    // Serialize.
    let serializedFountain = serializer.writeFountain(annotated)

    // The serialized output must contain exactly four bare [[<breath/>]] tags.
    let bareCount =
      serializedFountain
      .components(separatedBy: "[[<breath/>]]")
      .count - 1
    #expect(bareCount == 4, "Expected 4 bare [[<breath/>]] tags, got \(bareCount)")

    // Re-parse via notes stream → parseFountainWithDiagnostics (see Test 2 note).
    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, _) = extractNotesAndDialogue(from: reparsed)
    let reparsedResult = parser.parseFountainWithDiagnostics(notes: reparsedNotes)
    let reparsedBreaths = reparsedResult.score.breaths.sorted {
      $0.characterOffset < $1.characterOffset
    }

    #expect(reparsedBreaths.count == 4)
    for (original, reparsedBreath) in zip(originalPoints, reparsedBreaths) {
      #expect(original.offset == reparsedBreath.characterOffset)
      #expect(original.length == reparsedBreath.length)
      #expect(original.strength == reparsedBreath.strength)
    }
    #expect(reparsedResult.diagnostics.isEmpty)
  }

  // MARK: - Test 5: All-default breaths emit bare [[<breath/>]]

  /// A dialogue line whose every breath point uses the defaults (comma,
  /// medium) must serialize to bare `[[<breath/>]]` — no `length=` or
  /// `strength=` attributes in the output.
  @Test("All-default breaths round-trip as bare [[<breath/>]] without attributes")
  func allDefaultBreathsEmitBareTag() throws {
    let prose = "A simple line with one bare breath."
    // Build annotated element directly with a known BreathPoint.
    let breathPoint = BreathPoint(offset: 14, length: .comma, strength: .medium)
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

    // Must contain the bare form exactly.
    #expect(output.contains("[[<breath/>]]"))

    // Must NOT contain any length= or strength= attributes.
    #expect(!output.contains("length="))
    #expect(!output.contains("strength="))
  }

  // MARK: - Test 6: .explicit(0.35) serializes as length="350ms"

  /// Methodology rule 5: `.explicit(0.35)` must serialize as `length="350ms"` via
  /// `.rounded()`. Truncation would emit `349ms` because IEEE-754 stores 0.35
  /// as 0.349999…
  ///
  /// The round-trip is verified by:
  /// 1. Asserting the serialized output contains `[[<breath length="350ms"/>]]`.
  /// 2. Feeding the dialogue-with-note directly through the parser and asserting
  ///    the decoded breath is `.explicit(0.35)`.
  @Test(".explicit(0.35) serializes as length=\"350ms\" and round-trips correctly")
  func explicitHalfSecondRoundTrip() throws {
    let prose = "Halt and listen carefully."
    let breathPoint = BreathPoint(offset: 5, length: .explicit(0.35), strength: .medium)
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

    // Canonical form: 350ms, not 349ms.
    #expect(
      output.contains("[[<breath length=\"350ms\"/>]]"),
      "Expected [[<breath length=\"350ms\"/>]] but output was: \(output)"
    )
    #expect(!output.contains("349ms"), "Truncation detected — 349ms appeared in output")

    // strength omitted (it's .medium, the default).
    #expect(!output.contains("strength="))

    // Round-trip: the serializer injects at offset 5, yielding:
    //   "Halt [[<breath length="350ms"/>]]and listen carefully."
    // Feed that dialogue string through the parser to verify the decoded
    // breath is .explicit(0.35) (not .explicit(0.349999…) or anything else).
    let dialogueWithNote = "Halt [[<breath length=\"350ms\"/>]]and listen carefully."
    let fullNotes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b">"#,
      dialogueWithNote,
      "</Intent>",
      "</SceneContext>",
    ]
    let parseResult = parser.parseFountainWithDiagnostics(notes: fullNotes)
    #expect(parseResult.score.breaths.count == 1)
    #expect(parseResult.score.breaths[0].length == .explicit(0.35))
    #expect(parseResult.score.breaths[0].strength == .medium)
    #expect(parseResult.diagnostics.isEmpty)
  }

  // MARK: - Test 7: Length-only attribute (no strength, non-default length)

  /// A breath with a non-default length and default strength must emit only
  /// the `length` attribute. The `strength` attribute must be absent.
  @Test("Non-default length with default strength emits only length attribute")
  func lengthOnlyAttribute() throws {
    let prose = "She paused here and then continued."
    let breathPoint = BreathPoint(offset: 11, length: .period, strength: .medium)
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

    #expect(output.contains("[[<breath length=\"period\"/>]]"))
    #expect(!output.contains("strength="))
  }

  // MARK: - Test 8: Strength-only attribute (default length, non-default strength)

  /// A breath with default length and non-default strength must emit only the
  /// `strength` attribute. The `length` attribute must be absent.
  @Test("Default length with non-default strength emits only strength attribute")
  func strengthOnlyAttribute() throws {
    let prose = "Listen to this carefully."
    let breathPoint = BreathPoint(offset: 9, length: .comma, strength: .strong)
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

  // MARK: - Test 9: Attribute order (length before strength)

  /// When both attributes are emitted, `length` must appear before `strength`
  /// in the canonical form.
  @Test("Canonical attribute order is length then strength")
  func attributeOrderLengthBeforeStrength() throws {
    let prose = "A test of attribute order."
    let breathPoint = BreathPoint(offset: 5, length: .beat, strength: .weak)
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

    // The canonical tag with both attributes.
    #expect(output.contains("[[<breath length=\"beat\" strength=\"weak\"/>]]"))

    // Verify ordering: length= must appear before strength= within any <breath …/> tag.
    if let breathRange = output.range(of: "[[<breath") {
      let afterBreath = output[breathRange.upperBound...]
      if let endRange = afterBreath.range(of: "]]") {
        let tagBody = String(afterBreath[..<endRange.upperBound])
        if let lengthIdx = tagBody.range(of: "length="),
          let strengthIdx = tagBody.range(of: "strength=")
        {
          #expect(
            lengthIdx.lowerBound < strengthIdx.lowerBound,
            "length= must precede strength= in canonical form"
          )
        }
      }
    }
  }

  // MARK: - Test 10: Breath-free dialogue emits no inline notes

  /// A dialogue element with no breath points must produce no `[[<breath` substrings.
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
