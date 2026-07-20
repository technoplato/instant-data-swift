import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct StorageContractTests {
  @Test
  func schemaAndPermissionsExposeCanonicalFilesNamespace() throws {
    let document = InstantSchemaExamples.storageDocument
    expectNoDifference(document.entities.map(\.namespace), ["$files"])
    expectNoDifference(document.entities[0].attributes.map(\.name), ["id", "path", "url"])
    expectNoDifference(document.links, [])

    let permissions = InstantSchemaExamples.storagePermissions
    expectNoDifference(
      permissions.namespaces,
      [.allowAll(namespace: "$files")]
    )

    let schemaSource = try TypeScriptSchemaPrinter().printSchema(document)
    let permissionsSource = try TypeScriptPermissionsPrinter().printPermissions(permissions)
    expectNoDifference(
      try TypeScriptSchemaParser().parseDocument(schemaSource),
      ParsedInstantSchemaDocument(document)
    )
    expectNoDifference(
      try TypeScriptPermissionsParser().parse(permissionsSource),
      permissions
    )
  }
}
