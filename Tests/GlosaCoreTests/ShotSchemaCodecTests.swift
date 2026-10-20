import Foundation
import Testing

@testable import GlosaCore

/// Tests for notation 2.0 model additions: `GlosaVersion.notation`,
/// `extraAttributes` on `Shot` / `Include`, the legacy-tolerant persistence
/// decoder, and the bare-object schema codec (`schemaJSON` /
/// `init(schemaJSON:documentIndex:)`).
@Suite("Shot and Include schema-form codec")
struct ShotSchemaCodecTests {

  // MARK: - Helpers

  private func json(_ text: String) throws -> GlosaJSONValue {
    try GlosaJSONReader.parse(text)
  }

  private func shotError(_ text: String) -> GlosaSchemaError? {
    do throws(GlosaSchemaError) {
      _ = try Shot(schemaJSONData: Data(text.utf8))
      return nil
    } catch {
      return error
    }
  }

  private func includeError(_ text: String) -> GlosaSchemaError? {
    do throws(GlosaSchemaError) {
      _ = try Include(schemaJSONData: Data(text.utf8))
      return nil
    } catch {
      return error
    }
  }

  private func keys(_ value: GlosaJSONValue) -> [String] {
    guard case .object(let members) = value else { return [] }
    return members.map(\.key)
  }

  private func fullShot() -> Shot {
    Shot(
      documentIndex: 4, prompt: "A keeper climbs the stair", caption: "Nine o'clock.",
      style: "ink wash", model: "klein4b", aspect: "wide", width: 1024, height: 576,
      steps: 4, guidance: 3.5, seed: 42, negative: "blur", lora: "loras/keeper.safetensors",
      loraScale: 0.8, output: "boards/01.png", preview: true, telemetry: false,
      ref: ["KEEPER", "interior.png"], character: "keeper",
      extraAttributes: [
        GlosaJSONMember(key: "zeta", value: .number(1)),
        GlosaJSONMember(key: "alpha", value: .object([GlosaJSONMember(key: "x", value: .null)])),
      ])
  }

  // MARK: - Version

  @Test func notationVersionIsTwoPointZero() {
    #expect(GlosaVersion.notation == "2.0")
  }

  // MARK: - Persistence Codable

  @Test func legacyShotJSONWithoutExtraAttributesDecodesToEmpty() throws {
    let legacy = #"{"documentIndex":3,"prompt":"A harbor at dawn","seed":7,"ref":["A"]}"#
    let shot = try JSONDecoder().decode(Shot.self, from: Data(legacy.utf8))
    #expect(shot.extraAttributes == [])
    #expect(shot == Shot(documentIndex: 3, prompt: "A harbor at dawn", seed: 7, ref: ["A"]))
  }

  @Test func legacyIncludeJSONWithoutExtraAttributesDecodesToEmpty() throws {
    let legacy = #"{"documentIndex":1,"src":"audio/surf.m4a","mode":"bed","gain":-12}"#
    let include = try JSONDecoder().decode(Include.self, from: Data(legacy.utf8))
    #expect(include.extraAttributes == [])
    #expect(include.mode == .bed)
    #expect(include.gain == -12)
  }

  @Test func persistenceCodableRoundTripsExtraAttributes() throws {
    let shot = fullShot()
    let data = try JSONEncoder().encode(shot)
    #expect(try JSONDecoder().decode(Shot.self, from: data) == shot)

    let include = Include(
      documentIndex: 2, src: "a.m4a",
      extraAttributes: [GlosaJSONMember(key: "loop", value: .bool(true))])
    let includeData = try JSONEncoder().encode(include)
    #expect(try JSONDecoder().decode(Include.self, from: includeData) == include)
  }

  // MARK: - Schema round-trips

  @Test func shotSchemaRoundTripAllKeys() throws {
    let shot = fullShot()
    let value = shot.schemaJSON()
    #expect(keys(value) == Shot.schemaKeys + ["zeta", "alpha"])
    #expect(try Shot(schemaJSON: value, documentIndex: 4) == shot)
    #expect(try Shot(schemaJSONData: shot.schemaJSONData(), documentIndex: 4) == shot)
  }

  @Test func schemaFormHasNoDocumentIndexOrWrapper() {
    let value = Shot(documentIndex: 9, prompt: "p").schemaJSON()
    #expect(keys(value) == ["prompt"])
    let text = String(decoding: Shot(documentIndex: 9, prompt: "p").schemaJSONData(), as: UTF8.self)
    #expect(text == #"{"prompt":"p"}"#)
  }

  @Test func includeSchemaRoundTripAllKeys() throws {
    let include = Include(
      documentIndex: 2, src: "audio/surf.m4a", gain: -12.0, mode: .bed, fadeIn: 0.5,
      fadeOut: 1.25, prompt: "low surf",
      extraAttributes: [GlosaJSONMember(key: "loop", value: .bool(true))])
    let value = include.schemaJSON()
    #expect(keys(value) == Include.schemaKeys + ["loop"])
    #expect(try Include(schemaJSON: value, documentIndex: 2) == include)
    #expect(try Include(schemaJSONData: include.schemaJSONData(), documentIndex: 2) == include)
  }

  @Test func decodingFollowsSchemaTypes() throws {
    let shot = try Shot(
      schemaJSONData: Data(
        #"{"width": 768, "guidance": 4, "preview": true, "ref": ["A", "b.png"], "prompt": "x"}"#
          .utf8), documentIndex: 11)
    #expect(shot.documentIndex == 11)
    #expect(shot.width == 768)
    #expect(shot.guidance == 4.0)
    #expect(shot.preview == true)
    #expect(shot.ref == ["A", "b.png"])
    #expect(shot.prompt == "x")
  }

  // MARK: - Defaults shot

  @Test func defaultsShotOmitsPromptAndDecodesToEmpty() throws {
    let defaults = Shot(documentIndex: 0, prompt: "", style: "ink wash", model: "klein4b")
    let value = defaults.schemaJSON()
    #expect(keys(value) == ["style", "model"])
    #expect(value["prompt"] == nil)

    let decoded = try Shot(schemaJSON: json(#"{"style": "ink wash", "model": "klein4b"}"#))
    #expect(decoded.prompt == "")
    #expect(decoded == defaults)
  }

  // MARK: - Seed

  @Test func seedAboveExactIntegerRoundTripsAsString() throws {
    let big: UInt64 = 18_446_744_073_709_551_615
    let decoded = try Shot(schemaJSON: json(#"{"seed": "18446744073709551615"}"#))
    #expect(decoded.seed == big)
    #expect(decoded.schemaJSON()["seed"] == .string("18446744073709551615"))
    #expect(try Shot(schemaJSONData: decoded.schemaJSONData()).seed == big)

    let justAbove = try Shot(schemaJSON: json(#"{"seed": "9007199254740992"}"#))
    #expect(justAbove.seed == 9_007_199_254_740_992)
    #expect(justAbove.schemaJSON()["seed"] == .string("9007199254740992"))
  }

  @Test func seedIntegerInputUpToExactLimitRoundTripsAsNumber() throws {
    let limit: UInt64 = 9_007_199_254_740_991
    let decoded = try Shot(schemaJSON: json(#"{"seed": 9007199254740991}"#))
    #expect(decoded.seed == limit)
    #expect(decoded.schemaJSON()["seed"] == .number(9_007_199_254_740_991))
    #expect(try Shot(schemaJSONData: decoded.schemaJSONData()).seed == limit)

    let small = try Shot(schemaJSON: json(#"{"seed": "42"}"#))
    #expect(small.seed == 42)
    #expect(small.schemaJSON()["seed"] == .number(42))
  }

  @Test func seedIntegerAboveExactLimitThrows() {
    let error = shotError(#"{"seed": 9007199254740993}"#)
    #expect(error?.kind == .wrongType(key: "seed"))
    #expect(error?.message.contains("decimal string") == true)
  }

  @Test func seedInvalidValuesThrow() {
    for text in [
      #"{"seed": -1}"#, #"{"seed": 1.5}"#, #"{"seed": "18446744073709551616"}"#,
      #"{"seed": "+5"}"#, #"{"seed": ""}"#, #"{"seed": "12a"}"#, #"{"seed": true}"#,
    ] {
      #expect(shotError(text)?.kind == .wrongType(key: "seed"), "\(text)")
    }
  }

  // MARK: - Unknown keys

  @Test func unknownKeysPreservedInReadOrderAtTopLevel() throws {
    let shot = try Shot(
      schemaJSON: json(
        #"{"zeta": 1, "prompt": "p", "alpha": [true, null], "mid": {"b": 1, "a": 2}}"#))
    #expect(shot.extraAttributes.map(\.key) == ["zeta", "alpha", "mid"])
    #expect(shot.extraAttributes[2].value == .object([
      GlosaJSONMember(key: "b", value: .number(1)),
      GlosaJSONMember(key: "a", value: .number(2)),
    ]))
    #expect(keys(shot.schemaJSON()) == ["prompt", "zeta", "alpha", "mid"])
    #expect(shot.schemaJSON()["extraAttributes"] == nil)
    #expect(
      String(decoding: shot.schemaJSONData(), as: UTF8.self)
        == #"{"prompt":"p","zeta":1,"alpha":[true,null],"mid":{"b":1,"a":2}}"#)

    let include = try Include(schemaJSON: json(#"{"z": "q", "src": "a.m4a", "b": 2}"#))
    #expect(include.extraAttributes.map(\.key) == ["z", "b"])
    #expect(keys(include.schemaJSON()) == ["src", "z", "b"])
  }

  @Test func unrecognizedIncludeModeDecodesToNil() throws {
    let include = try Include(schemaJSON: json(#"{"src": "a.m4a", "mode": "crossfade"}"#))
    #expect(include.mode == nil)
  }

  // MARK: - Throw cases

  @Test func nonObjectThrows() {
    for text in [#"[]"#, #""shot""#, #"42"#, #"null"#] {
      #expect(shotError(text)?.kind == .notAnObject, "\(text)")
      #expect(includeError(text)?.kind == .notAnObject, "\(text)")
    }
  }

  @Test func invalidJSONThrowsWithPosition() {
    let error = shotError("{\n  \"prompt\": \"p\",\n}")
    guard case .invalidJSON(let jsonError) = error?.kind else {
      Issue.record("expected invalidJSON, got \(String(describing: error))")
      return
    }
    #expect(jsonError.line == 3)
    #expect(includeError("{") != nil)
  }

  @Test func wrongTypedShotKeysThrowNamingTheKey() {
    let cases: [(String, String)] = [
      (#"{"prompt": 1}"#, "prompt"),
      (#"{"caption": false}"#, "caption"),
      (#"{"width": "wide"}"#, "width"),
      (#"{"height": 1.5}"#, "height"),
      (#"{"steps": null}"#, "steps"),
      (#"{"guidance": "3"}"#, "guidance"),
      (#"{"loraScale": true}"#, "loraScale"),
      (#"{"preview": "yes"}"#, "preview"),
      (#"{"telemetry": 1}"#, "telemetry"),
      (#"{"ref": "A,B"}"#, "ref"),
      (#"{"ref": ["A", 2]}"#, "ref"),
      (#"{"character": ["x"]}"#, "character"),
      (#"{"output": {}}"#, "output"),
    ]
    for (text, key) in cases {
      let error = shotError(text)
      #expect(error?.kind == .wrongType(key: key), "\(text)")
      #expect(error?.key == key)
      #expect(error?.message.contains(key) == true, "\(text)")
    }
  }

  @Test func wrongTypedIncludeKeysThrowNamingTheKey() {
    let cases: [(String, String)] = [
      (#"{"src": 1}"#, "src"),
      (#"{"src": "a", "gain": "-12"}"#, "gain"),
      (#"{"src": "a", "mode": 3}"#, "mode"),
      (#"{"src": "a", "fadeIn": null}"#, "fadeIn"),
      (#"{"src": "a", "fadeOut": [1]}"#, "fadeOut"),
      (#"{"src": "a", "prompt": false}"#, "prompt"),
    ]
    for (text, key) in cases {
      #expect(includeError(text)?.kind == .wrongType(key: key), "\(text)")
    }
  }

  @Test func includeMissingSrcThrows() {
    let error = includeError(#"{"gain": -3.0}"#)
    #expect(error?.kind == .missingKey("src"))
    #expect(error?.key == "src")
  }
}
