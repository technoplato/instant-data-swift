import Foundation
import SQLite3

@testable import InstantSwiftDataCore

// #1072 (2026-10-24): a store shaped like a phone's, generated through the runtime's own API, for the whole-store cost
// audit's measurements and budgets and for the sibling audits (#1074 concurrency, #1075 memory, #1076 storage).
//
// The shape is a copy of one iPhone's store on 2026-10-24 (an always-on recorder after months of use), counted, never
// copied: 174,817 facts on disk (113,972 of them transcript lines), about 45,000 resident at launch, 2,283 attributes,
// 9,455 files the account holds in storage (75,640 facts, about 25 MB as one answer), 4,264 file records of the
// device's own uploads, 663 writes the server refused and 355 closed queries' results unloaded to disk. The generator
// writes what that phone wrote: its own recordings and transcript lines through `transact`, acknowledged by a scripted
// server; queries the server answers from the account it holds, some kept open (the resident set) and the rest closed
// and pruned (the unloaded results, the whole `$files` list among them); refused writes; upload records. Every id is
// derived from its index, so the account a session's server holds matches the generated store in any process.
//
// The generated store is cached under the temporary directory by fixture version, shape and the library's schema
// migrations, and each session opens a copy of it. A phone's own store can stand in for the generated one: set
// `INSTANT_REAL_SIZE_STORE` to a copy of it (never committed: its rows are someone's data); its account is not known,
// so the server answers from the generated account.
//
// History:
// - 2026-10-24: #1072: the fixture, its scripted server and storage, the cache.

/// How big the generated store is, in the dimensions that the library's costs depend on.
struct RealSizeShape: Sendable, Hashable, CustomStringConvertible {
  /// Recordings the account holds, each with a few attributes more than a line.
  var recordings = 352
  /// Transcript lines of each transcribed recording, longest first: the phone's 108 transcribed recordings.
  var transcriptLines: [Int] = RealSizeShape.phoneTranscriptLines
  /// Entities of the other namespaces the device wrote (runtime events, attachments, sounds, chunks, agents), 16 facts
  /// each.
  var otherEntities = 3_400
  /// Files the account holds in storage (`$files`), 8 facts each.
  var accountFiles = 9_455
  /// Records of the device's own uploads (`instant_files`).
  var deviceFileRecords = 4_264
  /// Writes the server refused, each a recording's update (`failed`, terminal).
  var refusedWrites = 663
  /// Queries open when the store closed, so their entities are resident at the next launch.
  var openQueries = 48
  /// Queries answered and closed, so the prune unloads their results.
  var closedQueries = 355
  /// Attributes of the app's schema.
  var attributes = 2_283

  /// The 2026-10-24 phone copy's counts.
  static let phone = RealSizeShape()

  /// Every dimension multiplied by `factor` (at least one of each), for checks that a cost does not grow with the
  /// store: the same operation on `.phone.scaled(0.25)` and on `.phone` should cost the same.
  func scaled(_ factor: Double) -> RealSizeShape {
    func scale(_ value: Int) -> Int { max(1, Int((Double(value) * factor).rounded())) }
    var shape = self
    shape.recordings = scale(recordings)
    let lines = transcriptLines.map(scale)
    shape.transcriptLines = Array(lines.prefix(max(1, Int((Double(lines.count) * factor).rounded()))))
    shape.otherEntities = scale(otherEntities)
    shape.accountFiles = scale(accountFiles)
    shape.deviceFileRecords = scale(deviceFileRecords)
    shape.refusedWrites = scale(refusedWrites)
    shape.openQueries = max(2, scale(openQueries))
    shape.closedQueries = max(2, scale(closedQueries))
    shape.attributes = max(RealSizeAccount.scribeAttributeCount, scale(attributes))
    return shape
  }

  var transcriptLineCount: Int { transcriptLines.reduce(0, +) }

  var description: String {
    "recordings=\(recordings) lines=\(transcriptLineCount) others=\(otherEntities) files=\(accountFiles)"
      + " fileRecords=\(deviceFileRecords) refused=\(refusedWrites) open=\(openQueries) closed=\(closedQueries)"
      + " attributes=\(attributes)"
  }

  /// The cache key: every dimension.
  var key: String {
    var hasher = RealSizeStableHash()
    for value in [recordings, otherEntities, accountFiles, deviceFileRecords, refusedWrites, openQueries, closedQueries,
                  attributes] + transcriptLines {
      hasher.combine(value)
    }
    return String(hasher.value, radix: 16)
  }

  /// The phone's transcribed recordings by line count (7,140 lines): eleven long ones and 97 short ones.
  static let phoneTranscriptLines: [Int] = [2_318, 909, 746, 606, 560, 399, 399, 292, 292, 292, 114]
    + Array(repeating: 21, count: 61) + Array(repeating: 14, count: 36)
}

/// FNV-1a over integers: the same in every process, unlike `Hasher`.
struct RealSizeStableHash {
  private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
  mutating func combine(_ integer: Int) {
    var integer = UInt64(bitPattern: Int64(integer))
    for _ in 0..<8 {
      value ^= integer & 0xff
      value &*= 0x100_0000_01b3
      integer >>= 8
    }
  }
  mutating func combine(_ string: String) {
    for byte in string.utf8 {
      value ^= UInt64(byte)
      value &*= 0x100_0000_01b3
    }
  }
}

/// The account the generated store belongs to, as the server holds it: derived from the shape alone.
struct RealSizeAccount: Sendable {
  static let appID = "real-size-app"
  static let userID = "real-size-user"
  static let refreshToken = "real-size-token"
  /// The fixed clock every generated fact carries: 2026-10-24 00:00 UTC.
  static let epoch = InstantTimestamp(milliseconds: 1_792_800_000_000)

  static let segmentFields = [
    "id", "recordingID", "transcriptionID", "ownerUserID", "segmentIndex", "text", "wordsJSON", "isFinal",
    "startTimeSeconds", "endTimeSeconds", "wallClockStartedAtMs", "wallClockEndedAtMs", "updatedAtMs",
    "sentToInstantAtMs", "speaker", "wordCount",
  ]
  static let recordingFields = [
    "id", "ownerUserID", "title", "startedAtMs", "updatedAtMs", "durationSeconds", "activityKind", "activityClientID",
    "audioFileURL", "buildInfo", "captureGapsJSON", "clipboardEntries", "deviceIcon", "location", "media", "owner",
    "speakers", "systemAudioContextEntries",
  ]
  static let fileFields = ["id", "path", "url", "content-type", "content-disposition", "location-id", "size", "key-version"]
  static let otherNamespaces = [
    "recordingRuntimeEvents", "recordingAttachments", "recordingSounds", "recordingAudioChunks", "agentFenceposts",
    "agentResponses", "agentThreads", "recordingSpeakers",
  ]
  static let otherFields = ["id", "recordingID", "ownerUserID", "kind", "createdAtMs", "updatedAtMs", "payloadJSON"]
    + (1...9).map { "field\($0)" }
  static var scribeAttributeCount: Int {
    segmentFields.count + recordingFields.count + fileFields.count + otherNamespaces.count * otherFields.count
  }

  let shape: RealSizeShape
  let attributes: [InstantAttribute]
  /// Entities by namespace, in index order.
  let entities: [String: [RealSizeEntity]]

  init(_ shape: RealSizeShape) {
    self.shape = shape
    var attributes: [InstantAttribute] = []
    func attribute(_ namespace: String, _ name: String, _ type: InstantValueType, indexed: Bool = true) {
      let unique = name == "id" || (namespace == "$files" && (name == "path" || name == "location-id"))
      attributes.append(
        InstantAttribute(
          id: "\(namespace)/\(name)", namespace: namespace, name: name, valueType: type, isRequired: false,
          isIndexed: indexed || unique, isUnique: unique, forwardIdentity: "\(namespace)/\(name)"
        )
      )
    }
    for field in Self.segmentFields {
      switch field {
      case "text", "wordsJSON": attribute("transcriptionSegments", field, .string, indexed: false)
      case "isFinal": attribute("transcriptionSegments", field, .boolean)
      case "id", "recordingID", "transcriptionID", "ownerUserID": attribute("transcriptionSegments", field, .string)
      default: attribute("transcriptionSegments", field, .number)
      }
    }
    for field in Self.recordingFields {
      switch field {
      case "startedAtMs", "updatedAtMs", "durationSeconds": attribute("recordings", field, .number)
      default: attribute("recordings", field, .string, indexed: field == "id" || field == "ownerUserID")
      }
    }
    for field in Self.fileFields {
      attribute("$files", field, field == "size" || field == "key-version" ? .number : .string)
    }
    for namespace in Self.otherNamespaces {
      for field in Self.otherFields {
        attribute(namespace, field, field.hasSuffix("Ms") ? .number : .string, indexed: !field.hasPrefix("field"))
      }
    }
    // The rest of the schema: namespaces the app declares that this account never wrote to.
    var filler = 0
    while attributes.count < shape.attributes {
      attribute("unusedNamespace\(filler / 16)", "field\(filler % 16)", .string, indexed: false)
      filler += 1
    }
    self.attributes = attributes

    var entities: [String: [RealSizeEntity]] = [:]
    let recordingIDs = (0..<shape.recordings).map { RealSizeID.make(.recording, $0) }
    entities["recordings"] = recordingIDs.enumerated().map { index, id in
      Self.recording(id: id, index: index)
    }
    var segments: [RealSizeEntity] = []
    for (recordingIndex, lineCount) in shape.transcriptLines.enumerated() {
      let recordingID = recordingIDs[recordingIndex % recordingIDs.count]
      for line in 0..<lineCount {
        segments.append(Self.segment(recordingID: recordingID, line: line, revision: 4, serial: segments.count))
      }
    }
    entities["transcriptionSegments"] = segments
    var others: [String: [RealSizeEntity]] = [:]
    for index in 0..<shape.otherEntities {
      let namespace = Self.otherNamespaces[index % Self.otherNamespaces.count]
      let id = RealSizeID.make(.other, index)
      var values: [String: InstantValue] = [:]
      for field in Self.otherFields {
        switch field {
        case "id": values[field] = .string(id)
        case "recordingID": values[field] = .string(recordingIDs[index % recordingIDs.count])
        case "ownerUserID": values[field] = .string(Self.userID)
        case "kind": values[field] = .string("kind-\(index % 7)")
        case "createdAtMs", "updatedAtMs": values[field] = .number(Double(Self.epoch.milliseconds - Int64(index) * 1_000))
        case "payloadJSON": values[field] = .string(String(repeating: "{\"k\":\(index)}", count: 6))
        default: values[field] = .string("\(field)-\(index)")
        }
      }
      others[namespace, default: []].append(RealSizeEntity(namespace: namespace, id: id, values: values))
    }
    for (namespace, list) in others { entities[namespace] = list }
    entities["$files"] = (0..<shape.accountFiles).map { Self.file(index: $0) }
    self.entities = entities
  }

  static func recording(id: String, index: Int) -> RealSizeEntity {
    let started = Double(epoch.milliseconds - Int64(index) * 3_600_000)
    var values: [String: InstantValue] = [:]
    for field in recordingFields {
      switch field {
      case "id": values[field] = .string(id)
      case "ownerUserID", "owner": values[field] = .string(userID)
      case "title": values[field] = .string("Recording \(index)")
      case "startedAtMs": values[field] = .number(started)
      case "updatedAtMs": values[field] = .number(started + 1_800_000)
      case "durationSeconds": values[field] = .number(1_800)
      case "captureGapsJSON", "clipboardEntries", "systemAudioContextEntries", "speakers", "media":
        values[field] = .string("[" + (0..<4).map { "{\"i\":\($0),\"r\":\"\(id)\"}" }.joined(separator: ",") + "]")
      default: values[field] = .string("\(field)-\(index)")
      }
    }
    return RealSizeEntity(namespace: "recordings", id: id, values: values)
  }

  /// A transcript line as Scribe writes it: sixteen facts, its words about 460 bytes of JSON once final.
  static func segment(recordingID: String, line: Int, revision: Int, serial: Int, id: String? = nil) -> RealSizeEntity {
    let id = id ?? RealSizeID.make(.segment, serial)
    let words = (0..<(4 + revision * 2)).map { "word\(($0 + line) % 37)" }
    let text = "line \(line) " + words.joined(separator: " ")
    let start = Double(line) * 4
    let wordsJSON =
      "[" + words.enumerated().map { offset, word in
        "{\"w\":\"\(word)\",\"s\":\(start + Double(offset) * 0.31),\"e\":\(start + Double(offset) * 0.31 + 0.28),\"c\":0.97}"
      }.joined(separator: ",") + "]"
    let wallClock = Double(epoch.milliseconds) + start * 1_000
    let values: [String: InstantValue] = [
      "id": .string(id),
      "recordingID": .string(recordingID),
      "transcriptionID": .string(recordingID),
      "ownerUserID": .string(userID),
      "segmentIndex": .number(Double(line)),
      "text": .string(text),
      "wordsJSON": .string(wordsJSON),
      "isFinal": .bool(revision >= 4),
      "startTimeSeconds": .number(start),
      "endTimeSeconds": .number(start + 3.9),
      "wallClockStartedAtMs": .number(wallClock),
      "wallClockEndedAtMs": .number(wallClock + 3_900),
      "updatedAtMs": .number(wallClock + 3_900 + Double(revision)),
      "sentToInstantAtMs": .number(wallClock + 3_900 + Double(revision)),
      "speaker": .number(Double(line % 3)),
      "wordCount": .number(Double(words.count + 2)),
    ]
    return RealSizeEntity(namespace: "transcriptionSegments", id: id, values: values)
  }

  static func file(index: Int) -> RealSizeEntity {
    let id = RealSizeID.make(.file, index)
    let path = "scribe/recording-\(index / 60)/generation-1/audio-chunks/\(String(format: "%06d", index % 60)).wav"
    let values: [String: InstantValue] = [
      "id": .string(id),
      "path": .string(path),
      "url": .string("https://files.example.test/\(appID)/\(id)?" + String(repeating: "signature-", count: 85)),
      "content-type": .string("audio/wav"),
      "content-disposition": .string("inline"),
      "location-id": .string(RealSizeID.make(.fileLocation, index)),
      "size": .number(5_760_044),
      "key-version": .number(1),
    ]
    return RealSizeEntity(namespace: "$files", id: id, values: values)
  }
}

/// One entity of the account: its values by field name.
struct RealSizeEntity: Sendable, Hashable {
  var namespace: String
  var id: String
  var values: [String: InstantValue]

  func triples(fields: [String]? = nil, at time: InstantTimestamp = RealSizeAccount.epoch) -> [InstantTriple] {
    let names = fields.map { Set($0 + ["id"]) }
    return values.keys.sorted().compactMap { field in
      guard names?.contains(field) ?? true, let value = values[field] else { return nil }
      return InstantTriple(entityID: id, attributeID: "\(namespace)/\(field)", value: value, txID: "real-size", txTime: time)
    }
  }

  /// The entity as one row of the server's datalog answer.
  func joinRow(fields: [String]? = nil) -> InstantLiveJSONValue {
    .array(
      triples(fields: fields).map { triple in
        .array([
          .string(triple.entityID), .string(triple.attributeID), RealSizeWire.value(triple.value),
          .number(Double(triple.txTime.milliseconds)),
        ])
      }
    )
  }

  /// Merges of every value: how the device writes the entity.
  func mergeOperations(at time: InstantTimestamp) -> [InstantTripleOperation] {
    triples(at: time).map { .merge($0) }
  }
}

/// Ids that look like the app's (UUID text) and are the same in every process.
enum RealSizeID {
  enum Kind: UInt32 {
    case recording = 1, segment, other, file, fileLocation, refusal, write, query
  }

  static func make(_ kind: Kind, _ index: Int) -> String {
    let index = UInt64(index)
    return String(
      format: "%08x-%04x-4%03x-8%03x-%012llx",
      kind.rawValue, UInt32(index >> 48 & 0xffff), UInt32(index >> 36 & 0xfff), UInt32(index >> 24 & 0xfff),
      index & 0xff_ffff
    )
  }
}

enum RealSizeWire {
  static func value(_ value: InstantValue) -> InstantLiveJSONValue {
    switch value {
    case .string(let value): .string(value)
    case .number(let value): .number(value)
    case .bool(let value): .bool(value)
    case .null: .null
    default: .string(String(describing: value))
    }
  }

  static func attributes(_ attributes: [InstantAttribute]) -> [InstantLiveJSONValue] {
    attributes.map { attribute in
      let valueType: String =
        switch attribute.valueType {
        case .string: "string"
        case .number: "number"
        case .boolean: "boolean"
        case .date: "date"
        case .json: "json"
        case .any: "any"
        case .ref: "ref"
        }
      return .object([
        "cardinality": .string("one"),
        "forward-identity": .array([.string("identity-\(attribute.id)"), .string(attribute.namespace), .string(attribute.name)]),
        "id": .string(attribute.id),
        "unique?": .bool(attribute.isUnique),
        "index?": .bool(attribute.isIndexed),
        "value-type": .string(valueType),
      ])
    }
  }

  /// A query answer in the server's datalog shape: one join row per entity.
  static func result(_ rows: [InstantLiveJSONValue]) -> [InstantLiveJSONValue] {
    [
      .object([
        "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
        "child-nodes": .array([]),
      ])
    ]
  }
}

/// A frame the scripted server sent or received, for counters of bytes on the wire (#1076).
struct RealSizeFrame: Sendable {
  enum Direction: Sendable { case toServer, toClient }
  var direction: Direction
  var op: String
  /// The frame's size as JSON.
  var encodedBytes: Int
}

/// A scripted Instant server for one session: answers `init`, every `add-query` from the account it holds and every
/// `transact` (accepted, or refused while `refusesWrites` is set); measurements push `refresh-ok` frames themselves.
actor RealSizeServer {
  enum WriteAnswer: Sendable { case accept, refuse, hold }

  private let account: RealSizeAccount
  /// The newest connection: the one that sent the last frame. A reconnect gets a new one.
  private var connection: RealSizeConnection?
  private var sent: [InstantLiveMessage] = []
  private var addQueryCount = 0
  /// The processed transaction id of each query's newest answer, by its key: the runtime's apply of that answer reports
  /// it (`RealSizeApplyLog`).
  private var answerTransactions: [String: String] = [:]
  private var transactionNumber = 0
  /// Makes this server's transaction ids unique in the process: the apply log of every session sees every event.
  private let prefix = UUID().uuidString.prefix(8).lowercased()
  private(set) var openQueries: [String: InstantLiveJSONValue] = [:]
  private(set) var answeredWrites = 0
  private(set) var heldWrites: [String] = []
  var writeAnswer: WriteAnswer = .accept
  /// Answer queries from the account; off, a measurement answers them itself (`answer(_:rows:)`).
  var answersQueries = true
  nonisolated let onFrame: (@Sendable (RealSizeFrame) -> Void)?

  init(account: RealSizeAccount, onFrame: (@Sendable (RealSizeFrame) -> Void)? = nil) {
    self.account = account
    self.onFrame = onFrame
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
      let connection = RealSizeConnection()
      return InstantLiveWebSocketSession(
        send: { message in await self.received(message, from: connection) },
        receive: { try await connection.next() },
        close: { connection.abort() },
        abort: { connection.abort() }
      )
    }
  }

  func setWriteAnswer(_ answer: WriteAnswer) { writeAnswer = answer }
  func setAnswersQueries(_ answers: Bool) { answersQueries = answers }

  /// Every frame the runtime sent, oldest first.
  func sentMessages() -> [InstantLiveMessage] { sent }

  /// How many `add-query` frames the runtime sent.
  var addQueries: Int { addQueryCount }

  /// Waits until the runtime has sent more than `count` `add-query` frames, and returns the newest one's query.
  func nextAddQuery(after count: Int, timeout: Duration = .seconds(60)) async throws -> InstantLiveJSONValue {
    let deadline = ContinuousClock.now + timeout
    while addQueryCount <= count {
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed, operation: "wait for a real-size add-query",
          message: "The runtime sent no add-query after the \(count)th within \(timeout).",
          recovery: "Check that the plan is not already observed, and that the session is connected."
        )
      }
      try await Task.sleep(for: .milliseconds(1))
    }
    return sent.last(where: { $0.op == "add-query" })?.fields["q"] ?? .null
  }

  /// The processed transaction id of the newest answer this server sent for `query`.
  func answerTransaction(for query: InstantLiveJSONValue) -> String? {
    answerTransactions[Self.key(query)]
  }

  func enqueue(_ message: InstantLiveMessage) {
    guard let connection else { return }
    if let onFrame { onFrame(RealSizeFrame(direction: .toClient, op: message.op, encodedBytes: Self.encodedSize(message))) }
    connection.push(message)
  }

  /// Answers `query` with `rows` (join rows), as an `add-query-ok`.
  func answer(_ query: InstantLiveJSONValue, rows: [InstantLiveJSONValue]) {
    let transaction = nextTransactionID()
    answerTransactions[Self.key(query)] = transaction
    enqueue(
      InstantLiveMessage(
        op: "add-query-ok",
        clientEventID: nil,
        fields: ["q": query, "processed-tx-id": .string(transaction), "result": .array(RealSizeWire.result(rows))]
      )
    )
  }

  /// Sends the server's `refresh-ok` of `query` with `rows`, as a refresh after another device's write does.
  @discardableResult
  func refresh(_ query: InstantLiveJSONValue, rows: [InstantLiveJSONValue]) -> String {
    let tx = nextTransactionID()
    enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: nil,
        fields: [
          "attrs": .array([]),
          "computations": .array([
            .object(["instaql-query": query, "instaql-result": .array(RealSizeWire.result(rows)), "processed-tx-id": .string(tx)])
          ]),
          "processed-tx-id": .string(tx),
        ]
      )
    )
    return tx
  }

  /// The account's `$files` as join rows: the first `count`, or all.
  func filesRows(count: Int? = nil) -> [InstantLiveJSONValue] {
    let files = account.entities["$files"] ?? []
    return files.prefix(count ?? files.count).map { $0.joinRow() }
  }

  /// Answers the writes held while `writeAnswer` was `.hold`.
  func releaseHeldWrites(as answer: WriteAnswer) {
    let held = heldWrites
    heldWrites = []
    for id in held { answerWrite(id, as: answer) }
  }

  // MARK: - The wire

  private func received(_ message: InstantLiveMessage, from connection: RealSizeConnection) {
    self.connection = connection
    sent.append(message)
    if let onFrame { onFrame(RealSizeFrame(direction: .toServer, op: message.op, encodedBytes: Self.encodedSize(message))) }
    switch message.op {
    case "init":
      enqueue(
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array(RealSizeWire.attributes(account.attributes)),
            "auth": .null,
            "session-id": .string("real-size-session"),
          ]
        )
      )
    case "add-query":
      addQueryCount += 1
      let query = message.fields["q"] ?? .null
      openQueries[Self.key(query)] = query
      if answersQueries { answer(query, rows: rows(answering: query)) }
    case "remove-query":
      openQueries[Self.key(message.fields["q"] ?? .null)] = nil
    case "transact":
      guard let id = message.clientEventID else { return }
      switch writeAnswer {
      case .hold: heldWrites.append(id)
      case .accept, .refuse: answerWrite(id, as: writeAnswer)
      }
    default:
      break
    }
  }

  private func answerWrite(_ id: String, as answer: WriteAnswer) {
    answeredWrites += 1
    switch answer {
    case .accept, .hold:
      enqueue(InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string(nextTransactionID())]))
    case .refuse:
      enqueue(
        InstantLiveMessage(
          op: "error",
          clientEventID: id,
          fields: [
            "message": .string("The scripted server refuses this write (#1072 fixture)."),
            "status": .number(400),
            "type": .string("validation-failed"),
          ]
        )
      )
    }
  }

  private func nextTransactionID() -> String {
    transactionNumber += 1
    return "real-size-\(prefix)-tx-\(transactionNumber)"
  }

  // MARK: - Answering queries

  /// The account's answer to an InstaQL query: its namespace's entities that match its `where`, in its `order`, at most
  /// `limit`, with only its `fields`. Cursors and nested includes are not evaluated: the fixture's queries use neither.
  func rows(answering query: InstantLiveJSONValue) -> [InstantLiveJSONValue] {
    guard case .object(let root) = query, let top = root.first, let entities = account.entities[top.key] else { return [] }
    let options = top.value.objectValue?["$"]?.objectValue ?? [:]
    var matches = entities.filter { Self.matches($0, options["where"]) }
    if case .object(let order)? = options["order"], let first = order.first {
      let field = first.key
      let descending = first.value.stringValue == "desc"
      matches.sort { left, right in
        let ordered = Self.compare(left.values[field], right.values[field])
        if ordered == .orderedSame { return left.id < right.id }
        return descending ? ordered == .orderedDescending : ordered == .orderedAscending
      }
    }
    if case .number(let limit)? = options["limit"] { matches = Array(matches.prefix(Int(limit))) }
    let fields = options["fields"]?.arrayValue?.compactMap(\.stringValue)
    return matches.map { $0.joinRow(fields: fields) }
  }

  private static func matches(_ entity: RealSizeEntity, _ clause: InstantLiveJSONValue?) -> Bool {
    guard case .object(let conditions)? = clause else { return true }
    for (field, condition) in conditions {
      switch field {
      case "and":
        guard condition.arrayValue?.allSatisfy({ matches(entity, $0) }) ?? true else { return false }
      case "or":
        guard condition.arrayValue?.contains(where: { matches(entity, $0) }) ?? true else { return false }
      default:
        let value = field == "id" ? .string(entity.id) : entity.values[field]
        if case .object(let operators) = condition {
          for (name, operand) in operators {
            switch name {
            case "$in":
              guard operand.arrayValue?.contains(where: { compare(value, instantValue($0)) == .orderedSame }) ?? false
              else { return false }
            case "$ne": if compare(value, instantValue(operand)) == .orderedSame { return false }
            case "$gt": if compare(value, instantValue(operand)) != .orderedDescending { return false }
            case "$gte": if compare(value, instantValue(operand)) == .orderedAscending { return false }
            case "$lt": if compare(value, instantValue(operand)) != .orderedAscending { return false }
            case "$lte": if compare(value, instantValue(operand)) == .orderedDescending { return false }
            case "$isNull":
              let wantsNull = if case .bool(let flag) = operand { flag } else { true }
              if (value == nil) != wantsNull { return false }
            default: break
            }
          }
        } else if compare(value, instantValue(condition)) != .orderedSame {
          return false
        }
      }
    }
    return true
  }

  private static func instantValue(_ value: InstantLiveJSONValue) -> InstantValue? {
    switch value {
    case .string(let value): .string(value)
    case .number(let value): .number(value)
    case .bool(let value): .bool(value)
    default: nil
    }
  }

  private static func compare(_ left: InstantValue?, _ right: InstantValue?) -> ComparisonResult {
    switch (left, right) {
    case let (.number(left)?, .number(right)?): left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
    case let (.string(left)?, .string(right)?): left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
    case let (.bool(left)?, .bool(right)?): left == right ? .orderedSame : (!left ? .orderedAscending : .orderedDescending)
    case (nil, nil): .orderedSame
    case (nil, _): .orderedAscending
    case (_, nil): .orderedDescending
    default: String(describing: left) < String(describing: right) ? .orderedAscending : .orderedDescending
    }
  }

  static func key(_ query: InstantLiveJSONValue) -> String {
    (try? String(decoding: JSONEncoder.realSizeSorted.encode(query), as: UTF8.self)) ?? "\(query)"
  }

  private static func encodedSize(_ message: InstantLiveMessage) -> Int {
    (try? JSONEncoder().encode(message).count) ?? 0
  }
}

/// One scripted socket: the frames the server sent that the runtime has not received, the waiting `receive`, and
/// whether it was closed. Its abort is synchronous, as the transport contract requires.
final class RealSizeConnection: @unchecked Sendable {
  // SAFETY: `lock` guards every stored property; continuations are resumed outside it.
  private let lock = NSLock()
  private var inbox: [InstantLiveMessage] = []
  private var continuation: CheckedContinuation<InstantLiveMessage, any Error>?
  private var aborted = false

  func push(_ message: InstantLiveMessage) {
    let waiting: CheckedContinuation<InstantLiveMessage, any Error>? = lock.withLock {
      guard !aborted else { return nil }
      guard let continuation else {
        inbox.append(message)
        return nil
      }
      self.continuation = nil
      return continuation
    }
    waiting?.resume(returning: message)
  }

  func next() async throws -> InstantLiveMessage {
    try await withCheckedThrowingContinuation { continuation in
      enum Next { case message(InstantLiveMessage), closed, wait }
      let next: Next = lock.withLock {
        if aborted { return .closed }
        if !inbox.isEmpty { return .message(inbox.removeFirst()) }
        self.continuation = continuation
        return .wait
      }
      switch next {
      case .message(let message): continuation.resume(returning: message)
      case .closed: continuation.resume(throwing: CancellationError())
      case .wait: break
      }
    }
  }

  func abort() {
    let waiting: CheckedContinuation<InstantLiveMessage, any Error>? = lock.withLock {
      aborted = true
      defer { continuation = nil }
      return continuation
    }
    waiting?.resume(throwing: CancellationError())
  }
}

extension JSONEncoder {
  static let realSizeSorted: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
}

/// Scripted storage: an upload is given an id, a download writes a small file, a delete succeeds.
final class RealSizeStorage: Sendable {
  let directory: URL
  init(directory: URL) { self.directory = directory }

  var client: InstantStorageTransportClient {
    let directory = directory
    @Sendable func download() throws -> URL {
      let url = directory.appendingPathComponent("download-\(UUID().uuidString)")
      try Data(repeating: 7, count: 4_096).write(to: url)
      return url
    }
    return InstantStorageTransportClient(
      upload: { _ in InstantStorageUploadResponse(id: UUID().uuidString.lowercased()) },
      delete: { _ in InstantStorageDeleteResponse(id: nil) },
      downloadToFile: { _ in try download() },
      downloadFileToFile: { _ in try download() }
    )
  }
}

/// A runtime over a copy of the generated store, its scripted server and storage.
struct RealSizeSession: Sendable {
  let shape: RealSizeShape
  let account: RealSizeAccount
  let runtime: InstantRuntime
  let server: RealSizeServer
  let storage: RealSizeStorage
  let configuration: InstantRuntimeConfiguration
  /// The session's own directory: the store copy, downloads, scratch files.
  let directory: URL
  /// Whether `directory` goes when the session closes.
  let removesDirectory: Bool
  let clock: RealSizeClock
  let applies: RealSizeApplyLog
  /// The operation gate's timeline (#1074), for the meter's longest hold.
  let gate: RealSizeGateLog

  /// Closes the connection, and removes the session's directory unless the caller owns it.
  func close() async {
    _ = try? await runtime.closeConnection()
    applies.stop()
    if removesDirectory { try? FileManager.default.removeItem(at: directory) }
  }

  /// Runs `body`, then closes the session, whether `body` threw or not: a test cannot `await` in a `defer`, and a
  /// close left to a detached task would run into the next measurement's counts.
  func closing<Result>(_ body: () async throws -> Result) async throws -> Result {
    let result: Result
    do {
      result = try await body()
    } catch {
      await close()
      throw error
    }
    await close()
    return result
  }

  /// The plan of a recording's live transcript page, as Scribe observes it while recording.
  func transcriptPage(recordingID: String, page: Int = 0) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "real-size-transcript-\(recordingID)-\(page)",
      namespace: "transcriptionSegments",
      filters: [
        .equals(field: "recordingID", value: .string(recordingID)),
        .greaterThanOrEqual(field: "segmentIndex", value: .number(Double(page * 256))),
      ],
      order: InstantQueryOrder("segmentIndex"),
      limit: 256
    )
  }

  /// A transcript line's write as Scribe makes it: every one of its sixteen values, merged.
  func segmentWrite(recordingID: String, line: Int, revision: Int, id: String) -> InstantStoreTransaction {
    let entity = RealSizeAccount.segment(recordingID: recordingID, line: line, revision: revision, serial: 0, id: id)
    return InstantStoreTransaction(id: UUID().uuidString.lowercased(), operations: entity.mergeOperations(at: clock.advance()))
  }

  /// A new recording's id and its first write.
  func newRecording(_ index: Int) -> (id: String, write: InstantStoreTransaction) {
    let id = RealSizeID.make(.write, index)
    let entity = RealSizeAccount.recording(id: id, index: index)
    return (id, InstantStoreTransaction(id: UUID().uuidString.lowercased(), operations: entity.mergeOperations(at: clock.advance())))
  }
}

/// Every server apply the runtime finished, by its processed transaction id: the runtime's own
/// `server-apply.operation-gate-held` event, with its gate hold and commit parts.
final class RealSizeApplyLog: @unchecked Sendable {
  // SAFETY: `lock` guards `finished` and `token`.
  private let lock = NSLock()
  private var finished: [String: [String: String]] = [:]
  private var token: UUID?

  init() {
    let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self, entry.event == "server-apply.operation-gate-held", let id = entry.correlationID else { return }
      self.lock.withLock { self.finished[id] = entry.metadata }
    }
    lock.withLock { self.token = token }
  }

  func stop() {
    if let token = lock.withLock({ self.token }) { InstantDiagnostics.shared.removeHandler(token) }
    lock.withLock { token = nil }
  }

  /// The apply of `transactionID`'s metadata (`heldMilliseconds`, `commitMilliseconds`, …), once it finished.
  func wait(for transactionID: String, timeout: Duration = .seconds(120)) async throws -> [String: String] {
    let deadline = ContinuousClock.now + timeout
    while true {
      if let metadata = lock.withLock({ finished[transactionID] }) { return metadata }
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed, operation: "wait for a real-size server apply",
          message: "No server apply finished for \(transactionID) within \(timeout).",
          recovery: "Check that the frame names a query the runtime holds."
        )
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// The session's clock: each read moves it a millisecond, so every write is newer than the last.
final class RealSizeClock: @unchecked Sendable {
  // SAFETY: `lock` guards `milliseconds`.
  private let lock = NSLock()
  private var milliseconds: Int64
  init(_ start: InstantTimestamp) { milliseconds = start.milliseconds }
  func now() -> InstantTimestamp { lock.withLock { InstantTimestamp(milliseconds: milliseconds) } }
  func advance(by delta: Int64 = 1) -> InstantTimestamp {
    lock.withLock {
      milliseconds += delta
      return InstantTimestamp(milliseconds: milliseconds)
    }
  }
}

enum RealSizeFixture {
  /// Bump when the generator changes what it writes: the cached stores of older versions are not reused.
  static let version = 2

  /// Opens a runtime over a fresh copy of the generated store, in a directory the session removes when it closes.
  static func open(_ shape: RealSizeShape = .phone, label: String) async throws -> RealSizeSession {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("real-size-sessions", isDirectory: true)
      .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    return try await open(shape, in: directory, removesDirectory: true)
  }

  /// Opens a runtime over a copy of the generated store in `directory`, which the caller owns: the store stays there
  /// (and grows with whatever the caller does) until the caller removes it.
  static func open(
    _ shape: RealSizeShape = .phone,
    in directory: URL,
    removesDirectory: Bool = false,
    onFrame: (@Sendable (RealSizeFrame) -> Void)? = nil,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> RealSizeSession {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storeURL = directory.appendingPathComponent("cache.sqlite")
    if !FileManager.default.fileExists(atPath: storeURL.path) {
      let source = try await store(shape)
      try copyStore(from: source, to: storeURL)
    }
    let account = RealSizeAccount(shape)
    return try await boot(shape: shape, account: account, storeURL: storeURL, directory: directory,
                          removesDirectory: removesDirectory, onFrame: onFrame, configure: configure)
  }

  /// The generated store for `shape`: from the cache when a complete one of this version and schema is there, else
  /// generated now. A phone's store copy named by `INSTANT_REAL_SIZE_STORE` stands in for the `.phone` shape.
  static func store(_ shape: RealSizeShape) async throws -> URL {
    if shape == .phone, let path = ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_STORE"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return try await RealSizeFixtureCache.shared.store(shape)
  }

  /// Copies the store at `source`, with what its write-ahead log still holds, into one new file at `destination`.
  ///
  /// SQLite's online backup copies page for page, free pages too, so a copy of a phone's store keeps its shape, and it
  /// reads one consistent snapshot even while another connection still has the source open (a generator's runtime is
  /// released whenever its last task lets go of it). The source is opened read-only: a phone's copy is never changed.
  static func copyStore(from source: URL, to destination: URL) throws {
    for suffix in ["", "-wal", "-shm", "-journal"] {
      try? FileManager.default.removeItem(atPath: destination.path + suffix)
    }
    var from: OpaquePointer?
    var to: OpaquePointer?
    defer {
      sqlite3_close(from)
      sqlite3_close(to)
    }
    func failure(_ message: String) -> InstantError {
      InstantError(
        code: .persistenceFailed, operation: "copy the real-size store",
        message: "\(message): \(source.lastPathComponent) to \(destination.path)",
        recovery: "Generate the fixture again, or check the store named by INSTANT_REAL_SIZE_STORE."
      )
    }
    guard sqlite3_open_v2(source.path, &from, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      throw failure("SQLite could not open the source")
    }
    guard sqlite3_open_v2(destination.path, &to, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
      throw failure("SQLite could not create the copy")
    }
    sqlite3_busy_timeout(from, 30_000)
    guard let backup = sqlite3_backup_init(to, "main", from, "main") else {
      throw failure(String(cString: sqlite3_errmsg(to)))
    }
    let step = sqlite3_backup_step(backup, -1)
    let finish = sqlite3_backup_finish(backup)
    guard step == SQLITE_DONE, finish == SQLITE_OK else {
      throw failure("the backup ended with \(step), \(finish): \(String(cString: sqlite3_errmsg(to)))")
    }
  }

  static func boot(
    shape: RealSizeShape,
    account: RealSizeAccount,
    storeURL: URL,
    directory: URL,
    removesDirectory: Bool,
    onFrame: (@Sendable (RealSizeFrame) -> Void)?,
    configure: (inout InstantRuntimeConfiguration) -> Void
  ) async throws -> RealSizeSession {
    let clock = RealSizeClock(RealSizeAccount.epoch)
    let applies = RealSizeApplyLog()
    let server = RealSizeServer(account: account, onFrame: onFrame)
    let storage = RealSizeStorage(directory: directory)
    var configuration = InstantRuntimeConfiguration(
      appID: RealSizeAccount.appID,
      apiURI: URL(string: "https://api.example.test")!,
      persistenceURL: storeURL,
      now: { clock.now() },
      liveTransport: server.transport
    )
    configuration.initialAttributes = account.attributes
    configuration.autoConnectLiveTransport = false
    // Measurements prune when they choose to, as Scribe's every-64-writes prune would land at random.
    configuration.liveQueryResultPruningWriteInterval = Int.max
    configuration.liveMutationDeadlineSleep = { _ in try await Task.sleep(for: .seconds(36_000)) }
    configuration.liveReconnectSleep = { _ in try await Task.sleep(for: .seconds(36_000)) }
    let gate = RealSizeGateLog()
    configuration.operationGateTimeline = { gate.record($0) }
    configure(&configuration)
    if let theirs = configuration.operationGateTimeline {
      configuration.operationGateTimeline = { event in
        gate.record(event)
        theirs(event)
      }
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration, storageTransport: storage.client)
    _ = try await runtime.signInWithRefreshToken(RealSizeAccount.refreshToken, userID: RealSizeAccount.userID)
    _ = try await runtime.connect()
    return RealSizeSession(
      shape: shape, account: account, runtime: runtime, server: server, storage: storage,
      configuration: configuration, directory: directory, removesDirectory: removesDirectory, clock: clock,
      applies: applies, gate: gate
    )
  }
}

/// What the generator left on disk, counted with SQL on the closed store.
struct RealSizeStoreCounts: Sendable, CustomStringConvertible {
  var facts = 0
  var attributes = 0
  var liveResults = 0
  var liveResultFacts = 0
  var unloadedResults = 0
  var unloadedResultBytes = 0
  var outbox: [String: Int] = [:]
  var writeKeys = 0
  var fileRecords = 0
  var migrations = ""

  init() {}

  init(_ url: URL) throws {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
      throw InstantError(
        code: .persistenceFailed, operation: "count the real-size store", message: url.path,
        recovery: "Generate the fixture again."
      )
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 30_000)
    func rows(_ sql: String) throws -> [[String]] {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw InstantError(
          code: .persistenceFailed, operation: "count the real-size store",
          message: "\(sql): \(String(cString: sqlite3_errmsg(db)))", recovery: "Generate the fixture again."
        )
      }
      defer { sqlite3_finalize(statement) }
      var rows: [[String]] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        rows.append((0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        })
      }
      return rows
    }
    func integer(_ sql: String) throws -> Int { Int(try rows(sql).first?.first ?? "") ?? 0 }
    facts = try integer("SELECT COUNT(*) FROM instant_triples")
    attributes = try integer("SELECT COUNT(*) FROM instant_attributes")
    liveResults = try integer("SELECT COUNT(*) FROM instant_live_query_results")
    liveResultFacts = try integer("SELECT COUNT(*) FROM instant_live_query_triples")
    unloadedResults = try integer("SELECT COUNT(*) FROM instant_unloaded_live_query_results")
    unloadedResultBytes = try integer("SELECT COALESCE(SUM(LENGTH(json)), 0) FROM instant_unloaded_live_query_results")
    for row in try rows("SELECT status, COUNT(*) FROM instant_outbox GROUP BY status") where row.count == 2 {
      outbox[row[0]] = Int(row[1]) ?? 0
    }
    writeKeys = try integer("SELECT COUNT(*) FROM instant_outbox_write_keys")
    fileRecords = try integer("SELECT COUNT(*) FROM instant_files")
    migrations = try rows("SELECT name FROM instant_schema_migrations ORDER BY name").map { $0[0] }.joined(separator: ",")
  }

  var description: String {
    "facts=\(facts) attributes=\(attributes) liveResults=\(liveResults) liveResultFacts=\(liveResultFacts)"
      + " unloadedResults=\(unloadedResults) unloadedMB=\(unloadedResultBytes / 1_048_576)"
      + " outbox=\(outbox.keys.sorted().map { "\($0):\(outbox[$0]!)" }.joined(separator: ","))"
      + " writeKeys=\(writeKeys) fileRecords=\(fileRecords)"
  }
}

/// One generation per shape per process; across processes, a complete store of this fixture version and schema.
actor RealSizeFixtureCache {
  static let shared = RealSizeFixtureCache()
  private var stores: [String: Task<URL, any Error>] = [:]

  func store(_ shape: RealSizeShape) async throws -> URL {
    if let existing = stores[shape.key] { return try await existing.value }
    let task = Task { try await Self.cachedOrGenerated(shape) }
    stores[shape.key] = task
    return try await task.value
  }

  private static func cachedOrGenerated(_ shape: RealSizeShape) async throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("real-size-fixture", isDirectory: true)
    let migrations = try await currentMigrations(root: root)
    var hash = RealSizeStableHash()
    hash.combine(RealSizeFixture.version)
    hash.combine(shape.key)
    hash.combine(migrations)
    let directory = root.appendingPathComponent("v\(RealSizeFixture.version)-\(String(hash.value, radix: 16))")
    let storeURL = directory.appendingPathComponent("cache.sqlite")
    let complete = directory.appendingPathComponent("complete")
    if FileManager.default.fileExists(atPath: complete.path) { return storeURL }

    // Generate beside it and move it into place, so a crashed or concurrent generation never leaves a partial store.
    let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let started = ContinuousClock.now
    let report = try await RealSizeGenerator.generate(shape, into: staging)
    let counts = try RealSizeStoreCounts(staging.appendingPathComponent("cache.sqlite"))
    print("REALSIZE-FIXTURE generated shape=[\(shape)] in \(ContinuousClock.now - started): \(counts) \(report)")
    try "\(shape)\n\(counts)\n\(report)\n".write(to: staging.appendingPathComponent("complete"), atomically: true, encoding: .utf8)
    try? FileManager.default.removeItem(at: directory)
    do {
      try FileManager.default.moveItem(at: staging, to: directory)
    } catch where FileManager.default.fileExists(atPath: complete.path) {
      // Another process finished first: use its store.
    }
    return storeURL
  }

  /// The library's schema migrations, from a new empty store: a cached store from before a migration is not reused.
  private static func currentMigrations(root: URL) async throws -> String {
    let probe = root.appendingPathComponent("migrations-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: probe) }
    let url = probe.appendingPathComponent("probe.sqlite")
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    return try RealSizeStoreCounts(url).migrations
  }
}

/// Writes the shape's store the way the phone's was written, through the runtime and a scripted server.
enum RealSizeGenerator {
  struct Report: CustomStringConvertible {
    var writes = 0
    var refused = 0
    var openQueries = 0
    var closedQueries = 0
    var unloaded = 0
    var description: String {
      "writes=\(writes) refused=\(refused) openQueries=\(openQueries) closedQueries=\(closedQueries) unloaded=\(unloaded)"
    }
  }

  static func generate(_ shape: RealSizeShape, into directory: URL) async throws -> Report {
    let account = RealSizeAccount(shape)
    let storeURL = directory.appendingPathComponent("cache.sqlite")
    let session = try await RealSizeFixture.boot(
      shape: shape, account: account, storeURL: storeURL, directory: directory, removesDirectory: false,
      onFrame: nil, configure: { _ in }
    )
    let runtime = session.runtime
    var report = Report()

    // 1. The device's own writes, accepted: recordings, transcript lines, the other namespaces.
    var groups: [[InstantTripleOperation]] = []
    for namespace in ["recordings", "transcriptionSegments"] + RealSizeAccount.otherNamespaces {
      for entity in account.entities[namespace] ?? [] {
        groups.append(entity.mergeOperations(at: RealSizeAccount.epoch))
      }
    }
    for transaction in BoundedBenchmarkSeed.transactions(baseID: "real-size-seed", atomicOperationGroups: groups) {
      try await runtime.transact(transaction, createdAt: session.clock.advance())
      report.writes += 1
    }
    try await waitForSettledOutbox(runtime)
    print("REALSIZE-FIXTURE stage writes=\(report.writes)")

    // 2. Closed queries: answered, then closed, so the prune unloads their results. The whole `$files` list is one of
    //    them, as an older build left it on the phone.
    var closedPlans: [InstantQueryPlan] = [
      InstantQueryPlan(id: "real-size-files", namespace: "$files")
    ]
    let recordingIDs = (account.entities["recordings"] ?? []).map(\.id)
    var recordingIndex = 0
    while closedPlans.count < shape.closedQueries {
      let recordingID = recordingIDs[recordingIndex % recordingIDs.count]
      let namespace = closedPlans.count % 3 == 0
        ? "transcriptionSegments" : RealSizeAccount.otherNamespaces[closedPlans.count % RealSizeAccount.otherNamespaces.count]
      closedPlans.append(
        InstantQueryPlan(
          id: "real-size-closed-\(closedPlans.count)",
          namespace: namespace,
          filters: [.equals(field: "recordingID", value: .string(recordingID))],
          limit: namespace == "transcriptionSegments" ? 32 : nil
        )
      )
      recordingIndex += 1
    }
    for plan in closedPlans {
      try await observeUntilAnswered(plan, session: session).cancel()
      report.closedQueries += 1
    }
    print("REALSIZE-FIXTURE stage closed-queries=\(report.closedQueries)")

    // 3. Open queries: kept until the store closes, so their entities are resident at the next launch.
    var openLeases: [InstantQueryObservationLease] = []
    var openPlans: [InstantQueryPlan] = [
      session.transcriptPage(recordingID: recordingIDs[0]),
      InstantQueryPlan(
        id: "real-size-recordings",
        namespace: "recordings",
        order: InstantQueryOrder("updatedAtMs", .descending),
        selectedFields: RealSizeAccount.recordingFields.filter { $0 != "id" }
      ),
    ]
    var openIndex = 0
    while openPlans.count < shape.openQueries {
      let namespace = RealSizeAccount.otherNamespaces[openIndex % RealSizeAccount.otherNamespaces.count]
      openPlans.append(
        InstantQueryPlan(
          id: "real-size-open-\(openIndex)",
          namespace: namespace,
          filters: [.equals(field: "kind", value: .string("kind-\(openIndex % 7)"))],
          order: InstantQueryOrder("updatedAtMs", .descending),
          limit: 200
        )
      )
      openIndex += 1
    }
    for plan in openPlans {
      openLeases.append(try await observeUntilAnswered(plan, session: session))
      report.openQueries += 1
    }
    print("REALSIZE-FIXTURE stage open-queries=\(report.openQueries)")
    let pruned = try await runtime.pruneLiveQueryResults(policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now())
    report.unloaded = pruned.unloadedQueryKeys.count

    // 4. Refused writes: updates of recordings the server refused for good.
    await session.server.setWriteAnswer(.refuse)
    for index in 0..<shape.refusedWrites {
      var entity = RealSizeAccount.recording(id: recordingIDs[index % recordingIDs.count], index: index % recordingIDs.count)
      entity.values["title"] = .string("Refused title \(index)")
      try await runtime.transact(
        InstantStoreTransaction(id: RealSizeID.make(.refusal, index), operations: entity.mergeOperations(at: session.clock.advance())),
        createdAt: session.clock.now()
      )
      report.refused += 1
    }
    try await waitForSettledOutbox(runtime)
    await session.server.setWriteAnswer(.accept)

    // 5. The device's upload records: storage holds the files, the device keeps a record of each.
    for index in 0..<shape.deviceFileRecords {
      let file = account.entities["$files"]![index % shape.accountFiles]
      let name: String = if case .string(let path)? = file.values["path"] { path } else { "file-\(index)" }
      _ = try await runtime.persistence.saveUploadedFileRecord(
        InstantStoredFile(
          id: file.id, appID: RealSizeAccount.appID, name: name,
          contentType: "audio/wav", byteCount: 5_760_044, localPath: "", ownerUserID: RealSizeAccount.userID,
          createdAt: InstantTimestamp(milliseconds: RealSizeAccount.epoch.milliseconds - Int64(index) * 60_000),
          updatedAt: InstantTimestamp(milliseconds: RealSizeAccount.epoch.milliseconds - Int64(index) * 60_000)
        )
      )
    }

    // Close with the open queries still observed, as an app that is stopped does, and close the SQLite connection, so
    // the store is whole in its main file when it is counted and copied.
    _ = try? await runtime.closeConnection()
    session.applies.stop()
    await runtime.persistence.simulateUnexpectedConnectionCloseForTesting()
    _ = openLeases
    return report
  }

  /// Observes `plan` until the runtime applied the server's first answer to it.
  ///
  /// The wait is on the apply itself (its `server-apply.operation-gate-held` event names the answer's processed
  /// transaction), not on the stream: an answer with no rows changes nothing the stream would emit again.
  private static func observeUntilAnswered(
    _ plan: InstantQueryPlan,
    session: RealSizeSession
  ) async throws -> InstantQueryObservationLease {
    let sent = await session.server.addQueries
    let lease = await session.runtime.observeQueryLease(plan)
    let query = try await session.server.nextAddQuery(after: sent)
    if let transaction = await session.server.answerTransaction(for: query) {
      _ = try await session.applies.wait(for: transaction)
    }
    return lease
  }

  /// Waits until no write is pending: every one was answered (accepted or refused).
  static func waitForSettledOutbox(_ runtime: InstantRuntime, timeout: Duration = .seconds(300)) async throws {
    let deadline = ContinuousClock.now + timeout
    while await runtime.pendingMutationCount() > 0 {
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed, operation: "settle the real-size fixture's writes",
          message: "\(await runtime.pendingMutationCount()) writes still pending after \(timeout).",
          recovery: "Check the scripted server's answers."
        )
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}
