import Foundation
import Testing
@testable import GlosaCore

/// Tests for `GlosaValidator` well-formedness checks.
///
/// Verifies that the validator detects and reports:
/// - Unclosed SceneContext
/// - Nested Intents
/// - Missing required attributes on SceneContext, Intent, and Constraint
@Suite("GlosaValidator Tests")
struct GlosaValidatorTests {

    let validator = GlosaValidator()

    // MARK: - Valid Input (No Diagnostics)

    @Test("Well-formed notes produce no diagnostics")
    func wellFormedNotes() {
        let notes: [String] = [
            #"<SceneContext location="the study" time="late night" ambience="quiet hum">"#,
            #"<Constraint character="A" direction="calm and steady">"#,
            #"<Intent from="curious" to="frustrated" pace="moderate">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Unclosed SceneContext

    @Test("Unclosed SceneContext produces warning")
    func unclosedSceneContext() {
        let notes: [String] = [
            #"<SceneContext location="the study" time="late night">"#,
            #"<Intent from="calm" to="tense">"#,
            "</Intent>",
            // Missing </SceneContext>
        ]

        let diagnostics = validator.validate(notes: notes)
        #expect(!diagnostics.isEmpty)

        let unclosedWarning = diagnostics.first { $0.message.contains("Unclosed SceneContext") }
        #expect(unclosedWarning != nil)
        #expect(unclosedWarning?.severity == .warning)
    }

    @Test("Closing SceneContext without opening produces warning")
    func closingWithoutOpening() {
        let notes: [String] = [
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        #expect(!diagnostics.isEmpty)

        let warning = diagnostics.first { $0.message.contains("without matching opening") }
        #expect(warning != nil)
        #expect(warning?.severity == .warning)
    }

    // MARK: - Nested Intents

    @Test("Nested Intent produces warning")
    func nestedIntent() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Intent from="calm" to="tense">"#,
            // Opening another Intent before closing the first = nesting
            #"<Intent from="happy" to="sad">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        #expect(!diagnostics.isEmpty)

        let nestedWarning = diagnostics.first { $0.message.contains("Nested Intent") }
        #expect(nestedWarning != nil)
        #expect(nestedWarning?.severity == .warning)
        #expect(nestedWarning?.line == 3) // The second Intent is at note index 2 (line 3)
    }

    @Test("Sequential Intents with proper closing are fine")
    func sequentialIntentsValid() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Intent from="calm" to="tense">"#,
            "</Intent>",
            #"<Intent from="happy" to="sad">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Missing Required Attributes

    @Test("SceneContext missing location produces warning")
    func sceneContextMissingLocation() {
        let notes: [String] = [
            #"<SceneContext time="night">"#,
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let locationWarning = diagnostics.first { $0.message.contains("'location'") }
        #expect(locationWarning != nil)
        #expect(locationWarning?.severity == .warning)
    }

    @Test("SceneContext missing time produces warning")
    func sceneContextMissingTime() {
        let notes: [String] = [
            #"<SceneContext location="room">"#,
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let timeWarning = diagnostics.first { $0.message.contains("'time'") }
        #expect(timeWarning != nil)
        #expect(timeWarning?.severity == .warning)
    }

    @Test("SceneContext missing both location and time produces two warnings")
    func sceneContextMissingBoth() {
        let notes: [String] = [
            "<SceneContext>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let locationWarnings = diagnostics.filter { $0.message.contains("'location'") }
        let timeWarnings = diagnostics.filter { $0.message.contains("'time'") }
        #expect(locationWarnings.count == 1)
        #expect(timeWarnings.count == 1)
    }

    @Test("Constraint missing character produces warning")
    func constraintMissingCharacter() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Constraint direction="calm and steady">"#,
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let charWarning = diagnostics.first { $0.message.contains("'character'") }
        #expect(charWarning != nil)
        #expect(charWarning?.severity == .warning)
    }

    @Test("Constraint missing direction produces warning")
    func constraintMissingDirection() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Constraint character="BOB">"#,
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let dirWarning = diagnostics.first { $0.message.contains("'direction'") }
        #expect(dirWarning != nil)
        #expect(dirWarning?.severity == .warning)
    }

    @Test("Constraint missing both character and direction produces two warnings")
    func constraintMissingBoth() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            "<Constraint>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let charWarnings = diagnostics.filter { $0.message.contains("'character'") }
        let dirWarnings = diagnostics.filter { $0.message.contains("'direction'") }
        #expect(charWarnings.count == 1)
        #expect(dirWarnings.count == 1)
    }

    @Test("Intent missing from produces warning")
    func intentMissingFrom() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Intent to="angry">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let fromWarning = diagnostics.first { $0.message.contains("'from'") }
        #expect(fromWarning != nil)
    }

    @Test("Intent missing to produces warning")
    func intentMissingTo() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            #"<Intent from="calm">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let toWarning = diagnostics.first { $0.message.contains("'to'") }
        #expect(toWarning != nil)
    }

    // MARK: - Score Validation

    @Test("Valid score produces no diagnostics")
    func validScoreNoDiagnostics() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "day"),
                intents: [
                    .init(
                        intent: Intent(from: "calm", to: "tense", scoped: true, lineCount: 1),
                        constraints: [Constraint(character: "A", direction: "steady")],
                        dialogueLines: ["Hello"]
                    ),
                ]
            ),
        ])

        let diagnostics = validator.validate(score: score)
        #expect(diagnostics.isEmpty)
    }

    @Test("Score with empty location produces warning")
    func scoreEmptyLocation() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "", time: "day"),
                intents: []
            ),
        ])

        let diagnostics = validator.validate(score: score)
        let warning = diagnostics.first { $0.message.contains("'location'") }
        #expect(warning != nil)
    }

    @Test("Score with mismatched lineCount produces warning")
    func scoreMismatchedLineCount() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "day"),
                intents: [
                    .init(
                        intent: Intent(from: "a", to: "b", scoped: true, lineCount: 5),
                        dialogueLines: ["One", "Two"]
                    ),
                ]
            ),
        ])

        let diagnostics = validator.validate(score: score)
        let warning = diagnostics.first { $0.message.contains("lineCount") }
        #expect(warning != nil)
    }

    // MARK: - Closing Intent Without Opening

    @Test("Closing Intent without opening produces warning")
    func closingIntentWithoutOpening() {
        let notes: [String] = [
            #"<SceneContext location="room" time="day">"#,
            "</Intent>",
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)
        let warning = diagnostics.first { $0.message.contains("without matching opening") }
        #expect(warning != nil)
    }

    // MARK: - Combined Issues

    @Test("Multiple issues are all reported")
    func multipleIssues() {
        let notes: [String] = [
            // Missing location and time
            "<SceneContext>",
            // Missing character
            #"<Constraint direction="calm">"#,
            // Nested intents
            #"<Intent from="a" to="b">"#,
            #"<Intent from="c" to="d">"#,
            "</Intent>",
            // Unclosed SceneContext (no </SceneContext>)
        ]

        let diagnostics = validator.validate(notes: notes)

        // Should have warnings for:
        // 1. Missing location
        // 2. Missing time
        // 3. Missing character on Constraint
        // 4. Nested Intent
        // 5. Unclosed SceneContext
        #expect(diagnostics.count >= 5)

        let hasLocationWarning = diagnostics.contains { $0.message.contains("'location'") }
        let hasTimeWarning = diagnostics.contains { $0.message.contains("'time'") }
        let hasCharacterWarning = diagnostics.contains { $0.message.contains("'character'") }
        let hasNestedWarning = diagnostics.contains { $0.message.contains("Nested Intent") }
        let hasUnclosedWarning = diagnostics.contains { $0.message.contains("Unclosed SceneContext") }

        #expect(hasLocationWarning)
        #expect(hasTimeWarning)
        #expect(hasCharacterWarning)
        #expect(hasNestedWarning)
        #expect(hasUnclosedWarning)
    }

    // MARK: - Line Numbers

    @Test("Diagnostics include correct line numbers")
    func diagnosticsHaveLineNumbers() {
        let notes: [String] = [
            // Line 1
            "<SceneContext>",
            // Line 2
            "<Constraint>",
            // Line 3
            "</SceneContext>",
        ]

        let diagnostics = validator.validate(notes: notes)

        // SceneContext missing attributes should be at line 1
        let sceneWarnings = diagnostics.filter { $0.line == 1 }
        #expect(!sceneWarnings.isEmpty)

        // Constraint missing attributes should be at line 2
        let constraintWarnings = diagnostics.filter { $0.line == 2 }
        #expect(!constraintWarnings.isEmpty)
    }
}
