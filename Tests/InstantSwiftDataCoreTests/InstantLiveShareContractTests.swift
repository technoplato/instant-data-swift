import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct InstantLiveShareContractTests {
  @Test("Canonical sharingQuery and sharingSnapshot project exact live share graph")
  func canonicalSharingGraphProjectsInstantShareSnapshot() throws {
    let contract = InstantLiveShareContract.v3SharedLists

    expectNoDifference(contract.queryPlan.namespace, "v3_shared_lists")
    expectNoDifference(contract.queryPlan.includes?.map(\.name), [
      "owner", "readers", "writers", "share",
    ])
    expectNoDifference(
      contract.queryPlan.includes?.map(\.direction),
      [.forward, .forward, .forward, .reverse]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.map(\.name),
      ["owner", "memberships"]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.map(\.direction),
      [.forward, .reverse]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.last?.query?.includes?.map(\.name),
      ["user"]
    )

    let owner = InstantLinkedEntitySnapshot(
      id: "owner-1",
      namespace: "$users",
      values: [:]
    )
    let reader = membership(
      id: "membership-reader",
      userID: "reader-1",
      role: "reader",
      acceptedAt: 1_700_000_001_000
    )
    let writer = membership(
      id: "membership-writer",
      userID: "writer-1",
      role: "writer",
      acceptedAt: 1_700_000_002_000
    )
    let ownerMembership = membership(
      id: "membership-owner",
      userID: "owner-1",
      role: "owner",
      acceptedAt: 1_700_000_000_000
    )
    let share = InstantLinkedEntitySnapshot(
      id: "share-1",
      namespace: "v3_shares",
      values: [
        "token": .one(.string("share-token")),
        "rootNamespace": .one(.string("v3_shared_lists")),
        "rootID": .one(.string("list-1")),
        "createdAt": .one(.date(date(1_700_000_000_000))),
        "updatedAt": .one(.date(date(1_700_000_003_000))),
      ],
      links: [
        "owner": [owner],
        "memberships": [ownerMembership, reader, writer],
      ]
    )
    let root = InstantEntitySnapshot(
      id: "list-1",
      namespace: "v3_shared_lists",
      values: [
        "title": .one(.string("Canonical shared list")),
        "value": .one(.number(3)),
      ],
      links: [
        "owner": [owner],
        "readers": [
          InstantLinkedEntitySnapshot(id: "reader-1", namespace: "$users", values: [:])
        ],
        "writers": [
          InstantLinkedEntitySnapshot(id: "writer-1", namespace: "$users", values: [:])
        ],
        "share": [share],
      ]
    )

    expectNoDifference(
      try contract.snapshots(
        appID: "app-1",
        roots: [
          InstantEntitySnapshot(
            id: "cached-unshared-list",
            namespace: "v3_shared_lists",
            values: ["title": .one(.string("Not a share"))]
          ),
          root,
        ]
      ),
      [
        InstantShareSnapshot(
          share: InstantShare(
            id: "share-1",
            appID: "app-1",
            rootNamespace: "v3_shared_lists",
            rootID: "list-1",
            ownerUserID: "owner-1",
            token: "share-token",
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
            updatedAt: InstantTimestamp(milliseconds: 1_700_000_003_000)
          ),
          memberships: [
            InstantShareMembership(
              appID: "app-1",
              shareID: "share-1",
              userID: "owner-1",
              role: .owner,
              acceptedAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
            ),
            InstantShareMembership(
              appID: "app-1",
              shareID: "share-1",
              userID: "reader-1",
              role: .reader,
              acceptedAt: InstantTimestamp(milliseconds: 1_700_000_001_000)
            ),
            InstantShareMembership(
              appID: "app-1",
              shareID: "share-1",
              userID: "writer-1",
              role: .writer,
              acceptedAt: InstantTimestamp(milliseconds: 1_700_000_002_000)
            ),
          ]
        )
      ]
    )
  }

  @Test("Canonical live share graph can target the VoiceTrail recording root")
  func canonicalSharingGraphTargetsV3CaptureRecordings() {
    let contract = InstantLiveShareContract.v3CaptureRecordings

    expectNoDifference(contract.queryPlan.namespace, "v3_capture_recordings")
    expectNoDifference(contract.queryPlan.includes?.map(\.name), [
      "owner", "share",
    ])
    expectNoDifference(
      contract.queryPlan.includes?.map(\.direction),
      [.forward, .reverse]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.map(\.name),
      ["owner", "memberships"]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.map(\.direction),
      [.forward, .reverse]
    )
    expectNoDifference(
      contract.queryPlan.includes?.last?.query?.includes?.last?.query?.includes?.map(\.name),
      ["user"]
    )
  }

  @Test("Live share emissions replace roles, revoke snapshots, and preserve cancellation")
  func liveShareEmissionStreamProjectsReplacementAndRevocation() async throws {
    let contract = InstantLiveShareContract.v3SharedLists
    let termination = LiveShareSourceTermination()
    let recorder = LiveShareProjectionRecorder()
    let failures = LiveShareFailureRecorder()
    let source = AsyncStream<InstantQueryEmission>(bufferingPolicy: .unbounded) {
      continuation in
      continuation.yield(emission(sequence: 0, roots: []))
      continuation.yield(
        emission(
          sequence: 1,
          roots: [
            InstantEntitySnapshot(
              id: "list-1",
              namespace: "v3_shared_lists",
              values: ["title": .one(.string("Cached before nested query result"))]
            )
          ]
        )
      )
      continuation.yield(emission(sequence: 2, roots: [shareRoot(memberRole: "reader")]))
      continuation.yield(emission(sequence: 3, roots: [shareRoot(memberRole: "writer")]))
      continuation.yield(emission(sequence: 4, roots: []))
      continuation.onTermination = { @Sendable _ in
        Task { await termination.record() }
      }
    }
    let snapshots = contract.observe(appID: "app-1", emissions: source) { error in
      await failures.record(error)
    }
    let observation = Task {
      for await value in snapshots {
        await recorder.record(value)
      }
    }
    await recorder.waitForCount(5)
    observation.cancel()
    await observation.value
    await termination.wait()

    let values = await recorder.values()
    let recordedFailures = await failures.values()
    expectNoDifference(recordedFailures, [])
    expectNoDifference(values[0], [])
    expectNoDifference(values[1], [])
    expectNoDifference(
      values[2].first?.memberships.map(\.role),
      [InstantShareRole.owner, .reader]
    )
    expectNoDifference(
      values[3].first?.memberships.map(\.role),
      [InstantShareRole.owner, .writer]
    )
    expectNoDifference(values[4], [])
  }

  @Test("Runtime shares and observation use the configured live share contract")
  func runtimeSharesUseConfiguredLiveContract() async throws {
    let queryIssue = TripleIndexes.validate(
      InstantLiveShareContract.v3SharedLists.queryPlan,
      attributes: AttributeStore(attributes: liveShareAttributes)
    )
    expectNoDifference(queryIssue, nil)
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-live-share-runtime-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        persistenceURL: persistenceURL,
        initialAttributes: liveShareAttributes,
        liveShareContract: .v3SharedLists
      )
    )
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "owner-1")
    let stream = try await runtime.observeShares()
    var iterator = stream.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, [])

    _ = try await runtime.applyServerTransaction(liveShareSeedTransaction)

    let observed = try #require(await iterator.next())
    expectNoDifference(observed.map(\.share.id), ["share-1"])
    expectNoDifference(observed.first?.memberships.map(\.role), [.owner, .reader])
    let listed = try await runtime.shares()
    expectNoDifference(listed, observed)
  }

  private func membership(
    id: String,
    userID: String,
    role: String,
    acceptedAt: Int64
  ) -> InstantLinkedEntitySnapshot {
    InstantLinkedEntitySnapshot(
      id: id,
      namespace: "v3_share_memberships",
      values: [
        "role": .one(.string(role)),
        "acceptedAt": .one(.date(date(acceptedAt))),
      ],
      links: [
        "user": [InstantLinkedEntitySnapshot(id: userID, namespace: "$users", values: [:])]
      ]
    )
  }

  private func emission(
    sequence: Int64,
    roots: [InstantEntitySnapshot]
  ) -> InstantQueryEmission {
    InstantQueryEmission(
      queryID: InstantLiveShareContract.v3SharedLists.queryPlan.id,
      sequence: sequence,
      values: roots
    )
  }

  private func shareRoot(memberRole: String) -> InstantEntitySnapshot {
    let owner = InstantLinkedEntitySnapshot(
      id: "owner-1",
      namespace: "$users",
      values: [:]
    )
    let share = InstantLinkedEntitySnapshot(
      id: "share-1",
      namespace: "v3_shares",
      values: [
        "token": .one(.string("share-token")),
        "rootNamespace": .one(.string("v3_shared_lists")),
        "rootID": .one(.string("list-1")),
        "createdAt": .one(.date(date(1_700_000_000_000))),
        "updatedAt": .one(.date(date(1_700_000_003_000))),
      ],
      links: [
        "owner": [owner],
        "memberships": [
          membership(
            id: "membership-owner",
            userID: "owner-1",
            role: "owner",
            acceptedAt: 1_700_000_000_000
          ),
          membership(
            id: "membership-member",
            userID: "member-1",
            role: memberRole,
            acceptedAt: 1_700_000_001_000
          ),
        ],
      ]
    )
    return InstantEntitySnapshot(
      id: "list-1",
      namespace: "v3_shared_lists",
      values: ["title": .one(.string("Shared list"))],
      links: [
        "owner": [owner],
        "readers": memberRole == "reader"
          ? [InstantLinkedEntitySnapshot(id: "member-1", namespace: "$users", values: [:])]
          : [],
        "writers": memberRole == "writer"
          ? [InstantLinkedEntitySnapshot(id: "member-1", namespace: "$users", values: [:])]
          : [],
        "share": [share],
      ]
    )
  }

  private func date(_ milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  private var liveShareAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: "$users"),
      .primaryKey(namespace: "v3_shared_lists"),
      .primaryKey(namespace: "v3_shares"),
      .primaryKey(namespace: "v3_share_memberships"),
      scalar("v3_shares", "token", .string),
      scalar("v3_shares", "rootNamespace", .string),
      scalar("v3_shares", "rootID", .string),
      scalar("v3_shares", "createdAt", .date),
      scalar("v3_shares", "updatedAt", .date),
      scalar("v3_share_memberships", "role", .string),
      scalar("v3_share_memberships", "acceptedAt", .date),
      link("v3_shared_lists", "owner", "$users", "ownedSharedLists", .one),
      link("v3_shared_lists", "readers", "$users", "readableSharedLists", .many),
      link("v3_shared_lists", "writers", "$users", "writableSharedLists", .many),
      link("v3_shares", "owner", "$users", "ownedShares", .one),
      link("v3_shares", "root", "v3_shared_lists", "share", .one),
      link("v3_share_memberships", "share", "v3_shares", "memberships", .one),
      link("v3_share_memberships", "user", "$users", "shareMemberships", .one),
    ]
  }

  private var liveShareSeedTransaction: InstantStoreTransaction {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txID: "live-share-seed",
        txTime: time
      )
    }
    return InstantStoreTransaction(
      id: "live-share-seed",
      operations: [
        .insert(triple("owner-1", "$users/id", .string("owner-1"))),
        .insert(triple("reader-1", "$users/id", .string("reader-1"))),
        .insert(triple("list-1", "v3_shared_lists/id", .string("list-1"))),
        .insert(triple("list-1", "v3_shared_lists/owner", .ref("owner-1"))),
        .insert(triple("list-1", "v3_shared_lists/readers", .ref("reader-1"))),
        .insert(triple("share-1", "v3_shares/id", .string("share-1"))),
        .insert(triple("share-1", "v3_shares/token", .string("share-token"))),
        .insert(triple("share-1", "v3_shares/rootNamespace", .string("v3_shared_lists"))),
        .insert(triple("share-1", "v3_shares/rootID", .string("list-1"))),
        .insert(triple("share-1", "v3_shares/createdAt", .date(date(1_700_000_000_000)))),
        .insert(triple("share-1", "v3_shares/updatedAt", .date(date(1_700_000_003_000)))),
        .insert(triple("share-1", "v3_shares/owner", .ref("owner-1"))),
        .insert(triple("share-1", "v3_shares/root", .ref("list-1"))),
        .insert(triple("membership-owner", "v3_share_memberships/id", .string("membership-owner"))),
        .insert(triple("membership-owner", "v3_share_memberships/role", .string("owner"))),
        .insert(triple("membership-owner", "v3_share_memberships/acceptedAt", .date(date(1_700_000_000_000)))),
        .insert(triple("membership-owner", "v3_share_memberships/share", .ref("share-1"))),
        .insert(triple("membership-owner", "v3_share_memberships/user", .ref("owner-1"))),
        .insert(triple("membership-reader", "v3_share_memberships/id", .string("membership-reader"))),
        .insert(triple("membership-reader", "v3_share_memberships/role", .string("reader"))),
        .insert(triple("membership-reader", "v3_share_memberships/acceptedAt", .date(date(1_700_000_001_000)))),
        .insert(triple("membership-reader", "v3_share_memberships/share", .ref("share-1"))),
        .insert(triple("membership-reader", "v3_share_memberships/user", .ref("reader-1"))),
      ]
    )
  }

  private func scalar(
    _ namespace: String,
    _ name: String,
    _ type: InstantValueType
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(namespace)/\(name)",
      namespace: namespace,
      name: name,
      valueType: type,
      isIndexed: true
    )
  }

  private func link(
    _ namespace: String,
    _ name: String,
    _ linkedNamespace: String,
    _ reverseName: String,
    _ cardinality: InstantCardinality
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(namespace)/\(name)",
      namespace: namespace,
      name: name,
      valueType: .ref,
      cardinality: cardinality,
      isIndexed: true,
      forwardIdentity: "\(namespace)/\(name)",
      reverseIdentity: "\(linkedNamespace)/\(reverseName)",
      linkNamespace: linkedNamespace
    )
  }
}

private actor LiveShareSourceTermination {
  private var didTerminate = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func record() {
    didTerminate = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }

  func wait() async {
    if didTerminate { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

private actor LiveShareProjectionRecorder {
  private var recordedValues: [[InstantShareSnapshot]] = []
  private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func record(_ value: [InstantShareSnapshot]) {
    recordedValues.append(value)
    let ready = waiters.filter { recordedValues.count >= $0.count }
    waiters.removeAll { recordedValues.count >= $0.count }
    for waiter in ready { waiter.continuation.resume() }
  }

  func waitForCount(_ count: Int) async {
    if recordedValues.count >= count { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }

  func values() -> [[InstantShareSnapshot]] {
    recordedValues
  }
}

private actor LiveShareFailureRecorder {
  private var recordedValues: [InstantError] = []

  func record(_ value: InstantError) {
    recordedValues.append(value)
  }

  func values() -> [InstantError] {
    recordedValues
  }
}
