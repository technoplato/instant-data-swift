import CloudKitDemoV3App
import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite
struct CloudKitDemoV3LifecycleTests {
  @Test
  func createGrantPromoteIncrementRevokeAndRelaunch() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("cloudkit-demo-v3-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let appID = "cloudkit-demo-v3-lifecycle"
    let ownerID = InstantID<CloudKitDemoV3User>(rawValue: "owner")
    let memberID = InstantID<CloudKitDemoV3User>(rawValue: "member")
    let counterID = InstantID<CloudKitDemoV3Counter>(rawValue: "counter")
    let shareID = InstantID<CloudKitDemoV3Share>(rawValue: "share")
    let ownerMembershipID = InstantID<CloudKitDemoV3ShareMembership>(rawValue: "membership-owner")
    let memberMembershipID = InstantID<CloudKitDemoV3ShareMembership>(rawValue: "membership-member")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let runtime = try await makeRuntime(appID: appID, persistenceURL: persistenceURL)
    try await seedUsers([ownerID.rawValue, memberID.rawValue], runtime: runtime)
    let client = InstantSwiftDataClient(runtime: runtime)

    try await transact(
      CreateCloudKitDemoV3SharedCounter(
        counterID: counterID,
        shareID: shareID,
        ownerMembershipID: ownerMembershipID,
        ownerID: ownerID,
        title: "Trips",
        token: "share-link-token",
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      AcceptCloudKitDemoV3Share(
        token: "share-link-token",
        membershipID: memberMembershipID,
        userID: memberID,
        acceptedAt: createdAt.addingTimeInterval(1)
      ),
      using: client
    )

    var counters = try await client.query(CloudKitDemoV3Counter.visible(to: memberID))
    expectNoDifference(counters.map(\.value), [0])
    expectNoDifference(counters.first?.share?.memberships.map(\.shareRole), [.owner, .reader])

    try await transact(
      ChangeCloudKitDemoV3ShareRole(
        shareID: shareID,
        membershipID: memberMembershipID,
        counterID: counterID,
        userID: memberID,
        previousRole: .reader,
        role: .writer,
        updatedAt: createdAt.addingTimeInterval(2)
      ),
      using: client
    )
    try await transact(IncrementCloudKitDemoV3Counter(counterID: counterID), using: client)

    counters = try await client.query(CloudKitDemoV3Counter.visible(to: memberID))
    expectNoDifference(counters.map(\.value), [1])
    expectNoDifference(counters.first?.writers, [memberID])
    expectNoDifference(counters.first?.share?.memberships.map(\.shareRole), [.owner, .writer])

    let relaunched = try await makeRuntime(appID: appID, persistenceURL: persistenceURL)
    let relaunchedClient = InstantSwiftDataClient(runtime: relaunched)
    let relaunchedCounters = try await relaunchedClient.query(
      CloudKitDemoV3Counter.visible(to: memberID)
    )
    expectNoDifference(relaunchedCounters.map(\.value), [1])
    expectNoDifference(
      relaunchedCounters.first?.share?.memberships.map(\.shareRole), [.owner, .writer])

    try await transact(
      RevokeCloudKitDemoV3Participant(
        shareID: shareID,
        membershipID: memberMembershipID,
        counterID: counterID,
        userID: memberID,
        role: .writer,
        revokedAt: createdAt.addingTimeInterval(3)
      ),
      using: relaunchedClient
    )
    let revokedMemberCounters = try await relaunchedClient.query(
      CloudKitDemoV3Counter.visible(to: memberID)
    )
    expectNoDifference(revokedMemberCounters, [])
    let ownerCounters = try await relaunchedClient.query(
      CloudKitDemoV3Counter.visible(to: ownerID)
    )
    expectNoDifference(ownerCounters.first?.share?.memberships.map(\.shareRole), [.owner])
  }

  @Test
  func participantRoleChangesRejectOwner() async throws {
    let runtime = try await makeRuntime(
      appID: "cloudkit-demo-v3-role-validation",
      persistenceURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("cloudkit-demo-v3-role-\(UUID().uuidString).sqlite")
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    await #expect(throws: CloudKitDemoV3ShareMessageError.participantRoleRequired(.owner)){
      _ = try await ChangeCloudKitDemoV3ShareRole(
        shareID: InstantID(rawValue: "share"),
        membershipID: InstantID(rawValue: "membership"),
        counterID: InstantID(rawValue: "counter"),
        userID: InstantID(rawValue: "member"),
        previousRole: .reader,
        role: .owner,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ).prepare(using: client)
    }
  }

  private func makeRuntime(appID: String, persistenceURL: URL) async throws -> InstantRuntime {
    try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: persistenceURL,
        initialAttributes: CloudKitDemoV3Schema.attributes
      )
    )
  }

  private func seedUsers(_ userIDs: [String], runtime: InstantRuntime) async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-cloudkit-demo-v3-users",
        operations: userIDs.map { userID in
          .insert(
            InstantTriple(
              entityID: userID,
              attributeID: "$users/id",
              value: .string(userID),
              txID: "seed-cloudkit-demo-v3-users",
              txTime: timestamp
            )
          )
        }
      ),
      createdAt: timestamp
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
}
