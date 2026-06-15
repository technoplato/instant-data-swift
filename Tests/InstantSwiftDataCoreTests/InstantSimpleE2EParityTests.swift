import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantSimpleE2EParityTests {
  @Test
  func upstreamSimpleE2ECanMakeAQuery() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "simple-e2e-parity",
        persistenceURL: temporarySimpleE2ECacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let plan = InstantQueryPlan(id: "simple.e2e.todos", namespace: TodoExample.namespace)

    let emission = try await runtime.queryOnce(plan)

    expectNoDifference(emission.queryID, "simple.e2e.todos", simpleE2ESource)
    expectNoDifference(emission.values, [], simpleE2ESource)
    expectNoDifference(emission.pageInfo, nil, simpleE2ESource)
  }
}

private let simpleE2ESource =
  "upstream/instant/client/packages/core/__tests__/src/simple.e2e.test.ts can make a query [adapted: Swift proves queryOnce over the local runtime; the browser document mutation is outside the core runtime surface.]"

private func temporarySimpleE2ECacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSimpleE2EParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
