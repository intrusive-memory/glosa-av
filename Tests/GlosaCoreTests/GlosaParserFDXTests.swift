import Foundation
import Testing

@testable import GlosaCore

/// Tests for the FDX (Final Draft XML) extraction mode of `GlosaParser`.
///
/// Parses the FDX example from REQUIREMENTS.md Section 3.2 and verifies the resulting
/// `GlosaScore` matches the equivalent Fountain parse output.
@Suite("GlosaParser FDX Extraction Tests")
struct GlosaParserFDXTests {

  let parser = GlosaParser()

  // MARK: - REQUIREMENTS.md Section 3.2 Example

  /// The FDX example from REQUIREMENTS.md Section 3.2:
  /// THE PRACTITIONER and ESPECTRO FAMILIAR in the study.
  /// This should produce the same GlosaScore structure as the Fountain version.
  @Test("Parses REQUIREMENTS.md Section 3.2 FDX example")
  func parseRequirementsSection32() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
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

          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let data = xml.data(using: .utf8)!
    let score = parser.parseFDX(data: data)

    // Should have 1 scene
    #expect(score.scenes.count == 1)

    let scene = score.scenes[0]

    // SceneContext attributes should match
    #expect(scene.context.location == "the study")
    #expect(scene.context.time == "late night")
    #expect(scene.context.ambience == "quiet hum of electronics")

    // Should have 2 intents
    #expect(scene.intents.count == 2)

    // First intent: scoped (curious -> frustrated) with 2 dialogue lines
    let intent1 = scene.intents[0]
    #expect(intent1.intent.from == "curious")
    #expect(intent1.intent.to == "frustrated")
    #expect(intent1.intent.pace == "moderate")
    #expect(intent1.intent.scoped == true)
    #expect(intent1.intent.lineCount == 2)
    #expect(intent1.dialogueLines.count == 2)
    #expect(intent1.dialogueLines[0] == "I've been staring at this struct for an hour.")
    #expect(intent1.dialogueLines[1] == "And the metadata?")

    // First intent constraints: the two scene-level constraints
    #expect(intent1.constraints.count == 2)
    #expect(intent1.constraints[0].character == "THE PRACTITIONER")
    #expect(intent1.constraints[0].direction == "thinking aloud, halting delivery")
    #expect(intent1.constraints[1].character == "ESPECTRO FAMILIAR")
    #expect(intent1.constraints[1].direction == "patient, measured, slightly amused")

    // Second intent: marker (self-closing <glosa:Intent .../>)
    let intent2 = scene.intents[1]
    #expect(intent2.intent.from == "frustrated")
    #expect(intent2.intent.to == "resolved")
    #expect(intent2.intent.pace == "decelerating")
    #expect(intent2.intent.scoped == false)
    #expect(intent2.intent.lineCount == nil)

    // Marker intent should collect dialogue that follows it until scope closes
    #expect(intent2.dialogueLines.count == 1)
    #expect(
      intent2.dialogueLines[0]
        == "I need a translator. A layer that sits between the score and the model.")

    // Second intent constraints: THE PRACTITIONER replacement
    #expect(intent2.constraints.count == 1)
    #expect(intent2.constraints[0].character == "THE PRACTITIONER")
    #expect(intent2.constraints[0].direction == "dawning realization, voice steadying")
  }

  // MARK: - Structural Equivalence

  @Test("FDX and Fountain produce equivalent SceneContext attributes")
  func fountainFDXSceneContextEquivalence() throws {
    // Fountain version
    let fountainNotes: [String] = [
      #"<SceneContext location="the study" time="late night" ambience="quiet hum of electronics">"#,
      #"<Intent from="curious" to="frustrated">"#,
      "A test line.",
      "</Intent>",
      "</SceneContext>",
    ]

    // FDX version
    let fdxXML = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="the study" time="late night" ambience="quiet hum of electronics">
            <glosa:Intent from="curious" to="frustrated">
              <Paragraph Type="Character">
                <Text>A</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>A test line.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let fountainScore = parser.parseFountain(notes: fountainNotes)
    let fdxScore = parser.parseFDX(data: fdxXML.data(using: .utf8)!)

    // Both should have 1 scene with matching context
    #expect(fountainScore.scenes.count == fdxScore.scenes.count)
    #expect(fountainScore.scenes[0].context == fdxScore.scenes[0].context)
  }

  @Test("FDX and Fountain produce equivalent Intent attributes")
  func fountainFDXIntentEquivalence() throws {
    // Fountain version
    let fountainNotes: [String] = [
      #"<SceneContext location="room" time="day">"#,
      #"<Intent from="calm" to="angry" pace="fast">"#,
      "Test dialogue.",
      "</Intent>",
      "</SceneContext>",
    ]

    // FDX version
    let fdxXML = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="room" time="day">
            <glosa:Intent from="calm" to="angry" pace="fast">
              <Paragraph Type="Character">
                <Text>A</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Test dialogue.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let fountainScore = parser.parseFountain(notes: fountainNotes)
    let fdxScore = parser.parseFDX(data: fdxXML.data(using: .utf8)!)

    let fountainIntent = fountainScore.scenes[0].intents[0].intent
    let fdxIntent = fdxScore.scenes[0].intents[0].intent

    #expect(fountainIntent.from == fdxIntent.from)
    #expect(fountainIntent.to == fdxIntent.to)
    #expect(fountainIntent.pace == fdxIntent.pace)
    #expect(fountainIntent.scoped == fdxIntent.scoped)
  }

  // MARK: - FDX-Specific Features

  @Test("Self-closing glosa:Intent is parsed as marker")
  func selfClosingIntent() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="park" time="dusk">
            <glosa:Intent from="nervous" to="relieved" pace="slow"/>
            <Paragraph Type="Character">
              <Text>A</Text>
            </Paragraph>
            <Paragraph Type="Dialogue">
              <Text>Hello there.</Text>
            </Paragraph>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let score = parser.parseFDX(data: xml.data(using: .utf8)!)

    #expect(score.scenes.count == 1)
    #expect(score.scenes[0].intents.count == 1)

    let intent = score.scenes[0].intents[0]
    #expect(intent.intent.from == "nervous")
    #expect(intent.intent.to == "relieved")
    #expect(intent.intent.scoped == false)
    #expect(intent.intent.lineCount == nil)
    #expect(intent.dialogueLines.count == 1)
    #expect(intent.dialogueLines[0] == "Hello there.")
  }

  @Test("Self-closing glosa:Constraint is parsed correctly")
  func selfClosingConstraint() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="office" time="morning">
            <glosa:Constraint character="BOB" direction="tired and irritable" ceiling="moderate"/>
            <glosa:Intent from="bored" to="engaged">
              <Paragraph Type="Character">
                <Text>BOB</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>What now?</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let score = parser.parseFDX(data: xml.data(using: .utf8)!)

    #expect(score.scenes.count == 1)
    #expect(score.scenes[0].intents.count == 1)

    let intent = score.scenes[0].intents[0]
    #expect(intent.constraints.count == 1)
    #expect(intent.constraints[0].character == "BOB")
    #expect(intent.constraints[0].direction == "tired and irritable")
    #expect(intent.constraints[0].ceiling == "moderate")
  }

  @Test("Empty FDX produces empty score")
  func emptyFDX() {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4">
        <Content>
          <Paragraph Type="Scene Heading">
            <Text>INT. ROOM - DAY</Text>
          </Paragraph>
        </Content>
      </FinalDraft>
      """

    let score = parser.parseFDX(data: xml.data(using: .utf8)!)
    #expect(score.scenes.isEmpty)
  }

  @Test("FDX with multiple scenes")
  func multipleFDXScenes() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="office" time="morning">
            <glosa:Intent from="calm" to="tense">
              <Paragraph Type="Character">
                <Text>A</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Good morning.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
          <glosa:SceneContext location="street" time="night">
            <glosa:Intent from="nervous" to="brave">
              <Paragraph Type="Character">
                <Text>B</Text>
              </Paragraph>
              <Paragraph Type="Dialogue">
                <Text>Let's go.</Text>
              </Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """

    let score = parser.parseFDX(data: xml.data(using: .utf8)!)

    #expect(score.scenes.count == 2)
    #expect(score.scenes[0].context.location == "office")
    #expect(score.scenes[0].context.time == "morning")
    #expect(score.scenes[1].context.location == "street")
    #expect(score.scenes[1].context.time == "night")
  }
}
