import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// These guard the two derived values that a write path consults per triple.
///
/// Both were recomputed from scratch on every read, which is invisible at test scale and quadratic
/// in production: on 2026-08-04 a Mac Scribe process sat at 99.5% CPU for 128 minutes applying
/// server transactions against a 343-attribute, 883k-triple store, and never returned to its event
/// loop — so a screen-stream session stayed `requested` forever and the app looked disconnected
/// when it was actually saturated.
@Suite(.serialized)
struct InstantStoreWriteScalingTests {

  // MARK: - AttributeStore.namespaces

  /// The set is maintained rather than rebuilt, so the thing that can now break is staleness.
  /// Every mutating entry point has to leave it equal to a fresh derivation.
  @Test
  func maintainedNamespacesMatchAFreshDerivationAfterEveryMutation() throws {
    func derived(_ store: AttributeStore) -> Set<String> {
      Set(store.attributes.map(\.namespace))
    }

    var store = AttributeStore(attributes: [
      InstantAttribute(id: "a/one", namespace: "a", name: "one", valueType: .string),
      InstantAttribute(id: "b/one", namespace: "b", name: "one", valueType: .string),
    ])
    expectNoDifference(store.namespaces, derived(store))
    expectNoDifference(store.namespaces, ["a", "b"])

    store.merge([InstantAttribute(id: "c/one", namespace: "c", name: "one", valueType: .string)])
    expectNoDifference(store.namespaces, derived(store))
    expectNoDifference(store.namespaces, ["a", "b", "c"])

    // Merging a namespace that is already present must not duplicate or drop it.
    store.merge([InstantAttribute(id: "a/two", namespace: "a", name: "two", valueType: .string)])
    expectNoDifference(store.namespaces, derived(store))
    expectNoDifference(store.namespaces, ["a", "b", "c"])

    // replaceAll narrows the set — a maintained set that only ever grows would fail here.
    store.replaceAll([InstantAttribute(id: "d/one", namespace: "d", name: "one", valueType: .string)])
    expectNoDifference(store.namespaces, derived(store))
    expectNoDifference(store.namespaces, ["d"])

    store.replaceAll([])
    expectNoDifference(store.namespaces, [])
  }

  /// Only `attributesByID` is encoded; everything derived is rebuilt on decode. The namespace set
  /// joins that group, so a round trip has to restore it.
  @Test
  func namespacesSurviveACodableRoundTrip() throws {
    let store = AttributeStore(attributes: [
      InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string),
      InstantAttribute(id: "debugLogs/message", namespace: "debugLogs", name: "message", valueType: .string),
    ])

    let decoded = try JSONDecoder().decode(
      AttributeStore.self,
      from: JSONEncoder().encode(store)
    )

    expectNoDifference(decoded.namespaces, store.namespaces)
    expectNoDifference(decoded.namespaces, ["recordings", "debugLogs"])
  }

  // MARK: - Write-path scaling

  /// `validateWriteValue` reads `namespaces` twice per triple. When that read rebuilt a Set from
  /// every attribute, a wide schema made each write proportional to the schema size, so applying a
  /// server transaction cost triples × attributes.
  ///
  /// The store here is deliberately shaped like the one that wedged: many attributes, many triples,
  /// one transaction touching a lot of rows.
  /// Asserts the *shape* rather than a wall-clock budget: the same transaction is applied against a
  /// narrow schema and a schema 8× wider, and the cost has to stay flat. A ratio survives being run
  /// on a slow machine, where an absolute bound would only measure the machine.
  ///
  /// Measured on 2026-08-04 at 2,000 writes, holding triples fixed and varying attributes:
  ///
  ///     attributes   rebuilt-per-read   maintained
  ///             50            0.142 s      0.026 s
  ///            400            0.934 s      0.024 s
  ///            800            1.825 s      0.025 s
  ///
  /// Rebuilt-per-read grows 7.1× from 100 to 800 attributes; maintained stays flat.
  @Test
  func applyingAWideTransactionDoesNotScaleWithTheAttributeCount() async throws {
    func applyTwoThousandWrites(againstAttributeCount attributeCount: Int) async throws -> Duration {
      let attributes = (0..<attributeCount).map { index in
        InstantAttribute(
          id: "ns\(index)/value",
          namespace: "ns\(index)",
          name: "value",
          valueType: .string
        )
      }
      let writeAttribute = try #require(attributes.first)
      let seed = (0..<5_000).map { index in
        InstantTriple(
          entityID: "row-\(index)",
          attributeID: writeAttribute.id,
          value: .string("seed-\(index)"),
          txID: "seed",
          txTime: InstantTimestamp(milliseconds: 1)
        )
      }
      let store = InstantStore(
        snapshot: InstantStoreSnapshot(attributes: attributes, triples: seed)
      )
      let operations = (0..<2_000).map { index in
        InstantTripleOperation.merge(
          InstantTriple(
            entityID: "row-\(index)",
            attributeID: writeAttribute.id,
            value: .string("updated-\(index)"),
            txID: "wide-tx",
            txTime: InstantTimestamp(milliseconds: 2)
          )
        )
      }

      let started = ContinuousClock.now
      let prepared = try await store.prepareCurrent(
        InstantStoreTransaction(id: "wide-tx", operations: operations)
      )
      let elapsed = ContinuousClock.now - started
      expectNoDifference(prepared.result.changedEntityIDs.count, 2_000)
      return elapsed
    }

    let narrow = try await applyTwoThousandWrites(againstAttributeCount: 100)
    let wide = try await applyTwoThousandWrites(againstAttributeCount: 800)

    // 8× the schema for the same writes. Flat is ~1.0×; rebuilding per read measured 7.1×.
    #expect(
      wide < narrow * 3,
      """
      Applying 2,000 writes cost \(narrow) against 100 attributes and \(wide) against 800 — \
      the write path is scaling with the size of the schema.

      This is the shape that wedged Mac Scribe on 2026-08-04: a per-triple read of a value \
      derived from the whole attribute table. Check that AttributeStore.namespaces is still a \
      maintained stored property and not a computed rebuild.
      """
    )
  }

  // MARK: - TripleIndexes.tripleCount

  /// `tripleCount` is read by `InstantStore.prepare`, which runs on every applied transaction and
  /// every terminal-failure removal. Deriving it walked every entity × attribute × value.
  ///
  /// Measured on a Mac Scribe process on 2026-08-04 with 883,388 triples: this single getter was
  /// 2,400 of 5,301 samples, reached through
  /// `failMutation → prepareTerminalFailureRemoval → InstantStore.prepare`.
  @Test
  func maintainedTripleCountMatchesAFreshWalkThroughEveryMutation() {
    let attributes = AttributeStore(attributes: [
      InstantAttribute(
        id: "ns/many",
        namespace: "ns",
        name: "many",
        valueType: .string,
        cardinality: .many
      ),
      InstantAttribute(
        id: "ns/one",
        namespace: "ns",
        name: "one",
        valueType: .string,
        cardinality: .one
      ),
    ])
    func walked(_ indexes: TripleIndexes) -> Int { indexes.triples.count }

    var indexes = TripleIndexes(attributes: attributes)
    expectNoDifference(indexes.tripleCount, 0)

    // Distinct values on a many-cardinality attribute accumulate.
    for index in 0..<5 {
      indexes.apply(
        .insert(
          InstantTriple(
            entityID: "row",
            attributeID: "ns/many",
            value: .string("v\(index)"),
            txID: "tx-\(index)",
            txTime: InstantTimestamp(milliseconds: Int64(index + 1))
          )
        ),
        attributes: attributes
      )
    }
    expectNoDifference(indexes.tripleCount, walked(indexes))
    expectNoDifference(indexes.tripleCount, 5)

    // Re-inserting an identical triple replaces rather than accumulates.
    indexes.apply(
      .insert(
        InstantTriple(
          entityID: "row",
          attributeID: "ns/many",
          value: .string("v0"),
          txID: "tx-again",
          txTime: InstantTimestamp(milliseconds: 99)
        )
      ),
      attributes: attributes
    )
    expectNoDifference(indexes.tripleCount, walked(indexes))
    expectNoDifference(indexes.tripleCount, 5)

    // A cardinality-one attribute evicts the previous value, so the count must not grow.
    for index in 0..<3 {
      indexes.apply(
        .insert(
          InstantTriple(
            entityID: "row",
            attributeID: "ns/one",
            value: .string("single-\(index)"),
            txID: "tx-one-\(index)",
            txTime: InstantTimestamp(milliseconds: Int64(200 + index))
          )
        ),
        attributes: attributes
      )
      expectNoDifference(indexes.tripleCount, walked(indexes))
    }
    expectNoDifference(indexes.tripleCount, 6)

    // Retraction decrements, and retracting something absent must not.
    indexes.apply(
      .retract(
        InstantTriple(
          entityID: "row",
          attributeID: "ns/many",
          value: .string("v3"),
          txID: "tx-retract",
          txTime: InstantTimestamp(milliseconds: 300)
        )
      ),
      attributes: attributes
    )
    expectNoDifference(indexes.tripleCount, walked(indexes))
    expectNoDifference(indexes.tripleCount, 5)

    indexes.apply(
      .retract(
        InstantTriple(
          entityID: "row",
          attributeID: "ns/many",
          value: .string("never-present"),
          txID: "tx-retract-missing",
          txTime: InstantTimestamp(milliseconds: 301)
        )
      ),
      attributes: attributes
    )
    expectNoDifference(indexes.tripleCount, walked(indexes))
    expectNoDifference(indexes.tripleCount, 5)

    // Deleting the entity drops everything it owned.
    indexes.apply(.deleteEntity("row"), attributes: attributes)
    expectNoDifference(indexes.tripleCount, walked(indexes))
    expectNoDifference(indexes.tripleCount, 0)
  }

  /// The count is derived, so it must be rebuilt on decode rather than trusted from the wire — and
  /// the encoded shape must not change, because persisted caches written by earlier builds have to
  /// keep decoding.
  @Test
  func tripleCountSurvivesACodableRoundTripWithoutChangingTheEncodedShape() throws {
    let attributes = AttributeStore(attributes: [
      InstantAttribute(id: "ns/value", namespace: "ns", name: "value", valueType: .string)
    ])
    let indexes = TripleIndexes(
      triples: (0..<20).map { index in
        InstantTriple(
          entityID: "row-\(index)",
          attributeID: "ns/value",
          value: .string("v\(index)"),
          txID: "tx-\(index)",
          txTime: InstantTimestamp(milliseconds: Int64(index + 1))
        )
      },
      attributes: attributes
    )
    expectNoDifference(indexes.tripleCount, 20)

    let encoded = try JSONEncoder().encode(indexes)
    let decoded = try JSONDecoder().decode(TripleIndexes.self, from: encoded)
    expectNoDifference(decoded.tripleCount, 20)
    expectNoDifference(decoded.tripleCount, decoded.triples.count)

    let keys = try #require(
      try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    ).keys.sorted()
    // Historical keys aev/eav/vae plus optional internedTxIDs for stamp wire.
    // aev is always empty on encode (memory floor); must remain present for decode.
    expectNoDifference(
      keys,
      ["aev", "eav", "internedTxIDs", "vae"],
      "A cached triple store written by an earlier build must still decode."
    )
  }

  /// `visibleWriteFilter` asks for the newest write time once per outbox write key, and the outbox
  /// is rescanned on every inbound server event. Allocating an array per key to take a max made
  /// that scan proportional to outbox depth × versions per key.
  @Test
  func newestWriteTimeReadsTheMaximumWithoutBuildingAnArray() {
    let versions = (1...50).map { version in
      InstantTriple(
        entityID: "row",
        attributeID: "ns/value",
        value: .string("v\(version)"),
        txID: "tx-\(version)",
        txTime: InstantTimestamp(milliseconds: version)
      )
    }
    let indexes = TripleIndexes(triples: versions)

    expectNoDifference(
      indexes.newestWriteTime(entityID: "row", attributeID: "ns/value"),
      InstantTimestamp(milliseconds: 50)
    )
    #expect(indexes.newestWriteTime(entityID: "missing", attributeID: "ns/value") == nil)
    #expect(indexes.newestWriteTime(entityID: "row", attributeID: "ns/missing") == nil)
  }

  // MARK: - TripleIndexes.newestTransactionTimeMilliseconds

  /// A full-rebase server apply stamps each pending write it replays one past the newest fact in the store, so it reads
  /// the newest once per write. Walking every fact for it made a frame that replays P writes over N facts cost P × N.
  ///
  /// Measured on a tablet on 2026-11-04 (library 1.9.64, #1748): iOS's CPU Monitor killed the app for "48 seconds cpu
  /// time over 60 seconds (81% cpu average), exceeding limit of 80% cpu over 60 seconds" while another app was
  /// frontmost in Split View, and 5 of the 6 samples were in this getter, under `applyLiveRefresh` →
  /// `performApplyServerTransaction`. After the relaunch the outbox it had built up drained at roughly one minute of
  /// writes an hour.
  ///
  /// The replay runs here as the server apply runs it: read the newest, write a fact one past it. The same 300 replays
  /// over a store 32× larger must cost about the same. Best of three, and an absolute floor for runs too short to time.
  @Test
  func replayingPendingWritesDoesNotWalkTheStoreForTheNewestTime() {
    let attributes = AttributeStore(attributes: [
      InstantAttribute(id: "ns/value", namespace: "ns", name: "value", valueType: .string)
    ])
    func replayThreeHundredWrites(overFacts factCount: Int) -> Duration {
      var indexes = TripleIndexes(
        triples: (0..<factCount).map { index in
          InstantTriple(
            entityID: "row-\(index)",
            attributeID: "ns/value",
            value: .string("seed-\(index)"),
            txID: "seed-\(index)",
            txTime: InstantTimestamp(milliseconds: Int64(index + 1))
          )
        },
        attributes: attributes
      )
      var best = Duration.seconds(3_600)
      for trial in 0..<3 {
        let started = ContinuousClock.now
        for write in 0..<300 {
          let newest = indexes.newestTransactionTimeMilliseconds ?? 0
          indexes.apply(
            .insert(
              InstantTriple(
                entityID: "pending-\(trial)-\(write)",
                attributeID: "ns/value",
                value: .string("pending-\(trial)-\(write)"),
                txID: "pending-\(trial)-\(write)",
                txTime: InstantTimestamp(milliseconds: newest + 1)
              )
            ),
            attributes: attributes
          )
        }
        best = min(best, ContinuousClock.now - started)
      }
      expectNoDifference(indexes.newestTransactionTimeMilliseconds, Int64(factCount + 900))
      return best
    }

    let small = replayThreeHundredWrites(overFacts: 2_000)
    let large = replayThreeHundredWrites(overFacts: 64_000)

    #expect(
      large < small * 4 || large < .milliseconds(20),
      """
      300 replayed writes cost \(small) over 2,000 facts and \(large) over 64,000: reading the store's newest \
      transaction time is walking the store.

      This is the shape that got the app killed on 2026-11-04 (#1748): the full-rebase server apply reads the newest \
      once per pending write it replays. Check that TripleIndexes still keeps its transaction times \
      (TransactionTimeCounts) and that newestTransactionTimeMilliseconds reads them.
      """
    )
  }

  /// The newest time is kept rather than walked, so what can now break is staleness: every write that adds, replaces
  /// or removes a fact has to leave it equal to a fresh walk, above all the ones that take the newest fact away.
  @Test
  func maintainedNewestTransactionTimeMatchesAFreshWalkThroughEveryMutation() throws {
    let attributes = AttributeStore(attributes: [
      InstantAttribute(id: "ns/many", namespace: "ns", name: "many", valueType: .string, cardinality: .many),
      InstantAttribute(id: "ns/one", namespace: "ns", name: "one", valueType: .string),
      InstantAttribute(id: "ns/doc", namespace: "ns", name: "doc", valueType: .json),
      InstantAttribute(
        id: "ns/link",
        namespace: "ns",
        name: "link",
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        linkNamespace: "ns"
      ),
    ])
    func walked(_ indexes: TripleIndexes) -> Int64? {
      indexes.triples.map(\.txTime.milliseconds).max()
    }
    func fact(
      _ entityID: String,
      _ attributeID: String,
      _ value: InstantValue,
      at milliseconds: Int64
    ) -> InstantTriple {
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txID: "tx-\(milliseconds)",
        txTime: InstantTimestamp(milliseconds: milliseconds)
      )
    }

    var indexes = TripleIndexes(attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, nil)

    // New cardinality-one facts and many-cardinality values.
    indexes.apply(.insert(fact("row-a", "ns/one", .string("a1"), at: 10)), attributes: attributes)
    indexes.apply(.insert(fact("row-b", "ns/one", .string("b1"), at: 20)), attributes: attributes)
    indexes.apply(.insert(fact("row-a", "ns/many", .string("m1"), at: 30)), attributes: attributes)
    indexes.apply(.insert(fact("row-a", "ns/many", .string("m2"), at: 40)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // An identical fact keeps the stamp it already has.
    indexes.apply(.insert(fact("row-a", "ns/many", .string("m2"), at: 99)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // A cardinality-one value replaced by a newer one, then retracted: the newest falls back one fact.
    indexes.apply(.insert(fact("row-a", "ns/one", .string("a2"), at: 50)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 50)
    indexes.apply(.retract(fact("row-a", "ns/one", .string("a2"), at: 51)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // The newest retracted when the next newest is far below it.
    indexes.apply(.insert(fact("row-c", "ns/one", .string("c1"), at: 1_000)), attributes: attributes)
    indexes.apply(.retract(fact("row-c", "ns/one", .string("c1"), at: 1_001)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // Retracting what the store does not hold changes nothing.
    indexes.apply(.retract(fact("row-a", "ns/many", .string("never"), at: 1_002)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // Replayed writes stamped one past each other, peeled newest first, as a full rebase does.
    for write in 1...5 {
      let newest = try #require(indexes.newestTransactionTimeMilliseconds)
      indexes.apply(
        .insert(fact("pending-\(write)", "ns/one", .string("p\(write)"), at: newest + 1)),
        attributes: attributes
      )
    }
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 45)
    for write in (1...5).reversed() {
      indexes.apply(
        .retract(fact("pending-\(write)", "ns/one", .string("p\(write)"), at: 0)),
        attributes: attributes
      )
      expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    }
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // A local write loses to a resident later value; the server's older value replaces it whatever the stamps (#431).
    indexes.apply(.insert(fact("row-d", "ns/one", .string("d-local"), at: 2_000)), attributes: attributes)
    indexes.apply(.insert(fact("row-d", "ns/one", .string("d-older"), at: 5)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 2_000)
    indexes.apply(
      .insert(fact("row-d", "ns/one", .string("d-server"), at: 5)),
      attributes: attributes,
      insertReplayPolicy: .preserveExactResident
    )
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 40)

    // A merge keeps the stamp of the value it merges into.
    indexes.apply(.insert(fact("row-e", "ns/doc", .json(.object(["a": .number(1)])), at: 3_000)), attributes: attributes)
    indexes.apply(.merge(fact("row-e", "ns/doc", .json(.object(["b": .number(2)])), at: 4_000)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 3_000)

    // Deleting an entity takes its facts and the links that point at it.
    indexes.apply(.insert(fact("row-g", "ns/one", .string("g"), at: 4_500)), attributes: attributes)
    indexes.apply(.insert(fact("row-f", "ns/link", .ref("row-g"), at: 5_000)), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 5_000)
    indexes.apply(.deleteEntity("row-g"), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 3_000)
    indexes.apply(.insert(fact("row-h", "ns/one", .string("h"), at: 5_500)), attributes: attributes)
    indexes.apply(.deleteEntityInNamespace(entityID: "row-h", namespace: "ns"), attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 3_000)

    // A deferred value read back to prepare a write, then removed again.
    indexes.hydrateDeferredValues([fact("row-i", "ns/one", .string("i"), at: 6_000)], attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 6_000)
    indexes.removeMarkedDeferredValues(attributes: attributes)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 3_000)

    // A schema change rebuilds the derived indexes: a many slot becomes one value.
    indexes.apply(.insert(fact("row-k", "ns/many", .string("k1"), at: 7_000)), attributes: attributes)
    indexes.apply(.insert(fact("row-k", "ns/many", .string("k2"), at: 6_500)), attributes: attributes)
    let narrowed = AttributeStore(
      attributes: attributes.attributes.map { attribute in
        var attribute = attribute
        if attribute.id == "ns/many" { attribute.cardinality = .one }
        return attribute
      }
    )
    indexes.reconcileDerivedIndexShapes(attributes: narrowed)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, walked(indexes))
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 7_000)

    // A copy prepared for a write is its own value.
    var prepared = indexes
    prepared.apply(.insert(fact("row-l", "ns/one", .string("l"), at: 9_000)), attributes: narrowed)
    expectNoDifference(prepared.newestTransactionTimeMilliseconds, 9_000)
    expectNoDifference(indexes.newestTransactionTimeMilliseconds, 7_000)

    // Decoded and freshly built indexes count their times again.
    let decoded = try JSONDecoder().decode(TripleIndexes.self, from: JSONEncoder().encode(prepared))
    expectNoDifference(decoded.newestTransactionTimeMilliseconds, walked(prepared))
    let rebuilt = TripleIndexes(triples: prepared.triples, attributes: narrowed)
    expectNoDifference(rebuilt.newestTransactionTimeMilliseconds, walked(prepared))

    // Emptied, the store has no newest time.
    for entityID in Set(prepared.triples.map(\.entityID)) {
      prepared.apply(.deleteEntity(entityID), attributes: narrowed)
    }
    expectNoDifference(prepared.tripleCount, 0)
    expectNoDifference(prepared.newestTransactionTimeMilliseconds, nil)
  }

  // MARK: - Overlay peel scaling (live server apply)

  /// Live server apply peels every durable optimistic overlay before rebasing. The wrong shape
  /// materializes `InstantStoreSnapshot.triples` and rebuilds `TripleIndexes` from the whole store
  /// once per pending mutation. The right shape is one `prepare(peelingOverlays:thenApplying:to:)`
  /// that keeps uniquely-owned indexes for the whole peel+apply.
  ///
  /// Upstream Instant (`store.transact` / `addTriple`) never rebuilds eav/aev/vae from a flat list
  /// on each live event — Swift was doing that on Mac Scribe and burning multi-core CPU inside
  /// `TripleIndexes.init` (sample 2026-08-06, issue #044).
  @Test
  func peelingOverlaysInOneStoreCallBeatsSnapshotRebuildPerMutation() async throws {
    let attribute = InstantAttribute(
      id: "ns/value",
      namespace: "ns",
      name: "value",
      valueType: .string
    )
    let tripleCount = 20_000
    let seed = (0..<tripleCount).map { index in
      InstantTriple(
        entityID: "row-\(index)",
        attributeID: attribute.id,
        value: .string("seed-\(index)"),
        txID: "seed",
        txTime: InstantTimestamp(milliseconds: 1)
      )
    }
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: [attribute], triples: seed)
    )
    let rollbacks = (0..<20).map { index in
      InstantStoreTransaction(
        id: "rollback-\(index)",
        operations: [
          .retract(
            InstantTriple(
              entityID: "row-\(index)",
              attributeID: attribute.id,
              value: .string("seed-\(index)"),
              txID: "rollback-\(index)",
              txTime: InstantTimestamp(milliseconds: 2)
            )
          )
        ]
      )
    }
    let serverTransaction = InstantStoreTransaction(
      id: "server-tx",
      operations: [
        .merge(
          InstantTriple(
            entityID: "row-100",
            attributeID: attribute.id,
            value: .string("from-server"),
            txID: "server-tx",
            txTime: InstantTimestamp(milliseconds: 3)
          )
        )
      ]
    )
    let snapshot = InstantStoreSnapshot(attributes: [attribute], triples: seed)

    let rebuiltStarted = ContinuousClock.now
    var rebuilt = snapshot
    for rollback in rollbacks {
      rebuilt = try await store.prepare(rollback, applyingTo: rebuilt).snapshot
    }
    let rebuiltPrepared = try await store.prepare(serverTransaction, applyingTo: rebuilt)
    let rebuiltElapsed = ContinuousClock.now - rebuiltStarted

    let singleCallStarted = ContinuousClock.now
    let singleCallPrepared = try await store.prepare(
      peelingOverlays: rollbacks,
      thenApplying: serverTransaction,
      to: snapshot
    )
    let singleCallElapsed = ContinuousClock.now - singleCallStarted

    expectNoDifference(
      rebuiltPrepared.indexes.tripleCount,
      singleCallPrepared.indexes.tripleCount
    )
    expectNoDifference(singleCallPrepared.indexes.tripleCount, tripleCount - 20)
    #expect(
      singleCallElapsed * 3 < rebuiltElapsed,
      """
      One-shot peel+apply (\(singleCallElapsed)) was not substantially faster than \
      snapshot-per-mutation (\(rebuiltElapsed)) on \(tripleCount) triples — live apply \
      still pays the rebuild cost that #044 hit.
      """
    )
  }

  /// Same final triples whether overlays are peeled via the expensive snapshot path or the
  /// single-call peel+apply path.
  @Test
  func peelingOverlaysInOneStoreCallMatchesSnapshotRebuild() async throws {
    let attribute = InstantAttribute(
      id: "ns/value",
      namespace: "ns",
      name: "value",
      valueType: .string
    )
    let seed = (0..<100).map { index in
      InstantTriple(
        entityID: "row-\(index)",
        attributeID: attribute.id,
        value: .string("seed-\(index)"),
        txID: "seed",
        txTime: InstantTimestamp(milliseconds: 1)
      )
    }
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: [attribute], triples: seed)
    )
    let rollbacks = (0..<5).map { index in
      InstantStoreTransaction(
        id: "rollback-\(index)",
        operations: [
          .retract(
            InstantTriple(
              entityID: "row-\(index)",
              attributeID: attribute.id,
              value: .string("seed-\(index)"),
              txID: "rollback-\(index)",
              txTime: InstantTimestamp(milliseconds: 2)
            )
          )
        ]
      )
    }
    let serverTransaction = InstantStoreTransaction(
      id: "server-tx",
      operations: [
        .merge(
          InstantTriple(
            entityID: "row-50",
            attributeID: attribute.id,
            value: .string("from-server"),
            txID: "server-tx",
            txTime: InstantTimestamp(milliseconds: 3)
          )
        )
      ]
    )
    let snapshot = InstantStoreSnapshot(attributes: [attribute], triples: seed)

    var rebuilt = snapshot
    for rollback in rollbacks {
      rebuilt = try await store.prepare(rollback, applyingTo: rebuilt).snapshot
    }
    let rebuiltPrepared = try await store.prepare(serverTransaction, applyingTo: rebuilt)
    let singleCallPrepared = try await store.prepare(
      peelingOverlays: rollbacks,
      thenApplying: serverTransaction,
      to: snapshot
    )

    expectNoDifference(
      rebuiltPrepared.indexes.tripleCount,
      singleCallPrepared.indexes.tripleCount
    )
    expectNoDifference(singleCallPrepared.indexes.tripleCount, 95)
    expectNoDifference(
      rebuiltPrepared.indexes.triples(entityID: "row-50").map(\.value),
      singleCallPrepared.indexes.triples(entityID: "row-50").map(\.value)
    )
  }
}
