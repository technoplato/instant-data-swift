import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantQueryValidationParityTests {
  @Test
  func upstreamTopLevelEntityNames() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "top level entitiy names",
      assertion: "lines 106-127 namespace validation",
      status: "adapted: Swift validates one InstantQueryPlan namespace at a time."
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "query-validation-parity.posts", namespace: "posts")
    )
    expectNoDifference(posts, [], source)

    let users = try await runtime.query(
      InstantQueryPlan(id: "query-validation-parity.users", namespace: "users")
    )
    expectNoDifference(users, [], source)

    await expectQueryValidation(
      namespace: "notInSchema",
      path: nil,
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(id: "query-validation-parity.not-in-schema", namespace: "notInSchema")
      )
    }

    let schemalessRuntime = try await queryValidationRuntime(initialAttributes: [])
    let schemaless = try await schemalessRuntime.query(
      InstantQueryPlan(
        id: "query-validation-parity.schemaless-random",
        namespace: "somethingsuperRandomButNoSchema"
      )
    )
    expectNoDifference(schemaless, [], source)
  }
}

private let upstreamQueryValidationTestSource =
  "upstream/instant/client/packages/core/__tests__/src/queryValidation.test.ts"

private func queryValidationSource(
  _ testName: String,
  assertion: String,
  status: String
) -> String {
  "\(upstreamQueryValidationTestSource) \(testName) \(assertion) [\(status)]"
}

private func queryValidationRuntime(
  initialAttributes: [InstantAttribute] = queryValidationParityAttributes()
) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "query-validation-parity",
      persistenceURL: temporaryQueryValidationCacheURL(),
      initialAttributes: initialAttributes
    )
  )
}

private func temporaryQueryValidationCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataQueryValidationParity-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func queryValidationParityAttributes() -> [InstantAttribute] {
  [
    InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/title",
      namespace: "posts",
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
  ]
}

private func expectQueryValidation(
  namespace: String,
  path: String?,
  _ source: String,
  operation: () async throws -> Void
) async {
  do {
    try await operation()
    #expect(Bool(false), "Expected query validation to fail. \(source)")
  } catch let error as InstantError {
    expectNoDifference(error.code, .validationFailed, source)
    expectNoDifference(error.operation, "validate query", source)
    expectNoDifference(error.namespace, namespace, source)
    expectNoDifference(error.path, path, source)
  } catch {
    #expect(Bool(false), "Unexpected error: \(error). \(source)")
  }
}
