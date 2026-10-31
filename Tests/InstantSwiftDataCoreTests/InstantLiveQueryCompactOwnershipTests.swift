import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #704 (P1): a device's store kept 32,555 live-query ownership rows, 3.7 MB of values, in 328.9 MB. Every row of
/// `instant_live_query_triples` repeated its query's key, the whole InstaQL JSON of the query (1,671 bytes on average,
/// up to 4,306), and both of the table's indexes held that key, so most index entries spilled to an overflow page of
/// their own. Ownership rows now name their result by an integer id (ADR 0020), and a store in migration 0011's layout
/// converts once, when it opens.
///
/// These tests pin the layout, the bytes a long-keyed result's ownership takes, that a converted store answers every
/// ownership read as the store answered before the change, that a conversion interrupted before its commit is redone
/// whole, that a row whose result is missing is counted, and what the conversion costs the open path.
@Suite(.serialized)
struct InstantLiveQueryCompactOwnershipTests {
  // MARK: - The layout

  /// A new store's ownership rows name their result by an integer id, in a table that is its own primary-key b-tree.
  @Test
  func aNewStoreKeysOwnershipByAnIntegerQueryID() async throws {
    let directory = try CompactOwnershipFixture.temporaryDirectory("layout")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "instant.sqlite")
    let store = try SQLitePersistenceStore(fileURL: url)
    try await store.bootstrap()

    expectNoDifference(try OwnershipLayout.read(url), .compact)
  }

  // MARK: - Bytes

  /// One result with the device's longest key (4,306 bytes) and 1,000 ownership rows. The issue's bound is 30 MB for
  /// the device's 32,555 rows: 921 bytes a row. 0011's layout took about 13 KB a row for a key this long.
  @Test
  func aLongKeyedResultsOwnershipStaysUnderTheIssuesBound() async throws {
    let fixture = try await CompactOwnershipFixture.seededWithOneResult(
      name: "bytes",
      keyLength: 4_306,
      itemCount: 500
    )
    defer { fixture.remove() }

    let measured = try OwnershipBytes.read(fixture.url)

    expectNoDifference(measured.rows, 1_000)
    #expect(
      measured.bytes / measured.rows < 921,
      "The ownership of 1,000 rows took \(measured.bytes) bytes, \(measured.bytes / max(measured.rows, 1)) a row."
    )
  }

  // MARK: - The conversion

  /// Two stores seeded alike: one stays as written, the other is put back in 0011's layout and reopened. The converted
  /// store keeps every result row, every ownership row, the outbox and the facts byte for byte, and answers every
  /// ownership read (a result's rows, whether a fact is still owned, #441's newest stamp, #445's newest values, the
  /// application-migration scan, the facts bootstrap loads) as the other store does; then both prune a result and store
  /// a narrower one, and answer alike again. The answers' digest is the one the library gave before this change, on the
  /// layout it wrote then.
  @Test
  func aStoreIn0011sLayoutConvertsAtOpenAndAnswersEveryOwnershipReadAsBefore() async throws {
    let reference = try await CompactOwnershipFixture.seeded(name: "reference")
    defer { reference.remove() }
    let converted = try await CompactOwnershipFixture.seeded(name: "converted")
    defer { converted.remove() }
    try converted.rewriteIn0011Layout()
    let ownershipBefore = try converted.ownershipRows()
    let resultsBefore = try converted.resultRows()
    let outboxBefore = try converted.outboxRows()
    let factsBefore = try converted.factRows()
    try #require(ownershipBefore.count == CompactOwnershipFixture.seededOwnershipRowCount)
    let capture = CompactionCapture(path: converted.url.path)
    let handler = InstantDiagnostics.shared.addHandler { capture.record($0) }
    defer { InstantDiagnostics.shared.removeHandler(handler) }

    let referenceStore = try SQLitePersistenceStore(fileURL: reference.url)
    try await referenceStore.bootstrap()
    let convertedStore = try SQLitePersistenceStore(fileURL: converted.url)
    try await convertedStore.bootstrap()

    expectNoDifference(try OwnershipLayout.read(converted.url), .compact)
    expectNoDifference(try converted.ownershipRows(), ownershipBefore)
    expectNoDifference(try converted.resultRows(), resultsBefore)
    expectNoDifference(try converted.outboxRows(), outboxBefore)
    expectNoDifference(try converted.factRows(), factsBefore)
    expectNoDifference(try converted.ledgerRowCount(), 1)
    expectNoDifference(
      capture.entries.map { [$0.metadata["rows"], $0.metadata["results"], $0.metadata["rowsWithoutAResult"]] },
      [["1040", "4", "0"]]
    )

    var expected = try await CompactOwnershipAnswers.read(referenceStore, reference)
    var answered = try await CompactOwnershipAnswers.read(convertedStore, converted)
    expectNoDifference(answered, expected)
    expected.lines += try await reference.applyTheSameChanges(to: referenceStore)
    answered.lines += try await converted.applyTheSameChanges(to: convertedStore)
    expected.lines += try await CompactOwnershipAnswers.read(referenceStore, reference).lines
    answered.lines += try await CompactOwnershipAnswers.read(convertedStore, converted).lines
    expectNoDifference(answered, expected)
    expectNoDifference(expected.digest, CompactOwnershipAnswers.digestBeforeTheChange)

    // The next open finds the new layout and rewrites nothing.
    let rootPages = try OwnershipLayout.rootPages(converted.url)
    let reopened = try SQLitePersistenceStore(fileURL: converted.url)
    try await reopened.bootstrap()
    expectNoDifference(try OwnershipLayout.rootPages(converted.url), rootPages)
    expectNoDifference(try converted.ledgerRowCount(), 1)
    expectNoDifference(capture.entries.count, 1)
  }

  /// A process that dies during the conversion leaves the store as it was: the conversion is one transaction, and
  /// SQLite ignores the uncommitted part of the WAL. The copy below is taken while a conversion's transaction has
  /// written its first steps (the new results table filled, the rows staged, the old ownership table dropped) to the
  /// WAL, as a crash at that moment leaves the files. The next open converts the whole store.
  @Test
  func aConversionInterruptedBeforeItsCommitIsRedoneWholeAtTheNextOpen() async throws {
    let fixture = try await CompactOwnershipFixture.seeded(name: "interrupted")
    defer { fixture.remove() }
    try fixture.rewriteIn0011Layout()
    let ownershipBefore = try fixture.ownershipRows()
    let resultsBefore = try fixture.resultRows()
    let crashed = try fixture.copyTakenDuringAnUncommittedConversion()
    defer { try? FileManager.default.removeItem(at: crashed.deletingLastPathComponent()) }
    let walBytes = try FileManager.default.attributesOfItem(atPath: crashed.path + "-wal")[.size] as? Int ?? 0
    try #require(
      walBytes > 64 * 1_024,
      "The copy's WAL should hold the uncommitted conversion's pages; it holds \(walBytes) bytes."
    )
    let crashedFixture = CompactOwnershipFixture(directory: crashed.deletingLastPathComponent(), url: crashed)

    let store = try SQLitePersistenceStore(fileURL: crashed)
    try await store.bootstrap()

    expectNoDifference(try OwnershipLayout.read(crashed), .compact)
    expectNoDifference(try crashedFixture.ownershipRows(), ownershipBefore)
    expectNoDifference(try crashedFixture.resultRows(), resultsBefore)
    expectNoDifference(try crashedFixture.ledgerRowCount(), 1)
  }

  /// The foreign key forbids an ownership row whose result is missing, so only a store written with foreign keys off
  /// can hold one. It names no result, so the conversion cannot copy it; the log counts it.
  @Test
  func anOwnershipRowWhoseResultIsMissingIsCountedAndNotCopied() async throws {
    let fixture = try await CompactOwnershipFixture.seeded(name: "orphan")
    defer { fixture.remove() }
    try fixture.rewriteIn0011Layout()
    let ownershipBefore = try fixture.ownershipRows()
    try SQLiteFile.execute(
      fixture.url,
      """
      PRAGMA foreign_keys = OFF;
      INSERT INTO instant_live_query_triples (query_key, entity_id, attribute_id, value_json)
      VALUES ('a-result-that-was-never-stored', 'orphan-entity', 'items/title', '{"string":"orphan"}');
      """
    )
    let capture = CompactionCapture(path: fixture.url.path)
    let handler = InstantDiagnostics.shared.addHandler { capture.record($0) }
    defer { InstantDiagnostics.shared.removeHandler(handler) }

    let store = try SQLitePersistenceStore(fileURL: fixture.url)
    try await store.bootstrap()

    expectNoDifference(try OwnershipLayout.read(fixture.url), .compact)
    expectNoDifference(try fixture.ownershipRows(), ownershipBefore)
    expectNoDifference(
      capture.entries.map { [$0.metadata["rows"], $0.metadata["rowsWithoutAResult"]] },
      [["1040", "1"]]
    )
  }

  // MARK: - The open path

  /// 20 results of 500 ownership rows each, with keys of the device's average length (1,671 bytes): about 100 MB in
  /// 0011's layout. The conversion runs inside `bootstrap()`, on the opening thread; its CPU time is bounded at 2 s,
  /// about ten times what it takes on a laptop, so only a conversion that does far more work than this one fails. The
  /// next open checks one table's columns and rewrites nothing.
  @Test
  func aConversionOf10000LongKeyedRowsFitsTheOpenBudget() async throws {
    let fixture = try await CompactOwnershipFixture.oldLayoutWithManyRows(
      name: "budget",
      resultCount: 20,
      itemsPerResult: 250,
      keyLength: 1_671
    )
    defer { fixture.remove() }
    try #require(try fixture.ownershipRows().count == 10_000)

    let store = try SQLitePersistenceStore(fileURL: fixture.url)
    let conversion = try await CompactOwnershipFixture.measuredBootstrap(store)

    expectNoDifference(try OwnershipLayout.read(fixture.url), .compact)
    expectNoDifference(try fixture.ownershipRows().count, 10_000)
    #expect(
      conversion.cpuMilliseconds < 2_000,
      "Converting 10,000 rows took \(conversion.cpuMilliseconds) ms of CPU, \(conversion.wallMilliseconds) ms in all."
    )

    let rootPages = try OwnershipLayout.rootPages(fixture.url)
    let reopened = try SQLitePersistenceStore(fileURL: fixture.url)
    let reopen = try await CompactOwnershipFixture.measuredBootstrap(reopened)
    expectNoDifference(try OwnershipLayout.rootPages(fixture.url), rootPages)
    #expect(
      reopen.cpuMilliseconds < 250,
      "Reopening the converted store took \(reopen.cpuMilliseconds) ms of CPU, \(reopen.wallMilliseconds) ms in all."
    )
    print(
      "#704 open budget: conversion of 10,000 rows \(conversion.cpuMilliseconds) ms CPU, "
        + "\(conversion.wallMilliseconds) ms wall; reopen \(reopen.cpuMilliseconds) ms CPU, "
        + "\(reopen.wallMilliseconds) ms wall"
    )
  }

  // MARK: - A device's store

  /// A copy of a device's store, given as `INSTANT_704_DEVICE_STORE` (a `.sqlite` with its `-wal` and `-shm`, or their
  /// folder); skipped without it. The copy is made in the temporary folder with its credential rows deleted, and the
  /// source is never opened for writing. Before the open, the reads are answered by the statements the library used
  /// before this change, on the layout it wrote then; after the open, by the library itself. Every answer, every result
  /// row, every ownership row and every outbox row must be the same; the sizes and times are printed.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_704_DEVICE_STORE"] != nil))
  func aDevicesStoreConvertsAndAnswersEveryOwnershipReadAsBefore() async throws {
    let source = try PhoneReplayGateTests.storeFile(
      at: try #require(ProcessInfo.processInfo.environment["INSTANT_704_DEVICE_STORE"])
    )
    let url = try PhoneReplayGateTests.scratchCopy(of: source, in: FileManager.default.temporaryDirectory)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let fixture = CompactOwnershipFixture(directory: url.deletingLastPathComponent(), url: url)
    let columns = try SQLiteFile.strings(url, "SELECT name FROM pragma_table_info('instant_live_query_triples')")
    try #require(columns.contains("query_key"), "The copy is already converted.")

    let fileBytesBefore = try OwnershipBytes.fileBytes(url)
    let sizesBefore = try OwnershipBytes.liveQueryTableBytes(url)
    let ownershipBefore = try fixture.ownershipDigest()
    let resultsBefore = try SQLiteFile.digest(url, CompactOwnershipFixture.resultRowsSQL)
    let outboxBefore = try SQLiteFile.digest(url, "SELECT * FROM instant_outbox ORDER BY mutation_id")
    let factsBefore = try SQLiteFile.digest(url, CompactOwnershipFixture.factRowsSQL)
    let legacy = try LegacyOwnershipReads.answers(url)

    let store = try SQLitePersistenceStore(fileURL: url)
    let conversion = try await CompactOwnershipFixture.measuredBootstrap(store)

    expectNoDifference(try OwnershipLayout.read(url), .compact)
    expectNoDifference(try fixture.ownershipDigest(), ownershipBefore)
    expectNoDifference(try SQLiteFile.digest(url, CompactOwnershipFixture.resultRowsSQL), resultsBefore)
    expectNoDifference(try SQLiteFile.digest(url, "SELECT * FROM instant_outbox ORDER BY mutation_id"), outboxBefore)
    expectNoDifference(try SQLiteFile.digest(url, CompactOwnershipFixture.factRowsSQL), factsBefore)
    let answered = try await LegacyOwnershipReads.libraryAnswers(store, url: url, probes: legacy.probes)
    expectNoDifference(answered.lines.count, legacy.answers.lines.count)
    expectNoDifference(answered, legacy.answers)

    let reopenedStore = try SQLitePersistenceStore(fileURL: url)
    let reopen = try await CompactOwnershipFixture.measuredBootstrap(reopenedStore)
    let sizesAfter = try OwnershipBytes.liveQueryTableBytes(url)
    try SQLiteFile.execute(url, "PRAGMA wal_checkpoint(TRUNCATE)")
    print(
      """
      #704 device store: \(ownershipBefore.rows) ownership rows, \(resultsBefore.rows) results, \
      \(outboxBefore.rows) outbox rows, \(factsBefore.rows) facts, \(legacy.answers.lines.count) answers compared.
      #704 device store: live-query tables before \(sizesBefore), after \(sizesAfter); file \(fileBytesBefore) bytes \
      before, \(try OwnershipBytes.fileBytes(url)) after, \(try OwnershipBytes.freelistBytes(url)) of it free.
      #704 device store: conversion \(conversion.cpuMilliseconds) ms CPU, \(conversion.wallMilliseconds) ms wall; \
      reopen \(reopen.cpuMilliseconds) ms CPU, \(reopen.wallMilliseconds) ms wall.
      """
    )
  }
}

// MARK: - Answers

/// What a store answers to every ownership read, one line per answer, for a fixture's keys and probes.
struct CompactOwnershipAnswers: Equatable {
  var lines: [String]

  /// The digest of the answers the library gave before this change (v1.9.10 with the read-only test hooks, on the
  /// layout it wrote), for ``CompactOwnershipFixture/seeded(name:)`` and its changes.
  static let digestBeforeTheChange = "e5f08f8f40ae0900 over 22178 answers"

  var digest: String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in lines.joined(separator: "\n").utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(format: "%016llx", hash) + " over \(lines.count) answers"
  }

  static func read(
    _ store: SQLitePersistenceStore,
    _ fixture: CompactOwnershipFixture
  ) async throws -> Self {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var lines: [String] = []
    for (label, key) in CompactOwnershipFixture.labeledKeys {
      for row in try await store.liveQueryOwnershipForTesting(queryKey: key) {
        lines.append("ownership \(label) \(row.joined(separator: " "))")
      }
      if let result = try await store.liveQueryResult(key: key) {
        lines.append("result \(label) \(result.triples.count) \(result.updatedAt.milliseconds)")
      } else {
        lines.append("result \(label) none")
      }
    }
    let probes = CompactOwnershipFixture.probes
    let attributes = AttributeStore(attributes: CompactOwnershipFixture.attributes)
    for (index, probe) in probes.enumerated() {
      for (exclusionIndex, exclusion) in CompactOwnershipFixture.exclusions.enumerated() {
        let owned = try await store.liveQueryTripleHasOwnerForTesting(probe, excludingQueryKeys: exclusion)
        lines.append("owned \(index) \(exclusionIndex) \(owned)")
      }
      for (thresholdIndex, threshold) in CompactOwnershipFixture.thresholds.enumerated() {
        let shown = try await store.newestServerResultShowingForTesting(
          probe,
          attributes: attributes,
          storedAtOrAfter: threshold
        )
        lines.append("showing \(index) \(thresholdIndex) \(shown.map { String($0) } ?? "none")")
      }
    }
    for (index, slot) in CompactOwnershipFixture.slots.enumerated() {
      let values = try await store.newestServerValuesForTesting(of: slot)
      lines.append("values \(index) \(String(decoding: try encoder.encode(values), as: UTF8.self))")
    }
    for (index, attributeIDs) in CompactOwnershipFixture.migrationAttributeSets.enumerated() {
      let keys = try await store.applicationMigrationLiveQueryResultKeysForTesting(affectedAttributeIDs: attributeIDs)
      lines.append("migration \(index) \(keys.map(CompactOwnershipFixture.label(of:)).joined(separator: " "))")
    }
    let state = try await store.loadCompactState()
    lines += try state.snapshot.store.triples.map { triple in
      let value = String(decoding: try encoder.encode(triple.value), as: UTF8.self)
      return "loaded \(triple.entityID) \(triple.attributeID) \(value)"
    }.sorted()
    return Self(lines: lines)
  }
}

// MARK: - Fixture

/// A store with four live-query results over one namespace: two pages with long keys that share 100 items, a
/// short-keyed result with a many-valued attribute, and an empty result; two pending writes; and the probes the answers
/// use.
struct CompactOwnershipFixture {
  let directory: URL
  let url: URL

  static let stamp: Int64 = 1_791_000_000_000
  static let titleAttribute = InstantAttribute(id: "items/title", namespace: "items", name: "title", valueType: .string)
  static let tagsAttribute = InstantAttribute(
    id: "items/tags",
    namespace: "items",
    name: "tags",
    valueType: .string,
    isRequired: false,
    cardinality: .many
  )
  static let attributes: [InstantAttribute] = [.primaryKey(namespace: "items"), titleAttribute, tagsAttribute]

  static let firstPageKey = listKey("first-page", length: 1_700)
  static let secondPageKey = listKey("second-page", length: 4_306)
  static let tagsKey = "items.tags"
  static let emptyKey = "items.none"
  static let labeledKeys: [(label: String, key: String)] = [
    ("K1", firstPageKey), ("K2", secondPageKey), ("K3", tagsKey), ("K4", emptyKey),
  ]
  /// K1 600 + K2 400 + K3 40 + K4 0.
  static let seededOwnershipRowCount = 1_040

  static let exclusions: [Set<String>] = [
    [], [firstPageKey], [secondPageKey], [firstPageKey, secondPageKey], [tagsKey], ["no-such-key"],
    [firstPageKey, secondPageKey, tagsKey, emptyKey],
  ]
  static let thresholds: [Int64] = [0, stamp + 6, stamp + 15, stamp + 25]
  static let migrationAttributeSets: [Set<String>] = [
    ["items/title"], ["items/tags"], ["items/id", "items/tags"], ["nothing/here"],
  ]

  static func label(of key: String) -> String {
    labeledKeys.first { $0.key == key }?.label ?? key
  }

  static func itemID(_ index: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012ld", index)
  }

  static func fact(_ index: Int, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
    InstantTriple(
      entityID: itemID(index),
      attributeID: attributeID,
      value: value,
      txID: "seed",
      txTime: InstantTimestamp(milliseconds: stamp)
    )
  }

  static func idFact(_ index: Int) -> InstantTriple {
    fact(index, "items/id", .string(itemID(index)))
  }

  static func titleFact(_ index: Int) -> InstantTriple {
    fact(index, "items/title", .string("Item \(index): a title about as long as a recording's, with a few more words"))
  }

  static func tagFacts(_ index: Int) -> [InstantTriple] {
    ["blue", "green", "red"].map { fact(index, "items/tags", .string("\($0) \(index)")) }
  }

  /// A list query's key as the runtime writes one: a namespace, a filter on a page of ids, as long as `length`.
  static func listKey(_ label: String, length: Int) -> String {
    var ids: [String] = []
    var key = ""
    repeat {
      ids.append("\"" + String(format: "%08lx-0000-4000-8000-%012lx", ids.count, ids.count) + "\"")
      key = "{\"items\":{\"$\":{\"where\":{\"id\":{\"$in\":["
        + ids.joined(separator: ",") + "]}}}},\"page\":\"\(label)\"}"
    } while key.utf8.count < length
    return key
  }

  static let firstPageTriples = (0..<300).flatMap { [idFact($0), titleFact($0)] }
  static let secondPageTriples = (200..<400).flatMap { [idFact($0), titleFact($0)] }
  static let tagTriples = (350..<360).flatMap { [idFact($0)] + tagFacts($0) }

  /// Every fact a result holds, once, then facts no result holds, and an identity insert of an entity none holds.
  static let probes: [InstantTriple] = {
    var seen: Set<String> = []
    var probes: [InstantTriple] = []
    for triple in firstPageTriples + secondPageTriples + tagTriples {
      let identity = "\(triple.entityID)|\(triple.attributeID)|\(triple.value)"
      if seen.insert(identity).inserted { probes.append(triple) }
    }
    probes.append(fact(999, "items/title", .string("A title no result holds")))
    probes.append(fact(5, "items/title", .string("Another title for an item a result holds")))
    probes.append(idFact(999))
    return probes
  }()

  /// One probe per slot (entity and attribute), for #445's read.
  static let slots: [InstantTriple] = {
    var seen: Set<String> = []
    return probes.filter { seen.insert("\($0.entityID)|\($0.attributeID)").inserted }
  }()

  static func temporaryDirectory(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "InstantLiveQueryCompactOwnershipTests-\(name)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func result(
    _ key: String,
    _ triples: [InstantTriple],
    at milliseconds: Int64
  ) -> InstantPersistedLiveQueryResult {
    InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(key: key, triples: triples, pageInfo: nil),
      updatedAt: InstantTimestamp(milliseconds: milliseconds)
    )
  }

  /// The four results, their facts, and two pending writes, written through the library.
  static func seeded(name: String) async throws -> Self {
    let directory = try temporaryDirectory(name)
    let url = directory.appending(path: "instant.sqlite")
    let pending = [
      InstantStoreTransaction(id: "pending-title-5", operations: [.insert(fact(5, "items/title", .string("Renamed")))]),
      InstantStoreTransaction(id: "pending-item-1000", operations: [.insert(idFact(1_000)), .insert(titleFact(1_000))]),
    ].enumerated().map { offset, transaction in
      PendingMutation(
        id: transaction.id,
        createdAt: InstantTimestamp(milliseconds: stamp + 30 + Int64(offset)),
        transaction: transaction
      )
    }
    try await seed(
      url,
      facts: (0..<400).flatMap { [idFact($0), titleFact($0)] } + (350..<360).flatMap(tagFacts),
      outbox: pending,
      results: [
        result(firstPageKey, firstPageTriples, at: stamp),
        result(secondPageKey, secondPageTriples, at: stamp + 10),
        result(tagsKey, tagTriples, at: stamp + 20),
        result(emptyKey, [], at: stamp + 5),
      ]
    )
    return Self(directory: directory, url: url)
  }

  /// One result with a key of `keyLength` bytes over `itemCount` items, two facts each.
  static func seededWithOneResult(name: String, keyLength: Int, itemCount: Int) async throws -> Self {
    let directory = try temporaryDirectory(name)
    let url = directory.appending(path: "instant.sqlite")
    let triples = (0..<itemCount).flatMap { [idFact($0), titleFact($0)] }
    try await seed(
      url,
      facts: triples,
      outbox: [],
      results: [result(listKey(name, length: keyLength), triples, at: stamp)]
    )
    return Self(directory: directory, url: url)
  }

  static func seed(
    _ url: URL,
    facts: [InstantTriple],
    outbox: [PendingMutation],
    results: [InstantPersistedLiveQueryResult]
  ) async throws {
    let store = try SQLitePersistenceStore(fileURL: url)
    try await store.bootstrap()
    try await store.saveSnapshot(
      InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: attributes, triples: facts), outbox: outbox)
    )
    let seeded = try await store.loadState()
    let saved = try await store.saveLiveRefresh(
      seeded.snapshot,
      queryResults: results,
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "test.compact-ownership",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: stamp),
      expectedStoreRevision: seeded.storeRevision,
      expectedOutboxRevision: seeded.outboxRevision,
      expectedAttributeRevision: seeded.attributeRevision
    )
    try #require(saved)
  }

  /// A store in 0011's layout written row by row: `resultCount` results over overlapping pages of `itemsPerResult`
  /// items, two facts each, with keys of `keyLength` bytes.
  static func oldLayoutWithManyRows(
    name: String,
    resultCount: Int,
    itemsPerResult: Int,
    keyLength: Int
  ) async throws -> Self {
    let directory = try temporaryDirectory(name)
    let url = directory.appending(path: "instant.sqlite")
    let store = try SQLitePersistenceStore(fileURL: url)
    try await store.bootstrap()
    let fixture = Self(directory: directory, url: url)
    try fixture.rewriteIn0011Layout()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let database = try SQLiteFile.open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    try SQLiteFile.execute(database, "BEGIN IMMEDIATE")
    for resultIndex in 0..<resultCount {
      let key = listKey("page-\(resultIndex)", length: keyLength)
      let first = resultIndex * (itemsPerResult - 50)
      let triples = (first..<(first + itemsPerResult)).flatMap { [idFact($0), titleFact($0)] }
      let json = String(
        decoding: try encoder.encode(result(key, triples, at: stamp + Int64(resultIndex))),
        as: UTF8.self
      )
      try SQLiteFile.run(
        database,
        "INSERT INTO instant_live_query_results (query_key, triple_count, updated_at_ms, json) VALUES (?, ?, ?, ?)",
        [key, String(triples.count), String(stamp + Int64(resultIndex)), json]
      )
      for triple in triples {
        try SQLiteFile.run(
          database,
          "INSERT INTO instant_live_query_triples (query_key, entity_id, attribute_id, value_json) VALUES (?, ?, ?, ?)",
          [key, triple.entityID, triple.attributeID, String(decoding: try encoder.encode(triple.value), as: UTF8.self)]
        )
      }
    }
    try SQLiteFile.execute(database, "COMMIT")
    return fixture
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }

  /// Puts the live-query tables back in migration 0011's layout, every row kept, and removes the conversion's ledger
  /// row, as a store an earlier version wrote has them. A store already in that layout is left alone. Each result's
  /// JSON is its whole result again, built from its rows, as such a store held it (#1426 empties it).
  func rewriteIn0011Layout() throws {
    let columns = try SQLiteFile.strings(url, "SELECT name FROM pragma_table_info('instant_live_query_triples')")
    guard columns.contains("query_id") else { return }
    let wholeResult = """
      json_object(
        'key', result.query_key,
        'pageInfo', json(result.page_info_json),
        'triples', (
          SELECT json_group_array(json(\(InstantStoredLiveQueryResultRows.factJSON(unstoredTransactionID: "''"))))
          \(InstantStoredLiveQueryResultRows.ownedFacts(ofQueryID: "result.query_id"))
        ),
        'updatedAt', json_object('milliseconds', result.updated_at_ms)
      )
      """
    try SQLiteFile.execute(
      url,
      """
      PRAGMA foreign_keys = OFF;
      BEGIN IMMEDIATE;
      CREATE TEMP TABLE results_704 AS
        SELECT query_key, triple_count, updated_at_ms, \(wholeResult) AS json FROM instant_live_query_results AS result;
      CREATE TEMP TABLE ownership_704 AS
        SELECT result.query_key, owned.entity_id, owned.attribute_id, owned.value_json
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results AS result ON result.query_id = owned.query_id;
      DROP TABLE instant_live_query_triples;
      DROP TABLE instant_live_query_results;
      CREATE TABLE IF NOT EXISTS instant_live_query_results (
        query_key TEXT PRIMARY KEY NOT NULL,
        triple_count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        json TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS instant_live_query_triples (
        query_key TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        attribute_id TEXT NOT NULL,
        value_json TEXT NOT NULL,
        PRIMARY KEY (query_key, entity_id, attribute_id, value_json),
        FOREIGN KEY (query_key) REFERENCES instant_live_query_results (query_key)
          ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS instant_live_query_triples_identity_idx
      ON instant_live_query_triples (entity_id, attribute_id, value_json, query_key);
      INSERT INTO instant_live_query_results SELECT * FROM temp.results_704;
      INSERT INTO instant_live_query_triples SELECT * FROM temp.ownership_704;
      DROP TABLE temp.results_704;
      DROP TABLE temp.ownership_704;
      DELETE FROM instant_schema_migrations WHERE name = '0026_live_query_compact_ownership';
      COMMIT;
      PRAGMA foreign_keys = ON;
      """
    )
  }

  /// A copy of the store's files taken while a conversion's transaction has done its first steps and not committed:
  /// the WAL holds those pages without a commit, as a crash at that moment leaves it. The source stays as it was.
  func copyTakenDuringAnUncommittedConversion() throws -> URL {
    let target = directory.appending(path: "crashed", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let database = try SQLiteFile.open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    // Nothing committed waits in the WAL, and a small page cache spills the transaction's pages into it (SQLite spills
    // only past `cache_spill` pages, 20,000 by default, so the threshold comes down too).
    try SQLiteFile.execute(
      database,
      "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA cache_size = 4; PRAGMA cache_spill = 1; PRAGMA foreign_keys = ON;"
    )
    try SQLiteFile.execute(
      database,
      """
      BEGIN IMMEDIATE;
      CREATE TABLE instant_live_query_results_0026 (
        query_id INTEGER PRIMARY KEY,
        query_key TEXT NOT NULL UNIQUE,
        triple_count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        json TEXT NOT NULL
      );
      INSERT INTO instant_live_query_results_0026 (query_key, triple_count, updated_at_ms, json)
        SELECT query_key, triple_count, updated_at_ms, json FROM instant_live_query_results ORDER BY query_key;
      CREATE TEMP TABLE instant_live_query_triples_0026 AS
        SELECT result.query_id AS query_id, owned.entity_id AS entity_id,
          owned.attribute_id AS attribute_id, owned.value_json AS value_json
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results_0026 AS result ON result.query_key = owned.query_key;
      DROP TABLE instant_live_query_triples;
      """
    )
    for suffix in ["", "-wal"] {
      try FileManager.default.copyItem(
        at: URL(fileURLWithPath: url.path + suffix),
        to: target.appending(path: url.lastPathComponent + suffix)
      )
    }
    try SQLiteFile.execute(database, "ROLLBACK")
    return target.appending(path: url.lastPathComponent)
  }

  /// Both stores prune the first page away and store a narrower second page.
  func applyTheSameChanges(to store: SQLitePersistenceStore) async throws -> [String] {
    let pruned = try await store.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(),
      now: InstantTimestamp(milliseconds: Self.stamp + 40),
      preservingQueryKeys: [Self.secondPageKey, Self.tagsKey, Self.emptyKey]
    )
    let state = try await store.loadState()
    let narrowed = Self.result(
      Self.secondPageKey,
      (250..<400).flatMap { [Self.idFact($0), Self.titleFact($0)] },
      at: Self.stamp + 50
    )
    let saved = try await store.saveLiveRefresh(
      state.snapshot,
      queryResults: [narrowed],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "test.compact-ownership",
      metadataValue: "narrowed",
      metadataUpdatedAt: InstantTimestamp(milliseconds: Self.stamp + 50),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let removed = pruned.result.removedQueryKeys.map(Self.label(of:))
    let remaining = pruned.result.remainingQueryKeys.map(Self.label(of:)).sorted()
    return ["pruned \(removed) \(remaining) \(pruned.result.removedOrphanedTripleCount)", "narrowed \(saved)"]
  }

  /// Every ownership row as `key, entity, attribute, value`, sorted, in whichever layout the store has.
  func ownershipRows() throws -> [String] {
    try SQLiteFile.strings(url, try ownershipRowsSQL())
  }

  func ownershipRowsSQL() throws -> String {
    let columns = try SQLiteFile.strings(url, "SELECT name FROM pragma_table_info('instant_live_query_triples')")
    return columns.contains("query_id")
      ? """
        SELECT result.query_key || char(31) || owned.entity_id || char(31) || owned.attribute_id || char(31)
          || owned.value_json
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results AS result ON result.query_id = owned.query_id
        ORDER BY 1
        """
      : """
        SELECT query_key || char(31) || entity_id || char(31) || attribute_id || char(31) || value_json
        FROM instant_live_query_triples
        ORDER BY 1
        """
  }

  // A result's `json` is empty once the store opens with #1426, which converts it, so it is left out.
  static let resultRowsSQL = """
    SELECT query_key || char(31) || triple_count || char(31) || updated_at_ms
    FROM instant_live_query_results
    ORDER BY query_key
    """

  func resultRows() throws -> [String] {
    try SQLiteFile.strings(url, Self.resultRowsSQL)
  }

  /// The ownership rows' count and digest, in whichever layout the store has.
  func ownershipDigest() throws -> SQLiteFile.Digest {
    try SQLiteFile.digest(url, try ownershipRowsSQL())
  }

  /// Every column of every outbox row.
  func outboxRows() throws -> [String] {
    try SQLiteFile.rows(url, "SELECT * FROM instant_outbox ORDER BY mutation_id").map { $0.joined(separator: "\u{1F}") }
  }

  static let factRowsSQL = "SELECT * FROM instant_triples ORDER BY entity_id, attribute_id, value_json"

  func factRows() throws -> [String] {
    try SQLiteFile.rows(url, Self.factRowsSQL).map { $0.joined(separator: "\u{1F}") }
  }

  func ledgerRowCount() throws -> Int {
    Int(
      try SQLiteFile.strings(
        url,
        "SELECT COUNT(*) FROM instant_schema_migrations WHERE name = '0026_live_query_compact_ownership'"
      ).first ?? ""
    ) ?? -1
  }

  /// The calling thread's CPU clock and the wall clock, in nanoseconds.
  static func clocks() -> (cpu: UInt64, wall: UInt64) {
    (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID), clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
  }

  /// The CPU time of the calling thread and the wall time since `start`, in milliseconds.
  static func elapsed(since start: (cpu: UInt64, wall: UInt64)) -> (cpuMilliseconds: Int, wallMilliseconds: Int) {
    let now = clocks()
    return (Int((now.cpu - start.cpu) / 1_000_000), Int((now.wall - start.wall) / 1_000_000))
  }

  /// `bootstrap()` on the store's own executor, measured there.
  static func measuredBootstrap(
    _ store: SQLitePersistenceStore
  ) async throws -> (cpuMilliseconds: Int, wallMilliseconds: Int) {
    try await store.run { store in
      let start = CompactOwnershipFixture.clocks()
      try store.bootstrap()
      return CompactOwnershipFixture.elapsed(since: start)
    }
  }
}

// MARK: - Layout and bytes

/// The live-query tables' shape, from SQLite's own description of them.
struct OwnershipLayout: Equatable {
  var resultColumns: [String]
  var ownershipColumns: [String]
  var ownershipIsWithoutRowID: Bool
  var ownershipForeignKeys: [String]
  /// The b-trees that hold the ownership table and its indexes.
  var ownershipBTrees: [String]
  var identityIndexColumns: [String]

  static let compact = Self(
    // A result's page info has its own column since #1426, and its `json` is empty.
    resultColumns: [
      "query_id INTEGER 0 1", "query_key TEXT 1 0", "triple_count INTEGER 1 0", "updated_at_ms INTEGER 1 0",
      "json TEXT 1 0", "page_info_json TEXT 0 0",
    ],
    ownershipColumns: ["query_id INTEGER 1 1", "entity_id TEXT 1 2", "attribute_id TEXT 1 3", "value_json TEXT 1 4"],
    ownershipIsWithoutRowID: true,
    ownershipForeignKeys: ["query_id instant_live_query_results query_id CASCADE"],
    ownershipBTrees: ["instant_live_query_triples", "instant_live_query_triples_identity_idx"],
    identityIndexColumns: ["entity_id", "attribute_id", "value_json", "query_id"]
  )

  static func read(_ url: URL) throws -> Self {
    func columns(_ table: String) throws -> [String] {
      try SQLiteFile.rows(url, "SELECT name, type, \"notnull\", pk FROM pragma_table_info('\(table)') ORDER BY cid")
        .map { $0.joined(separator: " ") }
    }
    let sql = try SQLiteFile.strings(url, "SELECT sql FROM sqlite_master WHERE name = 'instant_live_query_triples'")
    return Self(
      resultColumns: try columns("instant_live_query_results"),
      ownershipColumns: try columns("instant_live_query_triples"),
      ownershipIsWithoutRowID: sql.first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        .hasSuffix("WITHOUT ROWID") == true,
      ownershipForeignKeys: try SQLiteFile.rows(
        url,
        "SELECT \"from\", \"table\", \"to\", on_delete FROM pragma_foreign_key_list('instant_live_query_triples')"
      ).map { $0.joined(separator: " ") },
      ownershipBTrees: try SQLiteFile.strings(
        url,
        "SELECT name FROM sqlite_master WHERE tbl_name = 'instant_live_query_triples' AND rootpage > 0 ORDER BY name"
      ),
      identityIndexColumns: try SQLiteFile.strings(
        url,
        "SELECT name FROM pragma_index_info('instant_live_query_triples_identity_idx') ORDER BY seqno"
      )
    )
  }

  /// Each live-query b-tree's root page: a rebuilt table or index gets new ones.
  static func rootPages(_ url: URL) throws -> [String] {
    try SQLiteFile.rows(
      url,
      """
      SELECT name, rootpage FROM sqlite_master
      WHERE tbl_name IN ('instant_live_query_triples', 'instant_live_query_results')
      ORDER BY name
      """
    ).map { $0.joined(separator: " ") }
  }
}

enum OwnershipBytes {
  /// The pages of the ownership table and its indexes (SQLite's `dbstat`), and its rows.
  static func read(_ url: URL) throws -> (bytes: Int, rows: Int) {
    let bytes = try SQLiteFile.strings(
      url,
      """
      SELECT COALESCE(SUM(pgsize), 0) FROM dbstat
      WHERE name IN (SELECT name FROM sqlite_master WHERE tbl_name = 'instant_live_query_triples')
      """
    )
    let rows = try SQLiteFile.strings(url, "SELECT COUNT(*) FROM instant_live_query_triples")
    return (Int(bytes.first ?? "") ?? -1, Int(rows.first ?? "") ?? -1)
  }

  /// Each live-query b-tree's bytes, largest first.
  static func liveQueryTableBytes(_ url: URL) throws -> String {
    try SQLiteFile.rows(
      url,
      """
      SELECT name, SUM(pgsize) FROM dbstat
      WHERE name IN (
        SELECT name FROM sqlite_master
        WHERE tbl_name IN ('instant_live_query_triples', 'instant_live_query_results')
      )
      GROUP BY name ORDER BY 2 DESC
      """
    ).map { "\($0[0]) \($0[1])" }.joined(separator: ", ")
  }

  static func fileBytes(_ url: URL) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? -1
  }

  static func freelistBytes(_ url: URL) throws -> Int {
    let pages = Int(try SQLiteFile.strings(url, "PRAGMA freelist_count").first ?? "") ?? 0
    let pageSize = Int(try SQLiteFile.strings(url, "PRAGMA page_size").first ?? "") ?? 0
    return pages * pageSize
  }
}

// MARK: - The statements of 1.9.10, for a device's store

/// The ownership reads as the library made them before this change, run on a store in 0011's layout, and the probes
/// they answer: every fact an ownership row holds, each slot, each result's key, each attribute.
enum LegacyOwnershipReads {
  struct Probes {
    var keys: [String]
    var facts: [InstantTriple]
    /// For each fact, one key that owns it (to exclude).
    var owners: [String]
    var thresholds: [Int64]
    var slots: [InstantTriple]
    var attributeIDs: [String]
    var attributes: AttributeStore

    /// A key's place among `keys`, so an answer names it in a few bytes.
    func label(of key: String) -> String {
      keys.firstIndex(of: key).map { "K\($0)" } ?? key
    }
  }

  static func answers(_ url: URL) throws -> (probes: Probes, answers: CompactOwnershipAnswers) {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let database = try SQLiteFile.open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    let attributes = AttributeStore(
      attributes: try SQLiteFile.rows(database, "SELECT json FROM instant_attributes ORDER BY id").map {
        try decoder.decode(InstantAttribute.self, from: Data($0[0].utf8))
      }
    )
    let keys = try SQLiteFile.rows(database, "SELECT query_key FROM instant_live_query_results ORDER BY query_key")
      .map { $0[0] }
    let identities = try SQLiteFile.rows(
      database,
      """
      SELECT entity_id, attribute_id, value_json, MIN(query_key) FROM instant_live_query_triples
      GROUP BY entity_id, attribute_id, value_json ORDER BY entity_id, attribute_id, value_json
      """
    )
    let facts = try identities.map { row in
      InstantTriple(
        entityID: row[0],
        attributeID: row[1],
        value: try decoder.decode(InstantValue.self, from: Data(row[2].utf8)),
        txID: "probe",
        txTime: InstantTimestamp(milliseconds: 0)
      )
    }
    let stamps = try SQLiteFile.rows(database, "SELECT updated_at_ms FROM instant_live_query_results ORDER BY 1")
      .compactMap { Int64($0[0]) }
    let thresholds: [Int64] = [0, stamps.isEmpty ? 0 : stamps[stamps.count / 2]]
    var seenSlots: Set<String> = []
    let slots = facts.filter { seenSlots.insert("\($0.entityID)|\($0.attributeID)").inserted }
    let attributeIDs = try SQLiteFile.rows(
      database,
      "SELECT DISTINCT attribute_id FROM instant_live_query_triples ORDER BY 1"
    ).map { $0[0] }
    let probes = Probes(
      keys: keys,
      facts: facts,
      owners: identities.map { $0[3] },
      thresholds: thresholds,
      slots: slots,
      attributeIDs: attributeIDs,
      attributes: attributes
    )

    var lines: [String] = []
    for (keyIndex, key) in keys.enumerated() {
      for row in try SQLiteFile.rows(
        database,
        "SELECT entity_id, attribute_id, value_json FROM instant_live_query_triples WHERE query_key = ?",
        [key]
      ).sorted(by: { ($0[0], $0[1], $0[2]) < ($1[0], $1[1], $1[2]) }) {
        lines.append("ownership \(keyIndex) \(row.joined(separator: " "))")
      }
    }
    for (index, fact) in facts.enumerated() {
      let valueJSON = String(decoding: try encoder.encode(fact.value), as: UTF8.self)
      for exclusion in [[], [probes.owners[index]]] as [[String]] {
        var sql = "SELECT query_key FROM instant_live_query_triples"
          + " WHERE entity_id = ? AND attribute_id = ? AND value_json = ?"
        if !exclusion.isEmpty { sql += " AND query_key NOT IN (?)" }
        sql += " LIMIT 1"
        let bindings = [fact.entityID, fact.attributeID, valueJSON] + exclusion
        let owned = !(try SQLiteFile.rows(database, sql, bindings)).isEmpty
        lines.append("owned \(index) \(exclusion.count) \(owned)")
      }
      let attribute = attributes[fact.attributeID]
      for threshold in thresholds {
        let shown: [[String]]
        if attribute?.primaryKey == true || attribute?.name == "id", fact.value == .string(fact.entityID) {
          shown = try SQLiteFile.rows(
            database,
            """
            SELECT MAX(result.updated_at_ms)
            FROM instant_live_query_triples AS owned
            JOIN instant_live_query_results AS result ON result.query_key = owned.query_key
            WHERE owned.entity_id = ? AND result.updated_at_ms >= ?
            """,
            [fact.entityID, String(threshold)]
          )
        } else {
          shown = try SQLiteFile.rows(
            database,
            """
            SELECT MAX(result.updated_at_ms)
            FROM instant_live_query_triples AS owned
            JOIN instant_live_query_results AS result ON result.query_key = owned.query_key
            WHERE owned.entity_id = ? AND owned.attribute_id = ? AND owned.value_json = ?
              AND result.updated_at_ms >= ?
            """,
            [fact.entityID, fact.attributeID, valueJSON, String(threshold)]
          )
        }
        let value = shown.first?.first.flatMap { $0 == "NULL" ? nil : $0 } ?? "none"
        lines.append("showing \(index) \(threshold) \(value)")
      }
    }
    for (index, slot) in slots.enumerated() {
      var values: [InstantValue] = []
      if let key = try SQLiteFile.rows(
        database,
        """
        SELECT owned.query_key
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results AS result ON result.query_key = owned.query_key
        WHERE owned.entity_id = ? AND owned.attribute_id = ?
        ORDER BY result.updated_at_ms DESC, owned.query_key
        LIMIT 1
        """,
        [slot.entityID, slot.attributeID]
      ).first?.first {
        values = try SQLiteFile.rows(
          database,
          """
          SELECT value_json FROM instant_live_query_triples
          WHERE query_key = ? AND entity_id = ? AND attribute_id = ?
          ORDER BY value_json
          LIMIT 32
          """,
          [key, slot.entityID, slot.attributeID]
        ).map { try decoder.decode(InstantValue.self, from: Data($0[0].utf8)) }
      }
      lines.append("values \(index) \(String(decoding: try encoder.encode(values), as: UTF8.self))")
    }
    for attributeID in attributeIDs {
      let keys = try SQLiteFile.rows(
        database,
        """
        SELECT result.query_key FROM instant_live_query_results AS result
        WHERE EXISTS (
          SELECT 1 FROM instant_live_query_triples AS owned
          WHERE owned.query_key = result.query_key AND owned.attribute_id IN (?)
        )
        ORDER BY result.query_key
        """,
        [attributeID]
      ).map { $0[0] }
      lines.append("migration \(attributeID) \(keys.map { probes.label(of: $0) }.joined(separator: " "))")
    }
    let loaded = try SQLiteFile.rows(
      database,
      "SELECT COUNT(*), COUNT(DISTINCT entity_id) FROM instant_live_query_triples"
    )
    lines.append("retained \(loaded.first?.joined(separator: " ") ?? "")")
    return (probes, CompactOwnershipAnswers(lines: lines))
  }

  /// The same reads, answered by the library.
  static func libraryAnswers(
    _ store: SQLitePersistenceStore,
    url: URL,
    probes: Probes
  ) async throws -> CompactOwnershipAnswers {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var lines: [String] = []
    for (keyIndex, key) in probes.keys.enumerated() {
      for row in try await store.liveQueryOwnershipForTesting(queryKey: key) {
        lines.append("ownership \(keyIndex) \(row.joined(separator: " "))")
      }
    }
    for (index, fact) in probes.facts.enumerated() {
      for exclusion in [[], [probes.owners[index]]] as [[String]] {
        let owned = try await store.liveQueryTripleHasOwnerForTesting(fact, excludingQueryKeys: Set(exclusion))
        lines.append("owned \(index) \(exclusion.count) \(owned)")
      }
      for threshold in probes.thresholds {
        let shown = try await store.newestServerResultShowingForTesting(
          fact,
          attributes: probes.attributes,
          storedAtOrAfter: threshold
        )
        lines.append("showing \(index) \(threshold) \(shown.map { String($0) } ?? "none")")
      }
    }
    for (index, slot) in probes.slots.enumerated() {
      let values = try await store.newestServerValuesForTesting(of: slot)
      lines.append("values \(index) \(String(decoding: try encoder.encode(values), as: UTF8.self))")
    }
    for attributeID in probes.attributeIDs {
      let keys = try await store.applicationMigrationLiveQueryResultKeysForTesting(affectedAttributeIDs: [attributeID])
      lines.append("migration \(attributeID) \(keys.map { probes.label(of: $0) }.joined(separator: " "))")
    }
    let loaded = try SQLiteFile.rows(url, "SELECT COUNT(*), COUNT(DISTINCT entity_id) FROM instant_live_query_triples")
    lines.append("retained \(loaded.first?.joined(separator: " ") ?? "")")
    return CompactOwnershipAnswers(lines: lines)
  }
}

// MARK: - SQLite

struct SQLiteFileError: Error, CustomStringConvertible {
  var description: String
}

/// Plain SQLite connections to a test store, beside the store's own.
enum SQLiteFile {
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
      sqlite3_close(database)
      throw SQLiteFileError(description: "open \(url.lastPathComponent): \(message)")
    }
    sqlite3_busy_timeout(database, 10_000)
    return database
  }

  static func rows(_ url: URL, _ sql: String, _ bindings: [String] = []) throws -> [[String]] {
    let database = try open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    return try rows(database, sql, bindings)
  }

  static func strings(_ url: URL, _ sql: String, _ bindings: [String] = []) throws -> [String] {
    try rows(url, sql, bindings).map { $0.first ?? "NULL" }
  }

  static func rows(_ database: OpaquePointer, _ sql: String, _ bindings: [String] = []) throws -> [[String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw SQLiteFileError(description: "prepare: \(String(cString: sqlite3_errmsg(database))) in \(sql)")
    }
    defer { sqlite3_finalize(statement) }
    for (index, binding) in bindings.enumerated() {
      sqlite3_bind_text(statement, Int32(index + 1), binding, -1, transient)
    }
    var rows: [[String]] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw SQLiteFileError(description: "step: \(String(cString: sqlite3_errmsg(database))) in \(sql)")
      }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "NULL"
        }
      )
    }
  }

  /// A row count and an FNV-1a digest of every column of every row, read one row at a time.
  struct Digest: Equatable, CustomStringConvertible {
    var rows: Int
    var hash: UInt64

    var description: String { "\(rows) rows, " + String(format: "%016llx", hash) }
  }

  static func digest(_ url: URL, _ sql: String) throws -> Digest {
    let database = try open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw SQLiteFileError(description: "prepare: \(String(cString: sqlite3_errmsg(database))) in \(sql)")
    }
    defer { sqlite3_finalize(statement) }
    var digest = Digest(rows: 0, hash: 0xcbf2_9ce4_8422_2325)
    func mix(_ byte: UInt8) {
      digest.hash ^= UInt64(byte)
      digest.hash = digest.hash &* 0x0000_0100_0000_01b3
    }
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return digest }
      guard code == SQLITE_ROW else {
        throw SQLiteFileError(description: "step: \(String(cString: sqlite3_errmsg(database))) in \(sql)")
      }
      digest.rows += 1
      for column in 0..<sqlite3_column_count(statement) {
        let type = sqlite3_column_type(statement, column)
        mix(UInt8(truncatingIfNeeded: type))
        if type != SQLITE_NULL, let bytes = sqlite3_column_blob(statement, column) {
          let buffer = UnsafeRawBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column)))
          for byte in buffer { mix(byte) }
        }
        mix(0x1F)
      }
      mix(0x1E)
    }
  }

  /// One statement with text bindings, on an open connection.
  static func run(_ database: OpaquePointer, _ sql: String, _ bindings: [String]) throws {
    _ = try rows(database, sql, bindings)
  }

  static func execute(_ url: URL, _ sql: String) throws {
    let database = try open(url, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close(database) }
    try execute(database, sql)
  }

  static func execute(_ database: OpaquePointer, _ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
      let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
      sqlite3_free(message)
      throw SQLiteFileError(description: "exec: \(text)")
    }
  }
}

// MARK: - Diagnostics

/// The conversion's log entries for one store.
private final class CompactionCapture: @unchecked Sendable {
  // SAFETY: `lock` protects `captured`.
  private let lock = NSLock()
  private let path: String
  private var captured: [InstantDiagnosticEntry] = []

  init(path: String) {
    self.path = path
  }

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.event == "sqlite.live-query-ownership.compacted", entry.metadata["path"] == path else { return }
    lock.withLock { captured.append(entry) }
  }

  var entries: [InstantDiagnosticEntry] {
    lock.withLock { captured }
  }
}
