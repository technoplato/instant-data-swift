// History
// 2026-10-31  #1497  Created. The delivery claim and the acknowledgement each fingerprinted a write's optimistic effect
//                    again from the body the save had just written: a sorted-keys JSON encoding of the transaction and
//                    its rollback and a SHA-256, about 1.3 ms an acknowledgement on a Mac mini for a transcript line. The
//                    store now keeps the fingerprint it computed for each write, keyed by a hash of the fingerprint's
//                    inputs, and computes it again only for inputs it has not fingerprinted.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantAcknowledgementDigestTests {
  /// A body an earlier process saved is fingerprinted from its stored bytes once in the new process, by its claim, and
  /// its acknowledgement reuses that (#1497); its writes are claimed and accepted as before: transcript segments, live
  /// lines and link attachments.
  @Test
  func aBodySavedByAnEarlierProcessIsFingerprintedOnceFromItsStoredBytes() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-earlier-process",
      serverSegmentCount: 2,
      pendingSegmentCount: 0,
      scribeLinks: true,
      liveLines: true,
      attachments: true
    )
    _ = try await fixture.writeSegments(2)
    try await fixture.relaunch()
    let afterRelaunch = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    let window = try await fixture.claimWindow()
    let afterClaim = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()
    for mutation in window.mutations {
      let transactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: transactionID,
        claimToken: window.token
      )
    }
    let afterAcknowledgements = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    let pending = try await fixture.pendingCount()
    print(
      "#1497 earlier-process bodies: \(window.mutations.count) claimed; fingerprints: relaunch \(afterRelaunch), "
        + "claim \(afterClaim - afterRelaunch), acknowledgements \(afterAcknowledgements - afterClaim)"
    )
    #expect(!window.mutations.isEmpty)
    #expect(afterClaim - afterRelaunch == window.mutations.count)
    #expect(afterAcknowledgements - afterClaim == 0)
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A body whose content changed behind the store after its save is fingerprinted again, and the claim refuses it as
  /// before (#1497): the kept fingerprint stands for the inputs it was computed from, not for the mutation id.
  @Test
  func aBodyWhoseContentChangedIsFingerprintedAgainAndRefused() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-changed-content",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    _ = try await fixture.writeSegments(1)
    let changedID = try Self.rewriteFirstStoredBody(cacheURL: fixture.configuration.persistenceURL) { body in
      var transaction = try #require(body["transaction"] as? [String: Any])
      transaction["id"] = "changed-behind-the-store"
      body["transaction"] = transaction
    }
    let beforeClaim = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    var claimed: [PendingMutation] = []
    await withKnownIssue("A body whose receipt does not match its content is quarantined at the claim.") {
      claimed = try await fixture.claimWindow().mutations
    }
    let afterClaim = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    #expect(!claimed.map(\.id).contains(changedID))
    #expect(afterClaim - beforeClaim >= 1, "the claim reused a fingerprint for changed content")
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A body stored again in another encoding, with the same content, reuses the kept fingerprint (#1497): its inputs are
  /// the same, so its fingerprint is; its write is claimed and accepted.
  @Test
  func aBodyStoredInAnotherEncodingReusesTheKeptFingerprint() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-same-content",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    _ = try await fixture.writeSegments(1)
    let reencodedID = try Self.rewriteFirstStoredBody(cacheURL: fixture.configuration.persistenceURL) { _ in }
    let beforeClaim = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    let window = try await fixture.claimWindow()
    let afterClaim = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()
    for mutation in window.mutations {
      let transactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: transactionID,
        claimToken: window.token
      )
    }
    let afterAcknowledgements = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()

    let pending = try await fixture.pendingCount()
    #expect(window.mutations.map(\.id).contains(reencodedID))
    #expect(afterClaim - beforeClaim == 0, "the claim fingerprinted \(afterClaim - beforeClaim) bodies")
    #expect(afterAcknowledgements - afterClaim == 0, "\(afterAcknowledgements - afterClaim) acknowledgement fingerprints")
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// Rewrites the oldest stored body through a second SQLite connection, as `change` edits its JSON object, in another
  /// encoding (sorted keys, unescaped slashes), and returns its mutation id.
  static func rewriteFirstStoredBody(
    cacheURL: URL,
    _ change: (inout [String: Any]) throws -> Void
  ) throws -> String {
    var database: OpaquePointer?
    try #require(sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    var select: OpaquePointer?
    try #require(
      sqlite3_prepare_v2(
        database,
        """
        SELECT body.mutation_id, body.json FROM instant_outbox_bodies AS body
        JOIN instant_outbox AS outbox ON outbox.mutation_id = body.mutation_id
        ORDER BY outbox.created_at_ms, outbox.mutation_id LIMIT 1
        """,
        -1, &select, nil
      ) == SQLITE_OK
    )
    defer { sqlite3_finalize(select) }
    try #require(sqlite3_step(select) == SQLITE_ROW)
    let id = String(cString: sqlite3_column_text(select, 0))
    let json = String(cString: sqlite3_column_text(select, 1))
    var object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    try change(&object)
    let reencoded = String(
      decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
      as: UTF8.self
    )
    try #require(reencoded != json)

    var update: OpaquePointer?
    try #require(
      sqlite3_prepare_v2(database, "UPDATE instant_outbox_bodies SET json = ? WHERE mutation_id = ?", -1, &update, nil)
        == SQLITE_OK
    )
    defer { sqlite3_finalize(update) }
    sqlite3_bind_text(update, 1, reencoded, -1, transient)
    sqlite3_bind_text(update, 2, id, -1, transient)
    try #require(sqlite3_step(update) == SQLITE_DONE)
    try #require(sqlite3_changes(database) == 1)
    return id
  }
}
