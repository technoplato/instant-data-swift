import CustomDump
import Testing
@testable import VoiceTrailV3App

@Suite
struct VoiceTrailV3E2EContractTests {
  private let sourceReferences = [
    "screens/v3/auth-login.md",
    "screens/v3/recordings-list.md",
    "screens/v3/recording.md",
    "screens/v3/playback.md",
    "screens/v3/preferences.md",
    "validation/ts-runner/src/recording-action-sdk-contract.test.ts",
    "validation/ts-runner/src/sharing-sdk-contract.test.ts",
    "validation/ts-runner/src/playback-room-sdk-contract.test.ts",
    "validation/ts-runner/src/preferences-sdk-contract.test.ts",
  ]

  @Test
  func contractPinsAllFiveScreensToExactCrossSDKShapes() {
    let contract = VoiceTrailV3E2EContract.canonical(
      swiftUserID: "swift-user",
      typeScriptUserID: "typescript-user"
    )

    expectNoDifference(contract.tabs, [.auth, .recordings, .capture, .playback, .preferences])
    expectNoDifference(contract.swiftUserID, "swift-user")
    expectNoDifference(contract.typeScriptUserID, "typescript-user")
    expectNoDifference(
      contract.capture,
      VoiceTrailV3CaptureContract(
        recordingID: "v3-e2e-swift-recording",
        transcriptionID: "v3-e2e-swift-transcription",
        title: "Swift E2E recording",
        ownerUserID: "swift-user",
        deviceID: "swift-e2e-device",
        state: "recording",
        durationMilliseconds: 0,
        transcriptionState: "processing"
      )
    )
    expectNoDifference(contract.sharing.role, "reader")
    expectNoDifference(contract.sharing.recordingID, "v3-e2e-typescript-recording")
    expectNoDifference(contract.sharing.ownerUserID, "typescript-user")
    expectNoDifference(contract.sharing.memberUserID, "swift-user")
    expectNoDifference(contract.playback.roomType, "recording.playback")
    expectNoDifference(contract.playback.roomID, contract.capture.recordingID)
    expectNoDifference(contract.playback.swiftPresence.offsetSeconds, 12.5)
    expectNoDifference(contract.playback.typeScriptPresence.offsetSeconds, 4.25)
    expectNoDifference(contract.playback.swiftReaction.emoji, "swift-wave")
    expectNoDifference(contract.playback.typeScriptReaction.emoji, "typescript-wave")
    expectNoDifference(contract.preferences.streamContent, "hello-stream")
    expectNoDifference(contract.preferences.streamByteCount, 12)
    expectNoDifference(contract.preferences.downloadedByteCount, 7)
    expectNoDifference(contract.preferences.clearedAudioByteCount, 4)
    expectNoDifference(contract.preferences.remainingFileNames, ["transcript.txt"])
    expectNoDifference(sourceReferences.count, 9)
  }
}
