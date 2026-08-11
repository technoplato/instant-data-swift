import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct RecipesContractTests {
  @Test
  func aggregateDocumentContainsEveryDurableEntityAndUniqueRoom() throws {
    let document = InstantSchemaExamples.recipesDocument

    expectNoDifference(
      document.entities.map(\.namespace),
      [
        "todos",
        "boards",
        "linked_infinite_recordings",
        "linked_infinite_transcriptions",
        "linked_infinite_words",
        "recipe_public_counters",
        "recipe_account_counters",
        "recipe_private_notes",
      ]
    )
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
        .allowAll(namespace: "linked_infinite_recordings"),
        .allowAll(namespace: "linked_infinite_transcriptions"),
        .allowAll(namespace: "linked_infinite_words"),
        .allowAll(namespace: "recipe_public_counters"),
        InstantNamespacePermissions(
          namespace: "recipe_account_counters",
          allow: [
            .view: "auth.id == data.ownerUserID",
            .create: "auth.id == data.ownerUserID",
            .update: "auth.id == data.ownerUserID",
            .delete: "auth.id == data.ownerUserID",
          ]
        ),
        InstantNamespacePermissions(
          namespace: "recipe_private_notes",
          allow: [
            .view: "auth.id == data.ownerUserID",
            .create: "auth.id == data.ownerUserID",
            .update: "auth.id == data.ownerUserID",
            .delete: "auth.id == data.ownerUserID",
          ]
        ),
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
