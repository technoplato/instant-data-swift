import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct ReactionsContractTests {
  @Test
  func schemaPreservesTheCanonicalRoomOnlyTopicShape() {
    let document = InstantSchemaExamples.reactionsDocument

    expectNoDifference(document.entities, [])
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["topics-example"])
    expectNoDifference(document.rooms.first?.presence.attributes, [])
    expectNoDifference(document.rooms.first?.topics.map(\.name), ["emoji"])
    expectNoDifference(
      document.rooms.first?.topics.first?.payload.attributes.map(\.name),
      ["name", "directionAngle", "rotationAngle"]
    )
    expectNoDifference(
      document.rooms.first?.topics.first?.payload.attributes.map(\.valueType),
      [.string, .number, .number]
    )
    expectNoDifference(
      document.rooms.first?.topics.first?.payload.attributes.map(\.isRequired),
      [true, true, true]
    )
    expectNoDifference(InstantSchemaExamples.reactionsPermissions.namespaces, [])
  }

  @Test
  func generatedTypeScriptUsesTheExactTopicAndPayloadKeys() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.reactionsDocument
    )

    #expect(source.contains("\"topics-example\":"))
    #expect(source.contains("emoji: i.entity({"))
    #expect(source.contains("name: i.string()"))
    #expect(source.contains("directionAngle: i.number()"))
    #expect(source.contains("rotationAngle: i.number()"))
    #expect(source.contains("presence: i.entity({})"))
  }
}
