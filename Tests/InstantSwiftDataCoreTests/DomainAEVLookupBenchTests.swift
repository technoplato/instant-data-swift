import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Ground AEV omission for Scribe-shaped product lookups.
///
/// TypeScript Instant keeps AEV; experiment tip scans EAV. At N=200 recordings the
/// absolute scan cost should still be sub-millisecond — measure it.
///
/// Also measures product-shaped seed memory (segments + wordsJSON, **no** word
/// entities) so we can compare to the TS `@instantdb/core` baseline.
@Suite(.serialized)
struct DomainAEVLookupBenchTests {
  private let locations = [
    "Home Office", "Kitchen", "Car — commute", "Park walk", "Coffee shop",
    "Conference room A", "Conference room B", "Airport terminal", "Gym", "Library",
  ]

  /// Fair store-only floor (no SQLite dual residency) vs TypeScript `@instantdb/core` heap.
  @Test
  func storeOnlyProductSeedMemoryAndLookups() async throws {
    let recordingCount = 200
    let segmentsPerRecording = 8
    let baseline = InstantProcessMemory.sample()
    let ops = productSeedOperations(
      recordingCount: recordingCount,
      segmentsPerRecording: segmentsPerRecording
    )
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: domainAttributes()))
    // prepare commits on the live store.
    let prepared = try await store.prepare(
      InstantStoreTransaction(id: "store-only-seed", operations: ops)
    )

    let locationPlan = InstantQueryPlan(
      id: "store.location",
      namespace: "recordings",
      filters: [.equals(field: "locationLabel", value: .string("Conference room A"))],
      limit: 200
    )
    let iters = 500
    // Warm
    _ = await store.measureMaterializeAverageNanoseconds(locationPlan, iterations: 5)
    let locationBench = await store.measureMaterializeAverageNanoseconds(
      locationPlan,
      iterations: iters
    )
    let locationAvgMs = locationBench.averageNanoseconds / 1_000_000
    let locationCount = locationBench.lastCount

    let listPlan = InstantQueryPlan(
      id: "store.list",
      namespace: "recordings",
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 50
    )
    _ = await store.measureMaterializeAverageNanoseconds(listPlan, iterations: 5)
    let listBench = await store.measureMaterializeAverageNanoseconds(listPlan, iterations: iters)
    let listAvgMs = listBench.averageNanoseconds / 1_000_000
    let listCount = listBench.lastCount

    let after = InstantProcessMemory.sample()
    let growth: UInt64 =
      if let baseline, let after, after.physicalFootprintBytes > baseline.physicalFootprintBytes
      {
        after.physicalFootprintBytes - baseline.physicalFootprintBytes
      } else { 0 }

    print(
      """
      STORE_ONLY_BENCH profile=200rec×8seg_wordsJSON \
      physical_growth_bytes=\(growth) mb_growth=\(String(format: "%.1f", Double(growth) / 1024 / 1024)) \
      triple_count=\(prepared.result.tripleCount) \
      list50_avg_ms=\(String(format: "%.4f", listAvgMs)) list_count=\(listCount) \
      location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_matches=\(locationCount)
      """
    )
    #expect(locationCount == 20)
    #expect(listCount == 50)
    // Fair TS baseline (same shape): heap ~9.6 MB; full InstaQL location filter ~0.069 ms.
    // Physical footprint growth is freelist-noisy under Debug multi-suite runs; Release
    // isolation is the ship gate (measured 6.4 MB / 0.051 ms on this machine).
    #if DEBUG
      #expect(growth < 150 * 1024 * 1024)
      #expect(locationAvgMs < 1.0)
    #else
      #expect(growth < 9 * 1024 * 1024)
      #expect(locationAvgMs < 0.069)
    #endif
  }

  @Test
  func twoHundredRecordingsLookupLatencyAndProductSeedMemory() async throws {
    let recordingCount = 200
    let segmentsPerRecording = 8
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DomainAEVBench-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let attributes = domainAttributes()
    let baseline = InstantProcessMemory.sample()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "domain-aev-bench",
        persistenceURL: cacheURL,
        initialAttributes: attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    let ops = productSeedOperations(
      recordingCount: recordingCount,
      segmentsPerRecording: segmentsPerRecording
    )
    let seedCreatedAt = InstantTimestamp(milliseconds: 1_700_200_000_000)
    for transaction in BoundedBenchmarkSeed.transactions(
      baseID: "domain-aev-seed",
      atomicOperationGroups: ops.map { [$0] }
    ) {
      try await runtime.transact(transaction, createdAt: seedCreatedAt)
    }

    // List query (ordered page) — no AEV fast path on tip
    let listPlan = InstantQueryPlan(
      id: "domain.list",
      namespace: "recordings",
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 50
    )
    let tList0 = DispatchTime.now().uptimeNanoseconds
    let page = try await runtime.query(listPlan)
    let tList1 = DispatchTime.now().uptimeNanoseconds
    let listMs = Double(tList1 - tList0) / 1_000_000

    // Equality filter by location (EAV scan path without AEV)
    let locationPlan = InstantQueryPlan(
      id: "domain.location",
      namespace: "recordings",
      filters: [
        .equals(field: "locationLabel", value: .string("Conference room A")),
      ],
      limit: 200
    )
    let iters = 50
    var locationTotalNs: UInt64 = 0
    var locationCount = 0
    for _ in 0..<iters {
      let t0 = DispatchTime.now().uptimeNanoseconds
      let result = try await runtime.query(locationPlan)
      let t1 = DispatchTime.now().uptimeNanoseconds
      locationTotalNs += t1 - t0
      locationCount = result.count
    }
    let locationAvgMs = Double(locationTotalNs) / Double(iters) / 1_000_000

    // Speaker filter
    let speakerPlan = InstantQueryPlan(
      id: "domain.speaker",
      namespace: "recordings",
      filters: [
        .equals(field: "speakerCount", value: .number(2)),
      ],
      limit: 200
    )
    var speakerTotalNs: UInt64 = 0
    for _ in 0..<iters {
      let t0 = DispatchTime.now().uptimeNanoseconds
      _ = try await runtime.query(speakerPlan)
      let t1 = DispatchTime.now().uptimeNanoseconds
      speakerTotalNs += t1 - t0
    }
    let speakerAvgMs = Double(speakerTotalNs) / Double(iters) / 1_000_000

    // Title exact
    let titlePlan = InstantQueryPlan(
      id: "domain.title",
      namespace: "recordings",
      filters: [
        .equals(field: "title", value: .string("Recording 100")),
      ],
      limit: 10
    )
    var titleTotalNs: UInt64 = 0
    for _ in 0..<iters {
      let t0 = DispatchTime.now().uptimeNanoseconds
      _ = try await runtime.query(titlePlan)
      let t1 = DispatchTime.now().uptimeNanoseconds
      titleTotalNs += t1 - t0
    }
    let titleAvgMs = Double(titleTotalNs) / Double(iters) / 1_000_000

    let after = InstantProcessMemory.sample()
    let growth: UInt64 =
      if let baseline, let after, after.physicalFootprintBytes > baseline.physicalFootprintBytes
      {
        after.physicalFootprintBytes - baseline.physicalFootprintBytes
      } else { 0 }

    print(
      """
      DOMAIN_AEV_BENCH profile=200rec×8seg_wordsJSON \
      physical_growth_bytes=\(growth) mb_growth=\(String(format: "%.1f", Double(growth) / 1024 / 1024)) \
      list50_ms=\(String(format: "%.3f", listMs)) list_count=\(page.count) \
      location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_matches=\(locationCount) \
      speaker2_eq_avg_ms=\(String(format: "%.4f", speakerAvgMs)) \
      title_eq_avg_ms=\(String(format: "%.4f", titleAvgMs)) \
      aev=disabled_eav_scan
      """
    )

    #expect(page.count == 50)
    #expect(locationCount == 20)  // 200/10 locations
    // Product bar at N=200 without AEV: filters stay interactive (<50 ms).
    // TS pure-store scan is ~0.04 ms; Swift InstantRuntime path is higher overhead
    // but must not become multi-hundred-ms list jank from AEV removal alone.
    #expect(locationAvgMs < 50.0)
    #expect(listMs < 50.0)
  }

  private func productSeedOperations(
    recordingCount: Int,
    segmentsPerRecording: Int
  ) -> [InstantTripleOperation] {
    var ops: [InstantTripleOperation] = []
    let now = InstantTimestamp(milliseconds: 1_700_200_000_000)
    let tx = "domain-aev-seed"
    let wordsJSON =
      "[{\"t\":\"w0\"},{\"t\":\"w1\"},{\"t\":\"w2\"},{\"t\":\"w3\"},{\"t\":\"w4\"},{\"t\":\"w5\"},{\"t\":\"w6\"},{\"t\":\"w7\"},{\"t\":\"w8\"},{\"t\":\"w9\"},{\"t\":\"w10\"},{\"t\":\"w11\"}]"
    for index in 0..<recordingCount {
      let rid = "rec-\(index)"
      let loc = locations[index % locations.count]
      ops.append(contentsOf: [
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/id",
            value: .string(rid),
            txID: tx,
            txTime: now
          )
        ),
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/title",
            value: .string(String(format: "Recording %03d", index + 1)),
            txID: tx,
            txTime: now
          )
        ),
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/locationLabel",
            value: .string(loc),
            txID: tx,
            txTime: now
          )
        ),
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/latitude",
            value: .number(37.7 + Double(index % 50) * 0.01),
            txID: tx,
            txTime: now
          )
        ),
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/speakerCount",
            value: .number(Double(1 + index % 3)),
            txID: tx,
            txTime: now
          )
        ),
        .insert(
          InstantTriple(
            entityID: rid,
            attributeID: "recordings/updatedAtMs",
            value: .number(Double(1_700_200_000_000 - index * 60_000)),
            txID: tx,
            txTime: now
          )
        ),
      ])
      for segment in 0..<segmentsPerRecording {
        let sid = "seg-\(index)-\(segment)"
        ops.append(contentsOf: [
          .insert(
            InstantTriple(
              entityID: sid,
              attributeID: "transcriptionSegments/id",
              value: .string(sid),
              txID: tx,
              txTime: now
            )
          ),
          .insert(
            InstantTriple(
              entityID: sid,
              attributeID: "transcriptionSegments/recordingID",
              value: .string(rid),
              txID: tx,
              txTime: now
            )
          ),
          .insert(
            InstantTriple(
              entityID: sid,
              attributeID: "transcriptionSegments/wordsJSON",
              value: .string(wordsJSON),
              txID: tx,
              txTime: now
            )
          ),
          .insert(
            InstantTriple(
              entityID: sid,
              attributeID: "transcriptionSegments/wordCount",
              value: .number(12),
              txID: tx,
              txTime: now
            )
          ),
          .insert(
            InstantTriple(
              entityID: sid,
              attributeID: "transcriptionSegments/seq",
              value: .number(Double(segment)),
              txID: tx,
              txTime: now
            )
          ),
        ])
      }
    }
    return ops
  }

  private func domainAttributes() -> [InstantAttribute] {
    [
      .primaryKey(namespace: "recordings"),
      InstantAttribute(
        id: "recordings/title",
        namespace: "recordings",
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/locationLabel",
        namespace: "recordings",
        name: "locationLabel",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/latitude",
        namespace: "recordings",
        name: "latitude",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/speakerCount",
        namespace: "recordings",
        name: "speakerCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/updatedAtMs",
        namespace: "recordings",
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      .primaryKey(namespace: "transcriptionSegments"),
      InstantAttribute(
        id: "transcriptionSegments/recordingID",
        namespace: "transcriptionSegments",
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/wordsJSON",
        namespace: "transcriptionSegments",
        name: "wordsJSON",
        valueType: .string
      ),
      InstantAttribute(
        id: "transcriptionSegments/wordCount",
        namespace: "transcriptionSegments",
        name: "wordCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/seq",
        namespace: "transcriptionSegments",
        name: "seq",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }
}

/// Deterministically packs benchmark seed work into durable transactions that
/// fit the same transport-step ceiling enforced for product writes.
///
/// Callers choose the atomic operation groups. A plain insert-only seed can use
/// one operation per group, while an entity-creation seed keeps its missing
/// precondition and every field write for that entity in one group.
enum BoundedBenchmarkSeed {
  static func transactions(
    baseID: String,
    atomicOperationGroups: [[InstantTripleOperation]]
  ) -> [InstantStoreTransaction] {
    var batches: [[InstantTripleOperation]] = []
    var currentBatch: [InstantTripleOperation] = []
    var currentStepCount = 0

    for group in atomicOperationGroups {
      let groupStepCount = group.reduce(into: 0) { count, operation in
        count += transportStepCount(of: operation)
      }
      precondition(
        groupStepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount,
        "A benchmark seed's atomic operation group must fit one durable transaction."
      )

      if !currentBatch.isEmpty,
        currentStepCount + groupStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount
      {
        batches.append(currentBatch)
        currentBatch.removeAll(keepingCapacity: true)
        currentStepCount = 0
      }

      currentBatch.append(contentsOf: group)
      currentStepCount += groupStepCount
    }

    if !currentBatch.isEmpty {
      batches.append(currentBatch)
    }

    return batches.enumerated().map { batchIndex, operations in
      InstantStoreTransaction(
        id: "\(baseID)-\(String(format: "%04d", batchIndex))",
        operations: operations
      )
    }
  }

  static func entityCreationGroups(
    from operations: [InstantTripleOperation]
  ) -> [[InstantTripleOperation]] {
    var groups: [[InstantTripleOperation]] = []
    for operation in operations {
      switch operation {
      case .requireEntityMissing, .requireEntityMissingByLookup:
        groups.append([operation])

      default:
        precondition(
          !groups.isEmpty,
          "An entity-creation benchmark seed must begin each entity with a missing precondition."
        )
        groups[groups.index(before: groups.endIndex)].append(operation)
      }
    }
    return groups
  }

  private static func transportStepCount(of operation: InstantTripleOperation) -> Int {
    switch operation {
    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup, .requireTripleExists:
      0

    case .merge, .mergeByLookup, .insert, .insertByLookup, .retract, .retractByLookup,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
      .ruleParams, .ruleParamsByLookup:
      1
    }
  }
}
