import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

extension InstantStoreTests {
  @Test
  func cliInitScaffoldsTodoExampleFiles() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    let scaffoldURL = homeURL.appendingPathComponent("TodoScaffold", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let output = try JSONDecoder().decode(
      CLIInitOutput.self,
      from: Data(
        try runCLI(["init", "--example", "todos", "--to", scaffoldURL.path, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(output.example, "todos")
    expectNoDifference(output.directory, scaffoldURL.path)
    expectNoDifference(output.transport, "not-implemented-local-cache-only")
    expectNoDifference(output.files.map(\.kind), ["schema", "permissions", "swift-schema", "readme"])

    let schemaURL = scaffoldURL.appendingPathComponent("instant.schema.ts")
    let permissionsURL = scaffoldURL.appendingPathComponent("instant.perms.ts")
    let swiftSchemaURL = scaffoldURL.appendingPathComponent("Schema.swift")
    let readmeURL = scaffoldURL.appendingPathComponent("README.md")
    for url in [schemaURL, permissionsURL, swiftSchemaURL, readmeURL] {
      #expect(FileManager.default.fileExists(atPath: url.path))
    }
    #expect(try String(contentsOf: swiftSchemaURL).contains("InstantSchemaExamples.todosDocument"))
    #expect(try String(contentsOf: readmeURL).contains("not-implemented-local-cache-only"))

    _ = try runCLI(
      ["schema", "verify", "--example", "todos", "--from", schemaURL.path, "--json"],
      homeURL: homeURL
    )
    _ = try runCLI(
      ["perms", "verify", "--example", "todos", "--from", permissionsURL.path, "--json"],
      homeURL: homeURL
    )

    let schemaStdout = try JSONDecoder().decode(
      CLIGeneratedArtifactOutput.self,
      from: Data(
        try runCLI(["schema", "generate", "--example", "todos", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(schemaStdout.kind, "schema")
    expectNoDifference(schemaStdout.fileName, "instant.schema.ts")
    expectNoDifference(schemaStdout.path, nil)
    #expect(try #require(schemaStdout.contents).contains("export default i.schema({"))

    let rawSchema = try runCLI(["schema", "generate", "--example", "todos"], homeURL: homeURL)
    #expect(rawSchema.contains("export default i.schema({"))
    #expect(!rawSchema.contains(#""kind""#))

    let rawPermissions = try runCLI(["perms", "generate", "--example", "todos"], homeURL: homeURL)
    #expect(rawPermissions.contains("export default rules;"))
    #expect(!rawPermissions.contains(#""kind""#))

    let generatedSchemaURL = homeURL.appendingPathComponent("Generated/instant.schema.ts")
    let generatedSchema = try JSONDecoder().decode(
      CLIGeneratedArtifactOutput.self,
      from: Data(
        try runCLI(
          ["schema", "generate", "--example", "todos", "--to", generatedSchemaURL.path, "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(generatedSchema.kind, "schema")
    expectNoDifference(generatedSchema.path, generatedSchemaURL.path)
    expectNoDifference(generatedSchema.contents, nil)
    #expect(generatedSchema.byteCount > 0)
    _ = try runCLI(
      ["schema", "verify", "--example", "todos", "--from", generatedSchemaURL.path, "--json"],
      homeURL: homeURL
    )
    let quietSchemaURL = homeURL.appendingPathComponent("Generated/quiet.schema.ts")
    let quietSchema = try runCLI(
      ["schema", "generate", "--example", "todos", "--to", quietSchemaURL.path],
      homeURL: homeURL
    )
    expectNoDifference(quietSchema, "")
    _ = try runCLI(
      ["schema", "verify", "--example", "todos", "--from", quietSchemaURL.path, "--json"],
      homeURL: homeURL
    )

    let generatedPermissionsURL = homeURL.appendingPathComponent("Generated/instant.perms.ts")
    let permissionsJSONL = try runCLI(
      ["perms", "generate", "--example", "todos", "--to", generatedPermissionsURL.path, "--jsonl"],
      homeURL: homeURL
    )
    let permissionsLines = permissionsJSONL.split(separator: "\n")
    expectNoDifference(permissionsLines.count, 1)
    let permissionsEvidence = try JSONDecoder().decode(
      CLIGeneratedArtifactEvidence.self,
      from: Data(try #require(permissionsLines.first).utf8)
    )
    expectNoDifference(permissionsEvidence.caseID, "cli.perms.generate")
    expectNoDifference(permissionsEvidence.appID, "permissions-tooling")
    expectNoDifference(permissionsEvidence.event, "artifact")
    expectNoDifference(permissionsEvidence.details.kind, "permissions")
    expectNoDifference(permissionsEvidence.details.path, generatedPermissionsURL.path)
    expectNoDifference(permissionsEvidence.details.contents, nil)
    _ = try runCLI(
      ["perms", "verify", "--example", "todos", "--from", generatedPermissionsURL.path, "--json"],
      homeURL: homeURL
    )
    let quietPermissionsURL = homeURL.appendingPathComponent("Generated/quiet.perms.ts")
    let quietPermissions = try runCLI(
      ["perms", "generate", "--example", "todos", "--to", quietPermissionsURL.path],
      homeURL: homeURL
    )
    expectNoDifference(quietPermissions, "")
    _ = try runCLI(
      ["perms", "verify", "--example", "todos", "--from", quietPermissionsURL.path, "--json"],
      homeURL: homeURL
    )

    let collisionURL = homeURL.appendingPathComponent("TodoScaffoldCollision", isDirectory: true)
    try FileManager.default.createDirectory(at: collisionURL, withIntermediateDirectories: true)
    let collisionReadmeURL = collisionURL.appendingPathComponent("README.md")
    try Data("sentinel readme".utf8).write(to: collisionReadmeURL)
    let collision = try runCLIResult(
      ["init", "--example", "todos", "--to", collisionURL.path, "--json"],
      homeURL: homeURL
    )
    #expect(collision.status == 73)
    #expect(collision.error.contains("Scaffold refused to overwrite existing file(s)"))
    expectNoDifference(try String(contentsOf: collisionReadmeURL), "sentinel readme")
    #expect(!FileManager.default.fileExists(
      atPath: collisionURL.appendingPathComponent("instant.schema.ts").path
    ))

    let forcedOutput = try JSONDecoder().decode(
      CLIInitOutput.self,
      from: Data(
        try runCLI(
          ["init", "--example", "todos", "--to", collisionURL.path, "--force", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(forcedOutput.files.map(\.kind), ["schema", "permissions", "swift-schema", "readme"])
    #expect(try String(contentsOf: collisionReadmeURL).contains("Instant Swift Data Todo Scaffold"))

    let jsonlURL = homeURL.appendingPathComponent("TodoScaffoldJSONL", isDirectory: true)
    let jsonlOutput = try runCLI(
      ["init", "--example", "todos", "--to", jsonlURL.path, "--jsonl"],
      homeURL: homeURL
    )
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 5)
    let evidence = try JSONDecoder().decode(
      CLIInitEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.init")
    expectNoDifference(evidence.event, "summary")
    expectNoDifference(evidence.details.files.map(\.kind), ["schema", "permissions", "swift-schema", "readme"])

    let humanURL = homeURL.appendingPathComponent("TodoScaffoldHuman", isDirectory: true)
    let humanOutput = try runCLI(
      ["init", "--example", "todos", "--to", humanURL.path],
      homeURL: homeURL
    )
    #expect(humanOutput.contains("transport: not-implemented-local-cache-only"))
    #expect(humanOutput.contains("instant.schema.ts"))

    let unsupported = try runCLIResult(
      ["init", "--example", "rooms", "--to", scaffoldURL.path, "--json"],
      homeURL: homeURL
    )
    #expect(unsupported.status == 64)
    #expect(unsupported.error.contains("Only '--example todos' is implemented"))
  }

  @Test
  func cliSchemaPermissionsValidationExampleGenerateAndVerify() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    let generatedDirectoryURL = homeURL.appendingPathComponent("Generated", isDirectory: true)
    let generatedSchemaURL = generatedDirectoryURL.appendingPathComponent("validation.schema.ts")
    let generatedPermissionsURL = generatedDirectoryURL.appendingPathComponent("validation.perms.ts")
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let schemaStdout = try JSONDecoder().decode(
      CLIGeneratedArtifactOutput.self,
      from: Data(
        try runCLI(["schema", "generate", "--example", "validation", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(schemaStdout.example, "validation")
    expectNoDifference(schemaStdout.kind, "schema")
    expectNoDifference(schemaStdout.fileName, "instant.schema.ts")
    expectNoDifference(schemaStdout.path, nil)
    #expect(try #require(schemaStdout.contents).contains("postAuthor"))
    #expect(try #require(schemaStdout.contents).contains("rooms"))

    let generatedSchema = try JSONDecoder().decode(
      CLIGeneratedArtifactOutput.self,
      from: Data(
        try runCLI(
          [
            "schema", "generate", "--example", "validation",
            "--to", generatedSchemaURL.path,
            "--json",
          ],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(generatedSchema.example, "validation")
    expectNoDifference(generatedSchema.path, generatedSchemaURL.path)
    expectNoDifference(generatedSchema.contents, nil)
    #expect(generatedSchema.byteCount > 0)

    let schemaVerify = try JSONDecoder().decode(
      CLISchemaVerifyOutput.self,
      from: Data(
        try runCLI(
          ["schema", "verify", "--example", "validation", "--from", generatedSchemaURL.path, "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(schemaVerify.example, "validation")
    expectNoDifference(schemaVerify.entityCount, 2)
    expectNoDifference(schemaVerify.attributeCount, 7)
    expectNoDifference(schemaVerify.linkCount, 1)

    let permissionsOutput = try JSONDecoder().decode(
      CLIGeneratedArtifactOutput.self,
      from: Data(
        try runCLI(
          [
            "perms", "generate", "--example", "validation",
            "--to", generatedPermissionsURL.path,
            "--json",
          ],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(permissionsOutput.example, "validation")
    expectNoDifference(permissionsOutput.kind, "permissions")
    expectNoDifference(permissionsOutput.path, generatedPermissionsURL.path)
    expectNoDifference(permissionsOutput.contents, nil)

    let permissionsVerify = try JSONDecoder().decode(
      CLIPermissionsVerifyOutput.self,
      from: Data(
        try runCLI(
          ["perms", "verify", "--example", "validation", "--from", generatedPermissionsURL.path, "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(permissionsVerify.example, "validation")
    expectNoDifference(permissionsVerify.namespaceCount, 3)
    expectNoDifference(permissionsVerify.allowRuleCount, 12)
    expectNoDifference(permissionsVerify.rateLimitCount, 0)

    let fixtureURL = packageRootURL()
      .appendingPathComponent("validation/fixtures", isDirectory: true)
    let fixtureSchemaVerify = try JSONDecoder().decode(
      CLISchemaVerifyOutput.self,
      from: Data(
        try runCLI(
          [
            "schema", "verify", "--example", "validation",
            "--from", fixtureURL.appendingPathComponent("instant.schema.ts").path,
            "--json",
          ],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(fixtureSchemaVerify.example, "validation")
    expectNoDifference(fixtureSchemaVerify.entityCount, 2)
    expectNoDifference(fixtureSchemaVerify.attributeCount, 7)
    expectNoDifference(fixtureSchemaVerify.linkCount, 1)

    let fixturePermissionsVerify = try JSONDecoder().decode(
      CLIPermissionsVerifyOutput.self,
      from: Data(
        try runCLI(
          [
            "perms", "verify", "--example", "validation",
            "--from", fixtureURL.appendingPathComponent("instant.perms.ts").path,
            "--json",
          ],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(fixturePermissionsVerify.example, "validation")
    expectNoDifference(fixturePermissionsVerify.namespaceCount, 3)
    expectNoDifference(fixturePermissionsVerify.allowRuleCount, 12)

    let unsupported = try runCLIResult(
      ["schema", "generate", "--example", "rooms", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(unsupported.status, 64)
    #expect(unsupported.error.contains("Available examples: todos, validation"))
  }

  @Test
  func cliTopLevelHelpListsValidationSchemaExample() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let help = try runCLIResult(["--help"], homeURL: homeURL)

    expectNoDifference(help.status, 0)
    expectNoDifference(help.error, "")
    #expect(help.output.contains("schema generate --example todos|validation"))
    #expect(help.output.contains("schema verify --example todos|validation"))
    #expect(help.output.contains("perms generate --example todos|validation"))
    #expect(help.output.contains("perms verify --example todos|validation"))
  }

  @Test
  func cliMalformedToolingArgumentsDoNotCreateFiles() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    let scaffoldURL = homeURL.appendingPathComponent("TodoScaffold", isDirectory: true)
    let schemaURL = homeURL.appendingPathComponent("Generated/instant.schema.ts")
    let permissionsURL = homeURL.appendingPathComponent("Generated/instant.perms.ts")
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["init", "--to", scaffoldURL.path, "--json"],
      contains: "instant-swift-data init --example todos --to <directory>"
    )
    try expectMalformed(
      ["init", "--example", "todos", "--to", scaffoldURL.path, "--surprise", "--json"],
      contains: "Unknown init option: --surprise"
    )
    try expectMalformed(
      ["schema", "generate", "--to", schemaURL.path, "--json"],
      contains: "schema generate --example todos|validation"
    )
    try expectMalformed(
      ["schema", "dance", "--to", schemaURL.path, "--json"],
      contains: "schema generate --example todos|validation"
    )
    try expectMalformed(
      ["schema", "verify", "--example", "todos", "--unknown", "--json"],
      contains: "Unknown schema verify option: --unknown"
    )
    try expectMalformed(
      ["perms", "generate", "--example", "todos", "--unknown", "--json"],
      contains: "Unknown generate option: --unknown"
    )
    try expectMalformed(
      ["perms", "verify", "--example", "todos", "--from", "--json"],
      contains: "perms verify --example todos|validation --from instant.perms.ts"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
    #expect(!FileManager.default.fileExists(atPath: scaffoldURL.path))
    #expect(!FileManager.default.fileExists(atPath: schemaURL.path))
    #expect(!FileManager.default.fileExists(atPath: permissionsURL.path))
  }

  @Test
  func cliQueryTodosPrintsDecodedLocalResults() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "query open", "--json"], homeURL: homeURL)
    let completedAddOutput = try runCLI(
      ["examples", "todos", "add", "query completed", "--json"],
      homeURL: homeURL
    )
    let completedAdd = try JSONDecoder().decode(CLIAddOutput.self, from: Data(completedAddOutput.utf8))
    let completedID = try #require(completedAdd.changedID)
    _ = try runCLI(["examples", "todos", "complete", completedID, "--json"], homeURL: homeURL)
    _ = try runCLI(["examples", "todos", "add", "query second open", "--json"], homeURL: homeURL)

    let completedQuery = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["query", "todos", "--completed", "true", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(completedQuery.event, "query")
    expectNoDifference(completedQuery.transport, "not-implemented-local-cache-only")
    expectNoDifference(completedQuery.queryID, "examples.todos.list.completed-true")
    #expect(completedQuery.cacheKey.hasPrefix("plan:"))
    expectNoDifference(completedQuery.todos.map(\.text), ["query completed"])
    expectNoDifference(completedQuery.todos.map(\.isCompleted), [true])
    expectNoDifference(completedQuery.pendingMutationCount, 4)

    let jsonlOutput = try runCLI(
      ["query", "todos", "--completed", "false", "--jsonl"],
      homeURL: homeURL
    )
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 3)
    let summary = try JSONDecoder().decode(
      CLITodosEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.query.todos")
    expectNoDifference(summary.event, "query")
    expectNoDifference(summary.details.transport, "not-implemented-local-cache-only")
    expectNoDifference(summary.details.queryID, "examples.todos.list.completed-false")
    expectNoDifference(summary.details.todos.map(\.text), ["query open", "query second open"])

    let firstPage = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["query", "todos", "--completed", "false", "--first", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(firstPage.todos.map(\.text), ["query open"])
    expectNoDifference(firstPage.pageInfo?.hasPreviousPage, false)
    expectNoDifference(firstPage.pageInfo?.hasNextPage, true)

    let cursorID = try #require(firstPage.pageInfo?.endCursor?.entityID)
    let secondPage = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["query", "todos", "--completed", "false", "--first", "1", "--after", cursorID, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(secondPage.todos.map(\.text), ["query second open"])
    expectNoDifference(secondPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(secondPage.pageInfo?.hasNextPage, false)

    let inclusivePage = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          [
            "query", "todos", "--completed", "false", "--first", "1",
            "--after-inclusive", cursorID, "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(inclusivePage.todos.map(\.text), ["query open"])

    let duplicateQueryOptions = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          [
            "query", "todos", "--completed", "true", "--completed", "false",
            "--limit", "1", "--limit", "2", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(
      duplicateQueryOptions.queryID,
      "examples.todos.list.completed-false.limit-2"
    )
    expectNoDifference(duplicateQueryOptions.todos.map(\.text), ["query open", "query second open"])

    let invalidBidirectionalPage = try runCLIResult(
      ["query", "todos", "--first", "1", "--last", "1", "--json"],
      homeURL: homeURL
    )
    #expect(invalidBidirectionalPage.status == 64)
    #expect(invalidBidirectionalPage.error.contains("Use either --first or --last"))

    let selectedSnapshotsJSON = try runCLI(
      ["query", "todos", "--completed", "false", "--select", "text,isCompleted", "--json"],
      homeURL: homeURL
    )
    #expect(selectedSnapshotsJSON.contains(#""event" : "query""#))
    #expect(selectedSnapshotsJSON.contains(#""transport" : "not-implemented-local-cache-only""#))
    #expect(selectedSnapshotsJSON.contains(#""selectedFields" : ["#))
    #expect(selectedSnapshotsJSON.contains(#""isCompleted""#))
    #expect(selectedSnapshotsJSON.contains(#""text""#))
    #expect(!selectedSnapshotsJSON.contains(#""createdAt""#))
    #expect(selectedSnapshotsJSON.contains("query open"))
    #expect(selectedSnapshotsJSON.contains("query second open"))
    #expect(!selectedSnapshotsJSON.contains("query completed"))

    let explicitRawSnapshots = try runCLI(
      ["query", "todos", "--raw", "--select", "text,isCompleted", "--json"],
      homeURL: homeURL
    )
    #expect(explicitRawSnapshots.contains(#""selectedFields" : ["#))
    #expect(explicitRawSnapshots.contains(#""isCompleted""#))
    #expect(explicitRawSnapshots.contains(#""text""#))
    #expect(!explicitRawSnapshots.contains(#""createdAt""#))

    let selectedHumanOutput = try runCLI(
      ["query", "todos", "--completed", "false", "--select", "text,isCompleted"],
      homeURL: homeURL
    )
    #expect(selectedHumanOutput.contains("fields=isCompleted,text"))

    let badSelection = try runCLIResult(
      ["query", "todos", "--select", "missing", "--json"],
      homeURL: homeURL
    )
    #expect(badSelection.status == 66)
    #expect(badSelection.error.contains("validate query"))
    #expect(badSelection.error.contains("path: missing"))

    let humanOutput = try runCLI(["query", "todos", "--completed", "true"], homeURL: homeURL)
    #expect(humanOutput.contains("transport: not-implemented-local-cache-only"))
    #expect(humanOutput.contains("query completed"))

    let malformed = try runCLIResult(["query", "todos", "--completed", "--json"], homeURL: homeURL)
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("instant-swift-data query todos --completed"))

    _ = try runCLI(["connection", "close", "--json"], homeURL: homeURL)
    let offlineQuery = try runCLIResult(["query", "todos", "--completed", "false", "--json"], homeURL: homeURL)
    #expect(offlineQuery.status == 69)
    #expect(offlineQuery.error.contains("Cannot run query 'examples.todos.list.completed-false'"))
    #expect(offlineQuery.error.contains("cached query: examples.todos.list.completed-false results: 2"))
    _ = try runCLI(["connection", "connect", "--json"], homeURL: homeURL)

    let unsupported = try runCLIResult(["query", "rooms", "--json"], homeURL: homeURL)
    #expect(unsupported.status == 64)
    #expect(unsupported.error.contains("query <namespace>"))
  }

  @Test
  func cliAdminTransactAndQueryUseDurableLocalStore() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let adminTransactionID = "tx-admin-note-1"
    let created = try JSONDecoder().decode(
      CLIAdminTransactOutput.self,
      from: Data(
        try runCLI(
          [
            "admin", "transact", "notes", "note-1", "--merge",
            #"{"done":false,"meta":{"source":"cli"},"title":"Admin note"}"#,
            "--transaction-id", adminTransactionID,
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(created.event, "transact")
    expectNoDifference(created.changedID, "note-1")
    expectNoDifference(created.transport, "not-implemented-local-cache-only")
    expectNoDifference(created.namespace, "notes")
    expectNoDifference(created.transactionID, adminTransactionID)
    expectNoDifference(created.changedEntityIDs, ["note-1"])
    expectNoDifference(created.pendingMutationCount, 1)
    expectNoDifference(created.snapshotCount, 1)
    let createdSnapshot = try #require(created.snapshots.first)
    expectNoDifference(createdSnapshot.namespace, "notes")
    expectNoDifference(createdSnapshot.id, "note-1")
    expectNoDifference(createdSnapshot.values["title"]?.first, .some(.string("Admin note")))
    expectNoDifference(createdSnapshot.values["done"]?.first, .some(.bool(false)))
    expectNoDifference(
      createdSnapshot.values["meta"]?.first,
      .some(.json(.object(["source": .string("cli")])))
    )

    let replayed = try JSONDecoder().decode(
      CLIAdminTransactOutput.self,
      from: Data(
        try runCLI(
          [
            "admin", "transact", "notes", "note-1", "--merge",
            #"{"done":false,"meta":{"source":"cli"},"title":"Admin note"}"#,
            "--transaction-id", adminTransactionID,
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(replayed.transactionID, adminTransactionID)
    expectNoDifference(replayed.changedEntityIDs, [])
    expectNoDifference(replayed.pendingMutationCount, 1)
    expectNoDifference(replayed.snapshots, created.snapshots)

    let conflictingReplay = try runCLIResult(
      [
        "admin", "transact", "notes", "note-2", "--merge", #"{"title":"Different note"}"#,
        "--transaction-id", adminTransactionID, "--json",
      ],
      homeURL: homeURL
    )
    #expect(conflictingReplay.status == 66)
    #expect(conflictingReplay.error.contains("already pending with different operations"))

    let outbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(outbox.pendingMutationCount, 1)
    expectNoDifference(outbox.mutations.map(\.id), [adminTransactionID])

    let queried = try JSONDecoder().decode(
      CLIAdminQueryOutput.self,
      from: Data(
        try runCLI(["admin", "query", "notes", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(queried.event, "admin-query")
    expectNoDifference(queried.transport, "not-implemented-local-cache-only")
    expectNoDifference(queried.pendingMutationCount, 1)
    expectNoDifference(queried.snapshots, created.snapshots)

    let jsonlOutput = try runCLI(["admin", "query", "notes", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 2)
    let evidence = try JSONDecoder().decode(
      CLIAdminQueryEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.admin.query")
    expectNoDifference(evidence.event, "admin-query")
    expectNoDifference(evidence.details.snapshots.map(\.id), ["note-1"])
    let snapshotRow = try JSONDecoder().decode(
      CLIAdminSnapshotEvidence.self,
      from: Data(try #require(lines.dropFirst().first).utf8)
    )
    expectNoDifference(snapshotRow.caseID, "cli.admin.query")
    expectNoDifference(snapshotRow.event, "snapshot")
    expectNoDifference(snapshotRow.details.id, "note-1")

    let limited = try JSONDecoder().decode(
      CLIAdminQueryOutput.self,
      from: Data(
        try runCLI(["admin", "query", "notes", "--limit", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(limited.snapshots.map(\.id), ["note-1"])

    let duplicateLimitResult = try runCLIResult(
      ["admin", "query", "notes", "--limit", "0", "--limit", "1", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(duplicateLimitResult.status, 0)
    let duplicateLimitJSON = try #require(
      JSONSerialization.jsonObject(with: Data(duplicateLimitResult.output.utf8)) as? [String: Any]
    )
    #expect(duplicateLimitJSON["queryID"] as? String == "admin.bm90ZXM.query.limit-1")
    let duplicateLimitSnapshots = try #require(
      duplicateLimitJSON["snapshots"] as? [[String: Any]]
    )
    #expect(duplicateLimitSnapshots.compactMap { $0["id"] as? String } == ["note-1"])

    let transactJSONL = try runCLI(
      ["admin", "transact", "notes", "note-2", "--merge", #"{"title":"JSONL note"}"#, "--jsonl"],
      homeURL: homeURL
    )
    let transactLines = transactJSONL.split(separator: "\n")
    expectNoDifference(transactLines.count, 3)
    let transactEvidence = try JSONDecoder().decode(
      CLIAdminTransactEvidence.self,
      from: Data(try #require(transactLines.first).utf8)
    )
    expectNoDifference(transactEvidence.caseID, "cli.admin.transact")
    expectNoDifference(transactEvidence.event, "transact")
    expectNoDifference(transactEvidence.details.changedID, "note-2")
    expectNoDifference(transactEvidence.details.snapshots.map(\.id), ["note-1", "note-2"])
    let transactRows = try transactLines.dropFirst().map {
      try JSONDecoder().decode(CLIAdminSnapshotEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(transactRows.map(\.caseID), ["cli.admin.transact", "cli.admin.transact"])
    expectNoDifference(transactRows.map(\.event), ["snapshot", "snapshot"])
    expectNoDifference(transactRows.map(\.details.id), ["note-1", "note-2"])

    let updated = try JSONDecoder().decode(
      CLIAdminTransactOutput.self,
      from: Data(
        try runCLI(
          ["admin", "transact", "notes", "note-1", "--merge", #"{"done":true}"#, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(updated.pendingMutationCount, 3)
    let updatedSnapshot = try #require(updated.snapshots.first { $0.id == "note-1" })
    expectNoDifference(updatedSnapshot.values["title"]?.first, .some(.string("Admin note")))
    expectNoDifference(updatedSnapshot.values["done"]?.first, .some(.bool(true)))

    let missingMerge = try runCLIResult(
      ["admin", "transact", "notes", "note-2", "--json"],
      homeURL: homeURL
    )
    #expect(missingMerge.status == 64)
    #expect(missingMerge.error.contains("admin transact"))

    let reservedID = try runCLIResult(
      ["admin", "transact", "notes", "note-2", "--merge", #"{"id":"blocked"}"#, "--json"],
      homeURL: homeURL
    )
    #expect(reservedID.status == 64)
    #expect(reservedID.error.contains("reserved 'id' field"))

    let badNamespace = try runCLIResult(["admin", "query", "bad/namespace", "--json"], homeURL: homeURL)
    #expect(badNamespace.status == 64)
    #expect(badNamespace.error.contains("namespace must not be empty"))
  }

  @Test
  func cliMalformedAdminArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["admin", "query", "bad/namespace", "--json"],
      contains: "namespace must not be empty"
    )
    try expectMalformed(
      ["admin", "query", "notes", "--limit", "-1", "--json"],
      contains: "--limit must be a non-negative integer"
    )
    try expectMalformed(
      ["admin", "query", "notes", "--unknown", "--json"],
      contains: "Unknown admin query option"
    )
    try expectMalformed(
      ["admin", "transact", "notes", "note-1", "--merge", "--json"],
      contains: "admin transact"
    )
    try expectMalformed(
      ["admin", "transact", "notes", "note-1", "--merge", "[", "--unknown", "--json"],
      contains: "admin transact: Invalid JSON value"
    )
    try expectMalformed(
      [
        "admin", "transact", "notes", "note-1", "--merge", "[", "--transaction-id", "  ",
        "--json",
      ],
      contains: "admin transact: Invalid JSON value"
    )
    try expectMalformed(
      ["admin", "transact", "notes", "note-1", "--merge", "[]", "--json"],
      contains: "--merge must be a JSON object"
    )
    try expectMalformed(
      ["admin", "transact", "notes", "note-1", "--merge", "{}", "--json"],
      contains: "--merge must include at least one field"
    )
    try expectMalformed(
      [
        "admin", "transact", "notes", "note-1", "--merge", #"{"title":"One"}"#, "--merge",
        #"{"title":"Two"}"#, "--json",
      ],
      contains: "admin transact"
    )
    try expectMalformed(
      [
        "admin", "transact", "notes", "note-1", "--merge", #"{"title":"One"}"#,
        "--transaction-id", "tx-1", "--transaction-id", "tx-2", "--json",
      ],
      contains: "admin transact"
    )
    try expectMalformed(
      [
        "admin", "tx", "notes", "note-1", "--merge", #"{"title":"One"}"#, "--unknown",
        "--json",
      ],
      contains: "Unknown admin transact option"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedQueryAndValidationArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["query", "--json"],
      contains: "query <namespace>"
    )
    try expectMalformed(
      ["query", "rooms", "--json"],
      contains: "query <namespace>"
    )
    try expectMalformed(
      ["query", "todos", "--completed", "--json"],
      contains: "instant-swift-data query todos --completed true|false"
    )
    try expectMalformed(
      ["query", "todos", "--search", "  ", "--json"],
      contains: "instant-swift-data query todos --search text"
    )
    try expectMalformed(
      ["query", "todos", "--after", "  ", "--json"],
      contains: "instant-swift-data query todos --after id"
    )
    try expectMalformed(
      ["query", "todos", "--first", "1", "--last", "1", "--json"],
      contains: "Use either --first or --last"
    )
    try expectMalformed(
      ["query", "todos", "--unknown", "--json"],
      contains: "Unknown todo query option"
    )
    try expectMalformed(
      ["validation", "remote", "--json"],
      contains: "validation <local-todos|local-integrations|reminders|typed-drafts|platform-adapters|syncups-recording|parity-report|coverage>"
    )
    try expectMalformed(
      ["validation", "todos", "extra", "--json"],
      contains: "validation <local-todos|local-integrations|reminders|typed-drafts|platform-adapters|syncups-recording|parity-report|coverage>"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedExamplesTodosArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "todos", "seed", "unexpected", "--json"],
      contains: "examples todos seed"
    )
    try expectMalformed(
      ["examples", "todos", "add", "  ", "--json"],
      contains: #"examples todos add "todo text""#
    )
    try expectMalformed(
      ["examples", "todos", "list", "--unknown", "--json"],
      contains: "Unknown todo list option: --unknown"
    )
    try expectMalformed(
      ["examples", "todos", "watch", "--events", "2", "--jsonl"],
      contains: "examples todos watch --events 1"
    )
    try expectMalformed(
      ["examples", "todos", "watch", "--completed", "maybe", "--jsonl"],
      contains: "examples todos watch --completed true|false"
    )
    try expectMalformed(
      ["examples", "todos", "complete", "--json"],
      contains: "examples todos complete <todo-id>"
    )
    try expectMalformed(
      ["examples", "todos", "update", "todo-1", "--json"],
      contains: "examples todos update <todo-id>"
    )
    try expectMalformed(
      ["examples", "todos", "delete", "todo-1", "extra", "--json"],
      contains: "examples todos delete <todo-id>"
    )
    try expectMalformed(
      ["examples", "todos", "reset", "extra", "--json"],
      contains: "examples todos reset"
    )
    try expectMalformed(
      ["examples", "todos", "refresh", "--completed", "maybe", "--json"],
      contains: "examples todos list --completed true|false"
    )
    try expectMalformed(
      ["examples", "todos", "dance", "--json"],
      contains: "Unknown todos command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedExamplesAuthArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "auth", "--json"],
      contains: "examples auth <send-code|verify-code|status|watch|sign-out>"
    )
    try expectMalformed(
      ["examples", "authentication", "send-code", "--json"],
      contains: "examples auth send-code <email>"
    )
    try expectMalformed(
      ["examples", "auth", "verify-code", "user@example.com", "--json"],
      contains: "examples auth verify-code <email> <code>"
    )
    try expectMalformed(
      ["examples", "auth", "watch", "--events", "2", "--jsonl"],
      contains: "examples auth watch --events 1"
    )
    try expectMalformed(
      ["examples", "magic-code-auth", "dance", "--json"],
      contains: "Unknown auth recipe command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedAppBuilderArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "app-builder", "--json"],
      contains: "examples app-builder <generate|list|show|append|finish|reset>"
    )
    try expectMalformed(
      ["examples", "appbuilder", "generate", "--org-id", "org-1", "--json"],
      contains: #"examples app-builder generate "prompt""#
    )
    try expectMalformed(
      ["examples", "app-builder", "generate", "Build notes", "--org-id", "--json"],
      contains: "Missing value for --org-id"
    )
    try expectMalformed(
      ["examples", "builder", "append", "build-1", "--json"],
      contains: "examples app-builder append <build-id>"
    )
    try expectMalformed(
      ["examples", "builder", "dance", "--json"],
      contains: "Unknown app-builder command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedTodoLinksArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "todo-links", "--json"],
      contains: "examples todo-links <seed|list|nested|unlink>"
    )
    try expectMalformed(
      ["examples", "todo-links", "seed", "unexpected", "--json"],
      contains: "examples todo-links seed"
    )
    try expectMalformed(
      ["examples", "todo-links", "list", "unexpected", "--json"],
      contains: "examples todo-links list"
    )
    try expectMalformed(
      ["examples", "todo-links", "nested", "unexpected", "--json"],
      contains: "examples todo-links nested"
    )
    try expectMalformed(
      ["examples", "todo-links", "unlink", "unexpected", "--json"],
      contains: "examples todo-links unlink"
    )
    try expectMalformed(
      ["examples", "todo-links", "dance", "--json"],
      contains: "Unknown todo-links command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedCountersArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "counters", "--json"],
      contains: "examples counters <seed|add|list|increment|decrement|delete>"
    )
    try expectMalformed(
      ["examples", "counters", "add", "--count", "nope", "--json"],
      contains: "examples counters add"
    )
    try expectMalformed(
      ["examples", "cloudkit-demo", "increment", "  ", "--json"],
      contains: "examples counters increment <counter-id>"
    )
    try expectMalformed(
      ["examples", "cloudkit-demo", "dance", "--json"],
      contains: "Unknown counters command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedChatArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "chat", "--json"],
      contains: "examples chat <seed|channels|messages|post|reset>"
    )
    try expectMalformed(
      ["examples", "chat", "seed", "unexpected", "--json"],
      contains: "examples chat seed"
    )
    try expectMalformed(
      ["examples", "chat", "channels", "unexpected", "--json"],
      contains: "examples chat channels"
    )
    try expectMalformed(
      ["examples", "chat", "messages", "channel-1", "unexpected", "--json"],
      contains: "examples chat messages"
    )
    try expectMalformed(
      ["examples", "chat", "post", "channel-1", "--json"],
      contains: "examples chat post <channel-id>"
    )
    try expectMalformed(
      ["examples", "chat", "post", "channel-1", "--surprise", "Hello", "--json"],
      contains: "Unknown chat post option: --surprise"
    )
    try expectMalformed(
      ["examples", "chat", "reset", "unexpected", "--json"],
      contains: "examples chat reset"
    )
    try expectMalformed(
      ["examples", "chat", "dance", "--json"],
      contains: "Unknown chat command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedReactionsArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "reactions", "--json"],
      contains: "examples reactions <tap|list|watch>"
    )
    try expectMalformed(
      ["examples", "reaction", "tap", "sparkle", "--json"],
      contains: "Invalid reactions name: sparkle."
    )
    try expectMalformed(
      ["examples", "reactions", "tap", "wave", "--direction", "360", "--json"],
      contains: "Invalid reactions angle: 360."
    )
    try expectMalformed(
      ["examples", "reactions", "list", "--limit", "-1", "--json"],
      contains: "examples reactions list"
    )
    try expectMalformed(
      ["examples", "topics-reactions", "watch", "--events", "2", "--jsonl"],
      contains: "examples reactions watch"
    )
    try expectMalformed(
      ["examples", "reactions", "dance", "--json"],
      contains: "Unknown reactions command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedTypingIndicatorArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "typing-indicator", "--json"],
      contains: "examples typing-indicator <join|type|stop|list|watch|leave>"
    )
    try expectMalformed(
      ["examples", "typing", "join", "--json"],
      contains: "examples typing-indicator <join|type|stop|leave>"
    )
    try expectMalformed(
      ["examples", "typing-indicator", "type", "  ", "--json"],
      contains: "examples typing-indicator <join|type|stop|leave>"
    )
    try expectMalformed(
      ["examples", "typing-indicator", "list", "unexpected", "--json"],
      contains: "examples typing-indicator list"
    )
    try expectMalformed(
      ["examples", "typing-indicators", "watch", "--events", "2", "--jsonl"],
      contains: "examples typing-indicator watch"
    )
    try expectMalformed(
      ["examples", "typing-indicator", "leave", "--json"],
      contains: "examples typing-indicator <join|type|stop|leave>"
    )
    try expectMalformed(
      ["examples", "typing-indicator", "dance", "--json"],
      contains: "Unknown typing indicator command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedAvatarStackArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "avatar-stack", "--json"],
      contains: "examples avatar-stack <join|list|watch|leave>"
    )
    try expectMalformed(
      ["examples", "avatars", "join", "--json"],
      contains: "examples avatar-stack join <user-id>"
    )
    try expectMalformed(
      ["examples", "avatar-stack", "join", "user-1", "--name", "  ", "--json"],
      contains: "examples avatar-stack join <user-id>"
    )
    try expectMalformed(
      ["examples", "avatar-stack", "list", "unexpected", "--json"],
      contains: "examples avatar-stack list"
    )
    try expectMalformed(
      ["examples", "avatar-stack-recipe", "watch", "--events", "2", "--jsonl"],
      contains: "examples avatar-stack watch"
    )
    try expectMalformed(
      ["examples", "avatar-stack", "leave", "--json"],
      contains: "examples avatar-stack leave <user-id>"
    )
    try expectMalformed(
      ["examples", "avatar-stack", "dance", "--json"],
      contains: "Unknown avatar stack command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedCursorsArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "cursors", "--json"],
      contains: "examples cursors <move|list|watch|clear|leave>"
    )
    try expectMalformed(
      ["examples", "cursor", "move", "user-1", "--x", "1", "--y", "2", "--x-percent", "3", "--json"],
      contains: "examples cursors move <user-id>"
    )
    try expectMalformed(
      [
        "examples", "cursors", "move", "user-1",
        "--x", "1",
        "--y", "2",
        "--x-percent", "3",
        "--y-percent", "4",
        "--name", "Ada",
        "--json",
      ],
      contains: "examples cursors move <user-id>"
    )
    try expectMalformed(
      ["examples", "cursors", "list", "--viewer-user-id", "  ", "--json"],
      contains: "examples cursors list"
    )
    try expectMalformed(
      ["examples", "cursors", "watch", "--events", "2", "--jsonl"],
      contains: "examples cursors watch"
    )
    try expectMalformed(
      ["examples", "cursors", "clear", "--json"],
      contains: "examples cursors <clear|leave> <user-id>"
    )
    try expectMalformed(
      ["examples", "cursors", "dance", "--json"],
      contains: "Unknown cursors command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedCustomCursorsArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "custom-cursors", "--json"],
      contains: "examples custom-cursors <move|list|watch|clear|leave>"
    )
    try expectMalformed(
      [
        "examples", "custom-cursor", "move", "user-1",
        "--x", "1",
        "--y", "2",
        "--x-percent", "3",
        "--json",
      ],
      contains: "examples custom-cursors move <user-id>"
    )
    try expectMalformed(
      [
        "examples", "custom-cursors", "move", "user-1",
        "--x", "1",
        "--y", "2",
        "--x-percent", "3",
        "--y-percent", "4",
        "--name", "  ",
        "--json",
      ],
      contains: "examples custom-cursors move <user-id>"
    )
    try expectMalformed(
      ["examples", "custom-cursors", "list", "--viewer-user-id", "  ", "--json"],
      contains: "examples custom-cursors list"
    )
    try expectMalformed(
      ["examples", "custom-cursors", "watch", "--events", "2", "--jsonl"],
      contains: "examples custom-cursors watch"
    )
    try expectMalformed(
      ["examples", "custom-cursors", "leave", "--json"],
      contains: "examples custom-cursors <clear|leave> <user-id>"
    )
    try expectMalformed(
      ["examples", "custom-cursors", "dance", "--json"],
      contains: "Unknown custom cursors command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedMergeTileGameArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "merge-tile-game", "--json"],
      contains: "examples merge-tile-game <join|tap|board|watch|reset|leave>"
    )
    try expectMalformed(
      ["examples", "tile-game", "join", "--json"],
      contains: "examples merge-tile-game join <user-id>"
    )
    try expectMalformed(
      ["examples", "merge-game", "tap", "user-1", "0", "--json"],
      contains: "examples merge-tile-game tap <user-id>"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "tap", "user-1", "4", "0", "--json"],
      contains: "examples merge-tile-game tap <user-id>"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "board", "--viewer-user-id", "  ", "--json"],
      contains: "examples merge-tile-game board"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "watch", "--events", "2", "--jsonl"],
      contains: "examples merge-tile-game watch"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "reset", "again", "--json"],
      contains: "examples merge-tile-game reset"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "leave", "--json"],
      contains: "examples merge-tile-game leave <user-id>"
    )
    try expectMalformed(
      ["examples", "merge-tile-game", "dance", "--json"],
      contains: "Unknown merge tile game command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedSyncUpsArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "sync-ups", "--json"],
      contains: "examples sync-ups <seed|list|detail|add|edit|add-attendee|record|record-demo|delete|delete-attendee|delete-meeting>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "seed", "unexpected", "--json"],
      contains: "examples sync-ups seed"
    )
    try expectMalformed(
      ["examples", "sync-ups", "list", "--unknown", "--json"],
      contains: "examples sync-ups list"
    )
    try expectMalformed(
      ["examples", "sync-ups", "detail", "--json"],
      contains: "examples sync-ups detail <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "add", "Design", "--seconds", "0", "--attendee", "Blob", "--json"],
      contains: "Sync-up seconds must be a positive integer"
    )
    try expectMalformed(
      [
        "examples", "sync-ups", "add", "Design", "--theme", "chartreuse", "--attendee",
        "Blob", "--json",
      ],
      contains: "Unknown SyncUps theme. Use one of:"
    )
    try expectMalformed(
      ["examples", "sync-ups", "add", "Design", "--theme", "--json"],
      contains: "Unknown SyncUps theme. Use one of:"
    )
    try expectMalformed(
      ["examples", "sync-ups", "add", "Design", "--attendee", "--json"],
      contains: #"examples sync-ups add "title" --attendee name"#
    )
    try expectMalformed(
      ["examples", "sync-ups", "edit", "sync-1", "--json"],
      contains: "examples sync-ups edit <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "edit", "sync-1", "--theme", "chartreuse", "--json"],
      contains: "Unknown SyncUps theme. Use one of:"
    )
    try expectMalformed(
      ["examples", "sync-ups", "edit", "sync-1", "--theme", "--json"],
      contains: "Unknown SyncUps theme. Use one of:"
    )
    try expectMalformed(
      ["examples", "sync-ups", "edit", "sync-1", "--attendee", "  ", "--json"],
      contains: "Sync-up attendee replacement requires at least one non-empty --attendee"
    )
    try expectMalformed(
      ["examples", "sync-ups", "add-attendee", "sync-1", "  ", "--json"],
      contains: "examples sync-ups add-attendee <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "record", "sync-1", "--transcript", "--json"],
      contains: #"examples sync-ups record <sync-up-id> --transcript "text""#
    )
    try expectMalformed(
      ["examples", "sync-ups", "record-demo", "--json"],
      contains: "examples sync-ups record-demo <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "record-demo", "sync-1", "extra", "--json"],
      contains: "examples sync-ups record-demo <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "delete", "sync-1", "extra", "--json"],
      contains: "examples sync-ups delete <sync-up-id>"
    )
    try expectMalformed(
      ["examples", "sync-ups", "dance", "--json"],
      contains: "Unknown sync-ups command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedRemindersArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["examples", "reminders", "--json"],
      contains: "examples reminders <seed|list|stats|tags|list-tags|search|add-list"
    )
    try expectMalformed(
      ["examples", "reminders", "seed", "unexpected", "--json"],
      contains: "examples reminders seed"
    )
    try expectMalformed(
      ["examples", "reminders", "list", "--completed", "maybe", "--json"],
      contains: "examples reminders list"
    )
    try expectMalformed(
      ["examples", "reminders", "list", "--priority", "urgent", "--json"],
      contains: "examples reminders list"
    )
    try expectMalformed(
      ["examples", "reminders", "stats", "unexpected", "--json"],
      contains: "examples reminders stats"
    )
    try expectMalformed(
      ["examples", "reminders", "add-list", "  ", "--json"],
      contains: "examples reminders add-list"
    )
    try expectMalformed(
      ["examples", "reminders", "rename-list", "list-1", "--json"],
      contains: "examples reminders rename-list"
    )
    try expectMalformed(
      ["examples", "reminders", "add", "list-1", "Bad date", "--due-date", "not-a-date", "--json"],
      contains: "Invalid due date"
    )
    try expectMalformed(
      ["examples", "reminders", "add", "list-1", "Bad priority", "--priority", "urgent", "--json"],
      contains: "examples reminders add"
    )
    try expectMalformed(
      ["examples", "reminders", "add", "list-1", "Title", "--priority", "--json"],
      contains: "examples reminders add"
    )
    try expectMalformed(
      ["examples", "reminders", "update", "reminder-1", "--json"],
      contains: "examples reminders update"
    )
    try expectMalformed(
      ["examples", "reminders", "update", "reminder-1", "--due-date", "not-a-date", "--json"],
      contains: "Invalid due date"
    )
    try expectMalformed(
      ["examples", "reminders", "update", "reminder-1", "--priority", "urgent", "--json"],
      contains: "examples reminders update"
    )
    try expectMalformed(
      ["examples", "reminders", "complete", "reminder-1", "extra", "--json"],
      contains: "examples reminders complete"
    )
    try expectMalformed(
      ["examples", "reminders", "delete", "--json"],
      contains: "examples reminders delete <reminder-id>"
    )
    try expectMalformed(
      ["examples", "reminders", "delete-completed", "--list-id", "--json"],
      contains: "examples reminders delete-completed"
    )
    try expectMalformed(
      ["examples", "reminders", "delete-list", "list-1", "extra", "--json"],
      contains: "examples reminders delete-list"
    )
    try expectMalformed(
      ["examples", "reminders", "add-tag", "reminder-1", "#", "--json"],
      contains: "examples reminders add-tag"
    )
    try expectMalformed(
      ["examples", "reminders", "remove-tag", "reminder-1", "  ", "--json"],
      contains: "examples reminders remove-tag"
    )
    try expectMalformed(
      ["examples", "reminders", "search", "--json"],
      contains: "examples reminders search"
    )
    try expectMalformed(
      ["examples", "reminders", "search", "--tag", "#", "--json"],
      contains: "examples reminders search"
    )
    try expectMalformed(
      ["examples", "reminders", "search", "Take", "--priority", "urgent", "--json"],
      contains: "examples reminders search"
    )
    try expectMalformed(
      ["examples", "reminders", "dance", "--json"],
      contains: "Unknown reminders command: dance"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliQueryTodosSupportsServerCreatedAtOrder() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "seed", "--json"], homeURL: homeURL)
    let ordered = try runCLI(
      ["query", "todos", "--order-by", "serverCreatedAt", "--order", "desc", "--json"],
      homeURL: homeURL
    )
    #expect(ordered.contains(#""queryID" : "examples.todos.list.order-descending.order-by-serverCreatedAt""#))
    #expect(
      ordered.range(of: "Audit the local cache and outbox")?.lowerBound
        ?? ordered.endIndex
        < (ordered.range(of: "Run the non-captive terminal workflow")?.lowerBound ?? ordered.startIndex)
    )
    #expect(
      ordered.range(of: "Run the non-captive terminal workflow")?.lowerBound
        ?? ordered.endIndex
        < (ordered.range(of: "Plan the Instant Swift Data demo")?.lowerBound ?? ordered.startIndex)
    )

    let implicit = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["query", "todos", "--order-by", "none", "--first", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(implicit.queryID, "examples.todos.list.order-by-none.first-1")
    expectNoDifference(implicit.todos.count, 1)
    expectNoDifference(implicit.pageInfo?.hasNextPage, true)
    #expect(implicit.pageInfo?.endCursor?.sortValue != nil)
  }

  @Test
  func cliTodoLinksDemoPersistsAndUnlinksRefs() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let seed = try JSONDecoder().decode(
      CLITodoLinksOutput.self,
      from: Data(
        try runCLI(["examples", "todo-links", "seed", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(seed.event, "seed")
    expectNoDifference(seed.transport, "not-implemented-local-cache-only")
    expectNoDifference(seed.projects.map(\.title), ["Launch linked todos"])
    expectNoDifference(seed.todos.map(\.text), ["Wire a project link"])
    expectNoDifference(seed.todos.map(\.projectID), [seed.projects.first?.id])
    expectNoDifference(seed.pendingMutationCount, 1)

    let list = try JSONDecoder().decode(
      CLITodoLinksOutput.self,
      from: Data(
        try runCLI(["examples", "todo-links", "list", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(list.event, "list")
    expectNoDifference(list.projects, seed.projects)
    expectNoDifference(list.todos.map(\.projectID), [seed.projects.first?.id])

    let nested = try JSONDecoder().decode(
      CLITodoLinkSnapshotsOutput.self,
      from: Data(
        try runCLI(["examples", "todo-links", "nested", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(nested.event, "nested")
    expectNoDifference(nested.todos.map(\.id), seed.todos.map(\.id))
    expectNoDifference(nested.todos.first?.links?["project"]?.map(\.id), seed.projects.map(\.id))
    expectNoDifference(nested.projects.map(\.id), seed.projects.map(\.id))
    expectNoDifference(nested.projects.first?.links?["todos"]?.map(\.id), seed.todos.map(\.id))

    let unlinked = try JSONDecoder().decode(
      CLITodoLinksOutput.self,
      from: Data(
        try runCLI(["examples", "todo-links", "unlink", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(unlinked.event, "unlink")
    expectNoDifference(unlinked.projects, seed.projects)
    expectNoDifference(unlinked.todos.map(\.text), ["Wire a project link"])
    expectNoDifference(unlinked.todos.map(\.projectID), [nil])
    expectNoDifference(unlinked.pendingMutationCount, 2)

    let human = try runCLI(["examples", "todo-links", "list"], homeURL: homeURL)
    #expect(human.contains("project "))
    #expect(human.contains("Wire a project link"))
    #expect(!human.contains(" project="))

    let relinked = try JSONDecoder().decode(
      CLITodoLinksOutput.self,
      from: Data(
        try runCLI(["examples", "todo-links", "seed", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(relinked.event, "seed")
    expectNoDifference(relinked.projects, seed.projects)
    expectNoDifference(relinked.todos.map(\.projectID), [seed.projects.first?.id])
    expectNoDifference(relinked.pendingMutationCount, 3)
  }

  @Test
  func cliRemindersDemoPersistsAndSharesListRootsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let addedList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add-list", "Family", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(addedList.event, "add-list")
    expectNoDifference(addedList.transport, "not-implemented-local-cache-only")
    expectNoDifference(addedList.lists.map(\.list.title), ["Family"])
    expectNoDifference(addedList.lists.map(\.reminderCount), [0])
    expectNoDifference(addedList.pendingMutationCount, 1)
    let listID = try #require(addedList.changedID)

    let addedMilk = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add", listID, "Milk", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(addedMilk.event, "add")
    expectNoDifference(addedMilk.lists.map(\.reminderCount), [1])
    expectNoDifference(addedMilk.reminders.map(\.title), ["Milk"])
    let milkID = try #require(addedMilk.changedID)

    let completedMilk = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "complete", milkID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(completedMilk.event, "complete")
    expectNoDifference(completedMilk.lists.map(\.reminderCount), [0])
    expectNoDifference(completedMilk.reminders.map(\.isCompleted), [true])

    let addedEggs = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add", listID, "Eggs", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(addedEggs.lists.map(\.reminderCount), [1])
    expectNoDifference(addedEggs.reminders.map(\.title), ["Milk", "Eggs"])
    let eggsID = try #require(addedEggs.changedID)

    let refreshJSONL = try runCLI(
      ["examples", "reminders", "list", "--refresh", "--jsonl"],
      homeURL: homeURL
    )
    let refreshLines = refreshJSONL.split(separator: "\n")
    expectNoDifference(refreshLines.count, 4)
    let refreshEvidence = try JSONDecoder().decode(
      CLIRemindersEvidence.self,
      from: Data(try #require(refreshLines.first).utf8)
    )
    expectNoDifference(refreshEvidence.caseID, "cli.examples.reminders")
    expectNoDifference(refreshEvidence.event, "refresh")
    expectNoDifference(refreshEvidence.details.lists.map(\.reminderCount), [1])

    let createdShare = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(
          ["shares", "create", ReminderExample.listsNamespace, listID, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    let share = try #require(createdShare.shares.first)
    expectNoDifference(share.share.rootNamespace, ReminderExample.listsNamespace)
    expectNoDifference(share.share.rootID, listID)
    expectNoDifference(share.memberships.map(\.role), [.owner])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let accepted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "accept", share.share.token, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(accepted.shares.first?.memberships.map(\.role), [.owner, .reader])

    let readerUpdate = try runCLIResult(
      ["examples", "reminders", "update", eggsID, "Reader eggs", "--json"],
      homeURL: homeURL
    )
    #expect(readerUpdate.status == 77)
    #expect(readerUpdate.error.contains("reader access"))

    let readerRenameList = try runCLIResult(
      ["examples", "reminders", "rename-list", listID, "Reader Family", "--json"],
      homeURL: homeURL
    )
    #expect(readerRenameList.status == 77)
    #expect(readerRenameList.error.contains("reader access"))

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let promoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", share.share.id, "user-2", "writer", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(promoted.shares.first?.memberships.map(\.role), [.owner, .writer])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let writerUpdate = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "update", eggsID, "Writer eggs", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(writerUpdate.reminders.map(\.title), ["Milk", "Writer eggs"])
    expectNoDifference(writerUpdate.lists.map(\.reminderCount), [1])

    let writerComplete = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "complete", eggsID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(writerComplete.reminders.map(\.isCompleted), [true, true])
    expectNoDifference(writerComplete.lists.map(\.reminderCount), [0])

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let demoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", share.share.id, "user-2", "reader", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(demoted.shares.first?.memberships.map(\.role), [.owner, .reader])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let demotedReaderUpdate = try runCLIResult(
      ["examples", "reminders", "update", eggsID, "Reader again", "--json"],
      homeURL: homeURL
    )
    #expect(demotedReaderUpdate.status == 77)
    #expect(demotedReaderUpdate.error.contains("reader access"))
  }

  @Test
  func cliRemindersTagsSearchAndSeedPersistAcrossLaunches() throws {
    let fixedNow = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let fixedNowEnvironment = ["INSTANT_SWIFT_DATA_NOW": "\(fixedNow.milliseconds)"]
    let seedHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: seedHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: seedHomeURL) }

    let seeded = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "seed", "--json"],
          homeURL: seedHomeURL,
          environment: fixedNowEnvironment
        )
          .utf8
      )
    )
    expectNoDifference(seeded.event, "seed")
    expectNoDifference(seeded.reminders.map(\.title), ["Groceries", "Haircut"])
    expectNoDifference(seeded.reminders.map(\.isFlagged), [false, true])
    expectNoDifference(seeded.reminders.map(\.dueDate), [
      InstantTimestamp(milliseconds: fixedNow.milliseconds + 24 * 60 * 60 * 1000),
      InstantTimestamp(milliseconds: fixedNow.milliseconds + 3 * 24 * 60 * 60 * 1000),
    ])
    expectNoDifference(seeded.reminders.map(\.priority), [.medium, .high])
    expectNoDifference(
      seeded.stats,
      RemindersStats(allCount: 2, completedCount: 0, flaggedCount: 1, scheduledCount: 2, todayCount: 0)
    )
    expectNoDifference(seeded.tags.map(\.title), ["personal", "shopping"])
    expectNoDifference(
      seeded.reminderTags,
      [
        ReminderTagLinkRecord(reminderID: seeded.reminders[0].id, tagID: "shopping"),
        ReminderTagLinkRecord(reminderID: seeded.reminders[1].id, tagID: "personal"),
      ]
    )

    let seedSearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "search", "shop", "--tag", "shopping", "--json"], homeURL: seedHomeURL)
          .utf8
      )
    )
    expectNoDifference(seedSearch.event, "search")
    expectNoDifference(seedSearch.reminders.map(\.title), ["Groceries"])
    expectNoDifference(seedSearch.reminderTags.map(\.tagID), ["shopping"])

    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let fixedDate = Date(timeIntervalSince1970: Double(fixedNow.milliseconds) / 1000)
    let todayStart = calendar.startOfDay(for: fixedDate)
    let dueDateFormatter = DateFormatter()
    dueDateFormatter.calendar = calendar
    dueDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dueDateFormatter.timeZone = calendar.timeZone
    dueDateFormatter.dateFormat = "yyyy-MM-dd"
    let dueDateString = dueDateFormatter.string(from: todayStart)
    let dueDateTimestamp = InstantTimestamp(
      milliseconds: Int64((todayStart.timeIntervalSince1970 * 1000).rounded())
    )

    let addedList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add-list", "Family", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let listID = try #require(addedList.changedID)
    let addedTake = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reminders", "add", listID, "Take out trash",
            "--notes", "Bins at the curb",
            "--due-date", dueDateString,
            "--priority", "high",
            "--flagged",
            "--json",
          ],
          homeURL: homeURL
        )
          .utf8
      )
    )
    let takeID = try #require(addedTake.changedID)
    expectNoDifference(addedTake.reminders.map(\.isFlagged), [true])
    expectNoDifference(addedTake.reminders.map(\.priority), [.high])
    expectNoDifference(addedTake.reminders.map(\.dueDate), [dueDateTimestamp])
    let addedWalk = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add", listID, "Take a walk", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let walkID = try #require(addedWalk.changedID)
    _ = try runCLI(["examples", "reminders", "complete", walkID, "--json"], homeURL: homeURL)

    let stats = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "stats", "--json"],
          homeURL: homeURL,
          environment: fixedNowEnvironment
        ).utf8
      )
    )
    expectNoDifference(stats.event, "stats")
    expectNoDifference(
      stats.stats,
      RemindersStats(allCount: 1, completedCount: 1, flaggedCount: 1, scheduledCount: 1, todayCount: 1)
    )

    let badDueDate = try runCLIResult(
      ["examples", "reminders", "add", listID, "Bad date", "--due-date", "not-a-date", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badDueDate.status, 64)
    #expect(badDueDate.error.contains("Invalid due date"))

    let badPriority = try runCLIResult(
      ["examples", "reminders", "add", listID, "Bad priority", "--priority", "urgent", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badPriority.status, 64)
    #expect(badPriority.error.contains("Usage: instant-swift-data examples reminders add"))

    let taggedTake = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "add-tag", takeID, "#kids", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(taggedTake.event, "add-tag")
    expectNoDifference(taggedTake.tags.map(\.title), ["kids"])
    expectNoDifference(taggedTake.reminderTags, [
      ReminderTagLinkRecord(reminderID: takeID, tagID: "kids")
    ])

    _ = try runCLI(["examples", "reminders", "add-tag", walkID, "social", "--json"], homeURL: homeURL)
    let incompleteSearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "search", "Take", "--tag", "kids", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(incompleteSearch.event, "search")
    expectNoDifference(incompleteSearch.reminders.map(\.id), [takeID])
    expectNoDifference(incompleteSearch.reminderTags, [
      ReminderTagLinkRecord(reminderID: takeID, tagID: "kids")
    ])

    let flaggedList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "list", "--flagged", "--priority", "high", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(flaggedList.reminders.map(\.id), [takeID])

    let scheduledList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "list", "--scheduled", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(scheduledList.reminders.map(\.id), [takeID])

    let todayList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "list", "--today", "--json"],
          homeURL: homeURL,
          environment: fixedNowEnvironment
        )
          .utf8
      )
    )
    expectNoDifference(todayList.reminders.map(\.id), [takeID])

    let richSearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reminders", "search", "Take",
            "--flagged",
            "--priority", "high",
            "--scheduled",
            "--today",
            "--json",
          ],
          homeURL: homeURL,
          environment: fixedNowEnvironment
        )
          .utf8
      )
    )
    expectNoDifference(richSearch.reminders.map(\.id), [takeID])

    let humanRichList = try runCLI(
      ["examples", "reminders", "list", "--flagged", "--priority", "high"],
      homeURL: homeURL
    )
    #expect(humanRichList.contains("due=\(dueDateString)"))
    #expect(humanRichList.contains("priority=high"))
    #expect(humanRichList.contains("notes=\"Bins at the curb\""))

    let wildcardSearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "search", "%", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(wildcardSearch.reminders, [])
    expectNoDifference(wildcardSearch.reminderTags, [])

    let completedSearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "search", "social", "--include-completed", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(completedSearch.reminders.map(\.id), [walkID])
    expectNoDifference(completedSearch.reminders.map(\.isCompleted), [true])

    let editedTake = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reminders", "update", takeID, "Take bins out",
            "--notes", "Updated bins",
            "--clear-due-date",
            "--clear-priority",
            "--unflagged",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(editedTake.reminders.map(\.title), ["Take bins out", "Take a walk"])
    expectNoDifference(editedTake.reminders.first?.notes, "Updated bins")
    expectNoDifference(editedTake.reminders.first?.isFlagged, false)
    expectNoDifference(editedTake.reminders.first?.dueDate, nil)
    expectNoDifference(editedTake.reminders.first?.priority, nil)

    let emptyScheduledList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "list", "--scheduled", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(emptyScheduledList.reminders, [])

    let jsonlOutput = try runCLI(["examples", "reminders", "tags", "--jsonl"], homeURL: homeURL)
    let rows = jsonlOutput.split(separator: "\n")
    expectNoDifference(rows.count, 8)
    let evidence = try JSONDecoder().decode(
      CLIRemindersEvidence.self,
      from: Data(try #require(rows.first).utf8)
    )
    expectNoDifference(evidence.event, "tags")
    expectNoDifference(evidence.details.tags.map(\.title), ["kids", "social"])
    expectNoDifference(Set(evidence.details.reminderTags.map(\.tagID)), ["kids", "social"])

    let untaggedTake = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "remove-tag", takeID, "kids", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(untaggedTake.event, "remove-tag")
    expectNoDifference(untaggedTake.reminderTags, [
      ReminderTagLinkRecord(reminderID: walkID, tagID: "social")
    ])

    let emptySearch = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "search", "Take", "--tag", "kids", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(emptySearch.reminders, [])
    expectNoDifference(emptySearch.reminderTags, [])

    let badDeleteCompleted = try runCLIResult(
      ["examples", "reminders", "delete-completed", "--list-id", "missing-list", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badDeleteCompleted.status, 66)
    #expect(badDeleteCompleted.error.contains("Reminder list not found"))

    let deletedTake = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "delete", takeID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deletedTake.event, "delete")
    expectNoDifference(deletedTake.changedID, takeID)
    expectNoDifference(deletedTake.reminders.map(\.id), [walkID])
    expectNoDifference(deletedTake.reminderTags, [
      ReminderTagLinkRecord(reminderID: walkID, tagID: "social")
    ])

    let deletedCompleted = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "delete-completed", "--list-id", listID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deletedCompleted.event, "delete-completed")
    expectNoDifference(deletedCompleted.changedID, walkID)
    expectNoDifference(deletedCompleted.reminders, [])
    expectNoDifference(deletedCompleted.reminderTags, [])

    let tagsAfterReminderDeletes = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "tags", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(tagsAfterReminderDeletes.tags.map(\.title), ["kids", "social"])
    expectNoDifference(tagsAfterReminderDeletes.reminderTags, [])

    let deletedList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(["examples", "reminders", "delete-list", listID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deletedList.event, "delete-list")
    expectNoDifference(deletedList.changedID, listID)
    expectNoDifference(deletedList.lists, [])
    expectNoDifference(deletedList.reminders, [])
  }

  @Test
  func cliRemindersFilteredListKeepsGlobalSummaryCounts() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let environment = ["INSTANT_SWIFT_DATA_NOW": "1700000000000"]
    let addedList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "add-list", "Family", "--json"],
          homeURL: homeURL,
          environment: environment
        ).utf8
      )
    )
    let listID = try #require(addedList.changedID)
    let scheduled = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reminders", "add", listID, "Pack lunch",
            "--due-date", "2023-11-14",
            "--priority", "high",
            "--json",
          ],
          homeURL: homeURL,
          environment: environment
        ).utf8
      )
    )
    let scheduledID = try #require(scheduled.changedID)
    _ = try runCLI(
      ["examples", "reminders", "add", listID, "Read book", "--json"],
      homeURL: homeURL,
      environment: environment
    )

    let scheduledList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "list", "--scheduled", "--json"],
          homeURL: homeURL,
          environment: environment
        ).utf8
      )
    )
    expectNoDifference(scheduledList.reminders.map(\.id), [scheduledID])
    expectNoDifference(scheduledList.lists.map(\.reminderCount), [2])

    let priorityList = try JSONDecoder().decode(
      CLIRemindersOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reminders", "list", "--priority", "high", "--json"],
          homeURL: homeURL,
          environment: environment
        ).utf8
      )
    )
    expectNoDifference(priorityList.reminders.map(\.id), [scheduledID])
    expectNoDifference(priorityList.lists.map(\.reminderCount), [2])
  }

  @Test
  func cliSyncUpsDemoPersistsEditsMeetingsAndCascadeDeletes() async throws {
    let seedHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: seedHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: seedHomeURL) }

    let seeded = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "seed", "--json"], homeURL: seedHomeURL)
          .utf8
      )
    )
    expectNoDifference(seeded.event, "seed")
    expectNoDifference(seeded.syncUps.map(\.syncUp.title), ["Design", "Engineering", "Product"])
    expectNoDifference(seeded.syncUps.map(\.syncUp.seconds), [60, 600, 1_800])
    expectNoDifference(seeded.syncUps.map(\.attendeeCount), [6, 2, 2])
    expectNoDifference(seeded.syncUps.map(\.meetingCount), [1, 0, 0])
    expectNoDifference(seeded.attendees.count, 10)
    expectNoDifference(seeded.meetings.count, 1)
    #expect(seeded.meetings.first?.transcript.contains("Lorem ipsum dolor sit amet") == true)

    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let added = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "sync-ups", "add", "Design",
            "--seconds", "900",
            "--theme", "appOrange",
            "--attendee", "Blob",
            "--attendee", "Blob Jr",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(added.event, "add")
    expectNoDifference(added.transport, "not-implemented-local-cache-only")
    expectNoDifference(added.syncUps.map(\.syncUp.title), ["Design"])
    expectNoDifference(added.syncUps.map(\.attendeeCount), [2])
    expectNoDifference(added.attendees.map(\.name), ["Blob", "Blob Jr"])
    expectNoDifference(added.pendingMutationCount, 1)
    let syncUpID = try #require(added.changedID)

    let other = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "sync-ups", "add", "Engineering",
            "--seconds", "600",
            "--theme", "periwinkle",
            "--attendee", "Blob Sr",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(other.syncUps.map(\.syncUp.title), ["Engineering"])

    let detail = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "detail", syncUpID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(detail.event, "detail")
    expectNoDifference(detail.syncUps.map(\.syncUp.id), [syncUpID])
    expectNoDifference(detail.syncUps.map(\.syncUp.title), ["Design"])
    expectNoDifference(detail.attendees.map(\.name), ["Blob", "Blob Jr"])
    expectNoDifference(detail.meetings, [])

    let scopedList = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "list", "--sync-up-id", syncUpID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(scopedList.event, "list")
    expectNoDifference(scopedList.syncUps.map(\.syncUp.id), [syncUpID])
    expectNoDifference(scopedList.syncUps.map(\.syncUp.title), ["Design"])
    expectNoDifference(scopedList.attendees.map(\.name), ["Blob", "Blob Jr"])
    expectNoDifference(scopedList.meetings, [])

    let deletedAttendeeID = try #require(scopedList.attendees.first(where: { $0.name == "Blob Jr" })?.id)
    let deletedAttendee = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "delete-attendee", deletedAttendeeID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deletedAttendee.event, "delete-attendee")
    expectNoDifference(deletedAttendee.changedID, deletedAttendeeID)
    expectNoDifference(deletedAttendee.syncUps.map(\.attendeeCount), [1, 1])
    expectNoDifference(deletedAttendee.attendees.map(\.name), ["Blob", "Blob Sr"])

    let addedAttendee = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "add-attendee", syncUpID, "Blob Jr", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(addedAttendee.event, "add-attendee")
    #expect(addedAttendee.changedID != nil)
    expectNoDifference(addedAttendee.syncUps.map(\.attendeeCount), [2])
    expectNoDifference(addedAttendee.attendees.map(\.name), ["Blob", "Blob Jr"])

    let edited = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "sync-ups", "edit", syncUpID,
            "--title", "Design Review",
            "--seconds", "1200",
            "--theme", "periwinkle",
            "--attendee", "Blob",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(edited.event, "edit")
    expectNoDifference(edited.syncUps.map(\.syncUp.title), ["Design Review"])
    expectNoDifference(edited.syncUps.map(\.syncUp.seconds), [1_200])
    expectNoDifference(edited.syncUps.map(\.syncUp.theme), [.periwinkle])
    expectNoDifference(edited.syncUps.map(\.attendeeCount), [1])
    expectNoDifference(edited.attendees.map(\.name), ["Blob"])
    let onlyAttendeeID = try #require(edited.attendees.first?.id)

    let replacedLastAttendee = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "delete-attendee", onlyAttendeeID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(replacedLastAttendee.event, "delete-attendee")
    expectNoDifference(replacedLastAttendee.changedID, onlyAttendeeID)
    expectNoDifference(replacedLastAttendee.syncUps.map(\.attendeeCount), [1, 1])
    let otherSyncUpID = try #require(other.changedID)
    expectNoDifference(replacedLastAttendee.attendees.map(\.name), ["", "Blob Sr"])
    expectNoDifference(replacedLastAttendee.attendees.map(\.syncUpID), [syncUpID, otherSyncUpID])

    let recorded = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "sync-ups", "record", syncUpID,
            "--transcript", "Reviewed launch risks.",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(recorded.event, "record")
    expectNoDifference(recorded.syncUps.map(\.meetingCount), [1])
    expectNoDifference(recorded.meetings.map(\.transcript), ["Reviewed launch risks."])
    let meetingID = try #require(recorded.changedID)

    let jsonlOutput = try runCLI(["examples", "sync-ups", "list", "--jsonl"], homeURL: homeURL)
    let rows = jsonlOutput.split(separator: "\n")
    expectNoDifference(rows.count, 6)
    let evidence = try JSONDecoder().decode(
      CLISyncUpsEvidence.self,
      from: Data(try #require(rows.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.examples.sync-ups")
    expectNoDifference(evidence.event, "list")
    expectNoDifference(evidence.details.syncUps.map(\.meetingCount), [1, 0])

    let deletedMeeting = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "delete-meeting", meetingID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deletedMeeting.event, "delete-meeting")
    expectNoDifference(deletedMeeting.meetings, [])
    expectNoDifference(deletedMeeting.syncUps.map(\.meetingCount), [0, 0])

    let deleted = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "delete", syncUpID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deleted.event, "delete")
    expectNoDifference(deleted.syncUps.map(\.syncUp.title), ["Engineering"])
    expectNoDifference(deleted.attendees.map(\.name), ["Blob Sr"])
    expectNoDifference(deleted.meetings, [])

    let emptyHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: emptyHomeURL) }
    do {
      let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
      let emptyRuntime = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "cli-cache-test",
          persistenceURL: emptyHomeURL.appendingPathComponent("state.sqlite"),
          initialAttributes: SyncUpsExample.attributes,
          now: { timestamp }
        )
      )
      try await emptyRuntime.transact(
        InstantStoreTransaction(
          id: "tx-empty-sync-up",
          operations: SyncUpsExample.createSyncUpOperations(
            id: "empty-sync-up",
            title: "Empty",
            seconds: 300,
            theme: .bubblegum,
            updatedAt: timestamp,
            transactionID: "tx-empty-sync-up"
          )
        ),
        createdAt: timestamp,
        source: "cli.test.sync-ups.empty"
      )
    }

    let rejectedRecord = try runCLIResult(
      ["examples", "sync-ups", "record", "empty-sync-up", "--transcript", "No attendees", "--json"],
      homeURL: emptyHomeURL
    )
    expectNoDifference(rejectedRecord.status, 66)
    #expect(rejectedRecord.error.contains("without at least one attendee"))
  }

  @Test
  func cliSyncUpsRecordDemoUsesLocalSpeechAndSoundDependencies() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let added = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "sync-ups", "add", "Tiny Standup",
            "--seconds", "2",
            "--theme", "appOrange",
            "--attendee", "Blob",
            "--attendee", "Blob Jr",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    let syncUpID = try #require(added.changedID)

    let recorded = try JSONDecoder().decode(
      CLISyncUpsOutput.self,
      from: Data(
        try runCLI(["examples", "sync-ups", "record-demo", syncUpID, "--json"], homeURL: homeURL)
          .utf8
      )
    )

    let recording = try #require(recorded.recording)
    expectNoDifference(recorded.event, "record-demo")
    expectNoDifference(recorded.changedID, recording.meetingID)
    expectNoDifference(recorded.syncUps.map(\.meetingCount), [1])
    expectNoDifference(recorded.meetings.map(\.transcript), ["Reviewed launch risks. Final notes."])
    expectNoDifference(recording.authorizationStatus, .authorized)
    expectNoDifference(recording.loadedSoundEffectFileName, "ding.wav")
    expectNoDifference(recording.speechResultCount, 2)
    expectNoDifference(recording.soundEffectPlayCount, 1)
    expectNoDifference(recording.secondsElapsed, 2)
    expectNoDifference(recording.speakerIndex, 1)
    expectNoDifference(recording.currentSpeakerName, "Blob Jr")
    expectNoDifference(recording.isDismissed, true)

    let jsonlOutput = try runCLI(["examples", "sync-ups", "record-demo", syncUpID, "--jsonl"], homeURL: homeURL)
    let rows = jsonlOutput.split(separator: "\n")
    let evidence = try JSONDecoder().decode(
      CLISyncUpsEvidence.self,
      from: Data(try #require(rows.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.examples.sync-ups")
    expectNoDifference(evidence.event, "record-demo")
    expectNoDifference(evidence.details.recording?.speechResultCount, 2)
    expectNoDifference(evidence.details.recording?.soundEffectPlayCount, 1)
    expectNoDifference(evidence.details.syncUps.map(\.meetingCount), [2])
  }

  @Test
  func cliCacheInspectIncludesPlanAwareQuerySummaries() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "cli open", "--json"], homeURL: homeURL)
    let completedAddOutput = try runCLI(
      ["examples", "todos", "add", "cli completed", "--json"],
      homeURL: homeURL
    )
    let completedAdd = try JSONDecoder().decode(CLIAddOutput.self, from: Data(completedAddOutput.utf8))
    let completedID = try #require(completedAdd.changedID)
    _ = try runCLI(["examples", "todos", "complete", completedID, "--json"], homeURL: homeURL)
    _ = try runCLI(
      ["examples", "todos", "list", "--completed", "false", "--json"],
      homeURL: homeURL
    )
    _ = try runCLI(
      ["examples", "todos", "list", "--completed", "true", "--json"],
      homeURL: homeURL
    )

    let cacheOutput = try runCLI(["cache", "inspect", "--json"], homeURL: homeURL)
    let cache = try JSONDecoder().decode(CLICacheInspectOutput.self, from: Data(cacheOutput.utf8))
    let summaries = Set(cache.queries.map(\.stableSummary))

    expectNoDifference(cache.queryCacheCount, 3)
    expectNoDifference(
      summaries,
      [
        CLICacheQueryStableSummary(
          queryID: "examples.todos.list",
          namespace: "todos",
          resultCount: 2
        ),
        CLICacheQueryStableSummary(
          queryID: "examples.todos.list.completed-false",
          namespace: "todos",
          resultCount: 1
        ),
        CLICacheQueryStableSummary(
          queryID: "examples.todos.list.completed-true",
          namespace: "todos",
          resultCount: 1
        ),
      ]
    )
    #expect(cache.queries.allSatisfy { $0.cacheKey.hasPrefix("plan:") })

    let jsonlOutput = try runCLI(["cache", "inspect", "--jsonl"], homeURL: homeURL)
    let summaryLine = try #require(jsonlOutput.split(separator: "\n").first)
    let evidence = try JSONDecoder().decode(
      CLICacheInspectEvidence.self,
      from: Data(summaryLine.utf8)
    )

    expectNoDifference(evidence.event, "summary")
    expectNoDifference(Set(evidence.details.queries.map(\.stableSummary)), summaries)

    let attributes = try JSONDecoder().decode(
      CLICacheAttributesOutput.self,
      from: Data(try runCLI(["cache", "attributes", "todos", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(attributes.namespace, "todos")
    expectNoDifference(attributes.attributeCount, 4)
    expectNoDifference(attributes.attributes.map(\.name), ["createdAt", "id", "isCompleted", "text"])
    let allAttributes = try JSONDecoder().decode(
      CLICacheAttributesOutput.self,
      from: Data(try runCLI(["cache", "attributes", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(allAttributes.namespace, nil)
    #expect(allAttributes.attributeCount >= attributes.attributeCount)
    #expect(Set(allAttributes.attributes.map(\.id)).isSuperset(of: Set(attributes.attributes.map(\.id))))

    let attributesJSONL = try runCLI(["cache", "attributes", "todos", "--jsonl"], homeURL: homeURL)
    let attributeLines = attributesJSONL.split(separator: "\n")
    expectNoDifference(attributeLines.count, 5)
    let attributesEvidence = try JSONDecoder().decode(
      CLICacheAttributesEvidence.self,
      from: Data(try #require(attributeLines.first).utf8)
    )
    expectNoDifference(attributesEvidence.caseID, "cli.cache.attributes")
    expectNoDifference(attributesEvidence.event, "summary")
    expectNoDifference(attributesEvidence.details.attributes.map(\.id), attributes.attributes.map(\.id))
    let attributeRows = try attributeLines.dropFirst().map {
      try JSONDecoder().decode(CLICacheAttributeEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(attributeRows.map(\.event), Array(repeating: "attribute", count: 4))
    expectNoDifference(attributeRows.map(\.details.id), attributes.attributes.map(\.id))

    let triples = try JSONDecoder().decode(
      CLICacheTriplesOutput.self,
      from: Data(try runCLI(["cache", "triples", "todos", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(triples.namespace, "todos")
    expectNoDifference(triples.tripleCount, 8)
    expectNoDifference(
      Set(triples.triples.map(\.attributeID)),
      Set(["todos/createdAt", "todos/id", "todos/isCompleted", "todos/text"])
    )
    let allTriples = try JSONDecoder().decode(
      CLICacheTriplesOutput.self,
      from: Data(try runCLI(["cache", "triples", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(allTriples.namespace, nil)
    #expect(allTriples.tripleCount >= triples.tripleCount)
    #expect(Set(allTriples.triples).isSuperset(of: Set(triples.triples)))

    let triplesJSONL = try runCLI(["cache", "triples", "todos", "--jsonl"], homeURL: homeURL)
    let tripleLines = triplesJSONL.split(separator: "\n")
    expectNoDifference(tripleLines.count, 9)
    let triplesEvidence = try JSONDecoder().decode(
      CLICacheTriplesEvidence.self,
      from: Data(try #require(tripleLines.first).utf8)
    )
    expectNoDifference(triplesEvidence.caseID, "cli.cache.triples")
    expectNoDifference(triplesEvidence.event, "summary")
    expectNoDifference(triplesEvidence.details.triples.map(\.attributeID), triples.triples.map(\.attributeID))
    let tripleRows = try tripleLines.dropFirst().map {
      try JSONDecoder().decode(CLICacheTripleEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(tripleRows.map(\.event), Array(repeating: "triple", count: 8))
    expectNoDifference(tripleRows.map(\.details.entityID), triples.triples.map(\.entityID))

    let humanAttributes = try runCLI(["cache", "attributes", "todos"], homeURL: homeURL)
    #expect(humanAttributes.contains("todos/text namespace=todos name=text type=string"))
    let malformed = try runCLIResult(["cache", "triples", "bad/namespace", "--json"], homeURL: homeURL)
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("namespace must not be empty"))
  }

  @Test
  func cliTodoWatchEmitsFiniteJsonLEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "watch open", "--json"], homeURL: homeURL)
    let completedAddOutput = try runCLI(
      ["examples", "todos", "add", "watch completed", "--json"],
      homeURL: homeURL
    )
    let completedAdd = try JSONDecoder().decode(CLIAddOutput.self, from: Data(completedAddOutput.utf8))
    let completedID = try #require(completedAdd.changedID)
    _ = try runCLI(["examples", "todos", "complete", completedID, "--json"], homeURL: homeURL)

    let watchOutput = try runCLI(
      ["examples", "todos", "watch", "--events", "1", "--completed", "false", "--jsonl"],
      homeURL: homeURL
    )
    let lines = watchOutput.split(separator: "\n")
    expectNoDifference(lines.count, 1)
    let line = try #require(lines.first)
    let evidence = try JSONDecoder().decode(
      CLITodoWatchEvidence.self,
      from: Data(line.utf8)
    )

    expectNoDifference(evidence.event, "watch")
    expectNoDifference(evidence.caseID, "cli.examples.todos.watch")
    expectNoDifference(evidence.side, "swift")
    expectNoDifference(evidence.ok, true)
    expectNoDifference(evidence.details.queryID, "examples.todos.list.completed-false")
    #expect(evidence.details.cacheKey.hasPrefix("plan:"))
    expectNoDifference(evidence.details.emissionIndex, 0)
    expectNoDifference(evidence.details.sequence, 0)
    expectNoDifference(evidence.details.todos.map(\.text), ["watch open"])
    expectNoDifference(evidence.details.pendingMutationCount, 3)

    let cache = try JSONDecoder().decode(
      CLICacheInspectOutput.self,
      from: Data(try runCLI(["cache", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(
      Set(cache.queries.map(\.stableSummary)),
      [
        CLICacheQueryStableSummary(
          queryID: "examples.todos.list",
          namespace: "todos",
          resultCount: 2
        ),
        CLICacheQueryStableSummary(
          queryID: "examples.todos.list.completed-false",
          namespace: "todos",
          resultCount: 1
        ),
      ]
    )

    let jsonWatch = try JSONDecoder().decode(
      CLITodoWatchOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "watch", "--events", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(jsonWatch.event, "watch")
    expectNoDifference(jsonWatch.requestedEventCount, 1)
    expectNoDifference(jsonWatch.emittedEventCount, 1)
    expectNoDifference(jsonWatch.emissions.map(\.todos.count), [2])

    _ = try runCLI(["connection", "close", "--json"], homeURL: homeURL)
    let closedWatchOutput = try runCLI(
      ["examples", "todos", "watch", "--events", "1", "--completed", "false", "--jsonl"],
      homeURL: homeURL
    )
    let closedWatchLines = closedWatchOutput.split(separator: "\n")
    expectNoDifference(closedWatchLines.count, 1)
    let closedWatch = try JSONDecoder().decode(
      CLITodoWatchEvidence.self,
      from: Data(try #require(closedWatchLines.first).utf8)
    )
    expectNoDifference(closedWatch.event, "watch")
    expectNoDifference(closedWatch.details.todos.map(\.text), ["watch open"])
    expectNoDifference(closedWatch.details.pendingMutationCount, 3)
    _ = try runCLI(["connection", "connect", "--json"], homeURL: homeURL)

    let invalidEvents = try runCLIResult(
      ["examples", "todos", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidEvents.status == 64)
    #expect(invalidEvents.error.contains("watch --events 1"))
  }

  @Test
  func cliAuthWatchEmitsFiniteAuthState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedOutJSONL = try runCLI(["auth", "watch", "--events", "1", "--jsonl"], homeURL: homeURL)
    let signedOutLines = signedOutJSONL.split(separator: "\n")
    expectNoDifference(signedOutLines.count, 1)
    let signedOutEvidence = try JSONDecoder().decode(
      CLIAuthWatchEvidence.self,
      from: Data(try #require(signedOutLines.first).utf8)
    )
    expectNoDifference(signedOutEvidence.caseID, "cli.auth.watch")
    expectNoDifference(signedOutEvidence.side, "swift")
    expectNoDifference(signedOutEvidence.event, "watch")
    expectNoDifference(signedOutEvidence.ok, true)
    expectNoDifference(signedOutEvidence.details.event, "watch")
    expectNoDifference(signedOutEvidence.details.isSignedIn, false)
    expectNoDifference(signedOutEvidence.details.userID, nil)

    let token = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(
          ["auth", "token", "refresh-token", "--user-id", "watch-user", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(token.event, "token")
    expectNoDifference(token.isSignedIn, true)
    expectNoDifference(token.userID, "watch-user")
    expectNoDifference(token.hasRefreshToken, true)

    let signedInWatch = try JSONDecoder().decode(
      CLIAuthWatchOutput.self,
      from: Data(
        try runCLI(["auth", "watch", "--events", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(signedInWatch.event, "watch")
    expectNoDifference(signedInWatch.requestedEventCount, 1)
    expectNoDifference(signedInWatch.emittedEventCount, 1)
    expectNoDifference(signedInWatch.emissions.map(\.userID), ["watch-user"])
    expectNoDifference(signedInWatch.emissions.map(\.isGuest), [false])
    expectNoDifference(signedInWatch.emissions.map(\.hasRefreshToken), [true])

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutWatch = try JSONDecoder().decode(
      CLIAuthWatchOutput.self,
      from: Data(
        try runCLI(["auth", "watch", "--events", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(signedOutWatch.emissions.map(\.isSignedIn), [false])

    let invalidEvents = try runCLIResult(
      ["auth", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidEvents.status == 64)
    #expect(invalidEvents.error.contains("auth watch --events 1"))
  }

  @Test
  func cliAuthRecipeSendsVerifiesWatchesAndSignsOutAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedOut = try JSONDecoder().decode(
      CLIAuthRecipeOutput.self,
      from: Data(
        try runCLI(["examples", "auth", "status", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(signedOut.event, "status")
    expectNoDifference(signedOut.recipeSlug, "auth")
    expectNoDifference(signedOut.isLoginVisible, true)
    expectNoDifference(signedOut.isEmailEntryVisible, true)
    expectNoDifference(signedOut.isCodeEntryVisible, false)
    expectNoDifference(signedOut.isDashboardVisible, false)
    expectNoDifference(signedOut.isSignedIn, false)
    expectNoDifference(signedOut.userEmail, nil)

    let challenge = try JSONDecoder().decode(
      CLIAuthRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "auth", "send-code", "User@Example.com", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(challenge.event, "send-code")
    expectNoDifference(challenge.isLoginVisible, true)
    expectNoDifference(challenge.isEmailEntryVisible, false)
    expectNoDifference(challenge.isCodeEntryVisible, true)
    expectNoDifference(challenge.isDashboardVisible, false)
    expectNoDifference(challenge.sentEmail, "user@example.com")
    let localVerificationCode = try #require(challenge.localVerificationCode)
    expectNoDifference(localVerificationCode.count, 6)

    let verified = try JSONDecoder().decode(
      CLIAuthRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "auth", "verify-code", " user@example.com ",
            " \(localVerificationCode) ", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(verified.event, "verify-code")
    expectNoDifference(verified.isLoginVisible, false)
    expectNoDifference(verified.isEmailEntryVisible, false)
    expectNoDifference(verified.isCodeEntryVisible, false)
    expectNoDifference(verified.isDashboardVisible, true)
    expectNoDifference(verified.isSignedIn, true)
    expectNoDifference(verified.userID, "email:user@example.com")
    expectNoDifference(verified.userEmail, "user@example.com")
    expectNoDifference(verified.hasRefreshToken, true)

    let signedInSend = try runCLIResult(
      ["examples", "auth", "send-code", "another@example.com", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedInSend.status, 65)
    #expect(signedInSend.error.contains("Auth recipe send-code is only available while signed out."))
    let signedInVerify = try runCLIResult(
      ["examples", "auth", "verify-code", "another@example.com", "123456", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedInVerify.status, 65)
    #expect(signedInVerify.error.contains("Auth recipe verify-code is only available while signed out."))

    let watchJSONL = try runCLI(
      ["examples", "auth", "watch", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 1)
    let watchEvidence = try JSONDecoder().decode(
      CLIAuthRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watchEvidence.caseID, "cli.examples.auth.watch")
    expectNoDifference(watchEvidence.side, "swift")
    expectNoDifference(watchEvidence.event, "watch")
    expectNoDifference(watchEvidence.ok, true)
    expectNoDifference(watchEvidence.details.userEmail, "user@example.com")
    expectNoDifference(watchEvidence.details.isDashboardVisible, true)

    let signedOutAgain = try JSONDecoder().decode(
      CLIAuthRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "auth", "sign-out", "--skip-token-invalidation", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(signedOutAgain.event, "sign-out")
    expectNoDifference(signedOutAgain.isLoginVisible, true)
    expectNoDifference(signedOutAgain.isEmailEntryVisible, true)
    expectNoDifference(signedOutAgain.isCodeEntryVisible, false)
    expectNoDifference(signedOutAgain.isDashboardVisible, false)
    expectNoDifference(signedOutAgain.isSignedIn, false)

    let malformedVerify = try runCLIResult(
      ["examples", "auth", "verify-code", "user@example.com", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(malformedVerify.status, 64)
    #expect(malformedVerify.error.contains("examples auth verify-code"))
  }

  @Test
  func cliAppBuilderGeneratesListsUpdatesAndResetsBuildsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let missingAuth = try runCLIResult(
      ["examples", "app-builder", "generate", "Build a Tic Tac Toe game", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingAuth.status, 65)
    #expect(missingAuth.error.contains("App-builder requires a signed-in email user."))

    let challenge = try JSONDecoder().decode(
      CLIAuthRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "auth", "send-code", "builder@example.com", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    let code = try #require(challenge.localVerificationCode)
    _ = try runCLI(
      ["examples", "auth", "verify-code", "builder@example.com", code, "--json"],
      homeURL: homeURL
    )

    let generated = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "app-builder", "generate", "Build a Tic Tac Toe game",
            "--org-id", "org-terminal", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(generated.event, "generate")
    expectNoDifference(generated.authUserID, "email:builder@example.com")
    expectNoDifference(generated.authUserEmail, "builder@example.com")
    expectNoDifference(generated.buildCount, 1)
    expectNoDifference(generated.previewableBuildCount, 1)
    expectNoDifference(generated.generationEvents.map(\.event), ["create", "chunk", "chunk", "finish"])
    let build = try #require(generated.selectedBuild)
    expectNoDifference(build.title, "Build a Tic Tac Toe game")
    expectNoDifference(build.ownerID, "email:builder@example.com")
    expectNoDifference(build.isPreviewable, true)
    #expect(build.instantAppID.hasPrefix("local-platform-"))
    #expect(build.code.contains(build.instantAppID))
    #expect(build.reasoning?.contains("Create a compact Swift-friendly preview") == true)

    let listed = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(["examples", "app-builder", "list", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(listed.event, "list")
    expectNoDifference(listed.builds.map(\.id), [build.id])
    expectNoDifference(listed.selectedBuild, nil)

    let appended = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "app-builder", "append", build.id, "--code", "\n// patched",
            "--reasoning", "\nPolished after preview.", "--previewable", "false", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    let appendedBuild = try #require(appended.selectedBuild)
    #expect(appendedBuild.code.contains("// patched"))
    #expect(appendedBuild.reasoning?.contains("Polished after preview.") == true)
    expectNoDifference(appendedBuild.isPreviewable, false)

    let finished = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(["examples", "app-builder", "finish", build.id, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(finished.selectedBuild?.isPreviewable, true)

    let shown = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(["examples", "app-builder", "show", build.id, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(shown.event, "show")
    expectNoDifference(shown.selectedBuild?.id, build.id)
    expectNoDifference(shown.selectedBuild?.isPreviewable, true)

    let jsonl = try runCLI(
      ["examples", "app-builder", "generate", "Build a notes app", "--jsonl"],
      homeURL: homeURL
    )
    let lines = jsonl.split(separator: "\n")
    #expect(lines.count >= 5)
    let evidence = try JSONDecoder().decode(
      CLIAppBuilderEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.examples.app-builder")
    expectNoDifference(evidence.event, "generate")
    expectNoDifference(evidence.ok, true)
    expectNoDifference(evidence.details.generationEvents.map(\.event), ["create", "chunk", "chunk", "finish"])

    let reset = try JSONDecoder().decode(
      CLIAppBuilderOutput.self,
      from: Data(
        try runCLI(["examples", "app-builder", "reset", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.builds, [])
    expectNoDifference(reset.buildCount, 0)

    let malformedAppend = try runCLIResult(
      ["examples", "app-builder", "append", "build-1", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(malformedAppend.status, 64)
    #expect(malformedAppend.error.contains("examples app-builder append"))
  }

  @Test
  func cliAuthSignOutSupportsTokenInvalidationOption() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "token-user", "--json"],
      homeURL: homeURL
    )
    let skipped = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(["auth", "sign-out", "--skip-token-invalidation", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(skipped.event, "sign-out")
    expectNoDifference(skipped.isSignedIn, false)
    expectNoDifference(skipped.hasRefreshToken, false)

    let show = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(try runCLI(["auth", "show", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(show.isSignedIn, false)

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "token-user", "--json"],
      homeURL: homeURL
    )
    let noInvalidateAlias = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(["auth", "sign-out", "--no-invalidate-token", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(noInvalidateAlias.event, "sign-out")
    expectNoDifference(noInvalidateAlias.isSignedIn, false)

    let malformed = try runCLIResult(
      ["auth", "sign-out", "--unknown", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("auth sign-out"))
  }

  @Test
  func cliAuthIDTokenSignInPersistsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedIn = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(
          ["auth", "id-token", "google-ios", "local-jwt", "--nonce", "nonce-1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(signedIn.event, "id-token")
    expectNoDifference(signedIn.isSignedIn, true)
    expectNoDifference(signedIn.isGuest, false)
    expectNoDifference(signedIn.hasRefreshToken, true)
    #expect(signedIn.userID?.hasPrefix("id-token:google-ios:") == true)

    let show = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(try runCLI(["auth", "show", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(show.userID, signedIn.userID)
    expectNoDifference(show.hasRefreshToken, true)

    let watch = try JSONDecoder().decode(
      CLIAuthWatchOutput.self,
      from: Data(
        try runCLI(["auth", "watch", "--events", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(watch.emissions.map(\.userID), [signedIn.userID])

    let missingToken = try runCLIResult(
      ["auth", "id-token", "google-ios", " ", "--json"],
      homeURL: homeURL
    )
    #expect(missingToken.status == 65)
    #expect(missingToken.error.contains("ID token must not be empty"))

    let malformedNonce = try runCLIResult(
      ["auth", "id-token", "google-ios", "local-jwt", "--nonce", " ", "--json"],
      homeURL: homeURL
    )
    #expect(malformedNonce.status == 64)
    #expect(malformedNonce.error.contains("auth id-token"))
  }

  @Test
  func cliAuthOAuthSignInPersistsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedIn = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(
          ["auth", "oauth", "local-oauth-code", "--code-verifier", "verifier-1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(signedIn.event, "oauth")
    expectNoDifference(signedIn.isSignedIn, true)
    expectNoDifference(signedIn.isGuest, false)
    expectNoDifference(signedIn.hasRefreshToken, true)
    #expect(signedIn.userID?.hasPrefix("oauth:") == true)

    let show = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(try runCLI(["auth", "show", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(show.userID, signedIn.userID)
    expectNoDifference(show.hasRefreshToken, true)

    let watch = try JSONDecoder().decode(
      CLIAuthWatchOutput.self,
      from: Data(
        try runCLI(["auth", "watch", "--events", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(watch.emissions.map(\.userID), [signedIn.userID])

    let noVerifierHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: noVerifierHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: noVerifierHomeURL) }
    let noVerifier = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(["auth", "oauth", "local-oauth-code", "--json"], homeURL: noVerifierHomeURL)
          .utf8
      )
    )
    expectNoDifference(noVerifier.event, "oauth")
    expectNoDifference(noVerifier.isSignedIn, true)
    #expect(noVerifier.userID?.hasPrefix("oauth:") == true)

    let missingCode = try runCLIResult(
      ["auth", "oauth", " ", "--json"],
      homeURL: homeURL
    )
    #expect(missingCode.status == 65)
    #expect(missingCode.error.contains("OAuth authorization code must not be empty"))

    let malformedVerifier = try runCLIResult(
      ["auth", "oauth", "local-oauth-code", "--code-verifier", " ", "--json"],
      homeURL: homeURL
    )
    #expect(malformedVerifier.status == 64)
    #expect(malformedVerifier.error.contains("auth oauth"))
  }

  @Test
  func cliAuthOAuthEndpointCommandsUseConfiguredEndpoints() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let environment = [
      "INSTANT_APP_ID": "oauth-endpoint-app",
      "INSTANT_API_URI": "https://api.example.test/custom",
      "INSTANT_WEBSOCKET_URI": "wss://ws.example.test/runtime/session",
    ]
    let endpoint = try JSONDecoder().decode(
      CLIAuthEndpointOutput.self,
      from: Data(
        try runCLI(
          [
            "auth", "oauth-url", "google-ios",
            "myapp://oauth/callback?state=abc&next=/home", "--json",
          ],
          homeURL: homeURL,
          environment: environment
        ).utf8
      )
    )
    expectNoDifference(endpoint.appID, "oauth-endpoint-app")
    expectNoDifference(endpoint.event, "oauth-url")
    expectNoDifference(endpoint.apiURI, "https://api.example.test/custom")
    expectNoDifference(endpoint.websocketURI, "wss://ws.example.test/runtime/session")
    expectNoDifference(endpoint.issuerURI, "https://api.example.test/custom/runtime/oauth-endpoint-app")
    let authorizationURL = try #require(endpoint.authorizationURL.flatMap(URL.init(string:)))
    let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
    expectNoDifference(components.host, "api.example.test")
    expectNoDifference(components.path, "/custom/runtime/oauth/start")
    let queryItems = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
    expectNoDifference(queryItems["app_id"], "oauth-endpoint-app")
    expectNoDifference(queryItems["client_name"], "google-ios")
    expectNoDifference(
      queryItems["redirect_uri"],
      "myapp://oauth/callback?state=abc&next=/home"
    )

    let issuer = try JSONDecoder().decode(
      CLIAuthEndpointOutput.self,
      from: Data(
        try runCLI(["auth", "issuer", "--json"], homeURL: homeURL, environment: environment)
          .utf8
      )
    )
    expectNoDifference(issuer.event, "issuer")
    expectNoDifference(issuer.authorizationURL, nil)
    expectNoDifference(issuer.issuerURI, "https://api.example.test/custom/runtime/oauth-endpoint-app")

    let jsonl = try runCLI(
      ["auth", "issuer", "--jsonl"],
      homeURL: homeURL,
      environment: environment
    )
    let line = try #require(jsonl.split(separator: "\n").first)
    let evidence = try JSONDecoder().decode(
      CLIAuthEndpointEvidence.self,
      from: Data(line.utf8)
    )
    expectNoDifference(evidence.caseID, "cli.auth.endpoint")
    expectNoDifference(evidence.details.issuerURI, issuer.issuerURI)

    let missingRedirect = try runCLIResult(
      ["auth", "oauth-url", "google-ios", "--json"],
      homeURL: homeURL,
      environment: environment
    )
    #expect(missingRedirect.status == 64)
    #expect(missingRedirect.error.contains("auth oauth-url"))

    let emptyClient = try runCLIResult(
      ["auth", "oauth-url", " ", "myapp://oauth", "--json"],
      homeURL: homeURL,
      environment: environment
    )
    #expect(emptyClient.status == 65)
    #expect(emptyClient.error.contains("OAuth client name must not be empty"))

    let invalidEnvironment = try runCLIResult(
      ["auth", "issuer", "--json"],
      homeURL: homeURL,
      environment: ["INSTANT_API_URI": "https://api.example.test?query=1"]
    )
    #expect(invalidEnvironment.status == 64)
    #expect(invalidEnvironment.error.contains("INSTANT_API_URI"))

    let invalidWebSocketEnvironment = try runCLIResult(
      ["auth", "issuer", "--json"],
      homeURL: homeURL,
      environment: ["INSTANT_WEBSOCKET_URI": "https://ws.example.test/runtime/session"]
    )
    #expect(invalidWebSocketEnvironment.status == 64)
    #expect(invalidWebSocketEnvironment.error.contains("INSTANT_WEBSOCKET_URI"))
  }

  @Test
  func cliTodoCompleteMarksTodoDurably() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let addOutput = try runCLI(
      ["examples", "todos", "add", "complete from cli", "--json"],
      homeURL: homeURL
    )
    let add = try JSONDecoder().decode(CLIAddOutput.self, from: Data(addOutput.utf8))
    let todoID = try #require(add.changedID)

    let malformed = try runCLIResult(
      ["examples", "todos", "complete", todoID, "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("examples todos complete <todo-id>"))

    let afterMalformedComplete = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(afterMalformedComplete.todos.map(\.isCompleted), [false])

    let completeOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "complete", todoID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(completeOutput.event, "complete")
    expectNoDifference(completeOutput.changedID, todoID)
    expectNoDifference(completeOutput.todos.map(\.text), ["complete from cli"])
    expectNoDifference(completeOutput.todos.map(\.isCompleted), [true])
    expectNoDifference(completeOutput.pendingMutationCount, 2)

    let listOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--completed", "true", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(listOutput.todos.map(\.id), [todoID])
    expectNoDifference(listOutput.todos.map(\.isCompleted), [true])

    let missing = try runCLIResult(
      ["examples", "todos", "complete", "missing-todo", "--json"],
      homeURL: homeURL
    )
    #expect(missing.status == 66)
    #expect(missing.error.contains("Todo not found"))
  }

  @Test
  func cliTodoDeleteRemovesTodoFromDurableState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let deleteAddOutput = try runCLI(
      ["examples", "todos", "add", "delete from cli", "--json"],
      homeURL: homeURL
    )
    let deleteAdd = try JSONDecoder().decode(CLIAddOutput.self, from: Data(deleteAddOutput.utf8))
    let deletedID = try #require(deleteAdd.changedID)
    _ = try runCLI(["examples", "todos", "add", "keep from cli", "--json"], homeURL: homeURL)

    let malformed = try runCLIResult(
      ["examples", "todos", "delete", deletedID, "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("examples todos delete <todo-id>"))

    let afterMalformedDelete = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(
      Set(afterMalformedDelete.todos.map(\.text)),
      Set(["delete from cli", "keep from cli"])
    )

    let deleteOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "delete", deletedID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(deleteOutput.event, "delete")
    expectNoDifference(deleteOutput.changedID, deletedID)
    expectNoDifference(deleteOutput.todos.map(\.text), ["keep from cli"])
    expectNoDifference(deleteOutput.pendingMutationCount, 3)

    let listOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(listOutput.todos.map(\.text), ["keep from cli"])

    let missing = try runCLIResult(
      ["examples", "todos", "delete", deletedID, "--json"],
      homeURL: homeURL
    )
    #expect(missing.status == 66)
    #expect(missing.error.contains("Todo not found"))
  }

  @Test
  func cliTodoUpdateChangesDurableText() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let addOutput = try runCLI(
      ["examples", "todos", "add", "draft from cli", "--json"],
      homeURL: homeURL
    )
    let add = try JSONDecoder().decode(CLIAddOutput.self, from: Data(addOutput.utf8))
    let todoID = try #require(add.changedID)

    let malformed = try runCLIResult(
      ["examples", "todos", "update", todoID, "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("examples todos update <todo-id>"))

    let afterMalformedUpdate = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(afterMalformedUpdate.todos.map(\.text), ["draft from cli"])

    let updateOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["examples", "todos", "update", todoID, "polished from cli", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(updateOutput.event, "update")
    expectNoDifference(updateOutput.changedID, todoID)
    expectNoDifference(updateOutput.todos.map(\.text), ["polished from cli"])
    expectNoDifference(updateOutput.pendingMutationCount, 2)

    let listOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(listOutput.todos.map(\.text), ["polished from cli"])

    let missing = try runCLIResult(
      ["examples", "todos", "update", "missing-todo", "new text", "--json"],
      homeURL: homeURL
    )
    #expect(missing.status == 66)
    #expect(missing.error.contains("Todo not found"))
  }

  @Test
  func cliTodoCommandAliasesUseTypedParserDispatch() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let addOutput = try JSONDecoder().decode(
      CLIAddOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "add", "alias from cli", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let todoID = try #require(addOutput.changedID)

    let observeOutput = try runCLI(
      ["examples", "todos", "observe", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let observeLines = observeOutput.split(separator: "\n")
    expectNoDifference(observeLines.count, 1)
    let observeEvidence = try JSONDecoder().decode(
      CLITodoWatchEvidence.self,
      from: Data(try #require(observeLines.first).utf8)
    )
    expectNoDifference(observeEvidence.event, "watch")
    expectNoDifference(observeEvidence.details.todos.map(\.text), ["alias from cli"])

    let editOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["examples", "todos", "edit", todoID, "alias polished", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(editOutput.event, "update")
    expectNoDifference(editOutput.todos.map(\.text), ["alias polished"])

    let removeOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "remove", todoID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(removeOutput.event, "delete")
    expectNoDifference(removeOutput.todos, [])
  }

  @Test
  func cliExamplesWithoutSubcommandPrintsUsageError() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let result = try runCLIResult(["examples"], homeURL: homeURL)

    expectNoDifference(result.status, 64)
    #expect(
      result.error.contains(
        "Usage: instant-swift-data examples <todos|auth|app-builder|todo-links|counters|chat|mobile-chat|microblog|reactions|typing-indicator|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|sync-ups>"
      )
    )
  }

  @Test
  func cliTodoStrictMutationsUseLocalStateWhileConnectionIsClosed() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let add = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "add", "offline draft", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let todoID = try #require(add.changedID)
    _ = try runCLI(["connection", "close", "--json"], homeURL: homeURL)

    let update = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["examples", "todos", "update", todoID, "offline polished", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(update.event, "update")
    expectNoDifference(update.changedID, todoID)
    expectNoDifference(update.todos.map(\.text), ["offline polished"])
    expectNoDifference(update.pendingMutationCount, 2)

    let complete = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "complete", todoID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(complete.event, "complete")
    expectNoDifference(complete.todos.map(\.isCompleted), [true])
    expectNoDifference(complete.pendingMutationCount, 3)

    let delete = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "delete", todoID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(delete.event, "delete")
    expectNoDifference(delete.changedID, todoID)
    expectNoDifference(delete.todos, [])
    expectNoDifference(delete.pendingMutationCount, 4)

    let status = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(status.state, "closed")
    expectNoDifference(status.pendingMutationCount, 4)
    expectNoDifference(status.lastErrorMessage, nil)
  }

  @Test
  func cliTodoSeedAndResetUseDurableLocalState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let seedOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "seed", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(seedOutput.event, "seed")
    expectNoDifference(seedOutput.pendingMutationCount, 1)
    expectNoDifference(
      seedOutput.todos.map { "\($0.text)|\($0.isCompleted)" },
      [
        "Plan the Instant Swift Data demo|true",
        "Run the non-captive terminal workflow|false",
        "Audit the local cache and outbox|false",
      ]
    )

    let planID = try JSONDecoder().decode(
      CLILocalIDOutput.self,
      from: Data(
        try runCLI(["local-id", "get", "examples.todos.seed.plan", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(seedOutput.todos.first?.id, planID.id)

    let localIDs = try JSONDecoder().decode(
      CLILocalIDsOutput.self,
      from: Data(
        try runCLI(["local-id", "list", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(localIDs.transport, "not-implemented-local-cache-only")
    expectNoDifference(localIDs.localIDCount, 3)
    expectNoDifference(
      localIDs.localIDs.map(\.name),
      [
        "examples.todos.seed.audit",
        "examples.todos.seed.plan",
        "examples.todos.seed.terminal",
      ]
    )
    expectNoDifference(
      localIDs.localIDs.first { $0.name == "examples.todos.seed.plan" }?.entityID,
      planID.id
    )

    let localIDJSONL = try runCLI(["local-id", "list", "--jsonl"], homeURL: homeURL)
    let localIDLines = localIDJSONL.split(separator: "\n")
    expectNoDifference(localIDLines.count, 4)
    let localIDSummary = try JSONDecoder().decode(
      CLILocalIDsEvidence.self,
      from: Data(try #require(localIDLines.first).utf8)
    )
    expectNoDifference(localIDSummary.caseID, "cli.local-id.list")
    expectNoDifference(localIDSummary.event, "summary")
    expectNoDifference(localIDSummary.details.localIDCount, 3)
    let localIDRows = try localIDLines.dropFirst().map {
      try JSONDecoder().decode(CLILocalIDRowEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(localIDRows.map(\.caseID), Array(repeating: "cli.local-id.list", count: 3))
    expectNoDifference(localIDRows.map(\.event), Array(repeating: "local-id", count: 3))
    expectNoDifference(localIDRows.map(\.details.name), localIDs.localIDs.map(\.name))

    let localIDHuman = try runCLI(["local-id", "list"], homeURL: homeURL)
    #expect(localIDHuman.contains("examples.todos.seed.plan \(planID.id)"))
    #expect(localIDHuman.contains("transport: not-implemented-local-cache-only"))

    let malformedLocalIDList = try runCLIResult(
      ["local-id", "list", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformedLocalIDList.status == 64)
    #expect(malformedLocalIDList.error.contains("local-id list"))

    let malformedLocalIDListHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: malformedLocalIDListHomeURL,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: malformedLocalIDListHomeURL) }
    let malformedEmptyHomeList = try runCLIResult(
      ["local-id", "list", "unexpected", "--json"],
      homeURL: malformedLocalIDListHomeURL
    )
    #expect(malformedEmptyHomeList.status == 64)
    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: malformedLocalIDListHomeURL.path),
      []
    )

    let malformedLocalIDGetHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: malformedLocalIDGetHomeURL,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: malformedLocalIDGetHomeURL) }
    let malformedEmptyHomeGet = try runCLIResult(
      ["local-id", "get", "--json"],
      homeURL: malformedLocalIDGetHomeURL
    )
    #expect(malformedEmptyHomeGet.status == 64)
    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: malformedLocalIDGetHomeURL.path),
      []
    )

    let malformedSeed = try runCLIResult(
      ["examples", "todos", "seed", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformedSeed.status == 64)
    #expect(malformedSeed.error.contains("examples todos seed"))

    let reseedOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "seed", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reseedOutput.todos.map(\.id), seedOutput.todos.map(\.id))
    expectNoDifference(reseedOutput.todos.map(\.text), seedOutput.todos.map(\.text))
    expectNoDifference(reseedOutput.pendingMutationCount, 2)

    let malformedReset = try runCLIResult(
      ["examples", "todos", "reset", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformedReset.status == 64)
    #expect(malformedReset.error.contains("examples todos reset"))

    let afterMalformedReset = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(afterMalformedReset.todos.map(\.id), seedOutput.todos.map(\.id))
    expectNoDifference(afterMalformedReset.pendingMutationCount, 2)

    let resetOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "reset", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(resetOutput.event, "reset")
    expectNoDifference(resetOutput.todos, [])
    expectNoDifference(resetOutput.pendingMutationCount, 3)

    let emptyResetOutput = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "reset", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyResetOutput.todos, [])
    expectNoDifference(emptyResetOutput.pendingMutationCount, 3)
  }

  @Test
  func cliOutboxRetryAndDrainOperateOnDurableState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "retry me", "--json"], homeURL: homeURL)
    _ = try runCLI(["examples", "todos", "add", "drain later", "--json"], homeURL: homeURL)

    let initialOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    let retriedMutationID = try #require(initialOutbox.mutations.first?.id)

    let failed = try JSONDecoder().decode(
      CLIOutboxUpdateOutput.self,
      from: Data(
        try runCLI(
          ["outbox", "fail", retriedMutationID, "server rejected", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(failed.mutation.status, "failed")
    expectNoDifference(failed.mutation.failureMessage, "server rejected")

    let retried = try JSONDecoder().decode(
      CLIOutboxUpdateOutput.self,
      from: Data(try runCLI(["outbox", "retry", retriedMutationID, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(retried.mutation.status, "pending")
    expectNoDifference(retried.mutation.failureMessage, nil)

    let firstDrain = try JSONDecoder().decode(
      CLIOutboxDrainOutput.self,
      from: Data(
        try runCLI(
          ["outbox", "drain", "--local-confirm", "--limit", "1", "--json"],
          homeURL: homeURL
        )
        .utf8
      )
    )
    expectNoDifference(firstDrain.event, "drain-local-confirm")
    expectNoDifference(firstDrain.drainedMutationCount, 1)
    expectNoDifference(firstDrain.mutations.map(\.id), [retriedMutationID])
    expectNoDifference(firstDrain.mutations.map(\.status), ["confirmed"])
    expectNoDifference(firstDrain.pendingMutationCount, 1)
    expectNoDifference(firstDrain.mutationCount, 1)

    let finalDrainOutput = try runCLI(
      ["outbox", "drain", "--local-confirm", "--jsonl"],
      homeURL: homeURL
    )
    let finalSummaryLine = try #require(finalDrainOutput.split(separator: "\n").first)
    let finalDrain = try JSONDecoder().decode(
      CLIOutboxDrainEvidence.self,
      from: Data(finalSummaryLine.utf8)
    )
    expectNoDifference(finalDrain.event, "drain-local-confirm")
    expectNoDifference(finalDrain.details.drainedMutationCount, 1)
    expectNoDifference(finalDrain.details.pendingMutationCount, 0)

    let emptyOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyOutbox.pendingMutationCount, 0)
    expectNoDifference(emptyOutbox.mutationCount, 0)
    expectNoDifference(emptyOutbox.mutations, [])
  }

  @Test
  func cliMalformedOutboxArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let malformedInspect = try runCLIResult(
      ["outbox", "inspect", "extra", "--json"],
      homeURL: homeURL
    )
    #expect(malformedInspect.status == 64)
    #expect(malformedInspect.error.contains("outbox inspect"))

    let malformedFlush = try runCLIResult(
      ["outbox", "flush", "--limit", "-1", "--json"],
      homeURL: homeURL
    )
    #expect(malformedFlush.status == 64)
    #expect(malformedFlush.error.contains("outbox flush"))

    let malformedDrain = try runCLIResult(
      ["outbox", "drain", "--limit", "1", "--json"],
      homeURL: homeURL
    )
    #expect(malformedDrain.status == 64)
    #expect(malformedDrain.error.contains("outbox drain"))

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedRoomsFilesAndStreamsArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    func expectMalformed(_ arguments: [String], contains expectedFragment: String) throws {
      let result = try runCLIResult(arguments, homeURL: homeURL)
      expectNoDifference(result.status, 64)
      #expect(result.error.contains(expectedFragment))
    }

    try expectMalformed(
      ["rooms", "--json"],
      contains: "Usage: instant-swift-data rooms"
    )
    try expectMalformed(
      ["rooms", "presence", "set", "chat", "lobby", "--json"],
      contains: "Missing required option --value"
    )
    try expectMalformed(
      ["rooms", "presence", "set", "chat", "lobby", "--user-id", "  ", "--json"],
      contains: "Missing non-empty value for --user-id"
    )
    try expectMalformed(
      ["rooms", "presence", "watch", "chat", "lobby", "--events", "2", "--json"],
      contains: "rooms presence watch <room-type> <room-id> --events 1"
    )
    try expectMalformed(
      ["rooms", "presence", "leave", "chat", "lobby", "--user-id", "  ", "--json"],
      contains: "Missing non-empty value for --user-id"
    )
    try expectMalformed(
      ["rooms", "topics", "publish", "chat", "lobby", "sendEmoji", "--json"],
      contains: "Missing required option --value"
    )
    try expectMalformed(
      ["rooms", "topics", "list", "chat", "lobby", "sendEmoji", "--limit", "-1", "--json"],
      contains: "Invalid --limit value"
    )
    try expectMalformed(
      ["rooms", "topics", "watch", "chat", "lobby", "sendEmoji", "--surprise", "--json"],
      contains: "Unknown rooms topics watch option: --surprise"
    )
    try expectMalformed(
      ["files", "upload", "--json"],
      contains: "files upload <path>"
    )
    try expectMalformed(
      ["files", "upload", "/tmp/demo.txt", "--content-type", "  ", "--json"],
      contains: "Missing non-empty value for --content-type"
    )
    try expectMalformed(
      ["files", "upload-progress", "--json"],
      contains: "files upload-progress <path>"
    )
    try expectMalformed(
      ["files", "watch", "--events", "2", "--json"],
      contains: "instant-swift-data files watch --events 1"
    )
    try expectMalformed(
      ["files", "read", "file-1", "extra", "--json"],
      contains: "files read <file-id>"
    )
    try expectMalformed(
      ["streams", "append", "chat/lobby", "--json"],
      contains: "Missing required option --value"
    )
    try expectMalformed(
      ["streams", "read", "chat/lobby", "--limit", "-1", "--json"],
      contains: "Invalid --limit value"
    )
    try expectMalformed(
      ["streams", "watch", "chat/lobby", "--events", "2", "--json"],
      contains: "instant-swift-data streams watch <stream-id> --events 1"
    )

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliOutboxInspectAndConfirmEmitStructuredEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "confirm json", "--json"], homeURL: homeURL)

    let inspectJSONL = try runCLI(["outbox", "inspect", "--jsonl"], homeURL: homeURL)
    let inspectLines = inspectJSONL.split(separator: "\n")
    expectNoDifference(inspectLines.count, 2)
    let inspectSummary = try #require(
      JSONSerialization.jsonObject(with: Data(inspectLines[0].utf8)) as? [String: Any]
    )
    expectNoDifference(inspectSummary["case"] as? String, "cli.outbox.inspect")
    expectNoDifference(inspectSummary["event"] as? String, "summary")

    let pendingOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    let confirmedMutationID = try #require(pendingOutbox.mutations.first?.id)
    let confirmed = try JSONDecoder().decode(
      CLIOutboxUpdateOutput.self,
      from: Data(
        try runCLI(["outbox", "confirm", confirmedMutationID, "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(confirmed.mutation.id, confirmedMutationID)
    expectNoDifference(confirmed.mutation.status, "confirmed")

    _ = try runCLI(["examples", "todos", "add", "confirm jsonl", "--json"], homeURL: homeURL)
    let nextOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    let jsonlMutationID = try #require(nextOutbox.mutations.first?.id)
    let confirmJSONL = try runCLI(
      ["outbox", "confirm", jsonlMutationID, "--jsonl"],
      homeURL: homeURL
    )
    let confirmSummaryLine = try #require(confirmJSONL.split(separator: "\n").first)
    let confirmSummary = try #require(
      JSONSerialization.jsonObject(with: Data(confirmSummaryLine.utf8)) as? [String: Any]
    )
    expectNoDifference(confirmSummary["case"] as? String, "cli.outbox.update")
    expectNoDifference(confirmSummary["event"] as? String, "confirm")
  }

  @Test
  func cliOutboxTransportLowersPendingMutations() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let addOutput = try runCLI(
      ["examples", "todos", "add", "transport from cli", "--json"],
      homeURL: homeURL
    )
    let add = try JSONDecoder().decode(CLIAddOutput.self, from: Data(addOutput.utf8))
    let todoID = try #require(add.changedID)

    let transportObject = try #require(
      JSONSerialization.jsonObject(
        with: Data(try runCLI(["outbox", "transport", "--json"], homeURL: homeURL).utf8)
      ) as? [String: Any]
    )
    expectNoDifference(transportObject["event"] as? String, "transport")
    expectNoDifference(transportObject["mutationCount"] as? Int, 1)
    expectNoDifference(transportObject["txStepCount"] as? Int, 4)
    expectNoDifference(transportObject["preconditionCount"] as? Int, 1)
    let mutations = try #require(transportObject["mutations"] as? [[String: Any]])
    let mutation = try #require(mutations.first)
    expectNoDifference(mutation["status"] as? String, "pending")
    let preconditions = try #require(mutation["preconditions"] as? [[String: Any]])
    expectNoDifference(preconditions.first?["kind"] as? String, "entity-missing")
    expectNoDifference(preconditions.first?["entity"] as? String, todoID)

    let txSteps = try #require(mutation["txSteps"] as? [[Any]])
    expectNoDifference(txSteps[0][0] as? String, "add-triple")
    expectNoDifference(txSteps[0][1] as? String, todoID)
    expectNoDifference(txSteps[0][2] as? String, "todos/id")
    expectNoDifference(txSteps[0][3] as? String, todoID)
    expectNoDifference((txSteps[0][4] as? [String: Any])?["mode"] as? String, "create")
    let textStep = try #require(
      txSteps.first { step in step.count > 2 && step[2] as? String == "todos/text" }
    )
    expectNoDifference(textStep[3] as? String, "transport from cli")

    let jsonlOutput = try runCLI(["outbox", "transport", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 2)
    let summary = try #require(
      JSONSerialization.jsonObject(with: Data(jsonlLines[0].utf8)) as? [String: Any]
    )
    expectNoDifference(summary["case"] as? String, "cli.outbox.transport")
    expectNoDifference(summary["event"] as? String, "summary")

    let outbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    let mutationID = try #require(outbox.mutations.first?.id)
    _ = try runCLI(["outbox", "fail", mutationID, "server rejected", "--json"], homeURL: homeURL)
    let erroredStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(erroredStatus.state, "errored")
    expectNoDifference(erroredStatus.lastErrorMessage, "server rejected")

    let pendingOnly = try #require(
      JSONSerialization.jsonObject(
        with: Data(try runCLI(["outbox", "transport", "--json"], homeURL: homeURL).utf8)
      ) as? [String: Any]
    )
    expectNoDifference(pendingOnly["mutationCount"] as? Int, 0)

    let includeFailed = try #require(
      JSONSerialization.jsonObject(
        with: Data(try runCLI(["outbox", "transport", "--all", "--json"], homeURL: homeURL).utf8)
      ) as? [String: Any]
    )
    expectNoDifference(includeFailed["includeFailed"] as? Bool, true)
    expectNoDifference(includeFailed["mutationCount"] as? Int, 1)
    let failedTransportMutations = try #require(includeFailed["mutations"] as? [[String: Any]])
    expectNoDifference(
      failedTransportMutations.first?["failureMessage"] as? String,
      "server rejected"
    )

    _ = try runCLI(["outbox", "retry", mutationID, "--json"], homeURL: homeURL)
    let retriedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(retriedStatus.state, "opened")
    expectNoDifference(retriedStatus.lastErrorMessage, nil)

    let malformed = try runCLIResult(
      ["outbox", "transport", "--unknown", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("outbox transport"))
  }

  @Test
  func cliOutboxFlushUsesLocalMutationTransport() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(["examples", "todos", "add", "flush one", "--json"], homeURL: homeURL)
    _ = try runCLI(["examples", "todos", "add", "flush two", "--json"], homeURL: homeURL)

    let firstFlush = try #require(
      JSONSerialization.jsonObject(
        with: Data(
          try runCLI(["outbox", "flush", "--limit", "1", "--json"], homeURL: homeURL).utf8
        )
      ) as? [String: Any]
    )
    expectNoDifference(firstFlush["event"] as? String, "flush-local-transport")
    expectNoDifference(firstFlush["transport"] as? String, "local-mutation-transport")
    expectNoDifference(firstFlush["attemptedMutationCount"] as? Int, 1)
    expectNoDifference(firstFlush["confirmedMutationCount"] as? Int, 1)
    expectNoDifference(firstFlush["failedMutationCount"] as? Int, 0)
    expectNoDifference(firstFlush["pendingMutationCount"] as? Int, 1)
    expectNoDifference(firstFlush["mutationCount"] as? Int, 1)
    let firstResults = try #require(firstFlush["results"] as? [[String: Any]])
    expectNoDifference(firstResults.map { $0["outcome"] as? String }, ["confirmed"])
    let request = try #require(firstFlush["request"] as? [String: Any])
    let requestMutations = try #require(request["mutations"] as? [[String: Any]])
    expectNoDifference(requestMutations.count, 1)

    let jsonlOutput = try runCLI(["outbox", "flush", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 2)
    let summary = try #require(
      JSONSerialization.jsonObject(with: Data(jsonlLines[0].utf8)) as? [String: Any]
    )
    expectNoDifference(summary["case"] as? String, "cli.outbox.flush")
    expectNoDifference(summary["event"] as? String, "summary")
    expectNoDifference(summary["ok"] as? Bool, true)
    let summaryDetails = try #require(summary["details"] as? [String: Any])
    expectNoDifference(summaryDetails["pendingMutationCount"] as? Int, 0)

    let emptyOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyOutbox.pendingMutationCount, 0)
    expectNoDifference(emptyOutbox.mutations, [])

    let malformed = try runCLIResult(
      ["outbox", "flush", "--limit", "-1", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("outbox flush"))
  }

  @Test
  func cliOutboxFlushWaitsForReconnectWhenConnectionIsClosed() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let emptyClosedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "close", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyClosedStatus.state, "closed")
    expectNoDifference(emptyClosedStatus.pendingMutationCount, 0)

    let offlineAdd = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "add", "flush after reconnect", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(offlineAdd.event, "add")
    expectNoDifference(offlineAdd.pendingMutationCount, 1)
    expectNoDifference(offlineAdd.todos.map(\.text), ["flush after reconnect"])

    let closedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(closedStatus.state, "closed")
    expectNoDifference(closedStatus.pendingMutationCount, 1)

    let blockedFlush = try runCLIResult(["outbox", "flush", "--json"], homeURL: homeURL)
    expectNoDifference(blockedFlush.status, 69)
    #expect(blockedFlush.error.contains("Cannot flush 1 pending mutation(s)"))
    #expect(blockedFlush.error.contains("Call connect() before flushing pending mutations."))

    let pendingOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(pendingOutbox.pendingMutationCount, 1)
    expectNoDifference(pendingOutbox.mutations.map(\.status), ["pending"])

    let stillClosedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(stillClosedStatus.state, "closed")
    expectNoDifference(stillClosedStatus.pendingMutationCount, 1)
    expectNoDifference(stillClosedStatus.lastErrorMessage, nil)

    let connectedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "connect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(connectedStatus.state, "opened")
    expectNoDifference(connectedStatus.pendingMutationCount, 1)

    let flush = try #require(
      JSONSerialization.jsonObject(
        with: Data(try runCLI(["outbox", "flush", "--json"], homeURL: homeURL).utf8)
      ) as? [String: Any]
    )
    expectNoDifference(flush["event"] as? String, "flush-local-transport")
    expectNoDifference(flush["confirmedMutationCount"] as? Int, 1)
    expectNoDifference(flush["pendingMutationCount"] as? Int, 0)

    let emptyOutbox = try JSONDecoder().decode(
      CLIOutboxInspectOutput.self,
      from: Data(try runCLI(["outbox", "inspect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyOutbox.pendingMutationCount, 0)
    expectNoDifference(emptyOutbox.mutations, [])
  }

  @Test
  func cliConnectionStatusReportsDurableLocalRuntime() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let initialStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(initialStatus.event, "status")
    expectNoDifference(initialStatus.transport, "local-cache-only")
    expectNoDifference(initialStatus.state, "opened")
    expectNoDifference(initialStatus.isAuthenticated, false)
    expectNoDifference(initialStatus.pendingMutationCount, 0)
    #expect(initialStatus.processedTransactionID == nil)

    let closedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "close", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(closedStatus.event, "close")
    expectNoDifference(closedStatus.state, "closed")
    expectNoDifference(closedStatus.isAuthenticated, false)
    let statusAfterClose = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(statusAfterClose.event, "status")
    expectNoDifference(statusAfterClose.state, "closed")
    expectNoDifference(statusAfterClose.isAuthenticated, false)

    let connectedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "connect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(connectedStatus.event, "connect")
    expectNoDifference(connectedStatus.state, "opened")
    expectNoDifference(connectedStatus.isAuthenticated, false)
    let statusAfterConnect = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(statusAfterConnect.event, "status")
    expectNoDifference(statusAfterConnect.state, "opened")
    expectNoDifference(statusAfterConnect.isAuthenticated, false)

    _ = try runCLI(["examples", "todos", "add", "status proof", "--json"], homeURL: homeURL)
    _ = try runCLI(["sync", "mark-processed", "tx-remote-status", "--json"], homeURL: homeURL)
    _ = try runCLI(["auth", "guest", "--json"], homeURL: homeURL)

    let closedAuthenticatedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "close", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(closedAuthenticatedStatus.event, "close")
    expectNoDifference(closedAuthenticatedStatus.state, "closed")
    expectNoDifference(closedAuthenticatedStatus.isAuthenticated, true)
    expectNoDifference(closedAuthenticatedStatus.pendingMutationCount, 1)
    let authenticatedStatusAfterClose = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(authenticatedStatusAfterClose.event, "status")
    expectNoDifference(authenticatedStatusAfterClose.state, "closed")
    expectNoDifference(authenticatedStatusAfterClose.isAuthenticated, true)
    expectNoDifference(authenticatedStatusAfterClose.pendingMutationCount, 1)

    let reconnectedAuthenticatedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "connect", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reconnectedAuthenticatedStatus.event, "connect")
    expectNoDifference(reconnectedAuthenticatedStatus.state, "authenticated")
    expectNoDifference(reconnectedAuthenticatedStatus.isAuthenticated, true)
    expectNoDifference(reconnectedAuthenticatedStatus.pendingMutationCount, 1)

    let authenticatedStatus = try JSONDecoder().decode(
      CLIConnectionStatusOutput.self,
      from: Data(try runCLI(["connection", "status", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(authenticatedStatus.event, "status")
    expectNoDifference(authenticatedStatus.appID, "cli-cache-test")
    expectNoDifference(
      authenticatedStatus.cachePath,
      homeURL.appendingPathComponent("state.sqlite").path
    )
    expectNoDifference(authenticatedStatus.apiURI, "https://api.instantdb.com")
    expectNoDifference(
      authenticatedStatus.websocketURI,
      "wss://api.instantdb.com/runtime/session"
    )
    expectNoDifference(authenticatedStatus.transport, "local-cache-only")
    expectNoDifference(authenticatedStatus.state, "authenticated")
    expectNoDifference(authenticatedStatus.isAuthenticated, true)
    #expect(authenticatedStatus.userID?.isEmpty == false)
    expectNoDifference(authenticatedStatus.pendingMutationCount, 1)
    expectNoDifference(authenticatedStatus.processedTransactionID, "tx-remote-status")
    #expect(authenticatedStatus.lastErrorMessage == nil)

    let jsonlOutput = try runCLI(["connection", "status", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 1)
    let evidence = try JSONDecoder().decode(
      CLIConnectionStatusEvidence.self,
      from: Data(jsonlLines[0].utf8)
    )
    expectNoDifference(evidence.caseID, "cli.connection.status")
    expectNoDifference(evidence.event, "status")
    expectNoDifference(evidence.ok, true)
    expectNoDifference(evidence.details.state, "authenticated")
    expectNoDifference(evidence.details.pendingMutationCount, 1)

    let closeJSONL = try runCLI(["connection", "close", "--jsonl"], homeURL: homeURL)
    let closeJSONLLines = closeJSONL.split(separator: "\n")
    expectNoDifference(closeJSONLLines.count, 1)
    let closeEvidence = try JSONDecoder().decode(
      CLIConnectionStatusEvidence.self,
      from: Data(closeJSONLLines[0].utf8)
    )
    expectNoDifference(closeEvidence.caseID, "cli.connection.close")
    expectNoDifference(closeEvidence.event, "close")
    expectNoDifference(closeEvidence.ok, true)
    expectNoDifference(closeEvidence.details.state, "closed")
    expectNoDifference(closeEvidence.details.pendingMutationCount, 1)

    let connectJSONL = try runCLI(["connection", "connect", "--jsonl"], homeURL: homeURL)
    let connectJSONLLines = connectJSONL.split(separator: "\n")
    expectNoDifference(connectJSONLLines.count, 1)
    let connectEvidence = try JSONDecoder().decode(
      CLIConnectionStatusEvidence.self,
      from: Data(connectJSONLLines[0].utf8)
    )
    expectNoDifference(connectEvidence.caseID, "cli.connection.connect")
    expectNoDifference(connectEvidence.event, "connect")
    expectNoDifference(connectEvidence.ok, true)
    expectNoDifference(connectEvidence.details.state, "authenticated")
    expectNoDifference(connectEvidence.details.pendingMutationCount, 1)

    let malformed = try runCLIResult(
      ["connection", "status", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("connection status"))

    let malformedClose = try runCLIResult(
      ["connection", "close", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformedClose.status == 64)
    #expect(malformedClose.error.contains("connection close"))

    let malformedConnect = try runCLIResult(
      ["connection", "connect", "unexpected", "--json"],
      homeURL: homeURL
    )
    #expect(malformedConnect.status == 64)
    #expect(malformedConnect.error.contains("connection connect"))
  }

  @Test
  func cliEphemeralAppPersistsSelectionForLaterCommands() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let created = try JSONDecoder().decode(
      CLIAppOutput.self,
      from: Data(
        try runCLI(
          ["app", "ephemeral", "--title", "Reminders Port", "--json"],
          homeURL: homeURL,
          environment: ["INSTANT_APP_ID": nil]
        ).utf8
      )
    )
    #expect(created.appID.hasPrefix("local-ephemeral-"))
    expectNoDifference(created.event, "ephemeral")
    expectNoDifference(created.transport, "not-implemented-local-cache-only")
    expectNoDifference(created.selectionSource, "argument")
    expectNoDifference(created.title, "Reminders Port")
    expectNoDifference(created.isLocalOnly, true)

    let show = try JSONDecoder().decode(
      CLIAppOutput.self,
      from: Data(
        try runCLI(["app", "show", "--json"], homeURL: homeURL, environment: ["INSTANT_APP_ID": nil])
          .utf8
      )
    )
    expectNoDifference(show.appID, created.appID)
    expectNoDifference(show.selectionSource, "selected")

    let add = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(
          ["examples", "todos", "add", "uses selected ephemeral app", "--json"],
          homeURL: homeURL,
          environment: ["INSTANT_APP_ID": nil]
        ).utf8
      )
    )
    expectNoDifference(add.appID, created.appID)

    let jsonlOutput = try runCLI(
      ["app", "ephemeral", "--title", "JSONL Port", "--jsonl"],
      homeURL: homeURL,
      environment: ["INSTANT_APP_ID": nil]
    )
    let evidence = try JSONDecoder().decode(
      CLIAppEvidence.self,
      from: Data(try #require(jsonlOutput.split(separator: "\n").first).utf8)
    )
    expectNoDifference(evidence.event, "ephemeral")
    expectNoDifference(evidence.details.title, "JSONL Port")
    expectNoDifference(evidence.details.isLocalOnly, true)

    let humanOutput = try runCLI(
      ["app", "ephemeral", "--title", "Human Port"],
      homeURL: homeURL,
      environment: ["INSTANT_APP_ID": nil]
    )
    #expect(humanOutput.contains("transport: not-implemented-local-cache-only"))

    let malformed = try runCLIResult(
      ["app", "ephemeral", "--json"],
      homeURL: homeURL,
      environment: ["INSTANT_APP_ID": nil]
    )
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("app ephemeral --title"))
  }

  @Test
  func cliRoomsPresenceAndTopicsPersistAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let setPresence = try JSONDecoder().decode(
      CLIRoomPresenceOutput.self,
      from: Data(
        try runCLI(
          [
            "rooms", "presence", "set", "chat", "lobby",
            "--value", #"{"name":"Ada","status":"online"}"#,
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(setPresence.event, "presence-set")
    expectNoDifference(setPresence.transport, "not-implemented-local-cache-only")
    expectNoDifference(setPresence.room, InstantRoomHandle(type: "chat", id: "lobby"))
    expectNoDifference(setPresence.userID, "user-1")
    expectNoDifference(setPresence.memberCount, 1)
    expectNoDifference(setPresence.members.first?.userID, "user-1")
    expectNoDifference(setPresence.members.first?.values["name"], .string("Ada"))

    let invalidDuplicatePresenceValue = try runCLIResult(
      [
        "rooms", "presence", "set", "chat", "lobby",
        "--value", "not-json",
        "--value", "{}",
        "--json",
      ],
      homeURL: homeURL
    )
    #expect(invalidDuplicatePresenceValue.status == 64)
    #expect(invalidDuplicatePresenceValue.error.contains("set room presence: Invalid JSON value"))

    let listedPresence = try JSONDecoder().decode(
      CLIRoomPresenceOutput.self,
      from: Data(
        try runCLI(
          ["rooms", "presence", "list", "chat", "lobby", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listedPresence.members, setPresence.members)

    let presenceJSONL = try runCLI(
      ["rooms", "presence", "list", "chat", "lobby", "--jsonl"],
      homeURL: homeURL
    )
    let presenceLines = presenceJSONL.split(separator: "\n")
    expectNoDifference(presenceLines.count, 2)
    let presenceEvidence = try JSONDecoder().decode(
      CLIRoomPresenceEvidence.self,
      from: Data(try #require(presenceLines.first).utf8)
    )
    expectNoDifference(presenceEvidence.caseID, "cli.rooms.presence")
    expectNoDifference(presenceEvidence.details.memberCount, 1)

    let presenceWatchJSONL = try runCLI(
      ["rooms", "presence", "watch", "chat", "lobby", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let presenceWatchLines = presenceWatchJSONL.split(separator: "\n")
    expectNoDifference(presenceWatchLines.count, 2)
    let presenceWatchEvidence = try JSONDecoder().decode(
      CLIRoomPresenceEvidence.self,
      from: Data(try #require(presenceWatchLines.first).utf8)
    )
    expectNoDifference(presenceWatchEvidence.event, "presence-watch")
    expectNoDifference(presenceWatchEvidence.details.members, setPresence.members)

    let invalidPresenceWatch = try runCLIResult(
      ["rooms", "presence", "watch", "chat", "lobby", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidPresenceWatch.status == 64)
    #expect(invalidPresenceWatch.error.contains("rooms presence watch"))

    let firstTopic = try JSONDecoder().decode(
      CLIRoomTopicOutput.self,
      from: Data(
        try runCLI(
          [
            "rooms", "topics", "publish", "chat", "lobby", "sendEmoji",
            "--value", #"{"emoji":"wave"}"#,
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(firstTopic.event, "topic-publish")
    expectNoDifference(firstTopic.topic, "sendEmoji")
    expectNoDifference(firstTopic.messageCount, 1)
    expectNoDifference(firstTopic.messages.first?.userID, "user-1")
    expectNoDifference(firstTopic.messages.first?.payload, .object(["emoji": .string("wave")]))

    let invalidDuplicateTopicValue = try runCLIResult(
      [
        "rooms", "topics", "publish", "chat", "lobby", "sendEmoji",
        "--value", "not-json",
        "--value", #"{"emoji":"valid"}"#,
        "--json",
      ],
      homeURL: homeURL
    )
    #expect(invalidDuplicateTopicValue.status == 64)
    #expect(invalidDuplicateTopicValue.error.contains("publish room topic: Invalid JSON value"))

    _ = try runCLI(
      [
        "rooms", "topics", "publish", "chat", "lobby", "sendEmoji",
        "--value", #"{"emoji":"spark"}"#,
        "--json",
      ],
      homeURL: homeURL
    )

    let limitedTopic = try JSONDecoder().decode(
      CLIRoomTopicOutput.self,
      from: Data(
        try runCLI(
          ["rooms", "topics", "list", "chat", "lobby", "sendEmoji", "--limit", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(limitedTopic.event, "topic-list")
    expectNoDifference(limitedTopic.messageCount, 1)
    expectNoDifference(limitedTopic.messages.first?.payload, .object(["emoji": .string("wave")]))

    let topicWatch = try JSONDecoder().decode(
      CLIRoomTopicOutput.self,
      from: Data(
        try runCLI(
          ["rooms", "topics", "watch", "chat", "lobby", "sendEmoji", "--events", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(topicWatch.event, "topic-watch")
    expectNoDifference(topicWatch.messageCount, 2)
    expectNoDifference(
      topicWatch.messages.map(\.payload),
      [.object(["emoji": .string("wave")]), .object(["emoji": .string("spark")])]
    )

    let topicWatchJSONL = try runCLI(
      [
        "rooms", "topics", "watch", "chat", "lobby", "sendEmoji",
        "--events", "1",
        "--jsonl",
      ],
      homeURL: homeURL
    )
    let topicWatchLines = topicWatchJSONL.split(separator: "\n")
    expectNoDifference(topicWatchLines.count, 3)
    let topicWatchEvidence = try JSONDecoder().decode(
      CLIRoomTopicEvidence.self,
      from: Data(try #require(topicWatchLines.first).utf8)
    )
    expectNoDifference(topicWatchEvidence.event, "topic-watch")
    expectNoDifference(topicWatchEvidence.details.messageCount, 2)
    let topicMessageRows = try topicWatchLines.dropFirst().map {
      try JSONDecoder().decode(CLIRoomTopicMessageEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(topicMessageRows.map(\.event), ["topic-message", "topic-message"])
    expectNoDifference(topicMessageRows.map(\.details), topicWatch.messages)

    let invalidTopicWatch = try runCLIResult(
      [
        "rooms", "topics", "watch", "chat", "lobby", "sendEmoji",
        "--events", "2",
        "--json",
      ],
      homeURL: homeURL
    )
    #expect(invalidTopicWatch.status == 64)
    #expect(invalidTopicWatch.error.contains("rooms topics watch"))

    let leftPresence = try JSONDecoder().decode(
      CLIRoomPresenceOutput.self,
      from: Data(
        try runCLI(
          ["rooms", "presence", "leave", "chat", "lobby", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(leftPresence.event, "presence-leave")
    expectNoDifference(leftPresence.userID, "user-1")
    expectNoDifference(leftPresence.memberCount, 0)
    expectNoDifference(leftPresence.members, [])

    let anonymousHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: anonymousHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: anonymousHomeURL) }
    let anonymous = try runCLIResult(
      [
        "rooms", "presence", "set", "chat", "lobby",
        "--value", #"{"status":"online"}"#,
        "--json",
      ],
      homeURL: anonymousHomeURL
    )
    #expect(anonymous.status == 65)
    #expect(anonymous.error.contains("Room operations require a signed-in user"))
  }

  @Test
  func cliReactionsRecipePublishesAndWatchesTopicMessagesAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedOutTap = try runCLIResult(
      ["examples", "reactions", "tap", "fire", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedOutTap.status, 65)
    #expect(signedOutTap.error.contains("Room operations require a signed-in user"))

    _ = try runCLI(
      ["auth", "token", "reactions-a", "--user-id", "user-a", "--json"],
      homeURL: homeURL
    )
    let wave = try JSONDecoder().decode(
      CLIReactionsRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reactions", "tap", "wave",
            "--direction", "45",
            "--rotation", "90",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(wave.event, "tap")
    expectNoDifference(wave.transport, "not-implemented-local-cache-only")
    expectNoDifference(wave.room, ReactionsRecipeExample.room)
    expectNoDifference(wave.topic, ReactionsRecipeExample.topic)
    expectNoDifference(wave.authUserID, "user-a")
    expectNoDifference(wave.messageCount, 1)
    expectNoDifference(wave.reactionCount, 1)
    expectNoDifference(wave.reactions.map(\.name), ["wave"])
    expectNoDifference(wave.reactions.map(\.directionAngle), [45])
    expectNoDifference(wave.reactions.map(\.rotationAngle), [90])
    expectNoDifference(wave.publishedMessageID, wave.messages.first?.id)
    expectNoDifference(
      wave.messages.map(\.payload),
      [CLIReactionsRecipePayload(name: "wave", directionAngle: 45, rotationAngle: 90)]
    )

    _ = try runCLI(
      ["auth", "token", "reactions-b", "--user-id", "user-b", "--json"],
      homeURL: homeURL
    )
    let heart = try JSONDecoder().decode(
      CLIReactionsRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "reactions", "send", "heart",
            "--direction", "135",
            "--rotation", "270",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(heart.event, "tap")
    expectNoDifference(heart.authUserID, "user-b")
    expectNoDifference(heart.messageCount, 2)
    expectNoDifference(heart.reactionCount, 2)
    expectNoDifference(heart.reactions.map(\.name), ["wave", "heart"])
    expectNoDifference(heart.reactions.map(\.userID), ["user-a", "user-b"])
    expectNoDifference(
      heart.messages.map(\.payload),
      [
        CLIReactionsRecipePayload(name: "wave", directionAngle: 45, rotationAngle: 90),
        CLIReactionsRecipePayload(name: "heart", directionAngle: 135, rotationAngle: 270),
      ]
    )

    let limited = try JSONDecoder().decode(
      CLIReactionsRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "reactions", "list", "--limit", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(limited.event, "list")
    expectNoDifference(limited.messageCount, 1)
    expectNoDifference(limited.reactions.map(\.name), ["wave"])

    let watchJSONL = try runCLI(
      ["examples", "reactions", "watch", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 3)
    let watch = try JSONDecoder().decode(
      CLIReactionsRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watch.caseID, "cli.examples.reactions")
    expectNoDifference(watch.event, "watch")
    expectNoDifference(watch.details.reactionCount, 2)
    expectNoDifference(watch.details.reactions.map(\.name), ["wave", "heart"])
    let rows = try watchLines.dropFirst().map {
      try JSONDecoder().decode(CLIReactionsRecipeReactionEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(rows.map(\.event), ["reaction", "reaction"])
    expectNoDifference(rows.map(\.details.name), ["wave", "heart"])

    let invalidName = try runCLIResult(
      ["examples", "reactions", "tap", "sparkle", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidName.status, 64)
    #expect(invalidName.error.contains("Invalid reactions name: sparkle."))

    let invalidAngle = try runCLIResult(
      ["examples", "reactions", "tap", "fire", "--direction", "360", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidAngle.status, 64)
    #expect(invalidAngle.error.contains("Invalid reactions angle: 360."))
  }

  @Test
  func cliTypingIndicatorRecipePersistsActivePresenceAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let joined = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "join", "user-a", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(joined.event, "join")
    expectNoDifference(joined.transport, "not-implemented-local-cache-only")
    expectNoDifference(joined.room, TypingIndicatorRecipeExample.room)
    expectNoDifference(joined.inputName, TypingIndicatorRecipeExample.inputName)
    expectNoDifference(joined.userID, "user-a")
    expectNoDifference(joined.viewerUserID, "user-a")
    expectNoDifference(joined.memberCount, 1)
    expectNoDifference(joined.activeCount, 0)
    expectNoDifference(joined.typingInfo, nil)
    expectNoDifference(joined.members.compactMap(\.presenceID), ["user-a"])
    expectNoDifference(joined.members.map(\.isTyping), [false])

    let userATyping = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing", "type", "user-a", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(userATyping.event, "type")
    expectNoDifference(userATyping.viewerUserID, "user-a")
    expectNoDifference(userATyping.activeCount, 0)
    expectNoDifference(userATyping.typingInfo, nil)
    expectNoDifference(userATyping.activeMembers.map(\.userID), [])

    let twoTyping = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "type", "user-b", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(twoTyping.viewerUserID, "user-b")
    expectNoDifference(twoTyping.activeCount, 1)
    expectNoDifference(twoTyping.typingInfo, "1 person is typing...")
    expectNoDifference(twoTyping.activeMembers.map(\.userID), ["user-a"])
    expectNoDifference(twoTyping.members.map(\.userID), ["user-a", "user-b"])
    expectNoDifference(twoTyping.members.map(\.isTyping), [true, true])

    let listed = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "list", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listed.event, "list")
    expectNoDifference(listed.viewerUserID, nil)
    expectNoDifference(listed.activeMembers.map(\.userID), ["user-a", "user-b"])

    let listedForUserA = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "list", "--viewer-user-id", "user-a", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listedForUserA.viewerUserID, "user-a")
    expectNoDifference(listedForUserA.activeMembers.map(\.userID), ["user-b"])

    let watchJSONL = try runCLI(
      ["examples", "typing-indicator", "watch", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 3)
    let watch = try JSONDecoder().decode(
      CLITypingIndicatorRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watch.caseID, "cli.examples.typing-indicator")
    expectNoDifference(watch.event, "watch")
    expectNoDifference(watch.details.activeCount, 2)
    expectNoDifference(watch.details.activeMembers.compactMap(\.presenceID), ["user-a", "user-b"])
    let memberRows = try watchLines.dropFirst().map {
      try JSONDecoder().decode(CLITypingIndicatorRecipeMemberEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(memberRows.map(\.event), ["typing-member", "typing-member"])
    expectNoDifference(memberRows.map(\.details.userID), ["user-a", "user-b"])

    let stopped = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "stop", "user-a", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(stopped.viewerUserID, "user-a")
    expectNoDifference(stopped.activeMembers.map(\.userID), ["user-b"])

    let left = try JSONDecoder().decode(
      CLITypingIndicatorRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "typing-indicator", "leave", "user-b", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(left.event, "leave")
    expectNoDifference(left.userID, "user-b")
    expectNoDifference(left.viewerUserID, "user-b")
    expectNoDifference(left.members.map(\.userID), ["user-a"])
    expectNoDifference(left.activeCount, 0)
    expectNoDifference(left.activeMembers.map(\.userID), [])

    let invalidWatch = try runCLIResult(
      ["examples", "typing-indicator", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidWatch.status, 64)
    #expect(invalidWatch.error.contains("typing-indicator watch"))
  }

  @Test
  func cliAvatarStackRecipePersistsPresenceAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let joined = try JSONDecoder().decode(
      CLIAvatarStackRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "avatar-stack", "join", "user-alpha", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(joined.event, "join")
    expectNoDifference(joined.transport, "not-implemented-local-cache-only")
    expectNoDifference(joined.room, AvatarStackRecipeExample.room)
    expectNoDifference(joined.nameKey, AvatarStackRecipeExample.nameKey)
    expectNoDifference(joined.userID, "user-alpha")
    expectNoDifference(joined.viewerUserID, "user-alpha")
    expectNoDifference(joined.memberCount, 1)
    expectNoDifference(joined.peerCount, 0)
    expectNoDifference(joined.onlineCount, 1)
    expectNoDifference(joined.currentUser?.userID, "user-alpha")
    expectNoDifference(joined.currentUser?.name, "user-a")
    expectNoDifference(joined.peers, [])
    expectNoDifference(joined.members.map(\.isViewer), [true])

    let bettyJoined = try JSONDecoder().decode(
      CLIAvatarStackRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "avatars", "join", "user-beta", "--name", "Betty", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(bettyJoined.viewerUserID, "user-beta")
    expectNoDifference(bettyJoined.currentUser?.name, "Betty")
    expectNoDifference(bettyJoined.peers.map(\.userID), ["user-alpha"])
    expectNoDifference(bettyJoined.onlineCount, 2)

    let listed = try JSONDecoder().decode(
      CLIAvatarStackRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "avatar-stack", "list", "--viewer-user-id", "user-alpha", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listed.event, "list")
    expectNoDifference(listed.viewerUserID, "user-alpha")
    expectNoDifference(listed.currentUser?.userID, "user-alpha")
    expectNoDifference(listed.currentUser?.name, "user-a")
    expectNoDifference(listed.peers.map(\.userID), ["user-beta"])
    expectNoDifference(listed.peers.map(\.name), ["Betty"])
    expectNoDifference(listed.peerCount, 1)
    expectNoDifference(listed.onlineCount, 2)

    let terminalListed = try JSONDecoder().decode(
      CLIAvatarStackRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "avatar-stack", "list", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(terminalListed.viewerUserID, nil)
    expectNoDifference(terminalListed.currentUser, nil)
    expectNoDifference(terminalListed.peers.map(\.userID), ["user-alpha", "user-beta"])
    expectNoDifference(terminalListed.onlineCount, 2)

    let watchJSONL = try runCLI(
      [
        "examples", "avatar-stack", "watch",
        "--events", "1",
        "--viewer-user-id", "user-alpha",
        "--jsonl",
      ],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 3)
    let watch = try JSONDecoder().decode(
      CLIAvatarStackRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watch.caseID, "cli.examples.avatar-stack")
    expectNoDifference(watch.event, "watch")
    expectNoDifference(watch.details.viewerUserID, "user-alpha")
    expectNoDifference(watch.details.currentUser?.name, "user-a")
    expectNoDifference(watch.details.peers.map(\.name), ["Betty"])
    let memberRows = try watchLines.dropFirst().map {
      try JSONDecoder().decode(CLIAvatarStackRecipeMemberEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(memberRows.map(\.event), ["current-user", "avatar-member"])
    expectNoDifference(memberRows.map(\.details.userID), ["user-alpha", "user-beta"])

    let left = try JSONDecoder().decode(
      CLIAvatarStackRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "avatar-stack", "leave", "user-beta", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(left.event, "leave")
    expectNoDifference(left.userID, "user-beta")
    expectNoDifference(left.viewerUserID, "user-beta")
    expectNoDifference(left.currentUser, nil)
    expectNoDifference(left.members.map(\.userID), ["user-alpha"])
    expectNoDifference(left.onlineCount, 1)

    let invalidWatch = try runCLIResult(
      ["examples", "avatar-stack", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidWatch.status, 64)
    #expect(invalidWatch.error.contains("avatar-stack watch"))
  }

  @Test
  func cliCursorsRecipesPersistPresenceAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let alphaMoved = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "cursors", "move", "user-alpha",
            "--x", "10",
            "--y", "20",
            "--x-percent", "25",
            "--y-percent", "50",
            "--color", "#123456",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(alphaMoved.event, "move")
    expectNoDifference(alphaMoved.transport, "not-implemented-local-cache-only")
    expectNoDifference(alphaMoved.room, CursorsRecipeExample.room)
    expectNoDifference(alphaMoved.spaceID, CursorsRecipeExample.spaceID)
    expectNoDifference(alphaMoved.nameKey, nil)
    expectNoDifference(alphaMoved.userID, "user-alpha")
    expectNoDifference(alphaMoved.viewerUserID, "user-alpha")
    expectNoDifference(alphaMoved.memberCount, 1)
    expectNoDifference(alphaMoved.cursorCount, 0)
    expectNoDifference(alphaMoved.visibleCursors, [])
    expectNoDifference(alphaMoved.members.map(\.color), ["#123456"])
    expectNoDifference(alphaMoved.members.map(\.isViewer), [true])

    let betaMoved = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "cursor", "move", "user-beta",
            "--x", "30",
            "--y", "40",
            "--x-percent", "75",
            "--y-percent", "80",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(betaMoved.viewerUserID, "user-beta")
    expectNoDifference(betaMoved.members.map(\.userID), ["user-alpha", "user-beta"])
    expectNoDifference(betaMoved.visibleCursors.map(\.userID), ["user-alpha"])
    expectNoDifference(betaMoved.members.map(\.color), ["#123456", CursorsRecipeExample.defaultColor])

    let listed = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "cursors", "list", "--viewer-user-id", "user-alpha", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listed.event, "list")
    expectNoDifference(listed.viewerUserID, "user-alpha")
    expectNoDifference(listed.cursorCount, 1)
    expectNoDifference(listed.visibleCursors.map(\.userID), ["user-beta"])
    expectNoDifference(listed.visibleCursors.map(\.xPercent), [75])
    expectNoDifference(listed.visibleCursors.map(\.yPercent), [80])

    let watchJSONL = try runCLI(
      [
        "examples", "cursors", "watch",
        "--events", "1",
        "--viewer-user-id", "user-alpha",
        "--jsonl",
      ],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 2)
    let watch = try JSONDecoder().decode(
      CLICursorsRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watch.caseID, "cli.examples.cursors")
    expectNoDifference(watch.event, "watch")
    expectNoDifference(watch.details.visibleCursors.map(\.userID), ["user-beta"])
    let cursorRows = try watchLines.dropFirst().map {
      try JSONDecoder().decode(CLICursorsRecipeCursorEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(cursorRows.map(\.event), ["cursor-member"])
    expectNoDifference(cursorRows.map(\.details.userID), ["user-beta"])

    let cleared = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "cursors", "clear", "user-beta", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(cleared.event, "clear")
    expectNoDifference(cleared.userID, "user-beta")
    expectNoDifference(cleared.viewerUserID, "user-beta")
    expectNoDifference(cleared.members.map(\.userID), ["user-alpha"])
    expectNoDifference(cleared.visibleCursors.map(\.userID), ["user-alpha"])

    let left = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "cursors", "leave", "user-alpha", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(left.event, "leave")
    expectNoDifference(left.userID, "user-alpha")
    expectNoDifference(left.members, [])
    expectNoDifference(left.cursorCount, 0)

    let customMoved = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "custom-cursors", "move", "user-custom",
            "--x", "1",
            "--y", "2",
            "--x-percent", "3",
            "--y-percent", "4",
            "--name", "Ada",
            "--color", "#abcdef",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(customMoved.room, CursorsRecipeExample.customRoom)
    expectNoDifference(customMoved.spaceID, CursorsRecipeExample.spaceID(for: CursorsRecipeExample.customRoom))
    expectNoDifference(customMoved.nameKey, CursorsRecipeExample.nameKey)
    expectNoDifference(customMoved.members.map(\.name), ["Ada"])
    expectNoDifference(customMoved.members.map(\.color), ["#abcdef"])

    let customListed = try JSONDecoder().decode(
      CLICursorsRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "custom-cursors", "list", "--viewer-user-id", "viewer", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(customListed.cursorCount, 1)
    expectNoDifference(customListed.visibleCursors.map(\.name), ["Ada"])

    let invalidWatch = try runCLIResult(
      ["examples", "custom-cursors", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidWatch.status, 64)
    #expect(invalidWatch.error.contains("custom-cursors watch"))
  }

  @Test
  func cliMergeTileGameUsesMergeAndPresenceAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let initialBoard = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "board", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(initialBoard.event, "board")
    expectNoDifference(initialBoard.transport, "not-implemented-local-cache-only")
    expectNoDifference(initialBoard.room, MergeTileGameRecipeExample.room)
    expectNoDifference(initialBoard.boardID, MergeTileGameRecipeExample.boardID)
    expectNoDifference(initialBoard.boardSize, 4)
    expectNoDifference(initialBoard.emptyColor, MergeTileGameRecipeExample.emptyColor)
    expectNoDifference(initialBoard.playerCount, 0)
    expectNoDifference(initialBoard.filledCount, 0)
    expectNoDifference(initialBoard.board?.state.count, 16)
    expectNoDifference(initialBoard.paintedCells, [])

    let alpha = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "join", "user-alpha", "--color", "#e76f51", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(alpha.event, "join")
    expectNoDifference(alpha.userID, "user-alpha")
    expectNoDifference(alpha.currentPlayer?.color, "#e76f51")
    expectNoDifference(alpha.availableColors, ["#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0"])

    let beta = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "tile-game", "join", "user-beta", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(beta.event, "join")
    expectNoDifference(beta.currentPlayer?.userID, "user-beta")
    expectNoDifference(beta.currentPlayer?.color, "#2a9d8f")
    expectNoDifference(beta.players.map(\.userID), ["user-alpha", "user-beta"])
    expectNoDifference(beta.peers.map(\.userID), ["user-alpha"])

    let alphaTapped = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-game", "tap", "user-alpha", "0", "0", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(alphaTapped.event, "tap")
    expectNoDifference(alphaTapped.board?.state["0-0"], "#e76f51")
    expectNoDifference(alphaTapped.filledCount, 1)

    let betaTapped = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "tap", "user-beta", "0", "1", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(betaTapped.board?.state["0-0"], "#e76f51")
    expectNoDifference(betaTapped.board?.state["0-1"], "#2a9d8f")
    expectNoDifference(betaTapped.board?.state["1-0"], MergeTileGameRecipeExample.emptyColor)
    expectNoDifference(betaTapped.filledCount, 2)
    expectNoDifference(betaTapped.paintedCells.map(\.key), ["0-0", "0-1"])

    let listed = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "state", "--viewer-user-id", "user-alpha", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(listed.event, "board")
    expectNoDifference(listed.currentPlayer?.userID, "user-alpha")
    expectNoDifference(listed.peers.map(\.userID), ["user-beta"])
    expectNoDifference(listed.paintedCells.map(\.color), ["#e76f51", "#2a9d8f"])

    let watchJSONL = try runCLI(
      [
        "examples", "merge-tile-game", "watch",
        "--events", "1",
        "--viewer-user-id", "user-alpha",
        "--jsonl",
      ],
      homeURL: homeURL
    )
    let watchLines = watchJSONL.split(separator: "\n")
    expectNoDifference(watchLines.count, 5)
    let watch = try JSONDecoder().decode(
      CLIMergeTileGameRecipeEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watch.caseID, "cli.examples.merge-tile-game")
    expectNoDifference(watch.event, "watch")
    expectNoDifference(watch.details.filledCount, 2)
    expectNoDifference(watch.details.currentPlayer?.userID, "user-alpha")
    let evidenceRows = try watchLines.dropFirst().map {
      try JSONDecoder().decode(CLIMergeTileGameRecipeDetailEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(
      evidenceRows.map(\.event),
      ["current-player", "player", "painted-cell", "painted-cell"]
    )

    let reset = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "reset", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.filledCount, 0)
    expectNoDifference(reset.paintedCells, [])
    expectNoDifference(reset.board?.state["0-0"], MergeTileGameRecipeExample.emptyColor)

    let left = try JSONDecoder().decode(
      CLIMergeTileGameRecipeOutput.self,
      from: Data(
        try runCLI(
          ["examples", "merge-tile-game", "leave", "user-beta", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(left.event, "leave")
    expectNoDifference(left.userID, "user-beta")
    expectNoDifference(left.players.map(\.userID), ["user-alpha"])

    let invalidColor = try runCLIResult(
      ["examples", "merge-tile-game", "join", "user-gamma", "--color", "#000000", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidColor.status, 64)
    #expect(invalidColor.error.contains("Invalid merge tile game color: #000000."))

    let invalidCell = try runCLIResult(
      ["examples", "merge-tile-game", "tap", "user-alpha", "4", "0", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(invalidCell.status, 64)
    #expect(invalidCell.error.contains("merge-tile-game tap"))
  }

  @Test
  func cliFilesUploadListAndDeletePersistAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }
    let sourceURL = homeURL.appendingPathComponent("instant-demo-file.txt")
    let contents = Data("hello instant files\n".utf8)
    try contents.write(to: sourceURL)

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let upload = try JSONDecoder().decode(
      CLIFilesOutput.self,
      from: Data(
        try runCLI(
          [
            "files", "upload", sourceURL.path,
            "--content-type", "text/plain",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(upload.event, "upload")
    expectNoDifference(upload.transport, "not-implemented-local-cache-only")
    expectNoDifference(upload.fileCount, 1)
    let file = try #require(upload.files.first)
    expectNoDifference(upload.changedID, file.id)
    expectNoDifference(file.name, "instant-demo-file.txt")
    expectNoDifference(file.contentType, "text/plain")
    expectNoDifference(file.byteCount, Int64(contents.count))
    expectNoDifference(file.ownerUserID, "user-1")
    expectNoDifference(FileManager.default.fileExists(atPath: file.localPath), true)

    let read = try JSONDecoder().decode(
      CLIFileContentsOutput.self,
      from: Data(try runCLI(["files", "read", file.id, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(read.event, "read")
    expectNoDifference(read.transport, "not-implemented-local-cache-only")
    expectNoDifference(read.file, file)
    expectNoDifference(read.byteCount, Int64(contents.count))
    expectNoDifference(read.base64Content, contents.base64EncodedString())
    expectNoDifference(read.utf8Content, "hello instant files\n")

    let readJSONL = try runCLI(["files", "read", file.id, "--jsonl"], homeURL: homeURL)
    let readLines = readJSONL.split(separator: "\n")
    expectNoDifference(readLines.count, 1)
    let readEvidence = try JSONDecoder().decode(
      CLIFileContentsEvidence.self,
      from: Data(try #require(readLines.first).utf8)
    )
    expectNoDifference(readEvidence.caseID, "cli.files.contents")
    expectNoDifference(readEvidence.event, "read")
    expectNoDifference(readEvidence.details.utf8Content, "hello instant files\n")

    let list = try JSONDecoder().decode(
      CLIFilesOutput.self,
      from: Data(try runCLI(["files", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(list.event, "list")
    expectNoDifference(list.files, upload.files)

    let jsonlOutput = try runCLI(["files", "list", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 2)
    let evidence = try JSONDecoder().decode(
      CLIFilesEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.files")
    expectNoDifference(evidence.details.fileCount, 1)

    let watchOutput = try runCLI(["files", "watch", "--events", "1", "--jsonl"], homeURL: homeURL)
    let watchLines = watchOutput.split(separator: "\n")
    expectNoDifference(watchLines.count, 2)
    let watchEvidence = try JSONDecoder().decode(
      CLIFilesEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watchEvidence.caseID, "cli.files")
    expectNoDifference(watchEvidence.event, "watch")
    expectNoDifference(watchEvidence.details.files, upload.files)

    let invalidWatch = try runCLIResult(
      ["files", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidWatch.status == 64)
    #expect(invalidWatch.error.contains("files watch"))

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutList = try runCLIResult(["files", "list", "--json"], homeURL: homeURL)
    #expect(signedOutList.status == 65)
    #expect(signedOutList.error.contains("File operations require a signed-in user"))
    let signedOutWatch = try runCLIResult(["files", "watch", "--json"], homeURL: homeURL)
    #expect(signedOutWatch.status == 65)
    #expect(signedOutWatch.error.contains("File operations require a signed-in user"))
    let signedOutRead = try runCLIResult(["files", "read", file.id, "--json"], homeURL: homeURL)
    #expect(signedOutRead.status == 65)
    #expect(signedOutRead.error.contains("File operations require a signed-in user"))
    let signedOutDelete = try runCLIResult(["files", "delete", file.id, "--json"], homeURL: homeURL)
    #expect(signedOutDelete.status == 65)
    #expect(signedOutDelete.error.contains("File operations require a signed-in user"))
    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let deleted = try JSONDecoder().decode(
      CLIFilesOutput.self,
      from: Data(try runCLI(["files", "delete", file.id, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(deleted.event, "delete")
    expectNoDifference(deleted.changedID, file.id)
    expectNoDifference(deleted.fileCount, 0)
    expectNoDifference(deleted.files, [])
    expectNoDifference(FileManager.default.fileExists(atPath: file.localPath), false)

    let anonymousHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: anonymousHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: anonymousHomeURL) }
    let anonymousSourceURL = anonymousHomeURL.appendingPathComponent("anonymous.txt")
    try Data("anonymous".utf8).write(to: anonymousSourceURL)
    let anonymous = try runCLIResult(
      ["files", "upload", anonymousSourceURL.path, "--json"],
      homeURL: anonymousHomeURL
    )
    #expect(anonymous.status == 65)
    #expect(anonymous.error.contains("File operations require a signed-in user"))
  }

  @Test
  func cliFilesReadBinaryContentFallsBackToBase64() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }
    let sourceURL = homeURL.appendingPathComponent("instant-binary-file.bin")
    let contents = Data([0x00, 0xff, 0xfe, 0x41, 0x42])
    try contents.write(to: sourceURL)

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let upload = try JSONDecoder().decode(
      CLIFilesOutput.self,
      from: Data(
        try runCLI(
          [
            "files", "upload", sourceURL.path,
            "--content-type", "application/octet-stream",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    let file = try #require(upload.files.first)

    let read = try JSONDecoder().decode(
      CLIFileContentsOutput.self,
      from: Data(try runCLI(["files", "read", file.id, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(read.file, file)
    expectNoDifference(read.byteCount, Int64(contents.count))
    expectNoDifference(read.base64Content, contents.base64EncodedString())
    expectNoDifference(read.utf8Content, nil)

    let readJSONL = try runCLI(["files", "read", file.id, "--jsonl"], homeURL: homeURL)
    let readLines = readJSONL.split(separator: "\n")
    expectNoDifference(readLines.count, 1)
    let readEvidence = try JSONDecoder().decode(
      CLIFileContentsEvidence.self,
      from: Data(try #require(readLines.first).utf8)
    )
    expectNoDifference(readEvidence.caseID, "cli.files.contents")
    expectNoDifference(readEvidence.event, "read")
    expectNoDifference(readEvidence.details.base64Content, contents.base64EncodedString())
    expectNoDifference(readEvidence.details.utf8Content, nil)

    let humanOutput = try runCLI(["files", "read", file.id], homeURL: homeURL)
    expectNoDifference(humanOutput, contents.base64EncodedString() + "\n")
  }

  @Test
  func cliFilesUploadProgressEmitsFiniteEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }
    let sourceURL = homeURL.appendingPathComponent("progress.txt")
    let contents = Data("progress from cli\n".utf8)
    try contents.write(to: sourceURL)

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let summary = try JSONDecoder().decode(
      CLIFileUploadProgressSummaryOutput.self,
      from: Data(
        try runCLI(
          [
            "files", "upload-progress", sourceURL.path,
            "--name", "progress-json.txt",
            "--content-type", "text/plain",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(summary.event, "upload-progress")
    expectNoDifference(summary.transport, "not-implemented-local-cache-only")
    expectNoDifference(summary.emittedEventCount, 2)
    expectNoDifference(summary.finalState, .success)
    expectNoDifference(summary.events.map(\.state), [.loading, .success])
    expectNoDifference(summary.events.map(\.completedByteCount), [0, Int64(contents.count)])
    let uploaded = try #require(summary.events.last?.file)
    expectNoDifference(uploaded.name, "progress-json.txt")
    expectNoDifference(uploaded.contentType, "text/plain")
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), true)

    let jsonlOutput = try runCLI(
      [
        "files", "upload-progress", sourceURL.path,
        "--name", "progress-jsonl.txt",
        "--content-type", "text/plain",
        "--jsonl",
      ],
      homeURL: homeURL
    )
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 2)
    let evidence = try lines.map {
      try JSONDecoder().decode(CLIFileUploadProgressEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(evidence.map(\.caseID), [
      "cli.files.upload-progress",
      "cli.files.upload-progress",
    ])
    expectNoDifference(evidence.map(\.event), ["loading", "success"])
    expectNoDifference(evidence.map(\.details.state), [.loading, .success])
    expectNoDifference(evidence.last?.details.file?.name, "progress-jsonl.txt")

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutProgress = try runCLIResult(
      ["files", "upload-progress", sourceURL.path, "--json"],
      homeURL: homeURL
    )
    #expect(signedOutProgress.status == 65)
    #expect(signedOutProgress.error.contains("File operations require a signed-in user"))
  }

  @Test
  func cliStreamsAppendAndReadPersistAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )

    let firstAppend = try JSONDecoder().decode(
      CLIStreamsOutput.self,
      from: Data(
        try runCLI(
          ["streams", "append", "chat/lobby", "--value", #"{"text":"hello"}"#, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(firstAppend.event, "append")
    expectNoDifference(firstAppend.transport, "not-implemented-local-cache-only")
    expectNoDifference(firstAppend.streamID, "chat/lobby")
    expectNoDifference(firstAppend.chunkCount, 1)
    expectNoDifference(firstAppend.chunks.map(\.payload), [.object(["text": .string("hello")])])
    expectNoDifference(firstAppend.chunks.map(\.index), [0])
    expectNoDifference(firstAppend.chunks.map(\.userID), ["user-1"])
    expectNoDifference(firstAppend.changedID, firstAppend.chunks.first?.id)

    let secondAppend = try JSONDecoder().decode(
      CLIStreamsOutput.self,
      from: Data(
        try runCLI(
          ["streams", "append", "chat/lobby", "--value", #"{"text":"again"}"#, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(secondAppend.chunkCount, 2)
    expectNoDifference(
      secondAppend.chunks.map(\.payload),
      [
        .object(["text": .string("hello")]),
        .object(["text": .string("again")]),
      ]
    )
    expectNoDifference(secondAppend.chunks.map(\.index), [0, 1])

    let otherStreamAppend = try JSONDecoder().decode(
      CLIStreamsOutput.self,
      from: Data(
        try runCLI(
          ["streams", "append", "chat/side", "--value", #"{"text":"side"}"#, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(otherStreamAppend.streamID, "chat/side")
    expectNoDifference(otherStreamAppend.chunks.map(\.payload), [.object(["text": .string("side")])])
    expectNoDifference(otherStreamAppend.chunks.map(\.index), [0])

    let limitedRead = try JSONDecoder().decode(
      CLIStreamsOutput.self,
      from: Data(
        try runCLI(["streams", "read", "chat/lobby", "--limit", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(limitedRead.event, "read")
    expectNoDifference(limitedRead.changedID, nil)
    expectNoDifference(limitedRead.chunkCount, 1)
    expectNoDifference(limitedRead.chunks, Array(secondAppend.chunks.prefix(1)))

    let jsonlOutput = try runCLI(["streams", "read", "chat/lobby", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 3)
    let evidence = try JSONDecoder().decode(
      CLIStreamsEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.streams")
    expectNoDifference(evidence.event, "read")
    expectNoDifference(evidence.details.chunkCount, 2)
    let chunkRows = try lines.dropFirst().map {
      try JSONDecoder().decode(CLIStreamChunkEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(chunkRows.map(\.event), ["chunk", "chunk"])
    expectNoDifference(chunkRows.map(\.caseID), ["cli.streams", "cli.streams"])
    expectNoDifference(chunkRows.map(\.details), secondAppend.chunks)

    let watchOutput = try runCLI(
      ["streams", "watch", "chat/lobby", "--events", "1", "--jsonl"],
      homeURL: homeURL
    )
    let watchLines = watchOutput.split(separator: "\n")
    expectNoDifference(watchLines.count, 3)
    let watchEvidence = try JSONDecoder().decode(
      CLIStreamsEvidence.self,
      from: Data(try #require(watchLines.first).utf8)
    )
    expectNoDifference(watchEvidence.caseID, "cli.streams")
    expectNoDifference(watchEvidence.event, "watch")
    expectNoDifference(watchEvidence.details.changedID, nil)
    expectNoDifference(watchEvidence.details.chunks, secondAppend.chunks)

    let invalidWatch = try runCLIResult(
      ["streams", "watch", "chat/lobby", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidWatch.status == 64)
    #expect(invalidWatch.error.contains("streams watch"))

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutRead = try runCLIResult(["streams", "read", "chat/lobby", "--json"], homeURL: homeURL)
    #expect(signedOutRead.status == 65)
    #expect(signedOutRead.error.contains("Stream operations require a signed-in user"))
    let signedOutWatch = try runCLIResult(
      ["streams", "watch", "chat/lobby", "--json"],
      homeURL: homeURL
    )
    #expect(signedOutWatch.status == 65)
    #expect(signedOutWatch.error.contains("Stream operations require a signed-in user"))
    let signedOutAppend = try runCLIResult(
      ["streams", "append", "chat/lobby", "--value", #"{"text":"blocked"}"#, "--json"],
      homeURL: homeURL
    )
    #expect(signedOutAppend.status == 65)
    #expect(signedOutAppend.error.contains("Stream operations require a signed-in user"))

    _ = try runCLI(
      ["auth", "token", "refresh-token", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let reauthenticatedRead = try JSONDecoder().decode(
      CLIStreamsOutput.self,
      from: Data(try runCLI(["streams", "read", "chat/lobby", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reauthenticatedRead.chunks, secondAppend.chunks)
  }

  @Test
  func cliSharesCreateAcceptListAndRevokePersistAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let addedTodo = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "add", "shared cli todo", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let todoID = try #require(addedTodo.changedID)

    let created = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "create", TodoExample.namespace, todoID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(created.event, "create")
    expectNoDifference(created.transport, "not-implemented-local-cache-only")
    expectNoDifference(created.shareCount, 1)
    let createdSnapshot = try #require(created.shares.first)
    expectNoDifference(created.changedID, createdSnapshot.share.id)
    expectNoDifference(createdSnapshot.share.rootNamespace, TodoExample.namespace)
    expectNoDifference(createdSnapshot.share.rootID, todoID)
    expectNoDifference(createdSnapshot.share.ownerUserID, "user-1")
    expectNoDifference(createdSnapshot.memberships.map(\.role), [.owner])
    let shareID = createdSnapshot.share.id
    let token = createdSnapshot.share.token

    let ownerList = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(ownerList.shares.map(\.share.id), [shareID])
    expectNoDifference(ownerList.shares.first?.memberships.map(\.userID), ["user-1"])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let accepted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "accept", token, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(accepted.event, "accept")
    let acceptedSnapshot = try #require(accepted.shares.first)
    expectNoDifference(acceptedSnapshot.memberships.map(\.userID), ["user-1", "user-2"])
    expectNoDifference(acceptedSnapshot.memberships.map(\.role), [.owner, .reader])

    let inviteeListJSONL = try runCLI(["shares", "list", "--jsonl"], homeURL: homeURL)
    let lines = inviteeListJSONL.split(separator: "\n")
    expectNoDifference(lines.count, 2)
    let evidence = try JSONDecoder().decode(
      CLIShareEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(evidence.caseID, "cli.shares")
    expectNoDifference(evidence.event, "list")
    expectNoDifference(evidence.details.shares.map(\.share.id), [acceptedSnapshot.share.id])
    expectNoDifference(evidence.details.shares.first?.memberships.map(\.userID), ["user-1", "user-2"])
    let shareRow = try JSONDecoder().decode(
      CLIShareSnapshotEvidence.self,
      from: Data(try #require(lines.dropFirst().first).utf8)
    )
    expectNoDifference(shareRow.event, "share")
    expectNoDifference(shareRow.details.share.id, acceptedSnapshot.share.id)
    expectNoDifference(shareRow.details.memberships.map(\.userID), ["user-1", "user-2"])

    let readerDuplicateShare = try runCLIResult(
      ["shares", "create", TodoExample.namespace, todoID, "--json"],
      homeURL: homeURL
    )
    #expect(readerDuplicateShare.status == 77)
    #expect(readerDuplicateShare.error.contains("cannot create a share"))

    let readerUpdate = try runCLIResult(
      ["examples", "todos", "update", todoID, "reader edit", "--json"],
      homeURL: homeURL
    )
    #expect(readerUpdate.status == 77)
    #expect(readerUpdate.error.contains("reader access"))
    let todosAfterReaderUpdate = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(try runCLI(["examples", "todos", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(todosAfterReaderUpdate.todos.map(\.text), ["shared cli todo"])
    expectNoDifference(todosAfterReaderUpdate.pendingMutationCount, 1)

    let nonOwnerRole = try runCLIResult(
      ["shares", "role", shareID, "user-2", "writer", "--json"],
      homeURL: homeURL
    )
    #expect(nonOwnerRole.status == 77)
    #expect(nonOwnerRole.error.contains("cannot update roles"))

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let promoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", shareID, "user-2", "writer", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(promoted.event, "role")
    expectNoDifference(promoted.changedID, shareID)
    expectNoDifference(promoted.shares.first?.memberships.map(\.role), [.owner, .writer])

    let ownerRole = try runCLIResult(
      ["shares", "role", shareID, "user-1", "reader", "--json"],
      homeURL: homeURL
    )
    #expect(ownerRole.status == 66)
    #expect(ownerRole.error.contains("owner's membership role cannot be changed"))

    let invalidRole = try runCLIResult(
      ["shares", "role", shareID, "user-2", "owner", "--json"],
      homeURL: homeURL
    )
    #expect(invalidRole.status == 64)
    #expect(invalidRole.error.contains("reader|writer"))

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let writerUpdate = try JSONDecoder().decode(
      CLITodosOutput.self,
      from: Data(
        try runCLI(["examples", "todos", "update", todoID, "writer edit", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(writerUpdate.todos.map(\.text), ["writer edit"])
    expectNoDifference(
      writerUpdate.pendingMutationCount,
      todosAfterReaderUpdate.pendingMutationCount + 1
    )

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let demoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", shareID, "user-2", "reader", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(demoted.shares.first?.memberships.map(\.role), [.owner, .reader])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let demotedReaderUpdate = try runCLIResult(
      ["examples", "todos", "update", todoID, "reader edit after demotion", "--json"],
      homeURL: homeURL
    )
    #expect(demotedReaderUpdate.status == 77)
    #expect(demotedReaderUpdate.error.contains("reader access"))

    let inviteeRevoke = try runCLIResult(["shares", "revoke", shareID, "--json"], homeURL: homeURL)
    #expect(inviteeRevoke.status == 77)
    #expect(inviteeRevoke.error.contains("cannot revoke share"))

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let revoked = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "revoke", shareID, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(revoked.event, "revoke")
    expectNoDifference(revoked.changedID, shareID)
    expectNoDifference(revoked.shares.first?.share.isRevoked, true)
    expectNoDifference(revoked.shares.first?.memberships.map(\.isRevoked), [true, true])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let inviteeAfterRevoke = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(inviteeAfterRevoke.shares, [])
    let revokedAccept = try runCLIResult(["shares", "accept", token, "--json"], homeURL: homeURL)
    #expect(revokedAccept.status == 66)
    #expect(revokedAccept.error.contains("was not found or has been revoked"))

    let anonymousHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: anonymousHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: anonymousHomeURL) }
    let anonymous = try runCLIResult(
      ["shares", "create", "remindersLists", "list-1", "--json"],
      homeURL: anonymousHomeURL
    )
    #expect(anonymous.status == 65)
    #expect(anonymous.error.contains("Share operations require a signed-in user"))
  }

  @Test
  func cliCountersCloudKitDemoShareMetadataAndRolesPersistAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let added = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(
        try runCLI(["examples", "counters", "add", "--count", "2", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(added.event, "add")
    expectNoDifference(added.transport, "not-implemented-local-cache-only")
    expectNoDifference(added.counterCount, 1)
    expectNoDifference(added.sharedCounterCount, 0)
    expectNoDifference(added.counters.map(\.counter.count), [2])
    expectNoDifference(added.counters.map(\.isShared), [false])
    let counterID = try #require(added.changedID)

    let incremented = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(
        try runCLI(["examples", "cloudkit-demo", "increment", counterID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(incremented.event, "increment")
    expectNoDifference(incremented.changedID, counterID)
    expectNoDifference(incremented.counters.map(\.counter.count), [3])

    let createdShare = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "create", CounterExample.namespace, counterID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    let share = try #require(createdShare.shares.first)
    expectNoDifference(share.share.rootNamespace, CounterExample.namespace)
    expectNoDifference(share.share.rootID, counterID)
    expectNoDifference(share.memberships.map(\.role), [.owner])

    let ownerList = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(try runCLI(["examples", "counters", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(ownerList.sharedCounterCount, 1)
    expectNoDifference(ownerList.counters.map(\.shareID), [share.share.id])
    expectNoDifference(ownerList.counters.map(\.shareRole), [.owner])
    expectNoDifference(ownerList.counters.map(\.shareMemberCount), [1])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let accepted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(try runCLI(["shares", "accept", share.share.token, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(accepted.shares.first?.memberships.map(\.role), [.owner, .reader])

    let readerList = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(try runCLI(["examples", "cloudkit-demo", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(readerList.counters.map(\.counter.count), [3])
    expectNoDifference(readerList.counters.map(\.isShared), [true])
    expectNoDifference(readerList.counters.map(\.shareRole), [.reader])
    expectNoDifference(readerList.counters.map(\.shareMemberCount), [2])

    let readerIncrement = try runCLIResult(
      ["examples", "counters", "increment", counterID, "--json"],
      homeURL: homeURL
    )
    #expect(readerIncrement.status == 77)
    #expect(readerIncrement.error.contains("reader access"))
    let unchanged = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(try runCLI(["examples", "counters", "list", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(unchanged.counters.map(\.counter.count), [3])

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let promoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", share.share.id, "user-2", "writer", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(promoted.shares.first?.memberships.map(\.role), [.owner, .writer])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let writerIncrement = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(
        try runCLI(["examples", "counters", "increment", counterID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(writerIncrement.counters.map(\.counter.count), [4])
    expectNoDifference(writerIncrement.counters.map(\.shareRole), [.writer])

    let writerDecrement = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(
        try runCLI(["examples", "counters", "decrement", counterID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(writerDecrement.counters.map(\.counter.count), [3])
    expectNoDifference(writerDecrement.counters.map(\.shareRole), [.writer])

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let demoted = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "role", share.share.id, "user-2", "reader", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(demoted.shares.first?.memberships.map(\.role), [.owner, .reader])

    _ = try runCLI(
      ["auth", "token", "invitee-refresh", "--user-id", "user-2", "--json"],
      homeURL: homeURL
    )
    let demotedDecrement = try runCLIResult(
      ["examples", "counters", "decrement", counterID, "--json"],
      homeURL: homeURL
    )
    #expect(demotedDecrement.status == 77)
    #expect(demotedDecrement.error.contains("reader access"))

    let readerDelete = try runCLIResult(
      ["examples", "counters", "delete", counterID, "--json"],
      homeURL: homeURL
    )
    #expect(readerDelete.status == 77)
    #expect(readerDelete.error.contains("reader access"))

    let jsonlOutput = try runCLI(["examples", "counters", "list", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 2)
    let summary = try JSONDecoder().decode(
      CLICountersEvidence.self,
      from: Data(try #require(jsonlLines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.examples.counters")
    expectNoDifference(summary.event, "list")
    expectNoDifference(summary.details.sharedCounterCount, 1)
    let counterEvidence = try JSONDecoder().decode(
      CLISharedCounterEvidence.self,
      from: Data(try #require(jsonlLines.dropFirst().first).utf8)
    )
    expectNoDifference(counterEvidence.caseID, "cli.examples.counters")
    expectNoDifference(counterEvidence.event, "counter")
    expectNoDifference(counterEvidence.entityID, counterID)
    expectNoDifference(counterEvidence.details.counter.count, 3)
    expectNoDifference(counterEvidence.details.shareRole, .reader)
    expectNoDifference(counterEvidence.details.shareMemberCount, 2)

    _ = try runCLI(
      ["auth", "token", "owner-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let deleted = try JSONDecoder().decode(
      CLICountersOutput.self,
      from: Data(try runCLI(["examples", "counters", "delete", counterID, "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(deleted.event, "delete")
    expectNoDifference(deleted.changedID, counterID)
    expectNoDifference(deleted.counterCount, 0)
    expectNoDifference(deleted.sharedCounterCount, 0)
    expectNoDifference(deleted.counters, [])
  }

  @Test
  func cliChatExampleSeedsPostsAndResetsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let seeded = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(try runCLI(["examples", "chat", "seed", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(seeded.event, "seed")
    expectNoDifference(seeded.transport, "not-implemented-local-cache-only")
    expectNoDifference(seeded.channelCount, 2)
    expectNoDifference(seeded.messageCount, 2)
    expectNoDifference(seeded.channels.map(\.title), ["general", "random"])
    expectNoDifference(
      Set(seeded.messages.map(\.text)),
      Set(["Welcome to Instant chat.", "Use this channel for anything else."])
    )
    let generalChannelID = try #require(
      seeded.channels.first { $0.title == "general" }?.id
    )

    let channels = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(try runCLI(["examples", "chat", "channels", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(channels.event, "channels")
    expectNoDifference(channels.channels.map(\.id), seeded.channels.map(\.id))

    let generalMessages = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(
        try runCLI(["examples", "chat", "messages", generalChannelID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(generalMessages.event, "messages")
    expectNoDifference(generalMessages.selectedChannelID, generalChannelID)
    expectNoDifference(generalMessages.messages.map(\.channelID), [generalChannelID])
    expectNoDifference(generalMessages.messages.map(\.text), ["Welcome to Instant chat."])

    let guestPost = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "chat", "post", generalChannelID,
            "--author", "Guest CLI",
            "Hello from the guest CLI",
            "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(guestPost.event, "post")
    expectNoDifference(guestPost.selectedChannelID, generalChannelID)
    expectNoDifference(guestPost.authIsGuest, true)
    let guestUserID = try #require(guestPost.authUserID)
    let guestMessageID = try #require(guestPost.changedID)
    let guestMessage = try #require(guestPost.messages.first { $0.id == guestMessageID })
    expectNoDifference(guestMessage.channelID, generalChannelID)
    expectNoDifference(guestMessage.authorName, "Guest CLI")
    expectNoDifference(guestMessage.authorUserID, guestUserID)
    expectNoDifference(guestMessage.text, "Hello from the guest CLI")

    let guestAuth = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(try runCLI(["auth", "show", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(guestAuth.isSignedIn, true)
    expectNoDifference(guestAuth.isGuest, true)
    expectNoDifference(guestAuth.userID, guestUserID)

    _ = try runCLI(
      ["auth", "token", "local-chat-refresh", "--user-id", "user-1", "--json"],
      homeURL: homeURL
    )
    let userPost = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(
        try runCLI(
          ["examples", "chat", "send", generalChannelID, "Hello from a logged-in user", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(userPost.event, "post")
    expectNoDifference(userPost.authUserID, "user-1")
    expectNoDifference(userPost.authIsGuest, false)
    let userMessageID = try #require(userPost.changedID)
    let userMessage = try #require(userPost.messages.first { $0.id == userMessageID })
    expectNoDifference(userMessage.channelID, generalChannelID)
    expectNoDifference(userMessage.authorName, "user-1")
    expectNoDifference(userMessage.authorUserID, "user-1")
    expectNoDifference(userMessage.text, "Hello from a logged-in user")
    expectNoDifference(userPost.messages.count, 3)

    let missingChannel = try runCLIResult(
      ["examples", "chat", "post", "missing-channel", "Hello", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingChannel.status, 66)
    #expect(missingChannel.error.contains("Chat channel not found: missing-channel"))

    let jsonlOutput = try runCLI(
      ["examples", "chat", "messages", generalChannelID, "--jsonl"],
      homeURL: homeURL
    )
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 6)
    let summary = try JSONDecoder().decode(
      CLIChatEvidence.self,
      from: Data(try #require(jsonlLines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.examples.chat")
    expectNoDifference(summary.event, "messages")
    expectNoDifference(summary.details.selectedChannelID, generalChannelID)
    expectNoDifference(summary.details.channelCount, 2)
    expectNoDifference(summary.details.messageCount, 3)
    let eventRows = try jsonlLines.dropFirst().map {
      try JSONDecoder().decode(CLIChatEventEnvelope.self, from: Data($0.utf8))
    }
    expectNoDifference(
      eventRows.map(\.event),
      ["channel", "channel", "message", "message", "message"]
    )
    let messageRows = try jsonlLines.dropFirst(3).map {
      try JSONDecoder().decode(CLIChatMessageEvidence.self, from: Data($0.utf8))
    }
    expectNoDifference(
      Set(messageRows.map(\.details.text)),
      Set([
        "Welcome to Instant chat.",
        "Hello from the guest CLI",
        "Hello from a logged-in user",
      ])
    )
    expectNoDifference(Set(messageRows.map(\.details.channelID)), Set([generalChannelID]))

    let reset = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(try runCLI(["examples", "chat", "reset", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.channelCount, 0)
    expectNoDifference(reset.messageCount, 0)
    expectNoDifference(reset.channels, [])
    expectNoDifference(reset.messages, [])

    let emptyMessages = try JSONDecoder().decode(
      CLIChatOutput.self,
      from: Data(try runCLI(["examples", "chat", "messages", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(emptyMessages.event, "messages")
    expectNoDifference(emptyMessages.channelCount, 0)
    expectNoDifference(emptyMessages.messageCount, 0)
  }

  @Test
  func cliMicroblogExampleSeedsAuthPostsLikesAndCascadesAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let seeded = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(try runCLI(["examples", "microblog", "seed", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(seeded.event, "seed")
    expectNoDifference(seeded.transport, "not-implemented-local-cache-only")
    expectNoDifference(seeded.authUserID, nil)
    expectNoDifference(seeded.userCount, 3)
    expectNoDifference(seeded.profileCount, 3)
    expectNoDifference(seeded.postCount, 3)
    expectNoDifference(seeded.likeCount, 38)
    expectNoDifference(
      seeded.feed.map { "\($0.post.id)|\($0.author?.handle ?? "missing")|\($0.likes.count)" },
      [
        "\(seeded.feed[0].post.id)|sarahchen|12",
        "\(seeded.feed[1].post.id)|alexrivera|19",
        "\(seeded.feed[2].post.id)|jordanlee|7",
      ]
    )
    let seedPostID = try #require(seeded.feed.first?.post.id)

    let jsonlOutput = try runCLI(["examples", "microblog", "feed", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    expectNoDifference(jsonlLines.count, 48)
    let summary = try JSONDecoder().decode(
      CLIMicroblogEvidence.self,
      from: Data(try #require(jsonlLines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.examples.microblog")
    expectNoDifference(summary.event, "feed")
    expectNoDifference(summary.details.userCount, 3)
    expectNoDifference(summary.details.profileCount, 3)
    expectNoDifference(summary.details.postCount, 3)
    expectNoDifference(summary.details.likeCount, 38)
    let eventRows = try jsonlLines.dropFirst().map {
      try JSONDecoder().decode(CLIMicroblogEventEnvelope.self, from: Data($0.utf8))
    }
    expectNoDifference(eventRows.filter { $0.event == "user" }.count, 3)
    expectNoDifference(eventRows.filter { $0.event == "profile" }.count, 3)
    expectNoDifference(eventRows.filter { $0.event == "post" }.count, 3)
    expectNoDifference(eventRows.filter { $0.event == "like" }.count, 38)

    let profilesList = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(try runCLI(["examples", "microblog", "profiles", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(profilesList.event, "profiles")
    expectNoDifference(profilesList.profiles.map(\.handle), [
      "alexrivera",
      "jordanlee",
      "sarahchen",
    ])
    let sarahUserID = try #require(
      profilesList.profiles.first { $0.handle == "sarahchen" }?.userID
    )
    let sarahProfile = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(["examples", "microblog", "profile", sarahUserID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(sarahProfile.event, "profile")
    expectNoDifference(sarahProfile.selectedUserID, sarahUserID)
    expectNoDifference(sarahProfile.selectedProfile?.handle, "sarahchen")

    let missingSelectedProfile = try runCLIResult(
      ["examples", "microblog", "profile", "missing-user", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingSelectedProfile.status, 66)
    #expect(missingSelectedProfile.error.contains("Microblog profile not found for user: missing-user."))

    let signedOutMutation = try runCLIResult(
      ["examples", "microblog", "like", seedPostID, "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedOutMutation.status, 65)
    #expect(signedOutMutation.error.contains("Microblog mutation requires a signed-in user."))

    _ = try runCLI(
      ["auth", "token", "microblog-refresh", "--user-id", "user-cli", "--json"],
      homeURL: homeURL
    )
    let missingProfile = try runCLIResult(
      ["examples", "microblog", "post", "Before profile", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingProfile.status, 66)
    #expect(missingProfile.error.contains("Microblog profile not found for user: user-cli."))

    let profile = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(
          ["examples", "microblog", "setup-profile", "CLI User", "@cli-user", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(profile.event, "setup-profile")
    expectNoDifference(profile.changedID, "user-cli")
    expectNoDifference(profile.selectedUserID, "user-cli")
    expectNoDifference(profile.authUserID, "user-cli")
    expectNoDifference(profile.userCount, 4)
    expectNoDifference(profile.profileCount, 4)
    let cliProfile = try #require(profile.profiles.first { $0.userID == "user-cli" })
    expectNoDifference(cliProfile.handle, "cli-user")
    expectNoDifference(cliProfile.displayName, "CLI User")

    let currentProfile = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(try runCLI(["examples", "microblog", "profile", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(currentProfile.event, "profile")
    expectNoDifference(currentProfile.selectedUserID, "user-cli")
    expectNoDifference(currentProfile.selectedProfile, cliProfile)

    let duplicateProfile = try runCLIResult(
      ["examples", "microblog", "setup-profile", "Again", "again", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(duplicateProfile.status, 66)
    #expect(duplicateProfile.error.contains("strict create entity: An entity already exists"))

    let posted = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "microblog", "post", "Hello from the CLI microblog",
            "--color", "bg-green-100", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(posted.event, "post")
    expectNoDifference(posted.postCount, 4)
    let createdPostID = try #require(posted.changedID)
    expectNoDifference(posted.selectedPostID, createdPostID)
    let createdFeedPost = try #require(posted.feed.first { $0.post.id == createdPostID })
    expectNoDifference(createdFeedPost.author?.handle, "cli-user")
    expectNoDifference(createdFeedPost.post.color, "bg-green-100")
    expectNoDifference(createdFeedPost.post.content, "Hello from the CLI microblog")
    expectNoDifference(createdFeedPost.likes, [])

    let liked = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(["examples", "microblog", "like", seedPostID, "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(liked.event, "like")
    expectNoDifference(liked.selectedPostID, seedPostID)
    expectNoDifference(liked.likeCount, 39)
    let likeID = try #require(liked.changedID)
    expectNoDifference(
      try #require(liked.feed.first { $0.post.id == seedPostID }).likes.count,
      13
    )

    let repeatedLike = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(["examples", "microblog", "like", seedPostID, "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(repeatedLike.changedID, likeID)
    expectNoDifference(repeatedLike.likeCount, 39)

    let unliked = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(["examples", "microblog", "unlike", seedPostID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(unliked.event, "unlike")
    expectNoDifference(unliked.changedID, likeID)
    expectNoDifference(unliked.likeCount, 38)
    expectNoDifference(
      try #require(unliked.feed.first { $0.post.id == seedPostID }).likes.count,
      12
    )

    let unlikeMissing = try runCLIResult(
      ["examples", "microblog", "unlike", seedPostID, "--json"],
      homeURL: homeURL
    )
    expectNoDifference(unlikeMissing.status, 66)
    #expect(unlikeMissing.error.contains("Microblog like not found for post: \(seedPostID)"))

    let wrongOwner = try runCLIResult(
      ["examples", "microblog", "delete-post", seedPostID, "--json"],
      homeURL: homeURL
    )
    expectNoDifference(wrongOwner.status, 77)
    #expect(wrongOwner.error.contains("is owned by profile"))

    let deleted = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(
        try runCLI(
          ["examples", "microblog", "delete-post", createdPostID, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(deleted.event, "delete-post")
    expectNoDifference(deleted.changedID, createdPostID)
    expectNoDifference(deleted.postCount, 3)
    expectNoDifference(deleted.feed.contains { $0.post.id == createdPostID }, false)

    let reset = try JSONDecoder().decode(
      CLIMicroblogOutput.self,
      from: Data(try runCLI(["examples", "microblog", "reset", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.userCount, 0)
    expectNoDifference(reset.profileCount, 0)
    expectNoDifference(reset.postCount, 0)
    expectNoDifference(reset.likeCount, 0)
    expectNoDifference(reset.users, [])
    expectNoDifference(reset.profiles, [])
    expectNoDifference(reset.posts, [])
    expectNoDifference(reset.likes, [])
    expectNoDifference(reset.feed, [])
  }

  @Test
  func cliMobileChatExampleSeedsAuthPresenceAndResetsAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let empty = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(["examples", "mobile-chat", "channels", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(empty.event, "channels")
    expectNoDifference(empty.channelCount, 0)
    expectNoDifference(empty.messageCount, 0)

    let seeded = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(try runCLI(["examples", "mobile-chat", "seed", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(seeded.event, "seed")
    expectNoDifference(seeded.transport, "not-implemented-local-cache-only")
    expectNoDifference(seeded.authUserID, nil)
    expectNoDifference(seeded.userCount, 1)
    expectNoDifference(seeded.profileCount, 1)
    expectNoDifference(seeded.channelCount, 2)
    expectNoDifference(seeded.messageCount, 2)
    expectNoDifference(seeded.channels.map(\.name), ["general", "random"])
    expectNoDifference(
      seeded.messages.map { "\($0.content)|\($0.author?.displayName ?? "missing")|\($0.authorUser?.email ?? "missing")" },
      [
        "Welcome to Instant mobile chat.|Instant|instant@example.com",
        "Use this room for anything else.|Instant|instant@example.com",
      ]
    )
    let generalChannelID = try #require(
      seeded.channels.first { $0.name == "general" }?.id
    )

    let signedOutSend = try runCLIResult(
      ["examples", "mobile-chat", "send", generalChannelID, "Signed out", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedOutSend.status, 65)
    #expect(signedOutSend.error.contains("Mobile chat send a message requires a signed-in user."))

    _ = try runCLI(
      ["auth", "token", "mobile-chat-refresh", "--user-id", "user-cli", "--json"],
      homeURL: homeURL
    )
    let noProfileSend = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          ["examples", "mobile-chat", "send", generalChannelID, "Before profile", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(noProfileSend.event, "send")
    expectNoDifference(noProfileSend.authUserID, "user-cli")
    expectNoDifference(noProfileSend.authIsGuest, false)
    let noProfileMessageID = try #require(noProfileSend.changedID)
    let noProfileMessage = try #require(
      noProfileSend.messages.first { $0.id == noProfileMessageID }
    )
    expectNoDifference(noProfileMessage.authorProfileID, nil)
    expectNoDifference(noProfileMessage.author, nil)
    expectNoDifference(noProfileMessage.authorUser, nil)

    let profile = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          ["examples", "mobile-chat", "setup-profile", "CLI User", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(profile.event, "setup-profile")
    expectNoDifference(profile.changedID, "user-cli")
    expectNoDifference(profile.selectedUserID, "user-cli")
    expectNoDifference(profile.selectedProfile?.displayName, "CLI User")
    expectNoDifference(profile.userCount, 2)
    expectNoDifference(profile.profileCount, 2)

    let currentProfile = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(["examples", "mobile-chat", "profile", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(currentProfile.event, "profile")
    expectNoDifference(currentProfile.selectedUserID, "user-cli")
    expectNoDifference(currentProfile.selectedProfile?.displayName, "CLI User")

    let profiledSend = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "mobile-chat", "post", generalChannelID,
            "Hello from mobile chat", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(profiledSend.event, "send")
    expectNoDifference(profiledSend.selectedChannelID, generalChannelID)
    let profiledMessageID = try #require(profiledSend.changedID)
    let profiledMessage = try #require(
      profiledSend.messages.first { $0.id == profiledMessageID }
    )
    expectNoDifference(profiledMessage.channelID, generalChannelID)
    expectNoDifference(profiledMessage.author?.displayName, "CLI User")
    expectNoDifference(profiledMessage.authorUser?.id, "user-cli")
    expectNoDifference(profiledMessage.content, "Hello from mobile chat")
    expectNoDifference(profiledSend.messages.count, 3)

    let joined = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(["examples", "mobile-chat", "join", generalChannelID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(joined.event, "join")
    expectNoDifference(joined.changedID, "user-cli")
    expectNoDifference(joined.presenceRoom, InstantRoomHandle(type: "chat", id: generalChannelID))
    expectNoDifference(joined.presenceMemberCount, 1)
    expectNoDifference(joined.presenceMembers.first?.values["profileId"], .string("user-cli"))
    expectNoDifference(joined.presenceMembers.first?.values["displayName"], .string("CLI User"))

    let presence = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          ["examples", "mobile-chat", "presence", generalChannelID, "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(presence.event, "presence")
    expectNoDifference(presence.presenceMemberCount, 1)

    let jsonlOutput = try runCLI(
      ["examples", "mobile-chat", "messages", generalChannelID, "--jsonl"],
      homeURL: homeURL
    )
    let jsonlLines = jsonlOutput.split(separator: "\n")
    let summary = try JSONDecoder().decode(
      CLIMobileChatEvidence.self,
      from: Data(try #require(jsonlLines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.examples.mobile-chat")
    expectNoDifference(summary.event, "messages")
    expectNoDifference(summary.details.selectedChannelID, generalChannelID)
    expectNoDifference(summary.details.messageCount, 3)
    expectNoDifference(summary.details.presenceMemberCount, 1)
    let eventRows = try jsonlLines.dropFirst().map {
      try JSONDecoder().decode(CLIMobileChatEventEnvelope.self, from: Data($0.utf8))
    }
    expectNoDifference(eventRows.filter { $0.event == "user" }.count, 2)
    expectNoDifference(eventRows.filter { $0.event == "profile" }.count, 2)
    expectNoDifference(eventRows.filter { $0.event == "channel" }.count, 2)
    expectNoDifference(eventRows.filter { $0.event == "message" }.count, 3)
    expectNoDifference(eventRows.filter { $0.event == "presence" }.count, 1)

    let left = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(["examples", "mobile-chat", "leave", generalChannelID, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(left.event, "leave")
    expectNoDifference(left.changedID, "user-cli")
    expectNoDifference(left.presenceMemberCount, 0)
    expectNoDifference(left.presenceMembers, [])

    let missingChannel = try runCLIResult(
      ["examples", "mobile-chat", "send", "missing-channel", "Hello", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingChannel.status, 66)
    #expect(missingChannel.error.contains("Mobile chat channel not found: missing-channel"))

    let reset = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(["examples", "mobile-chat", "reset", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.userCount, 0)
    expectNoDifference(reset.profileCount, 0)
    expectNoDifference(reset.channelCount, 0)
    expectNoDifference(reset.messageCount, 0)
    expectNoDifference(reset.users, [])
    expectNoDifference(reset.profiles, [])
    expectNoDifference(reset.channels, [])
    expectNoDifference(reset.messages, [])
  }

  @Test
  func cliMobileChatMagicCodeProfilesPreserveAuthorEmail() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let seeded = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(try runCLI(["examples", "mobile-chat", "seed", "--json"], homeURL: homeURL).utf8)
    )
    let generalChannelID = try #require(
      seeded.channels.first { $0.name == "general" }?.id
    )

    let challenge = try JSONDecoder().decode(
      CLIMagicCodeOutput.self,
      from: Data(
        try runCLI(
          ["auth", "magic-code", "send", "User@Example.com", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(challenge.email, "user@example.com")
    let verified = try JSONDecoder().decode(
      CLIAuthOutput.self,
      from: Data(
        try runCLI(
          [
            "auth", "magic-code", "verify", "user@example.com",
            challenge.localVerificationCode, "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(verified.userID, "email:user@example.com")
    expectNoDifference(verified.isGuest, false)

    let profile = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          ["examples", "mobile-chat", "setup-profile", "Email User", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(profile.selectedProfile?.userID, "email:user@example.com")
    let emailUser = try #require(profile.users.first { $0.id == "email:user@example.com" })
    expectNoDifference(emailUser.email, "user@example.com")

    let sent = try JSONDecoder().decode(
      CLIMobileChatOutput.self,
      from: Data(
        try runCLI(
          [
            "examples", "mobile-chat", "send", generalChannelID,
            "Hello from email auth", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    let messageID = try #require(sent.changedID)
    let message = try #require(sent.messages.first { $0.id == messageID })
    expectNoDifference(message.author?.displayName, "Email User")
    expectNoDifference(message.authorUser?.id, "email:user@example.com")
    expectNoDifference(message.authorUser?.email, "user@example.com")
  }

  @Test
  func cliStroopwafelExampleRunsTwoUserRoomAndGameAcrossLaunches() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let signedOutCreate = try runCLIResult(
      ["examples", "stroopwafel", "create-room", "AB12", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(signedOutCreate.status, 65)
    #expect(signedOutCreate.error.contains("Stroopwafel create a room requires a signed-in user."))

    _ = try runCLI(
      ["auth", "token", "host-refresh", "--user-id", "user-host", "--json"],
      homeURL: homeURL
    )
    let hostProfile = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "setup-profile", "Host123", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(hostProfile.event, "setup-profile")
    expectNoDifference(hostProfile.selectedUser?.handle, "Host123")
    expectNoDifference(hostProfile.authUserID, "user-host")
    let hostCreatedAt = try #require(hostProfile.selectedUser?.createdAt)

    let highScore = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "score", "7", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(highScore.selectedUser?.highScore, 7)

    let renamedHost = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "setup-profile", "HostRenamed", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(renamedHost.selectedUser?.handle, "HostRenamed")
    expectNoDifference(renamedHost.selectedUser?.highScore, 7)
    expectNoDifference(renamedHost.selectedUser?.createdAt, hostCreatedAt)

    let room = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "create-room", "ab12", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(room.event, "create-room")
    expectNoDifference(room.selectedRoomCode, "AB12")
    expectNoDifference(room.selectedRoom?.hostID, "user-host")
    expectNoDifference(room.selectedRoom?.users.map(\.id), ["user-host"])

    _ = try runCLI(
      ["auth", "token", "guest-refresh", "--user-id", "user-guest", "--json"],
      homeURL: homeURL
    )
    let guestProfile = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "setup-profile", "Guest123", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(guestProfile.selectedUser?.handle, "Guest123")

    let joined = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(try runCLI(["examples", "stroopwafel", "join", "AB12", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(joined.event, "join")
    expectNoDifference(joined.selectedRoom?.users.map(\.id), ["user-guest", "user-host"])

    let ready = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(try runCLI(["examples", "stroopwafel", "ready", "AB12", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(ready.event, "ready")
    expectNoDifference(ready.selectedRoom?.readyIDs, ["user-guest"])

    let guestStart = try runCLIResult(
      ["examples", "stroopwafel", "start", "AB12", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(guestStart.status, 77)
    #expect(guestStart.error.contains("must host Stroopwafel room AB12"))

    _ = try runCLI(
      ["auth", "token", "host-refresh", "--user-id", "user-host", "--json"],
      homeURL: homeURL
    )
    let started = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(try runCLI(["examples", "stroopwafel", "start", "AB12", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(started.event, "start")
    let gameID = try #require(started.selectedGameID)
    let game = try #require(started.selectedGame)
    expectNoDifference(game.status, StroopwafelExample.gameInProgress)
    expectNoDifference(game.playerIDs.sorted(), ["user-guest", "user-host"])
    expectNoDifference(game.points.count, 2)
    expectNoDifference(started.selectedRoom?.currentGameID, gameID)

    let jsonlOutput = try runCLI(["examples", "stroopwafel", "games", "--jsonl"], homeURL: homeURL)
    let jsonlLines = jsonlOutput.split(separator: "\n")
    let summary = try JSONDecoder().decode(
      CLIStroopwafelEvidence.self,
      from: Data(try #require(jsonlLines.first).utf8)
    )
    expectNoDifference(summary.caseID, "cli.examples.stroopwafel")
    expectNoDifference(summary.event, "games")
    expectNoDifference(summary.details.gameCount, 1)
    expectNoDifference(summary.details.pointCount, 2)

    _ = try runCLI(
      ["auth", "token", "guest-refresh", "--user-id", "user-guest", "--json"],
      homeURL: homeURL
    )
    let label = try #require(game.colors.first?.label)
    let tapped = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "tap", gameID, label, "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(tapped.event, "tap")
    let guestPoint = try #require(tapped.selectedGame?.points.first { $0.userID == "user-guest" })
    expectNoDifference(guestPoint.value, 1)

    let roomStatus = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(try runCLI(["examples", "stroopwafel", "room", "AB12", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(roomStatus.selectedRoom?.currentGameID, gameID)
    expectNoDifference(roomStatus.roomCount, 1)
    expectNoDifference(roomStatus.gameCount, 1)

    let reset = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(try runCLI(["examples", "stroopwafel", "reset", "--json"], homeURL: homeURL).utf8)
    )
    expectNoDifference(reset.event, "reset")
    expectNoDifference(reset.userCount, 2)
    expectNoDifference(reset.roomCount, 0)
    expectNoDifference(reset.gameCount, 0)
    expectNoDifference(reset.pointCount, 0)
  }

  @Test
  func cliStroopwafelMagicCodeProfilePreservesEmail() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let challenge = try JSONDecoder().decode(
      CLIMagicCodeOutput.self,
      from: Data(
        try runCLI(
          ["auth", "magic-code", "send", "Stroop@Example.com", "--json"],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(challenge.email, "stroop@example.com")
    _ = try runCLI(
      [
        "auth", "magic-code", "verify", "stroop@example.com",
        challenge.localVerificationCode, "--json",
      ],
      homeURL: homeURL
    )

    let profile = try JSONDecoder().decode(
      CLIStroopwafelOutput.self,
      from: Data(
        try runCLI(["examples", "stroopwafel", "setup-profile", "Wafel123", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(profile.authUserID, "email:stroop@example.com")
    let user = try #require(profile.users.first { $0.id == "email:stroop@example.com" })
    expectNoDifference(user.email, "stroop@example.com")
    expectNoDifference(user.handle, "Wafel123")
  }

  @Test
  func cliMicroblogExampleReportsMalformedArguments() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let empty = try runCLIResult(["examples", "microblog", "--json"], homeURL: homeURL)
    expectNoDifference(empty.status, 64)
    #expect(empty.error.contains("examples microblog <seed|feed|profiles|profile|setup-profile"))

    let badPost = try runCLIResult(
      ["examples", "microblog", "post", "--surprise", "Hello", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badPost.status, 64)
    #expect(badPost.error.contains("Unknown microblog post option: --surprise."))

    let missingLikeID = try runCLIResult(
      ["examples", "microblog", "like", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingLikeID.status, 64)
    #expect(missingLikeID.error.contains("examples microblog like <post-id>"))

    let unknown = try runCLIResult(
      ["examples", "microblog", "dance", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(unknown.status, 64)
    #expect(unknown.error.contains("Unknown microblog command: dance"))

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMobileChatExampleReportsMalformedArguments() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let empty = try runCLIResult(["examples", "mobile-chat", "--json"], homeURL: homeURL)
    expectNoDifference(empty.status, 64)
    #expect(empty.error.contains("examples mobile-chat <seed|channels|messages|profiles"))

    let badSend = try runCLIResult(
      ["examples", "mobile-chat", "send", "channel-1", "--surprise", "Hello", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badSend.status, 64)
    #expect(badSend.error.contains("Unknown mobile chat send option: --surprise."))

    let missingJoinChannel = try runCLIResult(
      ["examples", "mobile-chat", "join", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingJoinChannel.status, 64)
    #expect(missingJoinChannel.error.contains("examples mobile-chat join <channel-id>"))

    let unknown = try runCLIResult(
      ["examples", "mobile-chat", "dance", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(unknown.status, 64)
    #expect(unknown.error.contains("Unknown mobile chat command: dance"))

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliMalformedStroopwafelArgumentsDoNotBootstrapState() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let empty = try runCLIResult(["examples", "stroopwafel", "--json"], homeURL: homeURL)
    expectNoDifference(empty.status, 64)
    #expect(empty.error.contains("examples stroopwafel <setup-profile|profile|score"))

    let badColor = try runCLIResult(
      ["examples", "stroopwafel", "tap", "game-1", "purple", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badColor.status, 64)
    #expect(badColor.error.contains("Invalid Stroopwafel color: purple."))

    let badScore = try runCLIResult(
      ["examples", "stroopwafel", "score", "-1", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(badScore.status, 64)
    #expect(badScore.error.contains("Invalid Stroopwafel score: -1."))

    let missingJoinCode = try runCLIResult(
      ["examples", "stroopwafel", "join", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(missingJoinCode.status, 64)
    #expect(missingJoinCode.error.contains("examples stroopwafel join <code>"))

    let unknown = try runCLIResult(
      ["examples", "stroopwafel", "dance", "--json"],
      homeURL: homeURL
    )
    expectNoDifference(unknown.status, 64)
    #expect(unknown.error.contains("Unknown Stroopwafel command: dance"))

    expectNoDifference(
      try FileManager.default.contentsOfDirectory(atPath: homeURL.path),
      []
    )
  }

  @Test
  func cliValidationLocalTodosEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLILocalTodoValidationOutput.self,
      from: Data(
        try runCLI(["validation", "local-todos", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "local-todos")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 8)
    expectNoDifference(
      jsonOutput.events,
      [
        "seed", "update", "cache", "reset", "relaunch", "offline-write",
        "offline-relaunch", "reconnect-flush",
      ]
    )
    expectNoDifference(jsonOutput.finalTodoCount, 1)
    expectNoDifference(jsonOutput.pendingMutationCount, 0)

    let jsonlOutput = try runCLI(["validation", "local-todos", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 8)
    let firstEvidence = try JSONDecoder().decode(
      CLILocalTodoValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(firstEvidence.caseID, "validation.local.todos")
    expectNoDifference(firstEvidence.appID, "cli-cache-test")
    expectNoDifference(firstEvidence.event, "seed")
    expectNoDifference(firstEvidence.details.todoTexts.count, 3)

    let offlineRelaunchEvidence = try JSONDecoder().decode(
      CLILocalTodoValidationEvidence.self,
      from: Data(lines[6].utf8)
    )
    expectNoDifference(offlineRelaunchEvidence.event, "offline-relaunch")
    expectNoDifference(offlineRelaunchEvidence.details.connectionState, "closed")
    expectNoDifference(
      offlineRelaunchEvidence.details.todoTexts,
      ["Validate restart restore while closed"]
    )
    expectNoDifference(offlineRelaunchEvidence.details.pendingMutationIDs.count, 4)

    let reconnectFlushEvidence = try JSONDecoder().decode(
      CLILocalTodoValidationEvidence.self,
      from: Data(lines[7].utf8)
    )
    expectNoDifference(reconnectFlushEvidence.event, "reconnect-flush")
    expectNoDifference(reconnectFlushEvidence.details.connectionState, "opened")
    expectNoDifference(reconnectFlushEvidence.details.pendingMutationIDs, [])
    expectNoDifference(reconnectFlushEvidence.details.confirmedMutationIDs.count, 4)

    let humanOutput = try runCLI(["validation", "local-todos"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("evidence rows: 8"))

    let defaultAppIDHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: defaultAppIDHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: defaultAppIDHomeURL) }
    let defaultAppIDOutput = try JSONDecoder().decode(
      CLILocalTodoValidationOutput.self,
      from: Data(
        try runCLI(
          ["validation", "local-todos", "--json"],
          homeURL: defaultAppIDHomeURL,
          environment: ["INSTANT_APP_ID": nil]
        ).utf8
      )
    )
    expectNoDifference(defaultAppIDOutput.appID, "local-demo")

    let malformed = try runCLIResult(["validation", "remote", "--json"], homeURL: homeURL)
    #expect(malformed.status == 64)
    #expect(
      malformed.error.contains(
        "validation <local-todos|local-integrations|reminders|typed-drafts|platform-adapters|syncups-recording|parity-report|coverage>"
      )
    )
  }

  @Test
  func cliValidationLocalIntegrationsEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLILocalIntegrationValidationOutput.self,
      from: Data(
        try runCLI(["validation", "local-integrations", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "local-integrations")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 9)
    expectNoDifference(
      jsonOutput.events,
      [
        "auth", "room-presence", "room-topic", "file", "stream", "share-create",
        "share-accept", "share-revoke", "relaunch",
      ]
    )
    expectNoDifference(jsonOutput.authUserID, "user-1")
    expectNoDifference(jsonOutput.roomMemberCount, 1)
    expectNoDifference(jsonOutput.topicMessageCount, 1)
    expectNoDifference(jsonOutput.fileCount, 1)
    expectNoDifference(jsonOutput.streamChunkCount, 1)
    expectNoDifference(jsonOutput.activeShareCount, 0)
    expectNoDifference(jsonOutput.revokedShareCount, 1)

    let jsonlOutput = try runCLI(["validation", "local-integrations", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 9)
    let firstEvidence = try JSONDecoder().decode(
      CLILocalIntegrationValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(firstEvidence.caseID, "validation.local.integrations")
    expectNoDifference(firstEvidence.appID, "cli-cache-test")
    expectNoDifference(firstEvidence.event, "auth")
    expectNoDifference(firstEvidence.details.authUserID, "user-1")

    let fileEvidence = try JSONDecoder().decode(
      CLILocalIntegrationValidationEvidence.self,
      from: Data(lines[3].utf8)
    )
    expectNoDifference(fileEvidence.event, "file")
    expectNoDifference(fileEvidence.details.fileIDs.count, 1)
    expectNoDifference(fileEvidence.details.fileByteCounts, [23])
    expectNoDifference(fileEvidence.details.fileContentDigests.count, 1)

    let revokeEvidence = try JSONDecoder().decode(
      CLILocalIntegrationValidationEvidence.self,
      from: Data(lines[7].utf8)
    )
    expectNoDifference(revokeEvidence.event, "share-revoke")
    expectNoDifference(revokeEvidence.details.activeShareIDs, [])
    expectNoDifference(revokeEvidence.details.revokedShareIDs.count, 1)
    expectNoDifference(revokeEvidence.details.shareMemberUserIDs, ["user-1", "user-2"])

    let relaunchEvidence = try JSONDecoder().decode(
      CLILocalIntegrationValidationEvidence.self,
      from: Data(lines[8].utf8)
    )
    expectNoDifference(relaunchEvidence.event, "relaunch")
    expectNoDifference(relaunchEvidence.details.fileContentDigests, fileEvidence.details.fileContentDigests)

    let humanOutput = try runCLI(["validation", "local-integrations"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("case: validation.local.integrations"))
    #expect(humanOutput.contains("evidence rows: 9"))
    #expect(humanOutput.contains("revoked shares: 1"))
  }

  @Test
  func cliValidationRemindersEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLIRemindersValidationOutput.self,
      from: Data(
        try runCLI(["validation", "reminders", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "reminders")
    expectNoDifference(jsonOutput.transport, "not-implemented-local-cache-only")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 9)
    expectNoDifference(
      jsonOutput.events,
      [
        "seed",
        "search-tags",
        "rich-filters",
        "edit-rich-fields",
        "complete",
        "reader-rejection",
        "writer-update",
        "demoted-reader-rejection",
        "relaunch",
      ]
    )
    expectNoDifference(jsonOutput.listCount, 1)
    expectNoDifference(jsonOutput.reminderCount, 1)
    expectNoDifference(jsonOutput.completedReminderCount, 1)
    expectNoDifference(jsonOutput.tagCount, 1)
    expectNoDifference(jsonOutput.activeShareCount, 1)
    expectNoDifference(jsonOutput.pendingMutationCount, 6)
    expectNoDifference(
      jsonOutput.rejectedOperations,
      [
        "reader-update:permissionRejected:remindersLists:validation-reminders-list",
        "demoted-reader-add-tag:permissionRejected:remindersLists:validation-reminders-list",
      ]
    )
    expectNoDifference(
      jsonOutput.stats,
      RemindersStats(allCount: 1, completedCount: 1, flaggedCount: 0, scheduledCount: 0, todayCount: 0)
    )

    let jsonlOutput = try runCLI(["validation", "local-reminders", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 9)
    let searchEvidence = try JSONDecoder().decode(
      CLIRemindersValidationEvidence.self,
      from: Data(try #require(lines.first { $0.contains("\"event\":\"search-tags\"") }).utf8)
    )
    expectNoDifference(searchEvidence.caseID, "validation.reminders")
    expectNoDifference(searchEvidence.appID, "cli-cache-test")
    expectNoDifference(searchEvidence.event, "search-tags")
    expectNoDifference(searchEvidence.ok, true)
    expectNoDifference(searchEvidence.details.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(searchEvidence.details.tagTitles, ["family"])

    let editEvidence = try JSONDecoder().decode(
      CLIRemindersValidationEvidence.self,
      from: Data(try #require(lines.first { $0.contains("\"event\":\"edit-rich-fields\"") }).utf8)
    )
    expectNoDifference(editEvidence.details.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(editEvidence.details.reminderTitles, ["Pack lunch and snacks"])
    expectNoDifference(editEvidence.details.reminderNotes, ["Updated through validation"])
    expectNoDifference(editEvidence.details.reminderTagIDs, ["validation-reminders-pack-lunch#family"])

    let readerEvidence = try JSONDecoder().decode(
      CLIRemindersValidationEvidence.self,
      from: Data(try #require(lines.first { $0.contains("\"event\":\"reader-rejection\"") }).utf8)
    )
    expectNoDifference(
      readerEvidence.details.rejectedOperations,
      ["reader-update:permissionRejected:remindersLists:validation-reminders-list"]
    )

    let humanOutput = try runCLI(["validation", "reminders"], homeURL: homeURL)
    #expect(humanOutput.contains("case: validation.reminders"))
    #expect(humanOutput.contains("events: seed, search-tags"))
    #expect(humanOutput.contains("rejections: reader-update:permissionRejected"))
  }

  @Test
  func cliValidationTypedDraftsEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLIDraftValidationOutput.self,
      from: Data(
        try runCLI(["validation", "typed-drafts", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "typed-drafts")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 4)
    expectNoDifference(jsonOutput.events, ["create", "edit", "relation", "relaunch"])
    expectNoDifference(jsonOutput.newDraftIDWasNil, true)
    expectNoDifference(
      jsonOutput.newDraftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(jsonOutput.newDraftIncludedPrimaryKeyAssignment, false)
    expectNoDifference(
      jsonOutput.draftTodoAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(jsonOutput.draftTodoTitles, ["Edit from generated draft"])
    expectNoDifference(jsonOutput.draftTodoCompletionStates, [true])
    expectNoDifference(jsonOutput.draftTodoNotes, ["Edited through Draft(existing)"])
    expectNoDifference(jsonOutput.draftAuthorNames, ["Draft relation author"])
    expectNoDifference(
      jsonOutput.draftPostAttributeIDs,
      [
        "draftValidationPosts/title",
        "draftValidationPosts/author",
      ]
    )
    expectNoDifference(jsonOutput.draftPostTitles, ["Post from relation draft"])
    expectNoDifference(jsonOutput.draftPostAuthorIDs, jsonOutput.draftAuthorIDs)
    expectNoDifference(jsonOutput.draftPostAuthorAttributeValueType, "ref")
    expectNoDifference(jsonOutput.draftPostAuthorLinkNamespace, "draftValidationAuthors")
    expectNoDifference(jsonOutput.draftPostAuthorForwardIdentity, "draftValidationPosts/author")
    expectNoDifference(jsonOutput.draftPostAuthorReverseIdentity, "draftValidationAuthors/posts")
    expectNoDifference(jsonOutput.pendingMutationCount, 4)
    expectNoDifference(jsonOutput.createdID, jsonOutput.editedID)
    expectNoDifference(jsonOutput.relationAuthorID, jsonOutput.draftAuthorIDs.first)
    expectNoDifference(jsonOutput.relationPostID, jsonOutput.draftPostIDs.first)
    let createdID = try #require(jsonOutput.createdID)
    let relationAuthorID = try #require(jsonOutput.relationAuthorID)
    let relationPostID = try #require(jsonOutput.relationPostID)
    let createMutation = try #require(
      jsonOutput.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.create"
      }
    )
    expectNoDifference(createMutation.status, "pending")
    expectNoDifference(createMutation.transactionID, "validation.typed-drafts.create")
    expectNoDifference(
      createMutation.operationKinds,
      ["requireEntityMissing", "insert", "insert", "insert", "insert", "insert"]
    )
    expectNoDifference(createMutation.txStepKinds, Array(repeating: "add-triple", count: 5))
    expectNoDifference(createMutation.preconditionKinds, ["entity-missing"])
    expectNoDifference(createMutation.preconditionNamespaces, ["draftValidationTodos"])
    expectNoDifference(
      createMutation.txStepAttributeIDs,
      [
        "draftValidationTodos/id",
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(createMutation.txStepEntityIDs, Array(repeating: createdID, count: 5))
    expectNoDifference(createMutation.txStepValueTypes, ["string", "string", "boolean", "string", "null"])
    expectNoDifference(
      Array(createMutation.txStepValueSummaries[0...2]),
      ["string:\(createdID)", "string:Create from generated draft", "boolean:false"]
    )
    expectNoDifference(createMutation.txStepValueSummaries.last, "null")
    expectNoDifference(createMutation.operationValueTypes, ["string", "string", "boolean", "date", "null"])
    expectNoDifference(createMutation.txStepOptionModes, Array(repeating: "create", count: 5))
    expectNoDifference(createMutation.primaryKeyStepCount, 1)
    expectNoDifference(
      createMutation.draftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )

    let editMutation = try #require(
      jsonOutput.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.edit"
      }
    )
    expectNoDifference(editMutation.preconditionKinds, [])
    expectNoDifference(editMutation.transactionID, "validation.typed-drafts.edit")
    expectNoDifference(editMutation.txStepKinds, Array(repeating: "add-triple", count: 5))
    expectNoDifference(editMutation.txStepEntityIDs, Array(repeating: createdID, count: 5))
    expectNoDifference(editMutation.txStepOptionModes, Array(repeating: "none", count: 5))
    expectNoDifference(
      editMutation.txStepValueSummaries,
      [
        "string:\(createdID)",
        "string:Edit from generated draft",
        "boolean:true",
        createMutation.txStepValueSummaries[3],
        "string:Edited through Draft(existing)",
      ]
    )
    expectNoDifference(
      editMutation.operationValueSummaries,
      [
        "string:\(createdID)",
        "string:Edit from generated draft",
        "boolean:true",
        createMutation.operationValueSummaries[3],
        "string:Edited through Draft(existing)",
      ]
    )

    let postMutation = try #require(
      jsonOutput.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.post"
      }
    )
    expectNoDifference(postMutation.transactionID, "validation.typed-drafts.post")
    expectNoDifference(postMutation.txStepKinds, Array(repeating: "add-triple", count: 3))
    expectNoDifference(postMutation.txStepEntityIDs, Array(repeating: relationPostID, count: 3))
    expectNoDifference(
      postMutation.txStepAttributeIDs,
      [
        "draftValidationPosts/id",
        "draftValidationPosts/title",
        "draftValidationPosts/author",
      ]
    )
    expectNoDifference(postMutation.txStepValueTypes, ["string", "string", "string"])
    expectNoDifference(postMutation.operationValueTypes, ["string", "string", "ref"])
    expectNoDifference(
      postMutation.operationValueSummaries,
      [
        "string:\(relationPostID)",
        "string:Post from relation draft",
        "ref:\(relationAuthorID)",
      ]
    )
    expectNoDifference(postMutation.refAttributeIDs, ["draftValidationPosts/author"])

    let jsonlOutput = try runCLI(["validation", "typed-drafts", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 4)
    let createEvidence = try JSONDecoder().decode(
      CLIDraftValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(createEvidence.caseID, "validation.typed.drafts")
    expectNoDifference(createEvidence.appID, "cli-cache-test")
    expectNoDifference(createEvidence.event, "create")
    expectNoDifference(createEvidence.details.newDraftIDWasNil, true)
    expectNoDifference(
      createEvidence.details.newDraftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(createEvidence.details.newDraftIncludedPrimaryKeyAssignment, false)
    expectNoDifference(
      createEvidence.details.draftTodoAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(createEvidence.details.draftTodoTitles, ["Create from generated draft"])
    expectNoDifference(createEvidence.details.draftTodoCompletionStates, [false])
    expectNoDifference(createEvidence.details.draftTodoNotes, [nil])

    let relationEvidence = try JSONDecoder().decode(
      CLIDraftValidationEvidence.self,
      from: Data(lines[2].utf8)
    )
    expectNoDifference(relationEvidence.event, "relation")
    expectNoDifference(relationEvidence.details.draftAuthorNames, ["Draft relation author"])
    expectNoDifference(relationEvidence.details.draftPostTitles, ["Post from relation draft"])
    expectNoDifference(
      relationEvidence.details.draftPostAuthorIDs,
      relationEvidence.details.draftAuthorIDs
    )
    expectNoDifference(relationEvidence.details.draftPostAuthorAttributeValueType, "ref")
    expectNoDifference(
      relationEvidence.details.draftPostAuthorLinkNamespace,
      "draftValidationAuthors"
    )
    expectNoDifference(
      relationEvidence.details.draftPostAuthorForwardIdentity,
      "draftValidationPosts/author"
    )
    expectNoDifference(
      relationEvidence.details.draftPostAuthorReverseIdentity,
      "draftValidationAuthors/posts"
    )
    expectNoDifference(
      relationEvidence.details.relationAuthorID,
      relationEvidence.details.draftAuthorIDs.first
    )
    expectNoDifference(
      relationEvidence.details.relationPostID,
      relationEvidence.details.draftPostIDs.first
    )
    expectNoDifference(relationEvidence.entityID, relationEvidence.details.relationPostID)
    expectNoDifference(
      relationEvidence.details.draftMutationSummaries.map(\.mutationID).sorted(),
      [
        "validation.typed-drafts.author",
        "validation.typed-drafts.create",
        "validation.typed-drafts.edit",
        "validation.typed-drafts.post",
      ]
    )

    let relaunchEvidence = try JSONDecoder().decode(
      CLIDraftValidationEvidence.self,
      from: Data(lines[3].utf8)
    )
    expectNoDifference(relaunchEvidence.event, "relaunch")
    expectNoDifference(relaunchEvidence.details.draftTodoTitles, ["Edit from generated draft"])
    expectNoDifference(relaunchEvidence.details.draftTodoCompletionStates, [true])
    expectNoDifference(relaunchEvidence.details.draftPostTitles, ["Post from relation draft"])
    expectNoDifference(
      relaunchEvidence.details.pendingMutationIDs.sorted(),
      [
        "validation.typed-drafts.author",
        "validation.typed-drafts.create",
        "validation.typed-drafts.edit",
        "validation.typed-drafts.post",
      ]
    )
    expectNoDifference(relaunchEvidence.details.createdID, relaunchEvidence.details.editedID)
    expectNoDifference(
      relaunchEvidence.details.relationAuthorID,
      relaunchEvidence.details.draftAuthorIDs.first
    )
    expectNoDifference(
      relaunchEvidence.details.relationPostID,
      relaunchEvidence.details.draftPostIDs.first
    )

    let humanOutput = try runCLI(["validation", "typed-drafts"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("case: validation.typed.drafts"))
    #expect(humanOutput.contains("evidence rows: 4"))
    #expect(humanOutput.contains("new draft id omitted: true"))
    #expect(humanOutput.contains("new draft assignments: draftValidationTodos/title"))
    #expect(humanOutput.contains("draft post ids:"))
    #expect(humanOutput.contains("draft post author relation: ref draftValidationAuthors"))
    #expect(humanOutput.contains("draft create mutation: entity-missing"))
  }

  @Test
  func cliValidationPlatformAdaptersEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLIPlatformAdapterValidationOutput.self,
      from: Data(
        try runCLI(["validation", "platform-adapters", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "platform-adapters")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 21)
    expectNoDifference(jsonOutput.events, [
      "fetch-all",
      "fetch-one",
      "fetch",
      "local-id",
      "auth-session",
      "room-presence",
      "room-topic-messages",
      "stored-files",
      "stream-chunks",
      "shares",
      "projected-bindings",
      "fetch-all-filtered-reload",
      "fetch-all-dynamic-query",
      "fetch-one-dynamic-query",
      "fetch-request-dynamic-query",
      "fetch-all-nil-query",
      "fetch-one-nil-query",
      "fetch-request-nil-request",
      "fetch-all-cached-prior-error",
      "fetch-all-cancellation",
      "fetch-request-cancellation",
    ])
    expectNoDifference(jsonOutput.adapters, [
      "@FetchAll",
      "@FetchOne",
      "@Fetch",
      "@LocalID",
      "@AuthSession",
      "@RoomPresence",
      "@RoomTopicMessages",
      "@StoredFiles",
      "@StreamChunks",
      "@Shares",
      "Projected bindings",
      "@FetchAll/@Fetch(filtered)",
      "@FetchAll(dynamic)",
      "@FetchOne(dynamic)",
      "@Fetch(request dynamic)",
      "@FetchAll(nil)",
      "@FetchOne(nil)",
      "@Fetch(request nil)",
      "@FetchAll(error)",
      "@FetchAll(cancellation)",
      "@Fetch(request cancellation)",
    ])
    expectNoDifference(jsonOutput.bindingAdapterCount, 10)
    expectNoDifference(jsonOutput.bindingAdapters, [
      "@FetchAll",
      "@FetchOne",
      "@Fetch",
      "@LocalID",
      "@AuthSession",
      "@RoomPresence",
      "@RoomTopicMessages",
      "@StoredFiles",
      "@StreamChunks",
      "@Shares",
    ])
    expectNoDifference(jsonOutput.todoCount, 1)
    expectNoDifference(jsonOutput.authUserID, "adapter-user")
    expectNoDifference(jsonOutput.roomMemberCount, 1)
    expectNoDifference(jsonOutput.topicMessageCount, 1)
    expectNoDifference(jsonOutput.fileCount, 1)
    expectNoDifference(jsonOutput.streamChunkCount, 1)
    expectNoDifference(jsonOutput.shareCount, 1)
    expectNoDifference(jsonOutput.lifecycleEventCount, 10)
    expectNoDifference(jsonOutput.queryProbeCount, 16)
    expectNoDifference(jsonOutput.observationProbeCount, 2)
    expectNoDifference(jsonOutput.loadErrorOperations, ["query dynamic FetchAll"])
    expectNoDifference(jsonOutput.cancellationTerminated, true)
    #expect(jsonOutput.selectedTodoID != nil)
    #expect(jsonOutput.localID != nil)

    let jsonlOutput = try runCLI(["validation", "wrappers", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 21)
    let fetchEvidence = try JSONDecoder().decode(
      CLIPlatformAdapterValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(fetchEvidence.caseID, "validation.platform.adapters")
    expectNoDifference(fetchEvidence.appID, "cli-cache-test")
    expectNoDifference(fetchEvidence.event, "fetch-all")
    expectNoDifference(fetchEvidence.details.adapter, "@FetchAll")
    expectNoDifference(fetchEvidence.details.todoTitles, ["Bind public adapter wrappers"])
    expectNoDifference(fetchEvidence.details.todoCount, 1)

    let evidenceRows = try lines.map {
      try JSONDecoder().decode(
        CLIPlatformAdapterValidationEvidence.self,
        from: Data($0.utf8)
      )
    }
    let shareEvidence = try #require(evidenceRows.first { $0.event == "shares" })
    expectNoDifference(shareEvidence.event, "shares")
    expectNoDifference(shareEvidence.details.adapter, "@Shares")
    expectNoDifference(shareEvidence.details.authUserID, "adapter-user")
    expectNoDifference(shareEvidence.details.shareIDs.count, 1)

    let projectedBindingsEvidence = try #require(
      evidenceRows.first { $0.event == "projected-bindings" }
    )
    expectNoDifference(projectedBindingsEvidence.details.adapter, "Projected bindings")
    expectNoDifference(projectedBindingsEvidence.details.bindingAdapters, [
      "@FetchAll",
      "@FetchOne",
      "@Fetch",
      "@LocalID",
      "@AuthSession",
      "@RoomPresence",
      "@RoomTopicMessages",
      "@StoredFiles",
      "@StreamChunks",
      "@Shares",
    ])
    expectNoDifference(projectedBindingsEvidence.details.todoTitles, [
      "Bind public adapter wrappers"
    ])
    expectNoDifference(projectedBindingsEvidence.details.todoCount, 1)
    expectNoDifference(projectedBindingsEvidence.details.authUserID, "adapter-user")
    expectNoDifference(projectedBindingsEvidence.details.roomMemberIDs, ["adapter-user"])
    expectNoDifference(projectedBindingsEvidence.details.topicMessageIDs.count, 1)
    expectNoDifference(projectedBindingsEvidence.details.fileIDs.count, 1)
    expectNoDifference(projectedBindingsEvidence.details.streamChunkIDs.count, 1)
    expectNoDifference(projectedBindingsEvidence.details.shareIDs.count, 1)

    let filteredReloadEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-all-filtered-reload" }
    )
    expectNoDifference(filteredReloadEvidence.details.adapter, "@FetchAll/@Fetch(filtered)")
    expectNoDifference(
      filteredReloadEvidence.details.fetchAllTitleBatches ?? [],
      [[], ["Engineering"], [], ["Engineering"]]
    )
    expectNoDifference(
      filteredReloadEvidence.details.fetchTitleBatches ?? [],
      [[], ["Engineering"], [], ["Engineering"]]
    )

    let fetchOneDynamicEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-one-dynamic-query" }
    )
    expectNoDifference(fetchOneDynamicEvidence.details.adapter, "@FetchOne(dynamic)")
    expectNoDifference(fetchOneDynamicEvidence.details.previousTodoTitles, ["Open single"])
    expectNoDifference(fetchOneDynamicEvidence.details.todoTitles, ["Done single"])
    expectNoDifference(fetchOneDynamicEvidence.details.selectedTodoTitle, "Done single")
    expectNoDifference(fetchOneDynamicEvidence.details.queryCount, 2)

    let fetchRequestDynamicEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-request-dynamic-query" }
    )
    expectNoDifference(fetchRequestDynamicEvidence.details.adapter, "@Fetch(request dynamic)")
    expectNoDifference(fetchRequestDynamicEvidence.details.previousTodoTitles, ["Open request"])
    expectNoDifference(fetchRequestDynamicEvidence.details.todoTitles, ["Done request"])
    expectNoDifference(fetchRequestDynamicEvidence.details.todoCount, 2)
    expectNoDifference(fetchRequestDynamicEvidence.details.queryCount, 4)

    let fetchOneNilEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-one-nil-query" }
    )
    expectNoDifference(fetchOneNilEvidence.details.adapter, "@FetchOne(nil)")
    expectNoDifference(fetchOneNilEvidence.details.previousTodoTitles, ["Cached optional nil query"])
    expectNoDifference(fetchOneNilEvidence.details.todoTitles, [])
    expectNoDifference(fetchOneNilEvidence.details.selectedTodoTitle, nil)
    expectNoDifference(fetchOneNilEvidence.details.nilQueryCleared, true)

    let fetchRequestNilEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-request-nil-request" }
    )
    expectNoDifference(fetchRequestNilEvidence.details.adapter, "@Fetch(request nil)")
    expectNoDifference(fetchRequestNilEvidence.details.previousTodoTitles, ["Cached request nil"])
    expectNoDifference(fetchRequestNilEvidence.details.todoTitles, [])
    expectNoDifference(fetchRequestNilEvidence.details.nilQueryCleared, nil)
    expectNoDifference(fetchRequestNilEvidence.details.nilRequestCleared, true)

    let cancellationEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-all-cancellation" }
    )
    expectNoDifference(cancellationEvidence.details.adapter, "@FetchAll(cancellation)")
    expectNoDifference(cancellationEvidence.details.observationCount, 1)
    expectNoDifference(cancellationEvidence.details.cancellationTerminated, true)

    let fetchRequestCancellationEvidence = try #require(
      evidenceRows.first { $0.event == "fetch-request-cancellation" }
    )
    expectNoDifference(
      fetchRequestCancellationEvidence.details.adapter,
      "@Fetch(request cancellation)"
    )
    expectNoDifference(fetchRequestCancellationEvidence.details.observationCount, 1)
    expectNoDifference(fetchRequestCancellationEvidence.details.cancellationTerminated, true)

    let humanOutput = try runCLI(["validation", "adapters"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("case: validation.platform.adapters"))
    #expect(humanOutput.contains("evidence rows: 21"))
    #expect(humanOutput.contains("binding adapters: @FetchAll, @FetchOne, @Fetch"))
    #expect(humanOutput.contains("lifecycle probes: 10"))
    #expect(humanOutput.contains("cancellation terminated: true"))
    #expect(humanOutput.contains("@FetchAll"))
    #expect(humanOutput.contains("@Fetch(request dynamic)"))
    #expect(humanOutput.contains("@Shares"))
  }

  @Test
  func cliValidationSyncUpsRecordingEmitsEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLISyncUpsRecordingValidationOutput.self,
      from: Data(
        try runCLI(["validation", "syncups-recording", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.appID, "cli-cache-test")
    expectNoDifference(jsonOutput.event, "syncups-recording")
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.evidenceCount, 7)
    expectNoDifference(jsonOutput.events, [
      "seed",
      "speech-task",
      "speaker-advance",
      "finish",
      "meeting-save",
      "settings-open",
      "relaunch",
    ])
    expectNoDifference(jsonOutput.meetingTranscripts, ["Reviewed launch risks. Final notes."])
    expectNoDifference(jsonOutput.transcript, "Reviewed launch risks. Final notes.")
    expectNoDifference(jsonOutput.authorizationStatus, .authorized)
    expectNoDifference(jsonOutput.requestedAuthorization, false)
    expectNoDifference(jsonOutput.loadedSoundEffectFileName, "ding.wav")
    expectNoDifference(jsonOutput.speechResultCount, 2)
    expectNoDifference(jsonOutput.soundEffectPlayCount, 1)
    expectNoDifference(jsonOutput.secondsElapsed, 2)
    expectNoDifference(jsonOutput.speakerIndex, 1)
    expectNoDifference(jsonOutput.currentSpeakerName, "Blob Jr")
    expectNoDifference(jsonOutput.openSettingsCount, 1)
    expectNoDifference(jsonOutput.finalAlert, .speechRecognitionDenied)
    expectNoDifference(jsonOutput.isDismissed, true)

    let jsonlOutput = try runCLI(["validation", "recording", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 7)
    let seedEvidence = try JSONDecoder().decode(
      CLISyncUpsRecordingValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(seedEvidence.caseID, "validation.syncups.recording")
    expectNoDifference(seedEvidence.appID, "cli-cache-test")
    expectNoDifference(seedEvidence.event, "seed")
    expectNoDifference(seedEvidence.details.syncUpTitles, ["Tiny validation standup"])
    expectNoDifference(seedEvidence.details.attendeeNames, ["Blob", "Blob Jr"])
    expectNoDifference(seedEvidence.details.meetingTranscripts, [])

    let advanceEvidence = try JSONDecoder().decode(
      CLISyncUpsRecordingValidationEvidence.self,
      from: Data(lines[2].utf8)
    )
    expectNoDifference(advanceEvidence.event, "speaker-advance")
    expectNoDifference(advanceEvidence.details.tickEvent, "advancedSpeaker")
    expectNoDifference(advanceEvidence.details.recording?.secondsElapsed, 1)
    expectNoDifference(advanceEvidence.details.recording?.currentSpeakerName, "Blob Jr")
    expectNoDifference(advanceEvidence.details.recording?.soundEffectPlayCount, 1)

    let settingsEvidence = try JSONDecoder().decode(
      CLISyncUpsRecordingValidationEvidence.self,
      from: Data(lines[5].utf8)
    )
    expectNoDifference(settingsEvidence.event, "settings-open")
    expectNoDifference(settingsEvidence.details.meetingTranscripts, ["Reviewed launch risks. Final notes."])
    expectNoDifference(settingsEvidence.details.recording?.authorizationStatus, .denied)
    expectNoDifference(settingsEvidence.details.recording?.alert, .speechRecognitionDenied)
    expectNoDifference(settingsEvidence.details.alertOutcome, .settingsOpened)
    expectNoDifference(settingsEvidence.details.openSettingsCount, 1)

    let relaunchEvidence = try JSONDecoder().decode(
      CLISyncUpsRecordingValidationEvidence.self,
      from: Data(try #require(lines.last).utf8)
    )
    expectNoDifference(relaunchEvidence.event, "relaunch")
    expectNoDifference(relaunchEvidence.details.meetingIDs, settingsEvidence.details.meetingIDs)
    expectNoDifference(relaunchEvidence.details.meetingTranscripts, ["Reviewed launch risks. Final notes."])

    let humanOutput = try runCLI(["validation", "syncups"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("case: validation.syncups.recording"))
    #expect(humanOutput.contains("evidence rows: 7"))
    #expect(humanOutput.contains("Reviewed launch risks. Final notes."))
    #expect(humanOutput.contains("open settings: 1"))
  }

  @Test
  func cliValidationParityReportEmitsCoverageProvenance() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLIParityCoverageOutput.self,
      from: Data(
        try runCLI(["validation", "parity-report", "--json"], homeURL: homeURL).utf8
      )
    )
    expectNoDifference(jsonOutput.event, "parity-report")
    expectNoDifference(jsonOutput.coverageComplete, false)
    expectNoDifference(jsonOutput.recordCount, 182)
    expectNoDifference(jsonOutput.exactCount, 28)
    expectNoDifference(jsonOutput.adaptedCount, 150)
    expectNoDifference(jsonOutput.blockedCount, 4)
    expectNoDifference(jsonOutput.notApplicableCount, 0)
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/schema.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/serializeSchema.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/object.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/PersistedObject.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/weakHashLegacy.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/store.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/www/_examples/app-builder.md + Galaxies-dev/app-builder@e67200cc70e01d88bd9a5382cf0380f4882fb8c7"
      )
    )
    #expect(
      jsonOutput.sourceFiles.contains(
        "upstream/instant/client/www/lib/recipes/auth.tsx"
      )
    )
    #expect(jsonOutput.sourceFiles.contains("upstream/instant/client/packages/react-common/src"))
    #expect(jsonOutput.swiftFiles.contains("Tests/InstantSwiftDataCoreTests/InstantDateCoercionTests.swift"))
    #expect(jsonOutput.swiftFiles.contains("Tests/InstantSwiftDataCoreTests/CLITests.swift"))
    #expect(jsonOutput.swiftFiles.contains("Tests/InstantSwiftDataTests/TypedAPITests.swift"))
    #expect(jsonOutput.records.contains { $0.id == "instant.store.simple-add" && $0.status == "exact" })
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.link-unlink-multi" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.link-unlink-without-update" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.on-delete-reverse-cascade" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.rule-params-no-op" && $0.status == "exact"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.recursive-links-same-id" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.v0-store-restore" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.new-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.update-attr" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.delete-attr" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.deep-merge" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.cloudkit-demo.local-counter-share" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.website.app-builder.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.website.chat.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.website.microblog.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.website.mobile-chat.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.website.stroopwafel.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.auth.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.reactions.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.typing-indicator.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.avatar-stack.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.cursors.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.custom-cursors.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.recipe.merge-tile-game.local-cli" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.simple-without-where" && $0.status == "exact"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.simple-where-expected-keys" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.where-deep-like-prefix-suffix" && $0.status == "exact"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.nested-wheres" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.missing-namespaces-attributes" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.relation-filter-refs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.create-update-triples" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.query.object-values" && $0.status == "exact"
      }
    )
    for expected in [
      ("instant.query.pagination-limit", "exact"),
      ("instant.query.nested-limit-warning", "adapted"),
      ("instant.query.pagination-offset-page-info", "blocked"),
      ("instant.query.pagination-last", "exact"),
      ("instant.query.pagination-first", "exact"),
      ("instant.query.leading-ignores-start-cursor", "adapted"),
      ("instant.query.leading-ignores-end-cursor", "adapted"),
      ("instant.query.arbitrary-ordering", "exact"),
      ("instant.query.arbitrary-ordering-dates", "adapted"),
      ("instant.query.arbitrary-ordering-strings", "exact"),
      ("instant.query.fields", "adapted"),
      ("instant.query.is-null", "exact"),
      ("instant.query.is-null-relations", "exact"),
      ("instant.query.is-null-reverse-relations", "exact"),
      ("instant.query.not-and-ne", "adapted"),
      ("instant.query.comparators", "exact"),
    ] {
      #expect(
        jsonOutput.records.contains { $0.id == expected.0 && $0.status == expected.1 },
        "Expected \(expected.1) InstaQL parity record \(expected.0)"
      )
    }
    for id in [
      "instant.query-validation.top-level-types",
      "instant.query-validation.top-level-entity-names",
      "instant.query-validation.links",
      "instant.query-validation.dollar-object",
      "instant.query-validation.dollar-keys",
      "instant.query-validation.where-types",
      "instant.query-validation.where-operators",
      "instant.query-validation.where-unknown-operators",
      "instant.query-validation.where-unknown-attributes",
      "instant.query-validation.where-id",
      "instant.query-validation.where-logical",
      "instant.query-validation.where-dot-notation",
      "instant.query-validation.pagination-top-level",
      "instant.query-validation.relations-complex-objects",
    ] {
      #expect(
        jsonOutput.records.contains { $0.id == id && $0.status == "adapted" },
        "Expected adapted query-validation parity record \(id)"
      )
    }
    let unknownAttributeRecord = try #require(
      jsonOutput.records.first { $0.id == "instant.query-validation.where-unknown-attributes" }
    )
    expectNoDifference(unknownAttributeRecord.sourceTestName, "where clause unknown attributes")
    expectNoDifference(unknownAttributeRecord.swiftTestName, "upstreamWhereClauseTypeValidation")
    expectNoDifference(
      unknownAttributeRecord.notes,
      "Swift rejects filters that reference undeclared schema attributes with the same namespace and path provenance."
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.chunk-arrays" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.chunk-structure" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.operation-structure" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.create-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.update-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.merge-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.delete-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.link-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.unlink-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.entity-existence" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.attribute-types" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.chained-operations" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.multiple-entity-types" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.link-relationships" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.without-schema" && $0.status == "exact"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.uuid-format" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.lookup-source-update" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.lookup-source-link" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.lookup-link-value" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.transaction-validation.lookup-proxy" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.basic-update-transform" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.optimistic-unknown-attr" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-resolves-attr-ids" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.custom-lookup-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-link-value" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-link-forward-identity" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-link-reverse-identity" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-link-declared-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-self-links" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.ref-lookup-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.ref-lookup-link-value" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookups-create-entities-from-links" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookups-create-entities-from-unlinks" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.mode-update" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.dotted-lookup-attribute" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.invalid-link-lookup-attr" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.lookup-link-value-arrays" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.no-duplicate-ref-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-attrs-and-links" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-no-duplicate-ref-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-custom-lookup-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-lookup-link-value" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-lookup-link-value-arrays" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-ref-lookup-attrs" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-ref-lookup-link-value" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.schema-checked-data-types" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.instaml.closed-mutation-surface" && $0.status == "adapted"
      }
    )
    for expected in [
      ("instant.utils.date-coercion.valid-strings", "exact"),
      ("instant.utils.date-coercion.invalid-strings", "adapted"),
      ("instant.utils.date-coercion.date-instances", "adapted"),
      ("instant.utils.date-coercion.number-timestamps", "exact"),
      ("instant.utils.date-coercion.unsupported-types", "adapted"),
    ] {
      #expect(
        jsonOutput.records.contains { $0.id == expected.0 && $0.status == expected.1 },
        "Expected \(expected.1) date coercion parity record \(expected.0)"
      )
    }
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.store.json-serialization" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-subscription.explicit-cancel" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-one.scalar-selection" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-one.dynamic-query" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-one.nil-query" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-all.decode-failure" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch-all.scalar-selection" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch.transaction-request" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch.request-dynamic-query" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch.request-nil-reset" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.fetch.request-dynamic-cancellation" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.case-studies.animation-initializers" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.case-studies.swiftui-direct-wrappers" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.case-studies.observable-model" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.case-studies.uikit-controller" && $0.status == "adapted"
      }
    )
    let platformAdapterBinding = try #require(
      jsonOutput.records.first { $0.id == "instant.react-common.platform-adapter-bindings" }
    )
    expectNoDifference(platformAdapterBinding.sourceKind, "instant-typescript")
    expectNoDifference(platformAdapterBinding.sourceFile, "upstream/instant/client/packages/react-common/src")
    expectNoDifference(
      platformAdapterBinding.sourceTestName,
      "useQuery, useAuth, useId, room, storage, streams, and shares hooks"
    )
    expectNoDifference(
      platformAdapterBinding.swiftFile,
      "Tests/InstantSwiftDataTests/BootstrapTests.swift"
    )
    expectNoDifference(
      platformAdapterBinding.swiftTestName,
      "platformAdapterValidationProvesWrappersBindLocalRuntime"
    )
    expectNoDifference(platformAdapterBinding.surface, "adapter-bindings")
    expectNoDifference(platformAdapterBinding.status, "adapted")
    expectNoDifference(
      platformAdapterBinding.notes,
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares."
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.reminders.search-tags" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.reminders.form-model" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.draft.generated-field-exclusion" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "sqlite.syncups.record-meeting" && $0.status == "adapted"
      }
    )
    #expect(
      jsonOutput.records.contains {
        $0.id == "instant.live-transport.swift-to-typescript" && $0.status == "blocked"
      }
    )

    let jsonlOutput = try runCLI(["validation", "coverage", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, jsonOutput.recordCount)
    let evidenceRows = try lines.map { line in
      try JSONDecoder().decode(CLIParityCoverageEvidence.self, from: Data(line.utf8))
    }
    let firstEvidence = try JSONDecoder().decode(
      CLIParityCoverageEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(firstEvidence.caseID, "validation.parity.report")
    expectNoDifference(firstEvidence.side, "instant-typescript")
    expectNoDifference(firstEvidence.event, "parity-record")
    expectNoDifference(firstEvidence.entityID, "instant.store.simple-add")
    expectNoDifference(firstEvidence.ok, true)
    expectNoDifference(firstEvidence.details.id, "instant.store.simple-add")
    expectNoDifference(firstEvidence.details.sourceKind, "instant-typescript")
    expectNoDifference(
      firstEvidence.details.sourceFile,
      "upstream/instant/client/packages/core/__tests__/src/store.test.ts"
    )
    expectNoDifference(firstEvidence.details.status, "exact")
    let platformAdapterBindingEvidence = try #require(
      evidenceRows.first { $0.entityID == "instant.react-common.platform-adapter-bindings" }
    )
    expectNoDifference(platformAdapterBindingEvidence.side, "instant-typescript")
    expectNoDifference(platformAdapterBindingEvidence.ok, true)
    expectNoDifference(platformAdapterBindingEvidence.details.sourceKind, "instant-typescript")
    expectNoDifference(
      platformAdapterBindingEvidence.details.sourceFile,
      "upstream/instant/client/packages/react-common/src"
    )
    expectNoDifference(
      platformAdapterBindingEvidence.details.sourceTestName,
      "useQuery, useAuth, useId, room, storage, streams, and shares hooks"
    )
    expectNoDifference(
      platformAdapterBindingEvidence.details.swiftFile,
      "Tests/InstantSwiftDataTests/BootstrapTests.swift"
    )
    expectNoDifference(
      platformAdapterBindingEvidence.details.swiftTestName,
      "platformAdapterValidationProvesWrappersBindLocalRuntime"
    )
    expectNoDifference(platformAdapterBindingEvidence.details.surface, "adapter-bindings")
    expectNoDifference(platformAdapterBindingEvidence.details.status, "adapted")
    expectNoDifference(
      platformAdapterBindingEvidence.details.notes,
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares."
    )
    let blockedEvidence = try JSONDecoder().decode(
      CLIParityCoverageEvidence.self,
      from: Data(try #require(lines.last).utf8)
    )
    expectNoDifference(blockedEvidence.ok, false)
    expectNoDifference(blockedEvidence.details.status, "blocked")

    let humanOutput = try runCLI(["validation", "parity"], homeURL: homeURL)
    #expect(humanOutput.contains("parity coverage: incomplete"))
    #expect(humanOutput.contains("records: 182"))
    #expect(humanOutput.contains("exact: 28"))
    #expect(humanOutput.contains("adapted: 150"))
    #expect(humanOutput.contains("blocked: 4"))
    #expect(humanOutput.contains("not applicable: 0"))
  }

  @Test
  func cliBenchmarkLocalTodosEmitsJSONAndEvidence() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    let jsonOutput = try JSONDecoder().decode(
      CLIBenchmarkOutput.self,
      from: Data(
        try runCLI(
          [
            "benchmark", "--suite", "local-todos", "--iterations", "1", "--app-id",
            "cli-benchmark", "--json",
          ],
          homeURL: homeURL
        ).utf8
      )
    )
    expectNoDifference(jsonOutput.suite, "local-todos")
    expectNoDifference(jsonOutput.appID, "cli-benchmark")
    expectNoDifference(jsonOutput.iterations, 1)
    expectNoDifference(jsonOutput.ok, true)
    expectNoDifference(jsonOutput.transport, "not-implemented-local-cache-only")
    expectNoDifference(jsonOutput.finalTodoCount, 0)
    expectNoDifference(jsonOutput.pendingMutationCount, 0)
    expectNoDifference(
      jsonOutput.metrics.map(\.name),
      [
        "bootstrap.local-sqlite",
        "triple-insert.seed",
        "query-materialization.todos",
        "pending-mutation-enqueue.update",
        "high-bandwidth.scalar-updates",
        "high-bandwidth.linked-writes",
        "memory-growth.triples.1k",
        "memory-growth.triples.10k",
        "memory-growth.triples.50k",
        "storage-metadata.query",
        "stream-write.chunks",
        "stream-read.chunks",
        "subscription-cancel.live-query",
        "subscription-cancel.presence",
        "subscription-cancel.topic",
        "subscription-cancel.storage",
        "subscription-cancel.stream",
        "query-cache-read.todos",
        "triple-retract.reset",
        "offline-restore.relaunch",
        "outbox-flush.local-transport",
      ]
    )
    let scalarMemorySamples = try #require(
      jsonOutput.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples
    )
    expectNoDifference(scalarMemorySamples.map(\.memoryBudgetBytes), [67_108_864])
    #if canImport(Darwin)
      #expect(scalarMemorySamples.allSatisfy { sample in
        guard let delta = sample.memoryDeltaBytes,
          let budget = sample.memoryBudgetBytes
        else { return false }
        return delta <= budget
      })
    #else
      expectNoDifference(scalarMemorySamples.map(\.memoryDeltaBytes), [UInt64?.none])
    #endif
    let linkedMemorySamples = try #require(
      jsonOutput.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples
    )
    expectNoDifference(linkedMemorySamples.map(\.memoryBudgetBytes), [67_108_864])
    #if canImport(Darwin)
      #expect(linkedMemorySamples.allSatisfy { sample in
        guard let delta = sample.memoryDeltaBytes,
          let budget = sample.memoryBudgetBytes
        else { return false }
        return delta <= budget
      })
    #else
      expectNoDifference(linkedMemorySamples.map(\.memoryDeltaBytes), [UInt64?.none])
    #endif
    let oneThousandTripleMemorySamples = try #require(
      jsonOutput.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples
    )
    expectNoDifference(oneThousandTripleMemorySamples.map(\.operationCount), [1_000])
    expectNoDifference(oneThousandTripleMemorySamples.map(\.resultCount), [250])
    expectNoDifference(oneThousandTripleMemorySamples.map(\.pendingMutationCount), [1])
    expectNoDifference(oneThousandTripleMemorySamples.map(\.memoryBudgetBytes), [67_108_864])
    let tenThousandTripleMemorySamples = try #require(
      jsonOutput.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples
    )
    expectNoDifference(tenThousandTripleMemorySamples.map(\.operationCount), [10_000])
    expectNoDifference(tenThousandTripleMemorySamples.map(\.resultCount), [2_500])
    expectNoDifference(tenThousandTripleMemorySamples.map(\.pendingMutationCount), [1])
    expectNoDifference(tenThousandTripleMemorySamples.map(\.memoryBudgetBytes), [268_435_456])
    let fiftyThousandTripleMemorySamples = try #require(
      jsonOutput.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples
    )
    expectNoDifference(fiftyThousandTripleMemorySamples.map(\.operationCount), [50_000])
    expectNoDifference(fiftyThousandTripleMemorySamples.map(\.resultCount), [12_500])
    expectNoDifference(fiftyThousandTripleMemorySamples.map(\.pendingMutationCount), [1])
    expectNoDifference(fiftyThousandTripleMemorySamples.map(\.memoryBudgetBytes), [1_073_741_824])
    #if canImport(Darwin)
      #expect(
        (
          oneThousandTripleMemorySamples
            + tenThousandTripleMemorySamples
            + fiftyThousandTripleMemorySamples
        )
        .allSatisfy { sample in
          guard let delta = sample.memoryDeltaBytes,
            let budget = sample.memoryBudgetBytes
          else { return false }
          return delta <= budget
        }
      )
    #else
      expectNoDifference(oneThousandTripleMemorySamples.map(\.memoryDeltaBytes), [UInt64?.none])
      expectNoDifference(tenThousandTripleMemorySamples.map(\.memoryDeltaBytes), [UInt64?.none])
      expectNoDifference(fiftyThousandTripleMemorySamples.map(\.memoryDeltaBytes), [UInt64?.none])
    #endif
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "storage-metadata.query" }?.samples.map(\.resultCount),
      [5]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "stream-write.chunks" }?.samples.map(\.operationCount),
      [25]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "stream-read.chunks" }?.samples.map(\.resultCount),
      [25]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "subscription-cancel.live-query" }?.samples.map(\.operationCount),
      [1]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "subscription-cancel.live-query" }?.samples.map(\.resultCount),
      [1]
    )
    for metricName in [
      "subscription-cancel.presence",
      "subscription-cancel.topic",
      "subscription-cancel.storage",
      "subscription-cancel.stream",
    ] {
      expectNoDifference(
        jsonOutput.metrics.first { $0.name == metricName }?.samples.map(\.operationCount),
        [1]
      )
      expectNoDifference(
        jsonOutput.metrics.first { $0.name == metricName }?.samples.map(\.resultCount),
        [1]
      )
    }
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "triple-insert.seed" }?.samples.map(\.actorHopCount),
      [7]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.actorHopCount),
      [350]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.operationCount),
      [54]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.resultCount),
      [54]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.pendingMutationCount),
      [0]
    )
    expectNoDifference(
      jsonOutput.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.actorHopBreakdown),
      [
        [
          "mutation-flush-gate": 2,
          "mutation-transport": 1,
          "operation-gate": 4,
          "outbox": 1,
          "persistence": 7,
        ]
      ]
    )

    let environmentDefaultOutput = try JSONDecoder().decode(
      CLIBenchmarkOutput.self,
      from: Data(
        try runCLI(["benchmark", "--iterations", "1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(environmentDefaultOutput.appID, "cli-cache-test")

    let fallbackDefaultHomeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: fallbackDefaultHomeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fallbackDefaultHomeURL) }
    let fallbackDefaultOutput = try JSONDecoder().decode(
      CLIBenchmarkOutput.self,
      from: Data(
        try runCLI(
          ["benchmark", "--iterations", "1", "--json"],
          homeURL: fallbackDefaultHomeURL,
          environment: ["INSTANT_APP_ID": nil]
        ).utf8
      )
    )
    expectNoDifference(fallbackDefaultOutput.appID, "local-demo")

    let jsonlOutput = try runCLI(
      ["benchmark", "--suite", "local-todos", "--iterations", "1", "--app-id", "cli-benchmark", "--jsonl"],
      homeURL: homeURL
    )
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 22)
    let firstEvidence = try JSONDecoder().decode(
      CLIBenchmarkEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(firstEvidence.caseID, "benchmark.local.todos")
    expectNoDifference(firstEvidence.event, "summary")
    expectNoDifference(firstEvidence.details.transport, "not-implemented-local-cache-only")
    expectNoDifference(firstEvidence.details.iterations, 1)
    expectNoDifference(firstEvidence.details.metric, nil)
    expectNoDifference(
      try lines.dropFirst().compactMap {
        try JSONDecoder().decode(CLIBenchmarkEvidence.self, from: Data($0.utf8)).details.metric?.name
      },
      jsonOutput.metrics.map(\.name)
    )

    let humanOutput = try runCLI(["benchmark", "--iterations", "1"], homeURL: homeURL)
    #expect(humanOutput.contains("benchmark: ok"))
    #expect(humanOutput.contains("suite: local-todos"))

    let malformed = try runCLIResult(["benchmark", "--iterations", "0", "--json"], homeURL: homeURL)
    #expect(malformed.status == 64)
    #expect(malformed.error.contains("instant-swift-data benchmark"))

    let help = try runCLIResult(["benchmark", "--help"], homeURL: homeURL)
    #expect(help.status == 0)
    #expect(help.output.contains("Usage: instant-swift-data benchmark"))
    expectNoDifference(help.error, "")
  }

  private func runCLI(
    _ arguments: [String],
    homeURL: URL,
    environment: [String: String?] = [:]
  ) throws -> String {
    let result = try runCLIResult(arguments, homeURL: homeURL, environment: environment)
    guard result.status == 0 else {
      throw CLITestError(
        "instant-swift-data \(arguments.joined(separator: " ")) failed with status \(result.status): \(result.error)"
      )
    }
    return result.output
  }

  private func runCLIResult(
    _ arguments: [String],
    homeURL: URL,
    environment: [String: String?] = [:]
  ) throws -> CLITestProcessResult {
    let packageURL = packageRootURL()
    let executableURL = packageURL.appendingPathComponent(".build/debug/instant-swift-data")

    let process = Process()
    if FileManager.default.isExecutableFile(atPath: executableURL.path) {
      try requireFreshCLIExecutable(executableURL, packageURL: packageURL)
      process.executableURL = executableURL
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["swift", "run", "instant-swift-data"] + arguments
    }
    process.currentDirectoryURL = packageURL
    var processEnvironment = ProcessInfo.processInfo.environment.merging(
      [
        "INSTANT_SWIFT_DATA_HOME": homeURL.path,
        "INSTANT_APP_ID": "cli-cache-test",
      ],
      uniquingKeysWith: { _, new in new }
    )
    for (key, value) in environment {
      processEnvironment[key] = value
    }
    process.environment = processEnvironment

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    let outputCapture = CLITestPipeCapture()
    let errorCapture = CLITestPipeCapture()
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      outputCapture.append(handle.availableData)
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      errorCapture.append(handle.availableData)
    }

    try process.run()
    process.waitUntilExit()
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
    outputCapture.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
    errorCapture.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

    let output = String(
      decoding: outputCapture.data(),
      as: UTF8.self
    )
    let error = String(
      decoding: errorCapture.data(),
      as: UTF8.self
    )
    return CLITestProcessResult(
      status: process.terminationStatus,
      output: output,
      error: error
    )
  }

  private func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func requireFreshCLIExecutable(_ executableURL: URL, packageURL: URL) throws {
    let executableModifiedAt = try modificationDate(of: executableURL)
    let newestSourceModifiedAt = try newestModificationDate(
      under: [
        packageURL.appendingPathComponent("Sources/instant-swift-data", isDirectory: true),
        packageURL.appendingPathComponent("Sources/InstantSwiftDataCore", isDirectory: true),
        packageURL.appendingPathComponent("Sources/InstantSwiftDataSchema", isDirectory: true),
      ]
    )
    guard executableModifiedAt >= newestSourceModifiedAt else {
      throw CLITestError(
        """
        .build/debug/instant-swift-data is older than CLI sources. Run \
        'swift build --product instant-swift-data' before process-level CLI tests.
        """
      )
    }
  }

  private func newestModificationDate(under roots: [URL]) throws -> Date {
    let fileManager = FileManager.default
    var newest = Date.distantPast

    for root in roots {
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
      ) else {
        continue
      }

      for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [
          .isRegularFileKey,
          .contentModificationDateKey,
        ])
        guard values.isRegularFile == true, fileURL.pathExtension == "swift" else {
          continue
        }
        if let modifiedAt = values.contentModificationDate, modifiedAt > newest {
          newest = modifiedAt
        }
      }
    }

    return newest
  }

  private func modificationDate(of url: URL) throws -> Date {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    return try #require(values.contentModificationDate)
  }
}

private struct CLIAddOutput: Decodable {
  var changedID: String?
}

private struct CLIInitOutput: Decodable {
  var example: String
  var directory: String
  var transport: String
  var files: [CLIInitFile]
}

private struct CLIInitFile: Decodable {
  var kind: String
  var path: String
}

private struct CLIInitEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIInitOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIGeneratedArtifactOutput: Decodable {
  var example: String
  var kind: String
  var fileName: String
  var path: String?
  var byteCount: Int
  var contents: String?
}

private struct CLISchemaVerifyOutput: Decodable {
  var example: String
  var path: String
  var entityCount: Int
  var attributeCount: Int
  var linkCount: Int
}

private struct CLIPermissionsVerifyOutput: Decodable {
  var example: String
  var path: String
  var namespaceCount: Int
  var allowRuleCount: Int
  var rateLimitCount: Int
}

private struct CLIGeneratedArtifactEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var details: CLIGeneratedArtifactOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case details
  }
}

private struct CLITodosOutput: Decodable {
  var appID: String
  var event: String
  var changedID: String?
  var transport: String
  var queryID: String
  var cacheKey: String
  var pageInfo: InstantQueryPageInfo?
  var pendingMutationCount: Int
  var todos: [CLITodo]
}

private struct CLITodoLinksOutput: Decodable {
  var event: String
  var changedID: String?
  var transport: String
  var pendingMutationCount: Int
  var projects: [CLITodoProject]
  var todos: [CLILinkedTodo]
}

private struct CLICountersOutput: Decodable {
  var event: String
  var changedID: String?
  var transport: String
  var queryID: String
  var cacheKey: String
  var pendingMutationCount: Int
  var counterCount: Int
  var sharedCounterCount: Int
  var counters: [CLISharedCounter]
}

private struct CLISharedCounter: Decodable, Equatable {
  var counter: CounterRecord
  var isShared: Bool
  var shareID: String?
  var shareRole: InstantShareRole?
  var shareMemberCount: Int
}

private struct CLIChatOutput: Decodable {
  var event: String
  var changedID: String?
  var selectedChannelID: String?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var pendingMutationCount: Int
  var channelCount: Int
  var messageCount: Int
  var channels: [ChatChannelRecord]
  var messages: [ChatMessageRecord]
}

private struct CLIChatEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIChatOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIChatEventEnvelope: Decodable {
  var event: String
}

private struct CLIAppBuilderGenerationEventOutput: Decodable, Equatable {
  var event: String
  var kind: String?
  var text: String?
  var codeLength: Int
  var reasoningLength: Int
  var isPreviewable: Bool
}

private struct CLIAppBuilderOutput: Decodable, Equatable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedBuildID: String?
  var authUserID: String?
  var authUserEmail: String?
  var transport: String
  var platformApp: InstantPlatformApp?
  var queryID: String
  var cacheKey: String
  var ownerQueryID: String?
  var ownerCacheKey: String?
  var pendingMutationCount: Int
  var buildCount: Int
  var previewableBuildCount: Int
  var builds: [AppBuilderBuildRecord]
  var selectedBuild: AppBuilderBuildRecord?
  var generationEvents: [CLIAppBuilderGenerationEventOutput]
}

private struct CLIAppBuilderEvidence: Decodable {
  var caseID: String
  var side: String
  var event: String
  var ok: Bool
  var details: CLIAppBuilderOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case ok
    case details
  }
}

private struct CLIChatMessageEvidence: Decodable {
  var event: String
  var entityID: String?
  var details: ChatMessageRecord
}

private struct CLIMicroblogOutput: Decodable {
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedProfile: MicroblogProfileRecord?
  var selectedPostID: String?
  var authUserID: String?
  var transport: String
  var pendingMutationCount: Int
  var userCount: Int
  var profileCount: Int
  var postCount: Int
  var likeCount: Int
  var users: [MicroblogUserRecord]
  var profiles: [MicroblogProfileRecord]
  var posts: [MicroblogPostRecord]
  var likes: [MicroblogLikeRecord]
  var feed: [MicroblogFeedPostRecord]
}

private struct CLIMicroblogEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIMicroblogOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIMicroblogEventEnvelope: Decodable {
  var event: String
}

private struct CLIMobileChatOutput: Decodable {
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedProfile: MobileChatProfileRecord?
  var selectedChannelID: String?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var pendingMutationCount: Int
  var userCount: Int
  var profileCount: Int
  var channelCount: Int
  var messageCount: Int
  var presenceRoom: InstantRoomHandle?
  var presenceMemberCount: Int
  var users: [MobileChatUserRecord]
  var profiles: [MobileChatProfileRecord]
  var channels: [MobileChatChannelRecord]
  var messages: [MobileChatMessageRecord]
  var presenceMembers: [InstantRoomPresenceMember]
}

private struct CLIMobileChatEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIMobileChatOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIMobileChatEventEnvelope: Decodable {
  var event: String
}

private struct CLIStroopwafelOutput: Decodable {
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedUser: StroopwafelUserRecord?
  var selectedRoomCode: String?
  var selectedRoom: StroopwafelRoomRecord?
  var selectedGameID: String?
  var selectedGame: StroopwafelGameRecord?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var pendingMutationCount: Int
  var userCount: Int
  var roomCount: Int
  var gameCount: Int
  var pointCount: Int
  var users: [StroopwafelUserRecord]
  var rooms: [StroopwafelRoomRecord]
  var games: [StroopwafelGameRecord]
  var points: [StroopwafelPointRecord]
}

private struct CLIStroopwafelEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIStroopwafelOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIRemindersOutput: Decodable {
  var event: String
  var changedID: String?
  var transport: String
  var pendingMutationCount: Int
  var lists: [RemindersListSummary]
  var stats: RemindersStats
  var reminders: [ReminderRecord]
  var tags: [ReminderTagRecord]
  var reminderTags: [ReminderTagLinkRecord]
}

private struct CLIRemindersEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIRemindersOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLISyncUpsOutput: Decodable {
  var event: String
  var changedID: String?
  var transport: String
  var pendingMutationCount: Int
  var syncUps: [SyncUpSummary]
  var attendees: [SyncUpAttendeeRecord]
  var meetings: [SyncUpMeetingRecord]
  var recording: SyncUpRecordingSummary?
}

private struct CLISyncUpsEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLISyncUpsOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLITodoLinkSnapshotsOutput: Decodable {
  var event: String
  var todos: [InstantEntitySnapshot]
  var projects: [InstantEntitySnapshot]
}

private struct CLIAdminQueryOutput: Decodable, Equatable {
  var event: String
  var transport: String
  var queryID: String
  var pendingMutationCount: Int
  var snapshots: [InstantEntitySnapshot]
}

private struct CLIAdminTransactOutput: Decodable, Equatable {
  var event: String
  var changedID: String
  var transport: String
  var namespace: String
  var transactionID: String
  var changedEntityIDs: [String]
  var tripleCount: Int
  var queryID: String
  var pendingMutationCount: Int
  var snapshotCount: Int
  var snapshots: [InstantEntitySnapshot]
}

private struct CLIAdminQueryEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIAdminQueryOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIAdminTransactEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIAdminTransactOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIAdminSnapshotEvidence: Decodable {
  var caseID: String
  var event: String
  var details: InstantEntitySnapshot

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLITodoProject: Decodable, Equatable {
  var id: String
  var title: String
}

private struct CLILinkedTodo: Decodable, Equatable {
  var id: String
  var text: String
  var isCompleted: Bool
  var projectID: String?
}

private struct CLITestProcessResult {
  var status: Int32
  var output: String
  var error: String
}

// Protected by an NSLock because FileHandle readability handlers run concurrently.
private final class CLITestPipeCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = Data()

  func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    storage.append(data)
    lock.unlock()
  }

  func data() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

private struct CLITodosEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLITodosOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLICountersEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLICountersOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLISharedCounterEvidence: Decodable {
  var caseID: String
  var event: String
  var entityID: String?
  var details: CLISharedCounter

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case entityID
    case details
  }
}

private struct CLITodoWatchOutput: Decodable {
  var event: String
  var requestedEventCount: Int
  var emittedEventCount: Int
  var emissions: [CLITodoWatchEmission]
}

private struct CLITodoWatchEvidence: Decodable {
  var caseID: String
  var side: String
  var event: String
  var ok: Bool
  var details: CLITodoWatchEmission

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case ok
    case details
  }
}

private struct CLITodoWatchEmission: Decodable {
  var queryID: String
  var cacheKey: String
  var emissionIndex: Int
  var sequence: Int64
  var pendingMutationCount: Int
  var todos: [CLITodo]
}

private struct CLIAuthOutput: Decodable {
  var event: String
  var isSignedIn: Bool
  var userID: String?
  var isGuest: Bool?
  var hasRefreshToken: Bool
}

private struct CLIAuthRecipeOutput: Decodable, Equatable {
  var event: String
  var recipeSlug: String
  var isLoginVisible: Bool
  var isEmailEntryVisible: Bool
  var isCodeEntryVisible: Bool
  var isDashboardVisible: Bool
  var isSignedIn: Bool
  var userID: String?
  var userEmail: String?
  var hasRefreshToken: Bool
  var sentEmail: String?
  var localVerificationCode: String?
}

private struct CLIAuthRecipeEvidence: Decodable {
  var caseID: String
  var side: String
  var event: String
  var ok: Bool
  var details: CLIAuthRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case ok
    case details
  }
}

private struct CLIMagicCodeOutput: Decodable {
  var event: String
  var email: String
  var localVerificationCode: String
}

private struct CLIAuthWatchOutput: Decodable {
  var event: String
  var requestedEventCount: Int
  var emittedEventCount: Int
  var emissions: [CLIAuthOutput]
}

private struct CLIAuthWatchEvidence: Decodable {
  var caseID: String
  var side: String
  var event: String
  var ok: Bool
  var details: CLIAuthOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case ok
    case details
  }
}

private struct CLIAuthEndpointOutput: Decodable {
  var appID: String
  var event: String
  var apiURI: String
  var websocketURI: String
  var authorizationURL: String?
  var issuerURI: String
}

private struct CLIAuthEndpointEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIAuthEndpointOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLITodo: Decodable, Equatable {
  var id: String
  var text: String
  var isCompleted: Bool
}

private struct CLILocalIDOutput: Decodable {
  var id: String
}

private struct CLILocalIDsOutput: Decodable {
  var transport: String
  var localIDCount: Int
  var localIDs: [InstantLocalID]
}

private struct CLILocalIDsEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLILocalIDsOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLILocalIDRowEvidence: Decodable {
  var caseID: String
  var event: String
  var details: InstantLocalID

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLICacheInspectEvidence: Decodable {
  var event: String
  var details: CLICacheInspectOutput
}

private struct CLICacheInspectOutput: Decodable {
  var attributeCount: Int
  var tripleCount: Int
  var queryCacheCount: Int
  var queries: [CLICacheQuerySummary]
}

private struct CLICacheAttributesOutput: Decodable {
  var namespace: String?
  var attributeCount: Int
  var attributes: [InstantAttribute]
}

private struct CLICacheTriplesOutput: Decodable {
  var namespace: String?
  var tripleCount: Int
  var triples: [InstantTriple]
}

private struct CLICacheQuerySummary: Decodable {
  var queryID: String
  var cacheKey: String
  var namespace: String
  var resultCount: Int

  var stableSummary: CLICacheQueryStableSummary {
    CLICacheQueryStableSummary(
      queryID: queryID,
      namespace: namespace,
      resultCount: resultCount
    )
  }
}

private struct CLICacheQueryStableSummary: Hashable {
  var queryID: String
  var namespace: String
  var resultCount: Int
}

private struct CLICacheAttributesEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLICacheAttributesOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLICacheAttributeEvidence: Decodable {
  var event: String
  var details: InstantAttribute
}

private struct CLICacheTriplesEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLICacheTriplesOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLICacheTripleEvidence: Decodable {
  var event: String
  var details: InstantTriple
}

private struct CLIOutboxInspectOutput: Decodable {
  var pendingMutationCount: Int
  var mutationCount: Int
  var mutations: [CLIOutboxMutation]
}

private struct CLIOutboxUpdateOutput: Decodable {
  var mutation: CLIOutboxMutation
}

private struct CLIOutboxDrainEvidence: Decodable {
  var event: String
  var details: CLIOutboxDrainOutput
}

private struct CLIOutboxDrainOutput: Decodable {
  var event: String
  var pendingMutationCount: Int
  var mutationCount: Int
  var drainedMutationCount: Int
  var mutations: [CLIOutboxMutation]
}

private struct CLIOutboxMutation: Decodable, Hashable {
  var id: String
  var status: String
  var failureMessage: String?
}

private struct CLIConnectionStatusOutput: Decodable, Equatable {
  var appID: String
  var cachePath: String
  var event: String
  var apiURI: String
  var websocketURI: String
  var transport: String
  var state: String
  var isAuthenticated: Bool
  var userID: String?
  var pendingMutationCount: Int
  var processedTransactionID: String?
  var lastErrorMessage: String?
}

private struct CLIConnectionStatusEvidence: Decodable {
  var caseID: String
  var event: String
  var ok: Bool
  var details: CLIConnectionStatusOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case ok
    case details
  }
}

private struct CLIAppOutput: Decodable {
  var appID: String
  var event: String
  var transport: String
  var selectionSource: String
  var title: String?
  var isLocalOnly: Bool?
}

private struct CLIAppEvidence: Decodable {
  var event: String
  var details: CLIAppOutput
}

private struct CLIRoomPresenceOutput: Decodable, Equatable {
  var event: String
  var transport: String
  var room: InstantRoomHandle
  var userID: String?
  var memberCount: Int
  var members: [InstantRoomPresenceMember]
}

private struct CLIRoomPresenceEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIRoomPresenceOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIRoomTopicOutput: Decodable, Equatable {
  var event: String
  var transport: String
  var room: InstantRoomHandle
  var topic: String
  var publishedMessageID: String?
  var messageCount: Int
  var messages: [InstantRoomTopicMessage]
}

private struct CLIRoomTopicEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIRoomTopicOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIRoomTopicMessageEvidence: Decodable {
  var event: String
  var details: InstantRoomTopicMessage
}

private struct CLIReactionsRecipeOutput: Decodable, Equatable {
  var event: String
  var publishedMessageID: String?
  var authUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var topic: String
  var messageCount: Int
  var reactionCount: Int
  var messages: [CLIReactionsRecipeMessage]
  var reactions: [ReactionsRecipeReaction]
}

private struct CLIReactionsRecipeMessage: Decodable, Equatable {
  var id: String
  var appID: String
  var room: InstantRoomHandle
  var topic: String
  var userID: String
  var payload: CLIReactionsRecipePayload
  var createdAt: InstantTimestamp
}

private struct CLIReactionsRecipePayload: Decodable, Equatable {
  var name: String
  var directionAngle: Double
  var rotationAngle: Double
}

private struct CLIReactionsRecipeEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIReactionsRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIReactionsRecipeReactionEvidence: Decodable {
  var event: String
  var details: ReactionsRecipeReaction
}

private struct CLITypingIndicatorRecipeOutput: Decodable, Equatable {
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var inputName: String
  var memberCount: Int
  var activeCount: Int
  var typingInfo: String?
  var members: [TypingIndicatorRecipeMember]
  var activeMembers: [TypingIndicatorRecipeMember]
}

private struct CLITypingIndicatorRecipeEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLITypingIndicatorRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLITypingIndicatorRecipeMemberEvidence: Decodable {
  var event: String
  var details: TypingIndicatorRecipeMember
}

private struct CLIAvatarStackRecipeOutput: Decodable, Equatable {
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var nameKey: String
  var memberCount: Int
  var peerCount: Int
  var onlineCount: Int
  var currentUser: AvatarStackRecipeMember?
  var peers: [AvatarStackRecipeMember]
  var members: [AvatarStackRecipeMember]
}

private struct CLIAvatarStackRecipeEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIAvatarStackRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIAvatarStackRecipeMemberEvidence: Decodable {
  var event: String
  var details: AvatarStackRecipeMember
}

private struct CLICursorsRecipeOutput: Decodable, Equatable {
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var spaceID: String
  var nameKey: String?
  var memberCount: Int
  var cursorCount: Int
  var visibleCursors: [CursorsRecipeCursor]
  var members: [CursorsRecipeCursor]
}

private struct CLICursorsRecipeEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLICursorsRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLICursorsRecipeCursorEvidence: Decodable {
  var event: String
  var details: CursorsRecipeCursor
}

private struct CLIMergeTileGameRecipeOutput: Decodable, Equatable {
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var boardID: String
  var boardSize: Int
  var emptyColor: String
  var colors: [String]
  var colorKey: String
  var playerCount: Int
  var filledCount: Int
  var currentPlayer: MergeTileGamePlayer?
  var peers: [MergeTileGamePlayer]
  var players: [MergeTileGamePlayer]
  var availableColors: [String]
  var board: MergeTileGameBoard?
  var paintedCells: [CLIMergeTileGameCellOutput]
}

private struct CLIMergeTileGameCellOutput: Decodable, Equatable {
  var boardID: String
  var key: String
  var row: Int
  var column: Int
  var color: String
}

private struct CLIMergeTileGameRecipeEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIMergeTileGameRecipeOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIMergeTileGameRecipeDetailEvidence: Decodable {
  var event: String
}

private struct CLIFilesOutput: Decodable, Equatable {
  var event: String
  var changedID: String?
  var transport: String
  var fileCount: Int
  var files: [InstantStoredFile]
}

private struct CLIFilesEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIFilesOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIFileContentsOutput: Decodable, Equatable {
  var event: String
  var transport: String
  var file: InstantStoredFile
  var byteCount: Int64
  var base64Content: String
  var utf8Content: String?
}

private struct CLIFileContentsEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIFileContentsOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIFileUploadProgressSummaryOutput: Decodable {
  var event: String
  var transport: String
  var emittedEventCount: Int
  var finalState: InstantStorageOperationState
  var events: [CLIFileUploadProgressOutput]
}

private struct CLIFileUploadProgressOutput: Decodable {
  var state: InstantStorageOperationState
  var completedByteCount: Int64
  var file: InstantStoredFile?
}

private struct CLIFileUploadProgressEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIFileUploadProgressOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIStreamsOutput: Decodable, Equatable {
  var event: String
  var changedID: String?
  var transport: String
  var streamID: String
  var chunkCount: Int
  var chunks: [InstantStreamChunk]
}

private struct CLIStreamsEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIStreamsOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIStreamChunkEvidence: Decodable {
  var caseID: String
  var event: String
  var details: InstantStreamChunk

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIShareOutput: Decodable, Equatable {
  var event: String
  var changedID: String?
  var transport: String
  var shareCount: Int
  var shares: [InstantShareSnapshot]
}

private struct CLIShareEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIShareOutput

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIShareSnapshotEvidence: Decodable {
  var event: String
  var details: InstantShareSnapshot
}

private struct CLILocalTodoValidationOutput: Decodable {
  var appID: String
  var event: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var finalTodoCount: Int
  var pendingMutationCount: Int
}

private struct CLILocalTodoValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var details: CLILocalTodoValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case details
  }
}

private struct CLILocalTodoValidationDetails: Decodable {
  var todoTexts: [String]
  var pendingMutationIDs: [String]
  var confirmedMutationIDs: [String]
  var connectionState: String
}

private struct CLILocalIntegrationValidationOutput: Decodable {
  var appID: String
  var event: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var authUserID: String?
  var roomMemberCount: Int
  var topicMessageCount: Int
  var fileCount: Int
  var streamChunkCount: Int
  var activeShareCount: Int
  var revokedShareCount: Int
}

private struct CLILocalIntegrationValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var details: CLILocalIntegrationValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case details
  }
}

private struct CLILocalIntegrationValidationDetails: Decodable {
  var authUserID: String?
  var fileIDs: [String]
  var fileByteCounts: [Int64]
  var fileContentDigests: [String]
  var activeShareIDs: [String]
  var revokedShareIDs: [String]
  var shareMemberUserIDs: [String]
}

private struct CLIRemindersValidationOutput: Decodable {
  var appID: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var listCount: Int
  var reminderCount: Int
  var completedReminderCount: Int
  var tagCount: Int
  var activeShareCount: Int
  var rejectedOperations: [String]
  var pendingMutationCount: Int
  var stats: RemindersStats
}

private struct CLIRemindersValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var ok: Bool
  var details: CLIRemindersValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case ok
    case details
  }
}

private struct CLIRemindersValidationDetails: Decodable {
  var reminderIDs: [String]
  var reminderTitles: [String]
  var reminderNotes: [String]
  var tagTitles: [String]
  var reminderTagIDs: [String]
  var rejectedOperations: [String]
}

private struct CLIDraftValidationOutput: Decodable {
  var appID: String
  var event: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var newDraftIDWasNil: Bool
  var newDraftAssignmentAttributeIDs: [String]
  var newDraftIncludedPrimaryKeyAssignment: Bool
  var draftTodoAttributeIDs: [String]
  var draftTodoTitles: [String]
  var draftTodoCompletionStates: [Bool]
  var draftTodoNotes: [String?]
  var draftAuthorIDs: [String]
  var draftAuthorNames: [String]
  var draftPostAttributeIDs: [String]
  var draftPostIDs: [String]
  var draftPostTitles: [String]
  var draftPostAuthorIDs: [String]
  var draftPostAuthorAttributeValueType: String?
  var draftPostAuthorLinkNamespace: String?
  var draftPostAuthorForwardIdentity: String?
  var draftPostAuthorReverseIdentity: String?
  var draftMutationSummaries: [CLIDraftValidationMutationSummary]
  var pendingMutationCount: Int
  var createdID: String?
  var editedID: String?
  var relationAuthorID: String?
  var relationPostID: String?
}

private struct CLIDraftValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var entityID: String?
  var details: CLIDraftValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case entityID
    case details
  }
}

private struct CLIDraftValidationDetails: Decodable {
  var newDraftIDWasNil: Bool
  var newDraftAssignmentAttributeIDs: [String]
  var newDraftIncludedPrimaryKeyAssignment: Bool
  var draftTodoAttributeIDs: [String]
  var draftTodoTitles: [String]
  var draftTodoCompletionStates: [Bool]
  var draftTodoNotes: [String?]
  var draftAuthorIDs: [String]
  var draftAuthorNames: [String]
  var draftPostAttributeIDs: [String]
  var draftPostIDs: [String]
  var draftPostTitles: [String]
  var draftPostAuthorIDs: [String]
  var draftPostAuthorAttributeValueType: String?
  var draftPostAuthorLinkNamespace: String?
  var draftPostAuthorForwardIdentity: String?
  var draftPostAuthorReverseIdentity: String?
  var draftMutationSummaries: [CLIDraftValidationMutationSummary]
  var pendingMutationIDs: [String]
  var createdID: String?
  var editedID: String?
  var relationAuthorID: String?
  var relationPostID: String?
}

private struct CLIDraftValidationMutationSummary: Decodable, Equatable {
  var mutationID: String
  var transactionID: String
  var status: String
  var operationKinds: [String]
  var preconditionKinds: [String]
  var preconditionNamespaces: [String]
  var txStepKinds: [String]
  var txStepEntityIDs: [String]
  var txStepAttributeIDs: [String]
  var txStepValueTypes: [String]
  var txStepValueSummaries: [String]
  var txStepOptionModes: [String]
  var operationValueTypes: [String]
  var operationValueSummaries: [String]
  var primaryKeyStepCount: Int
  var draftAssignmentAttributeIDs: [String]
  var refAttributeIDs: [String]
}

private struct CLIPlatformAdapterValidationOutput: Decodable {
  var appID: String
  var event: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var adapters: [String]
  var bindingAdapterCount: Int
  var bindingAdapters: [String]
  var todoCount: Int
  var selectedTodoID: String?
  var localID: String?
  var authUserID: String?
  var roomMemberCount: Int
  var topicMessageCount: Int
  var fileCount: Int
  var streamChunkCount: Int
  var shareCount: Int
  var lifecycleEventCount: Int
  var queryProbeCount: Int
  var observationProbeCount: Int
  var loadErrorOperations: [String]
  var cancellationTerminated: Bool
}

private struct CLIPlatformAdapterValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var details: CLIPlatformAdapterValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case details
  }
}

private struct CLIPlatformAdapterValidationDetails: Decodable {
  var adapter: String
  var bindingAdapters: [String]
  var todoTitles: [String]
  var previousTodoTitles: [String]
  var todoCount: Int
  var selectedTodoID: String?
  var selectedTodoTitle: String?
  var localID: String?
  var authUserID: String?
  var roomMemberIDs: [String]
  var topicMessageIDs: [String]
  var fileIDs: [String]
  var streamChunkIDs: [String]
  var shareIDs: [String]
  var fetchAllTitleBatches: [[String]]?
  var fetchTitleBatches: [[String]]?
  var queryCount: Int?
  var observationCount: Int?
  var nilQueryCleared: Bool?
  var nilRequestCleared: Bool?
  var cancellationTerminated: Bool?
}

private struct CLISyncUpsRecordingValidationOutput: Decodable {
  var appID: String
  var event: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var meetingID: String
  var meetingTranscripts: [String]
  var transcript: String
  var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  var requestedAuthorization: Bool
  var loadedSoundEffectFileName: String?
  var speechResultCount: Int
  var soundEffectPlayCount: Int
  var secondsElapsed: Int
  var speakerIndex: Int
  var currentSpeakerName: String?
  var openSettingsCount: Int
  var finalAlert: CLIRecordingAlert?
  var isDismissed: Bool
}

private struct CLISyncUpsRecordingValidationEvidence: Decodable {
  var caseID: String
  var appID: String
  var event: String
  var details: CLISyncUpsRecordingValidationDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case appID
    case event
    case details
  }
}

private struct CLISyncUpsRecordingValidationDetails: Decodable {
  var syncUpTitles: [String]
  var attendeeNames: [String]
  var meetingIDs: [String]
  var meetingTranscripts: [String]
  var recording: CLISyncUpsRecordingValidationSummary?
  var tickEvent: String?
  var alertOutcome: SyncUpRecordingAlertOutcome?
  var openSettingsCount: Int
}

private struct CLISyncUpsRecordingValidationSummary: Decodable {
  var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  var soundEffectPlayCount: Int
  var secondsElapsed: Int
  var currentSpeakerName: String?
  var alert: CLIRecordingAlert?
}

private enum CLIRecordingAlert: Equatable, Decodable {
  case endMeeting
  case speechRecognitionDenied
  case speechRecognitionFailed

  private enum CodingKeys: String, CodingKey {
    case endMeeting
    case speechRecognitionDenied
    case speechRecognitionFailed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.speechRecognitionDenied) {
      self = .speechRecognitionDenied
    } else if container.contains(.speechRecognitionFailed) {
      self = .speechRecognitionFailed
    } else if container.contains(.endMeeting) {
      self = .endMeeting
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown SyncUps recording alert."
        )
      )
    }
  }
}

private struct CLIParityCoverageOutput: Decodable {
  var event: String
  var coverageComplete: Bool
  var recordCount: Int
  var exactCount: Int
  var adaptedCount: Int
  var blockedCount: Int
  var notApplicableCount: Int
  var sourceFiles: [String]
  var swiftFiles: [String]
  var records: [CLIParityCoverageRecord]
}

private struct CLIParityCoverageRecord: Decodable {
  var id: String
  var sourceKind: String
  var sourceFile: String
  var sourceTestName: String
  var swiftFile: String
  var swiftTestName: String
  var surface: String
  var status: String
  var notes: String
}

private struct CLIParityCoverageEvidence: Decodable {
  var caseID: String
  var side: String
  var event: String
  var appID: String
  var entityID: String?
  var ok: Bool
  var details: CLIParityCoverageRecord

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case appID
    case entityID
    case ok
    case details
  }
}

private struct CLIBenchmarkOutput: Decodable {
  var suite: String
  var appID: String
  var transport: String
  var iterations: Int
  var ok: Bool
  var metrics: [CLIBenchmarkMetric]
  var finalTodoCount: Int
  var pendingMutationCount: Int
}

private struct CLIBenchmarkMetric: Decodable, Equatable {
  var name: String
  var samples: [CLIBenchmarkSample]
}

private struct CLIBenchmarkSample: Decodable, Equatable {
  var operationCount: Int?
  var resultCount: Int?
  var pendingMutationCount: Int?
  var memoryDeltaBytes: UInt64?
  var memoryBudgetBytes: UInt64?
  var actorHopCount: Int?
  var actorHopBreakdown: [String: Int]?
}

private struct CLIBenchmarkEvidence: Decodable {
  var caseID: String
  var event: String
  var details: CLIBenchmarkEvidenceDetails

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case details
  }
}

private struct CLIBenchmarkEvidenceDetails: Decodable {
  var transport: String
  var iterations: Int
  var metric: CLIBenchmarkMetric?
}

private struct CLITestError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
