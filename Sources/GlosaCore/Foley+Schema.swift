import Foundation

// MARK: - Foley schema form

extension Foley {

  /// The known `foley` keys in canonical order. Every other key is an extra
  /// attribute.
  public static let schemaKeys: [String] = [
    "prompt", "seed", "take", "steps", "cfg", "model", "offset", "gain", "fadeIn", "fadeOut",
    "output",
  ]

  /// Keys that belong to `ambience` beds and mean nothing on a one-shot
  /// effect. They are kept as extra attributes (and digested), but the
  /// validator warns about them (`.foleyAmbienceKey`).
  public static let ambienceOnlyKeys: [String] = ["length", "crossfade", "stop"]

  /// The bare `foley` object: known keys in canonical order (`nil` ones
  /// omitted), then `extraAttributes` at the top level in read order. No
  /// `documentIndex` and no `{"foley": …}` wrapper. `seed` is a JSON integer.
  ///
  /// This — not the synthesized `Codable` form — is the interchange form for
  /// render records and CLI input.
  public func schemaJSON() -> GlosaJSONValue {
    var members: [GlosaJSONMember] = []
    func add(_ key: String, _ value: GlosaJSONValue?) {
      if let value { members.append(GlosaJSONMember(key: key, value: value)) }
    }
    add("prompt", prompt.map { .string($0) })
    add("seed", seed.map { .number(Double($0)) })
    add("take", take.map { .number($0) })
    add("steps", steps.map { .number(Double($0)) })
    add("cfg", cfg.map { .number($0) })
    add("model", model.map { .string($0) })
    add("offset", offset.map { .number($0) })
    add("gain", gain.map { .number($0) })
    add("fadeIn", fadeIn.map { .number($0) })
    add("fadeOut", fadeOut.map { .number($0) })
    add("output", output.map { .string($0) })
    GlosaSchemaCodec.appendExtras(
      extraAttributes, to: &members, knownKeys: Set(Self.schemaKeys))
    return .object(members)
  }

  /// `schemaJSON()` as compact UTF-8 JSON text, member order kept.
  public func schemaJSONData() -> Data {
    Data(GlosaSchemaCodec.compactText(schemaJSON()).utf8)
  }

  /// Decodes a bare `foley` object (the schema form).
  ///
  /// No key is required here (a missing `prompt` is a validator concern).
  /// Unknown keys — including the ambience-only `length`, `crossfade` and
  /// `stop` — become `extraAttributes` in read order. `seed` is accepted as a
  /// JSON integer or a decimal string in `0...UInt32.max`. If a known key
  /// appears more than once, the last occurrence wins.
  ///
  /// - Parameter documentIndex: Not part of the schema; the caller supplies it.
  /// - Throws: `GlosaSchemaError` when `schemaJSON` is not an object or a known
  ///   key holds a wrongly typed value (including a `seed` outside the
  ///   `UInt32` range).
  public init(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws(GlosaSchemaError) {
    let members = try GlosaSchemaCodec.members(of: schemaJSON, directive: "foley")
    self.init(documentIndex: documentIndex)
    let d = "foley"
    typealias C = GlosaSchemaCodec
    for member in members {
      let v = member.value
      switch member.key {
      case "prompt": prompt = try C.string(v, d, "prompt")
      case "seed": seed = try Self.decodeSeed(v)
      case "take": take = try C.number(v, d, "take")
      case "steps": steps = try C.integer(v, d, "steps")
      case "cfg": cfg = try C.number(v, d, "cfg")
      case "model": model = try C.string(v, d, "model")
      case "offset": offset = try C.number(v, d, "offset")
      case "gain": gain = try C.number(v, d, "gain")
      case "fadeIn": fadeIn = try C.number(v, d, "fadeIn")
      case "fadeOut": fadeOut = try C.number(v, d, "fadeOut")
      case "output": output = try C.string(v, d, "output")
      default: extraAttributes.append(member)
      }
    }
  }

  /// Decodes a bare `foley` object from UTF-8 JSON text.
  ///
  /// - Throws: `GlosaSchemaError` — `.invalidJSON` (with line and column) when
  ///   the text is not JSON, otherwise as `init(schemaJSON:documentIndex:)`.
  public init(schemaJSONData: Data, documentIndex: Int = 0) throws(GlosaSchemaError) {
    try self.init(
      schemaJSON: try GlosaSchemaCodec.parseData(schemaJSONData), documentIndex: documentIndex)
  }

  private static func decodeSeed(_ value: GlosaJSONValue) throws(GlosaSchemaError) -> UInt32 {
    let wide = try GlosaSchemaCodec.seed(value, "foley")
    guard let seed = UInt32(exactly: wide) else {
      throw GlosaSchemaCodec.wrongType("foley", "seed", "an integer in 0...4294967295")
    }
    return seed
  }
}
