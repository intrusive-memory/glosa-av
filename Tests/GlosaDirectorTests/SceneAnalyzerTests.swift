import Foundation
import GlosaCore
import SwiftCompartido
import Testing

@testable import GlosaDirector

@Suite("SceneAnalyzer — Scene Segmentation")
struct SceneAnalyzerTests {

  // MARK: - Helpers

  /// Builds a GuionParsedElementCollection from an array of GuionElements.
  private func makeScreenplay(_ elements: [GuionElement]) -> GuionParsedElementCollection {
    GuionParsedElementCollection(
      filename: "test.fountain",
      elements: elements,
      titlePage: [],
      suppressSceneNumbers: false
    )
  }

  // MARK: - Scene Segmentation

  @Test("Three scene headings produce three segments")
  func threeHeadingsThreeSegments() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .action, elementText: "A cluttered desk."),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Morning."),
      GuionElement(elementType: .sceneHeading, elementText: "EXT. PARK - NIGHT"),
      GuionElement(elementType: .action, elementText: "Moonlight on the grass."),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "It's quiet."),
      GuionElement(elementType: .sceneHeading, elementText: "INT. CAR - CONTINUOUS"),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Drive."),
    ]

    let screenplay = makeScreenplay(elements)
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)

    #expect(segments.count == 3)

    // Each segment starts with its scene heading
    #expect(segments[0].elements.first?.elementType == .sceneHeading)
    #expect(segments[0].headingText == "INT. OFFICE - DAY")

    #expect(segments[1].elements.first?.elementType == .sceneHeading)
    #expect(segments[1].headingText == "EXT. PARK - NIGHT")

    #expect(segments[2].elements.first?.elementType == .sceneHeading)
    #expect(segments[2].headingText == "INT. CAR - CONTINUOUS")
  }

  @Test("Segment element counts are correct")
  func segmentElementCounts() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .action, elementText: "A cluttered desk."),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Morning."),
      GuionElement(elementType: .sceneHeading, elementText: "EXT. PARK - NIGHT"),
      GuionElement(elementType: .action, elementText: "Moonlight on the grass."),
      GuionElement(elementType: .sceneHeading, elementText: "INT. CAR - CONTINUOUS"),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Drive."),
    ]

    let screenplay = makeScreenplay(elements)
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)

    // Scene 1: heading + action + character + dialogue = 4
    #expect(segments[0].elements.count == 4)
    // Scene 2: heading + action = 2
    #expect(segments[1].elements.count == 2)
    // Scene 3: heading + character + dialogue = 3
    #expect(segments[2].elements.count == 3)
  }

  @Test("Elements before first scene heading are discarded")
  func preambleDiscarded() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .action, elementText: "FADE IN:"),
      GuionElement(elementType: .action, elementText: "Title card."),
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .dialogue, elementText: "Hello."),
    ]

    let screenplay = makeScreenplay(elements)
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)

    #expect(segments.count == 1)
    #expect(segments[0].elements.first?.elementType == .sceneHeading)
    #expect(segments[0].headingText == "INT. OFFICE - DAY")
    // Only heading + dialogue = 2 (preamble actions excluded)
    #expect(segments[0].elements.count == 2)
  }

  @Test("Empty screenplay produces no segments")
  func emptyScreenplay() {
    let screenplay = makeScreenplay([])
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)
    #expect(segments.isEmpty)
  }

  @Test("Screenplay with no scene headings produces no segments")
  func noSceneHeadings() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .action, elementText: "Just action."),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "No scene heading?"),
    ]

    let screenplay = makeScreenplay(elements)
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)
    #expect(segments.isEmpty)
  }

  @Test("Single scene heading with no following elements produces one segment")
  func singleHeadingOnly() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. VOID - NIGHT")
    ]

    let screenplay = makeScreenplay(elements)
    let segments = SceneAnalyzer.segmentScenes(from: screenplay)

    #expect(segments.count == 1)
    #expect(segments[0].elements.count == 1)
    #expect(segments[0].headingText == "INT. VOID - NIGHT")
  }
}

// MARK: - VocabularyGlossary Tests

@Suite("VocabularyGlossary — Loading & Override")
struct VocabularyGlossaryTests {

  @Test("Default glossary loads from bundle")
  func loadDefault() throws {
    let glossary = try VocabularyGlossary.loadDefault()

    #expect(glossary.emotions.count > 0)
    #expect(glossary.directions.count > 0)

    // Fixed vocabularies should have exact counts
    #expect(glossary.paceTerms == ["slow", "moderate", "fast", "accelerating", "decelerating"])
    #expect(glossary.registerTerms == ["low", "mid", "high"])
    #expect(glossary.ceilingTerms == ["subdued", "moderate", "intense", "explosive"])
  }

  @Test("Glossary loads from custom file path")
  func loadFromFile() throws {
    let customGlossary = VocabularyGlossary(
      emotions: ["happy", "sad"],
      directions: ["speak softly"],
      paceTerms: ["slow", "fast"],
      registerTerms: ["low", "high"],
      ceilingTerms: ["subdued", "explosive"]
    )

    // Write to a temp file
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("test_glossary_\(UUID().uuidString).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(customGlossary)
    try data.write(to: tempFile)

    defer { try? FileManager.default.removeItem(at: tempFile) }

    // Load from file and verify
    let loaded = try VocabularyGlossary.load(from: tempFile)

    #expect(loaded.emotions == ["happy", "sad"])
    #expect(loaded.directions == ["speak softly"])
    #expect(loaded.paceTerms == ["slow", "fast"])
    #expect(loaded.registerTerms == ["low", "high"])
    #expect(loaded.ceilingTerms == ["subdued", "explosive"])
    #expect(loaded == customGlossary)
  }

  @Test("Glossary override replaces default content")
  func overrideReplacesDefault() throws {
    let defaultGlossary = try VocabularyGlossary.loadDefault()
    let overrideGlossary = VocabularyGlossary(
      emotions: ["custom-emotion"],
      directions: ["custom-direction"],
      paceTerms: ["slow"],
      registerTerms: ["mid"],
      ceilingTerms: ["moderate"]
    )

    // They should differ
    #expect(defaultGlossary != overrideGlossary)
    #expect(overrideGlossary.emotions == ["custom-emotion"])
    #expect(defaultGlossary.emotions.count > 1)
  }
}

// MARK: - SceneAnnotation Tests

@Suite("SceneAnnotation — Codable Round-Trip")
struct SceneAnnotationTests {

  @Test("SceneAnnotation round-trips through JSON")
  func roundTrip() throws {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(
        location: "cramped office",
        time: "late night",
        ambience: "quiet hum of electronics"
      ),
      intents: [
        IntentAnnotation(
          from: "curious",
          to: "frustrated",
          pace: "accelerating",
          spacing: "beat",
          startLine: 0,
          endLine: 2,
          scoped: true
        ),
        IntentAnnotation(
          from: "resigned",
          to: "calm",
          pace: "decelerating",
          startLine: 3,
          endLine: 5,
          scoped: false
        ),
      ],
      constraints: [
        ConstraintAnnotation(
          character: "THE PRACTITIONER",
          direction: "angry but speaking softly on purpose",
          register: "low",
          ceiling: "moderate"
        ),
        ConstraintAnnotation(
          character: "ESPECTRO FAMILIAR",
          direction: "patient, slightly amused"
        ),
      ]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(annotation)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)

    #expect(decoded == annotation)
  }

  @Test("SceneAnnotation with minimal fields round-trips")
  func minimalRoundTrip() throws {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(
        location: "park",
        time: "dawn"
      )
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(annotation)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SceneAnnotation.self, from: data)

    #expect(decoded == annotation)
    #expect(decoded.intents.isEmpty)
    #expect(decoded.constraints.isEmpty)
    #expect(decoded.sceneContext.ambience == nil)
  }
}
