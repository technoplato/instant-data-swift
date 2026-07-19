import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing
import VoiceTrailV3App

@Suite
struct InstantPlaybackRoomLiveValidationTests {
  @Test
  func appOwnsTheCompletePlaybackRoomContract() {
    expectNoDifference(VoiceTrailPlaybackRoom.roomType, "recording.playback")
    expectNoDifference(
      VoiceTrailPlaybackRoom.Topic.allCases.map(\.rawValue),
      ["reaction", "commentDraft", "commentCommitted"]
    )
    expectNoDifference(
      VoiceTrailCommentDraft(text: "Swift draft", offsetSeconds: 12.5),
      VoiceTrailCommentDraft(text: "Swift draft", offsetSeconds: 12.5)
    )
    expectNoDifference(
      VoiceTrailCommentCommitted(commentID: "comment-swift"),
      VoiceTrailCommentCommitted(commentID: "comment-swift")
    )
  }

  @Test
  func evidenceEncodesCanonicalPlainJSONPayloads() throws {
    let canonicalJSON = Data(
      #"{"roomType":"recording.playback","roomID":"recording-1","swiftUserID":"swift-user","typeScriptUserID":"typescript-user","publishedPresence":{"userID":"swift-user","displayName":"Swift Listener","isPlaying":true,"offsetSeconds":12.5,"focusedSegmentID":"segment-swift"},"receivedPresence":{"userID":"typescript-user","displayName":"TypeScript Listener","isPlaying":false,"offsetSeconds":4.25,"focusedSegmentID":"segment-typescript"},"publishedTopics":{"reaction":{"emoji":"swift-wave","offsetSeconds":12.5},"commentDraft":{"text":"Swift draft","offsetSeconds":12.5},"commentCommitted":{"commentID":"comment-swift"}},"receivedTopics":{"reaction":{"emoji":"typescript-wave","offsetSeconds":4.25},"commentDraft":{"text":"TypeScript draft","offsetSeconds":4.25},"commentCommitted":{"commentID":"comment-typescript"}},"connectionState":"authenticated","reconnect":{"connectionCount":2,"publishedPresence":{"userID":"swift-user","displayName":"Swift Listener Rejoined","isPlaying":false,"offsetSeconds":18.75,"focusedSegmentID":"segment-swift-rejoined"},"receivedPresence":{"userID":"typescript-user","displayName":"TypeScript Listener Rejoined","isPlaying":true,"offsetSeconds":9.5,"focusedSegmentID":"segment-typescript-rejoined"},"publishedTopics":{"reaction":{"emoji":"swift-rejoined","offsetSeconds":18.75},"commentDraft":{"text":"Swift draft after reconnect","offsetSeconds":18.75},"commentCommitted":{"commentID":"comment-swift-rejoined"}},"receivedTopics":{"reaction":{"emoji":"typescript-rejoined","offsetSeconds":9.5},"commentDraft":{"text":"TypeScript draft after reconnect","offsetSeconds":9.5},"commentCommitted":{"commentID":"comment-typescript-rejoined"}},"connectionState":"authenticated"}}"#.utf8
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
    expectNoDifference(details.reconnect.connectionCount, 2)
    expectNoDifference(
      details.reconnect.publishedPresence,
      InstantPlaybackRoomPresenceValue(
        userID: "swift-user",
        displayName: "Swift Listener Rejoined",
        isPlaying: false,
        offsetSeconds: 18.75,
        focusedSegmentID: "segment-swift-rejoined"
      )
    )
    expectNoDifference(
      details.reconnect.receivedTopics.commentCommitted.commentID,
      "comment-typescript-rejoined"
    )
    expectNoDifference(details.reconnect.connectionState, "authenticated")
  }
}
