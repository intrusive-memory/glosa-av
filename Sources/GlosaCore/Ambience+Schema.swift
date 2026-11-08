import Foundation

// MARK: - Ambience schema form

extension Ambience {

  /// The known `ambience` keys in canonical order (Produciesta
  /// REQUIREMENTS-ambience § 2.1). Every other key is an extra attribute.
  public static let schemaKeys: [String] = [
    "prompt", "seed", "take", "steps", "cfg", "model", "length", "gain", "fadeIn",
    "fadeOut", "crossfade", "output", "stop",
  ]

  /// The bare `ambience` object: known keys in canonical order (`nil` ones
  /// omitted, `stop` omitted when `false`), then `extraAttributes` at the top
  /// level in read order. No `documentIndex` and no `{"ambience": …}` wrapper.
  /// `seed` is a JSON integer; `length` is its keyword string or a number.
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
    add("length", length.map(Self.lengthValue))
    add("gain", gain.map { .number($0) })
    add("fadeIn", fadeIn.map { .number($0) })
    add("fadeOut", fadeOut.map { .number($0) })
    add("crossfade", crossfade.map { .number($0) })
    add("output", output.map { .string($0) })
    add("stop", stop ? GlosaJSONValue.bool(true) : nil)
    GlosaSchemaCodec.appendExtras(
      extraAttributes, to: &members, knownKeys: Set(Self.schemaKeys))
    return .object(members)
  }

  /// `schemaJSON()` as compact UTF-8 JSON text, member order kept.
  public func schemaJSONData() -> Data {
    Data(GlosaSchemaCodec.compactText(schemaJSON()).utf8)
  }

  /// Decodes a bare `ambience` object (the schema form).
  ///
  /// No key is required here (a missing `prompt` is a validator concern).
  /// Unknown keys become `extraAttributes` in read order. `seed` is accepted
  /// as a JSON integer or a decimal string in `0...UInt32.max`. `length` is
  /// `"scene"`, `"continuous"`, `"natural"` or a number of seconds. `stop:
  /// false` decodes to the default. If a known key appears more than once, the
  /// last occurrence wins.
  ///
  /// - Parameter documentIndex: Not part of the schema; the caller supplies it.
  /// - Throws: `GlosaSchemaError` when `schemaJSON` is not an object or a known
  ///   key holds a wrongly typed value (including an unrecognized `length`
  ///   string or a `seed` outside the `UInt32` range).
  public init(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws(GlosaSchemaError) {
    let members = try GlosaSchemaCodec.members(of: schemaJSON, directive: "ambience")
    self.init(documentIndex: documentIndex)
    let d = "ambience"
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
      case "length": length = try Self.decodeLength(v)
      case "gain": gain = try C.number(v, d, "gain")
      case "fadeIn": fadeIn = try C.number(v, d, "fadeIn")
      case "fadeOut": fadeOut = try C.number(v, d, "fadeOut")
      case "crossfade": crossfade = try C.number(v, d, "crossfade")
      case "output": output = try C.string(v, d, "output")
      case "stop": stop = try C.bool(v, d, "stop")
      default: extraAttributes.append(member)
      }
    }
  }

  /// Decodes a bare `ambience` object from UTF-8 JSON text.
  ///
  /// - Throws: `GlosaSchemaError` — `.invalidJSON` (with line and column) when
  ///   the text is not JSON, otherwise as `init(schemaJSON:documentIndex:)`.
  public init(schemaJSONData: Data, documentIndex: Int = 0) throws(GlosaSchemaError) {
    try self.init(
      schemaJSON: try GlosaSchemaCodec.parseData(schemaJSONData), documentIndex: documentIndex)
  }

  // MARK: Key codecs

  /// `length` as written in the schema form: its keyword, or a number.
  static func lengthValue(_ length: AmbienceLength) -> GlosaJSONValue {
    if case .seconds(let seconds) = length { return .number(seconds) }
    return .string(length.keyword ?? "")
  }

  private static func decodeLength(
    _ value: GlosaJSONValue
  ) throws(GlosaSchemaError) -> AmbienceLength {
    if case .number(let seconds) = value { return .seconds(seconds) }
    if case .string(let string) = value, let length = AmbienceLength(keyword: string) {
      return length
    }
    throw GlosaSchemaCodec.wrongType(
      "ambience", "length", "\"scene\", \"continuous\", \"natural\" or a number of seconds")
  }

  private static func decodeSeed(_ value: GlosaJSONValue) throws(GlosaSchemaError) -> UInt32 {
    let wide = try GlosaSchemaCodec.seed(value, "ambience")
    guard let seed = UInt32(exactly: wide) else {
      throw GlosaSchemaCodec.wrongType("ambience", "seed", "an integer in 0...4294967295")
    }
    return seed
  }
}
