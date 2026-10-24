// progressive-media-live: progressive media end to end over a live Instant app (#1012, instant-data-swift ADR 0021).
//
// A recording is played out of a WAV in real time, the way Scribe's recorder writes one: every 5 s heartbeat the
// audio that is final (all but its last 10 s) goes through the library's InstantAudioSegmenter and
// InstantProgressiveMediaWriter on one client, which stores each 6 s segment in `$files` and lists it in rows. A second
// client, signed in as the same user with a store of its own, waits for the first listed segment and plays the stream
// through AVPlayer and InstantProgressiveMediaResourceLoader, as another device would. Every 2 s it prints how far the
// player is behind the recording's live edge. At Stop the rest goes, the stream finishes, and the finished playlist
// plays from its start and from its middle. The rows and files are deleted at the end.
//
// Usage (a THROWAWAY app; a guest sign-in, no admin token; the audio is uploaded, so use speech nobody minds):
//   INSTANT_APP_ID=<app id> progressive-media-live <speech.wav> [--seconds 180] [--margin 10] [--join 90]
//
// History:
// - 2026-10-23 (#1012): first version.

@preconcurrency import AVFoundation
import Foundation
import InstantSwiftData
import InstantSwiftDataMedia

@main
struct ProgressiveMediaLive {
  static let productionAppIDs: Set<String> = [
    "e7c49961-d702-46a1-82c1-fca9a61f6a4d", "28c98cc4-e65b-41be-a5bc-204827f5d364",
  ]

  static func main() async {
    do {
      try await run()
    } catch {
      emit(["event": "failed", "error": String(describing: error)])
      exit(1)
    }
  }

  static func run() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    func option(_ name: String, _ fallback: Double) -> Double {
      guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count,
        let value = Double(arguments[index + 1])
      else { return fallback }
      arguments.removeSubrange(index...(index + 1))
      return value
    }
    let seconds = option("--seconds", 180)
    let margin = option("--margin", 10)
    // When the other device opens the recording: at its first listed segment (0), or this many seconds in.
    let join = option("--join", 0)
    guard let path = arguments.first else {
      throw Failure("usage: progressive-media-live <speech.wav> [--seconds 180] [--margin 10] [--join 90]")
    }
    guard let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"], !appID.isEmpty,
      !productionAppIDs.contains(appID)
    else { throw Failure("Refusing: point INSTANT_APP_ID at a throwaway app.") }

    let wav = try WAV(url: URL(fileURLWithPath: path))
    let recordSeconds = min(seconds, wav.seconds)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("progressive-media-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // The recording device and the other device: one user, two stores.
    let writerClient = try await client(appID: appID, store: directory.appendingPathComponent("writer.sqlite"))
    let session = try await writerClient.signInAsGuest()
    _ = try await writerClient.connect()
    guard let refreshToken = session.refreshToken else { throw Failure("The guest session has no refresh token.") }
    let playerClient = try await client(appID: appID, store: directory.appendingPathComponent("player.sqlite"))
    _ = try await playerClient.signInWithRefreshToken(refreshToken, userID: session.userID)
    _ = try await playerClient.connect()
    emit(["event": "signed-in", "app": String(appID.prefix(8)), "user": String(session.userID.prefix(8))])

    // Under library/<user>/: the throwaway app's storage rules let a user store files only there (ownsLibraryInPath).
    let stream = InstantProgressiveMediaStream(
      key: "progressive-media-live:\(UUID().uuidString)",
      pathPrefix: "library/\(session.userID)/progressive-media-live/\(UUID().uuidString.lowercased())"
    )
    let writer = try InstantProgressiveMediaWriter(
      stream: stream,
      ownerUserID: session.userID,
      spool: InstantProgressiveMediaSpool(directory: directory.appendingPathComponent("spool")),
      storage: .live(writerClient)
    )
    let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: Double(wav.sampleRate))
    let forwarding = Task { try await segmenter.forward(to: writer) }
    let delivery = Task {
      do {
        try await writer.deliver()
      } catch {
        emit(["event": "delivery-ended", "error": String(describing: error)])
        throw error
      }
    }

    // The recorder: a 5 s heartbeat hands the segmenter what is final.
    let start = ContinuousClock.now
    let elapsed: @Sendable () -> Double = {
      let duration = ContinuousClock.now - start
      return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    let recorder = Task {
      var fed = 0
      while elapsed() < recordSeconds {
        try await Task.sleep(for: .seconds(5))
        let final = min(recordSeconds, max(0, elapsed() - margin))
        let through = Int(final * Double(wav.sampleRate))
        if through > fed {
          try await segmenter.append(Array(wav.samples[fed..<through]))
          fed = through
        }
      }
      // Stop: all of it, then the last segment and the finished row.
      let end = Int(recordSeconds * Double(wav.sampleRate))
      if end > fed { try await segmenter.append(Array(wav.samples[fed..<end])) }
      try await segmenter.finish()
      try await forwarding.value
      try await writer.finish()
      emit(["event": "stopped", "t": round(elapsed()), "appendedSeconds": round(await writer.appendedSeconds)])
    }

    // The other device: waits for a listed segment, then plays the live playlist.
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: .live(playerClient))
    var firstListed: Double?
    var waited = 0
    while firstListed == nil {
      try await Task.sleep(for: .seconds(1))
      waited += 1
      do {
        let snapshot = try await reader.refresh()
        if !snapshot.segments.isEmpty { firstListed = elapsed() }
        if waited % 5 == 0 {
          emit([
            "event": "waiting", "t": round(elapsed()), "streamRow": snapshot.stream != nil,
            "listed": Double(snapshot.segments.count), "writerNextIndex": Double(await writer.nextIndex),
            "writerLastFailure": await writer.lastFailure ?? "",
            "storedFiles": Double((try? await writerClient.storedFiles().count) ?? -1),
            "pendingMutations": Double((try? await writerClient.pendingMutations().count) ?? -1),
          ])
        }
      } catch {
        emit(["event": "refresh-failed", "t": round(elapsed()), "error": String(describing: error)])
      }
      if waited > 240 { throw Failure("No segment was listed within 240 s.") }
    }
    emit(["event": "first-segment-listed", "t": round(firstListed ?? 0)])
    while elapsed() < join { try await Task.sleep(for: .milliseconds(200)) }
    if join > 0 { emit(["event": "joined", "t": round(elapsed())]) }
    let live = InstantProgressiveMediaResourceLoader(reader: reader)
    let player = AVPlayer(playerItem: AVPlayerItem(asset: live.makeAsset()))
    player.play()
    var replays = 0
    var lags: [Double] = []
    while true {
      try await Task.sleep(for: .seconds(2))
      let now = elapsed()
      let position = player.currentTime().seconds
      let status = player.currentItem?.status
      if status == .failed {
        throw Failure("The live item failed: \(String(describing: player.currentItem?.error))")
      }
      let isPlaying = player.timeControlStatus == .playing
      if position.isFinite, position > 0, isPlaying, now < recordSeconds {
        lags.append(now - position)
      }
      emit([
        "event": "live", "t": round(now), "player": position.isFinite ? round(position) : -1,
        "lag": position.isFinite && position > 0 ? round(now - position) : -1,
        "status": String(describing: player.timeControlStatus.rawValue), "rate": Double(player.rate),
      ])
      // AVPlayer plays to the live edge and stops without an error when the segments stop coming; told to play again.
      if player.rate == 0, now < recordSeconds + 30 {
        replays += 1
        player.play()
      }
      if now >= recordSeconds + 30 { break }
    }
    player.pause()
    try await recorder.value

    // The stream finishes; the other device lists it whole and plays it as a file would.
    let stop = elapsed()
    var finished = try await reader.refresh()
    while !finished.isFinished {
      guard elapsed() - stop < 120 else { throw Failure("The stream was not listed whole within 120 s of Stop.") }
      try await Task.sleep(for: .seconds(1))
      finished = try await reader.refresh()
    }
    try await delivery.value
    let listedAfterStop = elapsed() - stop
    let whole = InstantProgressiveMediaResourceLoader(reader: reader)
    let vod = AVPlayer(playerItem: AVPlayerItem(asset: whole.makeAsset()))
    while vod.currentItem?.status == .unknown { try await Task.sleep(for: .milliseconds(100)) }
    guard vod.currentItem?.status == .readyToPlay else {
      throw Failure("The finished item failed: \(String(describing: vod.currentItem?.error))")
    }
    let duration = vod.currentItem?.duration.seconds ?? 0
    vod.play()
    try await Task.sleep(for: .seconds(3))
    let fromStart = vod.currentTime().seconds
    await vod.seek(to: CMTime(seconds: duration / 2, preferredTimescale: 600))
    vod.play()
    try await Task.sleep(for: .seconds(3))
    let fromMiddle = vod.currentTime().seconds - duration / 2
    vod.pause()
    let sorted = lags.sorted()
    emit([
      "event": "summary", "recordSeconds": recordSeconds, "margin": margin, "join": join,
      "firstSegmentListedSeconds": round(firstListed ?? 0),
      "lagMedianSeconds": sorted.isEmpty ? -1 : round(sorted[sorted.count / 2]),
      "lagMaxSeconds": sorted.last.map(round) ?? -1, "lagMinSeconds": sorted.first.map(round) ?? -1,
      "replays": Double(replays), "listedWholeAfterStopSeconds": round(listedAfterStop),
      "segments": Double(finished.segments.count), "finishedDurationSeconds": round(duration),
      "playedFromStartSeconds": round(fromStart), "playedFromMiddleSeconds": round(fromMiddle),
    ])

    // Leave the throwaway app as it was.
    var mutations = finished.segments.map { InstantProgressiveMediaSegmentRow.delete(id: stream.segmentID($0.index)) }
    mutations.append(InstantProgressiveMediaStreamRow.delete(id: stream.id))
    try await writerClient.transact(mutations)
    var deletedFiles = 0
    for file in try await writerClient.storedFiles() where file.name.hasPrefix(stream.pathPrefix) {
      _ = try? await writerClient.deleteStoredFile(id: file.id)
      deletedFiles += 1
    }
    try await writerClient.waitForAllPendingMutations()
    emit(["event": "cleaned-up", "rowsDeleted": Double(mutations.count), "filesDeleted": Double(deletedFiles)])
  }

  static func client(appID: String, store: URL) async throws -> InstantSwiftDataClient {
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: store,
      initialAttributes: InstantProgressiveMediaStreamRow.instantAttributes
        + InstantProgressiveMediaSegmentRow.instantAttributes,
      refreshTokenVerifier: .live,
      guestAuthenticator: .live,
      authTokenInvalidator: .live
    )
    configuration.liveTransport = .live
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration, storageTransport: .live())
    return InstantSwiftDataClient(runtime: runtime)
  }

  static func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }

  static func emit(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
  }
}

struct Failure: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

/// A mono 16-bit PCM WAV, read whole.
struct WAV {
  var sampleRate: Int
  var samples: [Int16]
  var seconds: Double { Double(samples.count) / Double(sampleRate) }

  init(url: URL) throws {
    let data = try Data(contentsOf: url)
    func uint32(_ offset: Int) -> UInt32 { data[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    func uint16(_ offset: Int) -> UInt16 { UInt16(data[offset]) | UInt16(data[offset + 1]) << 8 }
    guard data.count > 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF" else { throw Failure("Not a WAV.") }
    var offset = 12
    var rate = 0
    var channels = 0
    var bits = 0
    while offset + 8 <= data.count {
      let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
      let size = Int(uint32(offset + 4))
      if id == "fmt " {
        channels = Int(uint16(offset + 10))
        rate = Int(uint32(offset + 12))
        bits = Int(uint16(offset + 22))
      } else if id == "data" {
        guard channels == 1, bits == 16, rate > 0 else { throw Failure("The WAV must be mono 16-bit PCM.") }
        let body = data[(offset + 8)..<min(data.count, offset + 8 + size)]
        var samples = [Int16](repeating: 0, count: body.count / 2)
        _ = samples.withUnsafeMutableBytes { body.copyBytes(to: $0) }
        self.sampleRate = rate
        self.samples = samples
        return
      }
      offset += 8 + size + (size % 2)
    }
    throw Failure("The WAV has no data chunk.")
  }
}
