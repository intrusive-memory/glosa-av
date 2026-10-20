import Foundation
import Testing

@testable import GlosaCore

/// Tests for the notation 2.0 JSON foundation: `GlosaJSONValue`,
/// the order-preserving `GlosaJSONReader`, and the RFC 8785 `GlosaJCS` writer.
///
/// Expected JCS number strings were produced independently with
/// ECMAScript (`node -e 'String(n)'`); the key-sort vector is RFC 8785 § 3.2.3.
@Suite("GlosaJSON reader and JCS writer")
struct GlosaJSONTests {

  // MARK: - Helpers

  private func parse(_ text: String) throws -> GlosaJSONValue {
    try GlosaJSONReader.parse(text)
  }

  private func parseError(_ text: String) -> GlosaJSONError? {
    do throws(GlosaJSONError) {
      _ = try GlosaJSONReader.parse(text)
      return nil
    } catch {
      return error
    }
  }

  // MARK: - Reader: value kinds

  @Test("Reader parses every scalar kind")
  func readerScalars() throws {
    #expect(try parse("\"hi\"") == .string("hi"))
    #expect(try parse("42") == .number(42))
    #expect(try parse("-12.5") == .number(-12.5))
    #expect(try parse("1e3") == .number(1000))
    #expect(try parse("2.5E-2") == .number(0.025))
    #expect(try parse("true") == .bool(true))
    #expect(try parse("false") == .bool(false))
    #expect(try parse("null") == .null)
    #expect(try parse("  \n\t 7 \r\n") == .number(7))
  }

  @Test("Reader parses arrays and empty containers")
  func readerArrays() throws {
    #expect(try parse("[]") == .array([]))
    #expect(try parse("{}") == .object([]))
    #expect(
      try parse("[1, \"two\", true, null, [3]]")
        == .array([.number(1), .string("two"), .bool(true), .null, .array([.number(3)])]))
  }

  @Test("Reader preserves object member order")
  func readerPreservesOrder() throws {
    let value = try parse(#"{"zeta": 1, "alpha": 2, "mid": 3, "beta": 4}"#)
    guard case .object(let members) = value else {
      Issue.record("expected object")
      return
    }
    #expect(members.map(\.key) == ["zeta", "alpha", "mid", "beta"])
    #expect(value["mid"] == .number(3))
    #expect(value["missing"] == nil)
  }

  @Test("Reader parses a nested multi-line shot object")
  func readerNested() throws {
    let text = """
      {"shot": {
        "prompt": "A keeper climbs the stair",
        "ref": ["KEEPER", "interior.png"],
        "guidance": 3.5,
        "custom": {"b": [1, {"c": null}], "a": false}
      }}
      """
    let expected: GlosaJSONValue = .object([
      GlosaJSONMember(
        key: "shot",
        value: .object([
          GlosaJSONMember(key: "prompt", value: .string("A keeper climbs the stair")),
          GlosaJSONMember(key: "ref", value: .array([.string("KEEPER"), .string("interior.png")])),
          GlosaJSONMember(key: "guidance", value: .number(3.5)),
          GlosaJSONMember(
            key: "custom",
            value: .object([
              GlosaJSONMember(
                key: "b",
                value: .array([.number(1), .object([GlosaJSONMember(key: "c", value: .null)])])),
              GlosaJSONMember(key: "a", value: .bool(false)),
            ])),
        ]))
    ])
    #expect(try parse(text) == expected)
  }

  // MARK: - Reader: strings

  @Test("Reader decodes every simple escape")
  func readerSimpleEscapes() throws {
    #expect(
      try parse(#""q\" b\\ s\/ \b\f\n\r\t""#) == .string("q\" b\\ s/ \u{08}\u{0C}\n\r\t"))
  }

  @Test("Reader decodes \\u escapes, including ]\\u005d and [\\u005b")
  func readerUnicodeEscapes() throws {
    #expect(try parse(#""]\u005d""#) == .string("]]"))
    #expect(try parse(#""[\u005b""#) == .string("[["))
    #expect(try parse(#""caf\u00e9 \u00E9""#) == .string("café é"))
    #expect(try parse(#""\u0000""#) == .string("\u{0}"))
  }

  @Test("Reader combines surrogate pairs and passes literal non-ASCII through")
  func readerSurrogatePairs() throws {
    #expect(try parse(#""\ud83d\ude00""#) == .string("😀"))
    #expect(try parse(#""\uD834\uDD1E clef""#) == .string("𝄞 clef"))
    #expect(try parse("\"literal 😀 ö\"") == .string("literal 😀 ö"))
  }

  @Test("Reader rejects lone surrogates")
  func readerLoneSurrogates() {
    #expect(parseError(#""\ud83d""#) != nil)
    #expect(parseError(#""\ud83dx""#) != nil)
    #expect(parseError(#""\ude00""#) != nil)
    #expect(parseError(#""\ud83d\u0041""#) != nil)
  }

  // MARK: - Reader: errors

  @Test("Reader reports line and column of a missing comma")
  func readerErrorMissingComma() throws {
    let error = try #require(parseError("{\n  \"a\": 1\n  \"b\": 2\n}"))
    #expect(error.line == 3)
    #expect(error.column == 3)
  }

  @Test("Reader reports line and column of a trailing comma")
  func readerErrorTrailingComma() throws {
    let error = try #require(parseError("[1, 2,]"))
    #expect(error.line == 1)
    #expect(error.column == 7)
  }

  @Test("Reader reports line and column of an unterminated string")
  func readerErrorUnterminatedString() throws {
    let error = try #require(parseError("{\"shot\": {\n\"prompt\": \"open"))
    #expect(error.line == 2)
    #expect(error.column == 16)
    #expect(error.message.contains("Unterminated"))
  }

  @Test("Reader reports position of a bad literal, a bad escape and trailing content")
  func readerErrorMisc() throws {
    let literal = try #require(parseError("[tru]"))
    #expect((literal.line, literal.column) == (1, 2))
    let escape = try #require(parseError("\"a\\x\""))
    #expect((escape.line, escape.column) == (1, 3))
    let trailing = try #require(parseError("{} x"))
    #expect((trailing.line, trailing.column) == (1, 4))
    let empty = try #require(parseError("   "))
    #expect((empty.line, empty.column) == (1, 4))
  }

  @Test("Reader enforces RFC 8259 strictness")
  func readerStrictness() {
    #expect(parseError("01") != nil)
    #expect(parseError("1.") != nil)
    #expect(parseError(".5") != nil)
    #expect(parseError("+1") != nil)
    #expect(parseError("1e") != nil)
    #expect(parseError("1e400") != nil)
    #expect(parseError("NaN") != nil)
    #expect(parseError("{'a': 1}") != nil)
    #expect(parseError("{\"a\" 1}") != nil)
    #expect(parseError("\"tab\there\"") != nil)
    #expect(parseError("// c\n1") != nil)
    #expect(parseError(#"{"a": 1, "a": 2}"#) != nil)
  }

  @Test("Reader counts columns in Unicode scalars and lines across CRLF")
  func readerPositionsUnicodeAndCRLF() throws {
    let error = try #require(parseError("\"😀é\" x"))
    #expect((error.line, error.column) == (1, 6))
    let crlf = try #require(parseError("[\r\n1,\r\n?]"))
    #expect((crlf.line, crlf.column) == (3, 1))
  }

  // MARK: - Codable

  @Test("GlosaJSONValue Codable round-trip keeps member order and {} vs []")
  func codableRoundTrip() throws {
    let value = try parse(
      #"{"z": [1, {}, []], "a": {"y": null, "x": "s"}, "m": true, "e": {}, "n": -0.5}"#)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(GlosaJSONValue.self, from: data)
    #expect(decoded == value)
    let members = [GlosaJSONMember(key: "k", value: .array([]))]
    let memberData = try JSONEncoder().encode(members)
    #expect(try JSONDecoder().decode([GlosaJSONMember].self, from: memberData) == members)
  }

  // MARK: - JCS: numbers

  @Test(
    "JCS formats numbers as ECMAScript Number.prototype.toString",
    arguments: [
      (1.0, "1"),
      (1e21, "1e+21"),
      (1e-7, "1e-7"),
      (-0.0, "0"),
      (0.0, "0"),
      (0.1, "0.1"),
      (123456789012345680000.0, "123456789012345680000"),
      (1e20, "100000000000000000000"),
      (123456789012345678.0, "123456789012345680"),
      (0.000001, "0.000001"),
      (0.0000015, "0.0000015"),
      (-1.5, "-1.5"),
      (9007199254740993.0, "9007199254740992"),
      (5e-324, "5e-324"),
      (1.7976931348623157e308, "1.7976931348623157e+308"),
      (333333333.3333333, "333333333.3333333"),
      (0.30000000000000004, "0.30000000000000004"),
      (-12.0, "-12"),
      (2.5e25, "2.5e+25"),
      (100.0, "100"),
      (1e16, "10000000000000000"),
      (12345.678, "12345.678"),
    ] as [(Double, String)]
  )
  func jcsNumbers(_ value: Double, _ expected: String) {
    #expect(GlosaJCS.formatNumber(value) == expected)
    #expect(GlosaJCS.canonicalString(.number(value)) == expected)
  }

  @Test("JCS numbers parsed from text canonicalize (1.0 → 1, 1E21 → 1e+21)")
  func jcsNumbersFromText() throws {
    #expect(GlosaJCS.canonicalString(try parse("[1.0, 1E21, 0.0000001, -0, 1.50]")) == "[1,1e+21,1e-7,0,1.5]")
  }

  // MARK: - JCS: keys and strings

  @Test("JCS sorts keys by UTF-16 code units (RFC 8785 § 3.2.3 vector)")
  func jcsKeySort() throws {
    let input = """
      {"\\u20ac": "Euro Sign", "\\r": "Carriage Return", "\\ufb33": "Hebrew Letter Dalet With Dagesh",
       "1": "One", "\\ud83d\\ude00": "Emoji: Grinning Face", "\\u0080": "Control",
       "\\u00f6": "Latin Small Letter O With Diaeresis"}
      """
    let expected =
      "{\"\\r\":\"Carriage Return\",\"1\":\"One\",\"\u{80}\":\"Control\","
      + "\"ö\":\"Latin Small Letter O With Diaeresis\",\"€\":\"Euro Sign\","
      + "\"😀\":\"Emoji: Grinning Face\",\"\u{FB33}\":\"Hebrew Letter Dalet With Dagesh\"}"
    #expect(GlosaJCS.canonicalString(try parse(input)) == expected)
  }

  @Test("JCS sorts nested objects, keeps array order, drops whitespace")
  func jcsNested() throws {
    let input = #"{ "b": [3, {"z": 1, "y": [true, false, null]}], "a": { "d": "x", "c": 2.0 } }"#
    #expect(
      GlosaJCS.canonicalString(try parse(input))
        == #"{"a":{"c":2,"d":"x"},"b":[3,{"y":[true,false,null],"z":1}]}"#)
  }

  @Test("JCS escapes strings minimally")
  func jcsStringEscapes() {
    let value: GlosaJSONValue = .string("\u{01}\u{1F}\u{7F}\u{2028}é\"\\\u{08}\u{0C}\n\r\t/]]")
    #expect(
      GlosaJCS.canonicalString(value)
        == "\"\\u0001\\u001f\u{7F}\u{2028}é\\\"\\\\\\b\\f\\n\\r\\t/]]\"")
  }

  @Test("JCS output re-parses to an equal value")
  func jcsRoundTrip() throws {
    let value = try parse(#"{"shot": {"prompt": "a \"q\" ]\u005d", "seed": 42, "ref": ["A", "B"], "x": {}}}"#)
    let canonical = GlosaJCS.canonicalString(value)
    #expect(canonical == #"{"shot":{"prompt":"a \"q\" ]]","ref":["A","B"],"seed":42,"x":{}}}"#)
    let reparsed = try parse(canonical)
    #expect(GlosaJCS.canonicalString(reparsed) == canonical)
  }
}
