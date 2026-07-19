import CustomDump
import InstantSwiftDataSchema
import Testing

// Canonical sources:
// upstream/instant/client/www/lib/recipes/custom-cursors.tsx
// upstream/instant/client/packages/react/src/Cursors.tsx
@Suite
struct CustomCursorsContractTests {
  @Test
  func schemaPreservesNameAndTheRoom124DynamicCursorShape() {
    let document = InstantSchemaExamples.customCursorsDocument

    expectNoDifference(document.entities, [])
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["cursors-example"])
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.name),
      ["name", "cursors-space-default--cursors-example-124"]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.valueType),
      [.string, .json]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.isRequired),
      [true, false]
    )
    expectNoDifference(document.rooms.first?.topics, [])
    expectNoDifference(InstantSchemaExamples.customCursorsPermissions.namespaces, [])
  }

  @Test
  func generatedTypeScriptKeepsNameOutsideTheOptionalCursorJSON() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.customCursorsDocument
    )

    #expect(source.contains("\"cursors-example\":"))
    #expect(source.contains("name: i.string()"))
    #expect(
      source.contains(
        "\"cursors-space-default--cursors-example-124\": i.json().optional()"
      )
    )
    #expect(!source.contains("userID"))
    #expect(!source.contains("topics:"))
  }
}
