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
