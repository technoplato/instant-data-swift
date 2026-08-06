import Foundation
import os

extension InstantDBLogger {
  /// Creates a diagnostics writer without opening a socket or materializing an Instant store.
  /// Connection and replay happen on a bounded utility task after the first event is queued.
  public static func webSocket(
    endpoint: URL,
    context: InstantDBLogContext,
    spoolURL: URL,
    token: String? = nil,
    batchSize: Int = 32,
    batchInterval: Duration = .milliseconds(100),
    limits: InstantDBLogSpoolLimits = .device,
    isEnabled: @escaping @Sendable () -> Bool = { true }
  ) -> Self {
    let transport = InstantDBLogWebSocketTransport(endpoint: endpoint, token: token)
    return webSocket(
      context: context,
      spool: InstantDBLogJSONLSpool(url: spoolURL, limits: limits),
      transport: transport,
      batchSize: batchSize,
      batchInterval: batchInterval,
      isEnabled: isEnabled
    )
  }

  static func webSocket(
    context: InstantDBLogContext,
    spool: InstantDBLogJSONLSpool,
    transport: InstantDBLogWebSocketTransport,
    batchSize: Int,
    batchInterval: Duration,
    isEnabled: @escaping @Sendable () -> Bool
  ) -> Self {
    let writer = InstantDBLogWebSocketWriter(
      context: context,
      spool: spool,
      transport: transport,
      batchSize: batchSize,
      batchInterval: batchInterval,
      isEnabled: isEnabled
    )
    let buffer = InstantDBLogEnqueueBuffer(
      capacity: InstantDBLogDeliveryLimits.maximumPendingEvents
    ) { event in
      await writer.append(event)
    }
    Task(priority: .utility) { await writer.replayIfNeeded() }
    return Self(
      append: { event in buffer.enqueue(event) },
      recent: { _, _ in [] },
      observeRecent: { _, _ in .finished },
      flush: {
        let sharedFence = InstantDBLogEnqueueBuffer.shared.currentFenceSequence()
        await InstantDBLogEnqueueBuffer.shared.wait(until: sharedFence)
        let fence = buffer.currentFenceSequence()
        await buffer.wait(until: fence)
        try await writer.flush()
      },
      setRemoteObservabilityEnabled: { isEnabled in
        await writer.remoteObservabilityChanged(isEnabled: isEnabled)
      },
      queueMetrics: { buffer.metrics() }
    )
  }
}

actor InstantDBLogWebSocketWriter {
  private let batchInterval: Duration
  private let batchSize: Int
  private let context: InstantDBLogContext
  private let isEnabled: @Sendable () -> Bool
  private let reportFailure: @Sendable (String) -> Void
  private let retryInterval: Duration
  private let spool: InstantDBLogJSONLSpool
  private let transport: InstantDBLogWebSocketTransport
  private var deliveryTask: Task<Void, Never>?
  private var isDelivering = false
  private var observedRemoteObservabilityEnabled: Bool?
  private var requiresRemoteOutboxPurge = false

  init(
    context: InstantDBLogContext,
    spool: InstantDBLogJSONLSpool,
    transport: InstantDBLogWebSocketTransport,
    batchSize: Int,
    batchInterval: Duration,
    retryInterval: Duration = .seconds(30),
    isEnabled: @escaping @Sendable () -> Bool,
    reportFailure: @escaping @Sendable (String) -> Void = { message in
      Logger(subsystem: "InstantDBLogger", category: "WebSocketWriter").error(
        "\(message, privacy: .public)"
      )
    }
  ) {
    self.batchInterval = batchInterval
    self.batchSize = max(1, batchSize)
    self.context = context
    self.isEnabled = isEnabled
    self.reportFailure = reportFailure
    self.retryInterval = retryInterval
    self.spool = spool
    self.transport = transport
  }

  func append(_ event: InstantDBLogEvent) async {
    guard await synchronizeEnabledState() else { return }
    let timestampMs = event.timestampMs ?? Date().timeIntervalSince1970 * 1_000
    let timestamp = Date(timeIntervalSince1970: timestampMs / 1_000)
    let entry = InstantDBLogEntry(
      id: UUID().uuidString.lowercased(),
      timestampMs: timestampMs,
      level: event.level,
      subsystem: context.subsystem,
      category: event.category,
      name: event.name,
      message: event.message,
      metadata: event.metadata,
      sessionID: context.sessionID,
      platform: context.platform,
      deviceName: context.deviceName,
      appVersion: context.appVersion,
      buildCommit: context.buildCommit,
      fileID: event.fileID,
      function: event.function,
      sourceLine: event.sourceLine,
      timestampLocal: Self.localTimestamp(
        timestamp,
        timeZoneIdentifier: context.timeZoneIdentifier
      ),
      projectName: context.projectName,
      buildBranch: context.buildBranch,
      buildIsDirty: context.buildIsDirty,
      contributingPaths: event.contributingPaths,
      issueReferences: event.issueReferences
    )
    let wireEvent = InstantDBLogWireEvent(
      entry: entry,
      isProtectedEvidence: event.isProtectedRemoteEvidence
    )
    do {
      var line = try JSONEncoder().encode(wireEvent)
      line.append(Character("\n").asciiValue!)
      try await spool.append(line: line)
    } catch {
      reportFailure("Could not append diagnostics outbox: \(error.localizedDescription)")
      return
    }
    scheduleDeliveryIfNeeded()
  }

  func replayIfNeeded() async {
    guard await synchronizeEnabledState() else { return }
    await scheduleReplayIfPresent()
  }

  func remoteObservabilityChanged(isEnabled: Bool) async {
    let previousValue = observedRemoteObservabilityEnabled
    observedRemoteObservabilityEnabled = isEnabled
    if !isEnabled {
      if previousValue != false {
        requiresRemoteOutboxPurge = true
      }
      await purgeRemoteOutboxIfNeeded()
      return
    }
    guard await purgeRemoteOutboxIfNeeded() else { return }
    if previousValue != true {
      await scheduleReplayIfPresent()
    }
  }

  func flush() async throws {
    guard await synchronizeEnabledState() else { return }
    let targetIDs = Set(try await spool.records().map(\.id))
    guard !targetIDs.isEmpty else { return }
    deliveryTask?.cancel()
    deliveryTask = nil
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while try await spool.containsAny(ids: targetIDs) {
      guard clock.now < deadline else { throw InstantDBLoggerError.deliveryTimedOut }
      if isDelivering {
        try await Task.sleep(for: .milliseconds(10))
      } else {
        do {
          try await deliverNextBatch()
        } catch {
          if clock.now >= deadline { throw InstantDBLoggerError.deliveryTimedOut }
          try await Task.sleep(for: .milliseconds(50))
        }
      }
    }
    scheduleDeliveryIfNeeded()
  }

  private func scheduleDeliveryIfNeeded(after delay: Duration? = nil) {
    guard deliveryTask == nil, !isDelivering else { return }
    let delay = delay ?? batchInterval
    deliveryTask = Task(priority: .utility) { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.deliveryWindowElapsed()
    }
  }

  private func deliveryWindowElapsed() async {
    deliveryTask = nil
    guard await synchronizeEnabledState() else { return }
    do {
      try await deliverNextBatch()
      let hasRecords = (try? await spool.statistics().rowCount) ?? 0 > 0
      if hasRecords { scheduleDeliveryIfNeeded() }
    } catch {
      // After the transport's bounded immediate reconnect cycle is exhausted, keep exactly one
      // slow retry scheduled so a quiet process cannot strand a nonempty enabled outbox.
      guard await synchronizeEnabledState() else { return }
      do {
        if try await spool.statistics().rowCount > 0 {
          scheduleDeliveryIfNeeded(after: retryInterval)
        }
      } catch {
        reportFailure(
          "Could not inspect the diagnostics outbox after delivery failed: "
            + error.localizedDescription
        )
      }
    }
  }

  private func deliverNextBatch() async throws {
    guard !isDelivering else { return }
    isDelivering = true
    defer { isDelivering = false }
    guard await synchronizeEnabledState() else { return }
    let records = try await spool.records(limit: batchSize)
    guard !records.isEmpty else { return }
    let events = try records.map {
      try JSONDecoder().decode(InstantDBLogWireEvent.self, from: $0.line)
    }
    try await spool.synchronize()
    let batch = InstantDBLogWireBatch(
      batchID: "diagnostics-\(events.first!.id)",
      events: events
    )
    let acknowledgedIDs = try await transport.send(batch)
    guard !acknowledgedIDs.isEmpty else {
      throw InstantDBLogWebSocketError.invalidAcknowledgement
    }
    try await spool.acknowledge(ids: acknowledgedIDs)
  }

  private func synchronizeEnabledState() async -> Bool {
    let enabled = isEnabled()
    let previousValue = observedRemoteObservabilityEnabled
    observedRemoteObservabilityEnabled = enabled
    if !enabled {
      if previousValue != false {
        requiresRemoteOutboxPurge = true
      }
      await purgeRemoteOutboxIfNeeded()
      return false
    }
    return await purgeRemoteOutboxIfNeeded()
  }

  @discardableResult
  private func purgeRemoteOutboxIfNeeded() async -> Bool {
    guard requiresRemoteOutboxPurge else { return true }
    deliveryTask?.cancel()
    deliveryTask = nil
    await transport.disconnect()
    do {
      let records = try await spool.records()
      try await spool.acknowledge(ids: Set(records.map(\.id)))
      requiresRemoteOutboxPurge = false
      return true
    } catch {
      reportFailure(
        "Could not purge the opted-out diagnostics outbox: \(error.localizedDescription)"
      )
      return false
    }
  }

  private func scheduleReplayIfPresent() async {
    do {
      if try await spool.statistics().rowCount > 0 {
        scheduleDeliveryIfNeeded()
      }
    } catch {
      reportFailure(
        "Could not inspect the diagnostics outbox for replay: \(error.localizedDescription)"
      )
    }
  }

  private static func localTimestamp(
    _ date: Date,
    timeZoneIdentifier: String
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    return formatter.string(from: date)
  }
}
