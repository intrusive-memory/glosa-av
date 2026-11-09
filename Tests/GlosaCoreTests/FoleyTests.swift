import Foundation
import Testing

@testable import GlosaCore

/// Tests for `Foley`: schema codec, canonical serialization and render digest.
///
/// The block directive itself is not parsed from a screenplay here; a note's
/// JSON object is read with `GlosaJSONReader` and decoded with
/// `Foley.init(schemaJSON:documentIndex:)`.
@Suite("Foley value type, serializer and digest")
struct FoleyTests {

  // MARK: - Helpers

  /// Decodes the `foley` object of a canonical `[[ {"foley": {…}} ]]` note.
  private func parse(_ note: String) throws -> Foley {
    precondition(note.hasPrefix("[[") && note.hasSuffix("]]"))
    let json = try GlosaJSONReader.parse(String(note.dropFirst(2).dropLast(2)))
    let object = try #require(json["foley"])
    return try Foley(schemaJSON: object)
  }

  private func foley(_ json: String) throws -> Foley {
    try Foley(schemaJSONData: Data(json.utf8))
  }

  private func member(_ key: String, _ value: GlosaJSONValue) -> GlosaJSONMember {
    GlosaJSONMember(key: key, value: value)
  }

  // MARK: - Fixtures (canonical notes)

  static let minimalNote = """
    [[ {"foley": {
      "prompt": "door slams shut"
    }} ]]
    """

  static let fullNote = """
    [[ {"foley": {
      "prompt": "heavy wooden door slams shut",
      "seed": 7,
      "take": 3.0,
      "steps": 8,
      "cfg": 1.0,
      "model": "stable-audio-3-small-sfx",
      "offset": -0.25,
      "gain": -3.0,
      "fadeIn": 0.0,
      "fadeOut": 0.5,
      "output": "foley/door-01.wav"
    }} ]]
    """

  /// Escaped `[[` / `]]`, max seed, and unknown keys in read order.
  static let extrasNote = #"""
    [[ {"foley": {
      "prompt": "boots [\u005bheavy]\u005d on gravel",
      "seed": 4294967295,
      "take": 2.5,
      "x-surface": "gravel",
      "x-tags": ["a","b"]
    }} ]]
    """#

  // MARK: - Round trip

  @Test(
    "serialize(parse(n)) == n for canonical notes",
    arguments: [FoleyTests.minimalNote, FoleyTests.fullNote, FoleyTests.extrasNote])
  func roundTrip(note: String) throws {
    #expect(try parse(note).serialize() == note)
  }

  @Test("Decoded fields of the full and extras fixtures")
  func decodedFields() throws {
    let full = try parse(Self.fullNote)
    #expect(full.prompt == "heavy wooden door slams shut")
    #expect(full.seed == 7)
    #expect(full.take == 3)
    #expect(full.steps == 8)
    #expect(full.cfg == 1)
    #expect(full.model == "stable-audio-3-small-sfx")
    #expect(full.offset == -0.25)
    #expect(full.gain == -3)
    #expect(full.fadeIn == 0)
    #expect(full.fadeOut == 0.5)
    #expect(full.output == "foley/door-01.wav")
    #expect(full.extraAttributes.isEmpty)

    let extras = try parse(Self.extrasNote)
    #expect(extras.prompt == "boots [[heavy]] on gravel")
    #expect(extras.seed == UInt32.max)
    #expect(extras.extraAttributes.map(\.key) == ["x-surface", "x-tags"])
  }

  @Test("parse(serialize(x)) == x, ignoring documentIndex")
  func reverseRoundTrip() throws {
    let original = Foley(
      documentIndex: 7, prompt: "glass ]] and [[ clink", seed: 9, take: 2, steps: 12, cfg: 1.5,
      model: "m", offset: 1.25, gain: -3.5, fadeIn: 0, fadeOut: 0.1, output: "o.wav",
      extraAttributes: [member("x-a", .null), member("x-b", .array([.number(1)]))])
    var decoded = try parse(original.serialize())
    decoded.documentIndex = 7
    #expect(decoded == original)
  }

  @Test("A foley with no keys serializes as an empty object")
  func emptyFoley() {
    #expect(Foley(documentIndex: 0).serialize() == #"[[ {"foley": {}} ]]"#)
  }

  // MARK: - Schema codec

  @Test("Unknown and ambience-only keys are preserved in read order")
  func unknownKeysPreserved() throws {
    let f = try foley(#"{"x-z":1,"prompt":"p","stop":true,"take":5,"length":"scene"}"#)
    #expect(
      f.extraAttributes == [
        member("x-z", .number(1)), member("stop", .bool(true)),
        member("length", .string("scene")),
      ])
    guard case .object(let members) = f.schemaJSON() else {
      Issue.record("schemaJSON is not an object")
      return
    }
    #expect(members.map(\.key) == ["prompt", "take", "x-z", "stop", "length"])
  }

  @Test("seed must fit UInt32; a decimal string is accepted")
  func seedRange() throws {
    #expect(try foley(#"{"seed":"42"}"#).seed == 42)
    #expect(try foley(#"{"seed":4294967295}"#).seed == UInt32.max)
    #expect(throws: GlosaSchemaError.self) { try foley(#"{"seed":4294967296}"#) }
    #expect(throws: GlosaSchemaError.self) { try foley(#"{"seed":-1}"#) }
    #expect(throws: GlosaSchemaError.self) { try foley(#"{"seed":1.5}"#) }
  }

  private func foleyError(_ json: String) -> GlosaSchemaError? {
    do {
      _ = try foley(json)
      return nil
    } catch let error as GlosaSchemaError {
      return error
    } catch {
      return nil
    }
  }

  @Test("Wrongly typed known keys throw with the key name")
  func wrongTypes() {
    #expect(foleyError(#"{"take":"3"}"#)?.kind == .wrongType(key: "take"))
    #expect(foleyError(#"{"offset":"late"}"#)?.kind == .wrongType(key: "offset"))
    #expect(foleyError(#"{"seed":4294967296}"#)?.kind == .wrongType(key: "seed"))
    #expect(foleyError(#"[1]"#)?.kind == .notAnObject)
  }

  @Test("Codable persistence form round-trips")
  func codableRoundTrip() throws {
    let original = Foley(
      documentIndex: 3, prompt: "p", seed: 1, offset: -0.5,
      extraAttributes: [member("x", .string("y"))])
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Foley.self, from: data) == original)
  }

  // MARK: - Effective defaults

  @Test("Effective defaults when keys are not written")
  func effectiveDefaults() {
    let f = Foley(documentIndex: 0, prompt: "p")
    #expect(f.effectiveTake == 5)
    #expect(f.effectiveOffset == 0)
    #expect(f.effectiveGain == 0)
    #expect(f.effectiveFadeIn == 0)
    #expect(f.effectiveFadeOut == 0)
    #expect(f.effectiveModel == "stable-audio-3-small-sfx")
  }

  @Test("Written keys win over effective defaults")
  func effectiveWritten() {
    let f = Foley(
      documentIndex: 0, take: 2, model: "m", offset: 0.75, gain: -6, fadeIn: 0.05, fadeOut: 0.3)
    #expect(f.effectiveTake == 2)
    #expect(f.effectiveOffset == 0.75)
    #expect(f.effectiveGain == -6)
    #expect(f.effectiveFadeIn == 0.05)
    #expect(f.effectiveFadeOut == 0.3)
    #expect(f.effectiveModel == "m")
  }

  // MARK: - Digest vectors
  //
  // Each hash is `printf '%s' '<jcs>' | shasum -a 256` of the checked-in JCS string.

  private func checkVector(_ f: Foley, jcs: String, sha256: String) {
    #expect(GlosaJCS.canonicalString(f.renderDigestObject()) == jcs)
    #expect(f.renderDigest == sha256)
  }

  @Test("Digest vector 1: prompt only")
  func digestVectorPromptOnly() {
    checkVector(
      Foley(documentIndex: 0, prompt: "door slams shut"),
      jcs: #"{"prompt":"door slams shut"}"#,
      sha256: "5c655ba0fc90cf75660a349bcfceae8087cd4486aeef270841e4fe92435e0315")
  }

  @Test("Digest vector 2: every generation key, mix-time keys dropped")
  func digestVectorAllGenerationKeys() throws {
    checkVector(
      try parse(Self.fullNote),
      jcs:
        #"{"cfg":1,"model":"stable-audio-3-small-sfx","prompt":"heavy wooden door slams shut","seed":"7","steps":8,"take":3}"#,
      sha256: "83df6ea35b280ac26a90934ef199c0f4f6d9170be852d6f867c8c8889f9cc1d3")
  }

  @Test("Digest vector 3: unknown keys digested, max seed as a string")
  func digestVectorUnknownKeys() {
    checkVector(
      Foley(
        documentIndex: 0, prompt: "footsteps on gravel", seed: UInt32.max, take: 2.5,
        offset: 1, gain: -6, output: "foley/a.wav",
        extraAttributes: [
          member("x-tags", .array([.string("a"), .string("b")])),
          member("x-surface", .string("gravel")),
        ]),
      jcs:
        #"{"prompt":"footsteps on gravel","seed":"4294967295","take":2.5,"x-surface":"gravel","x-tags":["a","b"]}"#,
      sha256: "6cbdf76320a5456ad30c052ebcbb584eeb5f8afcabb9cc8e80eaee62d9246de4")
  }

  // MARK: - Digest invariants

  @Test("Mix-time keys, output and documentIndex leave the digest unchanged")
  func mixTimeKeysInvariant() throws {
    let base = try parse(Self.fullNote)
    let digest = base.renderDigest

    var offset = base
    offset.offset = 2
    var gain = base
    gain.gain = 6
    var fadeIn = base
    fadeIn.fadeIn = 0.2
    var fadeOut = base
    fadeOut.fadeOut = 1
    var output = base
    output.output = "elsewhere.wav"
    var index = base
    index.documentIndex = 99
    var cleared = base
    cleared.offset = nil
    cleared.gain = nil
    cleared.fadeIn = nil
    cleared.fadeOut = nil
    cleared.output = nil

    for variant in [offset, gain, fadeIn, fadeOut, output, index, cleared] {
      #expect(variant.renderDigest == digest)
    }
  }

  @Test("Generation keys and unknown keys change the digest")
  func generationKeysChangeDigest() throws {
    let base = try parse(Self.fullNote)
    let digest = base.renderDigest

    var prompt = base
    prompt.prompt = "door creaks open"
    var seed = base
    seed.seed = 8
    var take = base
    take.take = 4
    var steps = base
    steps.steps = 9
    var cfg = base
    cfg.cfg = 1.25
    var model = base
    model.model = "other"
    var extra = base
    extra.extraAttributes = [member("x-surface", .string("oak"))]

    for variant in [prompt, seed, take, steps, cfg, model, extra] {
      #expect(variant.renderDigest != digest)
    }
  }

  @Test("A foley and an ambience with the same generation keys share a preimage")
  func sameConstructionAsAmbience() {
    let f = Foley(documentIndex: 0, prompt: "rain", seed: 3, take: 10)
    let a = Ambience(documentIndex: 0, prompt: "rain", seed: 3, take: 10)
    #expect(f.renderDigest == a.renderDigest)
  }
}
