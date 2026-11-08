import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #2028: on a flapping network, a write is reported refused only when the server truly refused it.
///
/// A scripted server keeps one row the way a consuming app's rules keep a row whose `updatedAtMs` never goes back: it
/// applies a write of the row only when the write is not older than the row's newest write, and refuses it otherwise.
/// It refuses every write of a second row, as a rule refuses a write the user may not make. Each write it is sent may
/// meet a socket that drops before the server applies it or after (the answer lost), or a transient server error with
/// or without the write applied; a result with the server's watermark follows half the answers. The server answers
/// every 25 ms and the device writes every 8 ms, so several writes are in flight at once, as on a slow network. A
/// refusal of the first row's writes is always false: a newer write of this device holds every slot it sets. A refusal
/// of the second row's writes is always true and must be reported. Seeds replay exactly; the interleaving of the
/// runtime's tasks does not.
@Suite(.serialized)
struct InstantFlappingNetworkRefusalTests {
  static let keptRowID = "todo-flapping-kept"
  static let refusedRowID = "todo-flapping-refused"
  static let createdAt: Int64 = 1_700_002_028_000

  /// A write the workload made, as the scripted server reads it.
  struct Write: Sendable {
    var id: String
    var rowID: String
    var createdAt: Int64
    var text: String
    var isCompleted: Bool
  }

  /// What the scripted server met, and what the runtime made of it.
  struct Tally: Sendable {
    var transacts = 0
    var droppedBeforeApply = 0
    var droppedAfterApply = 0
    var timedOut = 0
    var timedOutAfterApply = 0
    var accepted = 0
    var refusedAsOlder = 0
    var refusedAlways = 0
    var results = 0
  }

  actor Server {
    private var random: FastDrainRandom
    private var faults = false
    private(set) var version = Int64.min
    private var text = ""
    private var isCompleted = false
    private var transactionID = 0
    private var writes: [String: Write] = [:]
    private var handled: [Int: Int] = [:]
    private var dropped: Set<Int> = []
    private(set) var tally = Tally()
    private let query: InstantLiveJSONValue

    init(seed: UInt64, query: InstantLiveJSONValue) {
      random = FastDrainRandom(seed: seed)
      self.query = query
    }

    func register(_ write: Write) { writes[write.id] = write }
    func setFaults(_ on: Bool) { faults = on }

    /// Answers what the current connection sent since the last call.
    func serve(_ sessions: [LiveReactorParitySession], transport: LiveReactorParityTransport) async {
      let index = await transport.connectionRequests().count - 1
      guard sessions.indices.contains(index), !dropped.contains(index) else { return }
      let session = sessions[index]
      let sent = await session.sentMessages()
      while handled[index, default: 0] < sent.count {
        let message = sent[handled[index, default: 0]]
        handled[index, default: 0] += 1
        switch message.op {
        case "add-query":
          tally.results += 1
          await session.enqueue(result(op: "add-query-ok"))
        case "transact":
          guard let id = message.clientEventID, let write = writes[id] else { continue }
          guard await answer(write, on: session) else {
            dropped.insert(index)
            await session.failReceive(
              InstantError(
                code: .networkFailed,
                operation: "receive flapping network test event",
                message: "socket dropped",
                recovery: "Reconnect."
              )
            )
            return
          }
        default:
          continue
        }
      }
    }

    /// Answers one write, or returns false when the socket drops with it.
    private func answer(_ write: Write, on session: LiveReactorParitySession) async -> Bool {
      tally.transacts += 1
      let roll = faults ? random.int(1...100) : 100
      switch roll {
      case 1...8:
        tally.droppedBeforeApply += 1
        return false
      case 9...16:
        _ = apply(write)
        tally.droppedAfterApply += 1
        return false
      case 17...24:
        tally.timedOut += 1
        await session.enqueue(InstantTransientMutationRetryTests.transactTimedOut(write.id))
      case 25...28:
        _ = apply(write)
        tally.timedOutAfterApply += 1
        await session.enqueue(InstantTransientMutationRetryTests.transactTimedOut(write.id))
      default:
        await session.enqueue(apply(write))
        if !faults || random.chance(50) {
          tally.results += 1
          await session.enqueue(result(op: "refresh-ok"))
        }
      }
      return true
    }

    private func apply(_ write: Write) -> InstantLiveMessage {
      guard write.rowID == InstantFlappingNetworkRefusalTests.keptRowID else {
        tally.refusedAlways += 1
        return InstantSupersededReplayTests.refused(write.id)
      }
      guard write.createdAt >= version else {
        tally.refusedAsOlder += 1
        return InstantSupersededReplayTests.refused(write.id)
      }
      version = write.createdAt
      text = write.text
      isCompleted = write.isCompleted
      transactionID += 1
      tally.accepted += 1
      return InstantSupersededReplayTests.accepted(write.id, transactionID: transactionID)
    }

    /// The todo query's result as the server holds it, with its watermark.
    private func result(op: String) -> InstantLiveMessage {
      let createdAt = Double(InstantFlappingNetworkRefusalTests.createdAt)
      func row(_ attributeID: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
        .array([.string(InstantFlappingNetworkRefusalTests.keptRowID), .string(attributeID), value, .number(createdAt)])
      }
      let rows: [InstantLiveJSONValue] = version == .min
        ? []
        : [
          .array([
            row("server-todos-id", .string(InstantFlappingNetworkRefusalTests.keptRowID)),
            row("server-todos-text", .string(text)),
            row("server-todos-is-completed", .bool(isCompleted)),
            row("server-todos-created-at", .number(createdAt)),
          ])
        ]
      let result: InstantLiveJSONValue = .object([
        "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
        "child-nodes": .array([]),
      ])
      if op == "add-query-ok" {
        return liveReactorAddQueryOK(query: query, processedTransactionID: String(transactionID), result: [result])
      }
      return InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: nil,
        fields: [
          "attrs": .array([]),
          "computations": .array([
            .object([
              "instaql-query": query,
              "instaql-result": .array([result]),
              "processed-tx-id": .string(String(transactionID)),
            ])
          ]),
          "processed-tx-id": .string(String(transactionID)),
        ]
      )
    }
  }

  static func keptRowOperations(_ write: Write) -> [InstantTripleOperation] {
    let at = InstantTimestamp(milliseconds: write.createdAt)
    func insert(_ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: keptRowID, attributeID: attributeID, value: value, txID: write.id, txTime: at))
    }
    return [
      .requireEntityExists(entityID: keptRowID, namespace: TodoExample.namespace),
      insert(InstantAttribute.primaryKeyID(namespace: TodoExample.namespace), .string(keptRowID)),
      insert("todos/text", .string(write.text)),
      insert("todos/isCompleted", .bool(write.isCompleted)),
    ]
  }

  @Test(arguments: [UInt64(2028), 7, 41, 99, 314, 1234, 4242, 9001])
  func onAFlappingNetworkOnlyTrueRefusalsAreReported(seed: UInt64) async throws {
    let sessions = (0..<80).map { index in
      LiveReactorParitySession(messages: [
        liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "flapping-\(seed)-\(index)")
      ])
    }
    let transport = LiveReactorParityTransport(sessions: sessions)
    var configuration = InstantRuntimeConfiguration(
      appID: "flapping-network-\(seed)",
      persistenceURL: try InstantSupersededReplayTests.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.liveServerErrorRetryPolicy = InstantServerErrorRetryPolicy(
      baseMilliseconds: 20,
      maximumMilliseconds: 80,
      jitter: { 1 }
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observe(TodoExample.query)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()
    let server = Server(seed: seed, query: try InstantLiveQueryEncoder.encode(TodoExample.query))
    let serving = Task {
      while !Task.isCancelled {
        await server.serve(sessions, transport: transport)
        try? await Task.sleep(for: .milliseconds(25))
      }
    }
    defer { serving.cancel() }
    _ = try await runtime.connect()

    // The row exists on the server before the network starts to flap.
    let create = Write(id: "tx-flapping-create", rowID: Self.keptRowID, createdAt: Self.createdAt, text: "created", isCompleted: false)
    await server.register(create)
    try await runtime.transact(
      InstantStoreTransaction(
        id: create.id,
        operations: TodoExample.createOperations(
          id: Self.keptRowID,
          text: create.text,
          createdAt: InstantTimestamp(milliseconds: create.createdAt),
          transactionID: create.id
        )
      ),
      createdAt: InstantTimestamp(milliseconds: create.createdAt)
    )
    try await InstantSupersededReplayTests.waitUntil("the row is created") {
      await runtime.durableOutboxMutationsForTesting().first { $0.id == create.id }?.status != .pending
    }

    await server.setFaults(true)
    var keptWrites: [Write] = []
    for step in 1...48 {
      let at = Self.createdAt + 1_000 + Int64(step)
      if step.isMultiple(of: 6) {
        let write = Write(id: "tx-flapping-refused-\(step)", rowID: Self.refusedRowID, createdAt: at, text: "refused \(step)", isCompleted: false)
        await server.register(write)
        try await runtime.transact(
          InstantStoreTransaction(
            id: write.id,
            operations: TodoExample.upsertOperations(
              id: Self.refusedRowID,
              text: write.text,
              createdAt: InstantTimestamp(milliseconds: at),
              transactionID: write.id
            )
          ),
          createdAt: InstantTimestamp(milliseconds: at)
        )
      } else {
        let write = Write(id: "tx-flapping-kept-\(step)", rowID: Self.keptRowID, createdAt: at, text: "kept \(step)", isCompleted: step.isMultiple(of: 2))
        await server.register(write)
        keptWrites.append(write)
        try await runtime.transact(
          InstantStoreTransaction(id: write.id, operations: Self.keptRowOperations(write)),
          createdAt: InstantTimestamp(milliseconds: at)
        )
      }
      try await Task.sleep(for: .milliseconds(8))
    }

    // The network settles; every write gets its final answer.
    await server.setFaults(false)
    try await InstantSupersededReplayTests.waitUntil("every write has its final answer") {
      await runtime.durableOutboxMutationsForTesting().allSatisfy { $0.status != .pending }
    }
    serving.cancel()

    let mutations = await runtime.durableOutboxMutationsForTesting()
    let falseRefusals = mutations.filter { $0.status == .failed && $0.id.hasPrefix("tx-flapping-kept-") }.map(\.id)
    let refusedRowWrites = mutations.filter { $0.id.hasPrefix("tx-flapping-refused-") }
    let trueRefusals = refusedRowWrites.filter { $0.status == .failed }.map(\.id)
    let tally = await server.tally
    let serverVersion = await server.version
    print(
      """
      #2028 flapping seed=\(seed) transacts=\(tally.transacts) droppedBeforeApply=\(tally.droppedBeforeApply) \
      droppedAfterApply=\(tally.droppedAfterApply) timedOut=\(tally.timedOut) \
      timedOutAfterApply=\(tally.timedOutAfterApply) accepted=\(tally.accepted) refusedAsOlder=\(tally.refusedAsOlder) \
      refusedAlways=\(tally.refusedAlways) results=\(tally.results) connections=\(await transport.connectionRequests().count) \
      falseRefusals=\(falseRefusals.count) trueRefusals=\(trueRefusals.count) of \(refusedRowWrites.count)
      """
    )
    expectNoDifference(falseRefusals, [], "a write the server holds a newer write of this device for is not refused")
    expectNoDifference(trueRefusals, refusedRowWrites.map(\.id), "every write the server truly refused is reported")
    #expect(!refusedRowWrites.isEmpty)
    expectNoDifference(serverVersion, keptWrites.last?.createdAt, "the server holds the newest write")
    _ = try await runtime.closeConnection()
    withExtendedLifetime(observation) {}
  }
}
