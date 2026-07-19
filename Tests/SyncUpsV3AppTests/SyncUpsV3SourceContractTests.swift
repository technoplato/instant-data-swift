import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataSchema
import SyncUpsV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical sources:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/SyncUps/Schema.swift
// - Examples/SyncUps/SyncUpsList.swift
// - Examples/SyncUps/SyncUpDetail.swift
// - Examples/SyncUps/SyncUpForm.swift
// - Examples/SyncUps/RecordMeeting.swift
// - Examples/SyncUpTests/SyncUpFormTests.swift
@Suite
struct SyncUpsV3SourceContractTests {
  #if canImport(SwiftUI)
    @Test @MainActor
    func desiredAppOwnedListDetailFormAndRecordingSyntaxCompiles() {
      let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up-1")
      let attendee = SyncUpsV3Attendee(
        id: InstantID(rawValue: "attendee-1"),
        name: "Blob",
        syncUp: syncUpID
      )
      let syncUp = SyncUpsV3SyncUp(
        id: syncUpID,
        title: "Design",
        attendees: [attendee]
      )
      let form = SyncUpsV3FormState(
        syncUp: syncUp,
        attendeeDraftIDs: [InstantID(rawValue: "draft-1")],
        blankAttendeeID: InstantID(rawValue: "draft-blank")
      )
      let recording = SyncUpsV3RecordingModel(syncUp: syncUp, attendees: [attendee])

      let list: any View = SyncUpsV3Screen()
      let detail: any View = SyncUpsV3DetailScreen(syncUp: syncUp)
      let formScreen: any View = SyncUpsV3FormScreen(form: form)
      let recordingScreen: any View = SyncUpsV3RecordMeetingScreen(recording: recording)
      _ = list
      _ = detail
      _ = formScreen
      _ = recordingScreen
    }
  #endif

  @Test
  func desiredTypedEntityQueryAndDraftSyntaxCompiles() {
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up-1")
    let syncUps = FetchAll(SyncUpsV3SyncUp.list)
    let detail = FetchOne(SyncUpsV3SyncUp.detail(syncUpID))
    let attendees = FetchAll(SyncUpsV3Attendee.forSyncUp(syncUpID))
    let meetings = FetchAll(SyncUpsV3Meeting.forSyncUp(syncUpID))
    let syncUp = SyncUpsV3SyncUp.Draft(
      seconds: 60 * 5,
      theme: .bubblegum,
      title: "Morning Sync"
    )
    let attendee = SyncUpsV3Attendee.Draft(name: "Blob", syncUp: syncUpID)
    let meeting = SyncUpsV3Meeting.Draft(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      syncUp: syncUpID,
      transcript: "Reviewed launch risks."
    )

    _ = syncUps
    _ = detail
    _ = attendees
    _ = meetings
    _ = syncUp
    _ = attendee
    _ = meeting
  }

  @Test
  func typedEntitiesPreserveUpstreamNamespacesAndInstantLinkAdaptation() {
    expectNoDifference(SyncUpsV3SyncUp.instantNamespace, "syncUps")
    expectNoDifference(SyncUpsV3Attendee.instantNamespace, "attendees")
    expectNoDifference(SyncUpsV3Meeting.instantNamespace, "meetings")
    expectNoDifference(
      SyncUpsV3SyncUp.instantAttributes.map(\.name),
      ["id", "seconds", "theme", "title"]
    )
    expectNoDifference(
      SyncUpsV3Attendee.instantAttributes.map(\.name),
      ["id", "name", "syncUp"]
    )
    expectNoDifference(
      SyncUpsV3Meeting.instantAttributes.map(\.name),
      ["id", "date", "transcript", "syncUp"]
    )
    expectNoDifference(
      SyncUpsV3Schema.document.links.map(\.name),
      ["syncUpsAttendees", "syncUpsMeetings"]
    )
    expectNoDifference(SyncUpsV3Schema.document.links.map(\.isRequired), [true, true])
    expectNoDifference(
      SyncUpsV3Schema.document.links.map(\.forward.onDelete),
      [.cascade, .cascade]
    )
  }

  @Test
  func themePreservesEveryUpstreamStringWireCase() throws {
    expectNoDifference(
      SyncUpsV3Theme.allCases.map(\.rawValue),
      [
        "appIndigo", "appMagenta", "appOrange", "appPurple", "appTeal", "appYellow",
        "bubblegum", "buttercup", "lavender", "navy", "oxblood", "periwinkle",
        "poppy", "seafoam", "sky", "tan",
      ]
    )
    expectNoDifference(
      String(decoding: try JSONEncoder().encode(SyncUpsV3Theme.bubblegum), as: UTF8.self),
      #""bubblegum""#
    )
  }
}
