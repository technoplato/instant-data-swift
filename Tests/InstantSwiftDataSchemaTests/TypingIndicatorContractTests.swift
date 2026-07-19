import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct TypingIndicatorContractTests {
  @Test
  func schemaPreservesTheCanonicalRoomOnlyPresenceShape() {
    let document = InstantSchemaExamples.typingIndicatorDocument

    expectNoDifference(document.entities, [])
    expectNoDifference(document.links, [])
    expectNoDifference(document.rooms.map(\.name), ["typing-indicator-example"])
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.name),
      ["id", "chat-input"]
    )
    expectNoDifference(
      document.rooms.first?.presence.attributes.map(\.isRequired),
      [true, false]
    )
    expectNoDifference(document.rooms.first?.topics, [])
    expectNoDifference(InstantSchemaExamples.typingIndicatorPermissions.namespaces, [])
  }

  @Test
  func generatedTypeScriptQuotesTheHyphenatedPresenceKey() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.typingIndicatorDocument
    )

    #expect(source.contains("\"typing-indicator-example\":"))
    #expect(source.contains("\"chat-input\": i.boolean().optional()"))
    #expect(!source.contains("topics:"))
  }
}
