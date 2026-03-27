import Testing
import GlosaCore
import GlosaAnnotation
import SwiftCompartido

@Suite("GlosaAnnotatedScreenplay Tests")
struct GlosaAnnotatedScreenplayTests {

    // MARK: - Helpers

    /// Creates a simple screenplay with a mix of element types.
    ///
    /// Structure:
    ///   [0] Scene Heading: "INT. STUDY - NIGHT"
    ///   [1] Action: "DR. CHEN sits at her desk."
    ///   [2] Character: "DR. CHEN"
    ///   [3] Dialogue: "Something strange is happening here."  (dialogue index 0)
    ///   [4] Character: "DR. CHEN"
    ///   [5] Dialogue: "I need to investigate further."        (dialogue index 1)
    ///   [6] Action: "She opens the drawer."
    ///   [7] Character: "DR. CHEN"
    ///   [8] Dialogue: "What is this?"                          (dialogue index 2)
    private func makeScreenplay() -> GuionParsedElementCollection {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. STUDY - NIGHT"),
            GuionElement(elementType: .action, elementText: "DR. CHEN sits at her desk."),
            GuionElement(elementType: .character, elementText: "DR. CHEN"),
            GuionElement(elementType: .dialogue, elementText: "Something strange is happening here."),
            GuionElement(elementType: .character, elementText: "DR. CHEN"),
            GuionElement(elementType: .dialogue, elementText: "I need to investigate further."),
            GuionElement(elementType: .action, elementText: "She opens the drawer."),
            GuionElement(elementType: .character, elementText: "DR. CHEN"),
            GuionElement(elementType: .dialogue, elementText: "What is this?"),
        ]
        return GuionParsedElementCollection(elements: elements)
    }

    /// Creates a CompilationResult where dialogue indices 0 and 1 have
    /// instructs, and index 2 is in a neutral gap (no instruct).
    private func makeCompilationResult() -> CompilationResult {
        let sceneCtx = SceneContext(location: "the study", time: "late night", ambience: "quiet hum of electronics")
        let intent = Intent(from: "curious", to: "frustrated", pace: "moderate", spacing: nil, scoped: true, lineCount: 2)
        let constraint = Constraint(character: "DR. CHEN", direction: "thinking aloud", register: nil, ceiling: "moderate")

        let provenance: [InstructProvenance] = [
            InstructProvenance(
                lineIndex: 0,
                characterName: "DR. CHEN",
                sceneContext: sceneCtx,
                intent: ResolvedIntent(intent: intent, arcPosition: 0.0),
                constraint: constraint,
                composedInstruct: "Late night in the study, quiet hum of electronics. Curious, early in arc toward frustrated, moderate pace. Thinking aloud. Ceiling: moderate."
            ),
            InstructProvenance(
                lineIndex: 1,
                characterName: "DR. CHEN",
                sceneContext: sceneCtx,
                intent: ResolvedIntent(intent: intent, arcPosition: 1.0),
                constraint: constraint,
                composedInstruct: "Late night in the study, quiet hum of electronics. Frustrated, deep into arc from curious, moderate pace. Thinking aloud. Ceiling: moderate."
            ),
        ]

        return CompilationResult(
            instructs: [
                0: "Late night in the study, quiet hum of electronics. Curious, early in arc toward frustrated, moderate pace. Thinking aloud. Ceiling: moderate.",
                1: "Late night in the study, quiet hum of electronics. Frustrated, deep into arc from curious, moderate pace. Thinking aloud. Ceiling: moderate.",
            ],
            diagnostics: [
                GlosaDiagnostic(severity: .info, message: "Parsed 1 scene context"),
            ],
            provenance: provenance
        )
    }

    // MARK: - Tests

    @Test("Dialogue elements receive matching instructs from CompilationResult")
    func dialogueElementsReceiveInstructs() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        // Total elements should match
        #expect(annotated.annotatedElements.count == screenplay.elements.count)

        // Dialogue index 0 -> element index 3
        let dialogue0 = annotated.annotatedElements[3]
        #expect(dialogue0.element.elementType == .dialogue)
        #expect(dialogue0.instruct == result.instructs[0])
        #expect(dialogue0.instruct != nil)

        // Dialogue index 1 -> element index 5
        let dialogue1 = annotated.annotatedElements[5]
        #expect(dialogue1.element.elementType == .dialogue)
        #expect(dialogue1.instruct == result.instructs[1])
        #expect(dialogue1.instruct != nil)
    }

    @Test("Dialogue elements in neutral gap have nil instruct")
    func neutralGapDialogueHasNilInstruct() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        // Dialogue index 2 -> element index 8 (no entry in instructs map)
        let dialogue2 = annotated.annotatedElements[8]
        #expect(dialogue2.element.elementType == .dialogue)
        #expect(dialogue2.instruct == nil)
        #expect(dialogue2.directives == nil)
    }

    @Test("Non-dialogue elements have nil directives and nil instruct")
    func nonDialogueElementsAreNil() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        // Scene heading (index 0)
        let sceneHeading = annotated.annotatedElements[0]
        #expect(sceneHeading.element.elementType == .sceneHeading)
        #expect(sceneHeading.directives == nil)
        #expect(sceneHeading.instruct == nil)

        // Action (index 1)
        let action1 = annotated.annotatedElements[1]
        #expect(action1.element.elementType == .action)
        #expect(action1.directives == nil)
        #expect(action1.instruct == nil)

        // Character (index 2)
        let character0 = annotated.annotatedElements[2]
        #expect(character0.element.elementType == .character)
        #expect(character0.directives == nil)
        #expect(character0.instruct == nil)

        // Character (index 4)
        let character1 = annotated.annotatedElements[4]
        #expect(character1.element.elementType == .character)
        #expect(character1.directives == nil)
        #expect(character1.instruct == nil)

        // Action (index 6)
        let action2 = annotated.annotatedElements[6]
        #expect(action2.element.elementType == .action)
        #expect(action2.directives == nil)
        #expect(action2.instruct == nil)

        // Character (index 7)
        let character2 = annotated.annotatedElements[7]
        #expect(character2.element.elementType == .character)
        #expect(character2.directives == nil)
        #expect(character2.instruct == nil)
    }

    @Test("Directives are reconstructed from provenance for annotated dialogue")
    func directivesReconstructedFromProvenance() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        // Dialogue index 0 -> element index 3
        let dialogue0 = annotated.annotatedElements[3]
        #expect(dialogue0.directives != nil)
        #expect(dialogue0.directives?.sceneContext?.location == "the study")
        #expect(dialogue0.directives?.sceneContext?.time == "late night")
        #expect(dialogue0.directives?.intent?.arcPosition == 0.0)
        #expect(dialogue0.directives?.intent?.intent.from == "curious")
        #expect(dialogue0.directives?.constraint?.character == "DR. CHEN")

        // Dialogue index 1 -> element index 5
        let dialogue1 = annotated.annotatedElements[5]
        #expect(dialogue1.directives != nil)
        #expect(dialogue1.directives?.intent?.arcPosition == 1.0)
        #expect(dialogue1.directives?.intent?.intent.to == "frustrated")
    }

    @Test("Diagnostics and provenance are forwarded from CompilationResult")
    func diagnosticsAndProvenanceForwarded() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        #expect(annotated.diagnostics.count == result.diagnostics.count)
        #expect(annotated.diagnostics.first?.message == "Parsed 1 scene context")
        #expect(annotated.provenance.count == result.provenance.count)
    }

    @Test("Screenplay reference is preserved")
    func screenplayReferencePreserved() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        #expect(annotated.screenplay.elements.count == screenplay.elements.count)
        #expect(annotated.screenplay === screenplay)
    }

    @Test("Empty compilation result produces all-nil annotations")
    func emptyCompilationResult() {
        let screenplay = makeScreenplay()
        let result = CompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        #expect(annotated.annotatedElements.count == screenplay.elements.count)

        for annotatedElement in annotated.annotatedElements {
            #expect(annotatedElement.instruct == nil)
            #expect(annotatedElement.directives == nil)
        }

        #expect(annotated.diagnostics.isEmpty)
        #expect(annotated.provenance.isEmpty)
    }

    @Test("Build with explicit score preserves the score")
    func buildWithExplicitScore() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let score = GlosaScore(scenes: [
            GlosaScore.SceneEntry(
                context: SceneContext(location: "the study", time: "late night", ambience: "quiet hum")
            )
        ])

        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: result,
            score: score
        )

        #expect(annotated.score.scenes.count == 1)
        #expect(annotated.score.scenes.first?.context.location == "the study")
    }

    @Test("Instruct matches CompilationResult.instructs[index] for every dialogue element")
    func instructMatchesCompilationResultForAllDialogue() {
        let screenplay = makeScreenplay()
        let result = makeCompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        var dialogueIndex = 0
        for annotatedElement in annotated.annotatedElements {
            if annotatedElement.element.elementType == .dialogue {
                let expectedInstruct = result.instructs[dialogueIndex]
                #expect(annotatedElement.instruct == expectedInstruct,
                        "Dialogue index \(dialogueIndex): expected \(String(describing: expectedInstruct)), got \(String(describing: annotatedElement.instruct))")
                dialogueIndex += 1
            }
        }

        // Verify we counted all 3 dialogue elements
        #expect(dialogueIndex == 3)
    }

    @Test("Screenplay with only non-dialogue elements produces all-nil annotations")
    func onlyNonDialogueElements() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .action, elementText: "The room is empty."),
            GuionElement(elementType: .transition, elementText: "CUT TO:"),
        ]
        let screenplay = GuionParsedElementCollection(elements: elements)
        let result = CompilationResult()
        let annotated = GlosaAnnotatedScreenplay.build(from: screenplay, compilationResult: result)

        #expect(annotated.annotatedElements.count == 3)
        for annotatedElement in annotated.annotatedElements {
            #expect(annotatedElement.instruct == nil)
            #expect(annotatedElement.directives == nil)
        }
    }
}
