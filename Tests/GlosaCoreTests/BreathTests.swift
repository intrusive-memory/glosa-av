import Foundation
import Testing

@testable import GlosaCore

/// Unit tests for the `Breath` data model — `BreathStrength`, `Breath`, and
/// the `GlosaScore.breaths` collection.
///
/// `Breath` is a silent phrasing hint with no duration (`length` was removed
/// in Sortie 1 of OPERATION CLEAVING BREATH; duration now lives on `Pause`).
/// `PauseLength` (formerly `BreathLength`) codec tests live in `PauseTests.swift`.
///
/// All tests follow the OPERATION CLEAVING BREATH methodology: deterministic,
/// hermetic, untimed.
@Suite("Breath data model")
struct BreathTests {

  // MARK: - Default initialization

  @Test("Default initialization fills strength=.medium")
  func defaultInitialization() {
    let breath = Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 20)

    #expect(breath.sceneIndex == 0)
    #expect(breath.dialogueLineIndex == 0)
    #expect(breath.characterOffset == 20)
    #expect(breath.strength == .medium)
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

  @Test("BreathStrength.weak encodes as \"weak\"")
  func breathStrengthWeakCanonical() throws {
    let data = try JSONEncoder().encode(BreathStrength.weak)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"weak\"")
  }

  @Test("BreathStrength.strong encodes as \"strong\"")
  func breathStrengthStrongCanonical() throws {
    let data = try JSONEncoder().encode(BreathStrength.strong)
    let encoded = String(data: data, encoding: .utf8)
    #expect(encoded == "\"strong\"")
  }

  // MARK: - Breath struct round-trip

  @Test("Breath struct round-trips through JSON with non-default strength")
  func breathRoundTrip() throws {
    let original = Breath(
      sceneIndex: 0,
      dialogueLineIndex: 0,
      characterOffset: 20,
      strength: .strong
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Breath.self, from: data)

    #expect(decoded == original)
    #expect(decoded.strength == .strong)
  }

  @Test("Breath struct Equatable: two breaths with same fields are equal")
  func breathEquatable() {
    let a = Breath(sceneIndex: 1, dialogueLineIndex: 2, characterOffset: 42, strength: .weak)
    let b = Breath(sceneIndex: 1, dialogueLineIndex: 2, characterOffset: 42, strength: .weak)
    #expect(a == b)
  }

  @Test("Breath struct Equatable: breaths with different strength are not equal")
  func breathEquatableDifferentStrength() {
    let a = Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 10, strength: .weak)
    let b = Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 10, strength: .strong)
    #expect(a != b)
  }

  // MARK: - GlosaScore with breaths

  @Test("GlosaScore round-trips a mixed breath collection")
  func glosaScoreWithMixedBreathsRoundTrip() throws {
    // The Bishop case: three breaths on a single dialogue line with varying strength.
    let bishopBreaths: [Breath] = [
      Breath(
        sceneIndex: 0,
        dialogueLineIndex: 0,
        characterOffset: 20,
        strength: .strong
      ),
      Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 31),
      Breath(sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 43),
    ]
    let extraBreath = Breath(
      sceneIndex: 0,
      dialogueLineIndex: 1,
      characterOffset: 200
    )

    let sceneEntry = GlosaScore.SceneEntry(
      context: SceneContext(location: "the rectory office", time: "late afternoon"),
      intents: []
    )

    let original = GlosaScore(
      scenes: [sceneEntry],
      breaths: bishopBreaths + [extraBreath]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

    #expect(decoded == original)
    #expect(decoded.breaths.count == 4)
    #expect(decoded.breaths[0].strength == .strong)
    #expect(decoded.breaths[1].strength == .medium)
    #expect(decoded.breaths[2].strength == .medium)
    #expect(decoded.breaths[3].strength == .medium)
  }

  @Test("Empty GlosaScore defaults breaths to []")
  func emptyGlosaScoreDefaultsBreaths() {
    let score = GlosaScore()
    #expect(score.breaths == [])
  }
}
