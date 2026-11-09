import Foundation
import Testing

@testable import GlosaCore

/// Tests for the notation 2.0 `ambience` block directive in the parser and the
/// validator (Produciesta REQUIREMENTS-ambience § 2.3): `{"ambience": {…}}`
/// notes land on `GlosaScore.ambiences` in document order, and each
/// validation rule has its own diagnostic code.
@Suite("Ambience block directive (parser, validator)")
struct AmbienceDirectiveTests {

  let parser = GlosaParser()
  let validator = GlosaValidator()

  /// Two scenes, two beds and a stop, interleaved with a shot and screenplay
  /// prose that is not a note.
  static let screenplay = """
    INT. TEA HOUSE - NIGHT

    [[ {"ambience": {
      "prompt": "heavy rain on paper screens, distant thunder, quiet room",
      "seed": 42,
      "gain": -6.0,
      "output": "ambience/episode-03/amb-7c1e09a4.wav"
    }} ]]

    Rain hammers the paper screens. KENJI kneels across a low table.

    [[ {"shot": {"prompt": "Kenji at the low table"}} ]]

    EXT. RIDGE - DAWN

    [[ {"ambience": {
      "prompt": "wind over a ridge, sparse birdsong",
      "length": "continuous",
      "take": 45.0
    }} ]]

    KENJI walks the ridge.

    [[ {"ambience": {
      "stop": true
    }} ]]

    Silence.
    """

  /// Validator diagnostics with `code` for a single ambience.
  private func diagnostics(
    _ ambience: Ambience, _ code: GlosaDiagnostic.Code
  ) -> [GlosaDiagnostic] {
    validator.validate(score: GlosaScore(ambiences: [ambience])).filter { $0.code == code }
  }

  // MARK: - Parser

  @Test("A screenplay with two ambience notes and a stop yields three ambiences in order")
  func screenplayParsesInOrder() throws {
    let notes = GlosaFountainNotes.standaloneNotes(in: Self.screenplay).map(\.text)
    #expect(notes.count == 4)

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.diagnostics.isEmpty)

    let ambiences = result.score.ambiences
    #expect(ambiences.count == 3)
    #expect(ambiences.map(\.documentIndex) == [0, 2, 3])
    #expect(
      ambiences[0].prompt == "heavy rain on paper screens, distant thunder, quiet room")
    #expect(ambiences[0].seed == 42)
    #expect(ambiences[0].gain == -6.0)
    #expect(ambiences[0].output == "ambience/episode-03/amb-7c1e09a4.wav")
    #expect(ambiences[1].prompt == "wind over a ridge, sparse birdsong")
    #expect(ambiences[1].length == .continuous)
    #expect(ambiences[1].take == 45)
    #expect(ambiences[2].stop)
    #expect(ambiences[2].prompt == nil)
    #expect(result.score.shots.count == 1)

    #expect(validator.validate(score: result.score).isEmpty)
  }

  @Test("An ambience note is a known directive, not unknownBlockDirective")
  func ambienceIsKnownDirective() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"{"ambience": {"prompt": "crowded bar"}}"#
    ])
    #expect(!result.diagnostics.contains { $0.code == .unknownBlockDirective })
    #expect(result.diagnostics.isEmpty)
    #expect(result.score.ambiences.map(\.prompt) == ["crowded bar"])
    #expect(GlosaParser.knownBlockDirectives.contains("ambience"))
  }

  @Test("The unknown-directive message lists ambience among the expected keys")
  func unknownDirectiveMessageListsAmbience() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [#"{"bed": {"prompt": "p"}}"#])
    let warning = try #require(
      result.diagnostics.first(where: { $0.code == .unknownBlockDirective }))
    #expect(warning.message.contains(#"(expected "shot", "include", "ambience" or "foley")"#))
  }

  @Test("An ambience with a wrongly typed key is still invalidBlockDirectiveJSON")
  func wrongTypeIsInvalidJSON() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"{"ambience": {"prompt": "p", "take": "30"}}"#
    ])
    #expect(result.score.ambiences.isEmpty)
    let error = try #require(result.diagnostics.first)
    #expect(error.code == .invalidBlockDirectiveJSON)
    #expect(error.message.contains("\"take\""))
  }

  @Test("No notation 1.0 tag form: <ambience/> is not read as a directive")
  func noTagForm() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [#"<ambience prompt="rain"/>"#])
    #expect(result.score.ambiences.isEmpty)
    #expect(!result.diagnostics.contains { $0.code == .deprecatedTagDirective })
  }

  @Test("GlosaScore Codable round-trips ambiences; an old encoding decodes to none")
  func scoreCodable() throws {
    let score = GlosaScore(ambiences: [
      Ambience(documentIndex: 1, prompt: "rain", length: .seconds(30)),
      Ambience(documentIndex: 4, stop: true),
    ])
    let decoded = try JSONDecoder().decode(
      GlosaScore.self, from: try JSONEncoder().encode(score))
    #expect(decoded == score)

    let old = try JSONDecoder().decode(GlosaScore.self, from: Data(#"{"scenes": []}"#.utf8))
    #expect(old.ambiences.isEmpty)
  }

  // MARK: - Diagnostics (one test per code)

  @Test("ambienceMissingPrompt: no prompt and not a stop")
  func missingPrompt() throws {
    let missing = diagnostics(Ambience(documentIndex: 0, gain: -3), .ambienceMissingPrompt)
    #expect(missing.count == 1)
    #expect(missing.first?.severity == .warning)

    #expect(
      diagnostics(Ambience(documentIndex: 0, prompt: "  "), .ambienceMissingPrompt).count == 1)
    #expect(diagnostics(Ambience(documentIndex: 0, prompt: "rain"), .ambienceMissingPrompt).isEmpty)
    #expect(diagnostics(Ambience(documentIndex: 0, stop: true), .ambienceMissingPrompt).isEmpty)

    // Through the parser: a promptless note is carried, then flagged.
    let parsed = parser.parseFountainWithDiagnostics(notes: [#"{"ambience": {"take": 20}}"#])
    #expect(parsed.score.ambiences.count == 1)
    #expect(
      validator.validate(score: parsed.score).contains { $0.code == .ambienceMissingPrompt })
  }

  @Test("ambienceStopWithKeys: stop with any other key, known or unknown")
  func stopWithKeys() throws {
    let withPrompt = diagnostics(
      Ambience(documentIndex: 2, prompt: "rain", stop: true), .ambienceStopWithKeys)
    #expect(withPrompt.count == 1)
    #expect(withPrompt.first?.severity == .warning)
    #expect(withPrompt.first?.message.contains("\"prompt\"") == true)

    let withExtra = Ambience(
      documentIndex: 0, stop: true,
      extraAttributes: [GlosaJSONMember(key: "mood", value: .string("calm"))])
    #expect(diagnostics(withExtra, .ambienceStopWithKeys).count == 1)

    #expect(diagnostics(Ambience(documentIndex: 0, stop: true), .ambienceStopWithKeys).isEmpty)

    // A stop note is not also reported as missing its prompt.
    let all = validator.validate(
      score: GlosaScore(ambiences: [Ambience(documentIndex: 0, gain: 1, stop: true)]))
    #expect(all.map(\.code) == [.ambienceStopWithKeys])
  }

  @Test("ambienceTakeOutOfRange: take outside 1–120 seconds")
  func takeOutOfRange() throws {
    for take in [0.5, 0, -1, 120.5, 121] {
      let found = diagnostics(
        Ambience(documentIndex: 0, prompt: "p", take: take), .ambienceTakeOutOfRange)
      #expect(found.count == 1, "take \(take)")
      #expect(found.first?.severity == .warning)
    }
    for take in [1.0, 30, 120] {
      #expect(
        diagnostics(Ambience(documentIndex: 0, prompt: "p", take: take), .ambienceTakeOutOfRange)
          .isEmpty, "take \(take)")
    }
  }

  @Test("ambienceNegativeFade: fadeIn, fadeOut or crossfade below 0, one per key")
  func negativeFade() throws {
    let all = diagnostics(
      Ambience(documentIndex: 0, prompt: "p", fadeIn: -1, fadeOut: -0.5, crossfade: -2),
      .ambienceNegativeFade)
    #expect(all.count == 3)
    #expect(all.allSatisfy { $0.severity == .warning })
    #expect(all[0].message.contains("fadeIn"))
    #expect(all[1].message.contains("fadeOut"))
    #expect(all[2].message.contains("crossfade"))

    #expect(
      diagnostics(Ambience(documentIndex: 0, prompt: "p", crossfade: -0.1), .ambienceNegativeFade)
        .count == 1)
    #expect(
      diagnostics(
        Ambience(documentIndex: 0, prompt: "p", fadeIn: 0, fadeOut: 0, crossfade: 0),
        .ambienceNegativeFade
      ).isEmpty)
  }

  @Test("ambienceInvalidLength: a numeric length ≤ 0 (validator warning)")
  func invalidLengthNonPositive() throws {
    for seconds in [0.0, -5] {
      let found = diagnostics(
        Ambience(documentIndex: 0, prompt: "p", length: .seconds(seconds)),
        .ambienceInvalidLength)
      #expect(found.count == 1, "length \(seconds)")
      #expect(found.first?.severity == .warning)
    }
    #expect(
      diagnostics(
        Ambience(documentIndex: 0, prompt: "p", length: .seconds(0.5)), .ambienceInvalidLength
      ).isEmpty)
    #expect(
      diagnostics(Ambience(documentIndex: 0, prompt: "p", length: .natural), .ambienceInvalidLength)
        .isEmpty)

    // Through the parser: a zero length parses, then the validator flags it.
    let parsed = parser.parseFountainWithDiagnostics(notes: [
      #"{"ambience": {"prompt": "p", "length": 0}}"#
    ])
    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.score.ambiences.first?.length == .seconds(0))
    #expect(
      validator.validate(score: parsed.score).contains { $0.code == .ambienceInvalidLength })
  }

  @Test("ambienceInvalidLength: an unknown length string (parser error, note ignored)")
  func invalidLengthUnknownString() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"{"ambience": {"prompt": "p", "length": "forever"}}"#,
      #"{"ambience": {"prompt": "q"}}"#,
    ])
    #expect(result.score.ambiences.map(\.prompt) == ["q"])
    #expect(result.diagnostics.count == 1)
    let error = try #require(result.diagnostics.first)
    #expect(error.code == .ambienceInvalidLength)
    #expect(error.severity == .error)
    #expect(error.line == 1)
    #expect(error.message.contains("\"forever\""))

    // Any other wrongly typed length is the generic schema error.
    let typed = parser.parseFountainWithDiagnostics(notes: [
      #"{"ambience": {"prompt": "p", "length": true}}"#
    ])
    #expect(typed.diagnostics.map(\.code) == [.invalidBlockDirectiveJSON])
  }

  @Test("Compile surfaces the parser's ambienceInvalidLength error")
  func compileSurfacesInvalidLength() throws {
    let result = try GlosaCompiler().compile(
      fountainNotes: [#"{"ambience": {"prompt": "p", "length": "always"}}"#],
      dialogueLines: [])
    #expect(result.diagnostics.contains { $0.code == .ambienceInvalidLength })
  }
}
