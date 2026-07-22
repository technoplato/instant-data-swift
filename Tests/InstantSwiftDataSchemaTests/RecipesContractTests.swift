import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct RecipesContractTests {
  @Test
  func aggregateDocumentContainsEveryDurableEntityAndUniqueRoom() throws {
    let document = InstantSchemaExamples.recipesDocument

    expectNoDifference(document.entities.map(\.namespace), ["todos", "boards"])
    expectNoDifference(
      document.rooms.map(\.name),
      [
        "todos",
        "cursors-example",
        "topics-example",
        "typing-indicator-example",
        "avatars-example",
        "tile-game-example",
      ]
    )
    expectNoDifference(
      try #require(document.rooms.first { $0.name == "cursors-example" })
        .presence.attributes.map(\.name),
      [
        "name",
        "cursors-space-default--cursors-example-123",
        "cursors-space-default--cursors-example-124",
      ]
    )
    expectNoDifference(
      InstantSchemaExamples.recipesPermissions.namespaces,
      [
        .allowAll(namespace: "todos"),
        .allowAll(namespace: "boards"),
      ]
    )
  }

  @Test
  func aggregateTypeScriptIncludesEveryRoomContract() throws {
    let source = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.recipesDocument
    )

    for name in [
      "todos",
      "boards",
      "cursors-example",
      "topics-example",
      "typing-indicator-example",
      "avatars-example",
      "tile-game-example",
    ] {
      #expect(source.contains(name))
    }
  }
}
