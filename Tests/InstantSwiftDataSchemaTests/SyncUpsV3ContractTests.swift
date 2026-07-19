import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct SyncUpsV3ContractTests {
  @Test
  func schemaPreservesThePinnedUpstreamGraph() throws {
    let document = InstantSchemaExamples.syncUpsV3Document

    expectNoDifference(
      document.entities.map(\.namespace),
      ["syncUps", "attendees", "meetings"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "syncUps" })
        .attributes.map(\.name),
      ["id", "seconds", "theme", "title"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "attendees" })
        .attributes.map(\.name),
      ["id", "name"]
    )
    expectNoDifference(
      try #require(document.entities.first { $0.namespace == "meetings" })
        .attributes.map(\.name),
      ["id", "date", "transcript"]
    )
    expectNoDifference(
      document.links,
      [
        InstantLinkSchema(
          name: "syncUpsAttendees",
          forward: InstantLinkEndpoint(
            namespace: "attendees",
            cardinality: .one,
            label: "syncUp",
            onDelete: .cascade
          ),
          reverse: InstantLinkEndpoint(
            namespace: "syncUps",
            cardinality: .many,
            label: "attendees"
          ),
          isRequired: true
        ),
        InstantLinkSchema(
          name: "syncUpsMeetings",
          forward: InstantLinkEndpoint(
            namespace: "meetings",
            cardinality: .one,
            label: "syncUp",
            onDelete: .cascade
          ),
          reverse: InstantLinkEndpoint(
            namespace: "syncUps",
            cardinality: .many,
            label: "meetings"
          ),
          isRequired: true
        ),
      ]
    )
    expectNoDifference(
      InstantSchemaExamples.syncUpsV3Permissions.namespaces,
      [
        .allowAll(namespace: "syncUps"),
        .allowAll(namespace: "attendees"),
        .allowAll(namespace: "meetings"),
      ]
    )
  }

  @Test
  func generatedTypeScriptRoundTripsTheSwiftOwnedContract() throws {
    let schemaSource = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.syncUpsV3Document
    )
    let permissionsSource = try TypeScriptPermissionsPrinter().printPermissions(
      InstantSchemaExamples.syncUpsV3Permissions
    )

    expectNoDifference(
      try TypeScriptSchemaParser().parseDocument(schemaSource),
      ParsedInstantSchemaDocument(InstantSchemaExamples.syncUpsV3Document)
    )
    var expectedPermissions = InstantSchemaExamples.syncUpsV3Permissions
    expectedPermissions.namespaces.sort { $0.namespace < $1.namespace }
    expectNoDifference(
      try TypeScriptPermissionsParser().parse(permissionsSource),
      expectedPermissions
    )
    #expect(schemaSource.contains("seconds: i.number().indexed()"))
    #expect(schemaSource.contains("date: i.date().indexed()"))
    #expect(schemaSource.contains("syncUpsAttendees"))
    #expect(schemaSource.contains("syncUpsMeetings"))
  }
}
