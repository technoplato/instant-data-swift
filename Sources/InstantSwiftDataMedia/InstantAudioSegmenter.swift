// Encodes PCM into a progressive media stream's fragmented MP4 segments with AVFoundation's own HLS segmenter (#1012,
// ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation
  import InstantSwiftData

  public actor InstantAudioSegmenter {
    public enum Output: Hashable, Sendable {
      case initialization(Data)
      case segment(Data, durationSeconds: Double)
    }

    public nonisolated let outputs: AsyncStream<Output>
    private let continuation: AsyncStream<Output>.Continuation

    public init(
      format: InstantProgressiveMediaFormat,
      inputSampleRate: Double,
      startSeconds: Double = 0
    ) throws {
      (outputs, continuation) = AsyncStream<Output>.makeStream()
      throw InstantError(
        code: .implementationFailed,
        operation: "segment progressive media",
        message: "Not implemented yet (#1012).",
        recovery: "None."
      )
    }

    public func append(_ samples: [Int16]) async throws {}

    public func finish() async throws {}

    public var appendedSeconds: Double { 0 }

    public nonisolated func forward(to writer: InstantProgressiveMediaWriter) async throws {}
  }
#endif
