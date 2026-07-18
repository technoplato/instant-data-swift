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
      contract.queryPlan.includes?.last?.query?.includes?.map(\.name),
      ["owner", "memberships"]
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
      try contract.snapshots(appID: "app-1", roots: [root]),
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

  private func date(_ milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }
}
