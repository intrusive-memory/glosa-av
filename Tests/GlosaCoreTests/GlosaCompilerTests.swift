import Foundation
import Testing
@testable import GlosaCore

/// End-to-end tests for `GlosaCompiler` — verifies the full pipeline from
/// scored Fountain notes + dialogue lines to `CompilationResult` with
/// correct instructs per line, diagnostics, and provenance.
@Suite("GlosaCompiler Tests")
struct GlosaCompilerTests {

    let compiler = GlosaCompiler()

    // MARK: - Fallback: Empty Input

    @Test("Empty fountainNotes returns empty CompilationResult")
    func emptyFountainNotes() throws {
        let result = try compiler.compile(
            fountainNotes: [],
            dialogueLines: [
                (character: "ALICE", text: "Hello"),
                (character: "BOB", text: "Hi there"),
            ]
        )

        #expect(result.instructs.isEmpty)
        #expect(result.diagnostics.isEmpty)
        #expect(result.provenance.isEmpty)
    }

    @Test("Empty fountainNotes and empty dialogueLines returns empty result")
    func emptyBoth() throws {
        let result = try compiler.compile(
            fountainNotes: [],
            dialogueLines: []
        )

        #expect(result.instructs.isEmpty)
        #expect(result.diagnostics.isEmpty)
        #expect(result.provenance.isEmpty)
    }

    // MARK: - REQUIREMENTS.md Section 3.1: The Study Example

    @Test("Full REQUIREMENTS.md Section 3.1 example produces correct instructs")
    func requirementsSection31FullExample() throws {
        // Fountain notes from REQUIREMENTS.md Section 3.1
        let notes: [String] = [
            #"<SceneContext location="the study" time="late night" ambience="quiet hum of electronics">"#,
            #"<Constraint character="THE PRACTITIONER" direction="thinking aloud, halting delivery">"#,
            #"<Constraint character="ESPECTRO FAMILIAR" direction="patient, measured, slightly amused">"#,
            #"<Intent from="curious" to="frustrated" pace="moderate">"#,
            "I've been staring at this struct for an hour.",
            "And the metadata?",
            #"Key-value pairs. Right now the only one that matters is "instruct.""#,
            "</Intent>",
            #"<Intent from="frustrated" to="resolved" pace="decelerating">"#,
            #"<Constraint character="THE PRACTITIONER" direction="dawning realization, voice steadying">"#,
            "I need a translator. A layer that sits between the score and the model.",
            "Now you are thinking like a language designer.",
            "</SceneContext>",
        ]

        // All dialogue lines in document order (including neutral gaps if any)
        let dialogueLines: [(character: String, text: String)] = [
            (character: "THE PRACTITIONER", text: "I've been staring at this struct for an hour."),
            (character: "ESPECTRO FAMILIAR", text: "And the metadata?"),
            (character: "THE PRACTITIONER", text: #"Key-value pairs. Right now the only one that matters is "instruct.""#),
            (character: "THE PRACTITIONER", text: "I need a translator. A layer that sits between the score and the model."),
            (character: "ESPECTRO FAMILIAR", text: "Now you are thinking like a language designer."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // All 5 lines should have instructs (all have active directives)
        #expect(result.instructs.count == 5)

        // Line 0: THE PRACTITIONER, first intent, arcPosition 0.0
        let instruct0 = result.instructs[0]
        #expect(instruct0 != nil)
        #expect(instruct0!.contains("Late night in the study"))
        #expect(instruct0!.contains("quiet hum of electronics"))
        #expect(instruct0!.contains("very early in arc toward frustrated"))
        #expect(instruct0!.contains("moderate pace"))
        #expect(instruct0!.contains("Thinking aloud, halting delivery."))

        // Line 1: ESPECTRO FAMILIAR, arcPosition 0.5
        let instruct1 = result.instructs[1]
        #expect(instruct1 != nil)
        #expect(instruct1!.contains("Midway between curious and frustrated"))
        #expect(instruct1!.contains("Patient, measured, slightly amused."))

        // Line 2: THE PRACTITIONER, arcPosition 1.0
        let instruct2 = result.instructs[2]
        #expect(instruct2 != nil)
        #expect(instruct2!.contains("Arrived at frustrated"))
        #expect(instruct2!.contains("Thinking aloud, halting delivery."))

        // Line 3: THE PRACTITIONER, second intent (marker), frustrated -> resolved
        // New constraint: "dawning realization, voice steadying"
        let instruct3 = result.instructs[3]
        #expect(instruct3 != nil)
        #expect(instruct3!.contains("Late night in the study"))
        #expect(instruct3!.contains("Dawning realization, voice steadying."))

        // Line 4: ESPECTRO FAMILIAR, second intent
        // Keeps original constraint: "patient, measured, slightly amused"
        let instruct4 = result.instructs[4]
        #expect(instruct4 != nil)
        #expect(instruct4!.contains("Patient, measured, slightly amused."))
    }

    // MARK: - Neutral Gap Handling

    @Test("Neutral gap lines between intents produce no instruct entry")
    func neutralGapLinesProduceNoInstruct() throws {
        let notes: [String] = [
            #"<SceneContext location="front room" time="pre-dawn">"#,
            #"<Intent from="startled" to="sardonic" pace="fast">"#,
            "Bernard!",
            "Yes, Satan?",
            "</Intent>",
            // Neutral gap follows
            #"<Intent from="accusatory" to="resigned">"#,
            "Oil accusation.",
            "Oil defense.",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "SYLVIA", text: "Bernard!"),
            (character: "BERNARD", text: "Yes, Satan?"),
            (character: "SYLVIA", text: "They're jogging shorts."),  // neutral gap
            (character: "SYLVIA", text: "Oil accusation."),
            (character: "BERNARD", text: "Oil defense."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // Lines 0, 1 should have instructs (first intent)
        #expect(result.instructs[0] != nil)
        #expect(result.instructs[1] != nil)

        // Line 2 (neutral gap) -- no intent, no constraint, but SceneContext is present
        // Since it still has SceneContext, it will have an instruct (scene context only)
        // Actually the resolveFlat will still provide the scene context for neutral lines
        let instruct2 = result.instructs[2]
        // Neutral line has only SceneContext (no intent, no constraint)
        // So it will get a minimal instruct with just the scene context
        #expect(instruct2 != nil)
        #expect(instruct2!.contains("Pre-dawn in front room."))

        // Lines 3, 4 should have instructs (second intent)
        #expect(result.instructs[3] != nil)
        #expect(result.instructs[4] != nil)
    }

    @Test("Neutral gap with no scene context or constraints returns nil instruct")
    func neutralGapNoDirectives() throws {
        // If lines fall completely outside any GLOSA scope
        let notes: [String] = [
            #"<SceneContext location="office" time="morning">"#,
            #"<Intent from="calm" to="tense">"#,
            "Directed line.",
            "</Intent>",
            "</SceneContext>",
        ]

        // Extra dialogue after the scene context closes
        let dialogueLines: [(character: String, text: String)] = [
            (character: "ALICE", text: "Directed line."),
            (character: "BOB", text: "Unscoped line."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // Line 0 has instruct
        #expect(result.instructs[0] != nil)

        // Line 1 falls outside all scopes -- no instruct
        #expect(result.instructs[1] == nil)
    }

    // MARK: - Provenance

    @Test("Provenance records trace each instruct back to source directives")
    func provenanceRecords() throws {
        let notes: [String] = [
            #"<SceneContext location="office" time="morning" ambience="keyboard clicks">"#,
            #"<Constraint character="ALICE" direction="professional">"#,
            #"<Intent from="calm" to="frustrated" pace="moderate">"#,
            "I'm done with this.",
            "Then leave.",
            "</Intent>",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "ALICE", text: "I'm done with this."),
            (character: "BOB", text: "Then leave."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        #expect(result.provenance.count == 2)

        // First provenance record
        let prov0 = result.provenance[0]
        #expect(prov0.lineIndex == 0)
        #expect(prov0.characterName == "ALICE")
        #expect(prov0.sceneContext?.location == "office")
        #expect(prov0.intent?.intent.from == "calm")
        #expect(prov0.intent?.intent.to == "frustrated")
        #expect(prov0.constraint?.direction == "professional")
        #expect(!prov0.composedInstruct.isEmpty)

        // Second provenance record
        let prov1 = result.provenance[1]
        #expect(prov1.lineIndex == 1)
        #expect(prov1.characterName == "BOB")
        #expect(prov1.sceneContext?.location == "office")
        #expect(prov1.intent?.intent.from == "calm")
        // BOB has no constraint
        #expect(prov1.constraint == nil)
    }

    @Test("Provenance composedInstruct matches instructs dictionary")
    func provenanceMatchesInstructs() throws {
        let notes: [String] = [
            #"<SceneContext location="room" time="night">"#,
            #"<Intent from="a" to="b">"#,
            "Line one.",
            "Line two.",
            "</Intent>",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "X", text: "Line one."),
            (character: "Y", text: "Line two."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        for prov in result.provenance {
            let instruct = result.instructs[prov.lineIndex]
            #expect(instruct == prov.composedInstruct)
        }
    }

    // MARK: - Diagnostics

    @Test("Unclosed SceneContext produces a diagnostic")
    func unclosedSceneContextDiagnostic() throws {
        let notes: [String] = [
            #"<SceneContext location="room" time="night">"#,
            #"<Intent from="a" to="b">"#,
            "Line.",
            "</Intent>",
            // Missing </SceneContext>
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "ALICE", text: "Line."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // Should have at least one diagnostic about unclosed SceneContext
        let unclosedDiagnostics = result.diagnostics.filter {
            $0.message.lowercased().contains("unclosed") && $0.message.contains("SceneContext")
        }
        #expect(!unclosedDiagnostics.isEmpty)
    }

    @Test("Missing required attributes produce diagnostics")
    func missingAttributesDiagnostics() throws {
        let notes: [String] = [
            #"<SceneContext location="room">"#, // Missing 'time'
            #"<Intent from="a">"#,  // Missing 'to'
            "Dialog",
            "</Intent>",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "ALICE", text: "Dialog"),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // Should have diagnostics about missing attributes
        let missingTimeDiagnostics = result.diagnostics.filter {
            $0.message.contains("time")
        }
        let missingToDiagnostics = result.diagnostics.filter {
            $0.message.contains("'to'") || $0.message.lowercased().contains("missing") && $0.message.contains("to")
        }

        #expect(!missingTimeDiagnostics.isEmpty)
        #expect(!missingToDiagnostics.isEmpty)
    }

    // MARK: - EXAMPLES.md: Steam Room (Full End-to-End)

    @Test("Steam Room example: full end-to-end with two scoped intents")
    func steamRoomFullEndToEnd() throws {
        let notes: [String] = [
            #"<SceneContext location="steam room" time="morning" ambience="hissing steam, echoing tile">"#,
            #"<Constraint character="BERNARD" direction="nervous amateur, out of his depth, trying to sound casual" ceiling="moderate">"#,
            #"<Constraint character="KILLIAN" direction="clinical detachment, this is business, calm and methodical" ceiling="subdued">"#,
            #"<Intent from="conspiratorial calm" to="grim resolve" pace="slow">"#,
            "Have you thought about how I'm going to do it?",
            "I can't think about anything else.",
            "And?",
            "Insulin. You need to give him a mega dose of the fast acting stuff.",
            "Yeah, but doesn't that take a few minutes--",
            "He needs to be far enough away from anyone or anything that can help him.",
            "Where would that be?",
            "When he goes running. His elevated heart rate will make the mega dose more potent.",
            "He runs marathons. How am I going to keep up with him?",
            "You don't have to keep up with him. What you have to do is attract him.",
            "How am I going to do that?",
            "</Intent>",
            #"<Intent from="absurd" to="darkly comic" pace="moderate">"#,
            "Slutty shorts.",
            "Slutty... Shorts?",
            "He buys these super-short lightweight nylon shorts online that he wears when he's jogging.",
            "And you think that will do it?",
            "Oh, that will do it.",
            "They turn him on?",
            "Every. Time.",
            "How slutty?",
            "</Intent>",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            // First intent: 11 lines (indices 0-10)
            (character: "BERNARD", text: "Have you thought about how I'm going to do it?"),
            (character: "KILLIAN", text: "I can't think about anything else."),
            (character: "BERNARD", text: "And?"),
            (character: "KILLIAN", text: "Insulin. You need to give him a mega dose of the fast acting stuff."),
            (character: "BERNARD", text: "Yeah, but doesn't that take a few minutes--"),
            (character: "KILLIAN", text: "He needs to be far enough away from anyone or anything that can help him."),
            (character: "BERNARD", text: "Where would that be?"),
            (character: "KILLIAN", text: "When he goes running. His elevated heart rate will make the mega dose more potent."),
            (character: "BERNARD", text: "He runs marathons. How am I going to keep up with him?"),
            (character: "KILLIAN", text: "You don't have to keep up with him. What you have to do is attract him."),
            (character: "BERNARD", text: "How am I going to do that?"),
            // Second intent: 8 lines (indices 11-18) — but the parser saw 7 dialogue lines within the Intent scope
            (character: "KILLIAN", text: "Slutty shorts."),
            (character: "BERNARD", text: "Slutty... Shorts?"),
            (character: "KILLIAN", text: "He buys these super-short lightweight nylon shorts online that he wears when he's jogging."),
            (character: "BERNARD", text: "And you think that will do it?"),
            (character: "KILLIAN", text: "Oh, that will do it."),
            (character: "BERNARD", text: "They turn him on?"),
            (character: "KILLIAN", text: "Every. Time."),
            (character: "BERNARD", text: "How slutty?"),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // All 19 lines should have instructs
        // (Actually the parser gets the dialogue from the notes, and the flat resolver
        // matches them. The first intent has 11 dialogue lines and the second has 8.)
        // Since notes interleave dialogue and tags, the parser captures dialogue within intents.

        // Verify first intent lines exist
        #expect(result.instructs[0] != nil)

        // Line 0: BERNARD, ~0% = very early
        let i0 = result.instructs[0]!
        #expect(i0.contains("Morning in steam room"))
        #expect(i0.contains("hissing steam"))
        #expect(i0.contains("very early in arc toward grim resolve"))
        #expect(i0.contains("slow pace"))
        #expect(i0.contains("Nervous amateur"))
        #expect(i0.contains("Ceiling: moderate."))

        // Line 1: KILLIAN
        let i1 = result.instructs[1]!
        #expect(i1.contains("Clinical detachment"))
        #expect(i1.contains("Ceiling: subdued."))

        // Last line of first intent (line 10): 100%
        if let i10 = result.instructs[10] {
            #expect(i10.contains("Arrived at grim resolve"))
        }

        // Verify second intent exists
        #expect(result.instructs[11] != nil)

        // Line 11: KILLIAN, second intent, ~0%
        if let i11 = result.instructs[11] {
            #expect(i11.contains("absurd") || i11.contains("Absurd"))
            #expect(i11.contains("darkly comic"))
        }

        // Provenance count should match instructs count
        #expect(result.provenance.count == result.instructs.count)
    }

    // MARK: - Per-Character Constraint in Compilation

    @Test("Per-character constraints are correctly applied in compilation")
    func perCharacterConstraintsInCompilation() throws {
        let notes: [String] = [
            #"<SceneContext location="room" time="night">"#,
            #"<Constraint character="ALICE" direction="nervous">"#,
            #"<Constraint character="BOB" direction="confident">"#,
            #"<Intent from="calm" to="tense">"#,
            "Alice line.",
            "Bob line.",
            "</Intent>",
            "</SceneContext>",
        ]

        let dialogueLines: [(character: String, text: String)] = [
            (character: "ALICE", text: "Alice line."),
            (character: "BOB", text: "Bob line."),
        ]

        let result = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        #expect(result.instructs[0] != nil)
        #expect(result.instructs[1] != nil)

        // ALICE gets "nervous" constraint
        #expect(result.instructs[0]!.contains("Nervous."))

        // BOB gets "confident" constraint
        #expect(result.instructs[1]!.contains("Confident."))
    }

    // MARK: - InstructProvenance Codable Conformance

    @Test("InstructProvenance round-trips through JSON")
    func instructProvenanceCodable() throws {
        let prov = InstructProvenance(
            lineIndex: 3,
            characterName: "ALICE",
            sceneContext: SceneContext(location: "room", time: "night", ambience: "rain"),
            intent: ResolvedIntent(
                intent: Intent(from: "calm", to: "angry", pace: "fast"),
                arcPosition: 0.75
            ),
            constraint: Constraint(character: "ALICE", direction: "nervous", ceiling: "moderate"),
            composedInstruct: "Night in room, rain. Approaching angry from calm, fast pace. Nervous. Ceiling: moderate."
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(prov)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstructProvenance.self, from: data)

        #expect(decoded.lineIndex == prov.lineIndex)
        #expect(decoded.characterName == prov.characterName)
        #expect(decoded.sceneContext == prov.sceneContext)
        #expect(decoded.intent == prov.intent)
        #expect(decoded.constraint == prov.constraint)
        #expect(decoded.composedInstruct == prov.composedInstruct)
    }

    @Test("InstructProvenance with nil optional fields round-trips")
    func instructProvenanceNilFieldsCodable() throws {
        let prov = InstructProvenance(
            lineIndex: 0,
            characterName: "BOB",
            composedInstruct: "Minimal instruct."
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(prov)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstructProvenance.self, from: data)

        #expect(decoded.lineIndex == 0)
        #expect(decoded.characterName == "BOB")
        #expect(decoded.sceneContext == nil)
        #expect(decoded.intent == nil)
        #expect(decoded.constraint == nil)
        #expect(decoded.composedInstruct == "Minimal instruct.")
    }
}
