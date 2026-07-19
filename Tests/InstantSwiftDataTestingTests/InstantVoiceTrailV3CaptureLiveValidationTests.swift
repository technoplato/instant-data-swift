import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantVoiceTrailV3CaptureLiveValidationTests {
  @Test
  func evidenceDecodesTheExactAppCaptureShape() throws {
    let data = Data(
      #"{"direction":"swift-to-typescript","userID":"swift-user","recordingID":"v3-e2e-swift-recording","transcriptionID":"v3-e2e-swift-transcription","attachmentID":"v3-e2e-swift-attachment","title":"Swift E2E recording","deviceID":"swift-e2e-device","recordingState":"finished","durationMilliseconds":12750,"transcriptionState":"ready","attachmentKind":"screenshot","attachmentContents":"capture.png","attachmentOffsetMilliseconds":2500,"connectionState":"authenticated","pendingMutationCount":0}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantVoiceTrailV3CaptureLiveValidationDetails.self,
      from: data
    )

    expectNoDifference(details.direction, "swift-to-typescript")
    expectNoDifference(details.userID, "swift-user")
    expectNoDifference(details.recordingID, "v3-e2e-swift-recording")
    expectNoDifference(details.transcriptionID, "v3-e2e-swift-transcription")
    expectNoDifference(details.attachmentID, "v3-e2e-swift-attachment")
    expectNoDifference(details.title, "Swift E2E recording")
    expectNoDifference(details.deviceID, "swift-e2e-device")
    expectNoDifference(details.recordingState, "finished")
    expectNoDifference(details.durationMilliseconds, 12_750)
    expectNoDifference(details.transcriptionState, "ready")
    expectNoDifference(details.attachmentKind, "screenshot")
    expectNoDifference(details.attachmentContents, "capture.png")
    expectNoDifference(details.attachmentOffsetMilliseconds, 2_500)
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.pendingMutationCount, 0)
  }
}
