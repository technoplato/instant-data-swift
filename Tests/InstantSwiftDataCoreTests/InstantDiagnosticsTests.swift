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
    #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

    diagnostics.record(
      .error,
      subsystem: "runtime",
      category: "query",
      event: "query.failed",
      message: "Written"
    )
    #expect(try readEntries(at: fileURL).map(\.message) == ["Written"])

    diagnostics.configure(InstantDiagnosticsConfiguration(fileURL: nil))
    diagnostics.record(
      .critical,
      subsystem: "runtime",
      category: "query",
      event: "query.failed-again",
      message: "Ignored after disabling"
    )
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

    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o600)
    #expect(diagnostics.status.fileURL == fileURL)
    #expect(diagnostics.status.sessionID == "private-session")
    #expect(diagnostics.status.lastWriteError == nil)
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

    let entry = try #require(readEntries(at: fileURL).first)
    #expect(entry.subsystem.count == 129)
    #expect(entry.message.count == 4_097)
    #expect(entry.metadata["large"]?.count == 4_097)
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
