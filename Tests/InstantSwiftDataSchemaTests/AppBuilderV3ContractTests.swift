import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct AppBuilderV3ContractTests {
  @Test
  func schemaPreservesThePinnedSourceAndStorageAdaptation() throws {
    let document = InstantSchemaExamples.appBuilderV3Document

    expectNoDifference(
      document.entities.map(\.namespace),
      ["$files", "$users", "builds"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "$files" })
        .attributes.map(\.name),
      ["id", "path", "url"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "$users" })
        .attributes.map(\.name),
      ["id", "email"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "builds" })
        .attributes.map(\.name),
      [
        "id", "instantAppId", "code", "reasoning", "slug", "error",
        "isPreviewable", "title",
      ]
    )
    expectNoDifference(document.links.map(\.name), ["buildFile", "buildOwner"])
    expectNoDifference(document.links.map(\.isRequired), [nil, true])
    expectNoDifference(
      document.links.map { "\($0.forward.label)->\($0.reverse.label)" },
      ["file->builds", "owner->builds"]
    )
  }

  @Test
  func permissionsAndGeneratedTypeScriptRoundTripExactly() throws {
    let permissions = InstantSchemaExamples.appBuilderV3Permissions
    expectNoDifference(permissions.defaults?.allow, [.default: "true"])
    expectNoDifference(
      permissions.namespaces,
      [
        InstantNamespacePermissions(
          namespace: "$users",
          allow: [
            .view: "auth.id == data.id",
            .create: "false",
            .update: "false",
            .delete: "false",
          ]
        )
      ]
    )

    let schemaSource = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.appBuilderV3Document
    )
    let permissionsSource = try TypeScriptPermissionsPrinter().printPermissions(permissions)
    expectNoDifference(
      try TypeScriptSchemaParser().parseDocument(schemaSource),
      ParsedInstantSchemaDocument(InstantSchemaExamples.appBuilderV3Document)
    )
    expectNoDifference(
      try TypeScriptPermissionsParser().parse(permissionsSource),
      permissions
    )
    #expect(schemaSource.contains("buildFile:"))
    #expect(schemaSource.contains("buildOwner:"))
    #expect(permissionsSource.contains("$default"))
    #expect(permissionsSource.contains("auth.id == data.id"))
  }
}
