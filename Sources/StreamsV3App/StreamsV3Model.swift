import Dependencies
import Foundation
import InstantSwiftData
import Observation

@MainActor
@Observable
public final class StreamsV3Model {
  public var clientID: String
  public private(set) var streamID: String?
  public private(set) var content = ""
  public private(set) var byteCount: Int64 = 0
  public private(set) var isDone = false
  public private(set) var status = "Ready"
  public private(set) var errorMessage: String?

  @ObservationIgnored @Dependency(\.defaultInstantSwiftData) private var db
  @ObservationIgnored private var readerTask: Task<Void, Never>?

  public init(clientID: String = UUID().uuidString.lowercased()) {
    self.clientID = clientID
  }

  deinit {
    readerTask?.cancel()
  }

  public func write(
    _ chunks: [String],
    onComplete: @escaping @MainActor @Sendable (InstantStreamMetadata) -> Void = { _ in }
  ) async {
    guard !chunks.isEmpty else { return }
    status = "Starting stream"
    errorMessage = nil
    do {
      let metadata = try await db.createStream(clientID: clientID)
      streamID = metadata.id
      var offset: Int64 = 0
      for chunk in chunks {
        let append = try await db.appendStreamContent(
          streamID: metadata.id,
          content: chunk,
          expectedOffset: offset
        )
        offset += append.chunk.byteCount
      }
      let closed = try await db.closeStream(streamID: metadata.id)
      status = "Complete"
      onComplete(closed)
    } catch {
      status = "Failed"
      errorMessage = String(describing: error)
    }
  }

  public func resume(
    byteOffset: Int64 = 0,
    onUpdate: @escaping @MainActor @Sendable (InstantStreamContentRead) -> Void = { _ in }
  ) {
    readerTask?.cancel()
    status = "Connecting"
    errorMessage = nil
    readerTask = Task { [weak self, clientID] in
      guard let self else { return }
      do {
        let snapshots = try await db.observeStreamContent(
          clientID: clientID,
          byteOffset: byteOffset
        )
        for await snapshot in snapshots {
          try Task.checkCancellation()
          streamID = snapshot.metadata.id
          content = snapshot.content
          byteCount = snapshot.byteCount
          isDone = snapshot.done
          status = snapshot.done ? "Complete" : "Streaming"
          onUpdate(snapshot)
          if snapshot.done { return }
        }
      } catch is CancellationError {
        status = "Cancelled"
      } catch {
        status = "Failed"
        errorMessage = String(describing: error)
      }
    }
  }

  public func cancelReader() {
    readerTask?.cancel()
    readerTask = nil
    status = "Cancelled"
  }
}
