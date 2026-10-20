import Foundation

/// RFC 8785 JSON Canonicalization Scheme (JCS) writer.
///
/// Produces the canonical, whitespace-free JSON text of a `GlosaJSONValue`:
/// - object members sorted by their names' UTF-16 code units (RFC 8785 § 3.2.3);
/// - numbers formatted as ECMAScript `Number.prototype.toString` does
///   (shortest round-trip digits; exponent form when the decimal exponent is
///   ≥ 21 or < -6; `-0` written as `0`) (§ 3.2.2.3);
/// - strings with the minimal escaping of § 3.2.2.2 (`\"`, `\\`, `\b`, `\f`,
///   `\n`, `\r`, `\t`, other controls as lowercase `\u00xx`; everything else literal);
/// - arrays in their original order.
///
/// `GlosaJSONValue` cannot hold NaN or infinities when produced by
/// `GlosaJSONReader`; a non-finite number is written as `null`, matching
/// ECMAScript `JSON.stringify`.
public enum GlosaJCS {

  /// The canonical JSON text of `value`.
  public static func canonicalString(_ value: GlosaJSONValue) -> String {
    var output = ""
    write(value, into: &output)
    return output
  }

  private static func write(_ value: GlosaJSONValue, into output: inout String) {
    switch value {
    case .null:
      output += "null"
    case .bool(let flag):
      output += flag ? "true" : "false"
    case .number(let number):
      output += formatNumber(number)
    case .string(let string):
      writeString(string, into: &output)
    case .array(let values):
      output += "["
      for (offset, element) in values.enumerated() {
        if offset > 0 { output += "," }
        write(element, into: &output)
      }
      output += "]"
    case .object(let members):
      let sorted = members.sorted { lhs, rhs in
        lhs.key.utf16.lexicographicallyPrecedes(rhs.key.utf16)
      }
      output += "{"
      for (offset, member) in sorted.enumerated() {
        if offset > 0 { output += "," }
        writeString(member.key, into: &output)
        output += ":"
        write(member.value, into: &output)
      }
      output += "}"
    }
  }

  private static let hexDigits: [Character] = Array("0123456789abcdef")

  /// Writes `string` as a JSON string literal with RFC 8785 § 3.2.2.2 escaping.
  static func writeString(_ string: String, into output: inout String) {
    output += "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"": output += "\\\""
      case "\\": output += "\\\\"
      case "\u{08}": output += "\\b"
      case "\u{0C}": output += "\\f"
      case "\n": output += "\\n"
      case "\r": output += "\\r"
      case "\t": output += "\\t"
      default:
        if scalar.value < 0x20 {
          output += "\\u00"
          output.append(hexDigits[Int(scalar.value >> 4)])
          output.append(hexDigits[Int(scalar.value & 0xF)])
        } else {
          output.unicodeScalars.append(scalar)
        }
      }
    }
    output += "\""
  }

  /// Formats `value` as ECMAScript `Number.prototype.toString(10)` does.
  ///
  /// Swift's `Double.description` yields the shortest digit string that
  /// round-trips (closest to the exact value on ties), which is the digit
  /// selection ECMAScript requires; this re-lays those digits out with the
  /// ECMAScript placement rules (ECMA-262 Number::toString).
  public static func formatNumber(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    if value == 0 { return "0" }  // also -0

    var text = value.magnitude.description  // e.g. "1e-07", "0.1", "1.2345678901234568e+20"
    var exponent = 0
    if let eIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      exponent = Int(text[text.index(after: eIndex)...])!
      text = String(text[..<eIndex])
    }
    var digits: [Character]
    var pointPosition: Int
    if let dot = text.firstIndex(of: ".") {
      pointPosition = text.distance(from: text.startIndex, to: dot)
      digits = Array(text[..<dot]) + Array(text[text.index(after: dot)...])
    } else {
      pointPosition = text.count
      digits = Array(text)
    }
    while digits.first == "0" {
      digits.removeFirst()
      pointPosition -= 1
    }
    while digits.last == "0" {
      digits.removeLast()
    }

    // value = 0.d1d2…dk × 10^n
    let k = digits.count
    let n = pointPosition + exponent
    let digitString = String(digits)
    var result = value < 0 ? "-" : ""

    if k <= n && n <= 21 {
      result += digitString + String(repeating: "0", count: n - k)
    } else if 0 < n && n <= 21 {
      result += String(digits[0..<n]) + "." + String(digits[n...])
    } else if -6 < n && n <= 0 {
      result += "0." + String(repeating: "0", count: -n) + digitString
    } else {
      let e = n - 1
      let sign = e < 0 ? "-" : "+"
      result += String(digits[0])
      if k > 1 { result += "." + String(digits[1...]) }
      result += "e" + sign + String(e.magnitude)
    }
    return result
  }
}
