import Foundation
import Testing

@testable import GlosaCore

@Suite("Shipped JSON Schemas")
struct SchemaResourceTests {

  private func load(_ name: String) throws -> [GlosaJSONMember] {
    let url = try #require(
      GlosaResources.bundle.url(forResource: name, withExtension: "json", subdirectory: "schemas"))
    let text = try String(contentsOf: url, encoding: .utf8)
    guard case .object(let members) = try GlosaJSONReader.parse(text) else {
      Issue.record("\(name) is not a JSON object")
      return []
    }
    return members
  }

  private func string(_ members: [GlosaJSONMember], _ key: String) -> String? {
    if case .string(let s)? = members.first(where: { $0.key == key })?.value { return s }
    return nil
  }

  private func propertyKeys(_ members: [GlosaJSONMember]) -> [String] {
    guard case .object(let props)? = members.first(where: { $0.key == "properties" })?.value
    else { return [] }
    return props.map(\.key)
  }

  @Test("shot schema loads, is 2.0, and lists the canonical keys")
  func shotSchema() throws {
    let members = try load("shot.schema")
    #expect(string(members, "$schema") == "https://json-schema.org/draft/2020-12/schema")
    #expect(try #require(string(members, "$id")).contains("2.0"))
    #expect(propertyKeys(members) == Shot.schemaKeys)
  }

  @Test("include schema loads, is 2.0, and lists the canonical keys")
  func includeSchema() throws {
    let members = try load("include.schema")
    #expect(string(members, "$schema") == "https://json-schema.org/draft/2020-12/schema")
    #expect(try #require(string(members, "$id")).contains("2.0"))
    #expect(propertyKeys(members) == Include.schemaKeys)
  }
}
