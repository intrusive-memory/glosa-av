import Testing
import Foundation
import GlosaCore
import GlosaAnnotation
import SwiftCompartido

@Suite("GlosaSerializer FDX Tests")
struct GlosaSerializerFDXTests {

    // MARK: - Test Data

    /// An FDX document with GLOSA namespace elements matching the REQUIREMENTS.md Section 3.2 example.
    private let annotatedFDXXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="4"
                xmlns:glosa="https://intrusive-memory.productions/glosa">
      <Content>
        <glosa:SceneContext location="the study" time="late night" ambience="quiet hum of electronics">

          <Paragraph Type="Scene Heading">
            <Text>INT. THE STUDY - NIGHT</Text>
          </Paragraph>

          <glosa:Constraint character="THE PRACTITIONER"
                            direction="thinking aloud, halting delivery"/>
          <glosa:Constraint character="ESPECTRO FAMILIAR"
                            direction="patient, measured, slightly amused"/>

          <glosa:Intent from="curious" to="frustrated" pace="moderate">

            <Paragraph Type="Character">
              <Text>THE PRACTITIONER</Text>
            </Paragraph>
            <Paragraph Type="Dialogue">
              <Text>I've been staring at this struct for an hour.</Text>
            </Paragraph>

            <Paragraph Type="Character">
              <Text>ESPECTRO FAMILIAR</Text>
            </Paragraph>
            <Paragraph Type="Dialogue">
              <Text>And the metadata?</Text>
            </Paragraph>

          </glosa:Intent>

          <glosa:Intent from="frustrated" to="resolved" pace="decelerating"/>
          <glosa:Constraint character="THE PRACTITIONER"
                            direction="dawning realization, voice steadying"/>

          <Paragraph Type="Character">
            <Text>THE PRACTITIONER</Text>
          </Paragraph>
          <Paragraph Type="Dialogue">
            <Text>I need a translator. A layer that sits between the score and the model.</Text>
          </Paragraph>

          <Paragraph Type="Character">
            <Text>ESPECTRO FAMILIAR</Text>
          </Paragraph>
          <Paragraph Type="Dialogue">
            <Text>Now you are thinking like a language designer.</Text>
          </Paragraph>

        </glosa:SceneContext>
      </Content>
      <TitlePage>
        <Content/>
      </TitlePage>
    </FinalDraft>
    """

    // MARK: - Round-Trip Tests

    @Test("FDX round-trip: parse -> compile -> serialize -> parse produces identical GlosaScore")
    func fdxRoundTrip() throws {
        let fdxData = Data(annotatedFDXXML.utf8)

        // Step 1: Parse the FDX to extract GLOSA score.
        let parser = GlosaParser()
        let originalScore = parser.parseFDX(data: fdxData)

        // Verify the original score has expected structure.
        #expect(originalScore.scenes.count == 1, "Expected 1 scene")
        #expect(originalScore.scenes[0].intents.count == 2, "Expected 2 intents")

        // Step 2: Build a screenplay from the FDX elements (without GLOSA).
        // We need a GuionParsedElementCollection for the annotated screenplay.
        let screenplay = buildScreenplayFromFDXContent()

        // Step 3: Extract dialogue lines for compilation.
        let dialogueLines = extractDialogueLines(from: screenplay)

        // Step 4: Build notes for the compiler from the score.
        let notes = buildNotesFromScore(originalScore, dialogueLines: dialogueLines)

        // Step 5: Compile.
        let compiler = GlosaCompiler()
        let compilationResult = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        // Step 6: Build annotated screenplay.
        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: compilationResult,
            score: originalScore
        )

        // Step 7: Serialize to FDX.
        let serializer = GlosaSerializer()
        let serializedFDX = serializer.writeFDX(annotated)

        // Step 8: Parse the serialized FDX.
        let reparsedScore = parser.parseFDX(data: serializedFDX)

        // Verify the scores are structurally identical.
        #expect(originalScore.scenes.count == reparsedScore.scenes.count,
                "Scene count mismatch")

        for (sceneIdx, (origScene, reparsedScene)) in zip(originalScore.scenes, reparsedScore.scenes).enumerated() {
            #expect(origScene.context.location == reparsedScene.context.location,
                    "Scene \(sceneIdx): location mismatch")
            #expect(origScene.context.time == reparsedScene.context.time,
                    "Scene \(sceneIdx): time mismatch")
            #expect(origScene.context.ambience == reparsedScene.context.ambience,
                    "Scene \(sceneIdx): ambience mismatch")

            #expect(origScene.intents.count == reparsedScene.intents.count,
                    "Scene \(sceneIdx): intent count mismatch: original \(origScene.intents.count) vs reparsed \(reparsedScene.intents.count)")

            for (intentIdx, (origIntent, reparsedIntent)) in zip(origScene.intents, reparsedScene.intents).enumerated() {
                #expect(origIntent.intent.from == reparsedIntent.intent.from,
                        "Scene \(sceneIdx), Intent \(intentIdx): 'from' mismatch")
                #expect(origIntent.intent.to == reparsedIntent.intent.to,
                        "Scene \(sceneIdx), Intent \(intentIdx): 'to' mismatch")
                #expect(origIntent.intent.pace == reparsedIntent.intent.pace,
                        "Scene \(sceneIdx), Intent \(intentIdx): 'pace' mismatch")
                #expect(origIntent.intent.scoped == reparsedIntent.intent.scoped,
                        "Scene \(sceneIdx), Intent \(intentIdx): 'scoped' mismatch: original \(origIntent.intent.scoped) vs reparsed \(reparsedIntent.intent.scoped)")

                // Verify dialogue line counts match for scoped intents.
                if origIntent.intent.scoped {
                    #expect(origIntent.dialogueLines.count == reparsedIntent.dialogueLines.count,
                            "Scene \(sceneIdx), Intent \(intentIdx): dialogue line count mismatch")
                }
            }
        }
    }

    @Test("Serialized FDX output is valid XML with correct glosa: namespace")
    func serializedFDXIsValidXML() throws {
        let screenplay = buildScreenplayFromFDXContent()
        let score = buildTestScore()
        let dialogueLines = extractDialogueLines(from: screenplay)
        let notes = buildNotesFromScore(score, dialogueLines: dialogueLines)

        let compiler = GlosaCompiler()
        let compilationResult = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: compilationResult,
            score: score
        )

        let serializer = GlosaSerializer()
        let fdxData = serializer.writeFDX(annotated)

        // Verify it's valid XML by parsing it.
        let xmlParser = XMLParser(data: fdxData)
        let delegate = XMLValidationDelegate()
        xmlParser.delegate = delegate
        let success = xmlParser.parse()

        #expect(success, "Serialized FDX is not valid XML: \(delegate.errorMessage ?? "unknown error")")

        // Verify the content string contains the namespace declaration.
        let xmlString = String(data: fdxData, encoding: .utf8)!
        #expect(xmlString.contains("xmlns:glosa=\"https://intrusive-memory.productions/glosa\""))
        #expect(xmlString.contains("glosa:SceneContext"))
        #expect(xmlString.contains("glosa:Intent"))
        #expect(xmlString.contains("glosa:Constraint"))
        #expect(xmlString.contains("</glosa:SceneContext>"))
    }

    @Test("FDX serialization uses self-closing tags for marker Intents")
    func fdxMarkerIntentUsesSelfClosingTag() throws {
        let screenplay = buildScreenplayFromFDXContent()
        let score = buildTestScore()
        let dialogueLines = extractDialogueLines(from: screenplay)
        let notes = buildNotesFromScore(score, dialogueLines: dialogueLines)

        let compiler = GlosaCompiler()
        let compilationResult = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: compilationResult,
            score: score
        )

        let serializer = GlosaSerializer()
        let fdxData = serializer.writeFDX(annotated)
        let xmlString = String(data: fdxData, encoding: .utf8)!

        // The second intent is a marker (not scoped), so it should be self-closing.
        #expect(xmlString.contains("<glosa:Intent from=\"frustrated\" to=\"resolved\""),
                "Missing marker intent element")

        // Verify the scoped intent has opening and closing tags.
        #expect(xmlString.contains("</glosa:Intent>"),
                "Missing scoped intent closing tag")
    }

    @Test("FDX serialization uses self-closing tags for Constraints")
    func fdxConstraintUsesSelfClosingTag() throws {
        let screenplay = buildScreenplayFromFDXContent()
        let score = buildTestScore()
        let dialogueLines = extractDialogueLines(from: screenplay)
        let notes = buildNotesFromScore(score, dialogueLines: dialogueLines)

        let compiler = GlosaCompiler()
        let compilationResult = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: compilationResult,
            score: score
        )

        let serializer = GlosaSerializer()
        let fdxData = serializer.writeFDX(annotated)
        let xmlString = String(data: fdxData, encoding: .utf8)!

        // Constraints should be self-closing.
        #expect(xmlString.contains("<glosa:Constraint character=\"THE PRACTITIONER\""))
        #expect(xmlString.contains("/>"))
    }

    @Test("write() to .fdx file on disk")
    func writeToFDXFile() throws {
        let screenplay = buildScreenplayFromFDXContent()
        let score = buildTestScore()
        let dialogueLines = extractDialogueLines(from: screenplay)
        let notes = buildNotesFromScore(score, dialogueLines: dialogueLines)

        let compiler = GlosaCompiler()
        let compilationResult = try compiler.compile(
            fountainNotes: notes,
            dialogueLines: dialogueLines
        )

        let annotated = GlosaAnnotatedScreenplay.build(
            from: screenplay,
            compilationResult: compilationResult,
            score: score
        )

        let serializer = GlosaSerializer()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_serialized.fdx")

        try serializer.write(annotated, to: tempURL)

        // Read it back and verify it's valid XML.
        let data = try Data(contentsOf: tempURL)
        let xmlParser = XMLParser(data: data)
        let delegate = XMLValidationDelegate()
        xmlParser.delegate = delegate
        let success = xmlParser.parse()

        #expect(success, "Written FDX file is not valid XML")

        // Clean up.
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Empty score produces FDX without GLOSA elements")
    func emptyScoreProducesNoGlosaElements() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .character, elementText: "JOHN"),
            GuionElement(elementType: .dialogue, elementText: "Hello."),
        ]
        let screenplay = GuionParsedElementCollection(elements: elements)
        let annotated = GlosaAnnotatedScreenplay(
            screenplay: screenplay,
            annotatedElements: elements.map { GlosaAnnotatedElement(element: $0) },
            score: GlosaScore(),
            diagnostics: [],
            provenance: []
        )

        let serializer = GlosaSerializer()
        let fdxData = serializer.writeFDX(annotated)
        let xmlString = String(data: fdxData, encoding: .utf8)!

        // Should have the namespace declaration but no GLOSA elements.
        #expect(xmlString.contains("xmlns:glosa="))
        #expect(!xmlString.contains("<glosa:SceneContext"))
        #expect(!xmlString.contains("<glosa:Intent"))
        #expect(!xmlString.contains("<glosa:Constraint"))

        // Should still have the screenplay content.
        #expect(xmlString.contains("INT. OFFICE - DAY"))
        #expect(xmlString.contains("JOHN"))
        #expect(xmlString.contains("Hello."))
    }

    // MARK: - Helpers

    /// Build a screenplay matching the FDX test content.
    private func buildScreenplayFromFDXContent() -> GuionParsedElementCollection {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. THE STUDY - NIGHT"),
            GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
            GuionElement(elementType: .dialogue, elementText: "I've been staring at this struct for an hour."),
            GuionElement(elementType: .character, elementText: "ESPECTRO FAMILIAR"),
            GuionElement(elementType: .dialogue, elementText: "And the metadata?"),
            GuionElement(elementType: .character, elementText: "THE PRACTITIONER"),
            GuionElement(elementType: .dialogue, elementText: "I need a translator. A layer that sits between the score and the model."),
            GuionElement(elementType: .character, elementText: "ESPECTRO FAMILIAR"),
            GuionElement(elementType: .dialogue, elementText: "Now you are thinking like a language designer."),
        ]
        return GuionParsedElementCollection(elements: elements)
    }

    /// Build the test score matching the REQUIREMENTS.md Section 3.2 example.
    private func buildTestScore() -> GlosaScore {
        let sceneContext = SceneContext(
            location: "the study",
            time: "late night",
            ambience: "quiet hum of electronics"
        )

        let scopedIntent = GlosaScore.IntentEntry(
            intent: Intent(
                from: "curious",
                to: "frustrated",
                pace: "moderate",
                spacing: nil,
                scoped: true,
                lineCount: 2
            ),
            constraints: [
                Constraint(character: "THE PRACTITIONER", direction: "thinking aloud, halting delivery"),
                Constraint(character: "ESPECTRO FAMILIAR", direction: "patient, measured, slightly amused"),
            ],
            dialogueLines: [
                "I've been staring at this struct for an hour.",
                "And the metadata?",
            ]
        )

        let markerIntent = GlosaScore.IntentEntry(
            intent: Intent(
                from: "frustrated",
                to: "resolved",
                pace: "decelerating",
                spacing: nil,
                scoped: false,
                lineCount: nil
            ),
            constraints: [
                Constraint(character: "THE PRACTITIONER", direction: "dawning realization, voice steadying"),
            ],
            dialogueLines: [
                "I need a translator. A layer that sits between the score and the model.",
                "Now you are thinking like a language designer.",
            ]
        )

        let scene = GlosaScore.SceneEntry(
            context: sceneContext,
            intents: [scopedIntent, markerIntent]
        )

        return GlosaScore(scenes: [scene])
    }

    /// Extract dialogue lines from a screenplay.
    private func extractDialogueLines(
        from screenplay: GuionParsedElementCollection
    ) -> [(character: String, text: String)] {
        var dialogueLines: [(character: String, text: String)] = []
        var lastCharacterName = ""

        for element in screenplay.elements {
            switch element.elementType {
            case .character:
                lastCharacterName = element.elementText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            case .dialogue:
                dialogueLines.append((character: lastCharacterName, text: element.elementText))
            default:
                break
            }
        }

        return dialogueLines
    }

    /// Build notes array from a GlosaScore for the compiler.
    private func buildNotesFromScore(
        _ score: GlosaScore,
        dialogueLines: [(character: String, text: String)]
    ) -> [String] {
        var notes: [String] = []

        for scene in score.scenes {
            // Scene context opening.
            var sceneTag = "<SceneContext location=\"\(scene.context.location)\" time=\"\(scene.context.time)\""
            if let ambience = scene.context.ambience {
                sceneTag += " ambience=\"\(ambience)\""
            }
            sceneTag += ">"
            notes.append(sceneTag)

            for (intentIndex, intentEntry) in scene.intents.enumerated() {
                // Constraints (emit scene-level constraints before the first intent).
                if intentIndex == 0 {
                    for constraint in intentEntry.constraints {
                        var constraintTag = "<Constraint character=\"\(constraint.character)\" direction=\"\(constraint.direction)\""
                        if let register = constraint.register {
                            constraintTag += " register=\"\(register)\""
                        }
                        if let ceiling = constraint.ceiling {
                            constraintTag += " ceiling=\"\(ceiling)\""
                        }
                        constraintTag += ">"
                        notes.append(constraintTag)
                    }
                } else {
                    for constraint in intentEntry.constraints {
                        var constraintTag = "<Constraint character=\"\(constraint.character)\" direction=\"\(constraint.direction)\""
                        if let register = constraint.register {
                            constraintTag += " register=\"\(register)\""
                        }
                        if let ceiling = constraint.ceiling {
                            constraintTag += " ceiling=\"\(ceiling)\""
                        }
                        constraintTag += ">"
                        notes.append(constraintTag)
                    }
                }

                // Intent opening.
                var intentTag = "<Intent from=\"\(intentEntry.intent.from)\" to=\"\(intentEntry.intent.to)\""
                if let pace = intentEntry.intent.pace {
                    intentTag += " pace=\"\(pace)\""
                }
                intentTag += ">"
                notes.append(intentTag)

                // Dialogue lines.
                for line in intentEntry.dialogueLines {
                    notes.append(line)
                }

                // Intent closing (only for scoped).
                if intentEntry.intent.scoped {
                    notes.append("</Intent>")
                }
            }

            notes.append("</SceneContext>")
        }

        return notes
    }
}

// MARK: - XML Validation Helper

/// A simple XMLParser delegate that records whether parsing succeeded.
private final class XMLValidationDelegate: NSObject, XMLParserDelegate {
    var errorMessage: String?

    func parser(
        _ parser: XMLParser,
        parseErrorOccurred parseError: Error
    ) {
        errorMessage = parseError.localizedDescription
    }

    func parser(
        _ parser: XMLParser,
        validationErrorOccurred validationError: Error
    ) {
        errorMessage = validationError.localizedDescription
    }
}
