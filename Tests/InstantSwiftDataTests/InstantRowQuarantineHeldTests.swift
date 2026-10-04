import CustomDump
import Foundation
import InstantSwiftData
import Testing

/// #522: Scribe's media retry scan decodes the same rows every 5-7 s while a recording is live. Through the static
/// `decodeQuarantiningFailures`, a row that stayed damaged was reported on every pass. A quarantine the caller holds
/// reports it once.
@Suite(.serialized)
struct InstantRowQuarantineHeldTests {
  @Test
  func aHeldQuarantineReportsARowThatStaysDamagedOnceAcrossDecodes() throws {
    let reports = HeldQuarantineReports()
    let token = InstantDiagnostics.shared.addHandler { entry in reports.record(entry) }
    defer { InstantDiagnostics.shared.removeHandler(token) }
    let quarantine = InstantRowQuarantine()

    var passes: [[String]] = []
    withKnownIssue {
      for _ in 1...3 {
        passes.append(quarantine.decode(heldRows, as: HeldQuarantineRow.self, operation: "held scan").map(\.id.rawValue))
      }
    } matching: { issue in
      issue.description.contains("row-2")
    }

    expectNoDifference(passes, Array(repeating: ["row-1", "row-3"], count: 3))
    expectNoDifference(reports.entityIDs(), ["row-2"])
  }

  @Test
  func eachStaticDecodeReportsItsDamagedRows() throws {
    let reports = HeldQuarantineReports()
    let token = InstantDiagnostics.shared.addHandler { entry in reports.record(entry) }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    withKnownIssue {
      for _ in 1...2 {
        _ = HeldQuarantineRow.decodeQuarantiningFailures(heldRows, operation: "static scan")
      }
    } matching: { issue in
      issue.description.contains("row-2")
    }

    expectNoDifference(reports.entityIDs(), ["row-2", "row-2"])
  }
}

private let heldRows: [InstantEntitySnapshot] = [
  InstantEntitySnapshot(id: "row-1", namespace: HeldQuarantineRow.instantNamespace, values: ["title": .one(.string("one"))]),
  // The shape a field-limited query leaves: the entity without its title.
  InstantEntitySnapshot(id: "row-2", namespace: HeldQuarantineRow.instantNamespace, values: [:]),
  InstantEntitySnapshot(id: "row-3", namespace: HeldQuarantineRow.instantNamespace, values: ["title": .one(.string("three"))]),
]

private struct HeldQuarantineRow: Hashable, InstantEntityModel {
  static let instantNamespace = "heldQuarantineRows"
  static let instantAttributes: [InstantAttribute] = [
    .primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "heldQuarantineRows/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isRequired: true
    ),
  ]
  static let title = InstantAttributePath<HeldQuarantineRow, String>("title")

  var id: InstantID<HeldQuarantineRow>
  var title: String

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.value(Self.title, operation: "decode held quarantine row")
  }
}

/// The quarantine diagnostics of this suite's namespace only: other suites run beside it.
private final class HeldQuarantineReports: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: [String] = []

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.event == "query.row-decode-quarantined",
      entry.metadata["namespace"] == HeldQuarantineRow.instantNamespace
    else { return }
    lock.withLock { ids.append(entry.metadata["entityIDs"] ?? "") }
  }

  func entityIDs() -> [String] {
    lock.withLock { ids }
  }
}
