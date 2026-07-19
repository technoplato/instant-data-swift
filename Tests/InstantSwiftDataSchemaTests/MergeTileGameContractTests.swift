import CustomDump
import InstantSwiftDataSchema
import Testing

// Canonical source:
// upstream/instant/client/www/lib/recipes/merge-tile-game.tsx
@Suite
struct MergeTileGameContractTests {
  @Test
  func schemaPreservesTheCanonicalBoardAndColorPresenceShape() {
    let document = InstantSchemaExamples.mergeTileGameDocument

    expectNoDifference(document.entities.map(\.namespace), ["boards"])
    expectNoDifference(
      document.entities.first?.attributes.map(\.name),
      ["id", "state"]
    )
    expectNoDifference(
      document.entities.first?.attributes.map(\.valueType),
      [.string, .json]
    )
    expectNoDifference(
      document.entities.first?.attributes.map(\.isRequired),
      [true, true]
    )
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["tile-game-example"])
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.name),
      ["color"]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.valueType),
      [.string]
    )
    expectNoDifference(document.rooms.first?.topics, [])
    expectNoDifference(
      InstantSchemaExamples.mergeTileGamePermissions.namespaces,
      [.allowAll(namespace: "boards")]
    )
  }

  @Test
  func generatedTypeScriptUsesRequiredJSONStateAndColorPresence() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.mergeTileGameDocument
    )

    #expect(source.contains("boards: i.entity"))
    #expect(source.contains("state: i.json()"))
    #expect(source.contains("\"tile-game-example\":"))
    #expect(source.contains("color: i.string()"))
    #expect(!source.contains("topics:"))
  }
}
