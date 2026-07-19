import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantPreferencesLiveValidationTests {
  private let sourceReferences = [
    "upstream/instant/client/packages/core/src/Reactor.js subscribeConnectionStatus and init-ok",
    "upstream/instant/client/packages/core/src/index.ts Storage uploadFile/delete contract",
    "upstream/instant/client/packages/core/src/StorageAPI.ts deleteFile request contract",
    "Tests/InstantSwiftDataCoreTests/InstantStorageSnapshotTests.swift",
    "Tests/InstantSwiftDataTests/V3PreferencesFixtureTests.swift",
    "screens/v3/preferences.md",
  ]

  @Test
  func evidenceDecodesExactSyncAndStorageBoundary() throws {
    let canonicalJSON = Data(
      #"{"userID":"swift-user","phaseSequence":["connected","authenticated"],"connectionState":"authenticated","localCacheSize":184,"streamCacheSize":12,"downloadedFileSizeBeforeClear":7,"downloadedFileCountBeforeClear":2,"clearedFileCount":1,"clearedBytes":4,"downloadedFileSizeAfterClear":3,"downloadedFileCountAfterClear":1,"remainingFileNames":["transcript.txt"]}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantPreferencesLiveValidationDetails.self,
      from: canonicalJSON
    )

    expectNoDifference(details.phaseSequence, ["connected", "authenticated"])
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.streamCacheSize, 12)
    expectNoDifference(details.downloadedFileSizeBeforeClear, 7)
    expectNoDifference(details.clearedFileCount, 1)
    expectNoDifference(details.clearedBytes, 4)
    expectNoDifference(details.downloadedFileSizeAfterClear, 3)
    expectNoDifference(details.remainingFileNames, ["transcript.txt"])
    expectNoDifference(sourceReferences.count, 6)
  }
}
