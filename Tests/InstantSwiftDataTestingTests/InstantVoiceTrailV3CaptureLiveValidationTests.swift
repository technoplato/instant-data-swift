import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantVoiceTrailV3CaptureLiveValidationTests {
  @Test
  func evidenceDecodesTheExactAppCaptureShape() throws {
    let data = Data(
      #"{"direction":"swift-to-typescript","userID":"swift-user","recordingID":"v3-e2e-swift-recording","transcriptionID":"v3-e2e-swift-transcription","title":"Swift E2E recording","deviceID":"swift-e2e-device","recordingState":"recording","durationMilliseconds":0,"transcriptionState":"processing","connectionState":"authenticated","pendingMutationCount":0}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantVoiceTrailV3CaptureLiveValidationDetails.self,
      from: data
    )

    expectNoDifference(details.direction, "swift-to-typescript")
    expectNoDifference(details.userID, "swift-user")
    expectNoDifference(details.recordingID, "v3-e2e-swift-recording")
    expectNoDifference(details.transcriptionID, "v3-e2e-swift-transcription")
    expectNoDifference(details.title, "Swift E2E recording")
    expectNoDifference(details.deviceID, "swift-e2e-device")
    expectNoDifference(details.recordingState, "recording")
    expectNoDifference(details.durationMilliseconds, 0)
    expectNoDifference(details.transcriptionState, "processing")
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.pendingMutationCount, 0)
  }
}
