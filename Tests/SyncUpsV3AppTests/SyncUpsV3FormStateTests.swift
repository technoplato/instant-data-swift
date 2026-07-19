import CustomDump
import InstantSwiftData
import Testing
@testable import SyncUpsV3App

// Canonical source:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/SyncUps/SyncUpForm.swift
// - Examples/SyncUpTests/SyncUpFormTests.swift
@Suite
struct SyncUpsV3FormStateTests {
  @Test
  func newFormAddsDeletesAndKeepsOneAttendee() {
    let blankID = InstantID<SyncUpsV3Attendee>(rawValue: "draft-1")
    var state = SyncUpsV3FormState(blankAttendeeID: blankID)

    expectDifference(state) {
      state.addAttendeeButtonTapped(id: InstantID(rawValue: "draft-2"))
    } changes: {
      $0.attendees.append(SyncUpsV3AttendeeDraft(id: InstantID(rawValue: "draft-2")))
      $0.focus = .attendee(InstantID(rawValue: "draft-2"))
    }
    expectDifference(state) {
      state.deleteAttendees(
        atOffsets: [0, 1],
        blankAttendeeID: InstantID(rawValue: "draft-3")
      )
    } changes: {
      $0.attendees.removeAll()
      $0.attendees.append(SyncUpsV3AttendeeDraft(id: InstantID(rawValue: "draft-3")))
      $0.focus = .attendee(InstantID(rawValue: "draft-3"))
    }
  }

  @Test
  func existingFormReplacesAttendeesAndCommitsIdentity() {
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up")
    let originalBlobID = InstantID<SyncUpsV3Attendee>(rawValue: "original-blob")
    let originalJuniorID = InstantID<SyncUpsV3Attendee>(rawValue: "original-junior")
    let syncUp = SyncUpsV3SyncUp(
      id: syncUpID,
      seconds: 600,
      theme: .periwinkle,
      title: "Engineering",
      attendees: [
        SyncUpsV3Attendee(id: originalBlobID, name: "Blob", syncUp: syncUpID),
        SyncUpsV3Attendee(id: originalJuniorID, name: "Blob Jr.", syncUp: syncUpID),
      ]
    )
    let blobDraftID = InstantID<SyncUpsV3Attendee>(rawValue: "draft-blob")
    let juniorDraftID = InstantID<SyncUpsV3Attendee>(rawValue: "draft-junior")
    var state = SyncUpsV3FormState(
      syncUp: syncUp,
      attendeeDraftIDs: [blobDraftID, juniorDraftID],
      blankAttendeeID: InstantID(rawValue: "unused")
    )
    state.title = "Evening Sync"
    state.deleteAttendees(
      atOffsets: [1],
      blankAttendeeID: InstantID(rawValue: "unused")
    )
    state.addAttendeeButtonTapped(id: InstantID(rawValue: "draft-blobby"))
    state.attendees[1].name = "Blobby McBlob"

    let message = state.saveButtonTapped(
      newSyncUpID: InstantID(rawValue: "unused-sync-up"),
      blankAttendeeID: InstantID(rawValue: "unused-attendee")
    )
    expectNoDifference(message.syncUpID, syncUpID)
    expectNoDifference(message.isNew, false)
    expectNoDifference(message.title, "Evening Sync")
    expectNoDifference(message.existingAttendeeIDs, [originalBlobID, originalJuniorID])
    expectNoDifference(
      message.attendees,
      [
        SyncUpsV3AttendeeInput(id: blobDraftID, name: "Blob"),
        SyncUpsV3AttendeeInput(id: InstantID(rawValue: "draft-blobby"), name: "Blobby McBlob"),
      ]
    )

    expectDifference(state) {
      state.commit(
        SyncUpsV3FormSaved(
          syncUpID: syncUpID,
          attendeeIDs: message.attendees.map(\.id)
        )
      )
    } changes: {
      $0.existingAttendeeIDs = message.attendees.map(\.id)
      $0.isDismissed = true
    }
  }

  @Test
  func whitespaceOnlyAttendeesNormalizeToOneBlankDraft() {
    var state = SyncUpsV3FormState(
      blankAttendeeID: InstantID(rawValue: "draft-1")
    )
    state.attendees[0].name = "   "
    let message = state.saveButtonTapped(
      newSyncUpID: InstantID(rawValue: "sync-up"),
      blankAttendeeID: InstantID(rawValue: "draft-2")
    )

    expectNoDifference(
      message.attendees,
      [SyncUpsV3AttendeeInput(id: InstantID(rawValue: "draft-2"), name: "")]
    )
  }
}
