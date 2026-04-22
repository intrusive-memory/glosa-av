import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

@testable import GlosaDirector

// MARK: - Mock Annotation Provider

/// A mock ``SceneAnnotationProvider`` that returns predetermined annotations.
///
/// Used for deterministic testing without a real LLM.
struct MockAnnotationProvider: SceneAnnotationProvider {
  /// The annotation to return for each scene, in order.
  let annotations: [SceneAnnotation]

  /// Tracks which scene index we are on.
  private let callCounter = CallCounter()

  init(annotations: [SceneAnnotation]) {
    self.annotations = annotations
  }

  /// Convenience init for a single scene.
  init(annotation: SceneAnnotation) {
    self.annotations = [annotation]
  }

  func annotateScene(
    sceneText: String,
    dialogueLineCount: Int,
    systemPrompt: String,
    model: String
  ) async throws -> SceneAnnotation {
    let index = callCounter.next()
    guard index < annotations.count else {
      return annotations.last!
    }
    return annotations[index]
  }
}

/// Thread-safe call counter for the mock provider.
private final class CallCounter: @unchecked Sendable {
  private var count = 0
  private let lock = NSLock()

  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    let current = count
    count += 1
    return current
  }
}

// MARK: - Test Helpers

/// Build a `GuionParsedElementCollection` from an array of elements.
private func makeScreenplay(_ elements: [GuionElement]) -> GuionParsedElementCollection {
  GuionParsedElementCollection(
    filename: "test.fountain",
    elements: elements,
    titlePage: [],
    suppressSceneNumbers: false
  )
}

/// Build a simple scene with a heading, characters, and dialogue.
private func makeSteamRoomScene() -> [GuionElement] {
  [
    GuionElement(elementType: .sceneHeading, elementText: "INT. STEAM ROOM - DAY"),
    GuionElement(elementType: .action, elementText: "BERNARD and KILLIAN sit in a steam room."),
    GuionElement(elementType: .character, elementText: "BERNARD"),
    GuionElement(
      elementType: .dialogue, elementText: "Have you thought about how I'm going to do it?"),
    GuionElement(elementType: .character, elementText: "KILLIAN"),
    GuionElement(elementType: .dialogue, elementText: "I can't think about anything else."),
    GuionElement(elementType: .character, elementText: "BERNARD"),
    GuionElement(elementType: .dialogue, elementText: "And?"),
  ]
}

/// A SceneAnnotation matching the steam room scene above.
private func makeSteamRoomAnnotation() -> SceneAnnotation {
  SceneAnnotation(
    sceneContext: SceneContextAnnotation(
      location: "steam room",
      time: "morning",
      ambience: "hissing steam, echoing tile"
    ),
    intents: [
      IntentAnnotation(
        from: "conspiratorial calm",
        to: "grim resolve",
        pace: "slow",
        startLine: 0,
        endLine: 2,
        scoped: true
      )
    ],
    constraints: [
      ConstraintAnnotation(
        character: "BERNARD",
        direction: "nervous amateur, out of his depth, trying to sound casual",
        ceiling: "moderate"
      ),
      ConstraintAnnotation(
        character: "KILLIAN",
        direction: "clinical detachment, this is business, calm and methodical",
        ceiling: "subdued"
      ),
    ]
  )
}

// MARK: - StageDirector Tests

@Suite("StageDirector — LLM Integration")
struct StageDirectorAnnotateTests {

  @Test("annotate produces instruct for every dialogue line")
  func everyDialogueLineHasInstruct() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    // Check that every dialogue element has a non-nil instruct
    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }

    #expect(dialogueAnnotations.count == 3, "Should have 3 dialogue elements")

    for (index, annotated) in dialogueAnnotations.enumerated() {
      #expect(
        annotated.instruct != nil,
        "Dialogue line \(index) should have a non-nil instruct, got nil"
      )
    }
  }

  @Test("annotate preserves non-dialogue elements without instruct")
  func nonDialogueElementsHaveNilInstruct() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    let nonDialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType != .dialogue
    }

    for annotated in nonDialogueAnnotations {
      #expect(
        annotated.instruct == nil,
        "Non-dialogue element '\(annotated.element.elementType)' should have nil instruct"
      )
    }
  }

  @Test("annotate produces correct element count")
  func elementCountMatchesScreenplay() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    #expect(
      result.annotatedElements.count == elements.count,
      "Annotated elements count should match original elements count"
    )
  }

  @Test("instruct strings contain scene context, intent, and constraint terms")
  func instructContainsExpectedTerms() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }

    // BERNARD's first line (dialogue index 0)
    let bernardFirst = dialogueAnnotations[0]
    let instruct0 = try #require(bernardFirst.instruct)

    // Should contain scene context
    #expect(instruct0.contains("steam room"), "Instruct should contain location")
    #expect(instruct0.contains("orning"), "Instruct should contain time (Morning)")

    // Should contain intent terms
    #expect(
      instruct0.lowercased().contains("conspiratorial calm")
        || instruct0.lowercased().contains("grim resolve"),
      "Instruct should contain intent emotional terms"
    )

    // Should contain BERNARD's constraint
    #expect(
      instruct0.contains("nervous amateur")
        || instruct0.contains("out of his depth"),
      "Instruct should contain BERNARD's constraint direction"
    )

    // KILLIAN's line (dialogue index 1) should have KILLIAN's constraint
    let killianLine = dialogueAnnotations[1]
    let instruct1 = try #require(killianLine.instruct)

    #expect(
      instruct1.contains("clinical detachment")
        || instruct1.contains("calm and methodical"),
      "KILLIAN's instruct should contain KILLIAN's constraint direction"
    )
    #expect(
      instruct1.contains("subdued"),
      "KILLIAN's instruct should contain ceiling: subdued"
    )
  }

  @Test("annotate with neutral gap between intents")
  func neutralGapBetweenIntents() async throws {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "First line."),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "Second line."),
      // Neutral gap — line indices 2,3 not covered by any intent
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Third line."),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "Fourth line."),
    ]

    let screenplay = makeScreenplay(elements)

    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(
        location: "office",
        time: "afternoon"
      ),
      intents: [
        IntentAnnotation(
          from: "calm",
          to: "tense",
          pace: "moderate",
          startLine: 0,
          endLine: 1,
          scoped: true
        )
        // Lines 2 and 3 are in a neutral gap — no intent covers them
      ],
      constraints: [
        ConstraintAnnotation(
          character: "ALICE",
          direction: "focused and precise",
          ceiling: "moderate"
        )
      ]
    )

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }

    // Lines 0 and 1 should have intent-based instruct
    #expect(
      dialogueAnnotations[0].instruct != nil, "Line 0 should have instruct (covered by intent)")
    #expect(
      dialogueAnnotations[1].instruct != nil, "Line 1 should have instruct (covered by intent)")

    // Lines 2 and 3: ALICE has a constraint so should get instruct from constraint alone;
    // BOB has no constraint, so will get scene context only instruct.
    // Both should get instruct because SceneContext is still active.
    #expect(
      dialogueAnnotations[2].instruct != nil,
      "Line 2 (ALICE): should have instruct from scene context + constraint even in neutral gap"
    )
    #expect(
      dialogueAnnotations[3].instruct != nil,
      "Line 3 (BOB): should have instruct from scene context even in neutral gap"
    )

    // Lines in the neutral gap should NOT have intent terms
    if let instruct2 = dialogueAnnotations[2].instruct {
      // Should have scene context but no intent
      #expect(instruct2.contains("office"), "Neutral gap line should still have scene context")
    }
  }
}

// MARK: - Element Mapping Tests

@Suite("StageDirector — Element Mapping")
struct StageDirectorMappingTests {

  @Test("line range [0,2] maps to elements at correct positions")
  func lineRangeMapsToCorrectElements() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }

    // The intent covers lines [0,2] — all 3 dialogue lines
    // Line 0 (BERNARD): arc position = 0/2 = 0.0
    // Line 1 (KILLIAN): arc position = 1/2 = 0.5
    // Line 2 (BERNARD): arc position = 2/2 = 1.0

    let line0 = dialogueAnnotations[0]
    let line1 = dialogueAnnotations[1]
    let line2 = dialogueAnnotations[2]

    #expect(
      line0.directives?.intent?.arcPosition == 0.0,
      "First dialogue line should have arc position 0.0")
    #expect(
      line1.directives?.intent?.arcPosition == 0.5,
      "Second dialogue line should have arc position 0.5")
    #expect(
      line2.directives?.intent?.arcPosition == 1.0,
      "Third dialogue line should have arc position 1.0")
  }

  @Test("dialogue lines map to correct character names in provenance")
  func provenanceHasCorrectCharacterNames() async throws {
    let elements = makeSteamRoomScene()
    let screenplay = makeScreenplay(elements)
    let annotation = makeSteamRoomAnnotation()

    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    #expect(result.provenance.count == 3, "Should have 3 provenance records")
    #expect(result.provenance[0].characterName == "BERNARD")
    #expect(result.provenance[1].characterName == "KILLIAN")
    #expect(result.provenance[2].characterName == "BERNARD")
  }

  @Test("multi-scene screenplay annotates each scene independently")
  func multiSceneAnnotation() async throws {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Morning."),
      GuionElement(elementType: .sceneHeading, elementText: "EXT. PARK - NIGHT"),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "Evening."),
    ]

    let screenplay = makeScreenplay(elements)

    let scene1Annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "office", time: "morning"),
      intents: [
        IntentAnnotation(from: "calm", to: "alert", startLine: 0, endLine: 0, scoped: true)
      ],
      constraints: [
        ConstraintAnnotation(character: "ALICE", direction: "professional tone")
      ]
    )

    let scene2Annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "park", time: "night"),
      intents: [
        IntentAnnotation(from: "relaxed", to: "wistful", startLine: 0, endLine: 0, scoped: true)
      ],
      constraints: [
        ConstraintAnnotation(character: "BOB", direction: "thoughtful and quiet")
      ]
    )

    let provider = MockAnnotationProvider(annotations: [scene1Annotation, scene2Annotation])
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }

    #expect(dialogueAnnotations.count == 2)

    // Scene 1 instruct should reference office
    let instruct0 = try #require(dialogueAnnotations[0].instruct)
    #expect(instruct0.contains("office"), "Scene 1 instruct should reference office")

    // Scene 2 instruct should reference park
    let instruct1 = try #require(dialogueAnnotations[1].instruct)
    #expect(instruct1.contains("park"), "Scene 2 instruct should reference park")
  }
}

// MARK: - Post-LLM Validation Tests

@Suite("StageDirector — Post-LLM Validation")
struct StageDirectorValidationTests {

  @Test("clamps out-of-range line indices")
  func clampsOutOfRangeIndices() {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "room", time: "night"),
      intents: [
        IntentAnnotation(
          from: "calm",
          to: "angry",
          startLine: -1,
          endLine: 10,
          scoped: true
        )
      ]
    )

    let (corrected, diagnostics) = StageDirector.validateAndCorrect(annotation, dialogueCount: 5)

    #expect(corrected.intents[0].startLine == 0, "startLine should be clamped to 0")
    #expect(corrected.intents[0].endLine == 4, "endLine should be clamped to dialogueCount-1")

    let clampDiagnostic = diagnostics.first {
      $0.message.contains("clamped")
    }
    #expect(clampDiagnostic != nil, "Should produce a clamping diagnostic")
  }

  @Test("removes overlapping intents with diagnostic")
  func removesOverlappingIntents() {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "room", time: "night"),
      intents: [
        IntentAnnotation(
          from: "calm",
          to: "angry",
          startLine: 0,
          endLine: 3,
          scoped: true
        ),
        IntentAnnotation(
          from: "sad",
          to: "happy",
          startLine: 2,
          endLine: 5,
          scoped: true
        ),
      ]
    )

    let (corrected, diagnostics) = StageDirector.validateAndCorrect(annotation, dialogueCount: 6)

    #expect(corrected.intents.count == 1, "Overlapping intent should be removed")
    #expect(corrected.intents[0].from == "calm", "First intent should survive")

    let overlapDiagnostic = diagnostics.first {
      $0.message.contains("overlaps")
    }
    #expect(overlapDiagnostic != nil, "Should produce an overlap diagnostic")
  }

  @Test("reports empty required fields")
  func reportsEmptyRequiredFields() {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "", time: ""),
      intents: [
        IntentAnnotation(from: "", to: "", startLine: 0, endLine: 0, scoped: true)
      ],
      constraints: [
        ConstraintAnnotation(character: "", direction: "")
      ]
    )

    let (_, diagnostics) = StageDirector.validateAndCorrect(annotation, dialogueCount: 1)

    let messages = diagnostics.map(\.message)

    #expect(messages.contains { $0.contains("empty SceneContext location") })
    #expect(messages.contains { $0.contains("empty SceneContext time") })
    #expect(messages.contains { $0.contains("empty 'from'") })
    #expect(messages.contains { $0.contains("empty 'to'") })
    #expect(messages.contains { $0.contains("empty 'character'") })
    #expect(messages.contains { $0.contains("empty 'direction'") })
  }

  @Test("validation does not crash on empty intents array")
  func emptyIntentsDoesNotCrash() {
    let annotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "room", time: "night"),
      intents: [],
      constraints: []
    )

    let (corrected, diagnostics) = StageDirector.validateAndCorrect(annotation, dialogueCount: 3)

    #expect(corrected.intents.isEmpty)
    // Only potential diagnostics are for valid scenes — none expected
    #expect(diagnostics.isEmpty, "No diagnostics expected for valid empty intents")
  }

  @Test("post-LLM validation catches malformed annotations end-to-end")
  func malformedAnnotationEndToEnd() async throws {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. ROOM - NIGHT"),
      GuionElement(elementType: .character, elementText: "ALICE"),
      GuionElement(elementType: .dialogue, elementText: "Hello."),
      GuionElement(elementType: .character, elementText: "BOB"),
      GuionElement(elementType: .dialogue, elementText: "Hi."),
    ]
    let screenplay = makeScreenplay(elements)

    // Malformed: overlapping intents (simulates nested intents)
    let malformedAnnotation = SceneAnnotation(
      sceneContext: SceneContextAnnotation(location: "room", time: "night"),
      intents: [
        IntentAnnotation(from: "calm", to: "angry", startLine: 0, endLine: 1, scoped: true),
        IntentAnnotation(from: "sad", to: "happy", startLine: 0, endLine: 1, scoped: true),
      ],
      constraints: [
        ConstraintAnnotation(
          character: "ALICE", direction: "quiet and reserved", ceiling: "subdued")
      ]
    )

    let provider = MockAnnotationProvider(annotation: malformedAnnotation)
    let director = StageDirector(provider: provider, modelChecker: SkipModelCheck())

    let result = try await director.annotate(screenplay, model: "mock-model")

    // Should not crash
    #expect(result.annotatedElements.count == elements.count)

    // Should have diagnostics about the overlap
    let overlapDiagnostics = result.diagnostics.filter {
      $0.message.contains("overlaps")
    }
    #expect(!overlapDiagnostics.isEmpty, "Should report overlap diagnostic")

    // Despite the malformation, dialogue lines should still get instructs
    // because the first intent survives and covers both lines
    let dialogueAnnotations = result.annotatedElements.filter {
      $0.element.elementType == .dialogue
    }
    for annotated in dialogueAnnotations {
      #expect(annotated.instruct != nil, "Dialogue should have instruct after correction")
    }
  }
}

// MARK: - Prompt Tests

@Suite("Prompts — System Prompt & Few-Shot")
struct PromptsTests {

  @Test("system prompt contains GLOSA element definitions")
  func systemPromptContainsGlosaSpec() {
    let prompt = Prompts.systemPrompt()

    #expect(prompt.contains("SceneContext"), "System prompt should mention SceneContext")
    #expect(prompt.contains("Intent"), "System prompt should mention Intent")
    #expect(prompt.contains("Constraint"), "System prompt should mention Constraint")
    #expect(prompt.contains("location"), "System prompt should mention location attribute")
    #expect(prompt.contains("from"), "System prompt should mention from attribute")
    #expect(prompt.contains("direction"), "System prompt should mention direction attribute")
  }

  @Test("system prompt contains scope rules")
  func systemPromptContainsScopeRules() {
    let prompt = Prompts.systemPrompt()

    #expect(prompt.contains("Scope Rules"), "System prompt should contain scope rules section")
    #expect(
      prompt.contains("do NOT nest"), "System prompt should mention Intent nesting prohibition")
  }

  @Test("system prompt with glossary contains emotion terms")
  func systemPromptWithGlossary() throws {
    let glossary = try VocabularyGlossary.loadDefault()
    let prompt = Prompts.systemPrompt(glossary: glossary)

    // Should contain at least one emotion from the glossary
    #expect(prompt.contains("calm"), "Prompt should contain glossary emotion 'calm'")
    #expect(prompt.contains("frustrated"), "Prompt should contain glossary emotion 'frustrated'")
    #expect(
      prompt.contains("Preferred Vocabulary"), "Prompt should contain vocabulary section header")
    #expect(prompt.contains("Emotion Terms"), "Prompt should contain emotion terms header")
    #expect(prompt.contains("Direction Phrases"), "Prompt should contain direction phrases header")
    #expect(prompt.contains("Pace Terms"), "Prompt should contain pace terms")
    #expect(prompt.contains("Register Terms"), "Prompt should contain register terms")
    #expect(prompt.contains("Ceiling Terms"), "Prompt should contain ceiling terms")
  }

  @Test("system prompt without glossary omits vocabulary section")
  func systemPromptWithoutGlossary() {
    let prompt = Prompts.systemPrompt(glossary: nil)

    #expect(
      !prompt.contains("Preferred Vocabulary"),
      "Prompt without glossary should not contain vocabulary section")
  }

  @Test("few-shot examples contain example scenes and JSON")
  func fewShotExamplesStructure() {
    let examples = Prompts.fewShotExamples()

    #expect(examples.contains("STEAM ROOM"), "Should contain steam room example")
    #expect(examples.contains("BERNARD"), "Should contain character names")
    #expect(examples.contains("sceneContext"), "Should contain JSON field names")
    #expect(examples.contains("intents"), "Should contain intents in JSON")
    #expect(examples.contains("constraints"), "Should contain constraints in JSON")
    #expect(examples.contains("startLine"), "Should contain startLine field")
    #expect(examples.contains("endLine"), "Should contain endLine field")
  }

  @Test("user prompt includes scene text and dialogue count")
  func userPromptStructure() {
    let sceneText = "INT. OFFICE - DAY\n\nALICE\nHello.\n"
    let prompt = Prompts.userPrompt(sceneText: sceneText, dialogueLineCount: 1)

    #expect(prompt.contains("INT. OFFICE - DAY"), "User prompt should include scene text")
    #expect(prompt.contains("1 dialogue lines"), "User prompt should include dialogue count")
    #expect(prompt.contains("indices 0 to 0"), "User prompt should include index range")
  }
}

// MARK: - Scene Text Building Tests

@Suite("StageDirector — Scene Text Building")
struct SceneTextBuildingTests {

  @Test("buildSceneText produces readable output")
  func buildSceneTextReadable() {
    let elements = makeSteamRoomScene()
    let text = StageDirector.buildSceneText(from: elements)

    #expect(text.contains("INT. STEAM ROOM - DAY"))
    #expect(text.contains("BERNARD"))
    #expect(text.contains("Have you thought about how I'm going to do it?"))
    #expect(text.contains("KILLIAN"))
  }

  @Test("extractDialogueInfo returns correct count and characters")
  func extractDialogueInfo() {
    let elements = makeSteamRoomScene()
    let info = StageDirector.extractDialogueInfo(from: elements)

    #expect(info.count == 3)
    #expect(info[0].character == "BERNARD")
    #expect(info[0].text == "Have you thought about how I'm going to do it?")
    #expect(info[1].character == "KILLIAN")
    #expect(info[1].text == "I can't think about anything else.")
    #expect(info[2].character == "BERNARD")
    #expect(info[2].text == "And?")
  }
}

// MARK: - Intent Lookup Tests

@Suite("StageDirector — Intent Lookup")
struct IntentLookupTests {

  @Test("buildIntentLookup maps line indices to correct arc positions")
  func intentLookupArcPositions() {
    let intents = [
      IntentAnnotation(
        from: "calm",
        to: "angry",
        startLine: 0,
        endLine: 2,
        scoped: true
      )
    ]

    let lookup = StageDirector.buildIntentLookup(intents: intents, dialogueCount: 3)

    #expect(lookup[0]?.arcPosition == 0.0, "Line 0 should be at arc position 0.0")
    #expect(lookup[1]?.arcPosition == 0.5, "Line 1 should be at arc position 0.5")
    #expect(lookup[2]?.arcPosition == 1.0, "Line 2 should be at arc position 1.0")
  }

  @Test("buildIntentLookup handles multiple non-overlapping intents")
  func multipleIntentsLookup() {
    let intents = [
      IntentAnnotation(
        from: "calm",
        to: "angry",
        startLine: 0,
        endLine: 1,
        scoped: true
      ),
      IntentAnnotation(
        from: "sad",
        to: "happy",
        startLine: 3,
        endLine: 4,
        scoped: true
      ),
    ]

    let lookup = StageDirector.buildIntentLookup(intents: intents, dialogueCount: 5)

    // First intent: lines 0-1
    #expect(lookup[0] != nil)
    #expect(lookup[1] != nil)

    // Gap: line 2
    #expect(lookup[2] == nil, "Line 2 should be in neutral gap")

    // Second intent: lines 3-4
    #expect(lookup[3] != nil)
    #expect(lookup[4] != nil)
    #expect(lookup[3]?.intent.from == "sad")
  }

  @Test("buildIntentLookup handles single-line intent")
  func singleLineIntent() {
    let intents = [
      IntentAnnotation(
        from: "calm",
        to: "tense",
        startLine: 0,
        endLine: 0,
        scoped: true
      )
    ]

    let lookup = StageDirector.buildIntentLookup(intents: intents, dialogueCount: 1)

    #expect(lookup[0]?.arcPosition == 0.0, "Single-line intent should have arc position 0.0")
  }
}
