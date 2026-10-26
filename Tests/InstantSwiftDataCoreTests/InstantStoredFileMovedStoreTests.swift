import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1227: a record of a stored file's copy kept the absolute path the copy had when it was made, and iOS moves an app's
/// data container, with the store's folder, when it installs an update. On one device all 3,844 copies sat at the same
/// place under the new container while their records named 14 earlier ones: eviction answered that no copy was held, a
/// read of the copy failed, and a delete removed the record and left the copy on disk. A copy is found under the store's
/// own files folder, wherever the folder moved.
@Suite struct InstantStoredFileMovedStoreTests {
  private let payload = Data((0..<4_096).map { UInt8($0 % 251) })

  @Test("A moved store's copies are listed, read and deleted where they now are")
  func aMovedStoresCopiesAreFoundWhereTheyNowAre() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-moved-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let earlier = root.appendingPathComponent("container-1", isDirectory: true)
    let later = root.appendingPathComponent("container-2", isDirectory: true)
    let earlierApps = earlier.appendingPathComponent("InstantSwiftData/apps", isDirectory: true)
    try FileManager.default.createDirectory(at: earlierApps, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("audio.wav")
    try payload.write(to: source)
    do {
      let earlierStore = try SQLitePersistenceStore(fileURL: earlierApps.appendingPathComponent("app-1.sqlite"))
      try await earlierStore.bootstrap()
      try await Self.saveCopies(in: earlierStore, from: source)
    }

    // The install moves the container, and the store's folder with it.
    try FileManager.default.moveItem(at: earlier, to: later)
    let apps = later.appendingPathComponent("InstantSwiftData/apps", isDirectory: true)
    let store = try SQLitePersistenceStore(fileURL: apps.appendingPathComponent("app-1.sqlite"))
    try await store.bootstrap()
    let audio = apps.appendingPathComponent("files/app-1/file-1/scribe_r_generation-1_audio.wav").path
    let picture = apps.appendingPathComponent("files/app-1/file-2/scribe_r_generation-1_picture.png").path

    // Each copy where it now is; the record without a copy stays without one.
    let records = try await store.loadStoredFiles(appID: "app-1")
    expectNoDifference(records.map(\.localPath), [audio, picture, ""])
    expectNoDifference(FileManager.default.fileExists(atPath: audio), true)
    expectNoDifference(FileManager.default.fileExists(atPath: picture), true)
    let record = try await store.loadStoredFile(appID: "app-1", fileID: "file-1")
    expectNoDifference(record?.localPath, audio)
    let contents = try await store.readStoredFileContents(appID: "app-1", fileID: "file-1")
    expectNoDifference(contents?.data, payload)
    // A delete removes the copy where it now is, not only its record.
    _ = try await store.deleteStoredFile(appID: "app-1", fileID: "file-1")
    expectNoDifference(FileManager.default.fileExists(atPath: audio), false)
    let remaining = try await store.loadStoredFiles(appID: "app-1")
    expectNoDifference(remaining.map(\.id), ["file-2", "file-3"])
  }

  /// Two copies and one record without a copy, as an earlier install's store made them.
  private static func saveCopies(in store: SQLitePersistenceStore, from source: URL) async throws {
    let at = InstantTimestamp(milliseconds: 1_700_000_000_000)
    for (id, name) in [("file-1", "scribe/r/generation-1/audio.wav"), ("file-2", "scribe/r/generation-1/picture.png")] {
      let saved = try await store.saveStoredFile(
        InstantStoredFile(
          id: id, appID: "app-1", name: name, byteCount: 0, localPath: "", ownerUserID: "user-1", createdAt: at,
          updatedAt: at
        ),
        contentsOf: source
      )
      #expect(saved.localPath.contains("/container-1/"))
    }
    _ = try await store.saveUploadedFileRecord(
      InstantStoredFile(
        id: "file-3", appID: "app-1", name: "scribe/r/generation-1/audio-chunks/000000.wav", byteCount: 4_096,
        localPath: "", ownerUserID: "user-1", createdAt: InstantTimestamp(milliseconds: 1_700_000_000_001),
        updatedAt: at
      )
    )
  }
}
