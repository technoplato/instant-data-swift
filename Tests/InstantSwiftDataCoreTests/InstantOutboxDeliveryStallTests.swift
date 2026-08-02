import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import IssueReporting
import Testing

/// Regression coverage for the 2026-08-01 Scribe field failure, reconstructed
/// from a device outbox that held 691 pending mutations and one `failed`
/// mutation whose stored message read:
///
///     Could not resolve 'recordingAttachments/analysisCaptureContextJSON'
///     from the attrs returned by init-ok.
///
/// The device kept recording, so local writes stayed durable, but nothing
/// reached the server for two days and the stored connection state ended at
/// `errored`. These tests pin the three behaviors that failure required.
@Suite(.serialized)
struct InstantOutboxDeliveryStallTests {
  /// A mutation naming an attribute the server never received must not stop
  /// the mutations queued behind it. Before the fix a schema-drifted write
  /// could hold an entire backlog indefinitely.
  @Test
  func undeliverableMutationDoesNotBlockLaterMutations() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_040_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-drift",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    // Queued first, so an ordered flush reaches it before the healthy writes.
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-stall-poison",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-outbox-stall-poison",
              attributeID: "todos/attributeTheServerNeverReceived",
              value: .string("drifted"),
              txID: "tx-outbox-stall-poison",
              txTime: createdAt
            )
          )
        ]
      ),
      createdAt: createdAt
    )

    for index in 0..<3 {
      let queuedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(index + 1))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-outbox-stall-healthy-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-outbox-stall-\(index)",
            text: "queued behind the drifted write",
            createdAt: queuedAt,
            transactionID: "tx-outbox-stall-healthy-\(index)"
          )
        ),
        createdAt: queuedAt
      )
    }

    // The quarantine is reported to the developer, which is the point: this
    // failure was previously invisible until a device database was inspected.
    try await withKnownIssue {
      _ = try await runtime.connect()
      try? await Task.sleep(nanoseconds: 300_000_000)
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("attributeTheServerNeverReceived")
    }

    let transactedEventIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      transactedEventIDs.contains("tx-outbox-stall-poison"),
      false,
      outboxStallSource
    )
    for index in 0..<3 {
      expectNoDifference(
        transactedEventIDs.contains("tx-outbox-stall-healthy-\(index)"),
        true,
        outboxStallSource
      )
    }
  }

  /// A backlog is flushed in bounded batches. The field failure sent every
  /// queued mutation in a single burst, which starved the session's own
  /// queries until they hit the 10s transport timeout and closed the
  /// connection, so the backlog could never shrink.
  @Test
  func deepBacklogIsFlushedInBoundedBatches() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_050_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-batching",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    let backlogCount = InstantRuntimeLiveSessionLimits.maximumMutationsPerFlush + 20
    for index in 0..<backlogCount {
      let queuedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-outbox-backlog-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-outbox-backlog-\(index)",
            text: "backlog \(index)",
            createdAt: queuedAt,
            transactionID: "tx-outbox-backlog-\(index)"
          )
        ),
        createdAt: queuedAt
      )
    }

    let sentBeforeConnect = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .count
    expectNoDifference(sentBeforeConnect, 0, outboxStallSource)

    _ = try await runtime.connect()
    // One flush pass, before any acknowledgement can arrive.
    let firstPass = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .count
    #expect(
      firstPass <= InstantRuntimeLiveSessionLimits.maximumMutationsPerFlush,
      "One flush pass must stay bounded; sent \(firstPass)"
    )
    #expect(firstPass > 0, "A bounded flush must still make progress")
  }
}

/// Mirrors the private tuning constants so the test fails loudly if they move.
enum InstantRuntimeLiveSessionLimits {
  static let maximumMutationsPerFlush = 50
  static let inFlightMutationTimeoutSeconds = 10
}

private let outboxStallSource = "Scribe field failure 2026-08-01: device outbox stall"

private func temporaryOutboxStallCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantOutboxDeliveryStallTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
