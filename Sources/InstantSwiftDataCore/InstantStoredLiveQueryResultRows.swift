import Foundation
import SQLite3

// History:
// - 2026-10-31: added (#1426): a stored live-query result is read from its header and its ownership rows, joined to
//   the facts the store holds, on the writer's connection and on the read connection alike.

/// How a stored live-query result is read from its rows (#1426).
///
/// A stored result is its ownership rows (which facts it holds), its facts (as the store holds them) and a narrow
/// header in `instant_live_query_results` (the count of its rows, when the server last stated it, and its page info).
/// Every save writes exactly its diff to those rows, so every reader, in a running process or after a kill, reads the
/// same result. An owned fact reads with the stamp the store holds for it. A fact the store no longer holds with that
/// value (another result's refresh replaced it, or a local write did) keeps the value the server last stated for this
/// result, stamped ``unstoredFactTransactionID`` at time 0: its own stamp is not kept, and no stamp the store holds is
/// older.
enum InstantStoredLiveQueryResultRows {
  /// The header of the result whose `query_key` is bound first: its id, count, time and page info.
  static let headerSQL = """
    SELECT query_id, triple_count, updated_at_ms, page_info_json
    FROM instant_live_query_results
    WHERE query_key = ?
    LIMIT 1
    """

  /// The ownership rows of the result `queryID` names (an SQL expression), each joined to the fact the store holds for
  /// it, as `owned` and `fact`.
  static func ownedFacts(ofQueryID queryID: String) -> String {
    """
    FROM instant_live_query_triples AS owned
    LEFT JOIN instant_triples AS fact
      ON fact.entity_id = owned.entity_id
      AND fact.attribute_id = owned.attribute_id
      AND fact.value_json = owned.value_json
    WHERE owned.query_id = \(queryID)
    """
  }

  /// One owned fact's JSON text, as the fact table's `json` column computes it (#1121), with the stamp the store holds;
  /// a fact the store does not hold is stamped with `unstoredTransactionID` (an SQL expression) at time 0.
  static func factJSON(unstoredTransactionID: String) -> String {
    """
    '{"attributeID":' || json_quote(owned.attribute_id) || ',"entityID":' || json_quote(owned.entity_id)
      || ',"txID":' || json_quote(coalesce(fact.tx_id, \(unstoredTransactionID))) || ',"txTime":{"milliseconds":'
      || coalesce(fact.tx_time_ms, 0) || '},"value":' || owned.value_json || '}'
    """
  }

  /// The facts of the result whose `query_id` is bound first, in the columns ``InstantFactRowReader`` reads, in the
  /// ownership rows' order. The second binding stamps an owned fact the store does not hold, at time 0.
  static let factsSQL = """
    SELECT owned.entity_id, owned.attribute_id, owned.value_json,
      coalesce(fact.tx_id, ?2), coalesce(fact.tx_time_ms, 0)
    \(ownedFacts(ofQueryID: "?1"))
    """

  /// The bytes of the result whose `query_id` is bound first, as its JSON would take them: each fact's text and a comma.
  /// An open-time pass leaves a result over its bound unread, and drops it (#436); the bound was the size of the JSON a
  /// result was stored as until #1426, and it still is. The second binding is as in ``factsSQL``.
  static let byteCountSQL = """
    SELECT coalesce(sum(length(CAST(\(factJSON(unstoredTransactionID: "?2")) AS BLOB)) + 1), 0)
    \(ownedFacts(ofQueryID: "?1"))
    """

  /// The closed query's copy of the stored result whose `query_key` is bound first, as the result's JSON
  /// (``InstantPersistedLiveQueryResult``), built inside SQLite from its header and rows (#1006, #1426): a prune batch
  /// unloads under the operation gate, and a result read and encoded in Swift there held it for the `$files` list's
  /// 75,640 facts (#1129). The second binding stamps an owned fact the store does not hold.
  static let unloadedCopySQL = """
    INSERT OR REPLACE INTO instant_unloaded_live_query_results (query_key, triple_count, updated_at_ms, json)
    SELECT result.query_key, result.triple_count, result.updated_at_ms,
      json_object(
        'key', result.query_key,
        'pageInfo', json(result.page_info_json),
        'triples', (
          SELECT json_group_array(json(\(factJSON(unstoredTransactionID: "?2"))))
          \(ownedFacts(ofQueryID: "result.query_id"))
        ),
        'updatedAt', json_object('milliseconds', result.updated_at_ms)
      )
    FROM instant_live_query_results AS result
    WHERE result.query_key = ?1
    """

  /// The transaction an owned fact the store does not hold reads with, at time 0: the value is the one the server last
  /// stated for this result, and its own stamp is not kept, so any stamp the store holds is newer than it.
  static let unstoredFactTransactionID = "live-query-result-ownership"

  /// The bytes `triples` take as ``byteCountSQL`` counts them: each fact's text as the store keeps it, and a comma.
  static func byteCount(of triples: [InstantTriple], encoder: JSONEncoder) throws -> Int {
    try triples.reduce(0) { total, triple in
      try total + InstantStoredJSON.stored(triple, using: encoder).utf8.count + 1
    }
  }

  /// One stored result's header, as ``headerSQL`` reads it.
  struct Header {
    var queryID: Int64
    var tripleCount: Int
    var updatedAtMilliseconds: Int64
    var pageInfo: InstantQueryPageInfo?

    /// The header `statement` is on, a row of ``headerSQL``.
    init(row statement: OpaquePointer, decoder: JSONDecoder) throws {
      queryID = sqlite3_column_int64(statement, 0)
      tripleCount = Int(sqlite3_column_int64(statement, 1))
      updatedAtMilliseconds = sqlite3_column_int64(statement, 2)
      pageInfo = try sqlite3_column_text(statement, 3).map { text in
        try decoder.decode(
          InstantQueryPageInfo.self,
          from: Data(bytes: text, count: Int(sqlite3_column_bytes(statement, 3)))
        )
      }
    }
  }

  /// The result `key` names, from its header and the facts `statement` reads, a ``factsSQL`` statement bound to the
  /// header's id and stamps and not yet stepped.
  static func result(
    key: String,
    header: Header,
    facts statement: OpaquePointer,
    decoder: JSONDecoder
  ) throws -> InstantPersistedLiveQueryResult {
    var triples: [InstantTriple] = []
    triples.reserveCapacity(header.tripleCount)
    var reader = InstantFactRowReader(decoder: decoder)
    try reader.read(statement, into: &triples)
    return InstantPersistedLiveQueryResult(
      key: key,
      storedTriples: triples,
      pageInfo: header.pageInfo,
      updatedAt: InstantTimestamp(milliseconds: header.updatedAtMilliseconds)
    )
  }
}

extension InstantPersistedLiveQueryResult {
  /// A stored result from its rows, which hold each fact once (#1426): no identity to merge, only the stored order.
  init(
    key: String,
    storedTriples: [InstantTriple],
    pageInfo: InstantQueryPageInfo?,
    updatedAt: InstantTimestamp
  ) {
    self.key = key
    self.triples = storedTriples.sorted(by: Self.storedOrder)
    self.pageInfo = pageInfo
    self.updatedAt = updatedAt
  }
}
