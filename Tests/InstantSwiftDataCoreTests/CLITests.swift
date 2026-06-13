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

    let created = try JSONDecoder().decode(
      CLIAdminTransactOutput.self,
      from: Data(
        try runCLI(
          [
            "admin", "transact", "notes", "note-1", "--merge",
            #"{"done":false,"meta":{"source":"cli"},"title":"Admin note"}"#,
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

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutList = try runCLIResult(["files", "list", "--json"], homeURL: homeURL)
    #expect(signedOutList.status == 65)
    #expect(signedOutList.error.contains("File operations require a signed-in user"))
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

    _ = try runCLI(["auth", "sign-out", "--json"], homeURL: homeURL)
    let signedOutRead = try runCLIResult(["streams", "read", "chat/lobby", "--json"], homeURL: homeURL)
    #expect(signedOutRead.status == 65)
    #expect(signedOutRead.error.contains("Stream operations require a signed-in user"))
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

    let created = try JSONDecoder().decode(
      CLIShareOutput.self,
      from: Data(
        try runCLI(["shares", "create", "remindersLists", "list-1", "--json"], homeURL: homeURL)
          .utf8
      )
    )
    expectNoDifference(created.event, "create")
    expectNoDifference(created.transport, "not-implemented-local-cache-only")
    expectNoDifference(created.shareCount, 1)
    let createdSnapshot = try #require(created.shares.first)
    expectNoDifference(created.changedID, createdSnapshot.share.id)
    expectNoDifference(createdSnapshot.share.rootNamespace, "remindersLists")
    expectNoDifference(createdSnapshot.share.rootID, "list-1")
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
    expectNoDifference(jsonOutput.evidenceCount, 5)
    expectNoDifference(jsonOutput.events, ["seed", "update", "cache", "reset", "relaunch"])
    expectNoDifference(jsonOutput.finalTodoCount, 0)
    expectNoDifference(jsonOutput.pendingMutationCount, 3)

    let jsonlOutput = try runCLI(["validation", "local-todos", "--jsonl"], homeURL: homeURL)
    let lines = jsonlOutput.split(separator: "\n")
    expectNoDifference(lines.count, 5)
    let firstEvidence = try JSONDecoder().decode(
      CLILocalTodoValidationEvidence.self,
      from: Data(try #require(lines.first).utf8)
    )
    expectNoDifference(firstEvidence.caseID, "validation.local.todos")
    expectNoDifference(firstEvidence.appID, "cli-cache-test")
    expectNoDifference(firstEvidence.event, "seed")
    expectNoDifference(firstEvidence.details.todoTexts.count, 3)

    let humanOutput = try runCLI(["validation", "local-todos"], homeURL: homeURL)
    #expect(humanOutput.contains("validation: ok"))
    #expect(humanOutput.contains("evidence rows: 5"))

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
    #expect(malformed.error.contains("validation <local-todos>"))
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
    expectNoDifference(jsonOutput.pendingMutationCount, 3)
    expectNoDifference(
      jsonOutput.metrics.map(\.name),
      [
        "bootstrap.local-sqlite",
        "triple-insert.seed",
        "query-materialization.todos",
        "pending-mutation-enqueue.update",
        "query-cache-read.todos",
        "triple-retract.reset",
        "offline-restore.relaunch",
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
    expectNoDifference(lines.count, 8)
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

    try process.run()
    process.waitUntilExit()

    let output = String(
      decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    let error = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
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
  var kind: String
  var fileName: String
  var path: String?
  var byteCount: Int
  var contents: String?
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
