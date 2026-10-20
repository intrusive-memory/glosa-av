import Foundation
import Testing

@testable import GlosaCore

/// Tests for the defaults fold (`Shot.effective(given:)`,
/// `GlosaScore.effectiveShots`) and the render digest (`Shot.renderDigest`).
@Suite("Fold and render digest")
struct FoldDigestTests {

  // MARK: - Helpers

  private func shot(_ text: String, documentIndex: Int = 0) throws -> Shot {
    try Shot(schemaJSONData: Data(text.utf8), documentIndex: documentIndex)
  }

  private func member(_ key: String, _ value: GlosaJSONValue) -> GlosaJSONMember {
    GlosaJSONMember(key: key, value: value)
  }

  // MARK: - Fold

  @Test("Each defaults shot replaces per key; the shot's own keys win")
  func perKeyReplacement() {
    let first = Shot(documentIndex: 0, prompt: "", style: "ink", model: "m1", width: 512, seed: 1)
    let second = Shot(documentIndex: 1, prompt: "", model: "m2", steps: 8)
    let panel = Shot(documentIndex: 2, prompt: "p", width: 1024)

    let effective = panel.effective(given: [first, second])
    #expect(effective.style == "ink")
    #expect(effective.model == "m2")
    #expect(effective.width == 1024)
    #expect(effective.steps == 8)
    #expect(effective.seed == 1)
    #expect(effective.prompt == "p")
    #expect(effective.documentIndex == 2)
  }

  @Test("Defaults apply in the order given (document order)")
  func documentOrder() {
    let a = Shot(documentIndex: 0, prompt: "", style: "a")
    let b = Shot(documentIndex: 1, prompt: "", style: "b")
    let panel = Shot(documentIndex: 2, prompt: "p")
    #expect(panel.effective(given: [a, b]).style == "b")
    #expect(panel.effective(given: [b, a]).style == "a")
  }

  @Test("Every inheritable known key folds; nil keys set nothing")
  func allInheritableKeys() {
    let defaults = Shot(
      documentIndex: 0, prompt: "", style: "s", model: "m", aspect: "wide", width: 1, height: 2,
      steps: 3, guidance: 4.5, seed: 5, negative: "n", lora: "l", loraScale: 0.5, preview: true,
      telemetry: false, ref: ["A"], character: "c")
    let effective = Shot(documentIndex: 1, prompt: "p").effective(given: [defaults])
    var expected = defaults
    expected.documentIndex = 1
    expected.prompt = "p"
    #expect(effective == expected)
  }

  @Test("caption and output are never inherited")
  func captionAndOutputNotInherited() {
    let defaults = Shot(documentIndex: 0, prompt: "", caption: "shared", output: "one.png")
    let bare = Shot(documentIndex: 1, prompt: "p").effective(given: [defaults])
    #expect(bare.caption == nil)
    #expect(bare.output == nil)

    let own = Shot(documentIndex: 1, prompt: "p", caption: "mine", output: "mine.png")
      .effective(given: [defaults])
    #expect(own.caption == "mine")
    #expect(own.output == "mine.png")
  }

  @Test("A defaults shot's prompt is never inherited")
  func promptNotInherited() {
    var defaults = Shot(documentIndex: 0, prompt: "")
    defaults.prompt = "stray"
    let effective = Shot(documentIndex: 1, prompt: "p").effective(given: [defaults])
    #expect(effective.prompt == "p")
  }

  @Test("Extra attributes fold per key, first-seen order, replaced in place")
  func extrasFold() {
    let a = Shot(
      documentIndex: 0, prompt: "",
      extraAttributes: [member("x-lens", .number(35)), member("x-mood", .string("calm"))])
    let b = Shot(
      documentIndex: 1, prompt: "",
      extraAttributes: [member("x-grain", .bool(true)), member("x-lens", .number(50))])
    let panel = Shot(
      documentIndex: 2, prompt: "p",
      extraAttributes: [member("x-mood", .null), member("x-new", .string("n"))])

    let effective = panel.effective(given: [a, b])
    #expect(
      effective.extraAttributes == [
        member("x-lens", .number(50)),
        member("x-mood", .null),
        member("x-grain", .bool(true)),
        member("x-new", .string("n")),
      ])
  }

  @Test("No defaults: the effective shot is the shot itself")
  func noDefaults() throws {
    let panel = try shot(#"{"prompt":"p","style":"s","caption":"c","x":1}"#, documentIndex: 4)
    #expect(panel.effective(given: []) == panel)
  }

  // MARK: - effectiveShots

  @Test("effectiveShots folds each panel with the promptless shots before it")
  func effectiveShots() {
    let score = GlosaScore(shots: [
      Shot(documentIndex: 0, prompt: "", style: "ink", output: "never.png"),
      Shot(documentIndex: 1, prompt: "one", model: "m1"),
      Shot(documentIndex: 2, prompt: "", style: "oil", seed: 9),
      Shot(documentIndex: 3, prompt: "two"),
    ])
    let panels = score.effectiveShots
    #expect(panels.map(\.prompt) == ["one", "two"])
    #expect(panels[0].style == "ink")
    #expect(panels[0].seed == nil)
    #expect(panels[0].model == "m1")
    #expect(panels[1].style == "oil")
    #expect(panels[1].seed == 9)
    #expect(panels[1].model == nil)
    #expect(panels.allSatisfy { $0.output == nil })
  }

  @Test("effectiveShots follows documentIndex, not array position")
  func effectiveShotsUsesDocumentIndex() {
    let score = GlosaScore(shots: [
      Shot(documentIndex: 5, prompt: "late"),
      Shot(documentIndex: 3, prompt: "", style: "after-early"),
      Shot(documentIndex: 1, prompt: "early"),
    ])
    let panels = score.effectiveShots
    #expect(panels.map(\.prompt) == ["early", "late"])
    #expect(panels[0].style == nil)
    #expect(panels[1].style == "after-early")
  }

  @Test("effectiveShots over parsed notation 2.0 notes")
  func effectiveShotsFromParser() throws {
    let score = GlosaParser().parseFountain(notes: [
      #"{"shot": {"style": "charcoal", "model": "m", "x-lens": 35}}"#,
      #"{"shot": {"prompt": "A", "caption": "beat"}}"#,
      #"{"shot": {"prompt": "B", "model": "n"}}"#,
    ])
    let panels = score.effectiveShots
    #expect(panels.count == 2)
    #expect(panels[0].style == "charcoal")
    #expect(panels[0].caption == "beat")
    #expect(panels[0].extraAttributes == [member("x-lens", .number(35))])
    #expect(panels[1].model == "n")
    #expect(panels[1].caption == nil)
  }

  // MARK: - Digest

  @Test("Digest is 64 lowercase hex characters")
  func digestShape() {
    let digest = Shot(documentIndex: 0, prompt: "p").renderDigest
    #expect(digest.count == 64)
    #expect(digest.allSatisfy { "0123456789abcdef".contains($0) })
  }

  @Test("Acceptance 5: caption, output, preview, telemetry leave the digest equal")
  func acceptance5ExcludedKeys() {
    let base = Shot(documentIndex: 0, prompt: "p", style: "s", ref: ["A", "B"])
    var changed = base
    changed.caption = "a caption"
    changed.output = "out/x.png"
    changed.preview = true
    changed.telemetry = true
    changed.documentIndex = 99
    #expect(changed.renderDigest == base.renderDigest)
  }

  @Test("Acceptance 5: prompt, style, ref order and an unknown key change the digest")
  func acceptance5IncludedKeys() {
    let base = Shot(
      documentIndex: 0, prompt: "p", style: "s", ref: ["A", "B"],
      extraAttributes: [member("x-lens", .number(35))])
    let digest = base.renderDigest

    var prompt = base
    prompt.prompt = "q"
    var style = base
    style.style = "t"
    var refOrder = base
    refOrder.ref = ["B", "A"]
    var extraValue = base
    extraValue.extraAttributes = [member("x-lens", .number(50))]
    var extraAdded = base
    extraAdded.extraAttributes.append(member("x-mood", .string("calm")))

    for variant in [prompt, style, refOrder, extraValue, extraAdded] {
      #expect(variant.renderDigest != digest)
    }
  }

  @Test("Source key order does not change the digest")
  func sourceKeyOrderIrrelevant() throws {
    let one = try shot(
      #"{"prompt":"p","style":"s","seed":7,"x-b":{"k":1,"j":[1,2]},"x-a":true}"#)
    let two = try shot(
      #"{"x-a":true,"seed":7,"x-b":{"j":[1,2],"k":1},"style":"s","prompt":"p"}"#)
    #expect(one != two)
    #expect(one.renderDigest == two.renderDigest)
  }

  @Test("Seeds above 2^53 stay distinct in the digest")
  func largeSeed() {
    let a = Shot(documentIndex: 0, prompt: "p", seed: 9_007_199_254_740_993)
    let b = Shot(documentIndex: 0, prompt: "p", seed: 9_007_199_254_740_992)
    #expect(a.renderDigest != b.renderDigest)
    #expect(
      GlosaJCS.canonicalString(a.renderDigestObject())
        == #"{"prompt":"p","seed":"9007199254740993"}"#)
  }

  @Test("seed is a decimal string in the preimage even when small")
  func smallSeedIsString() {
    let shot = Shot(documentIndex: 0, prompt: "p", seed: 42)
    #expect(GlosaJCS.canonicalString(shot.renderDigestObject()) == #"{"prompt":"p","seed":"42"}"#)
  }

  @Test("JCS numbers: 4.0 and 4 hash alike, exponent forms canonicalize")
  func numberEdgeCases() throws {
    #expect(
      try shot(#"{"prompt":"p","guidance":4.0}"#).renderDigest
        == shot(#"{"prompt":"p","guidance":4}"#).renderDigest)
    #expect(
      try shot(#"{"prompt":"p","x":1e21}"#).renderDigest
        == shot(#"{"prompt":"p","x":1000000000000000000000}"#).renderDigest)
    #expect(
      try shot(#"{"prompt":"p","x":0.0000001}"#).renderDigest
        == shot(#"{"prompt":"p","x":1E-7}"#).renderDigest)
    #expect(
      try shot(#"{"prompt":"p","x":3.5}"#).renderDigest
        != shot(#"{"prompt":"p","x":3}"#).renderDigest)
  }

  @Test("A defaults shot's empty prompt is omitted from the preimage")
  func emptyPromptOmitted() {
    let shot = Shot(documentIndex: 0, prompt: "", style: "s")
    #expect(GlosaJCS.canonicalString(shot.renderDigestObject()) == #"{"style":"s"}"#)
  }

  // MARK: - Golden vectors

  @Test("Golden digest vectors (computed independently) match")
  func goldenVectors() throws {
    let directory = try #require(
      Bundle.module.url(forResource: "digest", withExtension: nil, subdirectory: "Fixtures"))
    let files = try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    #expect(files.count >= 6)

    for file in files {
      let vector = try GlosaJSONReader.parse(String(contentsOf: file, encoding: .utf8))
      let shotJSON = try #require(vector["shot"], "\(file.lastPathComponent): no shot")
      guard case .string(let expected) = try #require(vector["sha256"]) else {
        Issue.record("\(file.lastPathComponent): sha256 is not a string")
        continue
      }
      let shot = try Shot(schemaJSON: shotJSON)
      #expect(shot.renderDigest == expected, "\(file.lastPathComponent)")
    }
  }
}
