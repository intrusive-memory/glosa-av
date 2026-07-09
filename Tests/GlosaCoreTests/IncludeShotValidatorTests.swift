import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaValidator`'s advisory checks on the `<include>` and `<shot>`
/// block events. All checks are warnings — the value is always carried through;
/// `model`/`aspect` are not hard-coupled to Vinetas's enums.
@Suite("GlosaValidator include/shot rules")
struct IncludeShotValidatorTests {

  let validator = GlosaValidator()

  @Test("<include> missing src → includeMissingSrc warning")
  func includeMissingSrc() throws {
    let score = GlosaScore(includes: [Include(documentIndex: 0, src: "")])
    let diags = validator.validate(score: score)

    #expect(diags.contains { $0.code == .includeMissingSrc && $0.severity == .warning })
  }

  @Test("Valid <include> produces no diagnostics")
  func includeValid() throws {
    let score = GlosaScore(includes: [Include(documentIndex: 0, src: "ok.wav")])
    #expect(validator.validate(score: score).isEmpty)
  }

  @Test("<shot> with empty prompt is a defaults declaration → no warning, carried through")
  func shotEmptyPromptIsDefaults() throws {
    // By convention a no-prompt <shot> sets defaults for subsequent shots; it
    // is NOT missing-prompt. The validator must not flag it, and the shot is
    // still carried through (recognizable by its empty prompt).
    let score = GlosaScore(shots: [Shot(documentIndex: 0, prompt: "", model: "klein4b")])
    let diags = validator.validate(score: score)

    #expect(!diags.contains { $0.code == .shotMissingPrompt })
    #expect(diags.isEmpty)
    #expect(score.shots.first?.prompt.isEmpty == true)
  }

  @Test("<shot> unknown model → shotUnknownModel warning, value carried")
  func shotUnknownModel() throws {
    let score = GlosaScore(shots: [Shot(documentIndex: 0, prompt: "p", model: "sd-xl")])
    let diags = validator.validate(score: score)

    #expect(diags.contains { $0.code == .shotUnknownModel })
    // The validator only warns — the score still carries the raw value.
    #expect(score.shots.first?.model == "sd-xl")
  }

  @Test("<shot> unknown aspect → shotUnknownAspect warning")
  func shotUnknownAspect() throws {
    let score = GlosaScore(shots: [Shot(documentIndex: 0, prompt: "p", aspect: "cinemascope")])
    let diags = validator.validate(score: score)

    #expect(diags.contains { $0.code == .shotUnknownAspect })
  }

  @Test("<shot> with known model and aspect produces no diagnostics")
  func shotKnownEnums() throws {
    let score = GlosaScore(
      shots: [Shot(documentIndex: 0, prompt: "p", model: "pixart-sigma", aspect: "panel")])
    #expect(validator.validate(score: score).isEmpty)
  }
}

/// Codable round-trip and backward-compatibility tests for the new
/// `GlosaScore.includes` / `GlosaScore.shots` fields.
@Suite("GlosaScore include/shot Codable")
struct IncludeShotCodableTests {

  @Test("GlosaScore round-trips includes and shots")
  func roundTrip() throws {
    let original = GlosaScore(
      includes: [Include(documentIndex: 0, src: "a.wav", gain: -6, mode: .bed)],
      shots: [Shot(documentIndex: 1, prompt: "p", model: "klein4b", width: 1024, preview: true)]
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: data)

    #expect(decoded == original)
  }

  @Test("Decoding a score without include/shot keys yields empty arrays")
  func backwardCompatDecode() throws {
    // A score serialized before these fields existed — only the old keys.
    let legacy = #"{"scenes":[],"breaths":[],"pauses":[]}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(GlosaScore.self, from: legacy)

    #expect(decoded.includes.isEmpty)
    #expect(decoded.shots.isEmpty)
  }
}

/// End-to-end tests for the `compileScript` façade, which surfaces block events
/// alongside the per-line annotations that `compileAnnotations` returns.
@Suite("compileScript include/shot façade")
struct CompileScriptTests {

  @Test("compileScript returns includes and shots in documentIndex order")
  func scriptSurfacesBlockEvents() throws {
    let notes = [
      #"<include src="opening.wav" mode="bed"/>"#,  // 0 — before any scene
      #"<SceneContext location="office" time="night">"#,  // 1
      #"<Intent from="calm" to="tense">"#,  // 2
      "We need to talk.",  // 3
      #"<shot prompt="close on Maria" aspect="panel"/>"#,  // 4
      "Now.",  // 5
      "</Intent>",
      "</SceneContext>",
    ]
    let dialogue = [
      (character: "MARIA", rawText: "We need to talk."),
      (character: "MARIA", rawText: "Now."),
    ]

    let script = try compileScript(fountainNotes: notes, rawDialogueLines: dialogue)

    #expect(script.includes.map(\.src) == ["opening.wav"])
    #expect(script.includes.first?.documentIndex == 0)
    #expect(script.shots.map(\.prompt) == ["close on Maria"])
    #expect(script.shots.first?.documentIndex == 4)
    // Per-line annotations are still produced for every dialogue line.
    #expect(script.lines.count == 2)
  }

  @Test("compileAnnotations returns exactly compileScript's lines")
  func annotationsMatchScriptLines() throws {
    let notes = [
      #"<SceneContext location="office" time="night">"#,
      #"<Intent from="calm" to="calm">"#,
      "Line one.",
      #"<include src="x.wav"/>"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let dialogue = [(character: "A", rawText: "Line one.")]

    let lines = try compileAnnotations(fountainNotes: notes, rawDialogueLines: dialogue)
    let script = try compileScript(fountainNotes: notes, rawDialogueLines: dialogue)

    #expect(lines.count == script.lines.count)
    #expect(lines[0]?.spokenText == script.lines[0]?.spokenText)
    #expect(script.includes.count == 1)
  }
}
