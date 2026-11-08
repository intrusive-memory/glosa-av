import Foundation
import Testing

@testable import GlosaCore

/// Tests for `GlosaFountainNotes.standaloneNotes(in:)` and
/// `GlosaMigration.migrateBlockDirectives(in:)`.
@Suite("Standalone notes and migration")
struct MigrationTests {

  // MARK: - Synthetic mixed document

  static let defaultsShotTag = #"<shot style="ink wash, muted palette" aspect="wide"/>"#
  static let fullShotTag =
    #"<shot prompt="A lamp on a table" caption="Evening" model="klein4b" "#
    + #"ref="ALICE,lamp.png" seed="42" guidance="7.5" steps="20"/>"#
  static let includeTag = #"<include src="audio/rain.wav" gain="-12" mode="loop" fadeIn="1.5"/>"#
  static let inlineShotLine = #"The room is quiet. [[<shot prompt="inline"/>]] Rain falls."#

  /// Segments of the document: `.keep` text is copied verbatim; `.migrate`
  /// text is the 1.0 note that must be replaced by its 2.0 form.
  enum Segment {
    case keep(String)
    case migrate(String)
  }

  static let segments: [Segment] = [
    .keep("INT. LIGHTHOUSE - NIGHT\n\n"),
    .keep("The keeper climbs the stair.\n\n"),
    .keep("[[<SceneContext location=\"lighthouse\" time=\"night\">Quiet.</SceneContext>]]\n\n"),
    .keep("[[<Intent from=\"calm\" to=\"uneasy\" pace=\"slow\">]]\n\n"),
    .keep(
      "KEEPER\n(softly)\nWho is there? [[<breath/>]] Hello. "
        + "[[<pause duration=\"1.0\"/>]] Anyone?\n\n"),
    .keep("[[</Intent>]]\n\n"),
    .migrate("[[ \(defaultsShotTag) ]]"),
    .keep("\n\n"),
    .migrate("[[\(fullShotTag)]]"),
    .keep("\n\n"),
    .migrate("[[ \(includeTag) ]]"),
    .keep("\n\n"),
    .keep("\(inlineShotLine)\n\n"),
    .keep("The end.\n"),
  ]

  static func notes(_ segment: Segment) -> (original: String, expected: String) {
    switch segment {
    case .keep(let text): return (text, text)
    case .migrate(let note):
      let inner = String(note.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
      let score = GlosaParser().parseFountain(notes: [inner])
      let replacement = score.shots.first?.serialize() ?? score.includes.first!.serialize()
      return (note, replacement)
    }
  }

  static var original: String { segments.map { notes($0).original }.joined() }
  static var expected: String { segments.map { notes($0).expected }.joined() }

  // MARK: - Migration

  @Test("Only standalone block directives change; every other byte is identical")
  func onlyBlockDirectivesMigrate() {
    let result = GlosaMigration.migrateBlockDirectives(in: Self.original)
    #expect(result.text == Self.expected)
    #expect(result.migrated == 3)
    #expect(result.skipped == 1)
    // The bytes between replaced notes are unchanged.
    let kept = Self.segments.compactMap { segment -> String? in
      if case .keep(let text) = segment { return text }
      return nil
    }
    var remainder = result.text
    for note in GlosaFountainNotes.standaloneNotes(in: result.text).reversed()
    where note.text.hasPrefix("{") {
      remainder.removeSubrange(note.range)
    }
    #expect(remainder == kept.joined())
  }

  @Test("Performance directive notes are byte-identical after migration")
  func performanceDirectivesUntouched() {
    let result = GlosaMigration.migrateBlockDirectives(in: Self.original)
    for fragment in [
      "[[<SceneContext location=\"lighthouse\" time=\"night\">Quiet.</SceneContext>]]",
      "[[<Intent from=\"calm\" to=\"uneasy\" pace=\"slow\">]]",
      "[[</Intent>]]",
      "Who is there? [[<breath/>]] Hello. [[<pause duration=\"1.0\"/>]] Anyone?",
      Self.inlineShotLine,
    ] {
      #expect(result.text.contains(fragment))
    }
  }

  @Test("A second run migrates nothing and returns identical text")
  func idempotent() {
    let first = GlosaMigration.migrateBlockDirectives(in: Self.original)
    let second = GlosaMigration.migrateBlockDirectives(in: first.text)
    #expect(second.migrated == 0)
    #expect(second.text == first.text)
    #expect(second.skipped == 1)
  }

  @Test("Acceptance 4: a migrated 1.0 document re-parses to equal values")
  func acceptance4MigratedDocumentReparsesEqual() {
    let oldNotes = [Self.defaultsShotTag, Self.fullShotTag, Self.includeTag]
    let oldScore = GlosaParser().parseFountain(notes: oldNotes)

    let migrated = GlosaMigration.migrateBlockDirectives(in: Self.original).text
    let newNotes = GlosaFountainNotes.standaloneNotes(in: migrated)
      .map(\.text).filter { $0.hasPrefix("{") }
    #expect(newNotes.count == 3)
    let newScore = GlosaParser().parseFountain(notes: newNotes)

    func normalized(_ shots: [Shot]) -> [Shot] {
      shots.map { original in
        var shot = original
        shot.documentIndex = 0
        return shot
      }
    }
    func normalized(_ includes: [Include]) -> [Include] {
      includes.map { original in
        var include = original
        include.documentIndex = 0
        return include
      }
    }
    #expect(oldScore.shots.count == 2)
    #expect(normalized(newScore.shots) == normalized(oldScore.shots))
    #expect(normalized(newScore.includes) == normalized(oldScore.includes))
    #expect(newScore.includes.count == 1)
  }

  @Test("A standalone note mixing a tag with other content is skipped, not migrated")
  func mixedStandaloneNoteSkipped() {
    let text = "Action.\n\n[[ <shot prompt=\"a\"/> and a remark ]]\n\nMore.\n"
    let result = GlosaMigration.migrateBlockDirectives(in: text)
    #expect(result.text == text)
    #expect(result.migrated == 0)
    #expect(result.skipped == 1)
  }

  @Test("A 2.0 note that mentions <shot in a string is neither changed nor counted")
  func jsonNoteMentioningTag() {
    let text = "[[ {\"shot\": {\"prompt\": \"a <shot b\"}} ]]\n"
    let result = GlosaMigration.migrateBlockDirectives(in: text)
    #expect(result.text == text)
    #expect(result.migrated == 0)
    #expect(result.skipped == 0)
  }

  @Test("CRLF line endings outside the replaced note are preserved")
  func crlfPreserved() {
    let text = "Action.\r\n\r\n[[ \(Self.defaultsShotTag) ]]\r\n\r\nMore.\r\n"
    let result = GlosaMigration.migrateBlockDirectives(in: text)
    #expect(result.migrated == 1)
    #expect(result.text.hasPrefix("Action.\r\n\r\n[[ {\"shot\""))
    #expect(result.text.hasSuffix("}} ]]\r\n\r\nMore.\r\n"))
    #expect(!result.text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
  }

  // MARK: - Unknown attributes

  /// The shot that `tag` migrates to, read back from the migrated note.
  private func migratedShot(_ tag: String) throws -> Shot {
    let result = GlosaMigration.migrateBlockDirectives(in: "[[ \(tag) ]]\n")
    #expect(result.migrated == 1)
    #expect(result.skipped == 0)
    let note = try #require(GlosaFountainNotes.standaloneNotes(in: result.text).first)
    #expect(note.text.hasPrefix("{"))
    return try #require(GlosaParser().parseFountain(notes: [note.text]).shots.first)
  }

  private func strings(_ pairs: KeyValuePairs<String, String>) -> [GlosaJSONMember] {
    pairs.map { GlosaJSONMember(key: $0.key, value: .string($0.value)) }
  }

  @Test("Every prototype attribute survives migration with its value, in the order written")
  func prototypeAttributesSurvive() throws {
    let tag =
      #"<shot id="01-purse" reference="portraits/mimi.png" location="APARTMENT" "#
      + #"view="foyer" prompt="Gloved hands" plate="plates/foyer.png" order="MIMI,RAY" "#
      + #"enters="RAY" exits="MIMI" move="MIMI to door" discovered="MIMI" "#
      + #"reorder="RAY before MIMI" refs="room,file:a.png"/>"#
    let shot = try migratedShot(tag)

    #expect(shot.id == "01-purse")
    #expect(shot.prompt == "Gloved hands")
    #expect(
      shot.extraAttributes
        == strings([
          "reference": "portraits/mimi.png",
          "location": "APARTMENT",
          "view": "foyer",
          "plate": "plates/foyer.png",
          "order": "MIMI,RAY",
          "enters": "RAY",
          "exits": "MIMI",
          "move": "MIMI to door",
          "discovered": "MIMI",
          "reorder": "RAY before MIMI",
          "refs": "room,file:a.png",
        ]))
    #expect(shot.ref == nil)
  }

  @Test("refs, reference and pref stay distinct from ref")
  func refStaysDistinct() throws {
    let tag =
      #"<shot prompt="p" pref="wrong" refs="room" reference="sheet.png" ref="ALICE, lamp.png"/>"#
    let shot = try migratedShot(tag)
    #expect(shot.ref == ["ALICE", "lamp.png"])
    #expect(
      shot.extraAttributes
        == strings(["pref": "wrong", "refs": "room", "reference": "sheet.png"]))

    let withoutRef = try migratedShot(#"<shot prompt="p" pref="a" refs="b" reference="c"/>"#)
    #expect(withoutRef.ref == nil)
    #expect(withoutRef.extraAttributes.map(\.key) == ["pref", "refs", "reference"])
  }

  @Test("ref is not read from inside a quoted value")
  func refIgnoresQuotedValues() throws {
    let shot = try migratedShot(#"<shot prompt="a sign reads ref='x'" view="ref='y'"/>"#)
    #expect(shot.ref == nil)
    #expect(shot.prompt == "a sign reads ref='x'")
    #expect(shot.extraAttributes == strings(["view": "ref='y'"]))
  }

  @Test("Values containing ', {ref:room} and > survive migration")
  func awkwardValuesSurvive() throws {
    let tag =
      #"<shot prompt="the keeper's lamp > the door" location="keeper's room" "#
      + #"view='a "wide" view' plate="{ref:room}" refs="room,{ref:room}" "#
      + #"move="hall > stair" reference='a > b'/>"#
    let shot = try migratedShot(tag)
    #expect(shot.prompt == "the keeper's lamp > the door")
    #expect(
      shot.extraAttributes
        == strings([
          "location": "keeper's room",
          "view": #"a "wide" view"#,
          "plate": "{ref:room}",
          "refs": "room,{ref:room}",
          "move": "hall > stair",
          "reference": "a > b",
        ]))
  }

  @Test("A migrated tag re-parses equal, and a second run changes nothing")
  func unknownAttributesRoundTrip() throws {
    let tag = #"<shot view="foyer" prompt="p" plate="{ref:room}" move="a > b"/>"#
    let parsed = try #require(GlosaParser().parseFountain(notes: [tag]).shots.first)
    #expect(try migratedShot(tag) == parsed)

    let first = GlosaMigration.migrateBlockDirectives(in: "[[ \(tag) ]]\n")
    let second = GlosaMigration.migrateBlockDirectives(in: first.text)
    #expect(second.migrated == 0)
    #expect(second.text == first.text)
  }

  @Test("A repeated unknown attribute keeps its first value and still migrates to a readable note")
  func repeatedAttributeKeepsFirst() throws {
    let shot = try migratedShot(#"<shot prompt="p" view="first" plate="x" view="second"/>"#)
    #expect(shot.extraAttributes == strings(["view": "first", "plate": "x"]))
  }

  @Test("Typed keys stay typed, and a malformed value stays lenient and is not kept")
  func typedKeysStayTyped() throws {
    let shot = try migratedShot(
      #"<shot prompt="p" steps="many" seed="7" preview="maybe" width="12px" view="foyer"/>"#)
    #expect(shot.steps == nil)
    #expect(shot.seed == 7)
    #expect(shot.preview == nil)
    #expect(shot.width == nil)
    #expect(shot.extraAttributes == strings(["view": "foyer"]))
  }

  @Test("Spaces around = do not lose an unknown attribute")
  func spacedEqualsIsKept() throws {
    let shot = try migratedShot(#"<shot prompt="p" view = "foyer" plate= 'x'/>"#)
    #expect(shot.extraAttributes == strings(["view": "foyer", "plate": "x"]))
  }

  @Test("Text outside the tag is not read as an attribute")
  func textOutsideTagIgnored() throws {
    let shot = try #require(
      GlosaParser().parseFountain(notes: [#"before="1" <shot view="foyer"/> after="2""#])
        .shots.first)
    #expect(shot.extraAttributes == strings(["view": "foyer"]))
  }

  @Test("<glosa:shot/> keeps unknown attributes in the order written")
  func fdxKeepsUnknownAttributes() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <!-- <glosa:shot alpha="" prompt="" mid="" ref="" zeta="" pref="" refs="" steps=""/> -->
          <glosa:shot zeta="1" prompt="p" alpha="a &gt; b" mid="{ref:room}" ref="ALICE"
                      pref="wrong" refs="room" steps="many"/>
          <glosa:shot prompt="q" alpha="2" zeta="3"/>
          <glosa:shot prompt="r" zeta="4" alpha="5"/>
          <glosa:shot prompt="s"/>
        </Content>
      </FinalDraft>
      """
    let shots = GlosaParser().parseFDXWithDiagnostics(data: Data(xml.utf8)).score.shots
    #expect(shots.count == 4)
    #expect(shots[0].ref == ["ALICE"])
    #expect(shots[0].steps == nil)
    #expect(
      shots[0].extraAttributes
        == strings([
          "zeta": "1", "alpha": "a > b", "mid": "{ref:room}", "pref": "wrong", "refs": "room",
        ]))
    #expect(shots[1].extraAttributes == strings(["alpha": "2", "zeta": "3"]))
    #expect(shots[2].extraAttributes == strings(["zeta": "4", "alpha": "5"]))
    #expect(shots[3].extraAttributes.isEmpty)
  }

  // MARK: - standaloneNotes boundaries

  @Test("A note at the start and end of the document is standalone")
  func documentBoundaries() {
    let text = "[[ one ]]\n\nAction.\n\n[[ two ]]"
    let notes = GlosaFountainNotes.standaloneNotes(in: text)
    #expect(notes.map(\.text) == ["one", "two"])
    #expect(text[notes[0].range] == "[[ one ]]")
    #expect(text[notes[1].range] == "[[ two ]]")
  }

  @Test("A multi-line note is one standalone note")
  func multiLine() {
    let text = "Action.\n\n[[ {\"shot\": {\n  \"prompt\": \"x\"\n}} ]]\n\nMore.\n"
    let notes = GlosaFountainNotes.standaloneNotes(in: text)
    #expect(notes.count == 1)
    #expect(notes[0].text == "{\"shot\": {\n  \"prompt\": \"x\"\n}}")
  }

  @Test("A note containing a blank line is not standalone")
  func blankLineExcluded() {
    let text = "[[ first\n\nsecond ]]\n"
    #expect(GlosaFountainNotes.standaloneNotes(in: text).isEmpty)
  }

  @Test("Inline notes in action and dialogue lines are excluded")
  func inlineExcluded() {
    let text = "He says [[ aside ]] loudly.\n\nKEEPER\nHello [[<breath/>]] there.\n\n[[ real ]]\n"
    let notes = GlosaFountainNotes.standaloneNotes(in: text)
    #expect(notes.map(\.text) == ["real"])
  }

  @Test("A note directly after a text line (no blank line) is not standalone")
  func noBlankBefore() {
    #expect(GlosaFountainNotes.standaloneNotes(in: "Action.\n[[ note ]]\n").isEmpty)
    #expect(GlosaFountainNotes.standaloneNotes(in: "[[ note ]]\nAction.\n").isEmpty)
  }

  @Test("Two notes in one block are not standalone")
  func twoNotesOneBlock() {
    #expect(GlosaFountainNotes.standaloneNotes(in: "[[ a ]] and [[ b ]]\n").isEmpty)
  }

  @Test("CRLF documents are handled")
  func crlf() {
    let text = "Action.\r\n\r\n[[ a\r\nb ]]\r\n\r\nMore.\r\n"
    let notes = GlosaFountainNotes.standaloneNotes(in: text)
    #expect(notes.count == 1)
    #expect(text[notes[0].range] == "[[ a\r\nb ]]")
    #expect(notes[0].text == "a\r\nb")
  }
}
