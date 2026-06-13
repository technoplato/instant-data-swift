import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantTransactionValidationParityTests {
  @Test
  func upstreamAllowsLookupValuesForEntityWrites() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-user",
        operations: [
          .insert(triple("user-1", "users/name", .string("Before"), txID: "tx-parity-seed-user", time: time)),
          .insert(triple("user-1", "users/email", .string("john@example.net"), txID: "tx-parity-seed-user", time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in square bracket",
      assertion: "line 392 lookup source update",
      status: "adapted: Swift core uses insertByLookup over a declared unique attribute."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-update-user-by-lookup",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(attributeID: "users/email", value: .string("john@example.net")),
            attributeID: "users/name",
            value: .string("John"),
            txID: "tx-parity-update-user-by-lookup",
            txTime: time
          )
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(
      InstantQueryPlan(id: "parity.users", namespace: "users")
    )
    expectNoDifference(users.map { $0.values["name"]?.first }, [.string("John")], source)
  }

  @Test
  func upstreamAllowsLookupValuesInLinks() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_050)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-source-link-lookup",
        operations: [
          .insert(triple("user-1", "users/name", .string("John"), txID: "tx-parity-seed-source-link-lookup", time: time)),
          .insert(triple("user-1", "users/email", .string("john@example.net"), txID: "tx-parity-seed-source-link-lookup", time: time)),
          .insert(triple("post-1", "posts/title", .string("Hello"), txID: "tx-parity-seed-source-link-lookup", time: time)),
          .insert(triple("post-1", "posts/slug", .string("hello"), txID: "tx-parity-seed-source-link-lookup", time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in link",
      assertion: "line 398 lookup link value",
      status:
        "adapted: Swift stores users.posts as posts.author, so the linked post lookup is the physical posts/author entity and uses unique posts/slug."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link-source-by-lookup",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(attributeID: "posts/slug", value: .string("hello")),
            attributeID: "posts/author",
            value: .ref("user-1"),
            txID: "tx-parity-link-source-by-lookup",
            txTime: time
          )
        ]
      ),
      createdAt: time
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "parity.lookup-source.posts", namespace: "posts")
    )
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-1")], source)
  }

  @Test
  func upstreamAllowsLookupSourceIDsInLinks() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_100)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-link-lookup",
        operations: [
          .insert(triple("user-1", "users/name", .string("John"), txID: "tx-parity-seed-link-lookup", time: time)),
          .insert(triple("user-1", "users/email", .string("john@example.net"), txID: "tx-parity-seed-link-lookup", time: time)),
          .insert(triple("post-1", "posts/title", .string("Hello"), txID: "tx-parity-seed-link-lookup", time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in square bracket",
      assertion: "line 394 lookup source link",
      status:
        "adapted: Swift stores users.posts as posts.author, so the source user lookup is the physical posts/author ref value."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link-by-lookup",
        operations: [
          .insert(
            triple(
              "post-1",
              "posts/author",
              .lookupRef(InstantLookupRef(attributeID: "users/email", value: .string("john@example.net"))),
              txID: "tx-parity-link-by-lookup",
              time: time
            )
          )
        ]
      ),
      createdAt: time
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "parity.posts", namespace: "posts")
    )
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-1")], source)
  }

  @Test
  func upstreamRejectsNonUniqueLookupAttributes() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_200)
    let source = transactionValidationSource(
      "lookup proxy",
      assertion: "line 444 TypeScript-only non-unique lookup constraint",
      status:
        "Swift-only adaptation: upstream enforces this at compile time; Swift core rejects non-unique lookup attrs at runtime."
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-nonunique-lookup",
          operations: [
            .insertByLookup(
              entity: InstantLookupRef(attributeID: "users/name", value: .string("John")),
              attributeID: "users/email",
              value: .string("john@example.net"),
              txID: "tx-parity-nonunique-lookup",
              txTime: time
            )
          ]
        ),
        createdAt: time
      )
      #expect(Bool(false), "Expected non-unique lookup to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "lookup entity", source)
      expectNoDifference(error.namespace, "users", source)
      expectNoDifference(error.path, "name", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }
  }

  @Test
  func upstreamRejectsLookupValuesThatDoNotMatchLinkNamespace() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_300)
    let source =
      "Swift-only additional coverage: lookup refs for ref values must belong to the declared link namespace."

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-wrong-link-lookup",
          operations: [
            .insert(
              triple(
                "post-1",
                "posts/author",
                .lookupRef(InstantLookupRef(attributeID: "posts/slug", value: .string("hello"))),
                txID: "tx-parity-wrong-link-lookup",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
      #expect(Bool(false), "Expected wrong-namespace link lookup to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "lookup entity", source)
      expectNoDifference(error.namespace, "users", source)
      expectNoDifference(error.path, "slug", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }
  }
}

private let upstreamTransactionValidationTestSource =
  "upstream/instant/client/packages/core/__tests__/src/transactionValidation.test.ts"

private func transactionValidationSource(
  _ testName: String,
  assertion: String,
  status: String
) -> String {
  "\(upstreamTransactionValidationTestSource) \(testName) \(assertion) [\(status)]"
}

private func parityRuntime() async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "transaction-validation-parity",
      persistenceURL: temporaryParityCacheURL(),
      initialAttributes: transactionValidationParityAttributes()
    )
  )
}

private func temporaryParityCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataTransactionParity-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func transactionValidationParityAttributes() -> [InstantAttribute] {
  // Adapted from transactionValidation.test.ts: Swift core needs explicit unique
  // lookup attributes and stores the users.posts link as posts.author.
  [
    InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "users/email",
      namespace: "users",
      name: "email",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "posts/title",
      namespace: "posts",
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/slug",
      namespace: "posts",
      name: "slug",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "posts/author",
      namespace: "posts",
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/author",
      reverseIdentity: "users/posts",
      linkNamespace: "users"
    ),
  ]
}

private func triple(
  _ entityID: String,
  _ attributeID: String,
  _ value: InstantValue,
  txID: String,
  time: InstantTimestamp
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attributeID,
    value: value,
    txID: txID,
    txTime: time
  )
}
