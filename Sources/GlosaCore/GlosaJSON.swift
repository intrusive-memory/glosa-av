import Foundation

/// A raw JSON value as read from a GLOSA notation 2.0 block directive.
///
/// Unlike Foundation's JSON parser, objects keep their members **in read order**
/// (`[GlosaJSONMember]`), so unknown keys can be carried and re-serialized
/// exactly as authored. Numbers are IEEE-754 doubles, as in JSON / ECMAScript.
///
/// `Codable` uses a single-value container: strings, numbers, booleans and
/// `null` encode as themselves, arrays as arrays, and objects as
/// `{"object": [{"key": …, "value": …}, …]}` — an ordered member list that
/// survives Foundation's JSON coders. The wrapper keeps an empty object
/// distinct from an empty array. This is the in-process persistence form; the
/// notation itself is read with `GlosaJSONReader` and canonicalized with
/// `GlosaJCS`.
public enum GlosaJSONValue: Sendable, Equatable, Hashable, Codable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case array([GlosaJSONValue])
  case object([GlosaJSONMember])

  /// Coding wrapper that marks an object (and so keeps `{}` distinct from `[]`).
  private struct ObjectBox: Codable {
    var object: [GlosaJSONMember]
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([GlosaJSONValue].self) {
      self = .array(value)
    } else if let box = try? container.decode(ObjectBox.self) {
      self = .object(box.object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Value is not a GlosaJSONValue")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    case .array(let values): try container.encode(values)
    case .object(let members): try container.encode(ObjectBox(object: members))
    }
  }

  /// The value of the first member named `key` when this is an object; otherwise `nil`.
  public subscript(key: String) -> GlosaJSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first(where: { $0.key == key })?.value
  }
}

/// One member of a JSON object, kept in read order inside `GlosaJSONValue.object`.
public struct GlosaJSONMember: Sendable, Equatable, Hashable, Codable {
  public var key: String
  public var value: GlosaJSONValue

  public init(key: String, value: GlosaJSONValue) {
    self.key = key
    self.value = value
  }
}
