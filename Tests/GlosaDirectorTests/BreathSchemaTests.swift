import Foundation
import GlosaCore
import Testing

@testable import GlosaDirector

/// Tests for the ``BreathAnnotation`` Codable schema and its integration into
/// ``SceneAnnotation`` (Sortie 9 — Stage Director schema extension).
///
/// OPERATION CLEAVING BREATH: `BreathAnnotation` no longer carries `length`
/// (duration moved to ``PauseAnnotation``). Tests updated to reflect
/// strength-only schema.
@Suite("Breath Schema Tests")
struct BreathSchemaTests {

  // MARK: - Helpers

  let decoder = JSONDecoder()
  let encoder = JSONEncoder()

  // MARK: - BreathAnnotation Round-Trip

  @Test("BreathAnnotation: round-trips with strength present")
  func breathAnnotationRoundTripWithStrength() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0,
      characterOffset: 20,
      strength: .strong
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.strength == .strong)
  }

  @Test("BreathAnnotation: round-trips with optional fields nil")
  func breathAnnotationRoundTripNilFields() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 1,
      characterOffset: 31,
      strength: nil
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.strength == nil)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.weak")
  func breathAnnotationRoundTripStrengthWeak() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, strength: .weak)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .weak)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.medium")
  func breathAnnotationRoundTripStrengthMedium() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, strength: .medium)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .medium)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.strong")
  func breathAnnotationRoundTripStrengthStrong() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, strength: .strong)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .strong)
  }

  @Test("BreathAnnotation: dialogueLineIndex and characterOffset are preserved")
  func breathAnnotationIndicesPreserved() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 3, characterOffset: 42, strength: .medium)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.dialogueLineIndex == 3)
    #expect(decoded.characterOffset == 42)
  }

  // MARK: - SceneAnnotation with non-empty breaths

  @Test("SceneAnnotation: round-trips with non-empty breaths array")
  func sceneAnnotationRoundTripWithBreaths() throws {
    let original = SceneAnnotation(
      sceneContext: SceneContextAnnotation(
        location: "rectory office",
        time: "late afternoon",
        ambience: "muted, formal"
      ),
      intents: [
        IntentAnnotation(
          from: "controlled",
          to: "indicting",
          pace: "moderate",
          startLine: 0,
          endLine: 0,
          scoped: true
        )
      ],
      constraints: [
        ConstraintAnnotation(
          character: "THE PRACTITIONER",
          direction: "measured, cataloging"
        )
      ],
      breaths: [
        BreathAnnotation(
          dialogueLineIndex: 0,
          characterOffset: 20,
          strength: .strong
        ),
        BreathAnnotation(
          dialogueLineIndex: 0,
          characterOffset: 31,
          strength: .medium
        ),
        BreathAnnotation(
          dialogueLineIndex: 0,
          characterOffset: 43,
          strength: .medium
        ),
      ]
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.breaths.count == 3)
    let offsets = decoded.breaths.map { $0.characterOffset }
    #expect(offsets == [20, 31, 43])
  }

  // MARK: - Backward compatibility: missing `breaths` key defaults to []

  @Test("SceneAnnotation: old JSON without 'breaths' key decodes with breaths == []")
  func sceneAnnotationOldJSONDecodesWithEmptyBreaths() throws {
    // Verbatim old-format JSON — no "breaths" key at all.
    let oldJSON = """
      {
        "sceneContext": {
          "location": "steam room",
          "time": "morning",
          "ambience": "hissing steam"
        },
        "intents": [
          {
            "from": "calm",
            "to": "tense",
            "pace": "slow",
            "spacing": null,
            "startLine": 0,
            "endLine": 1,
            "scoped": true
          }
        ],
        "constraints": [
          {
            "character": "BERNARD",
            "direction": "nervous amateur",
            "register": null,
            "ceiling": "moderate"
          }
        ]
      }
      """
    let data = try #require(oldJSON.data(using: .utf8))
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded.breaths == [], "Missing 'breaths' key must decode as empty array")
  }

  // MARK: - Bishop JSON payload (verbatim from spec §6.4, length keys now ignored)

  @Test("Bishop JSON payload from spec §6.4 decodes to correct SceneAnnotation")
  func bishopJSONPayloadDecodesCorrectly() throws {
    // JSON payload — "length" keys in breaths are now ignored (moved to PauseAnnotation).
    // Swift's Codable silently ignores unknown keys.
    let bishopJSON = """
      {
        "sceneContext": {
          "location": "the rectory office",
          "time": "late afternoon",
          "ambience": "muted, formal"
        },
        "intents": [
          {
            "from": "controlled",
            "to": "indicting",
            "pace": "moderate",
            "spacing": null,
            "startLine": 0,
            "endLine": 0,
            "scoped": true
          }
        ],
        "constraints": [
          {
            "character": "THE PRACTITIONER",
            "direction": "measured, cataloging — the prosecutor reading a charge sheet",
            "ceiling": "moderate"
          }
        ],
        "breaths": [
          {
            "dialogueLineIndex": 0,
            "characterOffset": 20,
            "strength": "strong"
          },
          {
            "dialogueLineIndex": 0,
            "characterOffset": 31,
            "strength": "medium"
          },
          {
            "dialogueLineIndex": 0,
            "characterOffset": 43,
            "strength": "medium"
          }
        ]
      }
      """
    let data = try #require(bishopJSON.data(using: .utf8))
    let annotation = try decoder.decode(SceneAnnotation.self, from: data)

    // Three breath entries.
    #expect(annotation.breaths.count == 3)

    // Entry 0: offset 20, strong.
    let breath0 = annotation.breaths[0]
    #expect(breath0.dialogueLineIndex == 0)
    #expect(breath0.characterOffset == 20)
    #expect(breath0.strength == .strong)

    // Entry 1: offset 31, medium.
    let breath1 = annotation.breaths[1]
    #expect(breath1.dialogueLineIndex == 0)
    #expect(breath1.characterOffset == 31)
    #expect(breath1.strength == .medium)

    // Entry 2: offset 43, medium.
    let breath2 = annotation.breaths[2]
    #expect(breath2.dialogueLineIndex == 0)
    #expect(breath2.characterOffset == 43)
    #expect(breath2.strength == .medium)

    // Context fields.
    #expect(annotation.sceneContext.location == "the rectory office")
    #expect(annotation.sceneContext.time == "late afternoon")
    #expect(annotation.sceneContext.ambience == "muted, formal")

    // One intent.
    #expect(annotation.intents.count == 1)
    #expect(annotation.intents[0].from == "controlled")
    #expect(annotation.intents[0].to == "indicting")

    // One constraint (note: register is absent in the JSON — decodes to nil).
    #expect(annotation.constraints.count == 1)
    #expect(annotation.constraints[0].character == "THE PRACTITIONER")
    #expect(annotation.constraints[0].register == nil)
  }
}
