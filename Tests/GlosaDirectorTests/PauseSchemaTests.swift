import Foundation
import GlosaCore
import Testing

@testable import GlosaDirector

/// Tests for the ``PauseAnnotation`` Codable schema and its integration into
/// ``SceneAnnotation`` via the `pauses` field (OPERATION CLEAVING BREATH,
/// Sortie 9).
///
/// Mirrors `BreathSchemaTests`. Covers round-trip encoding of every
/// ``PauseLength`` case and backward-compatible decode (a `pauses` key absent
/// from old JSON decodes to `[]`).
@Suite("Pause Schema Tests")
struct PauseSchemaTests {

  let decoder = JSONDecoder()
  let encoder = JSONEncoder()

  // MARK: - PauseAnnotation round-trip

  @Test("PauseAnnotation: round-trips with length present")
  func pauseAnnotationRoundTripWithLength() throws {
    let original = PauseAnnotation(
      dialogueLineIndex: 0,
      characterOffset: 20,
      length: .period
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(PauseAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.length == .period)
  }

  @Test("PauseAnnotation: round-trips with length nil")
  func pauseAnnotationRoundTripNilLength() throws {
    let original = PauseAnnotation(
      dialogueLineIndex: 1,
      characterOffset: 31,
      length: nil
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(PauseAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.length == nil)
  }

  @Test("PauseAnnotation: round-trips every named PauseLength case")
  func pauseAnnotationRoundTripNamedLengths() throws {
    let lengths: [PauseLength] = [.comma, .semicolon, .period, .emDash, .beat]
    for length in lengths {
      let original = PauseAnnotation(dialogueLineIndex: 0, characterOffset: 5, length: length)
      let data = try encoder.encode(original)
      let decoded = try decoder.decode(PauseAnnotation.self, from: data)
      #expect(decoded.length == length, "Round-trip failed for \(length)")
    }
  }

  @Test("PauseAnnotation: round-trips explicit duration")
  func pauseAnnotationRoundTripExplicit() throws {
    let original = PauseAnnotation(
      dialogueLineIndex: 0, characterOffset: 5, length: .explicit(0.35))
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(PauseAnnotation.self, from: data)
    #expect(decoded.length == .explicit(0.35))
  }

  @Test("PauseAnnotation: dialogueLineIndex and characterOffset are preserved")
  func pauseAnnotationIndicesPreserved() throws {
    let original = PauseAnnotation(
      dialogueLineIndex: 3, characterOffset: 42, length: .beat)
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(PauseAnnotation.self, from: data)
    #expect(decoded.dialogueLineIndex == 3)
    #expect(decoded.characterOffset == 42)
  }

  // MARK: - SceneAnnotation with non-empty pauses

  @Test("SceneAnnotation: round-trips with non-empty pauses array")
  func sceneAnnotationRoundTripWithPauses() throws {
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
      constraints: [],
      pauses: [
        PauseAnnotation(dialogueLineIndex: 0, characterOffset: 20, length: .period)
      ]
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.pauses.count == 1)
    #expect(decoded.pauses[0].characterOffset == 20)
    #expect(decoded.pauses[0].length == .period)
  }

  @Test("SceneAnnotation: pauses and breaths coexist and round-trip independently")
  func sceneAnnotationPausesAndBreathsCoexist() throws {
    let original = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "x", time: "y"),
      intents: [],
      constraints: [],
      breaths: [
        BreathAnnotation(dialogueLineIndex: 0, characterOffset: 31, strength: .medium),
        BreathAnnotation(dialogueLineIndex: 0, characterOffset: 43, strength: .medium),
      ],
      pauses: [
        PauseAnnotation(dialogueLineIndex: 0, characterOffset: 20, length: .period)
      ]
    )
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded == original)
    #expect(decoded.breaths.map(\.characterOffset) == [31, 43])
    #expect(decoded.pauses.map(\.characterOffset) == [20])
  }

  // MARK: - Backward compatibility: missing `pauses` key defaults to []

  @Test("SceneAnnotation: old JSON without 'pauses' key decodes with pauses == []")
  func sceneAnnotationOldJSONDecodesWithEmptyPauses() throws {
    // Verbatim old-format JSON — no "pauses" key at all (and no "breaths" either).
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
    #expect(decoded.pauses == [], "Missing 'pauses' key must decode as empty array")
    #expect(decoded.breaths == [], "Missing 'breaths' key must still decode as empty array")
  }

  @Test("SceneAnnotation: JSON with breaths but no pauses decodes pauses == []")
  func sceneAnnotationBreathsButNoPausesDecodesEmptyPauses() throws {
    let json = """
      {
        "sceneContext": { "location": "x", "time": "y", "ambience": null },
        "intents": [],
        "constraints": [],
        "breaths": [
          { "dialogueLineIndex": 0, "characterOffset": 31, "strength": "medium" }
        ]
      }
      """
    let data = try #require(json.data(using: .utf8))
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)
    #expect(decoded.breaths.count == 1)
    #expect(decoded.pauses == [])
  }

  // MARK: - Bishop pause JSON payload decodes correctly

  @Test("Bishop pauses JSON payload decodes to a single period pause at offset 20")
  func bishopPausesJSONDecodes() throws {
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
        "constraints": [],
        "breaths": [
          { "dialogueLineIndex": 0, "characterOffset": 31, "strength": "medium" },
          { "dialogueLineIndex": 0, "characterOffset": 43, "strength": "medium" }
        ],
        "pauses": [
          { "dialogueLineIndex": 0, "characterOffset": 20, "length": "period" }
        ]
      }
      """
    let data = try #require(bishopJSON.data(using: .utf8))
    let annotation = try decoder.decode(SceneAnnotation.self, from: data)

    #expect(annotation.pauses.count == 1)
    #expect(annotation.pauses[0].dialogueLineIndex == 0)
    #expect(annotation.pauses[0].characterOffset == 20)
    #expect(annotation.pauses[0].length == .period)

    // The two list-comma breaths coexist.
    #expect(annotation.breaths.count == 2)
    #expect(annotation.breaths.map(\.characterOffset) == [31, 43])
  }
}
