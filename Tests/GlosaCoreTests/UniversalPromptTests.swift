import Foundation
import Testing

@testable import GlosaCore

/// Tests for the **universal `prompt` attribute** — a freeform audio-intent
/// string carried on *every* GLOSA directive. GlosaCore never interprets it; it
/// parses `prompt="…"` from both Fountain and FDX, transports it through the
/// compiler untouched, and surfaces it on the output DTOs so the downstream
/// orchestrator can forward it to the audio model.
///
/// Coverage mirrors the per-archetype checklist:
/// - **Scope** (`SceneContext`/`Intent`/`Constraint`) → combined into
///   `GlosaLineAnnotation.prompt`.
/// - **Point** (`<breath/>`/`<pause/>`) → `breathPrompts` / `PausePointDTO.prompt`.
/// - **Block** (`<include/>`) → `Include.prompt` (and `<shot>` keeps its existing
///   `prompt`, decision ①).
@Suite("Universal prompt attribute")
struct UniversalPromptTests {

  let parser = GlosaParser()

  // MARK: - Fountain parsing (scope directives)

  @Test("Fountain: SceneContext/Intent/Constraint carry prompt")
  func fountainScopePrompts() throws {
    let notes = [
      #"<SceneContext location="alley" time="night" prompt="rain hiss on wet brick">"#,
      #"<Intent from="calm" to="afraid" prompt="breath tightening across the beat">"#,
      #"<Constraint character="MARA" direction="whispering" prompt="barely voiced, throat-tight">"#,
      "They're still out there.",
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)

    let scene = try #require(score.scenes.first)
    #expect(scene.context.prompt == "rain hiss on wet brick")

    let intentEntry = try #require(scene.intents.first)
    #expect(intentEntry.intent.prompt == "breath tightening across the beat")

    let constraint = try #require(intentEntry.constraints.first)
    #expect(constraint.prompt == "barely voiced, throat-tight")
  }

  @Test("Fountain: absent prompt stays nil")
  func fountainPromptAbsentIsNil() throws {
    let notes = [
      #"<SceneContext location="alley" time="night">"#,
      #"<Intent from="calm" to="afraid">"#,
      "Line.",
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)
    let scene = try #require(score.scenes.first)
    #expect(scene.context.prompt == nil)
    #expect(scene.intents.first?.intent.prompt == nil)
  }

  // MARK: - Fountain parsing (point directives)

  @Test("Fountain: <breath prompt=…> carries prompt")
  func fountainBreathPrompt() throws {
    let notes = [
      #"<SceneContext location="office" time="day">"#,
      #"<Intent from="calm" to="calm">"#,
      #"Halt[[<breath prompt="a caught breath"/>]] and listen."#,
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)
    let breath = try #require(score.breaths.first)
    #expect(breath.prompt == "a caught breath")
  }

  @Test("Fountain: <pause prompt=…> carries prompt (the plastic-bag example)")
  func fountainPausePrompt() throws {
    let notes = [
      #"<SceneContext location="parking lot" time="dusk">"#,
      #"<Intent from="tense" to="tense">"#,
      #"Say something.[[<pause prompt="silence as a plastic grocery bag blows between them"/>]]"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)
    let pause = try #require(score.pauses.first)
    #expect(pause.prompt == "silence as a plastic grocery bag blows between them")
  }

  @Test("Fountain: <breath after=… prompt=…> carries prompt on the after path")
  func fountainBreathAfterPrompt() throws {
    let notes = [
      #"<SceneContext location="office" time="day">"#,
      #"<Intent from="calm" to="calm">"#,
      #"One two three.[[<breath after="One" prompt="quick inhale"/>]]"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)
    let breath = try #require(score.breaths.first)
    #expect(breath.prompt == "quick inhale")
    #expect(breath.characterOffset == 3)  // after "One"
  }

  // MARK: - Fountain parsing (block events)

  @Test("Fountain: <include prompt=…> carries prompt")
  func fountainIncludePrompt() throws {
    let notes = [
      #"<include src="sting.wav" prompt="distant thunder rolling in">"#
    ]
    let score = parser.parseFountain(notes: notes)
    let include = try #require(score.includes.first)
    #expect(include.src == "sting.wav")
    #expect(include.prompt == "distant thunder rolling in")
  }

  @Test("Fountain: <shot> keeps its existing (image) prompt — decision ①")
  func fountainShotPromptUnchanged() throws {
    let notes = [
      #"<shot prompt="wide shot, rain-slicked street" aspect="wide">"#
    ]
    let score = parser.parseFountain(notes: notes)
    let shot = try #require(score.shots.first)
    #expect(shot.prompt == "wide shot, rain-slicked street")
  }

  // MARK: - FDX parsing

  private func fdxXML(bodyInsideIntent: String, sceneAttrs: String = "", intentAttrs: String = "")
    -> Data
  {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:SceneContext location="alley" time="night"\(sceneAttrs)>
            <glosa:Intent from="calm" to="afraid"\(intentAttrs)>
              <Paragraph Type="Character"><Text>MARA</Text></Paragraph>
              <Paragraph Type="Dialogue">\(bodyInsideIntent)</Paragraph>
            </glosa:Intent>
          </glosa:SceneContext>
        </Content>
      </FinalDraft>
      """
    return xml.data(using: .utf8)!
  }

  @Test("FDX: SceneContext/Intent prompt attributes parse")
  func fdxScopePrompts() throws {
    let data = fdxXML(
      bodyInsideIntent: "<Text>Line.</Text>",
      sceneAttrs: #" prompt="rain hiss""#,
      intentAttrs: #" prompt="breath tightening""#)
    let score = parser.parseFDX(data: data)
    let scene = try #require(score.scenes.first)
    #expect(scene.context.prompt == "rain hiss")
    #expect(scene.intents.first?.intent.prompt == "breath tightening")
  }

  @Test("FDX: <glosa:pause prompt=…> carries prompt")
  func fdxPausePrompt() throws {
    let data = fdxXML(
      bodyInsideIntent:
        #"<Text>Wait</Text><glosa:pause prompt="a bag blows past"/><Text> here.</Text>"#)
    let score = parser.parseFDX(data: data)
    let pause = try #require(score.pauses.first)
    #expect(pause.prompt == "a bag blows past")
  }

  @Test("FDX: <glosa:breath prompt=…> carries prompt")
  func fdxBreathPrompt() throws {
    let data = fdxXML(
      bodyInsideIntent:
        #"<Text>Wait</Text><glosa:breath prompt="sharp inhale"/><Text> here.</Text>"#)
    let score = parser.parseFDX(data: data)
    let breath = try #require(score.breaths.first)
    #expect(breath.prompt == "sharp inhale")
  }

  @Test("FDX: <glosa:include prompt=…> carries prompt")
  func fdxIncludePrompt() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:include src="sting.wav" prompt="distant thunder"/>
        </Content>
      </FinalDraft>
      """
    let score = parser.parseFDX(data: xml.data(using: .utf8)!)
    let include = try #require(score.includes.first)
    #expect(include.prompt == "distant thunder")
  }

  // MARK: - Compiler projection (point directives)

  @Test("Compiler: pause prompt projects onto PausePoint")
  func compilerPausePointPrompt() throws {
    let notes = [
      #"<SceneContext location="lot" time="dusk">"#,
      #"<Intent from="tense" to="tense">"#,
      #"Say it.[[<pause prompt="wind through the lot"/>]]"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let compiler = GlosaCompiler()
    let result = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: [(character: "X", text: "Say it.")])
    let points = try #require(result.pausePoints[0])
    #expect(points.first?.prompt == "wind through the lot")
  }

  // MARK: - Compiler / DTO surfacing (scope combined)

  @Test("compileScript: scope prompts combine into GlosaLineAnnotation.prompt")
  func scopePromptsCombine() throws {
    let notes = [
      #"<SceneContext location="alley" time="night" prompt="rain hiss">"#,
      #"<Intent from="calm" to="afraid" prompt="breath tightening">"#,
      #"<Constraint character="MARA" direction="whispering" prompt="throat-tight">"#,
      "They're still out there.",
      "</Intent>",
      "</SceneContext>",
    ]
    let script = try compileScript(
      fountainNotes: notes,
      rawDialogueLines: [(character: "MARA", rawText: "They're still out there.")])
    let line = try #require(script.lines[0])
    // scene → intent → constraint order, space-joined.
    #expect(line.prompt == "rain hiss breath tightening throat-tight")
  }

  @Test("compileScript: line with no scope prompt has nil prompt")
  func scopePromptNilWhenNone() throws {
    let notes = [
      #"<SceneContext location="alley" time="night">"#,
      #"<Intent from="calm" to="afraid">"#,
      "Plain line.",
      "</Intent>",
      "</SceneContext>",
    ]
    let script = try compileScript(
      fountainNotes: notes,
      rawDialogueLines: [(character: "MARA", rawText: "Plain line.")])
    #expect(script.lines[0]?.prompt == nil)
  }

  // MARK: - DTO surfacing (point + block)

  @Test("compileScript: breathPrompts parallels breathOffsets; pause + include prompts surface")
  func dtoPointAndBlockPrompts() throws {
    let notes = [
      #"<include src="bed.wav" prompt="low drone under the scene">"#,
      #"<SceneContext location="office" time="day">"#,
      #"<Intent from="calm" to="calm">"#,
      #"Halt[[<breath prompt="a caught breath"/>]] and[[<pause prompt="dead air"/>]] listen."#,
      "</Intent>",
      "</SceneContext>",
    ]
    let raw =
      "Halt[[<breath prompt=\"a caught breath\"/>]] and[[<pause prompt=\"dead air\"/>]] listen."
    let script = try compileScript(
      fountainNotes: notes,
      rawDialogueLines: [(character: "X", rawText: raw)])

    let line = try #require(script.lines[0])
    #expect(line.breathOffsets.count == 1)
    #expect(line.breathPrompts == ["a caught breath"])
    #expect(line.pausePoints.first?.prompt == "dead air")

    let include = try #require(script.includes.first)
    #expect(include.prompt == "low drone under the scene")
  }

  // MARK: - Validator

  @Test("Validator: empty prompt=\"\" warns with .promptEmpty")
  func validatorEmptyPromptWarns() throws {
    let notes = [
      #"<SceneContext location="alley" time="night" prompt="">"#,
      #"<Intent from="calm" to="afraid">"#,
      "Line.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let validator = GlosaValidator()
    let diags = validator.validate(score: result.score)
    #expect(diags.contains { $0.code == .promptEmpty })
  }

  @Test("Validator: non-empty prompt produces no .promptEmpty")
  func validatorNonEmptyPromptClean() throws {
    let notes = [
      #"<SceneContext location="alley" time="night" prompt="rain hiss">"#,
      #"<Intent from="calm" to="afraid">"#,
      "Line.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let diags = GlosaValidator().validate(score: result.score)
    #expect(!diags.contains { $0.code == .promptEmpty })
  }

  // MARK: - Codable

  @Test("Codable: models round-trip prompt")
  func modelsRoundTripPrompt() throws {
    let pause = Pause(
      sceneIndex: 0, dialogueLineIndex: 0, characterOffset: 3, length: .beat,
      prompt: "a bag blows past")
    let data = try JSONEncoder().encode(pause)
    let decoded = try JSONDecoder().decode(Pause.self, from: data)
    #expect(decoded.prompt == "a bag blows past")
  }

  @Test("Codable: GlosaLineAnnotation decodes legacy JSON without prompt fields")
  func annotationDecodesLegacyJSON() throws {
    // JSON that predates `breathPrompts` / `prompt` — both keys absent.
    let legacy = """
      {
        "spokenText": "Hello.",
        "breathOffsets": [],
        "breathStrengths": [],
        "pausePoints": []
      }
      """
    let decoded = try JSONDecoder().decode(
      GlosaLineAnnotation.self, from: Data(legacy.utf8))
    #expect(decoded.breathPrompts.isEmpty)
    #expect(decoded.prompt == nil)
    #expect(decoded.spokenText == "Hello.")
  }

  @Test("Codable: PausePointDTO decodes legacy JSON without prompt")
  func pausePointDTODecodesLegacyJSON() throws {
    let legacy = #"{"offset": 4, "lengthMs": 1000, "named": "beat"}"#
    let decoded = try JSONDecoder().decode(PausePointDTO.self, from: Data(legacy.utf8))
    #expect(decoded.prompt == nil)
    #expect(decoded.lengthMs == 1000)
  }
}
