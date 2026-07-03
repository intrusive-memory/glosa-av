import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaParser`'s standalone block-event extraction — the
/// `<include>` and `<shot>` directives. Unlike scope directives (which apply to
/// dialogue lines) and point directives (which anchor at a character offset
/// inside a dialogue line), these are document-positional events keyed by their
/// 0-based position in the note stream (`documentIndex`) and may appear anywhere
/// — including before any `<SceneContext>` opens.
@Suite("GlosaParser include/shot extraction (Fountain)")
struct IncludeShotParserFountainTests {

  let parser = GlosaParser()

  // MARK: - <include>

  @Test("Minimal <include src=…> parses with documentIndex")
  func minimalInclude() throws {
    let notes = [
      #"<SceneContext location="office" time="night">"#,
      #"<Intent from="calm" to="calm">"#,
      "We need to talk.",
      #"<include src="sting.wav"/>"#,
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    #expect(result.score.includes.count == 1)
    let include = try #require(result.score.includes.first)
    #expect(include.src == "sting.wav")
    #expect(include.documentIndex == 3)
    #expect(include.gain == nil)
    #expect(include.mode == nil)
  }

  @Test("<include> parses all mix controls")
  func includeMixControls() throws {
    let notes = [
      #"<include src="bed.wav" gain="-6" mode="bed" fadeIn="0.5" fadeOut="1.25"/>"#
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    let include = try #require(result.score.includes.first)
    #expect(include.src == "bed.wav")
    #expect(include.gain == -6)
    #expect(include.mode == .bed)
    #expect(include.fadeIn == 0.5)
    #expect(include.fadeOut == 1.25)
  }

  @Test("<include> with unknown mode coerces to nil (lenient)")
  func includeUnknownMode() throws {
    let notes = [#"<include src="x.wav" mode="sideways"/>"#]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    let include = try #require(result.score.includes.first)
    #expect(include.mode == nil)
  }

  @Test("<include> before any SceneContext is still parsed, not dropped")
  func includeBeforeScene() throws {
    // The point-directive machinery drops markers with sceneIndex == -1; block
    // events must NOT — an opening sting has no scene.
    let notes = [
      #"<include src="opening.wav" mode="bed"/>"#,
      #"<SceneContext location="office" time="night">"#,
      #"<Intent from="calm" to="calm">"#,
      "Line one.",
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    #expect(result.score.includes.count == 1)
    #expect(result.score.includes.first?.documentIndex == 0)
  }

  // MARK: - <shot>

  @Test("Minimal <shot prompt=…> parses with documentIndex")
  func minimalShot() throws {
    let notes = [#"<shot prompt="wide office, rain"/>"#]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    let shot = try #require(result.score.shots.first)
    #expect(shot.prompt == "wide office, rain")
    #expect(shot.documentIndex == 0)
    #expect(shot.model == nil)
  }

  @Test("<shot> parses the full Vinetas generate option set")
  func shotAllAttributes() throws {
    let notes = [
      #"<shot prompt="noir alley" style="heavy inks" model="klein9b" aspect="wide" "#
        + #"width="1344" height="768" steps="20" guidance="3.5" seed="42" "#
        + #"negative="blurry" lora="char.safetensors" loraScale="0.8" "#
        + #"output="panel1.png" preview="true" telemetry="false"/>"#
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    let shot = try #require(result.score.shots.first)
    #expect(shot.prompt == "noir alley")
    #expect(shot.style == "heavy inks")
    #expect(shot.model == "klein9b")
    #expect(shot.aspect == "wide")
    #expect(shot.width == 1344)
    #expect(shot.height == 768)
    #expect(shot.steps == 20)
    #expect(shot.guidance == 3.5)
    #expect(shot.seed == 42)
    #expect(shot.negative == "blurry")
    #expect(shot.lora == "char.safetensors")
    #expect(shot.loraScale == 0.8)
    #expect(shot.output == "panel1.png")
    #expect(shot.preview == true)
    #expect(shot.telemetry == false)
  }

  @Test("<shot> malformed numeric attribute coerces to nil (lenient)")
  func shotLenientNumeric() throws {
    let notes = [#"<shot prompt="p" width="12px" seed="-1"/>"#]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    let shot = try #require(result.score.shots.first)
    #expect(shot.width == nil)  // "12px" is not an Int
    #expect(shot.seed == nil)  // "-1" is not a UInt64
  }

  // MARK: - Ordering

  @Test("documentIndex preserves document order across includes and shots")
  func documentOrderPreserved() throws {
    let notes = [
      #"<include src="a.wav"/>"#,  // 0
      #"<SceneContext location="office" time="night">"#,  // 1
      #"<Intent from="calm" to="calm">"#,  // 2
      "Line one.",  // 3
      #"<shot prompt="close on Maria"/>"#,  // 4
      "Line two.",  // 5
      #"<include src="b.wav"/>"#,  // 6
      "</Intent>",
      "</SceneContext>",
    ]
    let result = parser.parseFountainWithDiagnostics(notes: notes)

    #expect(result.score.includes.map(\.documentIndex) == [0, 6])
    #expect(result.score.shots.map(\.documentIndex) == [4])
  }
}

/// FDX-side mirror of `IncludeShotParserFountainTests`. The `<glosa:include/>`
/// and `<glosa:shot/>` self-closing elements are document-positional; their
/// `documentIndex` is assigned from a monotonic appearance counter.
@Suite("GlosaParser include/shot extraction (FDX)")
struct IncludeShotParserFDXTests {

  let parser = GlosaParser()

  private func fdx(_ body: String) -> Data {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
      \(body)
        </Content>
      </FinalDraft>
      """
    return xml.data(using: .utf8)!
  }

  @Test("<glosa:include/> parses with attributes and documentIndex")
  func fdxInclude() throws {
    let data = fdx(#"<glosa:include src="bed.wav" gain="-3" mode="overlay" fadeIn="0.2"/>"#)
    let result = parser.parseFDXWithDiagnostics(data: data)

    let include = try #require(result.score.includes.first)
    #expect(include.src == "bed.wav")
    #expect(include.gain == -3)
    #expect(include.mode == .overlay)
    #expect(include.fadeIn == 0.2)
    #expect(include.documentIndex == 0)
  }

  @Test("<glosa:shot/> parses attributes and documentIndex order")
  func fdxShotOrder() throws {
    let data = fdx(
      #"<glosa:include src="a.wav"/>"#
        + #"<glosa:shot prompt="hero shot" model="klein4b" width="1024"/>"#)
    let result = parser.parseFDXWithDiagnostics(data: data)

    #expect(result.score.includes.first?.documentIndex == 0)
    let shot = try #require(result.score.shots.first)
    #expect(shot.prompt == "hero shot")
    #expect(shot.model == "klein4b")
    #expect(shot.width == 1024)
    #expect(shot.documentIndex == 1)
  }
}
