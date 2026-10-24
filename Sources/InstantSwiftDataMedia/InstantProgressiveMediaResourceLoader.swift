// Plays a progressive media stream in AVPlayer: the playlist is built from the stream's rows on this device, and the
// player is sent to each file's storage URL as it asks for it (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). The shape is Apple's AVARLDelegateDemo: a custom-scheme playlist answered with
//   data, and each media resource answered with a redirect, so URLs are signed only for what the player plays.

import Foundation
import InstantSwiftData
import os

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation

  /// Answers AVPlayer's requests for a stream's `instant-progressive-media:` URLs from a reader.
  ///
  /// ```swift
  /// let loader = InstantProgressiveMediaResourceLoader(
  ///   reader: InstantProgressiveMediaReader(streamID: stream.id, source: .live(client))
  /// )
  /// let player = AVPlayer(playerItem: AVPlayerItem(asset: loader.makeAsset()))
  /// ```
  ///
  /// A stream that is still recording plays as a live (`EVENT`) playlist. AVPlayer fails such an item for good when its
  /// playlist lists no segment (CoreMedia -12888, measured 2026-10-23), so the loader holds the first playlist request
  /// until a segment is listed. When the writer stops uploading for longer than the player's buffer, AVPlayer plays to
  /// the live edge and sets its rate to 0 without an error; its owner calls `play()` again when the stream grows.
  ///
  /// Keep the loader alive as long as its asset: `AVAssetResourceLoader` holds its delegate weakly. Not on watchOS,
  /// which has no `AVAssetResourceLoader`.
  public final class InstantProgressiveMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    public let reader: InstantProgressiveMediaReader
    private let queue = DispatchQueue(label: "instant-progressive-media.resource-loader")
    private let tasks = OSAllocatedUnfairLock<[ObjectIdentifier: Task<Void, Never>]>(initialState: [:])
    private let pollInterval: Duration

    public init(reader: InstantProgressiveMediaReader, pollInterval: Duration = .seconds(2)) {
      self.reader = reader
      self.pollInterval = pollInterval
    }

    /// The playlist's URL.
    public var playlistURL: URL { InstantProgressiveMediaResource.playlist.url(streamID: reader.streamID) }

    /// An asset whose resources this loader answers.
    public func makeAsset() -> AVURLAsset {
      let asset = AVURLAsset(url: playlistURL)
      asset.resourceLoader.setDelegate(self, queue: queue)
      return asset
    }

    public func resourceLoader(
      _ resourceLoader: AVAssetResourceLoader,
      shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
      guard
        let url = loadingRequest.request.url,
        let resource = InstantProgressiveMediaResource(url: url, streamID: reader.streamID)
      else { return false }
      let request = LoadingRequest(value: loadingRequest)
      let key = ObjectIdentifier(loadingRequest)
      let task = Task { [reader, pollInterval, tasks] in
        defer { tasks.withLock { $0[key] = nil } }
        do {
          switch resource {
          case .playlist:
            var snapshot = try await reader.refresh()
            while snapshot.segments.isEmpty {
              try await Task.sleep(for: pollInterval)
              snapshot = try await reader.refresh()
            }
            let streamID = reader.streamID
            let text = snapshot.playlist(
              initializationURI: InstantProgressiveMediaResource.initialization.url(streamID: streamID).absoluteString
            ) {
              InstantProgressiveMediaResource.segment($0.index).url(streamID: streamID).absoluteString
            }.text
            request.value.dataRequest?.respond(with: Data(text.utf8))
            request.value.finishLoading()
          case .initialization:
            Self.redirect(request.value, to: try await reader.initializationURL())
          case let .segment(index):
            Self.redirect(request.value, to: try await reader.url(forSegment: index))
          }
        } catch is CancellationError {
        } catch {
          request.value.finishLoading(with: error)
        }
      }
      tasks.withLock { $0[key] = task }
      return true
    }

    public func resourceLoader(
      _ resourceLoader: AVAssetResourceLoader,
      didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
      let task = tasks.withLock { $0.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
      task?.cancel()
    }

    /// A loading request, handed to the task that answers it.
    // SAFETY: one task owns each request. The resource loader's executor (the delegate queue) hands the request to
    // exactly one Task and keeps no reference of its own; that task alone answers it, and AVFoundation accepts the
    // answer from any thread.
    private struct LoadingRequest: @unchecked Sendable {
      let value: AVAssetResourceLoadingRequest
    }

    private static func redirect(_ request: AVAssetResourceLoadingRequest, to url: URL) {
      request.redirect = URLRequest(url: url)
      request.response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)
      request.finishLoading()
    }
  }
#endif

/// The resources of a stream's `instant-progressive-media:` URLs.
public enum InstantProgressiveMediaResource: Hashable, Sendable {
  case playlist
  case initialization
  case segment(Int)

  public static let scheme = "instant-progressive-media"

  /// `instant-progressive-media://<stream id>/playlist.m3u8`, `.../init.mp4` or `.../<index>.m4s`.
  public func url(streamID: InstantID<InstantProgressiveMediaStreamRow>) -> URL {
    let name =
      switch self {
      case .playlist: "playlist.m3u8"
      case .initialization: "init.mp4"
      case let .segment(index): "\(index).m4s"
      }
    return URL(string: "\(Self.scheme)://\(streamID.rawValue)/\(name)")!
  }

  /// The resource `url` names, when it is one of this stream's.
  public init?(url: URL, streamID: InstantID<InstantProgressiveMediaStreamRow>) {
    guard url.scheme == Self.scheme, url.host == streamID.rawValue else { return nil }
    let name = url.lastPathComponent
    switch name {
    case "playlist.m3u8":
      self = .playlist
    case "init.mp4":
      self = .initialization
    default:
      guard name.hasSuffix(".m4s"), let index = Int(name.dropLast(4)), index >= 0 else { return nil }
      self = .segment(index)
    }
  }
}
