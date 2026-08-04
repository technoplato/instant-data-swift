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
}
