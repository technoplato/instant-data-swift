import AppBuilderV3App
import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite
struct AppBuilderV3MessageTests {
  @Test
  func messagesMaterializeTheOwnerBuildAndFileGraph() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("app-builder-v3-messages-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-builder-v3-message-tests",
        persistenceURL: persistenceURL,
        initialAttributes: AppBuilderV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<AppBuilderV3User>(rawValue: "owner-1")
    let buildID = InstantID<AppBuilderV3Build>(rawValue: "build-1")
    let fileID = InstantID<AppBuilderV3File>(rawValue: "file-1")

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-owner",
        operations: [
          .insert(
            InstantTriple(
              entityID: ownerID.rawValue,
              attributeID: "$users/id",
              value: .string(ownerID.rawValue),
              txID: "seed-owner",
              txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    try await transact(
      CreateAppBuilderV3Build(
        buildID: buildID,
        ownerID: ownerID,
        instantAppID: "generated-app-1",
        title: "Build a workout tracker"
      ),
      using: client
    )
    try await transact(
      UpdateAppBuilderV3Build(
        buildID: buildID,
        code: "export default function App() {}",
        reasoning: "Create a compact preview.",
        isPreviewable: true,
        fileID: fileID
      ),
      using: client
    )

    let builds = try await client.query(AppBuilderV3Build.forOwner(ownerID))
    expectNoDifference(
      builds,
      [
        AppBuilderV3Build(
          id: buildID,
          instantAppID: "generated-app-1",
          code: "export default function App() {}",
          reasoning: "Create a compact preview.",
          isPreviewable: true,
          title: "Build a workout tracker",
          file: fileID,
          owner: ownerID
        )
      ]
    )

    let pending = await client.pendingMutations()
    expectNoDifference(pending.count, 3)
    let createTransport = InstantTransportMutation(pending[1])
    expectNoDifference(createTransport.preconditions.map(\.kind), [.entityMissing])
    expectNoDifference(
      try requiredRef(in: createTransport, attributeID: "builds/owner"),
      .init(value: ownerID.rawValue, mode: .create)
    )
  }

  private func transact<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient
  ) async throws {
    let prepared = try await message.prepare(using: client)
    _ = try await client.transact {
      for mutation in prepared.mutations { mutation }
    }
  }

  private struct RequiredRef: Equatable, Sendable {
    var value: String
    var mode: InstantTransportOptions.Mode?
  }

  private func requiredRef(
    in mutation: InstantTransportMutation,
    attributeID: String
  ) throws -> RequiredRef {
    for step in mutation.txSteps {
      guard case let .addTriple(_, candidateAttributeID, value, options) = step,
        candidateAttributeID == attributeID,
        case let .string(rawValue) = value
      else { continue }
      return RequiredRef(value: rawValue, mode: options?.mode)
    }
    Issue.record("Missing required ref step for \(attributeID)")
    throw CancellationError()
  }
}
