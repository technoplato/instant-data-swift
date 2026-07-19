import CustomDump
import Foundation
import InstantSwiftData
import SyncUpsV3App
import Testing

// Canonical source:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/SyncUpTests/SyncUpFormTests.swift
@Suite
struct SyncUpsV3FormTests {
  @Test
  func saveNew() async throws {
    let client = try await makeClient(test: "save-new")
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up-morning")
    let blobID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-blob")
    let blobJuniorID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-blob-junior")

    try await transact(
      SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: true,
        title: "Morning Sync",
        seconds: 300,
        theme: .bubblegum,
        attendees: [
          SyncUpsV3AttendeeInput(id: blobID, name: "Blob"),
          SyncUpsV3AttendeeInput(id: blobJuniorID, name: "Blob Jr."),
        ]
      ),
      using: client
    )

    let syncUps = try await client.query(SyncUpsV3SyncUp.detail(syncUpID))
    expectNoDifference(
      syncUps,
      [
        SyncUpsV3SyncUp(
          id: syncUpID,
          title: "Morning Sync",
          attendees: [
            SyncUpsV3Attendee(id: blobID, name: "Blob", syncUp: syncUpID),
            SyncUpsV3Attendee(id: blobJuniorID, name: "Blob Jr.", syncUp: syncUpID),
          ]
        )
      ]
    )
  }

  @Test
  func updateExisting() async throws {
    let client = try await makeClient(test: "update-existing")
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up-existing")
    let originalBlobID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-original-blob")
    let originalJuniorID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-original-junior")
    let retainedBlobID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-new-blob")
    let blobbyID = InstantID<SyncUpsV3Attendee>(rawValue: "attendee-blobby")

    try await transact(
      SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: true,
        title: "Morning Sync",
        seconds: 300,
        theme: .bubblegum,
        attendees: [
          SyncUpsV3AttendeeInput(id: originalBlobID, name: "Blob"),
          SyncUpsV3AttendeeInput(id: originalJuniorID, name: "Blob Jr."),
        ]
      ),
      using: client
    )
    try await transact(
      SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: false,
        title: "Evening Sync",
        seconds: 600,
        theme: .periwinkle,
        existingAttendeeIDs: [originalBlobID, originalJuniorID],
        attendees: [
          SyncUpsV3AttendeeInput(id: retainedBlobID, name: "Blob"),
          SyncUpsV3AttendeeInput(id: blobbyID, name: "Blobby McBlob"),
        ]
      ),
      using: client
    )

    let syncUps = try await client.query(SyncUpsV3SyncUp.detail(syncUpID))
    expectNoDifference(
      syncUps,
      [
        SyncUpsV3SyncUp(
          id: syncUpID,
          seconds: 600,
          theme: .periwinkle,
          title: "Evening Sync",
          attendees: [
            SyncUpsV3Attendee(id: retainedBlobID, name: "Blob", syncUp: syncUpID),
            SyncUpsV3Attendee(id: blobbyID, name: "Blobby McBlob", syncUp: syncUpID),
          ]
        )
      ]
    )
    let attendeeIDs = try await client.query(SyncUpsV3Attendee.forSyncUp(syncUpID)).map(\.id)
    expectNoDifference(
      attendeeIDs,
      [retainedBlobID, blobbyID]
    )
  }

  @Test
  func invalidFormPayloadsFailBeforeMutation() async throws {
    let client = try await makeClient(test: "invalid")
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up-invalid")

    await #expect(throws: SyncUpsV3MessageError.attendeeRequired) {
      _ = try await SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: true,
        title: "No attendees",
        seconds: 300,
        theme: .bubblegum,
        attendees: []
      ).prepare(using: client)
    }
    await #expect(throws: SyncUpsV3MessageError.invalidDuration(0)) {
      _ = try await SaveSyncUpsV3Form(
        syncUpID: syncUpID,
        isNew: true,
        title: "No duration",
        seconds: 0,
        theme: .bubblegum,
        attendees: [
          SyncUpsV3AttendeeInput(
            id: InstantID(rawValue: "attendee"),
            name: "Blob"
          )
        ]
      ).prepare(using: client)
    }
    let pendingMutations = await client.pendingMutations()
    expectNoDifference(pendingMutations, [])
  }

  private func makeClient(test: String) async throws -> InstantSwiftDataClient {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("syncups-v3-\(test)-\(UUID().uuidString).sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "syncups-v3-form-tests",
        persistenceURL: persistenceURL,
        initialAttributes: SyncUpsV3Schema.attributes
      )
    )
    return InstantSwiftDataClient(runtime: runtime)
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
