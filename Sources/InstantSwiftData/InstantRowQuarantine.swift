import Foundation
import InstantSwiftDataCore
import IssueReporting

extension InstantEntityModel {
  /// Decodes query rows one at a time, leaving out any row that fails to decode.
  ///
  /// Instant stores every attribute as its own fact, so a local entity can lack an attribute its
  /// model requires: a narrower query loaded only some of its facts, or a pruning bug removed the
  /// rest. On 2026-09-27 one such section failed a recording's whole playback detail fetch (#278).
  /// The library's entity and collection reads (`query`, `subscribe`, `FetchAll`, `FetchOne` of an
  /// entity, `InstantFetchRequest`) decode this way, so a damaged row costs only itself. Each one is
  /// reported with `reportIssue` and recorded as a `query.row-decode-quarantined` diagnostic.
  /// `FetchOne` of a single selected field still fails with the decode error.
  ///
  /// ``decode(_:)`` still throws on the first failure, for callers that need every row or none.
  /// SQLiteData fails the whole fetch on a bad row (`QueryCursor._element`); SQLite's column
  /// constraints keep partial rows from existing there.
  ///
  /// ```swift
  /// let sections = Section.decodeQuarantiningFailures(emission.values)
  /// ```
  public static func decodeQuarantiningFailures(
    _ snapshots: [InstantEntitySnapshot],
    operation: String = "decode rows"
  ) -> [Self] {
    InstantRowQuarantine().decode(
      snapshots,
      namespace: instantNamespace,
      operation: operation,
      Self.init(snapshot:)
    )
  }
}

/// Leaves rows that fail to decode out of a result and reports each one once.
///
/// One instance lives as long as the read it serves (a query, a live subscription, a fetch
/// wrapper), so a live query that re-emits the same damaged row reports it once, not on every
/// emission.
// SAFETY: `lock` protects `reportedKeys`, the only mutable state.
final class InstantRowQuarantine: @unchecked Sendable {
  private struct Failure {
    var entityID: String
    var path: String?
    var reason: String

    init(entityID: String, error: any Error) {
      self.entityID = entityID
      if let error = error as? InstantError {
        path = error.path
        reason = error.message
      } else {
        path = nil
        reason = String(String(describing: error).prefix(300))
      }
    }
  }

  private static let maximumReportedKeys = 4_096
  private let lock = NSLock()
  private var reportedKeys: Set<String> = []

  func decode<Row>(
    _ snapshots: [InstantEntitySnapshot],
    namespace: String,
    operation: String,
    _ decodeRow: (InstantEntitySnapshot) throws -> Row
  ) -> [Row] {
    var rows: [Row] = []
    rows.reserveCapacity(snapshots.count)
    var failures: [Failure] = []
    for snapshot in snapshots {
      do {
        rows.append(try decodeRow(snapshot))
      } catch {
        failures.append(Failure(entityID: snapshot.id, error: error))
      }
    }
    if !failures.isEmpty {
      report(failures, namespace: namespace, operation: operation, rowCount: snapshots.count)
    }
    return rows
  }

  /// The roots that decode, each with its snapshot so its included children can decode next.
  func decodeRoots<Root: InstantEntityModel>(
    _ snapshots: [InstantEntitySnapshot],
    as _: Root.Type
  ) -> [(snapshot: InstantEntitySnapshot, root: Root)] {
    decode(snapshots, namespace: Root.instantNamespace, operation: "InstantFetchRequest") {
      snapshot in (snapshot, try Root(snapshot: snapshot))
    }
  }

  func decodeChildren<Child: InstantEntityModel>(
    of snapshot: InstantEntitySnapshot,
    named relationName: String,
    as _: Child.Type
  ) -> [Child] {
    decode(
      snapshot.includedEntitySnapshots(named: relationName),
      namespace: Child.instantNamespace,
      operation: "InstantFetchRequest \(relationName)",
      Child.init(snapshot:)
    )
  }

  private func report(
    _ failures: [Failure],
    namespace: String,
    operation: String,
    rowCount: Int
  ) {
    let newFailures = lock.withLock {
      if reportedKeys.count + failures.count > Self.maximumReportedKeys {
        reportedKeys.removeAll(keepingCapacity: true)
      }
      return failures.filter { failure in
        let key = [namespace, failure.entityID, failure.path ?? failure.reason]
          .joined(separator: "\u{1F}")
        return reportedKeys.insert(key).inserted
      }
    }
    guard let first = newFailures.first else { return }
    let count = newFailures.count
    let message = """
      Instant left \(count) \(namespace) row\(count == 1 ? "" : "s") out of a \(rowCount)-row \
      result (\(operation)) because \(count == 1 ? "it" : "they") failed to decode. First: \
      \(first.entityID): \(first.reason) The other rows loaded. Check the model against the \
      Instant schema; a row returns once its facts decode, for example after the server \
      delivers them again.
      """
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data",
      category: "query",
      event: "query.row-decode-quarantined",
      message: message,
      metadata: [
        "namespace": namespace,
        "operation": operation,
        "quarantinedCount": String(count),
        "rowCount": String(rowCount),
        "entityIDs": newFailures.prefix(5).map(\.entityID).joined(separator: ","),
        "path": first.path ?? "",
        "reason": first.reason,
      ]
    )
    reportIssue(message)
  }
}
