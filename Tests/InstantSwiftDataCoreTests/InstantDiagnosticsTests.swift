import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite("Instant diagnostics")
struct InstantDiagnosticsTests {
  @Test("records structured JSON Lines with source and session context")
  func recordsStructuredEntry() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, minimumLevel: .trace),
      sessionID: "session-a",
      processID: 42,
      processName: "test-process"
    )

    diagnostics.record(
      .notice,
      subsystem: "runtime",
      category: "query",
      event: "query.completed",
      message: "Loaded lists",
      metadata: ["count": "2"],
      correlationID: "query-1",
      fileID: "Tests/Diagnostics.swift",
      line: 99,
      function: "test()"
    )

    diagnostics.flush()
    let entries = try readEntries(at: fileURL)
    #expect(entries.count == 1)
    #expect(entries[0].schemaVersion == 1)
    #expect(entries[0].sessionID == "session-a")
    #expect(entries[0].processID == 42)
    #expect(entries[0].processName == "test-process")
    #expect(entries[0].level == .notice)
    #expect(entries[0].subsystem == "runtime")
    #expect(entries[0].category == "query")
    #expect(entries[0].event == "query.completed")
    #expect(entries[0].message == "Loaded lists")
    #expect(entries[0].metadata == ["count": "2"])
    #expect(entries[0].correlationID == "query-1")
    #expect(entries[0].fileID == "Tests/Diagnostics.swift")
    #expect(entries[0].line == 99)
    #expect(entries[0].function == "test()")
  }

  @Test("records a keyed snapshot only when its metadata changes")
  func recordsKeyedSnapshotsOnlyOnChange() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, minimumLevel: .trace)
    )
    func snapshot(_ key: String, hasNextPage: Bool) {
      diagnostics.record(
        subsystem: "runtime",
        category: "infinite-query",
        event: "infinite.starter.snapshot",
        message: "Starter page.",
        metadata: ["hasNextPage": hasNextPage.description],
        changeKey: key
      )
    }

    snapshot("list", hasNextPage: false)
    snapshot("list", hasNextPage: false)
    snapshot("list", hasNextPage: false)
    snapshot("detail", hasNextPage: false)
    snapshot("list", hasNextPage: true)
    snapshot("list", hasNextPage: true)
    snapshot("list", hasNextPage: false)

    diagnostics.flush()
    let entries = try readEntries(at: fileURL)
    #expect(entries.map(\.metadata["hasNextPage"]) == ["false", "false", "true", "false"])
    #expect(entries.count == 4)
  }

  @Test("redacts credentials while retaining useful non-secret context")
  func redactsCredentials() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL)
    )

    diagnostics.record(
      subsystem: "auth",
      category: "session",
      event: "auth.signed-in",
      message: "Guest signed in",
      metadata: [
        "refreshToken": "do-not-write",
        "Authorization": "Bearer do-not-write",
        "codeVerifier": "do-not-write",
        "registrationKey": "query-with-private-filter-do-not-write",
        "errorCode": "networkFailed",
        "userID": "user-1",
      ],
      correlationID: "instant-query:private-plan-do-not-write"
    )

    diagnostics.flush()
    let entry = try #require(readEntries(at: fileURL).first)
    #expect(entry.metadata["refreshToken"] == "<redacted>")
    #expect(entry.metadata["Authorization"] == "<redacted>")
    #expect(entry.metadata["codeVerifier"] == "<redacted>")
    #expect(entry.metadata["registrationKey"] == "<redacted>")
    #expect(entry.metadata["errorCode"] == "networkFailed")
    #expect(entry.metadata["userID"] == "user-1")
    #expect(entry.correlationID == "instant-query:<redacted>")
    #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("do-not-write") == false)
  }

  @Test("respects the minimum level and disabled configuration")
  func respectsConfiguration() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, minimumLevel: .warning)
    )

    diagnostics.record(
      .debug,
      subsystem: "runtime",
      category: "query",
      event: "query.started",
      message: "Ignored"
    )
    diagnostics.flush()
    #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

    diagnostics.record(
      .error,
      subsystem: "runtime",
      category: "query",
      event: "query.failed",
      message: "Written"
    )
    diagnostics.flush()
    #expect(try readEntries(at: fileURL).map(\.message) == ["Written"])

    diagnostics.configure(InstantDiagnosticsConfiguration(fileURL: nil))
    diagnostics.record(
      .critical,
      subsystem: "runtime",
      category: "query",
      event: "query.failed-again",
      message: "Ignored after disabling"
    )
    diagnostics.flush()
    #expect(try readEntries(at: fileURL).map(\.message) == ["Written"])
  }

  @Test("multiple logger instances append complete decodable lines")
  func multipleWriters() async throws {
    let fileURL = temporaryLogURL()
    let first = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL),
      sessionID: "first"
    )
    let second = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL),
      sessionID: "second"
    )

    await withTaskGroup(of: Void.self) { group in
      for index in 0..<40 {
        group.addTask {
          let logger = index.isMultiple(of: 2) ? first : second
          logger.record(
            subsystem: "test",
            category: "concurrency",
            event: "writer.appended",
            message: "entry-\(index)"
          )
        }
      }
    }

    first.flush()
    second.flush()
    let entries = try readEntries(at: fileURL)
    #expect(entries.count == 40)
    #expect(Set(entries.map(\.sessionID)) == ["first", "second"])
    #expect(Set(entries.map(\.message)).count == 40)
  }

  @Test("environment configuration supports level, disable, and explicit paths")
  func environmentConfiguration() {
    let configured = InstantDiagnosticsConfiguration.environment([
      "INSTANT_SWIFT_DATA_LOG_PATH": "/tmp/instant-test.jsonl",
      "INSTANT_SWIFT_DATA_LOG_LEVEL": "warning",
    ])
    #expect(configured.fileURL?.path == "/tmp/instant-test.jsonl")
    #expect(configured.minimumLevel == .warning)

    #expect(
      InstantDiagnosticsConfiguration.environment([
        "INSTANT_SWIFT_DATA_LOG_PATH": "off"
      ]).fileURL == nil
    )
    #expect(InstantDiagnosticsConfiguration.environment([:]).fileURL == nil)
  }

  @Test("creates private log files and reports its active status")
  func privateFileAndStatus() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL),
      sessionID: "private-session"
    )
    diagnostics.record(
      subsystem: "test",
      category: "privacy",
      event: "privacy.checked",
      message: "Private"
    )

    diagnostics.flush()
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o600)
    #expect(diagnostics.status.fileURL == fileURL)
    #expect(diagnostics.status.sessionID == "private-session")
    #expect(diagnostics.status.lastWriteError == nil)
  }

  @Test("delivers entries to host handlers when no file path is configured")
  func deliversToHostHandlersWithoutFile() async throws {
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: nil, minimumLevel: .info)
    )
    let box = HandlerBox()
    let token = diagnostics.addHandler { entry in
      box.append(entry)
    }
    defer { diagnostics.removeHandler(token) }

    diagnostics.record(
      subsystem: "test",
      category: "handler",
      event: "handler.fired",
      message: "Host sink received the entry."
    )
    #expect(box.entries.count == 1)
    #expect(box.entries[0].event == "handler.fired")
    #expect(box.entries[0].category == "handler")
  }

  @Test("bounds oversized fields while keeping each record decodable")
  func boundsOversizedFields() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL)
    )
    diagnostics.record(
      subsystem: String(repeating: "s", count: 500),
      category: "bounds",
      event: "bounds.checked",
      message: String(repeating: "m", count: 10_000),
      metadata: ["large": String(repeating: "v", count: 10_000)]
    )

    diagnostics.flush()
    let entry = try #require(readEntries(at: fileURL).first)
    #expect(entry.subsystem.count == 129)
    #expect(entry.message.count == 4_097)
    #expect(entry.metadata["large"]?.count == 4_097)
  }

  @Test("keeps the file under its limit with one previous file")
  func rotatesAtTheLimit() throws {
    let fileURL = temporaryLogURL()
    let previousURL = InstantDiagnostics.previousLogFileURL(for: fileURL)
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, maximumFileBytes: 4_096)
    )

    for index in 0..<100 {
      diagnostics.record(
        subsystem: "test",
        category: "rotation",
        event: "row.\(index)",
        message: String(repeating: "x", count: 100)
      )
    }

    diagnostics.flush()
    let current = try readEntries(at: fileURL)
    let previous = try readEntries(at: previousURL)
    #expect(try fileSize(fileURL) <= 4_096)
    #expect(try fileSize(previousURL) <= 4_096)
    #expect(previousURL.lastPathComponent.hasSuffix(".previous.jsonl"))
    // Newest rows survive in order across the two files; older rotations were replaced.
    let events = (previous + current).map(\.event)
    #expect(events.last == "row.99")
    #expect(events == (100 - events.count..<100).map { "row.\($0)" })
    #expect(diagnostics.status.lastWriteError == nil)
  }

  @Test("grows without limit only when asked")
  func unlimitedWhenNil() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, maximumFileBytes: nil)
    )
    for index in 0..<50 {
      diagnostics.record(
        subsystem: "test", category: "rotation", event: "row.\(index)",
        message: String(repeating: "x", count: 100)
      )
    }
    diagnostics.flush()
    #expect(try readEntries(at: fileURL).count == 50)
    #expect(!FileManager.default.fileExists(atPath: InstantDiagnostics.previousLogFileURL(for: fileURL).path))
    #expect(InstantDiagnosticsConfiguration(fileURL: fileURL).maximumFileBytes == 16 * 1_024 * 1_024)
    #expect(
      InstantDiagnosticsConfiguration.environment([
        "INSTANT_SWIFT_DATA_LOG_PATH": fileURL.path, "INSTANT_SWIFT_DATA_LOG_MAX_BYTES": "0",
      ]).maximumFileBytes == nil
    )
  }

  /// Threads that opened the file before another rotated it must reopen, not rotate again: a
  /// second rotation from the stale file would move the fresh file over the previous one.
  @Test("concurrent writers across rotations write only whole rows and lose none they should keep")
  func concurrentRotation() async throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, maximumFileBytes: 64 * 1_024)
    )
    await withTaskGroup(of: Void.self) { group in
      for writer in 0..<8 {
        group.addTask {
          for index in 0..<150 {
            diagnostics.record(
              subsystem: "test", category: "rotation", event: "w\(writer).\(index)",
              message: String(repeating: "x", count: 120)
            )
          }
        }
      }
    }

    diagnostics.flush()
    let current = try readEntries(at: fileURL)
    let previous = try readEntries(at: InstantDiagnostics.previousLogFileURL(for: fileURL))
    #expect(try fileSize(fileURL) <= 64 * 1_024)
    #expect(diagnostics.status.lastWriteError == nil)
    // The two files together hold at least one full file of the newest rows.
    let rowBytes = try fileSize(fileURL) / max(1, current.count)
    #expect(current.count + previous.count >= (64 * 1_024 / rowBytes) - 1)
    #expect(Set((current + previous).map(\.event)).count == current.count + previous.count)
  }

  /// #473 (1.9.6): every line was fsynced, behind one process-wide file lock, so a burst of lines cost a burst of
  /// fsyncs on a hot, busy device. Lines are batched, under one open and lock per batch, and fsynced at most once a
  /// second, or at `flush()`.
  @Test("a burst of lines costs a few fsyncs, not one per line")
  func burstsAreBatched() throws {
    let fileURL = temporaryLogURL()
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fileURL, maximumFileBytes: nil)
    )
    for index in 0..<200 {
      diagnostics.record(
        subsystem: "test", category: "batching", event: "row.\(index)",
        message: String(repeating: "x", count: 100)
      )
    }
    diagnostics.flush()
    let counts = diagnostics.fileWriteCountsForTesting
    #expect(try readEntries(at: fileURL).map(\.event) == (0..<200).map { "row.\($0)" })
    #expect(counts.syncs <= 3, "\(counts.syncs) fsyncs for 200 lines")
  }

  private func fileSize(_ url: URL) throws -> Int {
    try (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
  }

  private func temporaryLogURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-diagnostics-tests")
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("jsonl")
  }

  private func readEntries(at fileURL: URL) throws -> [InstantDiagnosticEntry] {
    try String(contentsOf: fileURL, encoding: .utf8)
      .split(separator: "\n")
      .map { try JSONDecoder().decode(InstantDiagnosticEntry.self, from: Data($0.utf8)) }
  }
}

private final class HandlerBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InstantDiagnosticEntry] = []

  var entries: [InstantDiagnosticEntry] {
    lock.withLock { storage }
  }

  func append(_ entry: InstantDiagnosticEntry) {
    lock.withLock { storage.append(entry) }
  }
}
