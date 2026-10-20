import Foundation

// MARK: - Include schema form

extension Include {

  /// The known `include` keys in canonical order (REQ § 2.7). Every other key is
  /// an extra attribute.
  public static let schemaKeys: [String] = [
    "src", "gain", "mode", "fadeIn", "fadeOut", "prompt",
  ]

  /// The bare `include` object exactly as `include.schema.json` describes it:
  /// known keys in canonical order (`nil` ones omitted), then
  /// `extraAttributes` at the top level in read order. No `documentIndex` and
  /// no `{"include": …}` wrapper.
  ///
  /// This — not the synthesized `Codable` form — is the interchange form.
  public func schemaJSON() -> GlosaJSONValue {
    var members: [GlosaJSONMember] = [GlosaJSONMember(key: "src", value: .string(src))]
    func add(_ key: String, _ value: GlosaJSONValue?) {
      if let value { members.append(GlosaJSONMember(key: key, value: value)) }
    }
    add("gain", gain.map { .number($0) })
    add("mode", mode.map { .string($0.rawValue) })
    add("fadeIn", fadeIn.map { .number($0) })
    add("fadeOut", fadeOut.map { .number($0) })
    add("prompt", prompt.map { .string($0) })
    GlosaSchemaCodec.appendExtras(
      extraAttributes, to: &members, knownKeys: Set(Self.schemaKeys))
    return .object(members)
  }

  /// `schemaJSON()` as compact UTF-8 JSON text, member order kept.
  public func schemaJSONData() -> Data {
    Data(GlosaSchemaCodec.compactText(schemaJSON()).utf8)
  }

  /// Decodes a bare `include` object (the schema form).
  ///
  /// `src` is required. Unknown keys become `extraAttributes` in read order.
  /// An unrecognized `mode` string decodes to `mode == nil`, as the 1.0 tag
  /// form does. If a known key appears more than once, the last occurrence wins.
  ///
  /// - Parameter documentIndex: Not part of the schema; the caller supplies it.
  /// - Throws: `GlosaSchemaError` when `schemaJSON` is not an object, a known
  ///   key holds a wrongly typed value, or `src` is missing.
  public init(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws(GlosaSchemaError) {
    let members = try GlosaSchemaCodec.members(of: schemaJSON, directive: "include")
    let d = "include"
    typealias C = GlosaSchemaCodec
    var src: String?
    self.init(documentIndex: documentIndex, src: "")
    for member in members {
      let v = member.value
      switch member.key {
      case "src": src = try C.string(v, d, "src")
      case "gain": gain = try C.number(v, d, "gain")
      case "mode": mode = IncludeMode(rawValue: try C.string(v, d, "mode"))
      case "fadeIn": fadeIn = try C.number(v, d, "fadeIn")
      case "fadeOut": fadeOut = try C.number(v, d, "fadeOut")
      case "prompt": prompt = try C.string(v, d, "prompt")
      default: extraAttributes.append(member)
      }
    }
    guard let src else {
      throw GlosaSchemaError(
        kind: .missingKey("src"), message: "include is missing the required key \"src\"")
    }
    self.src = src
  }

  /// Decodes a bare `include` object from UTF-8 JSON text.
  ///
  /// - Throws: `GlosaSchemaError` — `.invalidJSON` (with line and column) when
  ///   the text is not JSON, otherwise as `init(schemaJSON:documentIndex:)`.
  public init(schemaJSONData: Data, documentIndex: Int = 0) throws(GlosaSchemaError) {
    try self.init(
      schemaJSON: try GlosaSchemaCodec.parseData(schemaJSONData), documentIndex: documentIndex)
  }
}
