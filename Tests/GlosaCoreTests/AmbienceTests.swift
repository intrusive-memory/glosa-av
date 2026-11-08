import Foundation
import Testing

@testable import GlosaCore

/// Tests for `Ambience`: schema codec, canonical serialization and render digest.
///
/// The block directive itself is not parsed from a screenplay here; a note's
/// JSON object is read with `GlosaJSONReader` and decoded with
/// `Ambience.init(schemaJSON:documentIndex:)`.
@Suite("Ambience value type, serializer and digest")
struct AmbienceTests {

  // MARK: - Helpers

  /// Decodes the `ambience` object of a canonical `[[ {"ambience": {…}} ]]` note.
  private func parse(_ note: String) throws -> Ambience {
    precondition(note.hasPrefix("[[") && note.hasSuffix("]]"))
    let json = try GlosaJSONReader.parse(String(note.dropFirst(2).dropLast(2)))
    let object = try #require(json["ambience"])
    return try Ambience(schemaJSON: object)
  }

  private func ambience(_ json: String) throws -> Ambience {
    try Ambience(schemaJSONData: Data(json.utf8))
  }

  private func member(_ key: String, _ value: GlosaJSONValue) -> GlosaJSONMember {
    GlosaJSONMember(key: key, value: value)
  }

  // MARK: - Fixtures (canonical notes)

  static let minimalNote = """
    [[ {"ambience": {
      "prompt": "rain on a tin roof"
    }} ]]
    """

  static let fullNote = """
    [[ {"ambience": {
      "prompt": "late-night bar, low murmur, glasses clinking",
      "seed": 1234567,
      "take": 45.0,
      "steps": 8,
      "cfg": 1.0,
      "model": "stable-audio-3-small-sfx",
      "length": "continuous",
      "gain": -6.0,
      "fadeIn": 1.5,
      "fadeOut": 2.0,
      "crossfade": 2.0,
      "output": "beds/bar-01.wav"
    }} ]]
    """

  /// Numeric `length`, escaped `[[` / `]]`, and unknown keys in read order.
  static let extrasNote = #"""
    [[ {"ambience": {
      "prompt": "wind [\u005bthrough]\u005d pines",
      "seed": 4294967295,
      "take": 12.5,
      "length": 90.0,
      "x-room": "forest",
      "x-tags": ["a","b"],
      "x-meta": {"k":1,"j":true}
    }} ]]
    """#

  static let stopNote = """
    [[ {"ambience": {
      "stop": true
    }} ]]
    """

  // MARK: - Round trip

  @Test(
    "serialize(parse(n)) == n for canonical notes",
    arguments: [
      AmbienceTests.minimalNote, AmbienceTests.fullNote, AmbienceTests.extrasNote,
      AmbienceTests.stopNote,
    ])
  func roundTrip(note: String) throws {
    #expect(try parse(note).serialize() == note)
  }

  @Test("Decoded fields of the full and extras fixtures")
  func decodedFields() throws {
    let full = try parse(Self.fullNote)
    #expect(full.prompt == "late-night bar, low murmur, glasses clinking")
    #expect(full.seed == 1_234_567)
    #expect(full.take == 45)
    #expect(full.steps == 8)
    #expect(full.cfg == 1)
    #expect(full.model == "stable-audio-3-small-sfx")
    #expect(full.length == .continuous)
    #expect(full.gain == -6)
    #expect(full.fadeIn == 1.5)
    #expect(full.fadeOut == 2)
    #expect(full.crossfade == 2)
    #expect(full.output == "beds/bar-01.wav")
    #expect(full.stop == false)
    #expect(full.extraAttributes.isEmpty)

    let extras = try parse(Self.extrasNote)
    #expect(extras.prompt == "wind [[through]] pines")
    #expect(extras.seed == UInt32.max)
    #expect(extras.length == .seconds(90))
    #expect(extras.extraAttributes.map(\.key) == ["x-room", "x-tags", "x-meta"])

    let stop = try parse(Self.stopNote)
    #expect(stop.stop)
    #expect(stop.prompt == nil)
  }

  @Test("parse(serialize(x)) == x, ignoring documentIndex")
  func reverseRoundTrip() throws {
    let original = Ambience(
      documentIndex: 7, prompt: "surf ]] and [[ gulls", seed: 9, take: 30, steps: 12, cfg: 1.5,
      model: "m", length: .natural, gain: -3.5, fadeIn: 0, fadeOut: 4, crossfade: 1,
      output: "o.wav", extraAttributes: [member("x-a", .null), member("x-b", .array([.number(1)]))])
    var decoded = try parse(original.serialize())
    decoded.documentIndex = 7
    #expect(decoded == original)
  }

  @Test("An ambience with no keys serializes as an empty object")
  func emptyAmbience() {
    #expect(Ambience(documentIndex: 0).serialize() == #"[[ {"ambience": {}} ]]"#)
  }

  // MARK: - Schema codec

  @Test("Unknown keys are preserved in read order")
  func unknownKeysPreserved() throws {
    let a = try ambience(#"{"x-z":1,"prompt":"p","x-a":"two","take":5,"x-m":[true]}"#)
    #expect(
      a.extraAttributes == [
        member("x-z", .number(1)), member("x-a", .string("two")),
        member("x-m", .array([.bool(true)])),
      ])
    guard case .object(let members) = a.schemaJSON() else {
      Issue.record("schemaJSON is not an object")
      return
    }
    #expect(members.map(\.key) == ["prompt", "take", "x-z", "x-a", "x-m"])
  }

  @Test("length accepts its keywords and numbers, rejects other strings")
  func lengthValues() throws {
    #expect(try ambience(#"{"length":"scene"}"#).length == .scene)
    #expect(try ambience(#"{"length":"continuous"}"#).length == .continuous)
    #expect(try ambience(#"{"length":"natural"}"#).length == .natural)
    #expect(try ambience(#"{"length":45}"#).length == .seconds(45))
    #expect(throws: GlosaSchemaError.self) { try ambience(#"{"length":"forever"}"#) }
    #expect(throws: GlosaSchemaError.self) { try ambience(#"{"length":true}"#) }
  }

  @Test("seed must fit UInt32; a decimal string is accepted")
  func seedRange() throws {
    #expect(try ambience(#"{"seed":"42"}"#).seed == 42)
    #expect(try ambience(#"{"seed":4294967295}"#).seed == UInt32.max)
    #expect(throws: GlosaSchemaError.self) { try ambience(#"{"seed":4294967296}"#) }
    #expect(throws: GlosaSchemaError.self) { try ambience(#"{"seed":-1}"#) }
    #expect(throws: GlosaSchemaError.self) { try ambience(#"{"seed":1.5}"#) }
  }

  private func ambienceError(_ json: String) -> GlosaSchemaError? {
    do {
      _ = try ambience(json)
      return nil
    } catch let error as GlosaSchemaError {
      return error
    } catch {
      return nil
    }
  }

  @Test("Wrongly typed known keys throw with the key name")
  func wrongTypes() {
    #expect(ambienceError(#"{"take":"30"}"#)?.kind == .wrongType(key: "take"))
    #expect(ambienceError(#"{"stop":"yes"}"#)?.kind == .wrongType(key: "stop"))
    #expect(ambienceError(#"{"length":"forever"}"#)?.kind == .wrongType(key: "length"))
    #expect(ambienceError(#"{"seed":4294967296}"#)?.kind == .wrongType(key: "seed"))
    #expect(ambienceError(#"[1]"#)?.kind == .notAnObject)
  }

  @Test("stop: false decodes to the default and is not written")
  func stopFalse() throws {
    let a = try ambience(#"{"prompt":"p","stop":false}"#)
    #expect(a.stop == false)
    #expect(a.schemaJSON() == .object([member("prompt", .string("p"))]))
  }

  @Test("Codable persistence form round-trips")
  func codableRoundTrip() throws {
    let original = Ambience(
      documentIndex: 3, prompt: "p", seed: 1, length: .seconds(12.5), stop: false,
      extraAttributes: [member("x", .string("y"))])
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Ambience.self, from: data) == original)
  }

  // MARK: - Effective defaults

  @Test("Effective defaults when keys are not written")
  func effectiveDefaults() {
    let a = Ambience(documentIndex: 0, prompt: "p")
    #expect(a.effectiveTake == 30)
    #expect(a.effectiveLength == .scene)
    #expect(a.effectiveGain == 0)
    #expect(a.effectiveFadeIn == 1)
    #expect(a.effectiveFadeOut == 2)
    #expect(a.effectiveCrossfade == 2)
    #expect(a.effectiveModel == "stable-audio-3-small-sfx")
  }

  @Test("Written keys win over effective defaults")
  func effectiveWritten() {
    let a = Ambience(
      documentIndex: 0, take: 10, model: "m", length: .natural, gain: -6, fadeIn: 0.5,
      fadeOut: 3, crossfade: 0.25)
    #expect(a.effectiveTake == 10)
    #expect(a.effectiveLength == .natural)
    #expect(a.effectiveGain == -6)
    #expect(a.effectiveFadeIn == 0.5)
    #expect(a.effectiveFadeOut == 3)
    #expect(a.effectiveCrossfade == 0.25)
    #expect(a.effectiveModel == "m")
  }

  // MARK: - Digest vectors
  //
  // Each hash is `printf '%s' '<jcs>' | shasum -a 256` of the checked-in JCS string.

  private func checkVector(_ a: Ambience, jcs: String, sha256: String) {
    #expect(GlosaJCS.canonicalString(a.renderDigestObject()) == jcs)
    #expect(a.renderDigest == sha256)
  }

  @Test("Digest vector 1: prompt only")
  func digestVectorPromptOnly() {
    checkVector(
      Ambience(documentIndex: 0, prompt: "rain on a tin roof"),
      jcs: #"{"prompt":"rain on a tin roof"}"#,
      sha256: "e6d5a74bfe942bcbe5f55dfa822962c8f595f91bb9196f3719bbe73d0c5dec05")
  }

  @Test("Digest vector 2: every generation key, mix-time keys dropped")
  func digestVectorAllGenerationKeys() throws {
    checkVector(
      try parse(Self.fullNote),
      jcs:
        #"{"cfg":1,"model":"stable-audio-3-small-sfx","prompt":"late-night bar, low murmur, glasses clinking","seed":"1234567","steps":8,"take":45}"#,
      sha256: "41696fea8953cb4b9547e60881e2cb810366c6234320e53fa72fb845401bad1c")
  }

  @Test("Digest vector 3: unknown keys digested, max seed as a string")
  func digestVectorUnknownKeys() {
    checkVector(
      Ambience(
        documentIndex: 0, prompt: "wind through pines", seed: UInt32.max, take: 12.5,
        length: .continuous, gain: -6, output: "beds/a.wav",
        extraAttributes: [
          member("x-tags", .array([.string("a"), .string("b")])),
          member("x-room", .string("forest")),
        ]),
      jcs:
        #"{"prompt":"wind through pines","seed":"4294967295","take":12.5,"x-room":"forest","x-tags":["a","b"]}"#,
      sha256: "8a8ab205ed0d0d30bfb94734f6fc1706a0fb2ff2d1ab03ca4c44657e32571dec")
  }

  @Test("Digest vector 4: a stop note has an empty preimage")
  func digestVectorStop() throws {
    checkVector(
      try parse(Self.stopNote),
      jcs: "{}",
      sha256: "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
  }

  // MARK: - Digest invariants

  @Test("Mix-time keys, output, stop and documentIndex leave the digest unchanged")
  func mixTimeKeysInvariant() throws {
    let base = try parse(Self.fullNote)
    let digest = base.renderDigest

    var length = base
    length.length = .seconds(120)
    var gain = base
    gain.gain = 6
    var fadeIn = base
    fadeIn.fadeIn = 0
    var fadeOut = base
    fadeOut.fadeOut = 10
    var crossfade = base
    crossfade.crossfade = 0.5
    var output = base
    output.output = "elsewhere.wav"
    var stop = base
    stop.stop = true
    var index = base
    index.documentIndex = 99
    var cleared = base
    cleared.length = nil
    cleared.gain = nil
    cleared.fadeIn = nil
    cleared.fadeOut = nil
    cleared.crossfade = nil
    cleared.output = nil

    for variant in [length, gain, fadeIn, fadeOut, crossfade, output, stop, index, cleared] {
      #expect(variant.renderDigest == digest)
    }
  }

  @Test("Generation keys and unknown keys change the digest")
  func generationKeysChangeDigest() throws {
    let base = try parse(Self.fullNote)
    let digest = base.renderDigest

    var prompt = base
    prompt.prompt = "empty bar"
    var seed = base
    seed.seed = 7
    var take = base
    take.take = 46
    var steps = base
    steps.steps = 9
    var cfg = base
    cfg.cfg = 1.25
    var model = base
    model.model = "other"
    var extraAdded = base
    extraAdded.extraAttributes = [member("x-room", .string("cellar"))]

    for variant in [prompt, seed, take, steps, cfg, model, extraAdded] {
      #expect(variant.renderDigest != digest)
    }

    var extraChanged = extraAdded
    extraChanged.extraAttributes = [member("x-room", .string("attic"))]
    #expect(extraChanged.renderDigest != extraAdded.renderDigest)
  }

  @Test("Source key order and number spelling do not change the digest")
  func sourceFormIrrelevant() throws {
    let one = try ambience(#"{"prompt":"p","take":30.0,"x-b":{"k":1,"j":[1,2]},"x-a":true}"#)
    let two = try ambience(#"{"x-a":true,"take":30,"x-b":{"j":[1,2],"k":1},"prompt":"p"}"#)
    #expect(one != two)
    #expect(one.renderDigest == two.renderDigest)
  }
}
