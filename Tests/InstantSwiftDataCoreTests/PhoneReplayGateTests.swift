import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The phone-shaped replay gate (#296): a pulled device store drains its outbox through the verdicts the device really
/// got, against a model of Instant's server and with no transport, and the store is then compared with that server.
///
/// It runs only when `INSTANT_PHONE_REPLAY_STORE` is set, so ordinary suite runs skip it. Run it through
/// `scripts/phone-replay/run-phone-replay.sh`, which stages a credential-free copy of the store under `/tmp` and
/// deletes it afterwards; `scripts/phone-replay/README.md` has the inputs and the numbers to compare against.
///
/// - `INSTANT_PHONE_REPLAY_STORE`: the store, a `<appID>.sqlite` file or the directory holding one, with its `-wal`
///   and `-shm`. The replay works on a scratch copy and never writes here.
/// - `INSTANT_PHONE_REPLAY_REFUSALS` (required): the mutation ids the device saw refused, as a JSON object keyed by id
///   (what `scripts/phone-replay/refused-mutation-ids.py` writes), a JSON array, or one id per line. Every other
///   claimed write is accepted.
/// - `INSTANT_PHONE_REPLAY_FRAMES`: `list` (the default) restates only the entities and attributes of the store's
///   stored list and attachment results, as the list screen's refreshes do; `touched` restates every fact of the
///   entities each window touched, as with the transcript open.
/// - `INSTANT_PHONE_REPLAY_WINDOW`: claims per window, 50 by default.
/// - `INSTANT_PHONE_REPLAY_SCRATCH`: the directory for the scratch copy, the temporary directory by default.
/// - `INSTANT_PHONE_REPLAY_DEFERRED`: comma-separated deferred attribute IDs, Scribe's by default.
///
/// Frames and comparisons run in a fixed order, so two runs on the same inputs print the same lines apart from times.
@Suite(.serialized)
struct PhoneReplayGateTests {
  static let scribeDeferredAttributeIDs = [
    "recordingRouteChunks/samplesJSON", "sharedRecordings/timeline", "transcriptionSegments/text",
    "transcriptionSegments/wordsJSON", "recordings/locationRoute", "sharedRecordings/locationRoute",
  ]

  /// Tables whose rows can carry a credential: the session's refresh token, magic-code challenges, and share tokens.
  static let credentialTables = ["instant_auth_sessions", "instant_magic_code_challenges", "instant_shares"]

  static let safeToPrint: Set<String> = [
    "transcriptionSegments/isFinal", "transcriptionSegments/updatedAtMs", "transcriptionSegments/segmentIndex",
    "transcriptionSegments/wordCount", "transcriptionSegments/endTimeSeconds", "transcriptionSegments/sentToInstantAtMs",
    "recordings/updatedAtMs", "recordings/previewSegmentA", "recordings/previewSegmentB", "recordings/durationSeconds",
    "recordings/activityKind",
  ]

  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_PHONE_REPLAY_STORE"] != nil))
  func replayThePhonesDrainThroughItsVerdicts() async throws {
    let environment = ProcessInfo.processInfo.environment
    let store = try Self.storeFile(at: try #require(environment["INSTANT_PHONE_REPLAY_STORE"]))
    let refusals = try #require(
      environment["INSTANT_PHONE_REPLAY_REFUSALS"],
      "INSTANT_PHONE_REPLAY_REFUSALS must name the refused mutation ids (an empty file means none were refused)"
    )
    let refused = try Self.refusedMutationIDs(at: URL(fileURLWithPath: refusals))
    let windowSize = environment["INSTANT_PHONE_REPLAY_WINDOW"].flatMap(Int.init) ?? 50
    let frameShape = environment["INSTANT_PHONE_REPLAY_FRAMES"] ?? "list"
    try #require(frameShape == "list" || frameShape == "touched", "INSTANT_PHONE_REPLAY_FRAMES is list or touched")
    let deferred = InstantDeferredValueResidencyPolicy(
      attributeIDs: environment["INSTANT_PHONE_REPLAY_DEFERRED"].map { $0.split(separator: ",").map(String.init) }
        ?? Self.scribeDeferredAttributeIDs
    )
    let scratchDirectory = environment["INSTANT_PHONE_REPLAY_SCRATCH"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.temporaryDirectory
    let url = try Self.scratchCopy(of: store, in: scratchDirectory)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let selection = Self.storedSelection(url)
    let runtime = try await Self.runtime(url, appID: store.deletingPathExtension().lastPathComponent, deferred: deferred)
    let state = try await runtime.persistence.loadCompactState()
    let pendingAtStart = await runtime.pendingMutations().sorted(by: PendingMutation.creationOrder)
    let failedAtStart = try await runtime.persistence.countOutboxMutations(status: .failed)
    // Every device stamp in the copy, so the server's first-set times come after them, as the phone's first offers did.
    var newestDeviceStamp: Int64 = 0
    for triple in state.snapshot.store.triples { newestDeviceStamp = max(newestDeviceStamp, triple.txTime.milliseconds) }
    for mutation in pendingAtStart {
      for operation in mutation.transaction.operations {
        if case let .insert(triple) = operation { newestDeviceStamp = max(newestDeviceStamp, triple.txTime.milliseconds) }
      }
    }
    var server = PhoneReplayServer(attributes: state.snapshot.store.attributes, clock: newestDeviceStamp + 1_000)
    for result in try Self.storedResults(url) {
      for triple in result.triples {
        server.store(triple.entityID, triple.attributeID, triple.value, createdAt: triple.txTime.milliseconds)
      }
    }
    let pendingIDs = Set(pendingAtStart.map(\.id))
    print("REPLAY frames: \(frameShape); selection \(selection.mapValues(\.count).sorted { $0.key < $1.key })")
    print("REPLAY start: \(pendingAtStart.count) pending, \(failedAtStart) failed, \(refused.intersection(pendingIDs).count) of \(refused.count) refusals pending, window \(windowSize), newest device stamp \(newestDeviceStamp)")

    let claimantID = runtime.automaticDeliveryClaimantIDForTesting()
    var touchedEver: Set<String> = []
    var claimMilliseconds: Int64 = 1_790_900_000_000
    var window = 0
    var frames = 0
    var rebases = 0
    var bodies = 0
    var refusedCount = 0
    var acceptedCount = 0
    var verdictsNotApplied = 0
    var slowest: Duration = .zero
    var totalApply: Duration = .zero
    var allDeclines: [String: Int] = [:]
    let started = ContinuousClock.now
    let metricsAtStart = await runtime.persistence.serverApplyMetricsForTesting()
    var emptyClaims = 0
    while true {
      window += 1
      if window > pendingAtStart.count + 100 {
        let pending = try await runtime.persistence.countOutboxMutations(status: .pending)
        print("REPLAY stuck: \(pending) pending after \(window - 1) windows")
        break
      }
      let token = "phone-replay-\(window)"
      let claim = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: claimantID,
          claimToken: token,
          now: InstantTimestamp(milliseconds: claimMilliseconds),
          maximumMutationCount: windowSize
        )
      )
      claimMilliseconds += 1_000
      guard !claim.mutations.isEmpty else {
        let pending = try await runtime.persistence.countOutboxMutations(status: .pending)
        if pending == 0 { break }
        emptyClaims += 1
        claimMilliseconds += 10_000
        if emptyClaims > 5 { print("REPLAY stuck: \(pending) pending, claims empty"); break }
        continue
      }
      emptyClaims = 0
      var touched: Set<String> = []
      var windowRefusals = 0
      for mutation in claim.mutations {
        let transactionID = server.apply(mutation.transaction.operations)
        touched.formUnion(server.entities(of: mutation.transaction.operations))
        if refused.contains(mutation.id) {
          windowRefusals += 1
          let failed = try await runtime.failClaimedMutationForTesting(
            id: mutation.id, message: "Permission denied: not perms-pass?", claimToken: token
          )
          if failed == nil { verdictsNotApplied += 1 }
        } else {
          let accepted = try await runtime.acceptMutationIfPresent(
            id: mutation.id, serverTransactionID: transactionID, claimToken: token
          )
          if accepted == nil { verdictsNotApplied += 1 }
        }
      }
      refusedCount += windowRefusals
      acceptedCount += claim.mutations.count - windowRefusals
      touchedEver.formUnion(touched)
      let processed = String(server.lastTransactionNumber)
      let frame = frameShape == "list"
        ? server.listTriples(touching: touched, selection: selection, transactionID: processed)
        : server.triples(of: touched, transactionID: processed)
      let before = await runtime.persistence.serverApplyMetricsForTesting()
      let frameStarted = ContinuousClock.now
      let (_, declines) = try await FastDrainDeclineCounter.counting {
        try await runtime.applyServerTransactionMergingAttributesForTesting(
          InstantStoreTransaction(id: processed, operations: frame.map(InstantTripleOperation.insert)),
          attributesToMerge: []
        )
      }
      let elapsed = ContinuousClock.now - frameStarted
      let after = await runtime.persistence.serverApplyMetricsForTesting()
      frames += 1
      totalApply += elapsed
      slowest = max(slowest, elapsed)
      let planned = after.plannedComponentBodyCount - before.plannedComponentBodyCount
      bodies += planned
      if planned > 0 { rebases += 1 }
      for (reason, count) in declines { allDeclines[reason, default: 0] += count }
      let pending = try await runtime.persistence.countOutboxMutations(status: .pending)
      if windowRefusals > 0 || planned > 0 || window % 10 == 0 {
        print("REPLAY window \(window): claimed \(claim.mutations.count), refused \(windowRefusals), frame \(frame.count) facts in \(elapsed), bodies \(planned), removed +\(after.removedFailedOverlayCount - before.removedFailedOverlayCount), declines \(declines), pending \(pending)")
      }
      if pending == 0 { break }
    }
    let wall = ContinuousClock.now - started
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    let failedAtEnd = try await runtime.persistence.countOutboxMutations(status: .failed)
    let pendingAtEnd = try await runtime.persistence.countOutboxMutations(status: .pending)
    print("REPLAY drain: \(pendingAtStart.count) -> \(pendingAtEnd) pending in \(wall) wall (\(totalApply) applying), \(frames) frames, \(rebases) with a component rebase, \(bodies) bodies, slowest frame \(slowest); accepted \(acceptedCount), refused \(refusedCount); failed rows \(failedAtStart) -> \(failedAtEnd)")
    print("REPLAY reductions +\(metrics.reductionCount - metricsAtStart.reductionCount), reduced +\(metrics.reducedCount - metricsAtStart.reducedCount), receipt patches +\(metrics.receiptPatchCount - metricsAtStart.receiptPatchCount), refused overlays removed by the reduction +\(metrics.removedFailedOverlayCount - metricsAtStart.removedFailedOverlayCount)")
    print("REPLAY declines: \(allDeclines.sorted { ($0.value, $1.key) > ($1.value, $0.key) })")
    if !server.unsupported.isEmpty { print("REPLAY unsupported server operations: \(server.unsupported.sorted { $0.key < $1.key })") }
    if verdictsNotApplied > 0 { print("REPLAY verdicts that found no claimed write: \(verdictsNotApplied)") }

    // What the phone would show now: the frames above carried only the entities each window touched.
    _ = Self.compare(server: server, device: try Self.deviceFacts(url, server: server), entities: touchedEver, label: "after the drain")
    // Then one frame restating every entity the drain touched, as opening each screen would.
    server.lastTransactionNumber += 1
    let restatement = server.triples(of: touchedEver, transactionID: String(server.lastTransactionNumber), allLinks: true)
    let restated = ContinuousClock.now
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(id: String(server.lastTransactionNumber), operations: restatement.map(InstantTripleOperation.insert)),
      attributesToMerge: []
    )
    print("REPLAY restatement: \(restatement.count) facts in \(ContinuousClock.now - restated)")
    _ = Self.compare(server: server, device: try Self.deviceFacts(url, server: server), entities: touchedEver, label: "after a full restatement")

    // The gate's own invariants; the numbers themselves are compared against a reference log by
    // `scripts/phone-replay/compare-replay-logs.py`.
    #expect(pendingAtEnd == 0, "The replay must deliver every pending write")
    #expect(acceptedCount + refusedCount == pendingAtStart.count, "Each pending write must be claimed exactly once")
    #expect(refusedCount == refused.intersection(pendingIDs).count, "Each listed refusal still pending must be refused")
    #expect(server.unsupported.isEmpty, "The model server must understand every operation it applied")
  }
}

extension PhoneReplayGateTests {
  /// The store file, from a `<appID>.sqlite` path or the directory holding exactly one store.
  static func storeFile(at path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw PhoneReplayInputError(description: "No store at \(path)")
    }
    guard isDirectory.boolValue else { return url }
    let stores = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".sqlite") }
    guard stores.count == 1 else {
      throw PhoneReplayInputError(description: "Expected one .sqlite store in \(path), found \(stores.count)")
    }
    return url.appendingPathComponent(stores[0])
  }

  /// The refused mutation ids: a JSON object keyed by id, a JSON array of ids, or one id per line.
  static func refusedMutationIDs(at url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    if let object = try? JSONSerialization.jsonObject(with: data) {
      if let byID = object as? [String: Any] { return Set(byID.keys) }
      if let ids = object as? [String] { return Set(ids) }
      throw PhoneReplayInputError(description: "\(url.path) is JSON but neither an object keyed by id nor an array of ids")
    }
    return Set(
      String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    )
  }

  /// A scratch copy of the store beside nothing else, with every credential row deleted.
  static func scratchCopy(of store: URL, in directory: URL) throws -> URL {
    let target = directory.appendingPathComponent("phone-replay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    for suffix in ["", "-wal", "-shm"] {
      let from = URL(fileURLWithPath: store.path + suffix)
      if FileManager.default.fileExists(atPath: from.path) {
        try FileManager.default.copyItem(at: from, to: target.appendingPathComponent(from.lastPathComponent))
      }
    }
    let url = target.appendingPathComponent(store.lastPathComponent)
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw PhoneReplayInputError(description: "Cannot open the scratch copy of \(store.lastPathComponent)")
    }
    sqlite3_busy_timeout(database, 10_000)
    // The copy must never carry a usable session or any other credential.
    for table in credentialTables where tableExists(table, in: database) {
      guard sqlite3_exec(database, "DELETE FROM \(table);", nil, nil, nil) == SQLITE_OK else {
        throw PhoneReplayInputError(description: "Cannot delete the rows of \(table) in the scratch copy")
      }
    }
    return url
  }

  static func tableExists(_ table: String, in database: OpaquePointer?) -> Bool {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(
      database, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(table)'", -1, &statement, nil
    ) == SQLITE_OK else { return false }
    return sqlite3_step(statement) == SQLITE_ROW
  }

  static func runtime(
    _ url: URL, appID: String, deferred: InstantDeferredValueResidencyPolicy
  ) async throws -> InstantRuntime {
    let loader = try SQLitePersistenceStore(fileURL: url, deferredValueResidency: deferred)
    try await loader.bootstrap()
    let attributes = try await loader.loadCompactState().snapshot.store.attributes
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: attributes,
      deferredValueResidency: deferred
    )
    configuration.reducesServerApplyToAffectedOverlays = true
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  static func storedResults(_ url: URL) throws -> [InstantPersistedLiveQueryResult] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(database, "SELECT json FROM instant_live_query_results ORDER BY triple_count DESC", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    var results: [InstantPersistedLiveQueryResult] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let json = String(cString: sqlite3_column_text(statement, 0))
      results.append(try JSONDecoder().decode(InstantPersistedLiveQueryResult.self, from: Data(json.utf8)))
    }
    return results
  }

  /// The attributes the store's stored live-query results select, by namespace.
  static func storedSelection(_ url: URL) -> [String: Set<String>] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(database, "SELECT DISTINCT attribute_id FROM instant_live_query_triples", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    var selection: [String: Set<String>] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let attributeID = String(cString: sqlite3_column_text(statement, 0))
      guard let slash = attributeID.firstIndex(of: "/") else { continue }
      selection[String(attributeID[..<slash]), default: []].insert(attributeID)
    }
    return selection
  }

  /// The device's persisted facts in forward form, read from the scratch store.
  static func deviceFacts(_ url: URL, server: PhoneReplayServer) throws -> [String: [String: Set<InstantValue>]] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)
    var statement: OpaquePointer?
    sqlite3_prepare_v2(database, "SELECT entity_id, attribute_id, value_json FROM instant_triples", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    var facts: [String: [String: Set<InstantValue>]] = [:]
    let decoder = JSONDecoder()
    while sqlite3_step(statement) == SQLITE_ROW {
      let entityID = String(cString: sqlite3_column_text(statement, 0))
      let attributeID = String(cString: sqlite3_column_text(statement, 1))
      let json = String(cString: sqlite3_column_text(statement, 2))
      guard let value = try? decoder.decode(InstantValue.self, from: Data(json.utf8)) else { continue }
      let (e, a, v) = server.forward(entityID, attributeID, value)
      facts[e, default: [:]][a, default: []].insert(v)
    }
    return facts
  }

  /// Fields on the device that differ from the server, for the entities pending writes touched. Prints ids, attribute
  /// names, and counts; values only for the attributes in `safeToPrint`.
  static func compare(
    server: PhoneReplayServer, device: [String: [String: Set<InstantValue>]], entities: Set<String>, label: String
  ) -> [String: Int] {
    var missing: [String: Int] = [:]
    var stale: [String: Int] = [:]
    var absentField: [String: Int] = [:]
    var linkDifferences: [String: Int] = [:]
    var examples: [String] = []
    var compared = 0
    for entityID in entities.sorted() {
      guard let serverAttributes = server.facts[entityID],
        let idAttribute = serverAttributes.keys.first(where: { $0.hasSuffix("/id") && server.attributesByID[$0]?.name == "id" })
      else { continue }
      let namespace = String(idAttribute.dropLast(3))
      compared += 1
      guard device[entityID]?[idAttribute] != nil else {
        missing[namespace, default: 0] += 1
        if examples.count < 40 { examples.append("missing \(namespace) \(entityID.prefix(8))") }
        continue
      }
      for (attributeID, values) in serverAttributes.sorted(by: { $0.key < $1.key }) {
        let serverValues = Set(values.keys)
        let deviceValues = device[entityID]?[attributeID] ?? []
        if server.isMany(attributeID) {
          if !serverValues.isSubset(of: deviceValues) { linkDifferences[attributeID, default: 0] += 1 }
          continue
        }
        if deviceValues.isEmpty {
          absentField[attributeID, default: 0] += 1
          if examples.count < 40 { examples.append("absent \(attributeID) \(entityID.prefix(8))") }
        } else if deviceValues != serverValues {
          stale[attributeID, default: 0] += 1
          if examples.count < 40 {
            let shown = Self.safeToPrint.contains(attributeID)
              ? "device \(deviceValues.map { "\($0)" }.sorted()) server \(serverValues.map { "\($0)" }.sorted())"
              : "(values not printed)"
            examples.append("older \(attributeID) \(entityID.prefix(8)) \(shown)")
          }
        }
      }
    }
    print("REPLAY compare [\(label)]: \(compared) server entities compared")
    print("REPLAY compare [\(label)] missing entities by namespace: \(missing.sorted { $0.key < $1.key })")
    print("REPLAY compare [\(label)] fields with a different value: \(stale.values.reduce(0, +)) \(stale.sorted { $0.key < $1.key })")
    print("REPLAY compare [\(label)] fields absent on the device: \(absentField.values.reduce(0, +)) \(absentField.sorted { $0.key < $1.key })")
    print("REPLAY compare [\(label)] link sets missing server links: \(linkDifferences.sorted { $0.key < $1.key })")
    for example in examples { print("REPLAY example [\(label)] \(example)") }
    return stale
  }
}

struct PhoneReplayInputError: Error, CustomStringConvertible {
  var description: String
}

/// Instant's server as the replay needs it: every write applied in creation order, links stored in forward form, and a
/// cardinality-one slot keeping the time it was first set when its value changes (`triple.clj`
/// `ea-conflict-update-set` overwrites `created_at` only when `overwrite-t` is set, which only app streams do).
struct PhoneReplayServer {
  var facts: [String: [String: [InstantValue: Int64]]] = [:]
  var clock: Int64
  var lastTransactionNumber: Int64 = 2_900_000_000
  let attributesByID: [String: InstantAttribute]
  let forwardByReverseIdentity: [String: InstantAttribute]
  var unsupported: [String: Int] = [:]

  init(attributes: [InstantAttribute], clock: Int64) {
    self.clock = clock
    attributesByID = Dictionary(attributes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    forwardByReverseIdentity = Dictionary(
      attributes.compactMap { attribute in attribute.reverseIdentity.map { ($0, attribute) } },
      uniquingKeysWith: { first, _ in first }
    )
  }

  func forward(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> (String, String, InstantValue) {
    if attributesByID[attributeID] == nil, let forward = forwardByReverseIdentity[attributeID], case let .ref(target) = value {
      return (target, forward.id, .ref(entityID))
    }
    return (entityID, attributeID, value)
  }

  func isMany(_ attributeID: String) -> Bool { attributesByID[attributeID]?.cardinality == .many }

  mutating func store(_ entityID: String, _ attributeID: String, _ value: InstantValue, createdAt: Int64) {
    let (e, a, v) = forward(entityID, attributeID, value)
    if isMany(a) {
      if facts[e]?[a]?[v] == nil { facts[e, default: [:]][a, default: [:]][v] = createdAt }
    } else {
      let firstSet = facts[e]?[a]?.values.first ?? createdAt
      facts[e, default: [:]][a] = [v: firstSet]
    }
  }

  mutating func retract(_ entityID: String, _ attributeID: String, _ value: InstantValue) {
    let (e, a, v) = forward(entityID, attributeID, value)
    facts[e]?[a]?[v] = nil
    if facts[e]?[a]?.isEmpty == true { facts[e]?[a] = nil }
  }

  mutating func delete(_ entityID: String) {
    facts[entityID] = nil
    for (e, attributes) in facts {
      for (a, values) in attributes where values[.ref(entityID)] != nil {
        facts[e]?[a]?[.ref(entityID)] = nil
      }
    }
  }

  mutating func apply(_ operations: [InstantTripleOperation]) -> String {
    lastTransactionNumber += 1
    clock += 3
    for operation in operations {
      switch operation {
      case let .insert(triple): store(triple.entityID, triple.attributeID, triple.value, createdAt: clock)
      case let .retract(triple): retract(triple.entityID, triple.attributeID, triple.value)
      case let .deleteEntity(entityID): delete(entityID)
      case let .deleteEntityInNamespace(entityID, _): delete(entityID)
      case .requireEntityMissing, .requireEntityExists, .requireTripleExists, .ruleParams: continue
      default: unsupported[String("\(operation)".prefix(24)), default: 0] += 1
      }
    }
    return String(lastTransactionNumber)
  }

  /// The forward-form entities a write touches.
  func entities(of operations: [InstantTripleOperation]) -> Set<String> {
    var entities: Set<String> = []
    for operation in operations {
      switch operation {
      case let .insert(triple), let .retract(triple):
        let (e, _, v) = forward(triple.entityID, triple.attributeID, triple.value)
        entities.insert(e)
        entities.insert(triple.entityID)
        if case let .ref(target) = v { entities.insert(target) }
      case let .deleteEntity(entityID), let .deleteEntityInNamespace(entityID, _): entities.insert(entityID)
      default: continue
      }
    }
    return entities
  }

  func namespace(of entityID: String) -> String? {
    facts[entityID]?.keys.first { $0.hasSuffix("/id") && attributesByID[$0]?.name == "id" }.map { String($0.dropLast(3)) }
  }

  /// A list-screen frame, like the phone's stored results: the touched recordings and their two preview segments, and
  /// the touched attachments, with only the attributes those results select.
  func listTriples(touching entityIDs: Set<String>, selection: [String: Set<String>], transactionID: String) -> [InstantTriple] {
    var frameEntities: Set<String> = []
    for entityID in entityIDs {
      switch namespace(of: entityID) {
      case "recordings"?:
        frameEntities.insert(entityID)
        for slot in ["recordings/previewSegmentA", "recordings/previewSegmentB"] {
          for case let .ref(target) in facts[entityID]?[slot]?.keys.map({ $0 }) ?? [] { frameEntities.insert(target) }
        }
      case "recordingAttachments"?:
        frameEntities.insert(entityID)
      default:
        continue
      }
    }
    return triples(of: frameEntities, transactionID: transactionID).filter { triple in
      guard let namespace = namespace(of: triple.entityID) else { return false }
      return selection[namespace]?.contains(triple.attributeID) == true
    }
  }

  /// One frame: every fact of `entityIDs`, in entity, attribute, and value order; a link travels when its target is in
  /// the frame too, or `allLinks`.
  func triples(of entityIDs: Set<String>, transactionID: String, allLinks: Bool = false) -> [InstantTriple] {
    var triples: [InstantTriple] = []
    for entityID in entityIDs.sorted() {
      for (attributeID, values) in (facts[entityID] ?? [:]).sorted(by: { $0.key < $1.key }) {
        for (value, createdAt) in values.sorted(by: { "\($0.key)" < "\($1.key)" }) {
          if isMany(attributeID), !allLinks, case let .ref(target) = value, !entityIDs.contains(target) { continue }
          triples.append(InstantTriple(
            entityID: entityID, attributeID: attributeID, value: value, txID: transactionID,
            txTime: InstantTimestamp(milliseconds: createdAt)
          ))
        }
      }
    }
    return triples
  }
}
