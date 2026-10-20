import Foundation

// MARK: - Schema-form error

/// Why a bare `shot` / `include` object (the schema form) could not be decoded.
public struct GlosaSchemaError: Error, Sendable, Equatable, CustomStringConvertible {

  /// What went wrong.
  public enum Kind: Sendable, Equatable {
    /// The input is not valid JSON (or not UTF-8). Carries the reader's
    /// position-bearing error.
    case invalidJSON(GlosaJSONError)
    /// The value is valid JSON but not an object.
    case notAnObject
    /// A known key holds a value of the wrong JSON type.
    case wrongType(key: String)
    /// A required key is absent (only `include.src`).
    case missingKey(String)
  }

  public var kind: Kind
  public var message: String

  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }

  /// The offending key, for `wrongType` and `missingKey`; otherwise `nil`.
  public var key: String? {
    switch kind {
    case .wrongType(let key), .missingKey(let key): return key
    case .invalidJSON, .notAnObject: return nil
    }
  }

  public var description: String { message }
}

// MARK: - Shared schema-form helpers

/// Reading and writing helpers shared by the `Shot` and `Include` schema codecs.
enum GlosaSchemaCodec {

  /// Largest integer a JSON number (IEEE-754 double) represents exactly: 2^53 − 1.
  static let maxExactInteger: UInt64 = (1 << 53) - 1

  static func parseData(_ data: Data) throws(GlosaSchemaError) -> GlosaJSONValue {
    guard let text = String(data: data, encoding: .utf8) else {
      throw GlosaSchemaError(
        kind: .invalidJSON(
          GlosaJSONError(message: "Input is not valid UTF-8", line: 1, column: 1)),
        message: "Input is not valid UTF-8")
    }
    do throws(GlosaJSONError) {
      return try GlosaJSONReader.parse(text)
    } catch {
      throw GlosaSchemaError(kind: .invalidJSON(error), message: "Invalid JSON: \(error)")
    }
  }

  static func members(
    of value: GlosaJSONValue, directive: String
  ) throws(GlosaSchemaError) -> [GlosaJSONMember] {
    guard case .object(let members) = value else {
      throw GlosaSchemaError(
        kind: .notAnObject, message: "A \(directive) must be a JSON object")
    }
    return members
  }

  static func wrongType(
    _ directive: String, _ key: String, _ expected: String
  ) -> GlosaSchemaError {
    GlosaSchemaError(
      kind: .wrongType(key: key),
      message: "\(directive) key \"\(key)\" must be \(expected)")
  }

  static func string(
    _ value: GlosaJSONValue, _ directive: String, _ key: String
  ) throws(GlosaSchemaError) -> String {
    guard case .string(let string) = value else {
      throw wrongType(directive, key, "a string")
    }
    return string
  }

  static func number(
    _ value: GlosaJSONValue, _ directive: String, _ key: String
  ) throws(GlosaSchemaError) -> Double {
    guard case .number(let number) = value else {
      throw wrongType(directive, key, "a number")
    }
    return number
  }

  static func integer(
    _ value: GlosaJSONValue, _ directive: String, _ key: String
  ) throws(GlosaSchemaError) -> Int {
    guard case .number(let number) = value, let integer = Int(exactly: number) else {
      throw wrongType(directive, key, "an integer")
    }
    return integer
  }

  static func bool(
    _ value: GlosaJSONValue, _ directive: String, _ key: String
  ) throws(GlosaSchemaError) -> Bool {
    guard case .bool(let bool) = value else {
      throw wrongType(directive, key, "a boolean")
    }
    return bool
  }

  static func stringArray(
    _ value: GlosaJSONValue, _ directive: String, _ key: String
  ) throws(GlosaSchemaError) -> [String] {
    guard case .array(let elements) = value else {
      throw wrongType(directive, key, "an array of strings")
    }
    var strings: [String] = []
    strings.reserveCapacity(elements.count)
    for element in elements {
      guard case .string(let string) = element else {
        throw wrongType(directive, key, "an array of strings")
      }
      strings.append(string)
    }
    return strings
  }

  /// A `seed`: a JSON integer in 0...2^53 − 1, or a decimal string for the full
  /// `UInt64` range. A JSON number above 2^53 − 1 is rejected because a double
  /// cannot carry it exactly.
  static func seed(
    _ value: GlosaJSONValue, _ directive: String
  ) throws(GlosaSchemaError) -> UInt64 {
    switch value {
    case .number(let number):
      guard let seed = UInt64(exactly: number), seed <= maxExactInteger else {
        throw wrongType(
          directive, "seed",
          "an integer in 0...9007199254740991; larger seeds must be decimal strings")
      }
      return seed
    case .string(let string):
      guard !string.isEmpty,
        string.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
        let seed = UInt64(string)
      else {
        throw wrongType(
          directive, "seed", "an unsigned 64-bit integer or its decimal string")
      }
      return seed
    default:
      throw wrongType(
        directive, "seed", "an integer or a decimal string")
    }
  }

  /// A `seed` as written in the schema form: an integer up to 2^53 − 1, a
  /// decimal string above.
  static func seedValue(_ seed: UInt64) -> GlosaJSONValue {
    seed <= maxExactInteger ? .number(Double(seed)) : .string(String(seed))
  }

  /// Appends `extras` after the known members, skipping any extra whose key
  /// collides with a known key (it could not have been read as an extra).
  static func appendExtras(
    _ extras: [GlosaJSONMember], to members: inout [GlosaJSONMember], knownKeys: Set<String>
  ) {
    for extra in extras where !knownKeys.contains(extra.key) {
      members.append(extra)
    }
  }

  /// Compact JSON text for `value`, keeping object member order. Strings use
  /// RFC 8785 escaping and numbers ECMAScript formatting, as in `GlosaJCS`,
  /// but members are not sorted.
  static func compactText(_ value: GlosaJSONValue) -> String {
    var output = ""
    write(value, into: &output)
    return output
  }

  private static func write(_ value: GlosaJSONValue, into output: inout String) {
    switch value {
    case .string(let string): GlosaJCS.writeString(string, into: &output)
    case .number(let number): output += GlosaJCS.formatNumber(number)
    case .bool(let bool): output += bool ? "true" : "false"
    case .null: output += "null"
    case .array(let elements):
      output += "["
      for (index, element) in elements.enumerated() {
        if index > 0 { output += "," }
        write(element, into: &output)
      }
      output += "]"
    case .object(let members):
      output += "{"
      for (index, member) in members.enumerated() {
        if index > 0 { output += "," }
        GlosaJCS.writeString(member.key, into: &output)
        output += ":"
        write(member.value, into: &output)
      }
      output += "}"
    }
  }
}

// MARK: - Shot schema form

extension Shot {

  /// The known `shot` keys in canonical order (REQ § 2.7). Every other key is an
  /// extra attribute.
  public static let schemaKeys: [String] = [
    "prompt", "caption", "style", "model", "aspect", "width", "height", "steps",
    "guidance", "seed", "negative", "lora", "loraScale", "ref", "character", "output",
    "preview", "telemetry",
  ]

  /// The bare `shot` object exactly as `shot.schema.json` describes it: known
  /// keys in canonical order (`nil` ones omitted, `prompt` omitted when empty),
  /// then `extraAttributes` at the top level in read order. No `documentIndex`
  /// and no `{"shot": …}` wrapper. `seed` is an integer up to 2^53 − 1 and a
  /// decimal string above.
  ///
  /// This — not the synthesized `Codable` form — is the interchange form for
  /// render records and CLI input.
  public func schemaJSON() -> GlosaJSONValue {
    var members: [GlosaJSONMember] = []
    func add(_ key: String, _ value: GlosaJSONValue?) {
      if let value { members.append(GlosaJSONMember(key: key, value: value)) }
    }
    add("prompt", prompt.isEmpty ? nil : .string(prompt))
    add("caption", caption.map { .string($0) })
    add("style", style.map { .string($0) })
    add("model", model.map { .string($0) })
    add("aspect", aspect.map { .string($0) })
    add("width", width.map { .number(Double($0)) })
    add("height", height.map { .number(Double($0)) })
    add("steps", steps.map { .number(Double($0)) })
    add("guidance", guidance.map { .number($0) })
    add("seed", seed.map { GlosaSchemaCodec.seedValue($0) })
    add("negative", negative.map { .string($0) })
    add("lora", lora.map { .string($0) })
    add("loraScale", loraScale.map { .number($0) })
    add("ref", ref.map { .array($0.map { .string($0) }) })
    add("character", character.map { .string($0) })
    add("output", output.map { .string($0) })
    add("preview", preview.map { .bool($0) })
    add("telemetry", telemetry.map { .bool($0) })
    GlosaSchemaCodec.appendExtras(
      extraAttributes, to: &members, knownKeys: Set(Self.schemaKeys))
    return .object(members)
  }

  /// `schemaJSON()` as compact UTF-8 JSON text, member order kept.
  public func schemaJSONData() -> Data {
    Data(GlosaSchemaCodec.compactText(schemaJSON()).utf8)
  }

  /// Decodes a bare `shot` object (the schema form).
  ///
  /// A missing `prompt` decodes to `""` (a defaults shot). Unknown keys become
  /// `extraAttributes` in read order. `seed` is accepted as a JSON integer in
  /// 0...2^53 − 1 or as a decimal string (full `UInt64` range). If a known key
  /// appears more than once, the last occurrence wins.
  ///
  /// - Parameter documentIndex: Not part of the schema; the caller supplies it.
  /// - Throws: `GlosaSchemaError` when `schemaJSON` is not an object or a known
  ///   key holds a wrongly typed value.
  public init(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws(GlosaSchemaError) {
    let members = try GlosaSchemaCodec.members(of: schemaJSON, directive: "shot")
    self.init(documentIndex: documentIndex, prompt: "")
    let d = "shot"
    typealias C = GlosaSchemaCodec
    for member in members {
      let v = member.value
      switch member.key {
      case "prompt": prompt = try C.string(v, d, "prompt")
      case "caption": caption = try C.string(v, d, "caption")
      case "style": style = try C.string(v, d, "style")
      case "model": model = try C.string(v, d, "model")
      case "aspect": aspect = try C.string(v, d, "aspect")
      case "width": width = try C.integer(v, d, "width")
      case "height": height = try C.integer(v, d, "height")
      case "steps": steps = try C.integer(v, d, "steps")
      case "guidance": guidance = try C.number(v, d, "guidance")
      case "seed": seed = try C.seed(v, d)
      case "negative": negative = try C.string(v, d, "negative")
      case "lora": lora = try C.string(v, d, "lora")
      case "loraScale": loraScale = try C.number(v, d, "loraScale")
      case "ref": ref = try C.stringArray(v, d, "ref")
      case "character": character = try C.string(v, d, "character")
      case "output": output = try C.string(v, d, "output")
      case "preview": preview = try C.bool(v, d, "preview")
      case "telemetry": telemetry = try C.bool(v, d, "telemetry")
      default: extraAttributes.append(member)
      }
    }
  }

  /// Decodes a bare `shot` object from UTF-8 JSON text.
  ///
  /// - Throws: `GlosaSchemaError` — `.invalidJSON` (with line and column) when
  ///   the text is not JSON, otherwise as `init(schemaJSON:documentIndex:)`.
  public init(schemaJSONData: Data, documentIndex: Int = 0) throws(GlosaSchemaError) {
    try self.init(
      schemaJSON: try GlosaSchemaCodec.parseData(schemaJSONData), documentIndex: documentIndex)
  }
}
