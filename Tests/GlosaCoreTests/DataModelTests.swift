import Foundation
import Testing
@testable import GlosaCore

/// Tests that all GlosaCore data model types conform to Sendable, Codable,
/// and Equatable by performing JSON round-trip encoding/decoding and
/// equality assertions.
@Suite("GlosaCore Data Model Round-Trip Tests")
struct DataModelTests {

    // MARK: - SceneContext

    @Test("SceneContext round-trips through JSON")
    func sceneContextRoundTrip() throws {
        let original = SceneContext(
            location: "the study",
            time: "late night",
            ambience: "quiet hum of electronics"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SceneContext.self, from: data)

        #expect(decoded == original)
    }

    @Test("SceneContext with nil ambience round-trips")
    func sceneContextNilAmbienceRoundTrip() throws {
        let original = SceneContext(location: "open field", time: "dusk")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SceneContext.self, from: data)

        #expect(decoded == original)
        #expect(decoded.ambience == nil)
    }

    // MARK: - Intent

    @Test("Intent round-trips through JSON")
    func intentRoundTrip() throws {
        let original = Intent(
            from: "curious",
            to: "frustrated",
            pace: "moderate",
            spacing: "beat",
            scoped: true,
            lineCount: 5
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Intent.self, from: data)

        #expect(decoded == original)
    }

    @Test("Marker Intent (no closing tag) round-trips")
    func markerIntentRoundTrip() throws {
        let original = Intent(
            from: "frustrated",
            to: "resigned",
            pace: "decelerating",
            scoped: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Intent.self, from: data)

        #expect(decoded == original)
        #expect(decoded.scoped == false)
        #expect(decoded.lineCount == nil)
        #expect(decoded.spacing == nil)
    }

    // MARK: - Constraint

    @Test("Constraint round-trips through JSON")
    func constraintRoundTrip() throws {
        let original = Constraint(
            character: "THE PRACTITIONER",
            direction: "thinking aloud, halting delivery",
            register: "mid",
            ceiling: "moderate"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Constraint.self, from: data)

        #expect(decoded == original)
    }

    @Test("Constraint with nil optional fields round-trips")
    func constraintMinimalRoundTrip() throws {
        let original = Constraint(
            character: "ESPECTRO FAMILIAR",
            direction: "patient, measured, slightly amused"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Constraint.self, from: data)

        #expect(decoded == original)
        #expect(decoded.register == nil)
        #expect(decoded.ceiling == nil)
    }

    // MARK: - GlosaDiagnostic

    @Test("GlosaDiagnostic warning round-trips through JSON")
    func diagnosticWarningRoundTrip() throws {
        let original = GlosaDiagnostic(
            severity: .warning,
            message: "Unclosed SceneContext tag",
            line: 42
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlosaDiagnostic.self, from: data)

        #expect(decoded == original)
    }

    @Test("GlosaDiagnostic info with nil line round-trips")
    func diagnosticInfoNilLineRoundTrip() throws {
        let original = GlosaDiagnostic(
            severity: .info,
            message: "No GLOSA annotations found"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlosaDiagnostic.self, from: data)

        #expect(decoded == original)
        #expect(decoded.line == nil)
    }

    // MARK: - GlosaScore (full round-trip)

    @Test("GlosaScore with 1 scene, 1 intent, 1 constraint round-trips")
    func glosaScoreFullRoundTrip() throws {
        let constraint = Constraint(
            character: "BERNARD",
            direction: "nervous amateur, out of his depth",
            ceiling: "moderate"
        )

        let intent = Intent(
            from: "conspiratorial calm",
            to: "grim resolve",
            pace: "slow",
            scoped: true,
            lineCount: 3
        )

        let intentEntry = GlosaScore.IntentEntry(
            intent: intent,
            constraints: [constraint],
            dialogueLines: [
                "Have you thought about how I'm going to do it?",
                "I can't think about anything else.",
                "And?",
            ]
        )

        let sceneContext = SceneContext(
            location: "steam room",
            time: "morning",
            ambience: "hissing steam, echoing tile"
        )

        let sceneEntry = GlosaScore.SceneEntry(
            context: sceneContext,
            intents: [intentEntry]
        )

        let original = GlosaScore(scenes: [sceneEntry])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

        #expect(decoded == original)
        #expect(decoded.scenes.count == 1)
        #expect(decoded.scenes[0].intents.count == 1)
        #expect(decoded.scenes[0].intents[0].constraints.count == 1)
        #expect(decoded.scenes[0].intents[0].dialogueLines.count == 3)
    }

    @Test("Empty GlosaScore round-trips")
    func emptyGlosaScoreRoundTrip() throws {
        let original = GlosaScore()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

        #expect(decoded == original)
        #expect(decoded.scenes.isEmpty)
    }

    @Test("GlosaScore with multiple scenes and intents round-trips")
    func glosaScoreMultipleScenes() throws {
        let scene1 = GlosaScore.SceneEntry(
            context: SceneContext(location: "steam room", time: "morning"),
            intents: [
                GlosaScore.IntentEntry(
                    intent: Intent(from: "calm", to: "tense", scoped: true, lineCount: 2),
                    constraints: [
                        Constraint(character: "A", direction: "nervous"),
                        Constraint(character: "B", direction: "confident"),
                    ],
                    dialogueLines: ["Line 1", "Line 2"]
                ),
            ]
        )

        let scene2 = GlosaScore.SceneEntry(
            context: SceneContext(location: "office", time: "afternoon", ambience: "typing"),
            intents: [
                GlosaScore.IntentEntry(
                    intent: Intent(from: "professional", to: "frustrated", pace: "accelerating"),
                    dialogueLines: ["Line 3"]
                ),
            ]
        )

        let original = GlosaScore(scenes: [scene1, scene2])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

        #expect(decoded == original)
        #expect(decoded.scenes.count == 2)
    }

    // MARK: - Sendable conformance (compilation proof)

    @Test("All types are Sendable")
    func sendableConformance() async {
        // These assignments prove Sendable conformance at compile time.
        // If any type is not Sendable, this test will not compile under strict concurrency.
        let context: any Sendable = SceneContext(location: "a", time: "b")
        let intent: any Sendable = Intent(from: "a", to: "b")
        let constraint: any Sendable = Constraint(character: "X", direction: "y")
        let diagnostic: any Sendable = GlosaDiagnostic(severity: .info, message: "test")
        let score: any Sendable = GlosaScore()

        // Use the values to silence unused-variable warnings.
        _ = context
        _ = intent
        _ = constraint
        _ = diagnostic
        _ = score
    }
}
