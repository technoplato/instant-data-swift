import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1148 (2026-10-25): every write, server apply and emission records diagnostics, and each entry's message and metadata
// were built before the floor decided to drop it: a debug entry shaped like a server apply's gate record cost its caller
// 18 allocations under Scribe's `.info` floor, and redacting a kept entry's 21 keys 41 more (Mac mini, release). An entry
// the floor drops should cost its caller nothing, and one it keeps should not make strings to redact its keys. Counted on
// the calling thread only.
//
// History:
// - 2026-10-25: #1148: the tests.
// - 2026-10-25: the dropped entry's bound holds in optimized builds only (a debug bundle counted 3, v1.9.41's check).

@Suite
struct InstantDiagnosticsCostTests {
  /// A debug entry under an `.info` floor builds neither its message nor its metadata.
  @Test("An entry below the floor builds nothing")
  func anEntryBelowTheFloorBuildsNothing() {
    let diagnostics = Self.diagnostics(floor: .info)
    let allocations = Self.allocations { index in
      diagnostics.record(
        .debug, subsystem: "instant-swift-data-core", category: "server-apply", event: "server-apply.operation-gate-held",
        message: "A server apply held the operation gate for \(index) ms across its plan and commit.",
        metadata: Self.metadata(index),
        correlationID: "1792893464257594"
      )
    }
    // The bound holds in optimized builds, where #1148 measured it: a debug bundle counted 3 (the 1.9.40 and 1.9.41
    // release checks).
    guard RealSizeBudget.isOptimized else { return }
    #expect(allocations == 0, "A dropped entry allocated \(allocations) times.")
  }

  /// A kept entry's redaction looks up each key without making a string of it.
  @Test("A kept entry's metadata is redacted without a string per key")
  func aKeptEntryIsRedactedWithoutAStringPerKey() {
    let diagnostics = Self.diagnostics(floor: .info)
    let metadata = Self.metadata(7)
    var withMetadata = 0
    var withoutMetadata = 0
    withMetadata = Self.allocations { _ in
      diagnostics.record(.notice, subsystem: "instant-swift-data-core", category: "mutation", event: "transaction.server-accepted", message: "Accepted.", metadata: metadata)
    }
    withoutMetadata = Self.allocations { _ in
      diagnostics.record(.notice, subsystem: "instant-swift-data-core", category: "mutation", event: "transaction.server-accepted", message: "Accepted.")
    }
    // The redacted copy of a 21-entry dictionary is one or two blocks; a string per key would be 21 or more.
    #expect(
      withMetadata - withoutMetadata <= 4,
      "21 metadata entries cost \(withMetadata - withoutMetadata) allocations more than none (\(withMetadata) against \(withoutMetadata))."
    )
  }

  /// Redaction still hides the values of keys that name a secret, however they are spelled.
  @Test func redactionStillHidesSecrets() throws {
    let seen = EntryLog()
    let diagnostics = InstantDiagnostics(configuration: InstantDiagnosticsConfiguration(fileURL: nil, minimumLevel: .info))
    let token = diagnostics.addHandler { entry in seen.append(entry) }
    defer { diagnostics.removeHandler(token) }
    diagnostics.record(
      .notice, subsystem: "s", category: "c", event: "e", message: "m",
      metadata: [
        "access_token": "a", "Authorization": "b", "refresh-Token": "c", "REGISTRATION_KEY": "d", "registrationKeys": "e",
        "registration\u{212A}ey": "f", "password1": "g", "pendingMutationCount": "3", "": "h",
      ]
    )
    let metadata = try #require(seen.first?.metadata)
    #expect(metadata["access_token"] == "<redacted>")
    #expect(metadata["Authorization"] == "<redacted>")
    #expect(metadata["refresh-Token"] == "<redacted>")
    #expect(metadata["REGISTRATION_KEY"] == "<redacted>")
    #expect(metadata["registrationKeys"] == "e")
    // A Kelvin sign lowercases to an ASCII k.
    #expect(metadata["registration\u{212A}ey"] == "<redacted>")
    #expect(metadata["password1"] == "<redacted>")
    #expect(metadata["pendingMutationCount"] == "3")
    #expect(metadata[""] == "h")
  }

  // MARK: - Helpers

  /// The entries a handler saw.
  final class EntryLog: @unchecked Sendable {
    // SAFETY: `lock` guards `entries`.
    private let lock = NSLock()
    private var entries: [InstantDiagnosticEntry] = []
    func append(_ entry: InstantDiagnosticEntry) { lock.withLock { entries.append(entry) } }
    var first: InstantDiagnosticEntry? { lock.withLock { entries.first } }
  }

  static func diagnostics(floor: InstantDiagnosticLevel) -> InstantDiagnostics {
    let diagnostics = InstantDiagnostics(configuration: InstantDiagnosticsConfiguration(fileURL: nil, minimumLevel: floor))
    diagnostics.addHandler { _ in }
    return diagnostics
  }

  /// A server apply's gate record's shape: 21 entries, most of them numbers made into strings.
  static func metadata(_ index: Int) -> [String: String] {
    var metadata: [String: String] = [
      "heldMilliseconds": String(index), "waiterCount": String(index % 3), "pendingMutationCount": String(index * 2),
      "catchUpReplayCount": String(index % 5), "catchUpBodyCount": String(index % 7), "operationCount": String(index * 16),
      "processedTransactionID": "1792893464257594", "planID": "server-apply-plan-\(index)",
    ]
    for phase in ["seed", "plan", "stage", "commit", "retractions", "publish", "prune", "translate", "hydrate", "reduce", "outbox", "results", "observers"] {
      metadata["\(phase)Milliseconds"] = String(index % 11)
    }
    return metadata
  }

  /// Allocations this thread makes per call of `body`.
  static func allocations(iterations: Int = 20, _ body: (Int) -> Void) -> Int {
    body(0)
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    for index in 1...iterations { body(index) }
    return RealSizeAllocations.stop().allocations / iterations
  }
}
