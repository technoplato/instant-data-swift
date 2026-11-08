import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// ADR 0015 L3: a count of an include's children per row, counted in the store from the children the query brings
/// down (Instant answers aggregates for admin queries only), and rows grouped into sections once per emission.
@Suite(.serialized)
struct InstantCountedIncludeTests {
  /// A counted include goes up without its bound, so every child comes down and the stored result keeps every child a
  /// relaunch counts; its fields widen to what its counts read. A count-only include asks for its children's ids and
  /// counted fields alone.
  @Test
  func aCountedIncludeGoesOnTheWireWholeAndNarrow() throws {
    var previews = InstantQueryIncludePlan(
      id: "pictures",
      namespace: Self.pictures,
      order: InstantQueryOrder("capturedAtMs", .descending),
      limit: 12,
      selectedFields: ["capturedAtMs", "id"]
    )
    previews.counts = [InstantQueryIncludeCount(filters: [.equals(field: "kind", value: .string("image"))])]
    var threads = InstantQueryIncludePlan(
      id: "threads",
      namespace: "bench_threads",
      filters: [.equals(field: "status", value: .string("working"))],
      selectedFields: ["id", "status"]
    )
    threads.counts = [InstantQueryIncludeCount(filters: [.equals(field: "status", value: .string("working"))])]
    threads.countOnly = true
    let plan = InstantQueryPlan(
      id: "recordings",
      namespace: Self.recordings,
      includes: [
        InstantQueryInclude("pictures", direction: .reverse, query: previews),
        InstantQueryInclude("threads", direction: .reverse, query: threads),
      ]
    )

    let encoded = try InstantLiveQueryEncoder.encode(plan)

    guard
      case let .object(root) = encoded,
      case let .object(recordings)? = root[Self.recordings],
      case let .object(pictureForm)? = recordings["pictures"],
      case let .object(pictureOptions)? = pictureForm["$"],
      case let .object(threadForm)? = recordings["threads"],
      case let .object(threadOptions)? = threadForm["$"]
    else {
      Issue.record("Unexpected live query shape: \(encoded)")
      return
    }
    expectNoDifference(pictureOptions["limit"], nil)
    expectNoDifference(pictureOptions["fields"], .array([.string("capturedAtMs"), .string("id"), .string("kind")]))
    expectNoDifference(pictureOptions["order"], .object(["capturedAtMs": .string("desc")]))
    expectNoDifference(threadOptions["fields"], .array([.string("id"), .string("status")]))
    #expect(threadOptions["where"] != nil)
  }

  /// A plan stored before counts existed decodes with none, and a plan without counts keeps the key it had.
  @Test
  func aPlanStoredBeforeCountsDecodesWithNone() throws {
    let stored = Data(
      #"{"id":"posts","namespace":"posts","filters":[],"limit":2,"selectedFields":["title"]}"#.utf8
    )
    let plan = try JSONDecoder().decode(InstantQueryIncludePlan.self, from: stored)

    expectNoDifference(plan.counts, nil)
    #expect(!plan.isCountOnly)
    expectNoDifference(
      plan,
      InstantQueryIncludePlan(id: "posts", namespace: "posts", limit: 2, selectedFields: ["title"])
    )
    let withoutCounts = InstantQueryPlan(
      id: "users",
      namespace: "users",
      includes: [InstantQueryInclude("posts", direction: .reverse, query: plan)]
    )
    var counted = plan
    counted.counts = [InstantQueryIncludeCount()]
    let withCounts = InstantQueryPlan(
      id: "users",
      namespace: "users",
      includes: [InstantQueryInclude("posts", direction: .reverse, query: counted)]
    )
    #expect(withoutCounts.cacheKey != withCounts.cacheKey)
    #expect(!withoutCounts.cacheKey.isEmpty)
  }

  /// The store counts each row's children, before the include's window, and links no rows for a count-only include.
  @Test
  func theStoreCountsEachRowsChildrenBeforeTheWindow() throws {
    var (indexes, attributes) = Self.fixture(recordings: 3, picturesPerRecording: 5)
    let all = InstantQueryIncludeCount()
    let images = InstantQueryIncludeCount(filters: [.equals(field: "kind", value: .string("image"))])
    var window = InstantQueryIncludePlan(
      id: "pictures",
      namespace: Self.pictures,
      order: InstantQueryOrder("capturedAtMs", .descending),
      limit: 2
    )
    window.counts = [all, images]
    let windowed = indexes.materialize(
      InstantQueryPlan(
        id: "windowed",
        namespace: Self.recordings,
        order: InstantQueryOrder("startedAtMs"),
        includes: [InstantQueryInclude("pictures", direction: .reverse, query: window)]
      ),
      attributes: attributes
    )

    expectNoDifference(windowed.map { $0.links?["pictures"]?.count }, [2, 2, 2])
    expectNoDifference(
      windowed.map { $0.counts?[all.snapshotKey(relation: "pictures")] },
      [5, 5, 5]
    )
    // Kinds cycle image, screen, audio: pictures 0 and 3 of each recording are images.
    expectNoDifference(
      windowed.map { $0.counts?[images.snapshotKey(relation: "pictures")] },
      [2, 2, 2]
    )

    var countOnly = InstantQueryIncludePlan(id: "pictures", namespace: Self.pictures, selectedFields: ["id"])
    countOnly.counts = [all]
    countOnly.countOnly = true
    let counted = indexes.materialize(
      InstantQueryPlan(
        id: "counted",
        namespace: Self.recordings,
        includes: [InstantQueryInclude("pictures", direction: .reverse, query: countOnly)]
      ),
      attributes: attributes
    )
    expectNoDifference(counted.map { $0.links?["pictures"] }, [nil, nil, nil])
    expectNoDifference(counted.map { $0.counts?[all.snapshotKey(relation: "pictures")] }, [5, 5, 5])
  }

  /// A row's counts are part of what its answer shows, so a changed count rewrites the query's cached row; a row without
  /// counts digests as it did before counts existed.
  @Test
  func aRowsCountsArePartOfItsAnswersDigest() {
    func digest(_ counts: [String: Int]?) -> String {
      InstantQueryAnswerDigest(
        InstantQueryEmission(
          queryID: "recordings",
          sequence: 1,
          values: [
            InstantEntitySnapshot(
              id: "recording-1",
              namespace: Self.recordings,
              values: [:],
              links: nil,
              counts: counts
            )
          ]
        )
      ).hexValue
    }

    #expect(digest(["pictures": 1]) != digest(["pictures": 2]))
    #expect(digest(["pictures": 0]) != digest(nil))
    expectNoDifference(
      digest(nil),
      InstantQueryAnswerDigest(
        InstantQueryEmission(
          queryID: "recordings",
          sequence: 1,
          values: [InstantEntitySnapshot(id: "recording-1", namespace: Self.recordings, values: [:])]
        )
      ).hexValue
    )
  }

  /// Sections keep the order of their first rows and each row's place in its section.
  @Test
  func sectionsGroupInFirstAppearanceOrder() {
    let sections = InstantResultsSectionCollection(grouping: [3, 1, 4, 1, 5, 9, 2, 6], by: { $0 % 3 })

    expectNoDifference(sections.sectionNames, [0, 1, 2])
    expectNoDifference(sections.map { Array($0) }, [[3, 9, 6], [1, 4, 1], [5, 2]])
    expectNoDifference(sections.sortedByName(.descending).sectionNames, [2, 1, 0])
    expectNoDifference(sections.sortedByName(.descending)[sectionName: 1].map { Array($0) }, [1, 4, 1])
  }

  /// ADR 0015 L3's benchmark: 1,000 rows counting their 10,000 children, the 10,000 children grouped into 100 sections,
  /// timed and allocation-counted on one thread. A count reads each child's counted field; a rows include, the shape
  /// a row read before counts existed (every child linked, then `children.count` in the map), materializes each child.
  ///
  /// Measured optimized on the Mac mini (2026-11-08, three runs): counting 13.9-14.5 ms, 24,034 allocations, 6.5 MB;
  /// linking 37.8 ms, 19,052 allocations, 13.8 MB; sections 2.4-2.6 ms, 20,816 allocations, 2.5 MB. Counting allocates
  /// a little more often (it reads each child's counted field through a small snapshot) but half the bytes.
  @Test
  func countingTenThousandChildrenCostsLessThanLinkingThem() throws {
    var (indexes, attributes) = Self.fixture(recordings: 1_000, picturesPerRecording: 10)
    let all = InstantQueryIncludeCount()
    let images = InstantQueryIncludeCount(filters: [.equals(field: "kind", value: .string("image"))])
    var countOnly = InstantQueryIncludePlan(
      id: "pictures",
      namespace: Self.pictures,
      selectedFields: ["id", "kind"]
    )
    countOnly.counts = [all, images]
    countOnly.countOnly = true
    let countPlan = InstantQueryPlan(
      id: "counted",
      namespace: Self.recordings,
      includes: [InstantQueryInclude("pictures", direction: .reverse, query: countOnly)]
    )
    let rowsPlan = InstantQueryPlan(
      id: "linked",
      namespace: Self.recordings,
      includes: [
        InstantQueryInclude(
          "pictures",
          direction: .reverse,
          query: InstantQueryIncludePlan(id: "pictures", namespace: Self.pictures)
        )
      ]
    )
    let childPlan = InstantQueryPlan(id: "pictures", namespace: Self.pictures, order: InstantQueryOrder("capturedAtMs"))

    let counted = indexes.materialize(countPlan, attributes: attributes)
    expectNoDifference(counted.count, 1_000)
    expectNoDifference(counted.reduce(0) { $0 + ($1.counts?[all.snapshotKey(relation: "pictures")] ?? 0) }, 10_000)
    expectNoDifference(counted.reduce(0) { $0 + ($1.counts?[images.snapshotKey(relation: "pictures")] ?? 0) }, 4_000)
    let children = indexes.materialize(childPlan, attributes: attributes)
    expectNoDifference(children.count, 10_000)

    let countCost = Self.measure { _ = indexes.materialize(countPlan, attributes: attributes) }
    let rowsCost = Self.measure { _ = indexes.materialize(rowsPlan, attributes: attributes) }
    // capturedAtMs is recording * 100 + picture, so this names one section per hundredth recording: 100 sections.
    let section: (InstantEntitySnapshot) -> Int = { snapshot in
      guard case let .number(capturedAtMs)? = snapshot.values["capturedAtMs"]?.first else { return -1 }
      return Int(capturedAtMs) / 100 % 100
    }
    expectNoDifference(InstantResultsSectionCollection(grouping: children, by: section).count, 100)
    let sectionsCost = Self.measure {
      _ = InstantResultsSectionCollection(grouping: children, by: section)
    }
    print("L3BENCH count rows=1000 children=10000 \(countCost.line)")
    print("L3BENCH links rows=1000 children=10000 \(rowsCost.line)")
    print("L3BENCH sections rows=10000 sections=100 \(sectionsCost.line)")

    // Wall time on a busy host varies; allocated bytes do not, so the comparison holds on them. Optimized, counting
    // makes about 26% more allocations than linking (a small snapshot per counted child) for half the bytes.
    guard RealSizeBudget.isOptimized else { return }
    #expect(
      countCost.allocatedKB * 3 < rowsCost.allocatedKB * 2,
      "Counting allocated \(countCost.allocatedKB) KB, linking \(rowsCost.allocatedKB) KB."
    )
  }

  // MARK: - Fixture

  static let recordings = "bench_recordings"
  static let pictures = "bench_pictures"

  struct Cost {
    var medianMilliseconds: Double
    var allocations: Int
    var allocatedKB: Int

    var line: String {
      String(format: "medianMs=%.2f allocations=%d allocatedKB=%d", medianMilliseconds, allocations, allocatedKB)
    }
  }

  /// The median of five timed runs after a warm-up, then one run's allocations on this thread.
  static func measure(_ body: () -> Void) -> Cost {
    body()
    var samples: [Double] = []
    for _ in 0..<5 {
      let started = ContinuousClock.now
      body()
      let elapsed = ContinuousClock.now - started
      samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000)
    }
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    body()
    let counts = RealSizeAllocations.stop()
    return Cost(
      medianMilliseconds: samples.sorted()[samples.count / 2],
      allocations: counts.allocations,
      allocatedKB: counts.allocatedBytes / 1_024
    )
  }

  /// `recordings` rows, each linked by `picturesPerRecording` pictures whose kinds cycle image, screen, audio.
  static func fixture(recordings: Int, picturesPerRecording: Int) -> (TripleIndexes, AttributeStore) {
    let attributes = AttributeStore(
      attributes: [
        .primaryKey(namespace: Self.recordings),
        InstantAttribute(
          id: "\(Self.recordings)/startedAtMs",
          namespace: Self.recordings,
          name: "startedAtMs",
          valueType: .number,
          isIndexed: true
        ),
        .primaryKey(namespace: Self.pictures),
        InstantAttribute(
          id: "\(Self.pictures)/kind",
          namespace: Self.pictures,
          name: "kind",
          valueType: .string,
          isIndexed: true
        ),
        InstantAttribute(
          id: "\(Self.pictures)/capturedAtMs",
          namespace: Self.pictures,
          name: "capturedAtMs",
          valueType: .number,
          isIndexed: true
        ),
        InstantAttribute(
          id: "\(Self.pictures)/recording",
          namespace: Self.pictures,
          name: "recording",
          valueType: .ref,
          isIndexed: true,
          forwardIdentity: "\(Self.pictures)/recording",
          reverseIdentity: "\(Self.recordings)/pictures",
          linkNamespace: Self.recordings
        ),
      ]
    )
    var indexes = TripleIndexes(attributes: attributes)
    var time: Int64 = 1
    func insert(_ entityID: String, _ attributeID: String, _ value: InstantValue) {
      indexes.apply(
        .insert(
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: "tx-\(time)",
            txTime: InstantTimestamp(milliseconds: time)
          )
        ),
        attributes: attributes
      )
      time += 1
    }
    let kinds = ["image", "screen", "audio"]
    for recording in 0..<recordings {
      let recordingID = String(format: "recording-%05d", recording)
      insert(recordingID, InstantAttribute.primaryKeyID(namespace: Self.recordings), .string(recordingID))
      insert(recordingID, "\(Self.recordings)/startedAtMs", .number(Double(recording)))
      for picture in 0..<picturesPerRecording {
        let pictureID = "\(recordingID)-picture-\(picture)"
        insert(pictureID, InstantAttribute.primaryKeyID(namespace: Self.pictures), .string(pictureID))
        insert(pictureID, "\(Self.pictures)/kind", .string(kinds[picture % kinds.count]))
        insert(pictureID, "\(Self.pictures)/capturedAtMs", .number(Double(recording * 100 + picture)))
        insert(pictureID, "\(Self.pictures)/recording", .ref(recordingID))
      }
    }
    return (indexes, attributes)
  }
}
