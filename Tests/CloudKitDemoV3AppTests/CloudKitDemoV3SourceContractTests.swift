import CloudKitDemoV3App
import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite
struct CloudKitDemoV3SourceContractTests {
  @Test
  func desiredTypedCounterAndSharingSyntaxCompiles() {
    let ownerID = InstantID<CloudKitDemoV3User>(rawValue: "owner")
    let counterID = InstantID<CloudKitDemoV3Counter>(rawValue: "counter")
    let visible = FetchAll(CloudKitDemoV3Counter.visible(to: ownerID))
    let create = CreateCloudKitDemoV3SharedCounter(
      counterID: counterID,
      shareID: InstantID(rawValue: "share"),
      ownerMembershipID: InstantID(rawValue: "owner-membership"),
      ownerID: ownerID,
      title: "Shared counter",
      token: "token",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let increment = IncrementCloudKitDemoV3Counter(counterID: counterID)
    let accept = AcceptCloudKitDemoV3Share(
      token: "token",
      membershipID: InstantID(rawValue: "reader-membership"),
      userID: InstantID(rawValue: "reader"),
      acceptedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
    _ = visible
    _ = create
    _ = increment
    _ = accept
  }

  @Test
  func sharesUseSettledNamespacesAndSchema() {
    expectNoDifference(CloudKitDemoV3Counter.instantNamespace, "v3_shared_lists")
    expectNoDifference(CloudKitDemoV3Share.instantNamespace, "v3_shares")
    expectNoDifference(
      CloudKitDemoV3ShareMembership.instantNamespace,
      "v3_share_memberships"
    )
    expectNoDifference(
      CloudKitDemoV3Schema.document.entities.map(\.namespace).sorted(),
      ["$users", "v3_share_memberships", "v3_shared_lists", "v3_shares"]
    )
  }
}
