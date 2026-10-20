import Foundation
import Testing

@testable import GlosaCore

/// Tests for reading notation 2.0 block directives — Fountain notes whose
/// trimmed content is a JSON object with a single `shot` or `include` key —
/// in the parser, the validator, and the compile path.
@Suite("Notation 2.0 block directives (parser, validator, compile path)")
struct NotationTwoParserTests {

  let parser = GlosaParser()

  /// The REQUIREMENTS § 1.1 example, verbatim.
  static let requirementsExample = """
    [[ {"shot": {
      "prompt": "A lighthouse keeper climbs the spiral stair at dusk, lantern in hand",
      "caption": "The light has to be lit by nine.",
      "style": "ink wash, muted blue palette",
      "model": "klein4b",
      "aspect": "wide",
      "ref": ["KEEPER", "lighthouse-interior.png"],
      "output": "storyboards/keeper-01.png"
    }} ]]

    [[ {"include": {"src": "audio/surf.m4a", "gain": -12.0, "mode": "bed"}} ]]
    """

  /// The contents of every `[[ … ]]` note in `fountain`, in document order.
  static func noteContents(_ fountain: String) -> [String] {
    let regex = try! NSRegularExpression(
      pattern: #"\[\[(.*?)\]\]"#, options: [.dotMatchesLineSeparators])
    let range = NSRange(fountain.startIndex..., in: fountain)
    return regex.matches(in: fountain, range: range).map {
      String(fountain[Range($0.range(at: 1), in: fountain)!])
    }
  }

  private func diagnostics(
    _ result: (score: GlosaScore, diagnostics: [GlosaDiagnostic]),
    _ code: GlosaDiagnostic.Code
  ) -> [GlosaDiagnostic] {
    result.diagnostics.filter { $0.code == code }
  }

  // MARK: - Acceptance

  @Test("Acceptance 2: the REQ § 1.1 example parses to a Shot and an Include")
  func acceptance2RequirementsExample() throws {
    let notes = Self.noteContents(Self.requirementsExample)
    #expect(notes.count == 2)

    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.diagnostics.isEmpty)

    let shot = try #require(result.score.shots.first)
    #expect(result.score.shots.count == 1)
    #expect(shot.documentIndex == 0)
    #expect(shot.prompt == "A lighthouse keeper climbs the spiral stair at dusk, lantern in hand")
    #expect(shot.caption == "The light has to be lit by nine.")
    #expect(shot.style == "ink wash, muted blue palette")
    #expect(shot.model == "klein4b")
    #expect(shot.aspect == "wide")
    #expect(shot.ref == ["KEEPER", "lighthouse-interior.png"])
    #expect(shot.output == "storyboards/keeper-01.png")
    #expect(shot.extraAttributes.isEmpty)

    let include = try #require(result.score.includes.first)
    #expect(result.score.includes.count == 1)
    #expect(include.documentIndex == 1)
    #expect(include.src == "audio/surf.m4a")
    #expect(include.gain == -12.0)
    #expect(include.mode == .bed)
  }

  // MARK: - Candidate detection

  @Test("Candidate test: `{` then optional whitespace (incl. newlines) then `\"`")
  func candidateDetection() {
    #expect(GlosaParser.isBlockDirectiveCandidate(#"{"shot": {}}"#))
    #expect(GlosaParser.isBlockDirectiveCandidate(#"{ "shot": {}}"#))
    #expect(GlosaParser.isBlockDirectiveCandidate("{\n\t \"shot\": {}}"))
    #expect(!GlosaParser.isBlockDirectiveCandidate("{beat} Fine."))
    #expect(!GlosaParser.isBlockDirectiveCandidate("{}"))
    #expect(!GlosaParser.isBlockDirectiveCandidate("{ "))
    #expect(!GlosaParser.isBlockDirectiveCandidate(#""{"shot"}"#))
    #expect(!GlosaParser.isBlockDirectiveCandidate(#"<shot prompt="x"/>"#))
    #expect(!GlosaParser.isBlockDirectiveCandidate(""))
  }

  @Test("`{ \"shot\": …}` with whitespace after the brace is detected")
  func whitespaceAfterBraceDetected() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"  { "shot": {"prompt": "spaced"}}  "#,
      "{\n  \"shot\": {\"prompt\": \"newline\"}}",
    ])
    #expect(result.score.shots.map(\.prompt) == ["spaced", "newline"])
    #expect(result.score.shots.map(\.documentIndex) == [0, 1])
    #expect(result.diagnostics.isEmpty)
  }

  // MARK: - Keys and types

  @Test("Every shot key decodes with its JSON type")
  func everyShotKey() throws {
    let note = """
      {"shot": {
        "prompt": "p", "caption": "c", "style": "s", "model": "m", "aspect": "portrait",
        "width": 1024, "height": 768, "steps": 4, "guidance": 3.5, "seed": 42,
        "negative": "n", "lora": "l", "loraScale": 0.75, "ref": ["A", "B, with comma"],
        "character": "KEEPER", "output": "o.png", "preview": true, "telemetry": false
      }}
      """
    let result = parser.parseFountainWithDiagnostics(notes: [note])
    #expect(result.diagnostics.isEmpty)
    let shot = try #require(result.score.shots.first)
    #expect(
      shot
        == Shot(
          documentIndex: 0, prompt: "p", caption: "c", style: "s", model: "m",
          aspect: "portrait", width: 1024, height: 768, steps: 4, guidance: 3.5, seed: 42,
          negative: "n", lora: "l", loraScale: 0.75, output: "o.png", preview: true,
          telemetry: false, ref: ["A", "B, with comma"], character: "KEEPER"))
  }

  @Test("Every include key decodes with its JSON type")
  func everyIncludeKey() throws {
    let note =
      #"{"include": {"src": "a.wav", "gain": -3, "mode": "overlay", "fadeIn": 0.5, "fadeOut": 1.25, "prompt": "rain"}}"#
    let include = try #require(parser.parseFountain(notes: [note]).includes.first)
    #expect(include.src == "a.wav")
    #expect(include.gain == -3)
    #expect(include.mode == .overlay)
    #expect(include.fadeIn == 0.5)
    #expect(include.fadeOut == 1.25)
    #expect(include.prompt == "rain")
  }

  @Test("`ref` is an array of strings; entries may contain commas")
  func refArray() throws {
    let note = #"{"shot": {"prompt": "p", "ref": ["SMITH, JOHN", "b.png", "C"]}}"#
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.ref == ["SMITH, JOHN", "b.png", "C"])
  }

  @Test("A defaults shot (no prompt) decodes with an empty prompt")
  func defaultsShot() throws {
    let note = #"{"shot": {"style": "charcoal", "model": "klein4b"}}"#
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.prompt == "")
    #expect(shot.style == "charcoal")
  }

  @Test("`seed` accepts an integer above 2^53 as a decimal string")
  func seedAsString() throws {
    let note = #"{"shot": {"prompt": "p", "seed": "18446744073709551615"}}"#
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.seed == UInt64.max)
  }

  @Test("Unknown keys are preserved in read order with their JSON types")
  func unknownKeysPreserved() throws {
    let note = """
      {"shot": {"zeta": "s", "prompt": "p", "alpha": 1.5, "flag": true, "none": null,
        "list": [1, "two"], "obj": {"k": "v"}}}
      """
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.prompt == "p")
    #expect(
      shot.extraAttributes == [
        GlosaJSONMember(key: "zeta", value: .string("s")),
        GlosaJSONMember(key: "alpha", value: .number(1.5)),
        GlosaJSONMember(key: "flag", value: .bool(true)),
        GlosaJSONMember(key: "none", value: .null),
        GlosaJSONMember(key: "list", value: .array([.number(1), .string("two")])),
        GlosaJSONMember(
          key: "obj", value: .object([GlosaJSONMember(key: "k", value: .string("v"))])),
      ])

    let include = try #require(
      parser.parseFountain(notes: [#"{"include": {"src": "a.wav", "duck": -6}}"#]).includes.first)
    #expect(include.extraAttributes == [GlosaJSONMember(key: "duck", value: .number(-6))])
  }

  @Test("D-4: an unrecognized include mode is nil, not an error")
  func unknownIncludeMode() throws {
    let result = parser.parseFountainWithDiagnostics(notes: [
      #"{"include": {"src": "a.wav", "mode": "sideways"}}"#
    ])
    #expect(result.diagnostics.isEmpty)
    #expect(result.score.includes.first?.mode == nil)
  }

  @Test("Multi-line note parses")
  func multiLineNote() throws {
    let note = "\n{\"shot\": {\n  \"prompt\": \"line one\",\n  \"style\": \"ink\"\n}}\n"
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.prompt == "line one")
    #expect(shot.style == "ink")
  }

  @Test("Escaped `]]` and `[[` decode inside JSON strings")
  func escapedBrackets() throws {
    let note = #"{"shot": {"prompt": "close ]] open [[ end"}}"#
    let shot = try #require(parser.parseFountain(notes: [note]).shots.first)
    #expect(shot.prompt == "close ]] open [[ end")
  }

  // MARK: - Invalid notes

  @Test("Invalid JSON → invalidBlockDirectiveJSON error with line and column; no event")
  func invalidJSONWithPosition() throws {
    let notes = [
      "{\"shot\": {\n  \"prompt\": \"x\"\n  \"style\": \"y\"\n}}",
      #"{"shot": {"prompt": "x",}}"#,
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.shots.isEmpty)

    let errors = diagnostics(result, .invalidBlockDirectiveJSON)
    #expect(errors.count == 2)
    #expect(errors.allSatisfy { $0.severity == .error })
    #expect(errors.map(\.line) == [1, 2])
    #expect(errors[0].message.contains("line 3, column "))
    #expect(errors[1].message.contains("line 1, column "))
  }

  @Test("A `{\"`-prefixed note that is not JSON is reported, not swallowed as dialogue")
  func notJSONReported() throws {
    let notes = [
      #"<SceneContext location="hall" time="day">"#,
      #"<Intent from="calm" to="calm">"#,
      #"{"so I said," she laughs."#,
      "Next line.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let errors = diagnostics(result, .invalidBlockDirectiveJSON)
    #expect(errors.count == 1)
    #expect(errors.first?.line == 3)
    #expect(result.score.scenes[0].intents[0].dialogueLines == ["Next line."])
  }

  @Test("Wrong shapes → unknownBlockDirective warning; no event")
  func wrongShapes() throws {
    let notes = [
      #"{"panel": {"prompt": "p"}}"#,
      #"{"shot": {"prompt": "p"}, "include": {"src": "a.wav"}}"#,
      #"{"": 1}"#,
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.shots.isEmpty)
    #expect(result.score.includes.isEmpty)
    let warnings = diagnostics(result, .unknownBlockDirective)
    #expect(warnings.count == 3)
    #expect(warnings.allSatisfy { $0.severity == .warning })
    #expect(warnings.map(\.line) == [1, 2, 3])
    #expect(warnings[0].message.contains("\"panel\""))
    #expect(result.diagnostics.count == 3)
  }

  @Test("D-3: schema mismatches → invalidBlockDirectiveJSON error naming the key")
  func schemaMismatches() throws {
    let notes = [
      #"{"shot": {"prompt": "p", "width": "wide"}}"#,
      #"{"include": {"gain": -6}}"#,
      #"{"shot": "a lighthouse"}"#,
      #"{"shot": {"ref": "A,B"}}"#,
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.score.shots.isEmpty)
    #expect(result.score.includes.isEmpty)
    let errors = diagnostics(result, .invalidBlockDirectiveJSON)
    #expect(errors.count == 4)
    #expect(errors.allSatisfy { $0.severity == .error })
    #expect(errors[0].message.contains("\"width\""))
    #expect(errors[1].message.contains("\"src\""))
    #expect(errors[2].message.contains("\"shot\""))
    #expect(errors[3].message.contains("\"ref\""))
  }

  // MARK: - Ordering and isolation from tag handling

  @Test("JSON value containing `</Intent>` / `<SceneContext` is not read as a tag")
  func jsonValueContainingTagsParser() throws {
    let notes = [
      #"<SceneContext location="hall" time="day">"#,
      #"<Intent from="calm" to="tense">"#,
      "First.",
      #"{"shot": {"prompt": "sign reads </Intent> and <SceneContext x> and <shot y/>"}}"#,
      "Second.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    #expect(result.diagnostics.isEmpty)
    #expect(result.score.scenes.count == 1)
    #expect(result.score.scenes[0].intents.count == 1)
    #expect(result.score.scenes[0].intents[0].dialogueLines == ["First.", "Second."])
    #expect(result.score.scenes[0].intents[0].intent.scoped)
    #expect(result.score.shots.count == 1)
    #expect(result.score.shots[0].documentIndex == 3)
  }

  @Test("Validator skips JSON candidates, including values containing tags")
  func jsonValueContainingTagsValidator() {
    let notes = [
      #"{"shot": {"prompt": "</SceneContext> </Intent>"}}"#,
      #"<SceneContext location="hall" time="day">"#,
      #"{"include": {"src": "<SceneContext location=\"\">"}}"#,
      #"<Intent from="calm" to="tense">"#,
      #"{"shot": {"prompt": "<Intent> nested <Constraint>"}}"#,
      "Line.",
      "</Intent>",
      "</SceneContext>",
    ]
    #expect(GlosaValidator().validate(notes: notes).isEmpty)
  }

  @Test("JSON and 1.0 tag block directives share document order")
  func mixedDocumentOrder() throws {
    let notes = [
      #"<shot prompt="one"/>"#,
      #"{"shot": {"prompt": "two"}}"#,
      #"<include src="a.wav"/>"#,
      #"{"include": {"src": "b.wav"}}"#,
    ]
    let score = parser.parseFountain(notes: notes)
    #expect(score.shots.map(\.documentIndex) == [0, 1])
    #expect(score.shots.map(\.prompt) == ["one", "two"])
    #expect(score.includes.map(\.documentIndex) == [2, 3])
    #expect(score.includes.map(\.src) == ["a.wav", "b.wav"])
  }

  // MARK: - Notation 1.0 deprecation

  @Test("Each 1.0 <shot/>/<include/> yields one deprecatedTagDirective info")
  func deprecatedTagInfo() throws {
    let notes = [
      #"<shot prompt="a"/>"#,
      "Prose.",
      #"<include src="a.wav"/>"#,
      #"{"shot": {"prompt": "b"}}"#,
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)
    let infos = diagnostics(result, .deprecatedTagDirective)
    #expect(infos.count == 2)
    #expect(infos.allSatisfy { $0.severity == .info })
    #expect(infos.map(\.line) == [1, 3])
    #expect(infos[0].message.contains(#"{"shot""#))
    #expect(infos[1].message.contains(#"{"include""#))
    #expect(result.diagnostics.count == 2)
  }

  // MARK: - `{beat}` regression

  @Test("`{beat} Fine.` inside an <Intent> stays dialogue; indices and offsets unchanged")
  func beatProseRegression() throws {
    let baseline = [
      #"<SceneContext location="kitchen" time="night">"#,
      #"<Intent from="calm" to="tense">"#,
      "{beat} Fine.",
      "Then[[<breath/>]] more.",
      "Wait[[<pause/>]] here.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: baseline)
    #expect(result.diagnostics.isEmpty)
    let intent = result.score.scenes[0].intents[0]
    #expect(intent.dialogueLines == ["{beat} Fine.", "Then more.", "Wait here."])
    #expect(result.score.breaths.map(\.dialogueLineIndex) == [1])
    #expect(result.score.breaths.map(\.characterOffset) == [4])
    #expect(result.score.pauses.map(\.dialogueLineIndex) == [2])
    #expect(result.score.pauses.map(\.characterOffset) == [4])

    // Interleaving JSON block directives changes no dialogue index or offset.
    var withJSON = baseline
    withJSON.insert(#"{"shot": {"prompt": "kitchen"}}"#, at: 3)
    withJSON.insert(#"{"bogus": 1}"#, at: 5)
    let result2 = parser.parseFountainWithDiagnostics(notes: withJSON)
    #expect(result2.score.scenes == result.score.scenes)
    #expect(result2.score.breaths.map(\.dialogueLineIndex) == [1])
    #expect(result2.score.breaths.map(\.characterOffset) == [4])
    #expect(result2.score.pauses.map(\.dialogueLineIndex) == [2])
    #expect(result2.score.pauses.map(\.characterOffset) == [4])
  }

  // MARK: - Compile path

  @Test("Compile surfaces an invalid JSON shot as an error diagnostic")
  func compileSurfacesInvalidJSON() throws {
    let notes = [
      #"<SceneContext location="hall" time="day">"#,
      #"<Intent from="calm" to="calm">"#,
      "Hello.",
      #"{"shot": {"prompt": "unterminated}}"#,
      #"{"shot": {"prompt": "valid"}}"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = try GlosaCompiler().compile(
      fountainNotes: notes, dialogueLines: [(character: "A", text: "Hello.")])
    let errors = result.diagnostics.filter { $0.code == .invalidBlockDirectiveJSON }
    #expect(errors.count == 1)
    #expect(errors.first?.severity == .error)
    #expect(errors.first?.line == 4)
    #expect(result.shots.map(\.prompt) == ["valid"])
    #expect(result.instructs[0] != nil)
  }

  @Test("Compile surfaces the deprecation info for a 1.0 shot")
  func compileSurfacesDeprecation() throws {
    let result = try GlosaCompiler().compile(
      fountainNotes: [#"<shot prompt="a"/>"#], dialogueLines: [])
    #expect(result.diagnostics.filter { $0.code == .deprecatedTagDirective }.count == 1)
  }

  @Test("D-7: parser diagnostics the validator already reports are not duplicated")
  func compileDedupe() {
    let validator = [
      GlosaDiagnostic(severity: .warning, message: "Same text", line: 2),
      GlosaDiagnostic(
        severity: .error, message: "validator wording", line: 4,
        code: .invalidBlockDirectiveJSON),
    ]
    let parser = [
      GlosaDiagnostic(severity: .warning, message: "Same text", line: 2),  // dup (message)
      GlosaDiagnostic(severity: .warning, message: "Same text", line: 3),  // other line
      GlosaDiagnostic(
        severity: .error, message: "parser wording", line: 4,
        code: .invalidBlockDirectiveJSON),  // dup (code)
      GlosaDiagnostic(
        severity: .warning, message: "w", line: 4, code: .unknownBlockDirective),  // other code
      GlosaDiagnostic(severity: .info, message: "repeat", line: 9),
      GlosaDiagnostic(severity: .info, message: "repeat", line: 9),  // parser repeats stay
    ]
    let merged = GlosaCompiler.appendingParserDiagnostics(parser, to: validator)
    #expect(merged.count == 6)
    #expect(Array(merged.prefix(2)) == validator)
    #expect(merged[2].line == 3)
    #expect(merged[3].code == .unknownBlockDirective)
    #expect(merged[4] == merged[5])
  }
}
