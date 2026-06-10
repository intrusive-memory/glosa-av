import Foundation
import Testing

@testable import GlosaCore

/// Unit tests for the `Pause` data model — `PauseLength`, `Pause`, and the
/// `GlosaScore.pauses` collection.
///
/// `PauseLength` is the duration type that `PauseLength` was promoted from
/// `BreathLength` in Sortie 1 (OPERATION CLEAVING BREATH). It retains every
/// case, every explicit-duration form, and the identical wire encoding. These
/// tests pin the codec so changes to the encoder/decoder surface immediately.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed. `TimeInterval` round-trips rely on `.rounded()` (not
/// truncation) inside the encoder so `.explicit(0.35)` ↔ `"350ms"` survives
/// IEEE-754. See `EXECUTION_PLAN.md` methodology rule 5.
@Suite("Pause / PauseLength data model")
struct PauseTests {

  // MARK: - PauseLength named cases

  @Test(
    "PauseLength named cases round-trip through JSON",
    arguments: [
      PauseLength.comma,
      PauseLength.semicolon,
      PauseLength.period,
      PauseLength.emDash,
      PauseLength.beat,
    ]
  )
  func pauseLengthNamedCaseRoundTrip(_ length: PauseLength) throws {
    let data = try JSONEncoder().encode(length)
    let decoded = try JSONDecoder().decode(PauseLength.self, from: data)
    #expect(decoded == length)
  }

  @Test("PauseLength.comma encodes as \"comma\"")
  func pauseLengthCommaCanonicalForm() throws {
    let data = try JSONEncoder().encode(PauseLength.comma)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"comma\"")
  }

  @Test("PauseLength.semicolon encodes as \"semicolon\"")
  func pauseLengthSemicolonCanonicalForm() throws {
    let data = try JSONEncoder().encode(PauseLength.semicolon)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"semicolon\"")
  }

  @Test("PauseLength.period encodes as \"period\"")
  func pauseLengthPeriodCanonicalForm() throws {
    let data = try JSONEncoder().encode(PauseLength.period)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"period\"")
  }

  @Test("PauseLength.beat encodes as \"beat\"")
  func pauseLengthBeatCanonicalForm() throws {
    let data = try JSONEncoder().encode(PauseLength.beat)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"beat\"")
  }

  @Test("PauseLength em-dash uses kebab-case wire form")
  func pauseLengthEmDashCanonicalForm() throws {
    let data = try JSONEncoder().encode(PauseLength.emDash)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"em-dash\"")
  }

  // MARK: - PauseLength.explicit

  @Test("PauseLength.explicit(0.35) round-trips as canonical \"350ms\"")
  func pauseLengthExplicitRoundTrip() throws {
    let original = PauseLength.explicit(0.35)

    let data = try JSONEncoder().encode(original)
    let encoded = String(data: data, encoding: .utf8)
    // Canonical form is a JSON string literal `"350ms"`. Methodology rule 5
    // requires `.rounded()` here; truncation would emit `"349ms"`.
    #expect(encoded == "\"350ms\"")

    let decoded = try JSONDecoder().decode(PauseLength.self, from: data)
    #expect(decoded == original)
  }

  @Test("PauseLength.explicit accepts \"0.4s\" decimal-seconds wire form")
  func pauseLengthExplicitSecondsDecodes() throws {
    let json = Data("\"0.4s\"".utf8)
    let decoded = try JSONDecoder().decode(PauseLength.self, from: json)
    #expect(decoded == .explicit(0.4))
  }

  @Test("PauseLength.explicit accepts \"1000ms\" integer-milliseconds wire form")
  func pauseLengthExplicitMillisecondsDecodes() throws {
    let json = Data("\"1000ms\"".utf8)
    let decoded = try JSONDecoder().decode(PauseLength.self, from: json)
    #expect(decoded == .explicit(1.0))
  }

  @Test("PauseLength.explicit: \"350ms\" decodes as .explicit(0.35) bit-exactly")
  func pauseLengthExplicit350msDecodes() throws {
    let json = Data("\"350ms\"".utf8)
    let decoded = try JSONDecoder().decode(PauseLength.self, from: json)
    #expect(decoded == .explicit(0.35))
  }

  // MARK: - PauseLength unknown value

  @Test("Unknown PauseLength wire value throws DecodingError")
  func pauseLengthUnknownValueThrows() throws {
    let json = Data("\"banana\"".utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(PauseLength.self, from: json)
    }
  }

  // MARK: - Pause default initialization

  @Test("Default Pause initialization fills length=.period")
  func defaultPauseInitialization() {
    let pause = Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20)

    #expect(pause.sceneIndex == 0)
    #expect(pause.dialogueLineIndex == 0)
    #expect(pause.characterOffset == 20)
    #expect(pause.length == .period)
  }

  @Test("Pause struct round-trips through JSON with non-default length")
  func pauseRoundTrip() throws {
    let original = Pause(
      sceneIndex: 1,
      dialogueLineIndex: 2,
      characterOffset: 42,
      length: .beat
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Pause.self, from: data)

    #expect(decoded == original)
    #expect(decoded.length == .beat)
  }

  // MARK: - GlosaScore with pauses

  @Test("GlosaScore round-trips a pause collection alongside breaths")
  func glosaScoreWithPausesRoundTrip() throws {
    let sceneEntry = GlosaScore.SceneEntry(
      context: SceneContext(location: "the rectory office", time: "late afternoon"),
      intents: []
    )

    let pauses: [Pause] = [
      Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20, length: .period),
      Pause(sceneIndex: 0, dialogueLineIndex: 1, characterOffset: 5, length: .beat),
      Pause(sceneIndex: 0, dialogueLineIndex: 2, characterOffset: 0, length: .explicit(0.35)),
    ]

    let original = GlosaScore(scenes: [sceneEntry], pauses: pauses)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

    #expect(decoded == original)
    #expect(decoded.pauses.count == 3)
    #expect(decoded.pauses[0].length == .period)
    #expect(decoded.pauses[1].length == .beat)
    #expect(decoded.pauses[2].length == .explicit(0.35))
  }

  @Test("Empty GlosaScore defaults pauses to []")
  func emptyGlosaScoreDefaultsPauses() {
    let score = GlosaScore()
    #expect(score.pauses == [])
  }

  @Test("GlosaScore with pauses but no breaths round-trips cleanly")
  func glosaScoreWithPausesOnlyRoundTrip() throws {
    let sceneEntry = GlosaScore.SceneEntry(
      context: SceneContext(location: "stage left", time: "dusk"),
      intents: []
    )
    let pauses: [Pause] = [
      Pause(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 10, length: .comma)
    ]
    let original = GlosaScore(scenes: [sceneEntry], breaths: [], pauses: pauses)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

    #expect(decoded == original)
    #expect(decoded.pauses.count == 1)
    #expect(decoded.breaths.isEmpty)
  }

  @Test("GlosaScore backward-compatible: old JSON without pauses key decodes as []")
  func glosaScoreBackwardCompatibleNoPausesKey() throws {
    // Simulate a JSON payload that pre-dates the `pauses` key — the key is
    // simply absent. `decodeIfPresent` must fall back to `[]` without error.
    let oldStyleJSON = """
      {
        "scenes": [],
        "breaths": []
      }
      """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(GlosaScore.self, from: oldStyleJSON)
    #expect(decoded.pauses == [])
  }
}
