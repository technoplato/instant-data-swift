import CustomDump
import Foundation
import InstantSwiftDataCore
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantVoiceTrailRecordingsListLiveValidationTests {
  @Test
  func sharedLiveValidationTimingIsExactlyFiveSeconds() {
    expectNoDifference(InstantLiveValidationTiming.timeoutMilliseconds, 5_000)
    expectNoDifference(InstantLiveValidationTiming.pollIntervalMilliseconds, 25)
    expectNoDifference(InstantLiveValidationTiming.pollAttemptCount, 200)
  }

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
      [.equals(field: "owner.id", value: .string("user-viewer"))]
    )
    expectNoDifference(
      member.filters,
      [
        .or([
          .equals(field: "readers.id", value: .string("user-viewer")),
          .equals(field: "writers.id", value: .string("user-viewer")),
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
      [.equals(field: "user.id", value: .string("user-viewer"))]
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

  @Test
  func liveValidationSourcesPreserveAbortAndFiveSecondContracts() throws {
    let root = voiceTrailPackageRootURL()
    let contracts: [(path: String, required: [String], forbidden: [String])] = [
      (
        "Sources/InstantSwiftDataTesting/InstantVoiceTrailRecordingsListLiveValidation.swift",
        [
          "return live.mapSessions { session in",
          "return session.forwarding(",
          "0..<InstantLiveValidationTiming.pollAttemptCount",
        ],
        [
          "InstantLiveTransportClient { request in",
          "live.connect(request)",
          "0..<800",
        ]
      ),
      (
        "Sources/InstantSwiftDataTesting/InstantPlaybackRoomLiveValidation.swift",
        [
          "base.mapSessions { session in",
          "return session.forwarding(",
          "timeoutMilliseconds: InstantLiveValidationTiming.timeoutMilliseconds",
        ],
        [
          "InstantLiveTransportClient { request in",
          "base.connect(request)",
          ".seconds(20)",
          "Timed out after 20 seconds.",
        ]
      ),
      (
        "Sources/InstantSwiftDataTesting/InstantSharingLiveValidation.swift",
        [
          "return live.mapSessions { session in",
          "return session.forwarding(",
          "0..<InstantLiveValidationTiming.pollAttemptCount",
          "Timed out after 5 seconds.",
        ],
        [
          "InstantLiveTransportClient { request in",
          "live.connect(request)",
          "0..<400",
          "Timed out after 10 seconds.",
        ]
      ),
    ]
    var failures: [String] = []
    for contract in contracts {
      let source = try String(
        contentsOf: root.appendingPathComponent(contract.path),
        encoding: .utf8
      )
      failures += contract.required.filter { !source.contains($0) }
        .map { "\(contract.path) missing \($0)" }
      failures += contract.forbidden.filter { source.contains($0) }
        .map { "\(contract.path) retained \($0)" }
    }
    expectNoDifference(failures, [])
  }
}

private func voiceTrailPackageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
