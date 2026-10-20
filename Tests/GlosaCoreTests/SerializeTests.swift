import Foundation
import Testing

@testable import GlosaCore

/// Tests for canonical note serialization (`Shot.serialize()`, `Include.serialize()`).
@Suite("Canonical note serialization")
struct SerializeTests {

  let parser = GlosaParser()

  /// The REQUIREMENTS § 1.1 shot note, verbatim.
  static let exampleShot = """
    [[ {"shot": {
      "prompt": "A lighthouse keeper climbs the spiral stair at dusk, lantern in hand",
      "caption": "The light has to be lit by nine.",
      "style": "ink wash, muted blue palette",
      "model": "klein4b",
      "aspect": "wide",
      "ref": ["KEEPER", "lighthouse-interior.png"],
      "output": "storyboards/keeper-01.png"
    }} ]]
    """

  private func parseShots(_ note: String) -> [Shot] {
    parser.parseFountainWithDiagnostics(notes: [Self.stripBrackets(note)]).score.shots
  }

  private func parseIncludes(_ note: String) -> [Include] {
    parser.parseFountainWithDiagnostics(notes: [Self.stripBrackets(note)]).score.includes
  }

  /// The content between the outer `[[` and `]]`.
  static func stripBrackets(_ note: String) -> String {
    precondition(note.hasPrefix("[[") && note.hasSuffix("]]"))
    return String(note.dropFirst(2).dropLast(2))
  }

  // MARK: - Acceptance

  @Test("Acceptance 3: serialize reproduces the REQ § 1.1 shot note byte-for-byte")
  func acceptance3ByteForByte() throws {
    let shot = try #require(parseShots(Self.exampleShot).first)
    #expect(shot.serialize() == Self.exampleShot)
  }

  // MARK: - Layout

  @Test("Include layout and decimal forcing")
  func includeLayout() {
    let include = Include(documentIndex: 0, src: "audio/surf.m4a", gain: -12, mode: .bed)
    #expect(
      include.serialize()
        == """
        [[ {"include": {
          "src": "audio/surf.m4a",
          "gain": -12.0,
          "mode": "bed"
        }} ]]
        """)
  }

  @Test("Decimal formatting on the named keys, ECMAScript elsewhere")
  func decimalFormatting() {
    let shot = Shot(
      documentIndex: 0, prompt: "p", width: 512, guidance: 4, loraScale: 0.35,
      extraAttributes: [
        GlosaJSONMember(key: "x", value: .number(4)),
        GlosaJSONMember(key: "y", value: .number(1e21)),
        GlosaJSONMember(key: "z", value: .number(0.000001)),
      ])
    let text = shot.serialize()
    #expect(text.contains("\"width\": 512,\n"))
    #expect(text.contains("\"guidance\": 4.0,\n"))
    #expect(text.contains("\"loraScale\": 0.35,\n"))
    #expect(text.contains("\"x\": 4,\n"))
    #expect(text.contains("\"y\": 1e+21,\n"))
    #expect(text.contains("\"z\": 0.000001\n"))

    let include = Include(
      documentIndex: 0, src: "a", gain: 0.35, fadeIn: 2, fadeOut: -0.0)
    let inc = include.serialize()
    #expect(inc.contains("\"gain\": 0.35,"))
    #expect(inc.contains("\"fadeIn\": 2.0,"))
    #expect(inc.contains("\"fadeOut\": 0.0\n"))
  }

  @Test("Key order: canonical keys, then extras in read order")
  func keyOrder() {
    let shot = Shot(
      documentIndex: 0, prompt: "p", caption: "c", seed: 7, character: "K",
      extraAttributes: [
        GlosaJSONMember(key: "zeta", value: .bool(true)),
        GlosaJSONMember(key: "alpha", value: .null),
      ])
    let keys = shot.serialize().split(separator: "\n").compactMap { line -> String? in
      guard line.hasPrefix("  \"") else { return nil }
      return String(line.dropFirst(3).prefix { $0 != "\"" })
    }
    #expect(keys == ["prompt", "caption", "seed", "character", "zeta", "alpha"])
  }

  @Test("Empty prompt is omitted; a keyless shot is [[ {\"shot\": {}} ]] and re-parses")
  func emptyShot() {
    let shot = Shot(documentIndex: 0, prompt: "")
    #expect(shot.serialize() == "[[ {\"shot\": {}} ]]")
    #expect(parseShots(shot.serialize()) == [shot])

    let styled = Shot(documentIndex: 0, prompt: "", style: "s")
    #expect(!styled.serialize().contains("\"prompt\""))
    #expect(parseShots(styled.serialize()) == [styled])
  }

  @Test("Seed: number up to 2^53 - 1, decimal string above")
  func seedRule() {
    let small = Shot(documentIndex: 0, prompt: "p", seed: 9_007_199_254_740_991)
    #expect(small.serialize().contains("\"seed\": 9007199254740991\n"))
    let big = Shot(documentIndex: 0, prompt: "p", seed: UInt64.max)
    #expect(big.serialize().contains("\"seed\": \"18446744073709551615\"\n"))
    #expect(parseShots(big.serialize()) == [big])
  }

  // MARK: - Escapes

  @Test("]] and [[ never appear inside a value, including overlapping runs")
  func bracketEscapes() {
    let nasty = ["]]", "[[", "]]]", "[[[", "]]]]", "a]]b[[c", "]][[]][[", "]", "[", "]\\]"]
    for value in nasty {
      let shot = Shot(
        documentIndex: 0, prompt: value, ref: [value, value],
        extraAttributes: [
          GlosaJSONMember(key: value, value: .string(value)),
          GlosaJSONMember(key: "n", value: .array([.string(value), .array([.array([])])])),
        ])
      let text = shot.serialize()
      let body = Self.stripBrackets(text)
      // The only `]]` / `[[` allowed is the note's own delimiters (stripped above).
      #expect(!body.contains("]]"), "value \(value)")
      #expect(!body.contains("[["), "value \(value)")
      #expect(!Self.stripBrackets(text).contains("\n\n"))
      var expected = shot
      expected.documentIndex = 0
      #expect(parseShots(text) == [expected], "value \(value)")
    }
    let text = Shot(documentIndex: 0, prompt: "a]]b[[c").serialize()
    #expect(text.contains("\"a]\\u005db[\\u005bc\""))
  }

  @Test("JSON escapes: quotes, backslashes, newlines, controls, unicode")
  func jsonEscapes() {
    let shot = Shot(documentIndex: 0, prompt: "q\" b\\ n\n t\t c\u{01} é 日本 😀")
    let text = shot.serialize()
    #expect(text.contains("\"q\\\" b\\\\ n\\n t\\t c\\u0001 é 日本 😀\""))
    #expect(parseShots(text) == [shot])
  }

  // MARK: - serialize(parse(n)) == n

  @Test("serialize(parse(n)) == n for canonical notes")
  func canonicalRoundTrip() throws {
    let shotNotes = [
      Self.exampleShot,
      """
      [[ {"shot": {
        "prompt": "Wide establishing shot",
        "width": 1024,
        "height": 576,
        "steps": 8,
        "guidance": 4.0,
        "seed": 42
      }} ]]
      """,
      """
      [[ {"shot": {
        "prompt": "Close on the lamp",
        "negative": "blur",
        "lora": "keeper-v1",
        "loraScale": 0.35,
        "character": "KEEPER",
        "preview": true,
        "telemetry": false
      }} ]]
      """,
      """
      [[ {"shot": {
        "style": "charcoal",
        "model": "klein4b"
      }} ]]
      """,
      """
      [[ {"shot": {
        "prompt": "Extras travel",
        "seed": "18446744073709551615",
        "mood": "calm",
        "weights": [1,2.5,{"a":null}],
        "nested": {"k":[true,false]}
      }} ]]
      """,
      "[[ {\"shot\": {}} ]]",
    ]
    for note in shotNotes {
      let shots = parseShots(note)
      #expect(shots.count == 1, "\(note)")
      #expect(shots.first?.serialize() == note)
    }

    let includeNotes = [
      """
      [[ {"include": {
        "src": "audio/surf.m4a",
        "gain": -12.0,
        "mode": "bed"
      }} ]]
      """,
      """
      [[ {"include": {
        "src": "audio/rain.wav",
        "gain": 0.5,
        "mode": "overlay",
        "fadeIn": 2.0,
        "fadeOut": 1.5,
        "prompt": "soft rain",
        "tag": 3
      }} ]]
      """,
    ]
    for note in includeNotes {
      let includes = parseIncludes(note)
      #expect(includes.count == 1, "\(note)")
      #expect(includes.first?.serialize() == note)
    }
  }

  // MARK: - Property tests

  /// SplitMix64 with a fixed seed; no system randomness.
  struct Generator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    mutating func bool() -> Bool { next() & 1 == 1 }

    static let pieces = [
      "plain", " ", "a\"b", "back\\slash", "]]", "[[", "]]]", "[[[", "line\nbreak", "tab\t",
      "é", "日本語", "😀", "\u{01}", "{", "}", "\"", ",", ":", "[", "]", "x y",
    ]

    mutating func string() -> String {
      var s = ""
      for _ in 0..<(1 + int(4)) { s += Self.pieces[int(Self.pieces.count)] }
      return s
    }

    /// Doubles that are exactly representable text-wise through ECMAScript formatting.
    mutating func double() -> Double {
      switch int(6) {
      case 0: return Double(int(1000)) - 500
      case 1: return Double(int(100_000)) / 100
      case 2: return Double(int(1000)) / 8
      case 3: return Double(int(9)) * 1e22
      case 4: return Double(1 + int(9)) * 1e-7
      default: return Double(next() % 1_000_000) / 3
      }
    }

    mutating func json(depth: Int) -> GlosaJSONValue {
      switch int(depth > 0 ? 7 : 5) {
      case 0: return .string(string())
      case 1: return .number(double())
      case 2: return .bool(bool())
      case 3: return .null
      case 4: return .number(Double(int(10_000)))
      case 5:
        return .array((0..<int(4)).map { _ in json(depth: depth - 1) })
      default:
        return .object(
          (0..<int(4)).map {
            GlosaJSONMember(key: "k\($0)" + (bool() ? string() : ""), value: json(depth: depth - 1))
          })
      }
    }

    mutating func seed() -> UInt64 {
      switch int(4) {
      case 0: return UInt64(int(100))
      case 1: return (1 << 53) - 1
      case 2: return (1 << 53) + UInt64(int(1000))
      default: return next()
      }
    }

    mutating func extras() -> [GlosaJSONMember] {
      var used = Set<String>()
      var members: [GlosaJSONMember] = []
      for i in 0..<int(4) {
        let key = "x\(i)" + (bool() ? string() : "")
        guard used.insert(key).inserted else { continue }
        members.append(GlosaJSONMember(key: key, value: json(depth: 3)))
      }
      return members
    }

    mutating func shot() -> Shot {
      var shot = Shot(documentIndex: 0, prompt: bool() ? string() : "")
      if bool() { shot.caption = string() }
      if bool() { shot.style = string() }
      if bool() { shot.model = string() }
      if bool() { shot.aspect = string() }
      if bool() { shot.width = int(8192) }
      if bool() { shot.height = int(8192) }
      if bool() { shot.steps = int(100) }
      if bool() { shot.guidance = double() }
      if bool() { shot.seed = seed() }
      if bool() { shot.negative = string() }
      if bool() { shot.lora = string() }
      if bool() { shot.loraScale = double() }
      if bool() { shot.ref = (0..<int(4)).map { _ in string() } }
      if bool() { shot.character = string() }
      if bool() { shot.output = string() }
      if bool() { shot.preview = bool() }
      if bool() { shot.telemetry = bool() }
      shot.extraAttributes = extras()
      return shot
    }

    mutating func include() -> Include {
      var include = Include(documentIndex: 0, src: string())
      if bool() { include.gain = double() }
      if bool() { include.mode = [.overlay, .bed, .sequential][int(3)] }
      if bool() { include.fadeIn = double() }
      if bool() { include.fadeOut = double() }
      if bool() { include.prompt = string() }
      include.extraAttributes = extras()
      return include
    }
  }

  @Test("Property: parse(serialize(shot)) == shot over 300 generated shots")
  func shotRoundTripProperty() {
    var generator = Generator(state: 0x6C05_A5EE_D001)
    for n in 0..<300 {
      let shot = generator.shot()
      let text = shot.serialize()
      let body = Self.stripBrackets(text)
      #expect(!body.contains("]]") && !body.contains("[["), "case \(n)")
      let parsed = parseShots(text)
      #expect(parsed == [shot], "case \(n): \(text)")
      // Serialization is a fixed point.
      #expect(parsed.first?.serialize() == text, "case \(n)")
    }
  }

  @Test("Property: parse(serialize(include)) == include over 300 generated includes")
  func includeRoundTripProperty() {
    var generator = Generator(state: 0x1AC1_0DE5_0002)
    for n in 0..<300 {
      let include = generator.include()
      let text = include.serialize()
      let body = Self.stripBrackets(text)
      #expect(!body.contains("]]") && !body.contains("[["), "case \(n)")
      let parsed = parseIncludes(text)
      #expect(parsed == [include], "case \(n): \(text)")
      #expect(parsed.first?.serialize() == text, "case \(n)")
    }
  }
}
