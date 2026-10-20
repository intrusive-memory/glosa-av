import Foundation

// MARK: - Canonical note serialization (notation 2.0)

extension Shot {

  /// The canonical notation 2.0 block directive note for this shot:
  /// `[[ {"shot": {` … `}} ]]`, one key per line, two-space indent.
  ///
  /// Keys come from `schemaJSON()` (canonical order, then extras in read
  /// order; an empty `prompt` is omitted). `guidance` and `loraScale` always
  /// carry a decimal point (`4` → `4.0`); other numbers use ECMAScript
  /// formatting. `seed` is an integer up to 2^53 − 1 and a decimal string
  /// above. A shot with no keys at all is written `[[ {"shot": {}} ]]`.
  /// `documentIndex` is not serialized.
  ///
  /// Inside any string, a second consecutive `]` or `[` is written `]` /
  /// `[`, so the text never contains `]]` or `[[` and cannot end or nest
  /// the note. `serialize(parse(n)) == n` holds for canonical notes and
  /// `parse(serialize(x)) == x` (ignoring `documentIndex`) for every shot.
  public func serialize() -> String {
    GlosaNoteSerializer.note(
      directive: "shot", object: schemaJSON(), decimalKeys: ["guidance", "loraScale"])
  }
}

extension Include {

  /// The canonical notation 2.0 block directive note for this include:
  /// `[[ {"include": {` … `}} ]]`, laid out as `Shot.serialize()` is.
  /// `gain`, `fadeIn` and `fadeOut` always carry a decimal point
  /// (`-12` → `-12.0`). `documentIndex` is not serialized.
  public func serialize() -> String {
    GlosaNoteSerializer.note(
      directive: "include", object: schemaJSON(), decimalKeys: ["gain", "fadeIn", "fadeOut"])
  }
}

/// Writes the canonical block directive layout shared by `Shot` and `Include`.
enum GlosaNoteSerializer {

  static func note(
    directive: String, object: GlosaJSONValue, decimalKeys: Set<String>
  ) -> String {
    guard case .object(let members) = object, !members.isEmpty else {
      return "[[ {\"\(directive)\": {}} ]]"
    }
    var lines: [String] = []
    for member in members {
      var line = "  "
      writeString(member.key, into: &line)
      line += ": "
      if decimalKeys.contains(member.key), case .number(let number) = member.value {
        line += decimalNumber(number)
      } else if member.key == "ref", case .array(let elements) = member.value,
        elements.allSatisfy({ if case .string = $0 { true } else { false } })
      {
        // Spaced array, as in the REQUIREMENTS § 1.1 example.
        line += "["
        for (index, element) in elements.enumerated() {
          if index > 0 { line += ", " }
          if case .string(let string) = element { writeString(string, into: &line) }
        }
        line += "]"
      } else {
        writeCompact(member.value, into: &line)
      }
      lines.append(line)
    }
    return "[[ {\"\(directive)\": {\n" + lines.joined(separator: ",\n") + "\n}} ]]"
  }

  /// ECMAScript number text, with `.0` appended when it would read as an integer.
  static func decimalNumber(_ number: Double) -> String {
    let text = GlosaJCS.formatNumber(number)
    if text == "null" { return text }
    return text.contains(".") || text.contains("e") ? text : text + ".0"
  }

  /// A JSON string literal (RFC 8785 escaping) in which a `]` directly after a
  /// `]`, or a `[` directly after a `[`, is written as a `\u` escape.
  static func writeString(_ string: String, into output: inout String) {
    var literal = ""
    GlosaJCS.writeString(string, into: &literal)
    var previous: Unicode.Scalar?
    for scalar in literal.unicodeScalars {
      if scalar == "]" && previous == "]" {
        output += "\\u005d"
      } else if scalar == "[" && previous == "[" {
        output += "\\u005b"
      } else {
        output.unicodeScalars.append(scalar)
      }
      previous = scalar
    }
  }

  /// Compact one-line JSON. A space separates adjacent `[` `[` or `]` `]`
  /// so structural brackets never form a note delimiter.
  static func writeCompact(_ value: GlosaJSONValue, into output: inout String) {
    switch value {
    case .string(let string): writeString(string, into: &output)
    case .number(let number): output += GlosaJCS.formatNumber(number)
    case .bool(let bool): output += bool ? "true" : "false"
    case .null: output += "null"
    case .array(let elements):
      if output.hasSuffix("[") { output += " " }
      output += "["
      for (index, element) in elements.enumerated() {
        if index > 0 { output += "," }
        writeCompact(element, into: &output)
      }
      if output.hasSuffix("]") { output += " " }
      output += "]"
    case .object(let members):
      output += "{"
      for (index, member) in members.enumerated() {
        if index > 0 { output += "," }
        writeString(member.key, into: &output)
        output += ":"
        writeCompact(member.value, into: &output)
      }
      output += "}"
    }
  }
}
