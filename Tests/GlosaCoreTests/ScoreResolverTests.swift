import Foundation
import Testing
@testable import GlosaCore

/// Tests for the `ScoreResolver` — verifies arc position computation,
/// neutral delivery gaps, per-character constraint independence, and
/// SceneContext scope resets.
@Suite("ScoreResolver Tests")
struct ScoreResolverTests {

    let resolver = ScoreResolver()

    // MARK: - (a) Scoped Intent Arc Positions

    @Test("Scoped intent with 3 lines produces arc positions 0.0, 0.5, 1.0")
    func scopedIntentThreeLines() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "office", time: "morning"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "angry",
                            scoped: true,
                            lineCount: 3
                        ),
                        dialogueLines: ["Line A", "Line B", "Line C"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results.count == 3)
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[1].intent?.arcPosition == 0.5)
        #expect(results[2].intent?.arcPosition == 1.0)
    }

    @Test("Scoped intent with 1 line produces arc position 0.0")
    func scopedIntentSingleLine() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "night"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "happy",
                            to: "sad",
                            scoped: true,
                            lineCount: 1
                        ),
                        dialogueLines: ["Only line"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results.count == 1)
        #expect(results[0].intent?.arcPosition == 0.0)
    }

    @Test("Scoped intent with 5 lines produces evenly spaced arc positions")
    func scopedIntentFiveLines() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "park", time: "dusk"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "nervous",
                            to: "confident",
                            scoped: true,
                            lineCount: 5
                        ),
                        dialogueLines: ["L1", "L2", "L3", "L4", "L5"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results.count == 5)
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[1].intent?.arcPosition == 0.25)
        #expect(results[2].intent?.arcPosition == 0.5)
        #expect(results[3].intent?.arcPosition == 0.75)
        #expect(results[4].intent?.arcPosition == 1.0)
    }

    @Test("Scoped intent preserves intent attributes through resolution")
    func scopedIntentPreservesAttributes() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "study", time: "late night", ambience: "hum"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "curious",
                            to: "frustrated",
                            pace: "moderate",
                            spacing: "beat",
                            scoped: true,
                            lineCount: 2
                        ),
                        dialogueLines: ["First", "Second"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results[0].intent?.intent.from == "curious")
        #expect(results[0].intent?.intent.to == "frustrated")
        #expect(results[0].intent?.intent.pace == "moderate")
        #expect(results[0].intent?.intent.spacing == "beat")
    }

    // MARK: - (b) Marker Intent Approximate Positions

    @Test("Marker intent with known dialogue lines uses linear interpolation")
    func markerIntentKnownLines() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "trail", time: "dawn"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "anxious",
                            to: "panicked",
                            scoped: false,
                            lineCount: nil
                        ),
                        dialogueLines: ["Line 1", "Line 2", "Line 3"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results.count == 3)
        // Marker with 3 known dialogue lines: linear interpolation
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[1].intent?.arcPosition == 0.5)
        #expect(results[2].intent?.arcPosition == 1.0)
    }

    @Test("Marker intent with single line produces 0.5 blend")
    func markerIntentSingleLine() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "noon"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "tense",
                            scoped: false,
                            lineCount: nil
                        ),
                        dialogueLines: ["Solo line"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)

        #expect(results.count == 1)
        // Single-line marker with no lineCount: steady 0.5 blend
        #expect(results[0].intent?.arcPosition == 0.5)
    }

    // MARK: - (c) Neutral Delivery Between Intents

    @Test("Neutral delivery between scoped intents produces nil intent")
    func neutralDeliveryBetweenIntents() {
        // Build a score with two scoped intents.
        // The flat resolver handles neutral gaps between them.
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "evening"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "startled",
                            to: "sardonic",
                            scoped: true,
                            lineCount: 2
                        ),
                        dialogueLines: ["Line A", "Line B"]
                    ),
                    .init(
                        intent: Intent(
                            from: "accusatory",
                            to: "resigned",
                            scoped: true,
                            lineCount: 2
                        ),
                        dialogueLines: ["Line D", "Line E"]
                    )
                ]
            )
        ])

        // The flat dialogue list includes a neutral line between the two intents.
        let allDialogue = ["Line A", "Line B", "Neutral line C", "Line D", "Line E"]
        let characterNames = ["ALICE", "BOB", "ALICE", "BOB", "ALICE"]

        let results = resolver.resolveFlat(
            score: score,
            dialogueLines: allDialogue,
            characterNames: characterNames
        )

        #expect(results.count == 5)

        // Lines 0-1: first intent active
        #expect(results[0].intent != nil)
        #expect(results[0].intent?.intent.from == "startled")
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[1].intent != nil)
        #expect(results[1].intent?.arcPosition == 1.0)

        // Line 2: neutral gap (no intent active)
        #expect(results[2].intent == nil)
        #expect(results[2].sceneContext != nil) // SceneContext still active

        // Lines 3-4: second intent active
        #expect(results[3].intent != nil)
        #expect(results[3].intent?.intent.from == "accusatory")
        #expect(results[3].intent?.arcPosition == 0.0)
        #expect(results[4].intent != nil)
        #expect(results[4].intent?.arcPosition == 1.0)
    }

    @Test("All lines after last intent and before scene close are neutral")
    func neutralAfterLastIntent() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "office", time: "morning"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "tense",
                            scoped: true,
                            lineCount: 1
                        ),
                        dialogueLines: ["Directed line"]
                    )
                ]
            )
        ])

        let allDialogue = ["Directed line", "Neutral line 1", "Neutral line 2"]
        let characterNames = ["ALICE", "ALICE", "BOB"]

        let results = resolver.resolveFlat(
            score: score,
            dialogueLines: allDialogue,
            characterNames: characterNames
        )

        #expect(results.count == 3)
        #expect(results[0].intent != nil)
        // Lines after the intent in the same scene get nil intent
        // but the scene context is no longer tracked since the scene
        // intents have been exhausted. The flat resolver moves on.
        // Lines 1-2 fall after the scene's intents are exhausted,
        // so they get nil for everything (after the scene scope).
        #expect(results[1].intent == nil)
        #expect(results[2].intent == nil)
    }

    // MARK: - (d) Per-Character Constraint Independence

    @Test("Per-character constraints are independent: changing A does not affect B")
    func perCharacterConstraintIndependence() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "study", time: "night"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "tense",
                            scoped: true,
                            lineCount: 2
                        ),
                        constraints: [
                            Constraint(character: "ALICE", direction: "nervous"),
                            Constraint(character: "BOB", direction: "confident"),
                        ],
                        dialogueLines: ["Alice speaks", "Bob speaks"]
                    ),
                    .init(
                        intent: Intent(
                            from: "tense",
                            to: "resolved",
                            scoped: true,
                            lineCount: 2
                        ),
                        constraints: [
                            // Only ALICE's constraint changes; BOB keeps his
                            Constraint(character: "ALICE", direction: "relieved"),
                        ],
                        dialogueLines: ["Alice speaks again", "Bob speaks again"]
                    )
                ]
            )
        ])

        let characterNames = ["ALICE", "BOB", "ALICE", "BOB"]
        let results = resolver.resolve(score: score, characterNames: characterNames)

        #expect(results.count == 4)

        // First intent: ALICE has "nervous", BOB has "confident"
        #expect(results[0].constraint?.character == "ALICE")
        #expect(results[0].constraint?.direction == "nervous")
        #expect(results[1].constraint?.character == "BOB")
        #expect(results[1].constraint?.direction == "confident")

        // Second intent: ALICE changed to "relieved", BOB still "confident"
        #expect(results[2].constraint?.character == "ALICE")
        #expect(results[2].constraint?.direction == "relieved")
        #expect(results[3].constraint?.character == "BOB")
        #expect(results[3].constraint?.direction == "confident")
    }

    @Test("Constraints for different characters coexist independently")
    func multipleCharacterConstraintsCoexist() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "evening"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "guarded",
                            to: "open",
                            scoped: true,
                            lineCount: 4
                        ),
                        constraints: [
                            Constraint(character: "ALICE", direction: "cautious", ceiling: "moderate"),
                            Constraint(character: "BOB", direction: "aggressive", ceiling: "intense"),
                            Constraint(character: "CHARLIE", direction: "neutral", ceiling: "subdued"),
                        ],
                        dialogueLines: ["Alice line", "Bob line", "Charlie line", "Alice again"]
                    )
                ]
            )
        ])

        let characterNames = ["ALICE", "BOB", "CHARLIE", "ALICE"]
        let results = resolver.resolve(score: score, characterNames: characterNames)

        #expect(results.count == 4)
        #expect(results[0].constraint?.direction == "cautious")
        #expect(results[0].constraint?.ceiling == "moderate")
        #expect(results[1].constraint?.direction == "aggressive")
        #expect(results[1].constraint?.ceiling == "intense")
        #expect(results[2].constraint?.direction == "neutral")
        #expect(results[2].constraint?.ceiling == "subdued")
        // ALICE's constraint unchanged for her second line
        #expect(results[3].constraint?.direction == "cautious")
        #expect(results[3].constraint?.ceiling == "moderate")
    }

    @Test("Constraint for unknown character returns nil")
    func constraintForUnknownCharacter() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "noon"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "tense",
                            scoped: true,
                            lineCount: 2
                        ),
                        constraints: [
                            Constraint(character: "ALICE", direction: "nervous"),
                        ],
                        dialogueLines: ["Alice line", "Unknown character line"]
                    )
                ]
            )
        ])

        let characterNames = ["ALICE", "UNKNOWN"]
        let results = resolver.resolve(score: score, characterNames: characterNames)

        #expect(results.count == 2)
        #expect(results[0].constraint?.direction == "nervous")
        // UNKNOWN has no constraint
        #expect(results[1].constraint == nil)
    }

    // MARK: - (e) SceneContext Scope Reset

    @Test("SceneContext scope reset: constraints and intents from scene 1 do not leak to scene 2")
    func sceneContextScopeReset() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "office", time: "morning"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "calm",
                            to: "angry",
                            scoped: true,
                            lineCount: 1
                        ),
                        constraints: [
                            Constraint(character: "ALICE", direction: "professional"),
                        ],
                        dialogueLines: ["Scene 1 line"]
                    )
                ]
            ),
            .init(
                context: SceneContext(location: "park", time: "afternoon"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "happy",
                            to: "sad",
                            scoped: true,
                            lineCount: 1
                        ),
                        // No constraints in scene 2
                        dialogueLines: ["Scene 2 line"]
                    )
                ]
            )
        ])

        let characterNames = ["ALICE", "ALICE"]
        let results = resolver.resolve(score: score, characterNames: characterNames)

        #expect(results.count == 2)

        // Scene 1: ALICE has constraint and intent, office context
        #expect(results[0].sceneContext?.location == "office")
        #expect(results[0].intent?.intent.from == "calm")
        #expect(results[0].constraint?.direction == "professional")

        // Scene 2: fresh context, no carryover of scene 1 constraint
        #expect(results[1].sceneContext?.location == "park")
        #expect(results[1].intent?.intent.from == "happy")
        #expect(results[1].constraint == nil) // Reset: scene 1 constraint gone
    }

    @Test("SceneContext change resets all constraints")
    func sceneContextChangeResetsConstraints() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "lab", time: "night"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "focused",
                            to: "distracted",
                            scoped: true,
                            lineCount: 2
                        ),
                        constraints: [
                            Constraint(character: "DR SMITH", direction: "methodical"),
                            Constraint(character: "NURSE", direction: "impatient"),
                        ],
                        dialogueLines: ["Smith line", "Nurse line"]
                    )
                ]
            ),
            .init(
                context: SceneContext(location: "hallway", time: "night"),
                intents: [
                    .init(
                        intent: Intent(
                            from: "urgent",
                            to: "calm",
                            scoped: true,
                            lineCount: 2
                        ),
                        // Only DR SMITH gets a new constraint in scene 2
                        constraints: [
                            Constraint(character: "DR SMITH", direction: "urgent"),
                        ],
                        dialogueLines: ["Smith in hallway", "Nurse in hallway"]
                    )
                ]
            )
        ])

        let characterNames = ["DR SMITH", "NURSE", "DR SMITH", "NURSE"]
        let results = resolver.resolve(score: score, characterNames: characterNames)

        #expect(results.count == 4)

        // Scene 1
        #expect(results[0].constraint?.direction == "methodical")
        #expect(results[1].constraint?.direction == "impatient")

        // Scene 2: NURSE's scene 1 constraint did NOT carry over
        #expect(results[2].constraint?.direction == "urgent")
        #expect(results[3].constraint == nil) // NURSE has no constraint in scene 2
    }

    // MARK: - Full Integration: REQUIREMENTS.md Section 3.1 via Parser + Resolver

    @Test("End-to-end: parse REQUIREMENTS.md example then resolve directives")
    func endToEndRequirementsExample() {
        let parser = GlosaParser()

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

        let score = parser.parseFountain(notes: notes)
        #expect(score.scenes.count == 1)

        // Character names for the 5 dialogue lines (3 in first intent, 2 in second)
        let characterNames = [
            "THE PRACTITIONER",
            "ESPECTRO FAMILIAR",
            "THE PRACTITIONER",
            "THE PRACTITIONER",
            "ESPECTRO FAMILIAR",
        ]

        let results = resolver.resolve(score: score, characterNames: characterNames)
        #expect(results.count == 5)

        // First intent (scoped, 3 lines): curious -> frustrated
        #expect(results[0].intent?.intent.from == "curious")
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[0].sceneContext?.location == "the study")
        #expect(results[0].constraint?.direction == "thinking aloud, halting delivery")

        #expect(results[1].intent?.arcPosition == 0.5)
        #expect(results[1].constraint?.direction == "patient, measured, slightly amused")

        #expect(results[2].intent?.arcPosition == 1.0)
        #expect(results[2].constraint?.direction == "thinking aloud, halting delivery")

        // Second intent (marker, 2 lines): frustrated -> resolved
        // THE PRACTITIONER got a new constraint, ESPECTRO FAMILIAR keeps the old one
        #expect(results[3].intent?.intent.from == "frustrated")
        #expect(results[3].intent?.intent.to == "resolved")
        #expect(results[3].constraint?.direction == "dawning realization, voice steadying")

        #expect(results[4].constraint?.direction == "patient, measured, slightly amused")
    }

    // MARK: - resolveFlat with Neutral Gaps (REQUIREMENTS.md Section 2 example)

    @Test("resolveFlat handles neutral gap between scoped intents")
    func resolveFlatNeutralGap() {
        let parser = GlosaParser()

        // Bernard and Sylvia example: two scoped intents with neutral lines between
        let notes: [String] = [
            #"<SceneContext location="front room" time="pre-dawn">"#,
            #"<Constraint character="SYLVIA" direction="imperious">"#,
            #"<Constraint character="BERNARD" direction="impatient">"#,
            #"<Intent from="startled" to="sardonic" pace="fast">"#,
            "Bernard!",
            "Yes, Satan?",
            "</Intent>",
            // Neutral gap: no intent active
            #"<Intent from="accusatory" to="resigned" pace="accelerating">"#,
            "You've been using my baby oil.",
            "I haven't touched your baby oil.",
            "</Intent>",
            "</SceneContext>",
        ]

        let score = parser.parseFountain(notes: notes)
        #expect(score.scenes.count == 1)
        #expect(score.scenes[0].intents.count == 2)

        // Full dialogue list including a neutral line between intents
        let allDialogue = [
            "Bernard!",
            "Yes, Satan?",
            "They're jogging shorts.",  // neutral gap
            "You've been using my baby oil.",
            "I haven't touched your baby oil.",
        ]
        let characterNames = ["SYLVIA", "BERNARD", "BERNARD", "SYLVIA", "BERNARD"]

        let results = resolver.resolveFlat(
            score: score,
            dialogueLines: allDialogue,
            characterNames: characterNames
        )

        #expect(results.count == 5)

        // Lines 0-1: first intent (startled -> sardonic)
        #expect(results[0].intent != nil)
        #expect(results[0].intent?.intent.from == "startled")
        #expect(results[0].intent?.arcPosition == 0.0)
        #expect(results[0].constraint?.direction == "imperious") // SYLVIA
        #expect(results[1].intent?.arcPosition == 1.0)
        #expect(results[1].constraint?.direction == "impatient") // BERNARD

        // Line 2: neutral gap -- scene context still active, constraints persist
        #expect(results[2].intent == nil)
        #expect(results[2].sceneContext?.location == "front room")
        #expect(results[2].constraint?.direction == "impatient") // BERNARD's constraint persists

        // Lines 3-4: second intent (accusatory -> resigned)
        #expect(results[3].intent != nil)
        #expect(results[3].intent?.intent.from == "accusatory")
        #expect(results[3].intent?.arcPosition == 0.0)
        #expect(results[4].intent?.arcPosition == 1.0)
    }

    // MARK: - Edge Cases

    @Test("Empty score produces empty results")
    func emptyScore() {
        let score = GlosaScore(scenes: [])
        let results = resolver.resolve(score: score)
        #expect(results.isEmpty)
    }

    @Test("Scene with no intents produces no results from resolve")
    func sceneWithNoIntents() {
        let score = GlosaScore(scenes: [
            .init(context: SceneContext(location: "room", time: "noon"))
        ])
        let results = resolver.resolve(score: score)
        #expect(results.isEmpty)
    }

    @Test("SceneContext is set on all resolved lines within a scene")
    func sceneContextSetOnAllLines() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "study", time: "late night", ambience: "electronics"),
                intents: [
                    .init(
                        intent: Intent(from: "a", to: "b", scoped: true, lineCount: 2),
                        dialogueLines: ["First", "Second"]
                    )
                ]
            )
        ])

        let results = resolver.resolve(score: score)
        #expect(results.count == 2)
        #expect(results[0].sceneContext?.location == "study")
        #expect(results[0].sceneContext?.ambience == "electronics")
        #expect(results[1].sceneContext?.location == "study")
    }

    @Test("No character names means no constraints resolved")
    func noCharacterNamesNoConstraints() {
        let score = GlosaScore(scenes: [
            .init(
                context: SceneContext(location: "room", time: "noon"),
                intents: [
                    .init(
                        intent: Intent(from: "a", to: "b", scoped: true, lineCount: 1),
                        constraints: [Constraint(character: "ALICE", direction: "nervous")],
                        dialogueLines: ["A line"]
                    )
                ]
            )
        ])

        // No character names provided
        let results = resolver.resolve(score: score, characterNames: nil)
        #expect(results.count == 1)
        #expect(results[0].constraint == nil)
    }

    // MARK: - ResolvedDirectives and ResolvedIntent Equatable

    @Test("ResolvedDirectives conforms to Equatable")
    func resolvedDirectivesEquatable() {
        let a = ResolvedDirectives(
            sceneContext: SceneContext(location: "room", time: "night"),
            intent: ResolvedIntent(
                intent: Intent(from: "a", to: "b"),
                arcPosition: 0.5
            ),
            constraint: Constraint(character: "X", direction: "calm")
        )
        let b = ResolvedDirectives(
            sceneContext: SceneContext(location: "room", time: "night"),
            intent: ResolvedIntent(
                intent: Intent(from: "a", to: "b"),
                arcPosition: 0.5
            ),
            constraint: Constraint(character: "X", direction: "calm")
        )
        #expect(a == b)
    }

    @Test("ResolvedDirectives with nil fields are equal")
    func resolvedDirectivesNilEquality() {
        let a = ResolvedDirectives()
        let b = ResolvedDirectives()
        #expect(a == b)
    }

    @Test("ResolvedIntent conforms to Equatable")
    func resolvedIntentEquatable() {
        let a = ResolvedIntent(
            intent: Intent(from: "calm", to: "angry"),
            arcPosition: 0.75
        )
        let b = ResolvedIntent(
            intent: Intent(from: "calm", to: "angry"),
            arcPosition: 0.75
        )
        #expect(a == b)
    }
}
