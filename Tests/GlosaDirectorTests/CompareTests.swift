import Foundation
import Testing

@testable import GlosaDirector
import GlosaAnnotation
import GlosaCore
import SwiftCompartido

// MARK: - Helpers (reuse pattern from StageDirectorTests)

/// Build a `GuionParsedElementCollection` from raw elements.
private func makeScreenplayForCompare(_ elements: [GuionElement]) -> GuionParsedElementCollection {
    GuionParsedElementCollection(
        filename: "compare-test.fountain",
        elements: elements,
        titlePage: [],
        suppressSceneNumbers: false
    )
}

/// A steam-room scene with deterministic GLOSA annotations.
private func makeSteamRoomSceneElements() -> [GuionElement] {
    [
        GuionElement(elementType: .sceneHeading, elementText: "INT. STEAM ROOM - MORNING"),
        GuionElement(elementType: .action,       elementText: "BERNARD and KILLIAN sit in the steam."),
        GuionElement(elementType: .character,    elementText: "BERNARD"),
        GuionElement(elementType: .dialogue,     elementText: "Have you thought about how I'm going to do it?"),
        GuionElement(elementType: .character,    elementText: "KILLIAN"),
        GuionElement(elementType: .dialogue,     elementText: "I can't think about anything else."),
        GuionElement(elementType: .character,    elementText: "BERNARD"),
        GuionElement(elementType: .dialogue,     elementText: "And?"),
    ]
}

/// GLOSA fountain notes that encode annotations for the steam-room scene above.
///
/// These notes are fed to `GlosaCompiler` (the template path).
private let steamRoomFountainNotes: [String] = [
    "<SceneContext location=\"steam room\" time=\"morning\" ambience=\"hissing steam\">",
    "<Intent from=\"conspiratorial calm\" to=\"grim resolve\" pace=\"slow\" lineCount=\"3\">",
    "Have you thought about how I'm going to do it?",
    "I can't think about anything else.",
    "And?",
    "</Intent>",
    "<Constraint character=\"BERNARD\" direction=\"nervous amateur, out of his depth\" ceiling=\"moderate\">",
    "<Constraint character=\"KILLIAN\" direction=\"clinical detachment, calm and methodical\" ceiling=\"subdued\">",
    "</SceneContext>",
]

/// Dialogue lines matching the steam-room scene above.
private let steamRoomDialogueLines: [(character: String, text: String)] = [
    ("BERNARD", "Have you thought about how I'm going to do it?"),
    ("KILLIAN", "I can't think about anything else."),
    ("BERNARD", "And?"),
]

/// `SceneAnnotation` matching the steam-room scene — used as the mock LLM response.
private func makeSteamRoomLLMAnnotation() -> SceneAnnotation {
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
                direction: "nervous amateur, out of his depth",
                ceiling: "moderate"
            ),
            ConstraintAnnotation(
                character: "KILLIAN",
                direction: "clinical detachment, calm and methodical",
                ceiling: "subdued"
            ),
        ]
    )
}

/// A `SceneAnnotation` that differs from the template: different intent emotions.
private func makeDivergentLLMAnnotation() -> SceneAnnotation {
    SceneAnnotation(
        sceneContext: SceneContextAnnotation(
            location: "office",
            time: "afternoon"
        ),
        intents: [
            IntentAnnotation(
                from: "cheerful",
                to: "resigned",
                pace: "fast",
                startLine: 0,
                endLine: 2,
                scoped: true
            )
        ],
        constraints: [
            ConstraintAnnotation(
                character: "BERNARD",
                direction: "buoyant confidence",
                ceiling: "intense"
            ),
        ]
    )
}

// MARK: - Comparison Logic Helpers

/// Run the template compilation path.
private func compileTemplatePath(
    notes: [String],
    dialogueLines: [(character: String, text: String)]
) throws -> [Int: String] {
    let compiler = GlosaCompiler()
    let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)
    return result.instructs
}

/// Run the LLM path using a mock provider, returning a dialogue-index → instruct map.
private func compileLLMPath(
    screenplay: GuionParsedElementCollection,
    annotation: SceneAnnotation
) async throws -> [Int: String] {
    let provider = MockAnnotationProvider(annotation: annotation)
    let director = StageDirector(provider: provider)
    let annotated = try await director.annotate(screenplay, model: "mock-model")

    var instructs: [Int: String] = [:]
    var index = 0
    for element in annotated.annotatedElements {
        if element.element.elementType == .dialogue {
            if let instruct = element.instruct {
                instructs[index] = instruct
            }
            index += 1
        }
    }
    return instructs
}

/// Compute match/differ result for each dialogue line.
private struct LineComparison {
    let lineIndex: Int
    let character: String
    let templateInstruct: String?
    let llmInstruct: String?
    var matches: Bool { templateInstruct == llmInstruct }
}

private func buildComparisons(
    dialogueLines: [(character: String, text: String)],
    templateInstructs: [Int: String],
    llmInstructs: [Int: String]
) -> [LineComparison] {
    dialogueLines.enumerated().map { index, line in
        LineComparison(
            lineIndex: index,
            character: line.character,
            templateInstruct: templateInstructs[index],
            llmInstruct: llmInstructs[index]
        )
    }
}

// MARK: - Tests

@Suite("CompareCommand — Template vs LLM diff")
struct CompareTests {

    // MARK: Template path produces instructs for all dialogue lines

    @Test("template compilation produces instruct for every dialogue line")
    func templatePathProducesInstructs() throws {
        let instructs = try compileTemplatePath(
            notes: steamRoomFountainNotes,
            dialogueLines: steamRoomDialogueLines
        )

        #expect(instructs.count == 3, "All 3 dialogue lines should have template instructs")
        #expect(instructs[0] != nil, "Line 0 (BERNARD) should have template instruct")
        #expect(instructs[1] != nil, "Line 1 (KILLIAN) should have template instruct")
        #expect(instructs[2] != nil, "Line 2 (BERNARD) should have template instruct")
    }

    // MARK: LLM path produces instructs for all dialogue lines

    @Test("LLM path (mock) produces instruct for every dialogue line")
    func llmPathProducesInstructs() async throws {
        let screenplay = makeScreenplayForCompare(makeSteamRoomSceneElements())
        let llmInstructs = try await compileLLMPath(
            screenplay: screenplay,
            annotation: makeSteamRoomLLMAnnotation()
        )

        #expect(llmInstructs.count == 3, "All 3 dialogue lines should have LLM instructs")
        #expect(llmInstructs[0] != nil, "Line 0 should have LLM instruct")
        #expect(llmInstructs[1] != nil, "Line 1 should have LLM instruct")
        #expect(llmInstructs[2] != nil, "Line 2 should have LLM instruct")
    }

    // MARK: Both paths produce instructs covering all dialogue lines

    @Test("both paths produce comparisons covering all dialogue lines")
    func bothPathsProduceComparisonsForAllLines() async throws {
        let screenplay = makeScreenplayForCompare(makeSteamRoomSceneElements())

        let templateInstructs = try compileTemplatePath(
            notes: steamRoomFountainNotes,
            dialogueLines: steamRoomDialogueLines
        )

        let llmInstructs = try await compileLLMPath(
            screenplay: screenplay,
            annotation: makeSteamRoomLLMAnnotation()
        )

        let comparisons = buildComparisons(
            dialogueLines: steamRoomDialogueLines,
            templateInstructs: templateInstructs,
            llmInstructs: llmInstructs
        )

        // Verify all comparison entries are present (one per dialogue line).
        #expect(comparisons.count == steamRoomDialogueLines.count,
                "Comparisons should cover all dialogue lines")

        // Each comparison should reference the correct character.
        #expect(comparisons[0].character == "BERNARD",
                "Line 0 should map to BERNARD")
        #expect(comparisons[1].character == "KILLIAN",
                "Line 1 should map to KILLIAN")
        #expect(comparisons[2].character == "BERNARD",
                "Line 2 should map to BERNARD")

        // Both paths should have produced non-nil instructs for all lines.
        for comparison in comparisons {
            #expect(
                comparison.templateInstruct != nil,
                "Line \(comparison.lineIndex) should have a template instruct"
            )
            #expect(
                comparison.llmInstruct != nil,
                "Line \(comparison.lineIndex) should have an LLM instruct"
            )
        }

        // Note: The two paths may produce different instruct strings even with the
        // same logical annotation, because the template compiler and the LLM
        // composer use different formatting paths. The comparison is about
        // identifying those differences, not expecting them to match.
    }

    // MARK: Divergent annotations produce differ flags

    @Test("divergent LLM annotation produces differ flags in diff output")
    func divergentAnnotationsProduceDiffer() async throws {
        let screenplay = makeScreenplayForCompare(makeSteamRoomSceneElements())

        let templateInstructs = try compileTemplatePath(
            notes: steamRoomFountainNotes,
            dialogueLines: steamRoomDialogueLines
        )

        // Use a divergent annotation (different location, intent, constraints).
        let llmInstructs = try await compileLLMPath(
            screenplay: screenplay,
            annotation: makeDivergentLLMAnnotation()
        )

        let comparisons = buildComparisons(
            dialogueLines: steamRoomDialogueLines,
            templateInstructs: templateInstructs,
            llmInstructs: llmInstructs
        )

        // All 3 lines should be present.
        #expect(comparisons.count == 3,
                "All dialogue lines should appear in the diff, even when they differ")

        // At least one line should differ (divergent location/intent guarantees this).
        let differCount = comparisons.filter { !$0.matches }.count
        #expect(differCount > 0,
                "Divergent annotations should produce at least one 'differ' line")

        // Verify the 'differ' label logic: divergent instructs are not equal.
        for comparison in comparisons {
            if let t = comparison.templateInstruct, let l = comparison.llmInstruct {
                if t != l {
                    #expect(!comparison.matches, "Non-equal instructs should be flagged as differ")
                } else {
                    #expect(comparison.matches, "Equal instructs should be flagged as match")
                }
            }
        }
    }

    // MARK: Diff covers all dialogue lines including neutral gaps

    @Test("diff covers all dialogue lines including neutral-gap lines")
    func diffCoversAllLinesIncludingGaps() async throws {
        // A screenplay where only the first line has an intent (lines 1 and 2 are neutral
        // for the template path — but the LLM covers them all).
        let partialNotes: [String] = [
            "<SceneContext location=\"office\" time=\"day\">",
            "<Intent from=\"calm\" to=\"tense\" lineCount=\"1\">",
            "First line in the office.",
            "</Intent>",
            // Lines 1 and 2 are in a neutral gap for the template path.
            "Second line.",
            "Third line.",
            "</SceneContext>",
        ]

        let gapDialogueLines: [(character: String, text: String)] = [
            ("ALICE", "First line in the office."),
            ("BOB", "Second line."),
            ("ALICE", "Third line."),
        ]

        let gapElements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .character,    elementText: "ALICE"),
            GuionElement(elementType: .dialogue,     elementText: "First line in the office."),
            GuionElement(elementType: .character,    elementText: "BOB"),
            GuionElement(elementType: .dialogue,     elementText: "Second line."),
            GuionElement(elementType: .character,    elementText: "ALICE"),
            GuionElement(elementType: .dialogue,     elementText: "Third line."),
        ]

        let screenplay = makeScreenplayForCompare(gapElements)

        let templateInstructs = try compileTemplatePath(
            notes: partialNotes,
            dialogueLines: gapDialogueLines
        )

        let fullCoverageAnnotation = SceneAnnotation(
            sceneContext: SceneContextAnnotation(location: "office", time: "day"),
            intents: [
                IntentAnnotation(from: "calm", to: "tense", pace: "moderate",
                                 startLine: 0, endLine: 2, scoped: true),
            ],
            constraints: [
                ConstraintAnnotation(character: "ALICE", direction: "focused and crisp"),
            ]
        )

        let llmInstructs = try await compileLLMPath(
            screenplay: screenplay,
            annotation: fullCoverageAnnotation
        )

        let comparisons = buildComparisons(
            dialogueLines: gapDialogueLines,
            templateInstructs: templateInstructs,
            llmInstructs: llmInstructs
        )

        // All 3 lines must appear in the diff output.
        #expect(comparisons.count == 3, "All 3 dialogue lines must appear in diff output")

        // The diff should contain lines for characters ALICE and BOB.
        let characters = comparisons.map(\.character)
        #expect(characters.contains("ALICE"), "Diff should include ALICE's lines")
        #expect(characters.contains("BOB"),   "Diff should include BOB's lines")
    }

    // MARK: Diff table match/differ indicators

    @Test("diff table comparison correctly labels 'match' and 'differ'")
    func diffTableMatchDifferIndicators() {
        // Build a scenario where line 0 matches and line 1 differs.
        let dialogueLines: [(character: String, text: String)] = [
            ("ALICE", "Hello."),
            ("BOB",   "Goodbye."),
        ]

        // templateInstructs[0] == llmInstructs[0] → match
        // templateInstructs[1] != llmInstructs[1] → differ
        let templateInstructs: [Int: String] = [
            0: "Calm office in the afternoon. Alice speaks warmly.",
            1: "Tense departure. Bob delivers flatly.",
        ]
        let llmInstructs: [Int: String] = [
            0: "Calm office in the afternoon. Alice speaks warmly.",
            1: "Relaxed farewell. Bob is lighthearted.",
        ]

        let comparisons = buildComparisons(
            dialogueLines: dialogueLines,
            templateInstructs: templateInstructs,
            llmInstructs: llmInstructs
        )

        // Line 0 should match, line 1 should differ.
        #expect(comparisons[0].matches,  "Line 0 should be flagged 'match' (identical instructs)")
        #expect(!comparisons[1].matches, "Line 1 should be flagged 'differ' (different instructs)")

        // Both characters should be present.
        let characters = comparisons.map(\.character)
        #expect(characters.contains("ALICE"), "Diff should include ALICE")
        #expect(characters.contains("BOB"),   "Diff should include BOB")

        // Verify the match labels in string form (as printDiffTable would show them).
        let matchLabels = comparisons.map { $0.matches ? "match" : "differ" }
        #expect(matchLabels.contains("match"),  "Comparison results should include 'match'")
        #expect(matchLabels.contains("differ"), "Comparison results should include 'differ'")

        // Line indices (0, 1) should be present.
        let indices = comparisons.map(\.lineIndex)
        #expect(indices.contains(0), "Diff should include line 0")
        #expect(indices.contains(1), "Diff should include line 1")
    }

    // MARK: Empty screenplay produces empty diff

    @Test("empty screenplay produces empty diff")
    func emptyScreenplayProducesEmptyDiff() throws {
        let instructs = try compileTemplatePath(notes: [], dialogueLines: [])
        let comparisons = buildComparisons(
            dialogueLines: [],
            templateInstructs: instructs,
            llmInstructs: [:]
        )
        #expect(comparisons.isEmpty, "Empty screenplay should produce empty comparisons")
    }
}

