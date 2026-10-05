import Foundation
@testable import InstantSwiftDataCore
import Testing

/// A row's interned snapshot holds every cardinality-one field the row stores (#577).
///
/// A write interns a snapshot of the fields it set and the `id` it synthesizes, so the next read of the row skips the
/// row's slots. When the row stores fields the write did not set, the snapshot would leave them out. The check counted
/// the row's stored slots against the fields the write set plus one `id` slot. A row stored without an `id` slot and
/// with one field the write did not set passed it, and every later read served the snapshot without that field: a
/// page filtered on the field dropped the row. #540's differential test found it (seed 15, step 29, dev-199): its rows
/// store no `id` slot.
@Suite
struct InstantInternedSnapshotCompletenessTests {
  enum Items {
    static let namespace = "items"
    static let group = InstantAttribute(
      id: "items/group",
      namespace: namespace,
      name: "group",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    )
    static let rank = InstantAttribute(
      id: "items/rank",
      namespace: namespace,
      name: "rank",
      valueType: .number,
      isRequired: false,
      isIndexed: true
    )
    static let note = InstantAttribute(
      id: "items/note",
      namespace: namespace,
      name: "note",
      valueType: .string,
      isRequired: false
    )
    static let primaryKey = InstantAttribute.primaryKey(namespace: namespace)
  }

  static func triple(_ entityID: String, _ attribute: InstantAttribute, _ value: InstantValue, tx: Int64) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attribute.id,
      value: value,
      txID: "tx-\(tx)",
      txTime: InstantTimestamp(milliseconds: 1_000 + tx)
    )
  }

  static func write(_ store: InstantStore, id: String, _ operations: [InstantTripleOperation]) async throws {
    let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: id, operations: operations))
    _ = await store.commitAndPublish(prepared)
  }

  static func groupC(_ store: InstantStore) async -> [String] {
    await store.materialize(
      InstantQueryPlan(
        id: "group-c",
        namespace: Items.namespace,
        filters: [.equals(field: Items.group.name, value: .string("c"))]
      )
    ).map(\.id).sorted()
  }

  static func rows(_ store: InstantStore) async -> [String: [String: InstantMaterializedValue]] {
    let rows = await store.materialize(InstantQueryPlan(id: "all", namespace: Items.namespace))
    return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.values) })
  }

  @Test
  func aWriteToOneFieldOfARowWithoutAnIDSlotKeepsItsOtherField() async throws {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [Items.group, Items.rank, Items.note],
        triples: [
          Self.triple("row-1", Items.group, .string("c"), tx: 1),
          Self.triple("row-1", Items.rank, .number(1), tx: 1),
          Self.triple("row-2", Items.group, .string("c"), tx: 2),
          Self.triple("row-2", Items.note, .string("kept"), tx: 2),
        ]
      )
    )
    #expect(await Self.groupC(store) == ["row-1", "row-2"])

    // Each write sets every stored field of its row but one, and neither row stores an id slot.
    try await Self.write(store, id: "rank", [.insert(Self.triple("row-1", Items.rank, .number(2), tx: 3))])
    try await Self.write(store, id: "note", [.insert(Self.triple("row-2", Items.note, .string("changed"), tx: 4))])

    #expect(await Self.groupC(store) == ["row-1", "row-2"])
    let rows = await Self.rows(store)
    #expect(rows["row-1"]?["group"] == .one(.string("c")))
    #expect(rows["row-1"]?["rank"] == .one(.number(2)))
    #expect(rows["row-2"]?["group"] == .one(.string("c")))
    #expect(rows["row-2"]?["note"] == .one(.string("changed")))
  }

  @Test
  func rowsWithoutAnIDSlotKeepTheirOtherFieldsWhenOneTransactionWritesThemInTurn() async throws {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [Items.group, Items.rank],
        triples: [
          Self.triple("row-1", Items.group, .string("c"), tx: 1),
          Self.triple("row-1", Items.rank, .number(1), tx: 1),
          Self.triple("row-2", Items.group, .string("c"), tx: 2),
          Self.triple("row-2", Items.rank, .number(1), tx: 2),
        ]
      )
    )
    // Row 1's snapshot is set aside when the write moves to row 2, then takes row 1's second write.
    try await Self.write(
      store,
      id: "ranks",
      [
        .insert(Self.triple("row-1", Items.rank, .number(2), tx: 3)),
        .insert(Self.triple("row-2", Items.rank, .number(3), tx: 3)),
        .insert(Self.triple("row-1", Items.rank, .number(4), tx: 3)),
      ]
    )

    #expect(await Self.groupC(store) == ["row-1", "row-2"])
    let rows = await Self.rows(store)
    #expect(rows["row-1"]?["group"] == .one(.string("c")))
    #expect(rows["row-1"]?["rank"] == .one(.number(4)))
    #expect(rows["row-2"]?["group"] == .one(.string("c")))
    #expect(rows["row-2"]?["rank"] == .one(.number(3)))
  }

  @Test
  func aWriteToEveryFieldOfARowWithAnIDSlotStillInternsTheRow() async throws {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [Items.primaryKey, Items.group, Items.rank],
        triples: [
          Self.triple("row-1", Items.primaryKey, .string("row-1"), tx: 1),
          Self.triple("row-1", Items.group, .string("c"), tx: 1),
          Self.triple("row-1", Items.rank, .number(1), tx: 1),
        ]
      )
    )
    let internedBefore = await store.internedCardinalityOneEntityCount()
    #expect(internedBefore == 0)

    try await Self.write(
      store,
      id: "fields",
      [
        .insert(Self.triple("row-1", Items.group, .string("d"), tx: 2)),
        .insert(Self.triple("row-1", Items.rank, .number(2), tx: 2)),
      ]
    )

    // The write set every field but the id, so its snapshot is complete and the next read uses it.
    let internedAfter = await store.internedCardinalityOneEntityCount()
    #expect(internedAfter == 1)
    let rows = await Self.rows(store)
    #expect(rows["row-1"] == ["id": .one(.string("row-1")), "group": .one(.string("d")), "rank": .one(.number(2))])
  }
}
