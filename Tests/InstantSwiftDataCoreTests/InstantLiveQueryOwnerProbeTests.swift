import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #2553 (#2551): a refresh that takes facts out of its results asks, once per fact, whether a loaded stored result
/// that the refresh does not replace still owns it (`liveQueryTripleHasOwnerWithoutTransaction`). The probe named the
/// loaded results with an uncorrelated `query_id IN (SELECT query_id FROM instant_live_query_results WHERE unloaded_at_ms
/// IS NULL)`, a list SQLite rebuilds by scanning every stored result each time the statement runs. A phone's store held
/// 1,000 stored results on 2026-11-19, 51 of them loaded, and the probe was 56 of 229 refresh-apply samples in a Power
/// Profiler trace of v1.9.87 (494 of 708 retraction samples in a 3.6-hour trace of v1.9.86).
///
/// These tests pin that one probe reaches the results only through their primary key, whatever their number, and that
/// it answers as the subquery form answered, for owners loaded, unloaded and excluded.
@Suite(.serialized)
struct InstantLiveQueryOwnerProbeTests {
  /// 200 stored results, 50 loaded. Two probes of a fact a loaded result owns, one excluding that result: the subquery
  /// form scanned the results table once each, 2 x 199 full-scan steps; the key lookup takes none.
  @Test
  func oneOwnerProbeTakesNoFullScanStepWhateverTheNumberOfStoredResults() async throws {
    let fixture = try await OwnerProbeFixture.seeded(name: "steps")
    defer { fixture.remove() }
    let store = try SQLitePersistenceStore(fileURL: fixture.url)
    try await store.bootstrap()
    let probe = CompactOwnershipFixture.titleFact(4)
    let traced = OwnerProbeStatements()
    await store.traceStatementsForTesting { traced.record($0) }

    let before = await store.statementCountersForTesting()
    let owned = try await store.liveQueryTripleHasOwnerForTesting(probe, excludingQueryKeys: [])
    let ownedWithoutItsLoadedOwner = try await store.liveQueryTripleHasOwnerForTesting(
      probe,
      excludingQueryKeys: [OwnerProbeFixture.key(4)]
    )
    let after = await store.statementCountersForTesting()
    await store.traceStatementsForTesting(nil)

    #expect(owned)
    #expect(!ownedWithoutItsLoadedOwner)
    let probes = traced.statements.filter { $0.contains("instant_live_query_triples") }
    try #require(probes.count == 2, "statements: \(traced.statements)")
    var plans: [String] = []
    for sql in probes {
      plans += try await store.queryPlanForTesting(sql)
    }
    #expect(!plans.contains { $0.hasPrefix("SCAN") }, "plans: \(plans)")
    expectNoDifference(after.fullScanSteps - before.fullScanSteps, 0)
  }

  /// Every fact the 200 results hold, and four no result holds, each under seven exclusions (none, a loaded owner, an
  /// unloaded owner, both owners of a fact, a key with no stored result, every loaded result), answered by the library
  /// and by the subquery form the library used through v1.9.87, run as it was on the same file.
  @Test
  func theOwnerProbeAnswersAsTheSubqueryFormForOwnersLoadedUnloadedAndExcluded() async throws {
    let fixture = try await OwnerProbeFixture.seeded(name: "answers")
    defer { fixture.remove() }
    let store = try SQLitePersistenceStore(fileURL: fixture.url)
    try await store.bootstrap()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let probes = OwnerProbeFixture.probes
    let encoded = try probes.map { try InstantStoredJSON.stored($0.value, using: encoder) }
    // The reference reads values as the store writes them: every stored ownership value is one of the probes'.
    let storedValues = try SQLiteFile.strings(
      fixture.url,
      "SELECT DISTINCT value_json FROM instant_live_query_triples"
    )
    try #require(!storedValues.isEmpty)
    try #require(Set(storedValues).isSubset(of: Set(encoded)))

    let database = try SQLiteFile.open(fixture.url, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close(database) }
    var library: [String] = []
    var reference: [String] = []
    for (index, probe) in probes.enumerated() {
      for (exclusionIndex, exclusion) in OwnerProbeFixture.exclusions.enumerated() {
        let owned = try await store.liveQueryTripleHasOwnerForTesting(probe, excludingQueryKeys: exclusion)
        library.append("\(index) \(exclusionIndex) \(owned)")
        let subqueryOwned = try OwnerProbeFixture.subqueryForm(
          database,
          entityID: probe.entityID,
          attributeID: probe.attributeID,
          valueJSON: encoded[index],
          excludingQueryKeys: exclusion
        )
        reference.append("\(index) \(exclusionIndex) \(subqueryOwned)")
      }
    }

    expectNoDifference(library, reference)
    // The fixture tells the cases apart: some probes are owned, some not, and an exclusion or an unload changes answers.
    let answers = Set(reference.map { $0.split(separator: " ").last.map(String.init) ?? "" })
    expectNoDifference(answers, ["true", "false"])
    let item1 = try #require(probes.firstIndex(of: CompactOwnershipFixture.titleFact(1)))
    #expect(reference.contains("\(item1) 0 true"))
    #expect(reference.contains("\(item1) 1 false"), "item 1's loaded owner, result 0, is excluded")
    let item4 = try #require(probes.firstIndex(of: CompactOwnershipFixture.titleFact(4)))
    #expect(reference.contains("\(item4) 0 true"))
    #expect(reference.contains("\(item4) 3 false"), "item 4's loaded owner, result 4, is excluded")
    let item2 = try #require(probes.firstIndex(of: CompactOwnershipFixture.titleFact(2)))
    #expect(reference.contains("\(item2) 0 false"), "item 2's owners, results 1 and 2, are both unloaded")
  }
}

/// 200 stored results over `CompactOwnershipFixture`'s namespace: result i holds items i and i + 1 (an id and a title
/// each), and item i's three tags when i is a multiple of 10. Results whose index is a multiple of 4 stay loaded; the
/// other 150 are unloaded where they are (#1500), as a phone's store keeps most of its results.
struct OwnerProbeFixture {
  let directory: URL
  let url: URL

  static let resultCount = 200

  static func key(_ index: Int) -> String {
    "{\"items\":{\"$\":{\"where\":{\"page\":\(index)}}}}"
  }

  static func isLoaded(_ index: Int) -> Bool {
    index.isMultiple(of: 4)
  }

  static func triples(ofResult index: Int) -> [InstantTriple] {
    var triples = [index, index + 1].flatMap {
      [CompactOwnershipFixture.idFact($0), CompactOwnershipFixture.titleFact($0)]
    }
    if index.isMultiple(of: 10) {
      triples += CompactOwnershipFixture.tagFacts(index)
    }
    return triples
  }

  /// Every fact a result holds, once, then four no result holds.
  static let probes: [InstantTriple] = {
    var seen: Set<InstantTriple> = []
    var probes: [InstantTriple] = []
    for index in 0..<resultCount {
      for triple in triples(ofResult: index) where seen.insert(triple).inserted {
        probes.append(triple)
      }
    }
    probes.append(CompactOwnershipFixture.fact(999, "items/title", .string("A title no result holds")))
    probes.append(CompactOwnershipFixture.fact(5, "items/title", .string("Another title for an item a result holds")))
    probes.append(CompactOwnershipFixture.idFact(999))
    probes += CompactOwnershipFixture.tagFacts(15).prefix(1)
    return probes
  }()

  /// None; result 0 (loaded, item 1's other owner unloaded); results 3 and 4 (item 4's owners, unloaded and loaded);
  /// result 4 alone; result 1 (unloaded); a key with no stored result; every loaded result.
  static let exclusions: [Set<String>] = [
    [],
    [key(0)],
    [key(3), key(4)],
    [key(4)],
    [key(1)],
    ["no-such-key"],
    Set((0..<resultCount).filter(isLoaded).map(key)),
  ]

  static func seeded(name: String) async throws -> Self {
    let directory = try CompactOwnershipFixture.temporaryDirectory("owner-probe-\(name)")
    let url = directory.appending(path: "instant.sqlite")
    var facts: [InstantTriple] = []
    var seen: Set<InstantTriple> = []
    for index in 0..<resultCount {
      for triple in triples(ofResult: index) where seen.insert(triple).inserted {
        facts.append(triple)
      }
    }
    try await CompactOwnershipFixture.seed(
      url,
      facts: facts,
      outbox: [],
      results: (0..<resultCount).map {
        CompactOwnershipFixture.result(key($0), triples(ofResult: $0), at: CompactOwnershipFixture.stamp + Int64($0))
      }
    )
    let database = try SQLiteFile.open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    for index in 0..<resultCount where !isLoaded(index) {
      try SQLiteFile.run(
        database,
        "UPDATE instant_live_query_results SET unloaded_at_ms = ? WHERE query_key = ?",
        [String(CompactOwnershipFixture.stamp + 1_000), key(index)]
      )
    }
    let unloaded = try SQLiteFile.rows(
      database,
      "SELECT COUNT(*) FROM instant_live_query_results WHERE unloaded_at_ms IS NOT NULL"
    )
    try #require(unloaded == [["150"]])
    return Self(directory: directory, url: url)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }

  /// The probe as the library ran it through v1.9.87, on a plain connection.
  static func subqueryForm(
    _ database: OpaquePointer,
    entityID: String,
    attributeID: String,
    valueJSON: String,
    excludingQueryKeys: Set<String>
  ) throws -> Bool {
    var sql = """
      SELECT 1
      FROM instant_live_query_triples
      WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
        AND query_id IN (SELECT query_id FROM instant_live_query_results WHERE unloaded_at_ms IS NULL)
      """
    var bindings = [entityID, attributeID, valueJSON]
    if !excludingQueryKeys.isEmpty {
      sql += " AND query_id NOT IN (SELECT query_id FROM instant_live_query_results WHERE query_key IN ("
        + Array(repeating: "?", count: excludingQueryKeys.count).joined(separator: ", ")
        + "))"
      bindings += excludingQueryKeys.sorted()
    }
    sql += " LIMIT 1"
    return try !SQLiteFile.rows(database, sql, bindings).isEmpty
  }
}

/// The SQL of each statement a store's writer runs, as the store's trace hands it over.
final class OwnerProbeStatements: @unchecked Sendable {
  // SAFETY: `lock` protects `recorded`.
  private let lock = NSLock()
  private var recorded: [String] = []

  func record(_ sql: String) {
    lock.withLock { recorded.append(sql) }
  }

  var statements: [String] {
    lock.withLock { recorded }
  }
}
