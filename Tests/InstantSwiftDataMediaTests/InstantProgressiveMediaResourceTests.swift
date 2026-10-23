// A stream's `instant-progressive-media:` URLs, which AVPlayer asks the resource loader for (#1012, ADR 0021).

import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataMedia
import Testing

@Suite struct InstantProgressiveMediaResourceTests {
  let stream = InstantProgressiveMediaStream(key: "recording-1/audio", pathPrefix: "media/recording-1/audio")

  @Test(arguments: [
    InstantProgressiveMediaResource.playlist, .initialization, .segment(0), .segment(123_456),
  ])
  func eachResourceNamesItselfAndIsReadBack(resource: InstantProgressiveMediaResource) {
    let url = resource.url(streamID: stream.id)
    expectNoDifference(InstantProgressiveMediaResource(url: url, streamID: stream.id), resource)
  }

  @Test func theURLsNameTheStreamAndTheFile() {
    expectNoDifference(
      InstantProgressiveMediaResource.segment(7).url(streamID: stream.id).absoluteString,
      "instant-progressive-media://\(stream.id.rawValue)/7.m4s"
    )
    expectNoDifference(
      InstantProgressiveMediaResource.playlist.url(streamID: stream.id).pathExtension,
      "m3u8"
    )
  }

  /// A loader answers only its own stream's URLs.
  @Test func anotherStreamsOrAnUnknownURLIsNotAResource() {
    let other = InstantProgressiveMediaStream(key: "recording-2/audio", pathPrefix: "x")
    #expect(
      InstantProgressiveMediaResource(url: InstantProgressiveMediaResource.playlist.url(streamID: other.id), streamID: stream.id)
        == nil
    )
    #expect(
      InstantProgressiveMediaResource(
        url: URL(string: "instant-progressive-media://\(stream.id.rawValue)/seven.m4s")!, streamID: stream.id)
        == nil
    )
    #expect(
      InstantProgressiveMediaResource(url: URL(string: "https://\(stream.id.rawValue)/0.m4s")!, streamID: stream.id)
        == nil
    )
  }
}
