import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #570: a many-cardinality value is sorted once, not on every snapshot of its entity.
///
/// Build 88's CPU kill on Michael's iPhone (48 s of CPU in 55 s, against a limit of 80% over 60 s) spent 26% of its
/// samples in one sort: `materializedValue` ordered every many-cardinality slot with
/// `slot.keys.sorted { $0.comparableKey < $1.comparableKey }`, and `comparableKey` builds a new string on each call.
/// Scribe's recordings hold `segments` forward, so every snapshot of a recording sorted all its segment refs, and each
/// final line, which changes the recording, re-sorted the refs of every recording on the list's page. Upstream
/// `Reactor.js` (`getAsObject`) reads only blob attributes and never sorts link sets.
@Suite(.serialized)
struct InstantManyCardinalityOrderTests {
  // MARK: - The recordings list

  enum Recordings {
    static let namespace = "recordings"
    static let title = InstantAttribute(
      id: "recordings/title",
      namespace: namespace,
      name: "title",
      valueType: .string,
      isRequired: false
    )
    static let updatedAtMs = InstantAttribute(
      id: "recordings/updatedAtMs",
      namespace: namespace,
      name: "updatedAtMs",
      valueType: .number,
      isRequired: false,
      isIndexed: true
    )
    /// Held forward on the recording, as Scribe's schema holds `recordings.segments` (has many).
    static let segments = InstantAttribute(
      id: "recordings/segments",
      namespace: namespace,
      name: "segments",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "recordings/segments",
      reverseIdentity: "transcriptionSegments/recording",
      linkNamespace: "transcriptionSegments"
    )
    static let attributes = [title, updatedAtMs, segments]
    /// The list's largest page in phone-perf's device numbers, with Recording 194's segment count on every recording.
    static let recordingCount = 73
    static let refsPerRecording = 1_190

    /// The list as Scribe orders it: newest update first.
    static let plan = InstantQueryPlan(
      id: "recordings.list",
      namespace: namespace,
      order: InstantQueryOrder(updatedAtMs.name, .descending),
      limit: 100
    )

    static func recordingID(_ index: Int) -> String {
      "rec-\(String(format: "%03d", index))"
    }

    static func uuid(using rng: inout SplitMix64) -> String {
      let a = rng.next(), b = rng.next()
      let hex = String(format: "%016llx%016llx", a, b)
      let characters = Array(hex)
      return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        .map { String(characters[$0]) }
        .joined(separator: "-")
    }

    static func seedTriples(using rng: inout SplitMix64) -> [InstantTriple] {
      var triples: [InstantTriple] = []
      triples.reserveCapacity(recordingCount * (refsPerRecording + 2))
      for index in 0..<recordingCount {
        let id = recordingID(index)
        let time = InstantTimestamp(milliseconds: 1_000 + Int64(index))
        triples.append(
          InstantTriple(entityID: id, attributeID: title.id, value: .string("Recording \(index)"), txID: "seed-\(index)", txTime: time)
        )
        triples.append(
          InstantTriple(
            entityID: id,
            attributeID: updatedAtMs.id,
            value: .number(Double(10_000 + index)),
            txID: "seed-\(index)",
            txTime: time
          )
        )
        for _ in 0..<refsPerRecording {
          triples.append(
            InstantTriple(entityID: id, attributeID: segments.id, value: .ref(uuid(using: &rng)), txID: "seed-\(index)", txTime: time)
          )
        }
      }
      return triples
    }
  }

  /// A final line on one recording, as Scribe saves it: a new segment linked to the recording and the recording's
  /// `updatedAtMs` moved to now, so the list's sort key changes and its page is materialized again, not spliced
  /// (phone-perf's device log: 586 publishes, spliced 0 at the median). Only that recording's segment refs changed, so
  /// only they need sorting; 1.9.8 sorted the refs of every recording on the page, twice for the written one.
  @Test
  func aFinalLineOnOneRecordingSortsOnlyThatRecordingsSegments() async throws {
    var rng = SplitMix64(state: 0x570)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Recordings.attributes, triples: Recordings.seedTriples(using: &rng))
    )
    let pages = ObservedLists()
    let coldStarted = ContinuousClock.now
    try await pages.observe(Recordings.plan, in: store)
    let coldDuration = coldStarted.duration(to: .now)
    let first = try #require(await pages.last)
    #expect(first.values.count == Recordings.recordingCount)

    let writeCount = 10
    var sorts: [Int] = []
    var durations: [Duration] = []
    var rematerialized = 0
    var nextUpdatedAt = Double(20_000)
    for write in 0..<writeCount {
      let recording = Recordings.recordingID(Int.random(in: 0..<Recordings.recordingCount, using: &rng))
      let time = InstantTimestamp(milliseconds: 50_000 + Int64(write))
      nextUpdatedAt += 1
      let operations: [InstantTripleOperation] = [
        .insert(
          InstantTriple(
            entityID: recording,
            attributeID: Recordings.segments.id,
            value: .ref(Recordings.uuid(using: &rng)),
            txID: "final-\(write)",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: recording,
            attributeID: Recordings.updatedAtMs.id,
            value: .number(nextUpdatedAt),
            txID: "final-\(write)",
            txTime: time
          )
        ),
      ]
      let sortsBefore = await store.manyCardinalitySortCountForTesting()
      let started = ContinuousClock.now
      let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: "final-\(write)", operations: operations))
      let committed = await store.commitAndPublish(prepared)
      durations.append(started.duration(to: .now))
      sorts.append(await store.manyCardinalitySortCountForTesting() - sortsBefore)
      await pages.record(committed.result.emissions)
      rematerialized += await store.lastPublishMetrics.rematerializedObserverCount
      let page = try #require(await pages.last)
      #expect(page.values.first?.id == recording, "The written recording moved to the top of the list.")
    }

    let sortedDurations = durations.sorted()
    let median = sortedDurations[sortedDurations.count / 2]
    print(
      """
      many-value-order: \(Recordings.recordingCount) recordings x \(Recordings.refsPerRecording) refs: first \
      materialization \(Self.milliseconds(coldDuration)) ms; a final line's commit and publish, median of \
      \(writeCount): \(Self.milliseconds(median)) ms (max \(Self.milliseconds(sortedDurations.last ?? .zero)) ms); \
      many-value sorts per final \(sorts); pages materialized again \(rematerialized)
      """
    )
    #expect(rematerialized == writeCount, "Every final materialized the list's page again, as on the phone.")
    #expect(
      sorts.allSatisfy { $0 <= 2 },
      "A final sorted only the written recording's segment refs, not every recording's: \(sorts)"
    )
  }

  // MARK: - The order stays the same

  enum Things {
    static let namespace = "things"
    static let tags = InstantAttribute(
      id: "things/tags",
      namespace: namespace,
      name: "tags",
      valueType: .any,
      isRequired: false,
      cardinality: .many
    )
    static let plan = InstantQueryPlan(id: "things.all", namespace: namespace)
    static let strings = [
      "", " ", "a", "A", "b", "B", "Z", "zz", "é", "e\u{301}x", "\u{301}a", "😀", "10", "9", "ß", "ss", "ﬁ", "İ", "\u{0}",
    ]

    static func value(using rng: inout SplitMix64) -> InstantValue {
      switch Int.random(in: 0..<7, using: &rng) {
      case 0:
        return .bool(Bool.random(using: &rng))
      case 1:
        return .number(Double(Int.random(in: -40...40, using: &rng)) / 4)
      case 2:
        let base = strings.randomElement(using: &rng) ?? ""
        return .string(Bool.random(using: &rng) ? base : base + String(Int.random(in: 0...99, using: &rng)))
      case 3:
        return .date(Date(timeIntervalSince1970: Double(Int.random(in: 0...2_000_000_000, using: &rng)) / 1_000))
      case 4:
        if Bool.random(using: &rng) {
          return .json(.object(["k": .number(Double(Int.random(in: 0...9, using: &rng)))]))
        }
        return .json(.array([.string(strings.randomElement(using: &rng) ?? "")]))
      default:
        return .ref(Recordings.uuid(using: &rng))
      }
    }

    /// Values whose `comparableKey`s differ, so the order before #570 is the only order.
    static func distinctValues(count: Int, using rng: inout SplitMix64) -> [InstantValue] {
      var keys = Set<String>()
      var values: [InstantValue] = []
      while values.count < count {
        let candidate = value(using: &rng)
        if keys.insert(candidate.comparableKey).inserted {
          values.append(candidate)
        }
      }
      return values
    }
  }

  /// Every materialized many-value lists its slot's values in `comparableKey` order, as before #570: values of every
  /// case, slots small and large, unchanged since the last materialization or after gaining, losing or swapping a value
  /// (a swap keeps the slot's count).
  @Test
  func manyValuesKeepTheComparableKeyOrderAcrossWrites() async throws {
    for seed in UInt64(0)..<UInt64(6) {
      var rng = SplitMix64(state: seed &* 0x2545_F491_4F6C_DD1D &+ 570)
      var model: [String: [InstantValue]] = [:]
      var triples: [InstantTriple] = []
      for index in 0..<24 {
        let id = "thing-\(seed)-\(index)"
        let count = index % 3 == 0 ? Int.random(in: 1...6, using: &rng) : Int.random(in: 16...80, using: &rng)
        let values = Things.distinctValues(count: count, using: &rng)
        model[id] = values
        for value in values {
          triples.append(
            InstantTriple(
              entityID: id,
              attributeID: Things.tags.id,
              value: value,
              txID: "seed-\(seed)",
              txTime: InstantTimestamp(milliseconds: 1_000)
            )
          )
        }
      }
      let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: [Things.tags], triples: triples))
      for step in 0..<10 {
        // Twice: the second read finds every slot as the first left it.
        for read in 0..<2 {
          let page = await store.materializePage(Things.plan)
          for snapshot in page.values {
            let expected = model[snapshot.id].map { values in values.sorted { $0.comparableKey < $1.comparableKey } } ?? []
            let actual: [InstantValue]
            switch snapshot.values[Things.tags.name] {
            case let .many(values)?: actual = values
            case nil: actual = []
            case let .one(value)?: actual = [value]
            }
            if actual != expected {
              Issue.record(
                "Seed \(seed), step \(step), read \(read): \(snapshot.id)'s tags are out of comparableKey order.\n\(actual.map(\.comparableKey))\nexpected\n\(expected.map(\.comparableKey))"
              )
            }
          }
        }
        var operations: [InstantTripleOperation] = []
        let txTime = InstantTimestamp(milliseconds: 2_000 + Int64(step))
        let txID = "step-\(seed)-\(step)"
        for id in model.keys.sorted() {
          guard Int.random(in: 0..<3, using: &rng) == 0 else { continue }
          var values = model[id] ?? []
          let keys = Set(values.map(\.comparableKey))
          var fresh = Things.value(using: &rng)
          while keys.contains(fresh.comparableKey) {
            fresh = Things.value(using: &rng)
          }
          switch Int.random(in: 0..<3, using: &rng) {
          case 0 where !values.isEmpty:
            // A swap: the count stays the same.
            let removed = values.remove(at: Int.random(in: 0..<values.count, using: &rng))
            operations.append(
              .retract(InstantTriple(entityID: id, attributeID: Things.tags.id, value: removed, txID: txID, txTime: txTime))
            )
            values.append(fresh)
            operations.append(
              .insert(InstantTriple(entityID: id, attributeID: Things.tags.id, value: fresh, txID: txID, txTime: txTime))
            )
          case 1 where values.count > 1:
            let removed = values.remove(at: Int.random(in: 0..<values.count, using: &rng))
            operations.append(
              .retract(InstantTriple(entityID: id, attributeID: Things.tags.id, value: removed, txID: txID, txTime: txTime))
            )
          default:
            values.append(fresh)
            operations.append(
              .insert(InstantTriple(entityID: id, attributeID: Things.tags.id, value: fresh, txID: txID, txTime: txTime))
            )
          }
          model[id] = values
        }
        guard !operations.isEmpty else { continue }
        let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: txID, operations: operations))
        _ = await store.commitAndPublish(prepared)
      }
    }
  }

  /// The comparator orders every pair of values as their `comparableKey`s do, across all eight cases, so the order a
  /// slot materializes in is the one 1.9.8 produced (#570).
  @Test
  func theComparatorOrdersEveryPairAsTheirComparableKeysDo() {
    var rng = SplitMix64(state: 0x570B)
    var values: [InstantValue] = [.null, .bool(false), .bool(true), .number(-1), .number(9), .number(10), .number(0.25)]
    values += Things.strings.map(InstantValue.string)
    values += Things.strings.map(InstantValue.ref)
    values += [
      .date(Date(timeIntervalSince1970: 0)),
      .date(Date(timeIntervalSince1970: 1_700_000_000.5)),
      .json(.null),
      .json(.object(["k": .string("v")])),
      .lookupRef(InstantLookupRef(attributeID: "a", value: .string("x"))),
      .lookupRef(InstantLookupRef(attributeID: "b", value: .number(1))),
    ]
    for _ in 0..<60 {
      values.append(Things.value(using: &rng))
    }
    var mismatches: [String] = []
    for lhs in values {
      for rhs in values {
        let expected = lhs.comparableKey < rhs.comparableKey
        if InstantValue.precedesInComparableKeyOrder(lhs, rhs) != expected {
          mismatches.append("\(lhs.comparableKey) < \(rhs.comparableKey) should be \(expected)")
        }
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) pairs differ: \(mismatches.prefix(8))")
  }

  // MARK: - Helpers

  /// Keeps the list observed, as `InstantStorePageSkipTests.ObservedPages` does, and its newest emission.
  actor ObservedLists {
    private var streams: [AsyncStream<InstantQueryEmission>] = []
    private(set) var last: InstantQueryEmission?

    func observe(_ plan: InstantQueryPlan, in store: InstantStore) async throws {
      let stream = await store.observe(plan)
      var iterator = stream.makeAsyncIterator()
      last = try #require(await iterator.next())
      streams.append(stream)
    }

    func record(_ emissions: [InstantQueryEmission]) {
      if let emission = emissions.last(where: { $0.queryID == Recordings.plan.id }) {
        last = emission
      }
    }
  }

  struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  static func milliseconds(_ duration: Duration) -> String {
    let components = duration.components
    let value = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    return String(format: "%.1f", value)
  }
}
