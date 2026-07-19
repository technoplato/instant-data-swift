import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct AvatarStackContractTests {
  @Test
  func schemaPreservesTheCanonicalNameOnlyPresenceShape() {
    let document = InstantSchemaExamples.avatarStackDocument

    expectNoDifference(document.entities, [])
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["avatars-example"])
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.name),
      ["name"]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.valueType),
      [.string]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.isRequired),
      [true]
    )
    expectNoDifference(document.rooms.first?.topics, [])
    expectNoDifference(InstantSchemaExamples.avatarStackPermissions.namespaces, [])
  }

  @Test
  func generatedTypeScriptDoesNotWidenPeerMetadataIntoPresence() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.avatarStackDocument
    )

    #expect(source.contains("\"avatars-example\":"))
    #expect(source.contains("name: i.string()"))
    #expect(!source.contains("userID"))
    #expect(!source.contains("topics:"))
  }
}
