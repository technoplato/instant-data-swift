// History
// 2026-10-31  #1497  Created. The delivery claim and the acknowledgement each fingerprinted a write's optimistic effect
//                    again from the body the save had just written: a sorted-keys JSON encoding of the transaction and
//                    its rollback and a SHA-256, about 1.3 ms an acknowledgement on a Mac mini for a transcript line. The
//                    store now keeps the fingerprint it computed for each body, keyed by the SHA-256 of the body's stored
//                    text, and computes it again only for bytes it has not fingerprinted.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantAcknowledgementDigestTests {
  /// A body an earlier process saved is fingerprinted from its stored bytes, once in the new process (#1497), and its
  /// writes are claimed and accepted as before: transcript segments, live lines and link attachments.
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

    let window = try await fixture.claimWindow()
    for mutation in window.mutations {
      let transactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: transactionID,
        claimToken: window.token
      )
    }

    let fingerprints = await fixture.runtime.persistence.optimisticEffectFingerprintCountForTesting()
    let pending = try await fixture.pendingCount()
    #expect(!window.mutations.isEmpty)
    #expect(fingerprints == window.mutations.count, "\(fingerprints) fingerprints for \(window.mutations.count) bodies")
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A body whose stored bytes changed after its save is fingerprinted again from them (#1497): the kept fingerprint
  /// names the bytes it was computed from, not the mutation id. The same write, encoded differently, is still claimed
  /// and accepted.
  @Test
  func aBodyChangedAfterItsSaveIsFingerprintedFromItsStoredBytes() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-changed-body",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    _ = try await fixture.writeSegments(1)
    let cacheURL = fixture.configuration.persistenceURL
    let changedID = try Self.reencodeFirstStoredBody(cacheURL: cacheURL)
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
    #expect(window.mutations.map(\.id).contains(changedID))
    #expect(afterClaim - beforeClaim == 1, "the claim fingerprinted \(afterClaim - beforeClaim) bodies")
    #expect(afterAcknowledgements - afterClaim == 0, "\(afterAcknowledgements - afterClaim) acknowledgement fingerprints")
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// Rewrites the oldest stored body with the same JSON in another encoding (sorted keys), through a second SQLite
  /// connection, and returns its mutation id.
  static func reencodeFirstStoredBody(cacheURL: URL) throws -> String {
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
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
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
