import CustomDump
import InstantSwiftDataSchema
import Testing

// Canonical sources:
// upstream/instant/client/www/lib/recipes/cursors.tsx
// upstream/instant/client/packages/react/src/Cursors.tsx
@Suite
struct CursorsContractTests {
  @Test
  func schemaPreservesTheCanonicalDynamicCursorPresenceShape() {
    let document = InstantSchemaExamples.cursorsDocument

    expectNoDifference(document.entities, [])
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["cursors-example"])
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.name),
      ["cursors-space-default--cursors-example-123"]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.valueType),
      [.json]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.isRequired),
      [false]
    )
    expectNoDifference(document.rooms.first?.topics, [])
    expectNoDifference(InstantSchemaExamples.cursorsPermissions.namespaces, [])
  }

  @Test
  func generatedTypeScriptUsesOneOptionalJSONCursorSpace() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.cursorsDocument
    )

    #expect(source.contains("\"cursors-example\":"))
    #expect(
      source.contains(
        "\"cursors-space-default--cursors-example-123\": i.json().optional()"
      )
    )
    #expect(!source.contains("userID"))
    #expect(!source.contains("topics:"))
  }
}
