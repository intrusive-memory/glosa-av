import Foundation
import Testing
@testable import GlosaCore

/// Tests for the `InstructComposer` — verifies that instruct string output
/// matches the expected format from REQUIREMENTS.md Section 4.3 and EXAMPLES.md.
@Suite("InstructComposer Tests")
struct InstructComposerTests {

    let composer = InstructComposer()

    // MARK: - REQUIREMENTS.md Section 4.3 Example

    @Test("Matches REQUIREMENTS.md Section 4.3 example format")
    func requirementsSection43Example() {
        // Line 1 of a 3-line scoped Intent: curious -> frustrated, arcPosition ~0.0
        // From REQUIREMENTS.md:
        //   "Late night in the study, quiet hum of electronics.
        //    Curious, early in arc toward frustrated, moderate pace.
        //    Thinking aloud, halting delivery. Ceiling: moderate."
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "the study",
                time: "late night",
                ambience: "quiet hum of electronics"
            ),
            intent: ResolvedIntent(
                intent: Intent(
                    from: "curious",
                    to: "frustrated",
                    pace: "moderate",
                    scoped: true,
                    lineCount: 3
                ),
                arcPosition: 0.0 // Line 0 of 3 = 0%
            ),
            constraint: Constraint(
                character: "THE PRACTITIONER",
                direction: "thinking aloud, halting delivery",
                ceiling: "moderate"
            )
        )

        let result = composer.compose(directives)

        #expect(result != nil)
        guard let instruct = result else { return }

        // Verify SceneContext portion
        #expect(instruct.contains("Late night in the study, quiet hum of electronics."))

        // Verify Intent arc description (0% = very early in arc)
        #expect(instruct.contains("Curious, very early in arc toward frustrated"))
        #expect(instruct.contains("moderate pace"))

        // Verify Constraint portion
        #expect(instruct.contains("Thinking aloud, halting delivery."))
        #expect(instruct.contains("Ceiling: moderate."))
    }

    @Test("Second line of 3-line scoped intent (50% = midway)")
    func midpointArcDescription() {
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "the study",
                time: "late night",
                ambience: "quiet hum of electronics"
            ),
            intent: ResolvedIntent(
                intent: Intent(
                    from: "curious",
                    to: "frustrated",
                    pace: "moderate",
                    scoped: true,
                    lineCount: 3
                ),
                arcPosition: 0.5 // Line 1 of 3 = 50%
            ),
            constraint: Constraint(
                character: "ESPECTRO FAMILIAR",
                direction: "patient, measured, slightly amused"
            )
        )

        let result = composer.compose(directives)

        #expect(result != nil)
        guard let instruct = result else { return }

        // 50% = "Midway between {from} and {to}"
        #expect(instruct.contains("Midway between curious and frustrated"))
        #expect(instruct.contains("moderate pace"))
        #expect(instruct.contains("Patient, measured, slightly amused."))
    }

    @Test("Third line of 3-line scoped intent (100% = arrived)")
    func arrivedArcDescription() {
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "the study",
                time: "late night",
                ambience: "quiet hum of electronics"
            ),
            intent: ResolvedIntent(
                intent: Intent(
                    from: "curious",
                    to: "frustrated",
                    pace: "moderate",
                    scoped: true,
                    lineCount: 3
                ),
                arcPosition: 1.0 // Line 2 of 3 = 100%
            ),
            constraint: Constraint(
                character: "THE PRACTITIONER",
                direction: "thinking aloud, halting delivery",
                ceiling: "moderate"
            )
        )

        let result = composer.compose(directives)

        #expect(result != nil)
        guard let instruct = result else { return }

        // 100% = "Arrived at {to}"
        #expect(instruct.contains("Arrived at frustrated"))
        #expect(instruct.contains("moderate pace"))
    }

    // MARK: - Arc Position Band Coverage

    @Test("Very early arc (0-10%)")
    func veryEarlyArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry"),
                arcPosition: 0.05
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("very early in arc toward angry"))
    }

    @Test("Early arc (11-25%)")
    func earlyArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "conspiratorial calm", to: "grim resolve"),
                arcPosition: 0.18
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("early in arc toward grim resolve"))
    }

    @Test("Shifting (26-35%)")
    func shiftingArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "tense"),
                arcPosition: 0.27
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Shifting from calm toward tense"))
    }

    @Test("Moving (36-40%)")
    func movingArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "conspiratorial calm", to: "grim resolve"),
                arcPosition: 0.36
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Moving from conspiratorial calm toward grim resolve"))
    }

    @Test("Nearing midpoint (41-49%)")
    func nearingMidpoint() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "accusatory", to: "grudging surrender"),
                arcPosition: 0.42
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Nearing midpoint between accusatory and grudging surrender"))
    }

    @Test("Past midpoint (51-60%)")
    func pastMidpoint() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "conspiratorial calm", to: "grim resolve"),
                arcPosition: 0.55
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Past midpoint, shifting toward grim resolve"))
    }

    @Test("Well into arc (61-75%)")
    func wellIntoArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "tense"),
                arcPosition: 0.64
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Well into the arc from calm toward tense"))
    }

    @Test("Approaching (76-85%)")
    func approachingArc() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "conspiratorial calm", to: "grim resolve"),
                arcPosition: 0.82
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Approaching grim resolve from conspiratorial calm"))
    }

    @Test("Nearing target (86-90%)")
    func nearingTarget() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry"),
                arcPosition: 0.86
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Nearing angry"))
    }

    @Test("Almost at target (91-99%)")
    func almostAtTarget() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry"),
                arcPosition: 0.91
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Almost at angry"))
    }

    // MARK: - Component Presence/Absence

    @Test("No directives returns nil")
    func noDirectivesReturnsNil() {
        let directives = ResolvedDirectives()
        let result = composer.compose(directives)
        #expect(result == nil)
    }

    @Test("SceneContext only (no intent, no constraint)")
    func sceneContextOnly() {
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(location: "office", time: "morning")
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result == "Morning in office.")
    }

    @Test("SceneContext with ambience")
    func sceneContextWithAmbience() {
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "steam room",
                time: "morning",
                ambience: "hissing steam, echoing tile"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result == "Morning in steam room, hissing steam, echoing tile.")
    }

    @Test("Intent only (no scene context, no constraint)")
    func intentOnly() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry", pace: "fast"),
                arcPosition: 0.5
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result!.contains("Midway between calm and angry"))
        #expect(result!.contains("fast pace"))
    }

    @Test("Constraint only (no scene context, no intent)")
    func constraintOnly() {
        let directives = ResolvedDirectives(
            constraint: Constraint(
                character: "ALICE",
                direction: "nervous amateur",
                register: "mid",
                ceiling: "moderate"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result == "Nervous amateur. Register: mid. Ceiling: moderate.")
    }

    @Test("Constraint with ceiling but no register")
    func constraintCeilingNoRegister() {
        let directives = ResolvedDirectives(
            constraint: Constraint(
                character: "BOB",
                direction: "clinical detachment",
                ceiling: "subdued"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result == "Clinical detachment. Ceiling: subdued.")
    }

    @Test("Constraint with direction only (no register, no ceiling)")
    func constraintDirectionOnly() {
        let directives = ResolvedDirectives(
            constraint: Constraint(
                character: "X",
                direction: "thinking aloud"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        #expect(result == "Thinking aloud.")
    }

    @Test("Intent with no pace")
    func intentNoPace() {
        let directives = ResolvedDirectives(
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry"),
                arcPosition: 0.5
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        // No pace means no ", {pace} pace" suffix
        #expect(result == "Midway between calm and angry.")
    }

    // MARK: - EXAMPLES.md: Steam Room Example (Line 0)

    @Test("Steam Room Example line 0: BERNARD, 1/11 (9%)")
    func steamRoomLine0() {
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "a steam room",
                time: "morning",
                ambience: "hissing steam, echoing tile"
            ),
            intent: ResolvedIntent(
                intent: Intent(
                    from: "conspiratorial calm",
                    to: "grim resolve",
                    pace: "slow",
                    scoped: true,
                    lineCount: 11
                ),
                arcPosition: Float(0) / Float(10) // 0%
            ),
            constraint: Constraint(
                character: "BERNARD",
                direction: "nervous amateur, out of his depth, trying to sound casual",
                ceiling: "moderate"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        guard let instruct = result else { return }

        // 0% = very early in arc
        #expect(instruct.contains("Morning in a steam room, hissing steam, echoing tile."))
        #expect(instruct.contains("very early in arc toward grim resolve"))
        #expect(instruct.contains("slow pace"))
        #expect(instruct.contains("Nervous amateur, out of his depth, trying to sound casual."))
        #expect(instruct.contains("Ceiling: moderate."))
    }

    // MARK: - EXAMPLES.md: Neutral Delivery

    @Test("SceneContext + Constraint only (neutral gap): line 4 of Example 2")
    func neutralGapWithConstraint() {
        // Example 2, line 4: BERNARD in neutral gap -- has SceneContext + Constraint but no Intent
        let directives = ResolvedDirectives(
            sceneContext: SceneContext(
                location: "cluttered front room, ceramic figurines on shelves",
                time: "pre-dawn",
                ambience: "quiet house, distant pool filter"
            ),
            intent: nil,
            constraint: Constraint(
                character: "BERNARD",
                direction: "impatient, trying to escape, dry wit as defense mechanism",
                ceiling: "moderate"
            )
        )

        let result = composer.compose(directives)
        #expect(result != nil)
        guard let instruct = result else { return }

        #expect(instruct.contains("Pre-dawn in cluttered front room"))
        #expect(!instruct.contains("arc"))
        #expect(instruct.contains("Impatient, trying to escape, dry wit as defense mechanism."))
        #expect(instruct.contains("Ceiling: moderate."))
    }
}
