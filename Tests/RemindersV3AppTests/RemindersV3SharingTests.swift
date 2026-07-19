import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

@Suite
struct RemindersV3SharingTests {
  @Test
  func shareAcceptPromoteAndRevokeMaterializeExactVisibleRoles() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-sharing-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-sharing-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(rawValue: "owner-user")
    let memberID = InstantID<RemindersV3User>(rawValue: "member-user")
    let listID = InstantID<RemindersV3List>(rawValue: "list-family")
    let shareID = InstantID<RemindersV3Share>(rawValue: "share-family")
    let ownerMembershipID = InstantID<RemindersV3ShareMembership>(
      rawValue: "membership-owner"
    )
    let memberMembershipID = InstantID<RemindersV3ShareMembership>(
      rawValue: "membership-member"
    )
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    try await seedUsers([ownerID.rawValue, memberID.rawValue], runtime: runtime)

    try await transact(
      CreateRemindersV3List(
        listID: listID,
        ownerID: ownerID,
        title: "Family",
        position: 0,
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      CreateRemindersV3Share(
        shareID: shareID,
        ownerMembershipID: ownerMembershipID,
        listID: listID,
        ownerID: ownerID,
        token: "family-token",
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      AcceptRemindersV3Share(
        shareID: shareID,
        membershipID: memberMembershipID,
        listID: listID,
        userID: memberID,
        role: .reader,
        acceptedAt: createdAt.addingTimeInterval(1)
      ),
      using: client
    )

    let readerLists = FetchAll(RemindersV3List.visible(to: memberID))
    try await readerLists.load(using: client)
    expectNoDifference(readerLists.wrappedValue.map(\.readers), [[memberID]])
    expectNoDifference(readerLists.wrappedValue.map(\.writers), [[]])
    expectNoDifference(
      readerLists.wrappedValue.first?.share?.memberships.map(\.shareRole),
      [.owner, .reader]
    )

    try await transact(
      ChangeRemindersV3ShareRole(
        shareID: shareID,
        membershipID: memberMembershipID,
        listID: listID,
        userID: memberID,
        previousRole: .reader,
        role: .writer,
        updatedAt: createdAt.addingTimeInterval(2)
      ),
      using: client
    )
    try await readerLists.load(using: client)
    expectNoDifference(readerLists.wrappedValue.map(\.readers), [[]])
    expectNoDifference(readerLists.wrappedValue.map(\.writers), [[memberID]])
    expectNoDifference(
      readerLists.wrappedValue.first?.share?.memberships.map(\.shareRole),
      [.owner, .writer]
    )

    try await transact(
      RevokeRemindersV3Share(
        shareID: shareID,
        membershipID: memberMembershipID,
        listID: listID,
        userID: memberID,
        role: .writer,
        revokedAt: createdAt.addingTimeInterval(3)
      ),
      using: client
    )
    try await readerLists.load(using: client)
    expectNoDifference(readerLists.wrappedValue, [])

    let ownerLists = FetchAll(RemindersV3List.visible(to: ownerID))
    try await ownerLists.load(using: client)
    expectNoDifference(
      ownerLists.wrappedValue.first?.share?.revokedAt,
      createdAt.addingTimeInterval(3)
    )
  }

  @Test
  func participantMessagesRejectTheOwnerRole() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-invalid-share-role",
        persistenceURL: FileManager.default.temporaryDirectory
          .appendingPathComponent("reminders-v3-invalid-role-\(UUID().uuidString).sqlite"),
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)

    await #expect(
      throws: RemindersV3ShareMessageError.participantRoleRequired(.owner)
    ) {
      _ = try await AcceptRemindersV3Share(
        shareID: InstantID(rawValue: "share"),
        membershipID: InstantID(rawValue: "membership"),
        listID: InstantID(rawValue: "list"),
        userID: InstantID(rawValue: "user"),
        role: .owner,
        acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ).prepare(using: client)
    }
  }

  private func seedUsers(_ userIDs: [String], runtime: InstantRuntime) async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-share-users",
        operations: userIDs.map { userID in
          .insert(
            InstantTriple(
              entityID: userID,
              attributeID: "$users/id",
              value: .string(userID),
              txID: "seed-share-users",
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
