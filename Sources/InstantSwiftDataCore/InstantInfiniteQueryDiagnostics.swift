import Foundation

/// Structured diagnostics for live infinite-query paging decisions.
///
/// Events land in `InstantDiagnostics` (local JSONL and/or host handlers such as
/// Scribe's Tailnet WebSocket dual-write). Payload bodies and tokens are never
/// logged — only counts, booleans, and short fingerprints.
enum InstantInfiniteQueryDiagnostics {
  static let subsystem = "instant-swift-data-core"
  static let category = "infinite-query"

  static func record(
    _ level: InstantDiagnosticLevel = .info,
    event: String,
    message: String,
    metadata: [String: String] = [:],
    correlationID: String? = nil
  ) {
    InstantDiagnostics.shared.record(
      level,
      subsystem: subsystem,
      category: category,
      event: event,
      message: message,
      metadata: metadata,
      correlationID: correlationID
    )
  }

  static func fingerprint(_ value: String?, length: Int = 8) -> String {
    guard let value, !value.isEmpty else { return "none" }
    let normalized = value.lowercased()
    if normalized.count <= length { return normalized }
    return String(normalized.prefix(length))
  }

  static func authMetadata(_ session: InstantAuthSession?) -> [String: String] {
    guard let session else {
      return [
        "authPresent": "false",
        "authIsGuest": "unknown",
        "authUserFingerprint": "none",
      ]
    }
    return [
      "authPresent": "true",
      "authIsGuest": session.isGuest.description,
      "authUserFingerprint": fingerprint(session.userID),
      "authType": session.type?.rawValue ?? "unknown",
    ]
  }

  /// Owner-like attribute fingerprints from root rows (junk/auth scope signal).
  static func ownerSampleMetadata(
    from values: [InstantEntitySnapshot],
    sampleLimit: Int = 5
  ) -> [String: String] {
    var owners: [String] = []
    var seen = Set<String>()
    for snapshot in values {
      guard let owner = ownerRawValue(in: snapshot) else { continue }
      let print = fingerprint(owner)
      guard seen.insert(print).inserted else { continue }
      owners.append(print)
      if owners.count >= sampleLimit { break }
    }
    return [
      "ownerFingerprintCount": owners.count.description,
      "ownerFingerprintsSample": owners.isEmpty ? "none" : owners.joined(separator: ","),
    ]
  }

  static func cursorMetadata(_ pageInfo: InstantQueryPageInfo?) -> [String: String] {
    [
      "remoteHasNextPage": pageInfo.map { $0.hasNextPage.description } ?? "nil",
      "remoteHasPreviousPage": pageInfo.map { $0.hasPreviousPage.description } ?? "nil",
      "hasStartCursor": (pageInfo?.startCursor != nil).description,
      "hasEndCursor": (pageInfo?.endCursor != nil).description,
      "hasLiveTupleStart":
        ((pageInfo?.startCursor?.liveTuple?.isEmpty) == false).description,
      "hasLiveTupleEnd":
        ((pageInfo?.endCursor?.liveTuple?.isEmpty) == false).description,
      "startEntityFingerprint": fingerprint(pageInfo?.startCursor?.entityID),
      "endEntityFingerprint": fingerprint(pageInfo?.endCursor?.entityID),
    ]
  }

  private static func ownerRawValue(in snapshot: InstantEntitySnapshot) -> String? {
    let keys = ["ownerUserID", "owner", "userID", "userId", "createdBy"]
    for key in keys {
      guard let value = snapshot.values[key]?.first else { continue }
      switch value {
      case let .string(raw) where !raw.isEmpty:
        return raw
      case let .ref(raw) where !raw.isEmpty:
        return raw
      default:
        continue
      }
    }
    return nil
  }
}
