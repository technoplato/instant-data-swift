import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantPlaybackRoomLiveValidationTests {
  @Test
  func evidenceEncodesCanonicalPlainJSONPayloads() throws {
    let canonicalJSON = Data(
      #"{"roomType":"recording.playback","roomID":"recording-1","swiftUserID":"swift-user","typeScriptUserID":"typescript-user","publishedPresence":{"userID":"swift-user","displayName":"Swift Listener","isPlaying":true,"offsetSeconds":12.5,"focusedSegmentID":"segment-swift"},"receivedPresence":{"userID":"typescript-user","displayName":"TypeScript Listener","isPlaying":false,"offsetSeconds":4.25,"focusedSegmentID":"segment-typescript"},"publishedTopics":{"reaction":{"emoji":"swift-wave","offsetSeconds":12.5},"commentDraft":{"text":"Swift draft","offsetSeconds":12.5},"commentCommitted":{"commentID":"comment-swift"}},"receivedTopics":{"reaction":{"emoji":"typescript-wave","offsetSeconds":4.25},"commentDraft":{"text":"TypeScript draft","offsetSeconds":4.25},"commentCommitted":{"commentID":"comment-typescript"}},"connectionState":"authenticated"}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantPlaybackRoomLiveValidationDetails.self,
      from: canonicalJSON
    )

    let data = try JSONEncoder().encode(details)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let publishedPresence = try #require(
      object["publishedPresence"] as? [String: Any]
    )
    let publishedTopics = try #require(
      object["publishedTopics"] as? [String: Any]
    )
    let reaction = try #require(
      publishedTopics["reaction"] as? [String: Any]
    )

    #expect(publishedPresence["displayName"] as? String == "Swift Listener")
    #expect(publishedPresence["isPlaying"] as? Bool == true)
    #expect(publishedPresence["offsetSeconds"] as? Double == 12.5)
    #expect(publishedPresence["string"] == nil)
    #expect(reaction["emoji"] as? String == "swift-wave")
    #expect(reaction["offsetSeconds"] as? Double == 12.5)
  }
}
