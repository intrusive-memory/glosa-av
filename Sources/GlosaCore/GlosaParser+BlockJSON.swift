import Foundation

// MARK: - Notation 2.0 block directives (JSON notes)

extension GlosaParser {

  /// The outcome of reading one notation 2.0 block-directive candidate note.
  enum BlockDirectiveNote: Sendable {
    /// A `{"shot": {…}}` note decoded into a `Shot`.
    case shot(Shot)
    /// An `{"include": {…}}` note decoded into an `Include`.
    case include(Include)
    /// The note yields no event; the diagnostic explains why.
    case rejected(GlosaDiagnostic)
  }

  /// The block directives notation 2.0 knows, in the order named in messages.
  static let knownBlockDirectives = ["shot", "include"]

  /// Whether an element of the notes array is a notation 2.0 block-directive
  /// candidate: its trimmed text starts with `{`, optional whitespace
  /// (newlines included), then `"`.
  ///
  /// The parser and the validator both apply this test before any substring
  /// check, so a candidate is never read as a scope tag, a 1.0 tag, or
  /// dialogue. Prose such as `{beat} Fine.` is not a candidate.
  ///
  /// - Parameter trimmed: The element with leading and trailing whitespace
  ///   and newlines removed.
  static func isBlockDirectiveCandidate(_ trimmed: String) -> Bool {
    var scalars = trimmed.unicodeScalars.makeIterator()
    guard scalars.next() == "{" else { return false }
    while let scalar = scalars.next() {
      if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
      return scalar == "\""
    }
    return false
  }

  /// Read a block-directive candidate note as notation 2.0 JSON.
  ///
  /// - A JSON object with exactly one key, `shot` or `include`, whose value
  ///   decodes through the schema codec, yields that directive.
  /// - Text that is not valid JSON yields `.invalidBlockDirectiveJSON`
  ///   (error) carrying the reader's line and column within the note.
  /// - A known directive whose object fails the schema (a wrongly typed known
  ///   key, a missing `include.src`, a non-object value) yields
  ///   `.invalidBlockDirectiveJSON` (error) naming the key.
  /// - Any other shape yields `.unknownBlockDirective` (warning).
  ///
  /// - Parameters:
  ///   - note: The note text as the caller passed it. Error positions are
  ///     relative to this text.
  ///   - documentIndex: The note's position in the notes array.
  ///   - line: The diagnostic line (note index + 1).
  func readBlockDirectiveNote(
    _ note: String,
    documentIndex: Int,
    line: Int
  ) -> BlockDirectiveNote {
    let value: GlosaJSONValue
    do throws(GlosaJSONError) {
      value = try GlosaJSONReader.parse(note)
    } catch {
      return .rejected(
        GlosaDiagnostic(
          severity: .error,
          message:
            "Block directive note is not valid JSON at line \(error.line), column \(error.column): "
            + "\(error.message); the note is ignored",
          line: line,
          code: .invalidBlockDirectiveJSON
        ))
    }

    guard case .object(let members) = value, members.count == 1,
      let member = members.first,
      Self.knownBlockDirectives.contains(member.key)
    else {
      return .rejected(
        GlosaDiagnostic(
          severity: .warning,
          message: Self.unknownShapeMessage(value),
          line: line,
          code: .unknownBlockDirective
        ))
    }

    do throws(GlosaSchemaError) {
      if member.key == "shot" {
        return .shot(try Shot(schemaJSON: member.value, documentIndex: documentIndex))
      }
      return .include(try Include(schemaJSON: member.value, documentIndex: documentIndex))
    } catch {
      let key = error.key ?? member.key
      return .rejected(
        GlosaDiagnostic(
          severity: .error,
          message:
            "Invalid \"\(member.key)\" block directive, key \"\(key)\": \(error.message); "
            + "the note is ignored",
          line: line,
          code: .invalidBlockDirectiveJSON
        ))
    }
  }

  /// The diagnostic that names the 2.0 replacement for a 1.0 tag directive.
  static func deprecatedTagDiagnostic(directive: String, line: Int) -> GlosaDiagnostic {
    GlosaDiagnostic(
      severity: .info,
      message:
        "<\(directive)/> is the deprecated notation 1.0 tag form; "
        + "write it as a notation 2.0 JSON note: {\"\(directive)\": {…}}",
      line: line,
      code: .deprecatedTagDirective
    )
  }

  private static func unknownShapeMessage(_ value: GlosaJSONValue) -> String {
    let known = knownBlockDirectives.map { "\"\($0)\"" }.joined(separator: " or ")
    guard case .object(let members) = value else {
      return "Block directive note is not a JSON object; expected a single \(known) key; "
        + "the note is ignored"
    }
    if members.count == 1, let key = members.first?.key {
      return "Unknown block directive \"\(key)\" (expected \(known)); the note is ignored"
    }
    return "Block directive note has \(members.count) keys; expected exactly one "
      + "\(known) key; the note is ignored"
  }
}
