import Foundation
import Testing

@testable import GlosaCore

/// Tests for `Shot.id`: the schema form, the canonical note, the `Codable` form,
/// the 1.0 and FDX parsing paths, and non-inheritance through the fold.
@Suite("Shot id")
struct ShotIDTests {

  let parser = GlosaParser()

  static let canonicalNote = """
    [[ {"shot": {
      "id": "panel-01",
      "prompt": "A lighthouse keeper climbs the spiral stair at dusk",
      "style": "ink wash"
    }} ]]
    """

  private func parseShot(_ note: String) throws -> Shot {
    let notes = [SerializeTests.stripBrackets(note)]
    return try #require(parser.parseFountainWithDiagnostics(notes: notes).score.shots.first)
  }

  private func parseTag(_ tag: String) throws -> Shot {
    try #require(parser.parseFountainWithDiagnostics(notes: [tag]).score.shots.first)
  }

  // MARK: - Non-inheritance

  @Test("A panel with no id has a nil effective id under a defaults shot with an id")
  func panelDoesNotInheritID() {
    let defaults = Shot(documentIndex: 0, id: "defaults-01", prompt: "", style: "ink")
    let panel = Shot(documentIndex: 1, prompt: "p")

    let effective = panel.effective(given: [defaults])
    #expect(effective.id == nil)
    #expect(effective.style == "ink")
  }

  @Test("A shot keeps its own id under defaults shots with ids")
  func shotKeepsOwnID() {
    let defaults = Shot(documentIndex: 0, id: "defaults-01", prompt: "")
    let panel = Shot(documentIndex: 1, id: "panel-01", prompt: "p")
    let laterDefaults = Shot(documentIndex: 2, id: "defaults-02", prompt: "")

    #expect(panel.effective(given: [defaults]).id == "panel-01")
    #expect(laterDefaults.effective(given: [defaults]).id == "defaults-02")
  }

  @Test("effectiveShots does not pass a parsed defaults shot's id to later panels")
  func effectiveShotsDoNotInheritID() {
    let score = parser.parseFountain(notes: [
      #"{"shot": {"id": "defaults-01", "style": "ink"}}"#,
      #"{"shot": {"prompt": "first"}}"#,
      #"{"shot": {"id": "panel-02", "prompt": "second"}}"#,
    ])

    let panels = score.effectiveShots
    #expect(panels.map(\.id) == [nil, "panel-02"])
    #expect(panels.map(\.style) == ["ink", "ink"])
  }

  // MARK: - Canonical note

  @Test("serialize(parse(n)) == n for a canonical note with id")
  func canonicalNoteRoundTrips() throws {
    let shot = try parseShot(Self.canonicalNote)
    #expect(shot.id == "panel-01")
    #expect(shot.extraAttributes.isEmpty)
    #expect(shot.serialize() == Self.canonicalNote)
  }

  @Test("parse(serialize(x)) == x, including a defaults shot with an id")
  func shotRoundTrips() throws {
    let panel = Shot(documentIndex: 0, id: "panel-01", prompt: "p")
    #expect(try parseShot(panel.serialize()) == panel)

    let defaults = Shot(documentIndex: 0, id: "defaults-01", prompt: "")
    #expect(try parseShot(defaults.serialize()) == defaults)
  }

  @Test("A shot with no id writes no id key")
  func noIDWritesNoKey() {
    #expect(!Shot(documentIndex: 0, prompt: "p").serialize().contains("\"id\""))
  }

  // MARK: - Schema and Codable forms

  @Test("id is a known key in the schema form, not an extra attribute")
  func schemaForm() throws {
    let shot = try Shot(schemaJSONData: Data(#"{"prompt": "p", "id": "panel-01"}"#.utf8))
    #expect(shot.id == "panel-01")
    #expect(shot.extraAttributes.isEmpty)
    #expect(String(decoding: shot.schemaJSONData(), as: UTF8.self)
      == #"{"id":"panel-01","prompt":"p"}"#)
  }

  @Test("A non-string id is rejected and names the key")
  func nonStringIDIsRejected() {
    do throws(GlosaSchemaError) {
      _ = try Shot(schemaJSONData: Data(#"{"id": 7}"#.utf8))
      Issue.record("Expected a wrongType error")
    } catch {
      #expect(error.kind == .wrongType(key: "id"))
    }
  }

  @Test("The Codable form round-trips id, and JSON without it decodes to nil")
  func codableForm() throws {
    let shot = Shot(documentIndex: 3, id: "panel-01", prompt: "p")
    let data = try JSONEncoder().encode(shot)
    #expect(try JSONDecoder().decode(Shot.self, from: data) == shot)

    let legacy = Data(#"{"documentIndex":3,"prompt":"p"}"#.utf8)
    #expect(try JSONDecoder().decode(Shot.self, from: legacy).id == nil)
  }

  // MARK: - Notation 1.0 tags

  @Test("A 1.0 tag carries id in either quote style")
  func tagID() throws {
    #expect(try parseTag(#"<shot id="panel-01" prompt="p"/>"#).id == "panel-01")
    #expect(try parseTag(#"<shot prompt="p" id='panel-02'/>"#).id == "panel-02")
    #expect(try parseTag(#"<shot prompt="p"/>"#).id == nil)
  }

  @Test("A 1.0 tag does not read id from a longer attribute name")
  func tagIDIgnoresLongerNames() throws {
    #expect(try parseTag(#"<shot prompt="p" grid="3" panel-id='9'/>"#).id == nil)
  }

  @Test("A 1.0 tag does not read id from inside a quoted value")
  func tagIDIgnoresQuotedValues() throws {
    #expect(try parseTag(#"<shot prompt="she said='run' and id='7'"/>"#).id == nil)
    #expect(try parseTag(#"<shot prompt='a sign reads id="7"' id="panel-01"/>"#).id == "panel-01")
  }

  @Test("Migrating a 1.0 tag keeps its id")
  func migrationKeepsID() {
    let result = GlosaMigration.migrateBlockDirectives(
      in: #"[[ <shot id="panel-01" prompt="p"/> ]]"#)
    #expect(result.migrated == 1)
    #expect(result.text == Shot(documentIndex: 0, id: "panel-01", prompt: "p").serialize())
  }

  // MARK: - FDX

  @Test("<glosa:shot id=…/> parses the id")
  func fdxID() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <FinalDraft DocumentType="Script" Template="No" Version="4"
                  xmlns:glosa="https://intrusive-memory.productions/glosa">
        <Content>
          <glosa:shot id="panel-01" prompt="first"/>
          <glosa:shot grid="3" prompt="second"/>
        </Content>
      </FinalDraft>
      """
    let shots = parser.parseFDXWithDiagnostics(data: Data(xml.utf8)).score.shots
    #expect(shots.map(\.id) == ["panel-01", nil])
  }
}
