import Foundation
import GlosaCore
import Testing

@testable import GlosaDirector

/// Tests for the ``BreathAnnotation`` Codable schema and its integration into
/// ``SceneAnnotation`` (Sortie 9 — Stage Director schema extension).
@Suite("Breath Schema Tests")
struct BreathSchemaTests {

  // MARK: - Helpers

  let decoder = JSONDecoder()
  let encoder = JSONEncoder()

  // MARK: - BreathAnnotation Round-Trip

  @Test("BreathAnnotation: round-trips with all fields present")
  func breathAnnotationRoundTripAllFields() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0,
      characterOffset: 20,
      length: .period,
      strength: .strong
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded == original)
  }

  @Test("BreathAnnotation: round-trips with optional fields nil")
  func breathAnnotationRoundTripNilFields() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 1,
      characterOffset: 31,
      length: nil,
      strength: nil
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.length == nil)
    #expect(decoded.strength == nil)
  }

  @Test("BreathAnnotation: round-trips BreathLength.comma via string 'comma'")
  func breathAnnotationRoundTripLengthComma() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 10, length: .comma, strength: nil)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.length == .comma)
  }

  @Test("BreathAnnotation: round-trips BreathLength.semicolon")
  func breathAnnotationRoundTripLengthSemicolon() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 15, length: .semicolon, strength: nil)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.length == .semicolon)
  }

  @Test("BreathAnnotation: round-trips BreathLength.period")
  func breathAnnotationRoundTripLengthPeriod() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 20, length: .period, strength: nil)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.length == .period)
  }

  @Test("BreathAnnotation: round-trips BreathLength.emDash via 'em-dash' wire token")
  func breathAnnotationRoundTripLengthEmDash() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 25, length: .emDash, strength: nil)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.length == .emDash)
  }

  @Test("BreathAnnotation: round-trips BreathLength.beat")
  func breathAnnotationRoundTripLengthBeat() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 30, length: .beat, strength: nil)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.length == .beat)
  }

  @Test("BreathAnnotation: round-trips BreathLength.explicit(0.35) as '350ms'")
  func breathAnnotationRoundTripLengthExplicit() throws {
    // 0.35 is stored in IEEE-754 as 0.349999…; .rounded() must be used to
    // produce 350ms, not 349ms. This test would catch a truncation regression.
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 35, length: .explicit(0.35), strength: nil)
    let data = try encoder.encode(original)
    // Verify the wire form is "350ms" (not "349ms").
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("350ms"), "Expected wire form '350ms', got: \(json)")
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded == original)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.weak")
  func breathAnnotationRoundTripStrengthWeak() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, length: nil, strength: .weak)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .weak)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.medium")
  func breathAnnotationRoundTripStrengthMedium() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, length: nil, strength: .medium)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .medium)
  }

  @Test("BreathAnnotation: round-trips BreathStrength.strong")
  func breathAnnotationRoundTripStrengthStrong() throws {
    let original = BreathAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, length: nil, strength: .strong)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BreathAnnotation.self, from: data)
    #expect(decoded.strength == .strong)
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
          length: .period,
          strength: .strong
        ),
        BreathAnnotation(
          dialogueLineIndex: 0,
          characterOffset: 31,
          length: .comma,
          strength: .medium
        ),
        BreathAnnotation(
          dialogueLineIndex: 0,
          characterOffset: 43,
          length: .comma,
          strength: .medium
        ),
      ]
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.breaths.count == 3)
    let offsets = decoded.breaths.map(\.characterOffset)
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

  // MARK: - Bishop JSON payload (verbatim from spec §6.4)

  @Test("Bishop JSON payload from spec §6.4 decodes to correct SceneAnnotation")
  func bishopJSONPayloadDecodesCorrectly() throws {
    // Verbatim JSON payload from breath-tag.md §6.4.
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
            "length": "period",
            "strength": "strong"
          },
          {
            "dialogueLineIndex": 0,
            "characterOffset": 31,
            "length": "comma",
            "strength": "medium"
          },
          {
            "dialogueLineIndex": 0,
            "characterOffset": 43,
            "length": "comma",
            "strength": "medium"
          }
        ]
      }
      """
    let data = try #require(bishopJSON.data(using: .utf8))
    let annotation = try decoder.decode(SceneAnnotation.self, from: data)

    // Three breath entries.
    #expect(annotation.breaths.count == 3)

    // Entry 0: offset 20, period/strong.
    let breath0 = annotation.breaths[0]
    #expect(breath0.dialogueLineIndex == 0)
    #expect(breath0.characterOffset == 20)
    #expect(breath0.length == .period)
    #expect(breath0.strength == .strong)

    // Entry 1: offset 31, comma/medium.
    let breath1 = annotation.breaths[1]
    #expect(breath1.dialogueLineIndex == 0)
    #expect(breath1.characterOffset == 31)
    #expect(breath1.length == .comma)
    #expect(breath1.strength == .medium)

    // Entry 2: offset 43, comma/medium.
    let breath2 = annotation.breaths[2]
    #expect(breath2.dialogueLineIndex == 0)
    #expect(breath2.characterOffset == 43)
    #expect(breath2.length == .comma)
    #expect(breath2.strength == .medium)

    // Context fields.
    #expect(annotation.sceneContext.location == "the rectory office")
    #expect(annotation.sceneContext.time == "late afternoon")
    #expect(annotation.sceneContext.ambience == "muted, formal")

    // One intent.
    #expect(annotation.intents.count == 1)
    #expect(annotation.intents[0].from == "controlled")
    #expect(annotation.intents[0].to == "indicting")

    // One constraint (note: register is absent in the §6.4 JSON — decodes to nil).
    #expect(annotation.constraints.count == 1)
    #expect(annotation.constraints[0].character == "THE PRACTITIONER")
    #expect(annotation.constraints[0].register == nil)
  }
}
