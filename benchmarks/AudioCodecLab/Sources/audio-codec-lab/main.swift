// audio-codec-lab: the command-line face of AudioCodecLab (#1012, ADR 0021). Every command prints one JSON object
// per result line, so a driver script can collect a measurement matrix.
//
//   audio-codec-lab probe
//   audio-codec-lab encode --input speech.wav --codec opus --rate 48000 --bitrate 24000 [--quality high]
//                          [--mode vbr] [--out-dir dir --name n] [--seconds 300]
//   audio-codec-lab hls    --input speech.wav --codec aac-lc --rate 48000 --bitrate 32000 --segment 6
//                          [--quality high] --out-dir dir --name n
//   audio-codec-lab play   --url http://127.0.0.1:8765/live.m3u8 --seconds 120 [--capture-start <epoch s>]
//                          [--offset <s>] [--loader absolute|redirect] [--recover]
//   audio-codec-lab check  --file out.mp4

import AVFoundation
import AudioCodecLab
import AudioToolbox
import Foundation
#if os(macOS)
  import WebKit
#endif

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
  FileHandle.standardError.write(Data("usage: audio-codec-lab probe|encode|hls|play|check [options]\n".utf8))
  exit(64)
}
arguments.removeFirst()

func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return nil }
  return arguments[index + 1]
}

func required(_ name: String) -> String {
  guard let value = option(name) else {
    FileHandle.standardError.write(Data("missing --\(name)\n".utf8))
    exit(64)
  }
  return value
}

func emit(_ object: [String: Any]) {
  let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  print(String(decoding: data, as: UTF8.self))
  fflush(stdout)
}

func rounded(_ value: Double, _ places: Int = 4) -> Double {
  let scale = pow(10, Double(places))
  return (value * scale).rounded() / scale
}

func osVersion() -> String {
  ProcessInfo.processInfo.operatingSystemVersionString
}

func loadInput() throws -> PCM16 {
  let seconds = option("seconds").flatMap(Double.init)
  return try PCM16(contentsOf: URL(fileURLWithPath: required("input")), maxSeconds: seconds)
}

func codecOption() -> LabCodec {
  guard let codec = LabCodec(rawValue: required("codec")) else {
    FileHandle.standardError.write(Data("--codec must be one of \(LabCodec.allCases.map(\.rawValue))\n".utf8))
    exit(64)
  }
  return codec
}

do {
  switch command {
  case "probe":
    let result = probe()
    emit([
      "kind": "probe",
      "os": osVersion(),
      "encoderImplementations": result.encoderImplementations,
      "encoders": result.encoders,
      "decoders": result.decoders,
      "playableMIMETypes": result.playableMIMETypes,
      "hlsWriter": result.hlsWriter,
      "bitRates": result.bitRates,
    ])

  case "encode":
    let pcm = try loadInput()
    let codec = codecOption()
    let rate = Double(required("rate"))!
    let bitRate = Int(required("bitrate"))!
    let quality = option("quality").flatMap(LabQuality.init(rawValue:))
    let mode = option("mode").flatMap(LabBitRateMode.init(rawValue:))
    let framesPerPacket = option("frames-per-packet").flatMap(UInt32.init)
    let encoded = try encode(
      pcm, codec: codec, sampleRate: rate, bitRate: bitRate, quality: quality, mode: mode,
      framesPerPacket: framesPerPacket
    )
    var record: [String: Any] = [
      "kind": "encode",
      "os": osVersion(),
      "codec": codec.rawValue,
      "rate": Int(rate),
      "bitrate": bitRate,
      "actualBitRate": Int(encoded.actualBitRate),
      "quality": quality?.rawValue ?? "default",
      "mode": mode?.rawValue ?? "default",
      "inputSeconds": rounded(encoded.inputSeconds, 3),
      "packetBytes": encoded.packets.count,
      "packets": encoded.packetDescriptions.count,
      "framesPerPacket": Int(encoded.format.mFramesPerPacket),
      "outputSampleRate": Int(encoded.format.mSampleRate),
      "leadingFrames": Int(encoded.leadingFrames),
      "bytesPerMinute": Int(encoded.bytesPerMinute),
      "kbpsMeasured": rounded(Double(encoded.packets.count) * 8 / encoded.inputSeconds / 1000, 2),
      "cpuSecondsPerMinute": rounded(encoded.cpuSecondsPerMinute),
      "processCPUSecondsPerMinute": rounded(encoded.processCPUSeconds / encoded.inputSeconds * 60),
      "corePercent": rounded(encoded.corePercent),
      "realtimeFactor": rounded(encoded.inputSeconds / max(encoded.wallSeconds, 1e-9), 1),
      "notes": encoded.settingNotes,
    ]
    if let directory = option("out-dir") {
      let name = option("name") ?? "\(codec.rawValue)-\(Int(rate))-\(bitRate)"
      let base = URL(fileURLWithPath: directory)
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
      do {
        record["cafBytes"] = try writeAudioFile(encoded, to: base.appendingPathComponent("\(name).caf"), type: kAudioFileCAFType)
      } catch {
        record["cafError"] = "\(error)"
      }
      do {
        record["m4aBytes"] = try writeAudioFile(encoded, to: base.appendingPathComponent("\(name).m4a"), type: kAudioFileM4AType)
      } catch {
        record["m4aError"] = "\(error)"
      }
      let decoded = try decode(encoded, sampleRate: 16_000)
      try writeWAV(decoded.samples, sampleRate: 16_000, to: base.appendingPathComponent("\(name).decoded-16k.wav"))
      record["decodeCPUSecondsPerMinute"] = rounded(decoded.cpuSeconds / encoded.inputSeconds * 60)
    }
    emit(record)

  case "hls":
    let pcm = try loadInput()
    let codec = codecOption()
    let rate = Double(required("rate"))!
    let bitRate = Int(required("bitrate"))!
    let segmentSeconds = Double(required("segment"))!
    let quality = option("quality").flatMap(LabQuality.init(rawValue:))
    let result = try writeHLS(pcm, codec: codec, sampleRate: rate, bitRate: bitRate, segmentSeconds: segmentSeconds, quality: quality)
    let directory = URL(fileURLWithPath: required("out-dir")).appendingPathComponent(option("name") ?? "\(codec.rawValue)-\(Int(rate))-\(bitRate)-\(Int(segmentSeconds))s")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try result.initialization.write(to: directory.appendingPathComponent("init.mp4"))
    var whole = result.initialization
    for (index, segment) in result.segments.enumerated() {
      try segment.data.write(to: directory.appendingPathComponent(String(format: "seg-%06d.m4s", index)))
      whole.append(segment.data)
    }
    try hlsPlaylist(segments: result.segments, ended: true).write(
      to: directory.appendingPathComponent("vod.m3u8"), atomically: true, encoding: .utf8)
    let wholeURL = directory.appendingPathComponent("whole.mp4")
    try whole.write(to: wholeURL)
    let asset = AVURLAsset(url: wholeURL)
    let playable = try await asset.load(.isPlayable)
    let duration = try await asset.load(.duration).seconds
    let durations = result.segments.map(\.duration)
    let sizes = result.segments.map(\.data.count)
    emit([
      "kind": "hls",
      "os": osVersion(),
      "codec": codec.rawValue,
      "rate": Int(rate),
      "bitrate": bitRate,
      "quality": quality?.rawValue ?? "default",
      "segmentSeconds": segmentSeconds,
      "inputSeconds": rounded(result.inputSeconds, 3),
      "initBytes": result.initialization.count,
      "segments": result.segments.count,
      "segmentBytesMedian": sizes.sorted()[sizes.count / 2],
      "segmentSecondsMin": rounded(durations.min() ?? 0, 3),
      "segmentSecondsMax": rounded(durations.max() ?? 0, 3),
      "totalBytes": result.totalBytes,
      "bytesPerMinute": Int(result.bytesPerMinute),
      "kbpsMeasured": rounded(Double(result.totalBytes) * 8 / result.inputSeconds / 1000, 2),
      "cpuSecondsPerMinute": rounded(result.cpuSecondsPerMinute),
      "corePercent": rounded(result.corePercent),
      "realtimeFactor": rounded(result.inputSeconds / max(result.wallSeconds, 1e-9), 1),
      "wholeFilePlayable": playable,
      "wholeFileSeconds": rounded(duration, 3),
      "directory": directory.path,
    ])

  case "check":
    let url = URL(fileURLWithPath: required("file"))
    let asset = AVURLAsset(url: url)
    let playable = try await asset.load(.isPlayable)
    let duration = try await asset.load(.duration).seconds
    var formats: [String] = []
    for track in try await asset.loadTracks(withMediaType: .audio) {
      for description in try await track.load(.formatDescriptions) {
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
          formats.append("\(fourCCString(asbd.mFormatID)) \(Int(asbd.mSampleRate)) Hz")
        }
      }
    }
    emit(["kind": "check", "os": osVersion(), "file": url.lastPathComponent, "playable": playable, "seconds": rounded(duration, 3), "formats": formats])

  case "play":
    let url = URL(string: required("url"))!
    let seconds = Double(option("seconds") ?? "60")!
    let captureStart = option("capture-start").flatMap(Double.init)
    // --loader serves the playlist through AVAssetResourceLoader under a custom scheme, the way a client that builds
    // the playlist from rows hands it to AVPlayer. `absolute`: segment URIs become absolute http(s) URLs AVPlayer
    // fetches itself. `redirect`: segment URIs stay in the custom scheme and the loader answers each with a 302 to its
    // http(s) URL, the way a reader that signs a segment's URL only when the player asks for it would.
    // --recover rebuilds the item when it fails (a live playlist that stopped growing fails with CoreMedia -12888) and
    // seeks back to where it was.
    let loaderMode = option("loader")
    let loader = loaderMode.map { PlaylistLoader(origin: url, redirect: $0 == "redirect") }
    let recover = arguments.contains("--recover")
    func makeItem() -> AVPlayerItem {
      let item: AVPlayerItem
      if let loader {
        let asset = AVURLAsset(url: loader.customURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        item = AVPlayerItem(asset: asset)
      } else {
        item = AVPlayerItem(url: url)
      }
      if let offset = option("offset").flatMap(Double.init) {
        item.configuredTimeOffsetFromLive = CMTime(seconds: offset, preferredTimescale: 1_000)
        item.automaticallyPreservesTimeOffsetFromLive = true
      }
      return item
    }
    var item = makeItem()
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    var stalls = 0
    var recoveries = 0
    var lastGoodTime = 0.0
    let observer = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
    ) { _ in stalls += 1 }
    let started = Date().timeIntervalSince1970
    player.play()
    var firstPlayingAt: Double?
    var behindCapture: [Double] = []
    while Date().timeIntervalSince1970 - started < seconds {
      RunLoop.main.run(until: Date().addingTimeInterval(1))
      let now = Date().timeIntervalSince1970
      if recover, item.status == .failed {
        recoveries += 1
        item = makeItem()
        player.replaceCurrentItem(with: item)
        if lastGoodTime > 0 { await player.seek(to: CMTime(seconds: lastGoodTime, preferredTimescale: 1_000)) }
        player.play()
      }
      let current = item.currentTime().seconds
      if current.isFinite, current > 0 { lastGoodTime = current }
      let seekableEnd = item.seekableTimeRanges.last.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds } ?? .nan
      if firstPlayingAt == nil, player.timeControlStatus == .playing { firstPlayingAt = now - started }
      var record: [String: Any] = [
        "kind": "play-tick",
        "t": rounded(now - started, 1),
        "status": item.status.rawValue,
        "timeControl": player.timeControlStatus.rawValue,
        "current": rounded(current, 2),
        "seekableEnd": seekableEnd.isNaN ? -1 : rounded(seekableEnd, 2),
        "stalls": stalls,
      ]
      if let reason = player.reasonForWaitingToPlay { record["waiting"] = reason.rawValue }
      if let captureStart, player.timeControlStatus == .playing {
        let behind = now - captureStart - current
        behindCapture.append(behind)
        record["behindCapture"] = rounded(behind, 2)
      }
      if let error = item.error { record["error"] = "\(error)" }
      if let events = item.errorLog()?.events, !events.isEmpty {
        record["errorLog"] = events.suffix(3).map { "\($0.errorStatusCode) \($0.errorDomain) \($0.uri ?? "-") \($0.errorComment ?? "")" }
      }
      emit(record)
    }
    NotificationCenter.default.removeObserver(observer)
    let sorted = behindCapture.sorted()
    emit([
      "kind": "play",
      "os": osVersion(),
      "url": url.absoluteString,
      "loader": loaderMode ?? "none",
      "playlistRequests": loader?.requests ?? 0,
      "segmentRedirects": loader?.redirects ?? 0,
      "recoveries": recoveries,
      "finalCurrent": rounded(lastGoodTime, 2),
      "firstPlayingAfter": firstPlayingAt.map { rounded($0, 2) } ?? -1,
      "stalls": stalls,
      "accessLogStalls": item.accessLog()?.events.reduce(0) { $0 + $1.numberOfStalls } ?? -1,
      "behindCaptureMedian": sorted.isEmpty ? -1 : rounded(sorted[sorted.count / 2], 2),
      "behindCaptureMax": sorted.last.map { rounded($0, 2) } ?? -1,
      "behindCaptureMin": sorted.first.map { rounded($0, 2) } ?? -1,
    ])

  case "webkit":
    #if os(macOS)
      // The browser check page in WebKit (Safari's engine) on this Mac: what MSE and <audio> accept and play.
      let url = URL(string: required("url"))!
      let configuration = WKWebViewConfiguration()
      configuration.mediaTypesRequiringUserActionForPlayback = []
      let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
      page.load(URLRequest(url: url))
      let deadline = Date().addingTimeInterval(Double(option("seconds") ?? "90")!)
      var verdict = "{\"kind\":\"webkit\",\"error\":\"timeout\"}"
      while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if page.title == "done" {
          let value: Any? = try await page.evaluateJavaScript("document.getElementById('result').textContent")
          verdict = value as? String ?? "{}"
          break
        }
      }
      print(verdict)
    #endif

  default:
    FileHandle.standardError.write(Data("unknown command \(command)\n".utf8))
    exit(64)
  }
} catch {
  emit(["kind": "error", "command": command, "error": "\(error)"])
  exit(1)
}

/// Answers AVPlayer's requests for `labhls://`: the playlist by fetching the real one and rewriting its URIs, and in
/// redirect mode each segment with a 302 to its http(s) URL.
final class PlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
  let origin: URL
  let redirect: Bool
  let queue = DispatchQueue(label: "audio-codec-lab.playlist-loader")
  private(set) var requests = 0
  private(set) var redirects = 0

  init(origin: URL, redirect: Bool) {
    self.origin = origin
    self.redirect = redirect
  }

  var customURL: URL { custom(origin) }

  func custom(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    components.scheme = "labhls"
    return components.url!
  }

  func http(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    components.scheme = origin.scheme
    return components.url!
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let requested = loadingRequest.request.url else { return false }
    if ProcessInfo.processInfo.environment["LAB_DEBUG"] != nil {
      FileHandle.standardError.write(Data("loader \(requested) info=\(loadingRequest.contentInformationRequest != nil) data=\(String(describing: loadingRequest.dataRequest?.requestedLength))\n".utf8))
    }
    if requested.pathExtension != "m3u8" {
      // A segment or the initialization section: send the player to the real URL.
      redirects += 1
      let target = http(requested)
      loadingRequest.redirect = URLRequest(url: target)
      loadingRequest.response = HTTPURLResponse(url: target, statusCode: 302, httpVersion: nil, headerFields: nil)
      loadingRequest.finishLoading()
      return true
    }
    requests += 1
    let task = URLSession.shared.dataTask(with: origin) { data, _, error in
      guard let data, let text = String(data: data, encoding: .utf8) else {
        loadingRequest.finishLoading(with: error ?? LabError("no playlist"))
        return
      }
      let base = self.origin.deletingLastPathComponent()
      let rewrite = { (uri: String) -> String in
        let absolute = base.appendingPathComponent(uri)
        return (self.redirect ? self.custom(absolute) : absolute).absoluteString
      }
      let rewritten = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        if line.hasPrefix("#EXT-X-MAP:URI=\""), let end = line.dropFirst(16).firstIndex(of: "\"") {
          let uri = line[line.index(line.startIndex, offsetBy: 16)..<end]
          return "#EXT-X-MAP:URI=\"\(rewrite(String(uri)))\""
        }
        if !line.isEmpty, !line.hasPrefix("#") { return rewrite(String(line)) }
        return String(line)
      }.joined(separator: "\n")
      let body = Data(rewritten.utf8)
      // Apple's AVARLDelegateDemo answers a playlist with data alone; LAB_CONTENT_INFO also fills the content
      // information, to compare (2026-10-23: with it filled, the item failed with -1002 "unsupported URL").
      if let type = ProcessInfo.processInfo.environment["LAB_CONTENT_INFO"] {
        loadingRequest.contentInformationRequest?.contentType = type
        loadingRequest.contentInformationRequest?.contentLength = Int64(body.count)
        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
      }
      loadingRequest.dataRequest?.respond(with: body)
      loadingRequest.finishLoading()
    }
    task.resume()
    return true
  }
}
