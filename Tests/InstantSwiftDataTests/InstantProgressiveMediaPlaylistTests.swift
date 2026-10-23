// A progressive media stream's rows, turned into the HLS media playlist a player follows (#1012, ADR 0021).

import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite struct InstantProgressiveMediaPlaylistTests {
  let stream = InstantProgressiveMediaStream(key: "recording-1/audio", pathPrefix: "media/recording-1/audio")

  @Test func aStreamStillRecordingIsAnEventPlaylistWithoutAnEnd() {
    let playlist = InstantProgressiveMediaPlaylist(
      initializationURI: "init.mp4",
      segments: [
        .init(uri: "000000.m4s", durationSeconds: 6.016),
        .init(uri: "000001.m4s", durationSeconds: 5.99467),
        .init(uri: "000002.m4s", durationSeconds: 5.99467),
      ],
      isFinished: false
    )
    expectNoDifference(
      playlist.text,
      """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:6
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-PLAYLIST-TYPE:EVENT
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-MAP:URI="init.mp4"
      #EXTINF:6.01600,
      000000.m4s
      #EXTINF:5.99467,
      000001.m4s
      #EXTINF:5.99467,
      000002.m4s

      """
    )
  }

  @Test func aFinishedStreamIsAVODPlaylistThatEnds() {
    let playlist = InstantProgressiveMediaPlaylist(
      initializationURI: "init.mp4",
      segments: [.init(uri: "000000.m4s", durationSeconds: 4.2)],
      isFinished: true
    )
    expectNoDifference(
      playlist.text,
      """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:4
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-PLAYLIST-TYPE:VOD
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-MAP:URI="init.mp4"
      #EXTINF:4.20000,
      000000.m4s
      #EXT-X-ENDLIST

      """
    )
  }

  /// RFC 8216 4.3.3.1: each EXTINF, rounded to the nearest integer, is at most the target duration. Rounding up
  /// instead (6.016 to 7) adds three seconds to a live player's hold-back for nothing; measured 2026-10-23.
  @Test(arguments: [(6.49, 6), (6.5, 7), (0.2, 1), (10.0, 10)])
  func theTargetDurationIsTheLongestSegmentRoundedToTheNearestSecond(longest: Double, target: Int) {
    let playlist = InstantProgressiveMediaPlaylist(
      initializationURI: "init.mp4",
      segments: [.init(uri: "a.m4s", durationSeconds: 1), .init(uri: "b.m4s", durationSeconds: longest)],
      isFinished: false
    )
    #expect(playlist.targetDurationSeconds == target)
  }

  /// A window of a long stream starts at its first segment's index, so a player that reloads it keeps its place.
  @Test func aWindowStartsAtItsFirstSegmentsSequenceNumber() {
    let playlist = InstantProgressiveMediaPlaylist(
      initializationURI: "init.mp4",
      segments: [.init(uri: "000010.m4s", durationSeconds: 6)],
      mediaSequence: 10,
      isFinished: false
    )
    #expect(playlist.text.contains("#EXT-X-MEDIA-SEQUENCE:10\n"))
  }

  @Test func aStreamNamesItsFilesUnderItsPrefix() {
    #expect(stream.initializationPath == "media/recording-1/audio/init.mp4")
    #expect(stream.segmentPath(0) == "media/recording-1/audio/000000.m4s")
    #expect(stream.segmentPath(1_234_567) == "media/recording-1/audio/1234567.m4s")
  }

  /// The same stream and index always name the same rows, so a retried write lands on the row it already wrote.
  @Test func rowIDsComeFromTheStreamsKeyAndTheSegmentsIndex() {
    let again = InstantProgressiveMediaStream(key: "recording-1/audio", pathPrefix: "elsewhere")
    let other = InstantProgressiveMediaStream(key: "recording-2/audio", pathPrefix: "media/recording-1/audio")
    #expect(stream.id == again.id)
    #expect(stream.id != other.id)
    #expect(stream.segmentID(3) == again.segmentID(3))
    #expect(stream.segmentID(3) != stream.segmentID(4))
    #expect(stream.segmentID(3) != other.segmentID(3))
    #expect(UUID(uuidString: stream.id.rawValue) != nil)
    #expect(UUID(uuidString: stream.segmentID(0).rawValue) != nil)
  }

  /// ADR 0021's measured choice: AAC-LC, mono, 24 kHz, 32 kbps, in 6 s segments.
  @Test func theSpeechFormatIsAACLowComplexityAt24kHzAnd32kbps() {
    expectNoDifference(
      InstantProgressiveMediaFormat.speech,
      InstantProgressiveMediaFormat(
        codecs: "mp4a.40.2",
        sampleRate: 24_000,
        channelCount: 1,
        bitRate: 32_000,
        segmentSeconds: 6
      )
    )
    #expect(stream.format == .speech)
  }
}
