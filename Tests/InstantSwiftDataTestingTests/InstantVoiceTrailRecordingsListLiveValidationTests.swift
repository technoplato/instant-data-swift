import CustomDump
import Foundation
import InstantSwiftDataCore
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantVoiceTrailRecordingsListLiveValidationTests {
  /// Source contracts:
  /// - Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift:12-80
  /// - validation/ts-runner/src/voice-trail-sdk-contract.test.ts
  /// - upstream/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift
  @Test
  func queryPlansMatchTheCanonicalOwnerAndMemberGraph() {
    let owner = InstantVoiceTrailRecordingsListLiveValidation.queryPlan(
      viewerUserID: "user-viewer",
      mode: .owner
    )
    let member = InstantVoiceTrailRecordingsListLiveValidation.queryPlan(
      viewerUserID: "user-viewer",
      mode: .member
    )

    expectNoDifference(
      owner.filters,
      [.equals(field: "owner", value: .ref("user-viewer"))]
    )
    expectNoDifference(
      member.filters,
      [
        .or([
          .equals(field: "readers", value: .ref("user-viewer")),
          .equals(field: "writers", value: .ref("user-viewer")),
        ])
      ]
    )
    expectNoDifference(owner.order, InstantQueryOrder("title"))
    expectNoDifference(member.order, InstantQueryOrder("title"))
    expectNoDifference(
      owner.includes?.map(\.name),
      ["owner", "readers", "writers", "share"]
    )
    expectNoDifference(member.includes, owner.includes)
    expectNoDifference(
      member.includes?.last?.query?.includes?.map(\.name),
      ["owner", "memberships"]
    )
    expectNoDifference(
      member.includes?.last?.query?.includes?.last?.query?.filters,
      [.equals(field: "user", value: .ref("user-viewer"))]
    )
    expectNoDifference(
      member.includes?.last?.query?.includes?.last?.query?.includes?.map(\.name),
      ["user"]
    )
  }

  @Test
  func evidenceEncodesExactRecordingAndMembershipShape() throws {
    let details = InstantVoiceTrailRecordingsListLiveDetails(
      stage: "writer",
      viewerUserID: "user-viewer",
      rows: [
        InstantVoiceTrailRecordingRowEvidence(
          id: "recording-1",
          title: "Canonical walk",
          ownerUserID: "user-owner",
          viewerRole: "writer"
        )
      ],
      connectionState: "authenticated"
    )

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(details))
        as? [String: Any]
    )
    let rows = try #require(object["rows"] as? [[String: Any]])
    let row = try #require(rows.first)

    #expect(object["stage"] as? String == "writer")
    #expect(object["viewerUserID"] as? String == "user-viewer")
    #expect(object["connectionState"] as? String == "authenticated")
    #expect(object["cancellationClean"] == nil)
    #expect(row["id"] as? String == "recording-1")
    #expect(row["title"] as? String == "Canonical walk")
    #expect(row["ownerUserID"] as? String == "user-owner")
    #expect(row["viewerRole"] as? String == "writer")
  }
}
