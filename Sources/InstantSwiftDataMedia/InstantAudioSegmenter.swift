// Encodes PCM into a progressive media stream's fragmented MP4 segments with AVFoundation's own HLS segmenter (#1012,
// ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). AVAssetWriter's `.mpeg4AppleHLS` profile hands over an initialization segment
//   and then one self-contained media segment per interval through its delegate, with no file on disk; measured on a
//   Mac, AAC-LC at 32 kbps cost 0.17 CPU seconds a minute of audio.

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation
  import InstantSwiftData

  /// Encodes mono 16-bit PCM into AAC-LC fragmented MP4: an initialization segment, then one media segment each
  /// ``InstantProgressiveMediaFormat/segmentSeconds``.
  ///
  /// The outputs arrive in order on ``outputs``; ``forward(to:)`` hands them to a writer:
  ///
  /// ```swift
  /// let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: 48_000)
  /// async let forwarding: Void = segmenter.forward(to: writer)
  /// try await segmenter.append(samples)  // as audio is captured
  /// try await segmenter.finish()
  /// try await forwarding
  /// ```
  ///
  /// Not on watchOS, which has no `AVAssetWriter`.
  public actor InstantAudioSegmenter {
    public enum Output: Hashable, Sendable {
      case initialization(Data)
      case segment(Data, durationSeconds: Double)
    }

    /// The initialization segment first, then each media segment, ending after ``finish()``.
    public nonisolated let outputs: AsyncStream<Output>
    public nonisolated let format: InstantProgressiveMediaFormat
    public nonisolated let inputSampleRate: Double
    private let continuation: AsyncStream<Output>.Continuation
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let collector: SegmentCollector
    private let pcmFormat: CMAudioFormatDescription
    private let startTime: CMTime
    private var framesAppended: Int64 = 0

    /// - Parameters:
    ///   - format: The encoding; its codecs must be AAC-LC (`mp4a.40.2`).
    ///   - inputSampleRate: The sample rate of the PCM ``append(_:)`` receives; the encoder converts it.
    ///   - startSeconds: Where the first sample sits on the stream's timeline: a stream resumed after a relaunch
    ///     continues at its writer's ``InstantProgressiveMediaWriter/appendedSeconds``.
    public init(
      format: InstantProgressiveMediaFormat,
      inputSampleRate: Double,
      startSeconds: Double = 0
    ) throws {
      guard format.codecs == "mp4a.40.2" else {
        throw Self.error("The segmenter encodes AAC-LC (mp4a.40.2), not \(format.codecs).")
      }
      let writer = AVAssetWriter(contentType: .mpeg4Movie)
      writer.outputFileTypeProfile = .mpeg4AppleHLS
      writer.preferredOutputSegmentInterval = CMTime(seconds: format.segmentSeconds, preferredTimescale: 1_000)
      let timescale = CMTimeScale(inputSampleRate)
      let startTime = CMTime(value: CMTimeValue((startSeconds * inputSampleRate).rounded()), timescale: timescale)
      writer.initialSegmentStartTime = startTime
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVEncoderBitRateKey: format.bitRate,
      ]
      guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
        throw Self.error("AVAssetWriter cannot encode \(format) as HLS fragmented MP4.")
      }
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
      input.expectsMediaDataInRealTime = false
      guard writer.canAdd(input) else { throw Self.error("AVAssetWriter cannot add an audio input.") }
      writer.add(input)

      var asbd = AudioStreamBasicDescription(
        mSampleRate: inputSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
      )
      var pcmFormat: CMAudioFormatDescription?
      let status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
        magicCookie: nil, extensions: nil, formatDescriptionOut: &pcmFormat
      )
      guard status == noErr, let pcmFormat else { throw Self.error("No PCM format description (\(status)).") }

      let (outputs, continuation) = AsyncStream<Output>.makeStream(bufferingPolicy: .unbounded)
      let collector = SegmentCollector(continuation: continuation)
      writer.delegate = collector
      guard writer.startWriting() else {
        throw Self.error("AVAssetWriter did not start: \(writer.error.map(String.init(describing:)) ?? "no error").")
      }
      writer.startSession(atSourceTime: startTime)

      self.outputs = outputs
      self.continuation = continuation
      self.format = format
      self.inputSampleRate = inputSampleRate
      self.writer = writer
      self.input = input
      self.collector = collector
      self.pcmFormat = pcmFormat
      self.startTime = startTime
    }

    /// Appends mono 16-bit samples at ``inputSampleRate``, after the ones appended before.
    public func append(_ samples: [Int16]) async throws {
      guard !samples.isEmpty else { return }
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw writerError("append") }
        try await Task.sleep(for: .milliseconds(5))
      }
      let buffer = try sampleBuffer(samples)
      guard input.append(buffer) else { throw writerError("append") }
      framesAppended += Int64(samples.count)
    }

    /// Ends the stream: the last, shorter segment arrives on ``outputs``, which then ends.
    public func finish() async throws {
      input.markAsFinished()
      await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        writer.finishWriting { done.resume() }
      }
      continuation.finish()
      guard writer.status == .completed else { throw writerError("finish") }
    }

    /// The seconds of audio appended so far.
    public var appendedSeconds: Double { Double(framesAppended) / inputSampleRate }

    /// Hands every output to `writer`, in order, until ``finish()``.
    public nonisolated func forward(to writer: InstantProgressiveMediaWriter) async throws {
      for await output in outputs {
        switch output {
        case let .initialization(data):
          try await writer.start(initialization: data)
        case let .segment(data, durationSeconds):
          try await writer.append(data, durationSeconds: durationSeconds)
        }
      }
    }

    private func sampleBuffer(_ samples: [Int16]) throws -> CMSampleBuffer {
      let byteCount = samples.count * 2
      var block: CMBlockBuffer?
      var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &block
      )
      guard status == noErr, let block else { throw Self.error("No block buffer (\(status)).") }
      status = samples.withUnsafeBytes { raw in
        CMBlockBufferReplaceDataBytes(
          with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
      }
      guard status == noErr else { throw Self.error("Could not copy samples (\(status)).") }
      var buffer: CMSampleBuffer?
      status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: pcmFormat, sampleCount: samples.count,
        presentationTimeStamp: CMTimeAdd(startTime, CMTime(value: framesAppended, timescale: startTime.timescale)),
        packetDescriptions: nil, sampleBufferOut: &buffer
      )
      guard status == noErr, let buffer else { throw Self.error("No sample buffer (\(status)).") }
      return buffer
    }

    private func writerError(_ step: String) -> InstantError {
      Self.error("AVAssetWriter failed to \(step): \(writer.error.map(String.init(describing:)) ?? "no error").")
    }

    private static func error(_ message: String) -> InstantError {
      InstantError(
        code: .implementationFailed,
        operation: "segment progressive media",
        message: message,
        recovery: "Check the format against ADR 0021's measured settings."
      )
    }
  }

  /// AVAssetWriter's delegate: called on the writer's own queue, it only yields into the stream, which keeps order.
  private final class SegmentCollector: NSObject, AVAssetWriterDelegate, Sendable {
    let continuation: AsyncStream<InstantAudioSegmenter.Output>.Continuation

    init(continuation: AsyncStream<InstantAudioSegmenter.Output>.Continuation) {
      self.continuation = continuation
    }

    func assetWriter(
      _ writer: AVAssetWriter,
      didOutputSegmentData segmentData: Data,
      segmentType: AVAssetSegmentType,
      segmentReport: AVAssetSegmentReport?
    ) {
      switch segmentType {
      case .initialization:
        continuation.yield(.initialization(segmentData))
      case .separable:
        let duration = segmentReport?.trackReports.first?.duration.seconds ?? 0
        continuation.yield(.segment(segmentData, durationSeconds: duration))
      @unknown default:
        break
      }
    }
  }
#endif
