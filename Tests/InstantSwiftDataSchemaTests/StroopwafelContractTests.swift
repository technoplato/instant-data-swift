import CustomDump
import InstantSwiftDataSchema
import Testing

// Canonical source:
// jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614
// - instant.schema.ts
// - instant.perms.ts
@Suite
struct StroopwafelContractTests {
  @Test
  func schemaPreservesCanonicalEntitiesAndAttributes() throws {
    let document = InstantSchemaExamples.stroopwafelDocument

    expectNoDifference(
      document.entities.map(\.namespace),
      ["$users", "rooms", "games", "points"]
    )

    let users = try #require(document.entities.first { $0.namespace == "$users" })
    expectNoDifference(
      users.attributes.map(\.name),
      ["id", "email", "handle", "highScore", "created_at"]
    )
    expectNoDifference(
      users.attributes.map(\.valueType),
      [.string, .any, .string, .number, .string]
    )
    expectNoDifference(
      users.attributes.map(\.isRequired),
      [true, false, false, false, false]
    )
    expectNoDifference(
      users.attributes.map(\.isIndexed),
      [true, true, false, false, false]
    )
    expectNoDifference(
      users.attributes.map(\.isUnique),
      [true, true, false, false, false]
    )

    let rooms = try #require(document.entities.first { $0.namespace == "rooms" })
    expectNoDifference(
      rooms.attributes.map(\.name),
      ["id", "code", "hostId", "readyIds", "kickedIds", "currentGameId", "created_at", "deleted_at"]
    )
    expectNoDifference(
      rooms.attributes.map(\.valueType),
      [.string, .string, .string, .json, .json, .string, .string, .string]
    )
    expectNoDifference(
      rooms.attributes.map(\.isRequired),
      [true, false, true, true, true, false, true, false]
    )
    expectNoDifference(
      rooms.attributes.map(\.isIndexed),
      [true, true, false, false, false, false, false, false]
    )

    let games = try #require(document.entities.first { $0.namespace == "games" })
    expectNoDifference(
      games.attributes.map(\.name),
      ["id", "status", "playerIds", "colors", "created_at"]
    )
    expectNoDifference(
      games.attributes.map(\.valueType),
      [.string, .string, .json, .json, .string]
    )
    expectNoDifference(games.attributes.map(\.isRequired), [true, true, true, true, true])

    let points = try #require(document.entities.first { $0.namespace == "points" })
    expectNoDifference(points.attributes.map(\.name), ["id", "val", "userId"])
    expectNoDifference(points.attributes.map(\.valueType), [.string, .number, .string])
    expectNoDifference(points.attributes.map(\.isRequired), [true, true, true])
  }

  @Test
  func schemaPreservesCanonicalLinksAndEmptyRoomsContract() {
    let document = InstantSchemaExamples.stroopwafelDocument

    expectNoDifference(
      document.links,
      [
        InstantLinkSchema(
          name: "roomUsers",
          forward: InstantLinkEndpoint(namespace: "rooms", cardinality: .many, label: "users"),
          reverse: InstantLinkEndpoint(namespace: "$users", cardinality: .many, label: "rooms")
        ),
        InstantLinkSchema(
          name: "gameUsers",
          forward: InstantLinkEndpoint(namespace: "games", cardinality: .many, label: "users"),
          reverse: InstantLinkEndpoint(namespace: "$users", cardinality: .many, label: "games")
        ),
        InstantLinkSchema(
          name: "gameRooms",
          forward: InstantLinkEndpoint(namespace: "games", cardinality: .many, label: "rooms"),
          reverse: InstantLinkEndpoint(namespace: "rooms", cardinality: .many, label: "games")
        ),
        InstantLinkSchema(
          name: "gamePoints",
          forward: InstantLinkEndpoint(namespace: "games", cardinality: .many, label: "points"),
          reverse: InstantLinkEndpoint(namespace: "points", cardinality: .one, label: "game")
        ),
      ]
    )
    expectNoDifference(document.rooms, [])
  }

  @Test
  func permissionsPreserveCanonicalRulesAndBindings() {
    expectNoDifference(
      InstantSchemaExamples.stroopwafelPermissions,
      InstantPermissionsDocument(
        attrs: InstantAttributePermissions(allow: [.create: "false"]),
        namespaces: [
          InstantNamespacePermissions(
            namespace: "$users",
            allow: [
              .view: "true",
              .create: "false",
              .update: "auth.id == data.id",
              .delete: "false",
            ],
            fields: ["email": "auth.id == data.id"]
          ),
          InstantNamespacePermissions(
            namespace: "rooms",
            allow: [
              .view: "true",
              .create: "auth.id != null",
              .update: "isHost || onlyMemberFields",
              .delete: "false",
            ],
            bind: [
              InstantPermissionBinding("isHost", "auth.id == data.hostId"),
              InstantPermissionBinding(
                "onlyMemberFields",
                "request.modifiedFields.all(field, field in ['readyIds', 'currentGameId', 'users'])"
              ),
            ]
          ),
          InstantNamespacePermissions(
            namespace: "games",
            allow: [
              .view: "true",
              .create: "auth.id != null",
              .update: "onlyMutableFields",
              .delete: "false",
            ],
            bind: [
              InstantPermissionBinding(
                "onlyMutableFields",
                "request.modifiedFields.all(field, field in ['status'])"
              )
            ]
          ),
          InstantNamespacePermissions(
            namespace: "points",
            allow: [
              .view: "true",
              .create: "auth.id != null",
              .update: "isOwner && onlyMutableFields",
              .delete: "false",
            ],
            bind: [
              InstantPermissionBinding("isOwner", "auth.id == data.userId"),
              InstantPermissionBinding(
                "onlyMutableFields",
                "request.modifiedFields.all(field, field in ['val'])"
              ),
            ]
          ),
        ]
      )
    )
  }

  @Test
  func generatedTypeScriptRoundTripsTheCanonicalContract() throws {
    let schemaSource = try TypeScriptSchemaPrinter().printSchema(
      InstantSchemaExamples.stroopwafelDocument
    )
    let permissionsSource = try TypeScriptPermissionsPrinter().printPermissions(
      InstantSchemaExamples.stroopwafelPermissions
    )

    expectNoDifference(
      try TypeScriptSchemaParser().parseDocument(schemaSource),
      ParsedInstantSchemaDocument(InstantSchemaExamples.stroopwafelDocument)
    )
    let parsedPermissions = try TypeScriptPermissionsParser().parse(permissionsSource)
    var expectedPermissions = InstantSchemaExamples.stroopwafelPermissions
    expectedPermissions.namespaces.sort { $0.namespace < $1.namespace }
    expectNoDifference(parsedPermissions, expectedPermissions)
    #expect(!schemaSource.contains("presence:"))
    #expect(!schemaSource.contains("topics:"))
    #expect(permissionsSource.contains("request.modifiedFields.all(field, field in ['val'])"))
  }

  @Test
  func serverManagedEmailStringNormalizesToCanonicalAnyWithExplicitWarning() throws {
    let expected = ParsedInstantSchemaDocument(InstantSchemaExamples.stroopwafelDocument)
    var server = expected
    let usersIndex = try #require(server.entities.firstIndex { $0.namespace == "$users" })
    let emailIndex = try #require(
      server.entities[usersIndex].attributes.firstIndex { $0.name == "email" }
    )
    server.entities[usersIndex].attributes[emailIndex].valueType = .string

    let comparison = try server.comparingServerNormalized(to: expected)

    expectNoDifference(comparison.normalizedDocument, expected)
    expectNoDifference(
      comparison.warnings,
      [
        InstantServerSchemaWarning(
          code: .serverSystemStringAsAny,
          path: "$users.email"
        )
      ]
    )
  }
}
