import Foundation
import Testing

@testable import GlosaCore

/// Unit tests for the `Breath` data model — `BreathLength`, `BreathStrength`,
/// `Breath`, and the `GlosaScore.breaths` collection.
///
/// All tests follow the OPERATION SIGHING SCRIBE methodology: deterministic,
/// hermetic, untimed. `TimeInterval` round-trips rely on `.rounded()` (not
/// truncation) inside the encoder so that `.explicit(0.35)` ↔ `"350ms"`
/// survives IEEE-754. See `EXECUTION_PLAN.md` methodology rule 5.
@Suite("Breath data model")
struct BreathTests {

  // MARK: - Default initialization

  @Test("Default initialization fills length=.comma and strength=.medium")
  func defaultInitialization() {
    let breath = Breath(dialogueLineIndex: 0, characterOffset: 20)

    #expect(breath.dialogueLineIndex == 0)
    #expect(breath.characterOffset == 20)
    #expect(breath.length == .comma)
    #expect(breath.strength == .medium)
  }

  // MARK: - BreathLength codable round-trip

  @Test(
    "BreathLength named cases round-trip through JSON",
    arguments: [
      BreathLength.comma,
      BreathLength.semicolon,
      BreathLength.period,
      BreathLength.emDash,
      BreathLength.beat,
    ]
  )
  func breathLengthNamedCaseRoundTrip(_ length: BreathLength) throws {
    let data = try JSONEncoder().encode(length)
    let decoded = try JSONDecoder().decode(BreathLength.self, from: data)
    #expect(decoded == length)
  }

  @Test("BreathLength.explicit(0.35) round-trips as canonical \"350ms\"")
  func breathLengthExplicitRoundTrip() throws {
    let original = BreathLength.explicit(0.35)

    let data = try JSONEncoder().encode(original)
    let encoded = String(data: data, encoding: .utf8)
    // Canonical form is a JSON string literal `"350ms"`. Methodology rule 5
    // requires `.rounded()` here; truncation would emit `"349ms"`.
    #expect(encoded == "\"350ms\"")

    let decoded = try JSONDecoder().decode(BreathLength.self, from: data)
    #expect(decoded == original)
  }

  @Test("BreathLength.explicit accepts \"0.4s\" decimal-seconds wire form")
  func breathLengthExplicitSecondsDecodes() throws {
    let json = Data("\"0.4s\"".utf8)
    let decoded = try JSONDecoder().decode(BreathLength.self, from: json)
    #expect(decoded == .explicit(0.4))
  }

  @Test("BreathLength em-dash uses kebab-case wire form")
  func breathLengthEmDashCanonicalForm() throws {
    let data = try JSONEncoder().encode(BreathLength.emDash)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"em-dash\"")
  }

  // MARK: - BreathStrength codable round-trip

  @Test(
    "BreathStrength round-trips through JSON",
    arguments: [BreathStrength.weak, BreathStrength.medium, BreathStrength.strong]
  )
  func breathStrengthRoundTrip(_ strength: BreathStrength) throws {
    let data = try JSONEncoder().encode(strength)
    let decoded = try JSONDecoder().decode(BreathStrength.self, from: data)
    #expect(decoded == strength)
  }

  // MARK: - Breath struct round-trip

  @Test("Breath struct round-trips through JSON with non-default attributes")
  func breathRoundTrip() throws {
    let original = Breath(
      dialogueLineIndex: 0,
      characterOffset: 20,
      length: .period,
      strength: .strong
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Breath.self, from: data)

    #expect(decoded == original)
  }

  // MARK: - GlosaScore with breaths

  @Test("GlosaScore round-trips a mixed breath collection")
  func glosaScoreWithMixedBreathsRoundTrip() throws {
    // The Bishop case from breath-tag.md §6.4: three breaths on a single
    // dialogue line, mixing strong/medium strength and period/comma length.
    let bishopBreaths: [Breath] = [
      Breath(
        dialogueLineIndex: 0,
        characterOffset: 20,
        length: .period,
        strength: .strong
      ),
      Breath(dialogueLineIndex: 0, characterOffset: 31),
      Breath(dialogueLineIndex: 0, characterOffset: 43),
    ]
    // Plus an explicit-ms breath drawn from spec §5.1 Example 3.
    let explicitBreath = Breath(
      dialogueLineIndex: 1,
      characterOffset: 200,
      length: .explicit(0.35)
    )

    let sceneEntry = GlosaScore.SceneEntry(
      context: SceneContext(location: "the rectory office", time: "late afternoon"),
      intents: []
    )

    let original = GlosaScore(
      scenes: [sceneEntry],
      breaths: bishopBreaths + [explicitBreath]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

    #expect(decoded == original)
    #expect(decoded.breaths.count == 4)
    #expect(decoded.breaths[0].length == .period)
    #expect(decoded.breaths[0].strength == .strong)
    #expect(decoded.breaths[1].length == .comma)
    #expect(decoded.breaths[1].strength == .medium)
    #expect(decoded.breaths[3].length == .explicit(0.35))
  }

  @Test("Empty GlosaScore defaults breaths to []")
  func emptyGlosaScoreDefaultsBreaths() {
    let score = GlosaScore()
    #expect(score.breaths == [])
  }
}
