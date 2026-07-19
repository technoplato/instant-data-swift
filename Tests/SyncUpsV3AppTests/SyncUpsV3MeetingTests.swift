import CustomDump
import Foundation
import InstantSwiftData
import SyncUpsV3App
import Testing

// Canonical source:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/SyncUps/RecordMeeting.swift
// - Examples/SyncUps/SyncUpDetail.swift
@Suite
struct SyncUpsV3MeetingTests {
  @Test
  func recordingCreatesTheRequiredParentLinkAndParentDeleteCascades() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("syncups-v3-meeting-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "syncups-v3-meeting-tests",
        persistenceURL: persistenceURL,
        initialAttributes: SyncUpsV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up")
    let attendeeID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee")
    let meetingID = InstantID<SyncUpsV3Meeting>(rawValue: "meeting")
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    try await transact(
      SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: true,
        title: "Design",
        seconds: 60,
        theme: .appOrange,
        attendees: [SyncUpsV3AttendeeInput(id: attendeeID, name: "Blob")]
      ),
      using: client
    )
    try await transact(
      RecordSyncUpsV3Meeting(
        meetingID: meetingID,
        syncUpID: syncUpID,
        date: date,
        transcript: "Reviewed launch risks."
      ),
      using: client
    )

    let meetings = try await client.query(SyncUpsV3Meeting.forSyncUp(syncUpID))
    expectNoDifference(
      meetings,
      [
        SyncUpsV3Meeting(
          id: meetingID,
          date: date,
          syncUp: syncUpID,
          transcript: "Reviewed launch risks."
        )
      ]
    )

    try await transact(DeleteSyncUpsV3SyncUp(syncUpID: syncUpID), using: client)
    let remainingAttendees = try await client.query(SyncUpsV3Attendee.forSyncUp(syncUpID))
    let remainingMeetings = try await client.query(SyncUpsV3Meeting.forSyncUp(syncUpID))
    expectNoDifference(remainingAttendees, [])
    expectNoDifference(remainingMeetings, [])
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
