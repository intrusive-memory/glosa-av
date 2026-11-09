import Foundation
import Testing

@testable import GlosaCore

/// Tests for the notation 2.0 `foley` block directive in the parser and the
/// validator: `{"foley": {…}}` notes land on `GlosaScore.foleys` in document
/// order, separate from ambiences, and each validation rule has its own
/// diagnostic code.
@Suite("Foley block directive (parser, validator)")
struct FoleyDirectiveTests {

  let parser = GlosaParser()
  let validator = GlosaValidator()

  /// An ambient bed with two spot effects laid over it.
  static let screenplay = """
    INT. TEA HOUSE - NIGHT

    [[ {"ambience": {
      "prompt": "heavy rain on paper screens, distant thunder, quiet room",
      "gain": -6.0
    }} ]]

    KENJI kneels across a low table from the MERCHANT.

    [[ {"foley": {
      "prompt": "heavy wooden door slams shut",
      "seed": 7,
      "take": 3.0
    }} ]]

    KENJI flinches.

    [[ {"foley": {
      "prompt": "ceramic teacup set down on wood",
      "offset": 0.5,
      "gain": -9.0
    }} ]]
    """

  /// Validator diagnostics with `code` for a single foley.
  private func diagnostics(_ foley: Foley, _ code: GlosaDiagnostic.Code) -> [GlosaDiagnostic] {
    validator.validate(score: GlosaScore(foleys: [foley])).filter { $0.code == code }
  }

  // MARK: - Parser

  @Test("Foley notes over an ambience bed parse in order, apart from the ambience")
  func screenplayParsesInOrder() throws {
    let notes = GlosaFountainNotes.standaloneNotes(in: Self.screenplay).map(\.text)
    #expect(notes.count == 3)

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.diagnostics.isEmpty)

    #expect(result.score.ambiences.map(\.documentIndex) == [0])
    let foleys = result.score.foleys
    #expect(foleys.map(\.documentIndex) == [1, 2])
    #expect(foleys[0].prompt == "heavy wooden door slams shut")
    #expect(foleys[0].seed == 7)
    #expect(foleys[0].take == 3)
    #expect(foleys[1].prompt == "ceramic teacup set down on wood")
    #expect(foleys[1].offset == 0.5)
    #expect(foleys[1].gain == -9)

    #expect(validator.validate(score: result.score).isEmpty)
  }

  @Test("A foley note is a known directive, not unknownBlockDirective")
  func foleyIsKnownDirective() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [#"{"foley": {"prompt": "thud"}}"#])
    #expect(result.diagnostics.isEmpty)
    #expect(result.score.foleys.map(\.prompt) == ["thud"])
    #expect(GlosaParser.knownBlockDirectives.contains("foley"))
  }

  @Test("The unknown-directive message lists foley among the expected keys")
  func unknownDirectiveMessageListsFoley() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [#"{"sfx": {"prompt": "p"}}"#])
    let warning = try #require(
      result.diagnostics.first(where: { $0.code == .unknownBlockDirective }))
    #expect(warning.message.contains(#"(expected "shot", "include", "ambience" or "foley")"#))
  }

  @Test("A foley with a wrongly typed key is invalidBlockDirectiveJSON")
  func wrongTypeIsInvalidJSON() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"{"foley": {"prompt": "p", "offset": "late"}}"#
    ])
    #expect(result.score.foleys.isEmpty)
    let error = try #require(result.diagnostics.first)
    #expect(error.code == .invalidBlockDirectiveJSON)
    #expect(error.message.contains("\"offset\""))
  }

  @Test("No notation 1.0 tag form: <foley/> is not read as a directive")
  func noTagForm() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [#"<foley prompt="thud"/>"#])
    #expect(result.score.foleys.isEmpty)
    #expect(!result.diagnostics.contains { $0.code == .deprecatedTagDirective })
  }

  @Test("GlosaScore Codable round-trips foleys; an old encoding decodes to none")
  func scoreCodable() throws {
    let score = GlosaScore(foleys: [
      Foley(documentIndex: 1, prompt: "thud", offset: -0.5),
      Foley(documentIndex: 4, prompt: "clink"),
    ])
    let decoded = try JSONDecoder().decode(
      GlosaScore.self, from: try JSONEncoder().encode(score))
    #expect(decoded == score)

    let old = try JSONDecoder().decode(GlosaScore.self, from: Data(#"{"scenes": []}"#.utf8))
    #expect(old.foleys.isEmpty)
  }

  // MARK: - Diagnostics (one test per code)

  @Test("foleyMissingPrompt: no prompt, or a blank one")
  func missingPrompt() throws {
    let missing = diagnostics(Foley(documentIndex: 0, gain: -3), .foleyMissingPrompt)
    #expect(missing.count == 1)
    #expect(missing.first?.severity == .warning)
    #expect(diagnostics(Foley(documentIndex: 0, prompt: " "), .foleyMissingPrompt).count == 1)
    #expect(diagnostics(Foley(documentIndex: 0, prompt: "thud"), .foleyMissingPrompt).isEmpty)

    // Through the parser: a promptless note is carried, then flagged.
    let parsed = parser.parseFountainWithDiagnostics(notes: [#"{"foley": {"take": 2}}"#])
    #expect(parsed.score.foleys.count == 1)
    #expect(validator.validate(score: parsed.score).contains { $0.code == .foleyMissingPrompt })
  }

  @Test("foleyTakeOutOfRange: take outside 1–120 seconds")
  func takeOutOfRange() throws {
    for take in [0.5, 0, -1, 120.5] {
      let found = diagnostics(
        Foley(documentIndex: 0, prompt: "p", take: take), .foleyTakeOutOfRange)
      #expect(found.count == 1, "take \(take)")
      #expect(found.first?.severity == .warning)
    }
    for take in [1.0, 5, 120] {
      #expect(
        diagnostics(Foley(documentIndex: 0, prompt: "p", take: take), .foleyTakeOutOfRange)
          .isEmpty, "take \(take)")
    }
  }

  @Test("foleyNegativeFade: fadeIn or fadeOut below 0, one per key")
  func negativeFade() throws {
    let all = diagnostics(
      Foley(documentIndex: 0, prompt: "p", fadeIn: -1, fadeOut: -0.5), .foleyNegativeFade)
    #expect(all.count == 2)
    #expect(all.allSatisfy { $0.severity == .warning })
    #expect(all[0].message.contains("fadeIn"))
    #expect(all[1].message.contains("fadeOut"))
    #expect(
      diagnostics(Foley(documentIndex: 0, prompt: "p", fadeIn: 0, fadeOut: 0), .foleyNegativeFade)
        .isEmpty)
  }

  @Test("A negative offset is valid: the effect starts before the note's position")
  func negativeOffsetIsValid() {
    let f = Foley(documentIndex: 0, prompt: "p", offset: -2)
    #expect(validator.validate(score: GlosaScore(foleys: [f])).isEmpty)
  }

  @Test("foleyAmbienceKey: length, crossfade or stop on a foley, one per key")
  func ambienceKeys() throws {
    let parsed = parser.parseFountainWithDiagnostics(notes: [
      #"{"foley": {"prompt": "p", "stop": true, "length": "scene", "crossfade": 1, "x-a": 1}}"#
    ])
    #expect(parsed.diagnostics.isEmpty)
    let found = validator.validate(score: parsed.score).filter { $0.code == .foleyAmbienceKey }
    #expect(found.count == 3)
    #expect(found.allSatisfy { $0.severity == .warning })
    #expect(found[0].message.contains("\"length\""))
    #expect(found[1].message.contains("\"crossfade\""))
    #expect(found[2].message.contains("\"stop\""))
  }
}
