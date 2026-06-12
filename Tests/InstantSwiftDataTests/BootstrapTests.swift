import CustomDump
import Darwin
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct BootstrapTests {
  @Test
  func defaultClientReportsMissingBootstrap() async {
    @Dependency(\.defaultInstantSwiftData) var client

    do {
      _ = try await client.transact(InstantStoreTransaction(id: "tx", operations: []))
      #expect(Bool(false), "Expected the default client to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.query(TodoExample.query)
      #expect(Bool(false), "Expected the default client query to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func bootstrapInstallsRuntimeBackedClient() async throws {
    let appID = "bootstrap-test-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      guard let runtime = client.runtime else {
        #expect(Bool(false), "Expected a runtime-backed client.")
        return
      }
      #expect(runtime.configuration.persistenceURL.path.contains(fixedUUID.uuidString.lowercased()))

      let localID = try await client.localID(named: "todos.bootstrap")
      expectNoDifference(localID, fixedUUID.uuidString.lowercased())

      let transaction = InstantStoreTransaction(
        id: "tx-bootstrap",
        operations: TodoExample.createOperations(
          id: "todo-bootstrap",
          text: "Use dependencies",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
          transactionID: "tx-bootstrap"
        )
      )
      try await client.transact(transaction)

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(
        todos,
        [
          TodoRecord(
            id: "todo-bootstrap",
            text: "Use dependencies",
            isCompleted: false,
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
          )
        ]
      )
    }
  }

  @Test
  func dependencyOverrideCanInstallMockClient() async throws {
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: 0,
          emissions: []
        )
      },
      query: { _ in
        [
          InstantEntitySnapshot(
            id: "mock-todo",
            namespace: TodoExample.namespace,
            values: [
              "text": .one(.string("Mocked")),
              "isCompleted": .one(.bool(true)),
              "createdAt": .one(.date(Date(timeIntervalSince1970: 1_700_000_001))),
            ]
          )
        ]
      },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let localID = try await client.localID(named: "todo")
      expectNoDifference(localID, "mock-todo")

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(todos.map(\.text), ["Mocked"])
      expectNoDifference(todos.map(\.isCompleted), [true])
    }
  }

  @Test
  func cliDefaultPersistenceURLHonorsHomeEnvironment() {
    let key = "INSTANT_SWIFT_DATA_HOME"
    let previous = getenv(key).map { String(cString: $0) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLIHome-\(UUID().uuidString)", isDirectory: true)

    #expect(setenv(key, directory.path, 1) == 0)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
    }

    let url = DependencyValues.defaultInstantSwiftDataPersistenceURL(
      appID: "ignored-for-cli",
      context: .cli
    )

    expectNoDifference(url.path, directory.appendingPathComponent("state.sqlite").path)
  }
}
