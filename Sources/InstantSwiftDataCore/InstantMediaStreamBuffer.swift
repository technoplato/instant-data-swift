import Foundation

public enum InstantMediaStreamOverflowPolicy: String, Codable, Hashable, Sendable {
  /// Suspend the producer until a consumer releases enough resident bytes.
  case suspendProducer
  /// Explicit realtime policy for preview media where latency is more important than completeness.
  case dropOldest
  /// Fail immediately rather than retaining or dropping additional media.
  case fail
}

public struct InstantMediaStreamBufferPolicy: Codable, Hashable, Sendable {
  public var maximumBytes: Int
  public var maximumFrames: Int
  public var overflow: InstantMediaStreamOverflowPolicy

  public init(
    maximumBytes: Int,
    maximumFrames: Int = 256,
    overflow: InstantMediaStreamOverflowPolicy = .suspendProducer
  ) {
    self.maximumBytes = maximumBytes
    self.maximumFrames = maximumFrames
    self.overflow = overflow
  }

  /// Lossless producer backpressure suitable for recording audio/video.
  public static func realtime(
    maximumBytes: Int = 1_048_576,
    maximumFrames: Int = 256
  ) -> Self {
    Self(
      maximumBytes: maximumBytes,
      maximumFrames: maximumFrames,
      overflow: .suspendProducer
    )
  }

  /// Explicit low-latency preview policy that may discard the oldest pending frame.
  public static func preview(
    maximumBytes: Int = 4_194_304,
    maximumFrames: Int = 12
  ) -> Self {
    Self(
      maximumBytes: maximumBytes,
      maximumFrames: maximumFrames,
      overflow: .dropOldest
    )
  }
}

public enum InstantMediaStreamBufferError: Error, Equatable, Sendable {
  case invalidPolicy
  case frameExceedsMaximum(actualBytes: Int, maximumBytes: Int)
  case overflow(residentBytes: Int, residentFrames: Int)
  case closed
}

public struct InstantMediaStreamBufferMetrics: Codable, Equatable, Hashable, Sendable {
  public var residentBytes: Int
  public var residentFrames: Int
  public var peakResidentBytes: Int
  public var peakResidentFrames: Int
  public var totalEnqueuedFrames: Int64
  public var totalDequeuedFrames: Int64
  public var droppedFrames: Int64
  public var suspendedProducerCount: Int64

  public init(
    residentBytes: Int = 0,
    residentFrames: Int = 0,
    peakResidentBytes: Int = 0,
    peakResidentFrames: Int = 0,
    totalEnqueuedFrames: Int64 = 0,
    totalDequeuedFrames: Int64 = 0,
    droppedFrames: Int64 = 0,
    suspendedProducerCount: Int64 = 0
  ) {
    self.residentBytes = residentBytes
    self.residentFrames = residentFrames
    self.peakResidentBytes = peakResidentBytes
    self.peakResidentFrames = peakResidentFrames
    self.totalEnqueuedFrames = totalEnqueuedFrames
    self.totalDequeuedFrames = totalDequeuedFrames
    self.droppedFrames = droppedFrames
    self.suspendedProducerCount = suspendedProducerCount
  }
}

/// Amortized O(1) FIFO storage that never shifts live media payloads.
///
/// The backing array grows geometrically only up to the caller's explicit frame
/// bound. Popping a frame clears its slot immediately, releasing the payload
/// without retaining a consumed prefix or periodically copying the remaining queue.
private struct InstantMediaRingStorage<Element> {
  private var elements: ContiguousArray<Element?>
  private var head = 0
  private(set) var count = 0
  private let maximumCapacity: Int

  init(maximumCapacity: Int) {
    self.maximumCapacity = maximumCapacity
    self.elements = ContiguousArray(
      repeating: nil,
      count: min(maximumCapacity, 16)
    )
  }

  mutating func append(_ element: Element) {
    precondition(count < maximumCapacity)
    if count == elements.count {
      grow()
    }
    let index = (head + count) % elements.count
    elements[index] = element
    count += 1
  }

  mutating func popFirst() -> Element? {
    guard count > 0 else { return nil }
    let element = elements[head]
    elements[head] = nil
    head = (head + 1) % elements.count
    count -= 1
    if count == 0 {
      head = 0
    }
    return element
  }

  mutating func removeAll(releasingCapacity: Bool) {
    guard count > 0 || releasingCapacity else { return }
    if releasingCapacity {
      elements = ContiguousArray(
        repeating: nil,
        count: min(maximumCapacity, 16)
      )
    } else {
      for offset in 0..<count {
        elements[(head + offset) % elements.count] = nil
      }
    }
    head = 0
    count = 0
  }

  private mutating func grow() {
    let nextCapacity = min(maximumCapacity, max(1, elements.count * 2))
    precondition(nextCapacity > elements.count)
    var grown = ContiguousArray<Element?>(repeating: nil, count: nextCapacity)
    for offset in 0..<count {
      grown[offset] = elements[(head + offset) % elements.count]
    }
    elements = grown
    head = 0
  }
}

/// Byte- and frame-bounded asynchronous media channel.
///
/// The default policy suspends producers instead of accumulating an unbounded
/// array. Cancellation and finish release every continuation and retained frame.
public actor InstantMediaStreamBuffer<Frame: InstantMediaStreamFrame> {
  private let policy: InstantMediaStreamBufferPolicy
  private var storage: InstantMediaRingStorage<Frame>
  private var residentBytes = 0
  private var isClosed = false

  private var spaceWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private var elementWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private var metricsValue = InstantMediaStreamBufferMetrics()

  public init(policy: InstantMediaStreamBufferPolicy = .realtime()) throws {
    guard policy.maximumBytes > 0, policy.maximumFrames > 0 else {
      throw InstantMediaStreamBufferError.invalidPolicy
    }
    self.policy = policy
    self.storage = InstantMediaRingStorage(maximumCapacity: policy.maximumFrames)
  }

  public var metrics: InstantMediaStreamBufferMetrics {
    var metrics = metricsValue
    metrics.residentBytes = residentBytes
    metrics.residentFrames = count
    return metrics
  }

  public var count: Int { storage.count }
  public var bufferedByteCount: Int { residentBytes }

  public func send(_ frame: Frame) async throws {
    let frameBytes = frame.payload.count
    guard frameBytes <= policy.maximumBytes else {
      throw InstantMediaStreamBufferError.frameExceedsMaximum(
        actualBytes: frameBytes,
        maximumBytes: policy.maximumBytes
      )
    }

    while wouldOverflow(addingBytes: frameBytes) {
      guard !isClosed else { throw InstantMediaStreamBufferError.closed }
      switch policy.overflow {
      case .suspendProducer:
        metricsValue.suspendedProducerCount += 1
        try await waitForSpace()
      case .dropOldest:
        guard removeFirst() != nil else {
          throw InstantMediaStreamBufferError.overflow(
            residentBytes: residentBytes,
            residentFrames: count
          )
        }
        metricsValue.droppedFrames += 1
      case .fail:
        throw InstantMediaStreamBufferError.overflow(
          residentBytes: residentBytes,
          residentFrames: count
        )
      }
    }

    guard !isClosed else { throw InstantMediaStreamBufferError.closed }
    storage.append(frame)
    residentBytes += frameBytes
    metricsValue.totalEnqueuedFrames += 1
    metricsValue.peakResidentBytes = max(metricsValue.peakResidentBytes, residentBytes)
    metricsValue.peakResidentFrames = max(metricsValue.peakResidentFrames, count)
    resumeOneElementWaiter()
  }

  public func next() async throws -> Frame? {
    while count == 0 {
      if isClosed { return nil }
      try await waitForElement()
    }
    let frame = removeFirst()
    if frame != nil {
      metricsValue.totalDequeuedFrames += 1
      resumeOneSpaceWaiter()
    }
    return frame
  }

  public func finish() {
    guard !isClosed else { return }
    isClosed = true
    resumeElementWaiters()
    resumeSpaceWaiters(throwing: InstantMediaStreamBufferError.closed)
  }

  /// Close the channel and immediately release every retained media payload.
  public func cancel() {
    guard !isClosed || count > 0 else { return }
    isClosed = true
    storage.removeAll(releasingCapacity: true)
    residentBytes = 0
    resumeElementWaiters(throwing: CancellationError())
    resumeSpaceWaiters(throwing: CancellationError())
  }

  private func wouldOverflow(addingBytes: Int) -> Bool {
    residentBytes + addingBytes > policy.maximumBytes
      || count + 1 > policy.maximumFrames
  }

  @discardableResult
  private func removeFirst() -> Frame? {
    guard let frame = storage.popFirst() else { return nil }
    residentBytes -= frame.payload.count
    return frame
  }

  private func waitForSpace() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        spaceWaiters[id] = continuation
      }
    } onCancel: {
      Task { await self.cancelSpaceWaiter(id) }
    }
  }

  private func waitForElement() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        elementWaiters[id] = continuation
      }
    } onCancel: {
      Task { await self.cancelElementWaiter(id) }
    }
  }

  private func cancelSpaceWaiter(_ id: UUID) {
    spaceWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  private func cancelElementWaiter(_ id: UUID) {
    elementWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  /// Resume only one blocked producer for one newly available queue slot.
  /// Waking every producer creates an avoidable actor-hop stampede where all but
  /// one immediately suspend again under a bounded lossless policy.
  private func resumeOneSpaceWaiter() {
    guard let (id, waiter) = spaceWaiters.first else { return }
    spaceWaiters.removeValue(forKey: id)
    waiter.resume()
  }

  /// Resume only one consumer for one newly enqueued frame.
  private func resumeOneElementWaiter() {
    guard let (id, waiter) = elementWaiters.first else { return }
    elementWaiters.removeValue(forKey: id)
    waiter.resume()
  }

  private func resumeSpaceWaiters(throwing error: (any Error)? = nil) {
    let waiters = spaceWaiters.values
    spaceWaiters.removeAll(keepingCapacity: true)
    for waiter in waiters {
      if let error {
        waiter.resume(throwing: error)
      } else {
        waiter.resume()
      }
    }
  }

  private func resumeElementWaiters(throwing error: (any Error)? = nil) {
    let waiters = elementWaiters.values
    elementWaiters.removeAll(keepingCapacity: true)
    for waiter in waiters {
      if let error {
        waiter.resume(throwing: error)
      } else {
        waiter.resume()
      }
    }
  }
}
