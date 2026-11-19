// Encodes PCM into a progressive media stream's fragmented MP4 segments with AVFoundation's own HLS segmenter (#1012,
// ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). AVAssetWriter's `.mpeg4AppleHLS` profile hands over an initialization segment
//   and then one self-contained media segment per interval through its delegate, with no file on disk; measured on a
//   Mac, AAC-LC at 32 kbps cost 0.17 CPU seconds a minute of audio.
// - 2026-11-19: every writer ends exactly once, inside the actor, before it is released (#2529). AVAssetWriter crashed on
//   its own queue (com.apple.coremedia.assetwriter, a CoreMedia deferred notification reading freed memory) in test
//   processes that dropped writers still writing and kept several alive at once. A segmenter can now be cancelled; one
//   released while writing cancels its writer first; a second finish returns the first one's outcome instead of
//   finishing a completed file (an Objective-C exception); an append after the end, or one that resumes after a finish
//   or cancel ran during its wait for the input, throws instead of reaching a finished input (another exception).

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

    /// How the segmenter's writer ended (#2529): each writer ends exactly once.
    public enum Ending: Hashable, Sendable {
      /// ``finish()`` completed the file: every segment arrived.
      case finished
      /// AVAssetWriter failed, at an append or at the finish.
      case failed
      /// ``cancel()`` ended it.
      case cancelled
      /// The segmenter was released while its writer still wrote, so it cancelled the writer first.
      case cancelledAtRelease
    }

    /// The initialization segment first, then each media segment, ending after ``finish()``.
    public nonisolated let outputs: AsyncStream<Output>
    public nonisolated let format: InstantProgressiveMediaFormat
    public nonisolated let inputSampleRate: Double
    private let lifetime: WriterLifetime
    private var continuation: AsyncStream<Output>.Continuation { lifetime.continuation }
    private var writer: AVAssetWriter { lifetime.writer }
    private let input: AVAssetWriterInput
    private let collector: SegmentCollector
    private let pcmFormat: CMAudioFormatDescription
    private let startTime: CMTime
    private var onEnd: @Sendable (Ending) -> Void { lifetime.onEnd }
    private var framesAppended: Int64 = 0
    /// Set once, by the first finish or cancel (or the writer's failure); a second finish waits for the first.
    private var ending: Task<Ending, Never>?

    /// - Parameters:
    ///   - format: The encoding; its codecs must be AAC-LC (`mp4a.40.2`).
    ///   - inputSampleRate: The sample rate of the PCM ``append(_:)`` receives; the encoder converts it.
    ///   - startSeconds: Where the first sample sits on the stream's timeline: a stream resumed after a relaunch
    ///     continues at its writer's ``InstantProgressiveMediaWriter/appendedSeconds``.
    ///   - onEnd: Told once how the writer ended, from wherever it ended (a finish, a cancel, a failure, or the release).
    public init(
      format: InstantProgressiveMediaFormat,
      inputSampleRate: Double,
      startSeconds: Double = 0,
      onEnd: @escaping @Sendable (Ending) -> Void = { _ in }
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
      self.lifetime = WriterLifetime(writer: writer, continuation: continuation, onEnd: onEnd)
      self.format = format
      self.inputSampleRate = inputSampleRate
      self.input = input
      self.collector = collector
      self.pcmFormat = pcmFormat
      self.startTime = startTime
    }

    /// Appends mono 16-bit samples at ``inputSampleRate``, after the ones appended before.
    ///
    /// Throws once the writer has ended (finished, cancelled or failed), including when a finish or cancel ran while
    /// this append waited for the input: AVAssetWriter raises an Objective-C exception for a sample appended after the
    /// end (#2529).
    public func append(_ samples: [Int16]) async throws {
      guard !samples.isEmpty else { return }
      try checkWriting("append")
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(for: .milliseconds(5))
        // The actor is reentrant here: a finish or cancel may have ended the writer during the sleep.
        try checkWriting("append")
      }
      let buffer = try sampleBuffer(samples)
      guard input.append(buffer) else {
        _ = end(.failed)
        throw writerError("append")
      }
      framesAppended += Int64(samples.count)
    }

    /// Ends the stream: the last, shorter segment arrives on ``outputs``, which then ends. A second finish returns the
    /// first one's outcome; a finish after a cancel throws.
    public func finish() async throws {
      if ending == nil {
        // A writer that already failed is not asked to finish: its finish would only report the failure again.
        guard writer.status == .writing else {
          _ = end(.failed)
          throw writerError("finish")
        }
        input.markAsFinished()
        ending = Task { await self.completeFinish() }
      }
      guard let ending, await ending.value == .finished else { throw writerError("finish") }
    }

    /// Ends the writer now without completing the file: its outputs end with the segments already made. Nothing after it
    /// reaches the writer; a cancel after the end does nothing (#2529).
    public func cancel() {
      guard ending == nil else { return }
      if writer.status == .writing { writer.cancelWriting() }
      _ = end(writer.status == .failed ? .failed : .cancelled)
    }

    private func completeFinish() async -> Ending {
      await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        writer.finishWriting { done.resume() }
      }
      let how: Ending = writer.status == .completed ? .finished : .failed
      lifetime.hasEnded = true
      continuation.finish()
      onEnd(how)
      return how
    }

    /// Records how the writer ended, once: its outputs end and ``onEnd`` hears it.
    private func end(_ how: Ending) -> Ending {
      guard ending == nil else { return how }
      ending = Task { how }
      lifetime.hasEnded = true
      continuation.finish()
      onEnd(how)
      return how
    }

    private func checkWriting(_ step: String) throws {
      guard ending == nil else { throw Self.error("The segmenter's writer has ended; nothing more can be appended.") }
      guard writer.status == .writing else {
        _ = end(.failed)
        throw writerError(step)
      }
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

  /// The segmenter's AVAssetWriter and what hears its end (#2529). Released with the segmenter, it cancels a writer
  /// still writing, so AVAssetWriter is never deallocated with a file in progress and its queue's work still pending.
  /// Unchecked: the owning actor is the only one that touches it while it lives, and its deinit runs when nothing else
  /// can, so the cancel meets no append, as `cancelWriting` requires.
  private final class WriterLifetime: @unchecked Sendable {
    let writer: AVAssetWriter
    let continuation: AsyncStream<InstantAudioSegmenter.Output>.Continuation
    let onEnd: @Sendable (InstantAudioSegmenter.Ending) -> Void
    /// Set by the segmenter when a finish, a cancel or a failure has ended the writer.
    var hasEnded = false

    init(
      writer: AVAssetWriter,
      continuation: AsyncStream<InstantAudioSegmenter.Output>.Continuation,
      onEnd: @escaping @Sendable (InstantAudioSegmenter.Ending) -> Void
    ) {
      self.writer = writer
      self.continuation = continuation
      self.onEnd = onEnd
    }

    deinit {
      guard !hasEnded else { return }
      if writer.status == .writing {
        writer.cancelWriting()
        onEnd(.cancelledAtRelease)
      } else {
        onEnd(writer.status == .completed ? .finished : .failed)
      }
      continuation.finish()
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
