import Foundation

/// A JSON syntax error with its 1-based position in the reader's input.
///
/// `line` counts line feeds (`\n`, `\r\n` and a lone `\r` each end a line);
/// `column` counts Unicode scalars from the start of the line.
public struct GlosaJSONError: Error, Sendable, Equatable, CustomStringConvertible {
  public var message: String
  public var line: Int
  public var column: Int

  public init(message: String, line: Int, column: Int) {
    self.message = message
    self.line = line
    self.column = column
  }

  public var description: String { "\(message) (line \(line), column \(column))" }
}

/// A hand-written, order-preserving RFC 8259 JSON reader.
///
/// GlosaCore cannot use Foundation's JSON parser or decoder for notation 2.0
/// notes: they lose object member order (so unknown keys cannot be carried in
/// read order) and do not report error positions. This reader is strict
/// RFC 8259: one value surrounded by optional whitespace, no comments, no
/// trailing commas, no leading zeros, no lone surrogates. Duplicate member
/// names are rejected, because canonical JSON (RFC 8785) requires unique names.
public enum GlosaJSONReader {

  /// Maximum nesting depth of arrays and objects.
  public static let maxDepth = 512

  /// Parses `text` as exactly one JSON value.
  public static func parse(_ text: String) throws(GlosaJSONError) -> GlosaJSONValue {
    var parser = Parser(scalars: Array(text.unicodeScalars))
    parser.skipWhitespace()
    let value = try parser.parseValue(depth: 0)
    parser.skipWhitespace()
    if !parser.atEnd {
      throw parser.error("Unexpected '\(parser.peekDescription)' after the JSON value")
    }
    return value
  }

  private struct Parser {
    let scalars: [Unicode.Scalar]
    var index = 0
    var line = 1
    var column = 1

    init(scalars: [Unicode.Scalar]) {
      self.scalars = scalars
    }

    var atEnd: Bool { index >= scalars.count }
    var peek: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    var peekDescription: String {
      guard let scalar = peek else { return "end of input" }
      if scalar.value < 0x20 { return String(format: "U+%04X", scalar.value) }
      return String(Character(scalar))
    }

    func error(_ message: String) -> GlosaJSONError {
      GlosaJSONError(message: message, line: line, column: column)
    }

    func error(_ message: String, line: Int, column: Int) -> GlosaJSONError {
      GlosaJSONError(message: message, line: line, column: column)
    }

    mutating func advance() {
      let scalar = scalars[index]
      index += 1
      if scalar == "\n" {
        line += 1
        column = 1
      } else if scalar == "\r" {
        if peek != "\n" {
          line += 1
          column = 1
        }
      } else {
        column += 1
      }
    }

    mutating func skipWhitespace() {
      while let scalar = peek, scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
        advance()
      }
    }

    mutating func expectLiteral(_ literal: String, _ value: GlosaJSONValue) throws(GlosaJSONError)
      -> GlosaJSONValue
    {
      let startLine = line
      let startColumn = column
      for expected in literal.unicodeScalars {
        guard peek == expected else {
          throw error("Invalid literal; expected '\(literal)'", line: startLine, column: startColumn)
        }
        advance()
      }
      return value
    }

    mutating func parseValue(depth: Int) throws(GlosaJSONError) -> GlosaJSONValue {
      guard let scalar = peek else { throw error("Unexpected end of input; expected a value") }
      switch scalar {
      case "{": return try parseObject(depth: depth + 1)
      case "[": return try parseArray(depth: depth + 1)
      case "\"": return .string(try parseString())
      case "t": return try expectLiteral("true", .bool(true))
      case "f": return try expectLiteral("false", .bool(false))
      case "n": return try expectLiteral("null", .null)
      case "-", "0"..."9": return try parseNumber()
      default: throw error("Unexpected '\(peekDescription)'; expected a value")
      }
    }

    mutating func parseObject(depth: Int) throws(GlosaJSONError) -> GlosaJSONValue {
      if depth > GlosaJSONReader.maxDepth { throw error("Nesting deeper than \(GlosaJSONReader.maxDepth)") }
      advance()  // {
      var members: [GlosaJSONMember] = []
      var seen: Set<String> = []
      skipWhitespace()
      if peek == "}" {
        advance()
        return .object([])
      }
      while true {
        guard peek == "\"" else {
          throw error("Unexpected \(describeHere()); expected a member name string")
        }
        let keyLine = line
        let keyColumn = column
        let key = try parseString()
        if !seen.insert(key).inserted {
          throw error("Duplicate member name \"\(key)\"", line: keyLine, column: keyColumn)
        }
        skipWhitespace()
        guard peek == ":" else { throw error("Unexpected \(describeHere()); expected ':'") }
        advance()
        skipWhitespace()
        let value = try parseValue(depth: depth)
        members.append(GlosaJSONMember(key: key, value: value))
        skipWhitespace()
        if peek == "," {
          advance()
          skipWhitespace()
        } else if peek == "}" {
          advance()
          return .object(members)
        } else {
          throw error("Unexpected \(describeHere()); expected ',' or '}'")
        }
      }
    }

    mutating func parseArray(depth: Int) throws(GlosaJSONError) -> GlosaJSONValue {
      if depth > GlosaJSONReader.maxDepth { throw error("Nesting deeper than \(GlosaJSONReader.maxDepth)") }
      advance()  // [
      var values: [GlosaJSONValue] = []
      skipWhitespace()
      if peek == "]" {
        advance()
        return .array([])
      }
      while true {
        values.append(try parseValue(depth: depth))
        skipWhitespace()
        if peek == "," {
          advance()
          skipWhitespace()
        } else if peek == "]" {
          advance()
          return .array(values)
        } else {
          throw error("Unexpected \(describeHere()); expected ',' or ']'")
        }
      }
    }

    func describeHere() -> String {
      atEnd ? "end of input" : "'\(peekDescription)'"
    }

    mutating func parseHex4() throws(GlosaJSONError) -> UInt32 {
      var result: UInt32 = 0
      for _ in 0..<4 {
        guard let scalar = peek, let digit = hexValue(scalar) else {
          throw error("Invalid \\u escape; expected four hex digits")
        }
        result = result * 16 + digit
        advance()
      }
      return result
    }

    func hexValue(_ scalar: Unicode.Scalar) -> UInt32? {
      switch scalar {
      case "0"..."9": return scalar.value - 0x30
      case "a"..."f": return scalar.value - 0x61 + 10
      case "A"..."F": return scalar.value - 0x41 + 10
      default: return nil
      }
    }

    mutating func parseString() throws(GlosaJSONError) -> String {
      advance()  // opening quote
      var result = String.UnicodeScalarView()
      while true {
        guard let scalar = peek else { throw error("Unterminated string") }
        switch scalar {
        case "\"":
          advance()
          return String(result)
        case "\\":
          let escLine = line
          let escColumn = column
          advance()
          guard let escape = peek else { throw error("Unterminated string") }
          switch escape {
          case "\"": result.append("\""); advance()
          case "\\": result.append("\\"); advance()
          case "/": result.append("/"); advance()
          case "b": result.append("\u{08}"); advance()
          case "f": result.append("\u{0C}"); advance()
          case "n": result.append("\n"); advance()
          case "r": result.append("\r"); advance()
          case "t": result.append("\t"); advance()
          case "u":
            advance()
            let unit = try parseHex4()
            if (0xD800...0xDBFF).contains(unit) {
              guard peek == "\\" else {
                throw error("Unpaired high surrogate", line: escLine, column: escColumn)
              }
              advance()
              guard peek == "u" else {
                throw error("Unpaired high surrogate", line: escLine, column: escColumn)
              }
              advance()
              let low = try parseHex4()
              guard (0xDC00...0xDFFF).contains(low) else {
                throw error("Unpaired high surrogate", line: escLine, column: escColumn)
              }
              let combined = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
              result.append(Unicode.Scalar(combined)!)
            } else if (0xDC00...0xDFFF).contains(unit) {
              throw error("Unpaired low surrogate", line: escLine, column: escColumn)
            } else {
              result.append(Unicode.Scalar(unit)!)
            }
          default:
            throw error("Invalid escape '\\\(peekDescription)'", line: escLine, column: escColumn)
          }
        default:
          if scalar.value < 0x20 {
            throw error("Unescaped control character \(peekDescription) in string")
          }
          result.append(scalar)
          advance()
        }
      }
    }

    mutating func parseNumber() throws(GlosaJSONError) -> GlosaJSONValue {
      let startLine = line
      let startColumn = column
      var text = ""
      func isDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return ("0"..."9").contains(scalar)
      }
      if peek == "-" {
        text.unicodeScalars.append("-")
        advance()
      }
      guard isDigit(peek) else { throw error("Invalid number; expected a digit") }
      if peek == "0" {
        text.unicodeScalars.append("0")
        advance()
        if isDigit(peek) { throw error("Invalid number; leading zeros are not allowed") }
      } else {
        while isDigit(peek) {
          text.unicodeScalars.append(peek!)
          advance()
        }
      }
      if peek == "." {
        text.unicodeScalars.append(".")
        advance()
        guard isDigit(peek) else { throw error("Invalid number; expected a digit after '.'") }
        while isDigit(peek) {
          text.unicodeScalars.append(peek!)
          advance()
        }
      }
      if peek == "e" || peek == "E" {
        text.unicodeScalars.append("e")
        advance()
        if peek == "+" || peek == "-" {
          text.unicodeScalars.append(peek!)
          advance()
        }
        guard isDigit(peek) else { throw error("Invalid number; expected a digit in the exponent") }
        while isDigit(peek) {
          text.unicodeScalars.append(peek!)
          advance()
        }
      }
      guard let value = Double(text), value.isFinite else {
        throw error("Number \(text) is out of range", line: startLine, column: startColumn)
      }
      return .number(value)
    }
  }
}
