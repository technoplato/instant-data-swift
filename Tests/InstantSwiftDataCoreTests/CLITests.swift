import CustomDump
import Foundation
import Testing

extension InstantStoreTests {
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

    let invalidEvents = try runCLIResult(
      ["examples", "todos", "watch", "--events", "2", "--json"],
      homeURL: homeURL
    )
    #expect(invalidEvents.status == 64)
    #expect(invalidEvents.error.contains("watch --events 1"))
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

  private func runCLI(_ arguments: [String], homeURL: URL) throws -> String {
    let result = try runCLIResult(arguments, homeURL: homeURL)
    guard result.status == 0 else {
      throw CLITestError(
        "instant-swift-data \(arguments.joined(separator: " ")) failed with status \(result.status): \(result.error)"
      )
    }
    return result.output
  }

  private func runCLIResult(_ arguments: [String], homeURL: URL) throws -> CLITestProcessResult {
    let packageURL = packageRootURL()
    let executableURL = packageURL.appendingPathComponent(".build/debug/instant-swift-data")

    let process = Process()
    if FileManager.default.isExecutableFile(atPath: executableURL.path) {
      process.executableURL = executableURL
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["swift", "run", "instant-swift-data"] + arguments
    }
    process.currentDirectoryURL = packageURL
    process.environment = ProcessInfo.processInfo.environment.merging(
      [
        "INSTANT_SWIFT_DATA_HOME": homeURL.path,
        "INSTANT_APP_ID": "cli-cache-test",
      ],
      uniquingKeysWith: { _, new in new }
    )

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
}

private struct CLIAddOutput: Decodable {
  var changedID: String?
}

private struct CLITodosOutput: Decodable {
  var event: String
  var changedID: String?
  var pendingMutationCount: Int
  var todos: [CLITodo]
}

private struct CLITestProcessResult {
  var status: Int32
  var output: String
  var error: String
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

private struct CLITodo: Decodable {
  var text: String
}

private struct CLICacheInspectEvidence: Decodable {
  var event: String
  var details: CLICacheInspectOutput
}

private struct CLICacheInspectOutput: Decodable {
  var queryCacheCount: Int
  var queries: [CLICacheQuerySummary]
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

private struct CLITestError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
