import AppKit
import Foundation
import InstantSwiftDataCore
import SwiftUI

/// Mac SwiftUI shell: highly refreshing Instant write/observe list.
/// Env: INSTANT_APP_ID, INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN, INSTANT_SWIFT_DATA_BENCH_USER_ID
@main
struct ExerciseGemMacApp: App {
  @StateObject private var model = LiveGemModel()

  var body: some Scene {
    WindowGroup("Instant Exercise Gem (Mac)") {
      ContentView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    }
  }
}

struct LiveRow: Identifiable, Hashable {
  let id: String
  let seq: Int
  let rttMs: Double?
  let clientId: String
  let descriptor: String
  let at: Date
}

@MainActor
final class LiveGemModel: ObservableObject {
  @Published var rows: [LiveRow] = []
  @Published var status: String = "idle"
  @Published var opsPerSecond: Double = 0
  @Published var lastRttMs: Double?
  @Published var peakAppRssMiB: Double = 0
  @Published var clientId: String = ""
  @Published var errorText: String = ""

  private var task: Task<Void, Never>?
  private var windowCount = 0
  private var windowStarted = Date()

  func start() {
    guard task == nil else { return }
    status = "starting"
    errorText = ""
    task = Task { await runLoop() }
  }

  func stop() {
    task?.cancel()
    task = nil
    status = "stopped"
  }

  private func runLoop() async {
    do {
      let env = ProcessInfo.processInfo.environment
      guard let appID = env["INSTANT_APP_ID"], !appID.isEmpty else {
        throw CLIError("INSTANT_APP_ID required")
      }
      guard let refreshToken = env["INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN"], !refreshToken.isEmpty,
        let userID = env["INSTANT_SWIFT_DATA_BENCH_USER_ID"], !userID.isEmpty
      else {
        throw CLIError(
          "INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN and INSTANT_SWIFT_DATA_BENCH_USER_ID required"
        )
      }

      let apiURI = InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = InstantRuntimeConfiguration.defaultWebSocketURI
      let persistenceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("exercise-gem-mac-\(UUID().uuidString).sqlite")

      var configuration = InstantRuntimeConfiguration(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        initialAttributes: MacExerciseSchema.attributes,
        refreshTokenVerifier: .live,
        authTokenInvalidator: .live,
        liveTransport: .live
      )
      configuration.autoConnectLiveTransport = true
      let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
      let session = try await runtime.signInWithRefreshToken(
        refreshToken,
        userID: "untrusted-mac-gem"
      )
      guard session.userID == userID else {
        throw CLIError("user mismatch")
      }
      _ = try await runtime.connect()
      try await waitAuthenticated(runtime)
      let localClientID = try await runtime.clientID()
      await MainActor.run {
        self.clientId = localClientID
        self.status = "running"
      }

      let baseline = InstantProcessMemory.sample()?.residentBytes ?? 0
      let counterID = UUID().uuidString
      let runID = UUID().uuidString
      let descriptor = "mac-swiftui-\(ProcessInfo.processInfo.processIdentifier)"
      var seq = 0
      var peakApp: UInt64 = 0

      while !Task.isCancelled {
        seq += 1
        let sentAt = Date().timeIntervalSince1970 * 1_000
        let ops = counterUpsertOps(
          counterID: counterID,
          runID: runID,
          seq: seq,
          clientID: localClientID,
          descriptor: descriptor,
          updatedAtMs: sentAt
        )
        let mutation = try await runtime.transact(operations: ops, source: "exercise-gem.mac")
        try await waitForServerAcceptance(
          runtime: runtime,
          transactionID: mutation.transactionID,
          timeoutSeconds: 5
        )
        let rtt = Date().timeIntervalSince1970 * 1_000 - sentAt
        if let sample = InstantProcessMemory.sample() {
          let attributed =
            sample.residentBytes > baseline ? sample.residentBytes - baseline : 0
          peakApp = max(peakApp, attributed)
        }
        let row = LiveRow(
          id: UUID().uuidString,
          seq: seq,
          rttMs: rtt,
          clientId: localClientID,
          descriptor: descriptor,
          at: Date()
        )
        await MainActor.run {
          self.rows.insert(row, at: 0)
          if self.rows.count > 100 { self.rows.removeLast(self.rows.count - 100) }
          self.lastRttMs = rtt
          self.peakAppRssMiB = Double(peakApp) / (1024 * 1024)
          self.windowCount += 1
          let elapsed = Date().timeIntervalSince(self.windowStarted)
          if elapsed >= 1 {
            self.opsPerSecond = Double(self.windowCount) / elapsed
            self.windowCount = 0
            self.windowStarted = Date()
          }
        }
      }
    } catch {
      await MainActor.run {
        self.status = "error"
        self.errorText = String(describing: error)
      }
    }
  }
}

struct ContentView: View {
  @ObservedObject var model: LiveGemModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Instant Exercise Gem — Mac").font(.headline)
        Spacer()
        Text(model.status).foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        Button("Start live") { model.start() }
        Button("Stop") { model.stop() }
        LabeledContent("ops/s") { Text(String(format: "%.1f", model.opsPerSecond)) }
        LabeledContent("RTT ms") {
          Text(model.lastRttMs.map { String(format: "%.1f", $0) } ?? "—")
        }
        LabeledContent("App RSS MiB") {
          Text(String(format: "%.1f", model.peakAppRssMiB))
        }
      }
      if !model.clientId.isEmpty {
        Text("clientId: \(model.clientId)").font(.caption).foregroundStyle(.secondary)
      }
      if !model.errorText.isEmpty {
        Text(model.errorText).foregroundStyle(.red).font(.caption)
      }
      Table(model.rows) {
        TableColumn("seq") { Text("\($0.seq)") }
        TableColumn("rtt ms") { row in
          Text(row.rttMs.map { String(format: "%.1f", $0) } ?? "")
        }
        TableColumn("clientId") { Text($0.clientId.prefix(10) + "…") }
        TableColumn("descriptor") { Text($0.descriptor) }
      }
    }
    .padding()
  }
}

// Reuse counter schema + helpers from CLI (duplicated for standalone mac target)
enum MacExerciseSchema {
  static let ns = "counters"
  static var attributes: [InstantAttribute] {
    [
      .primaryKey(namespace: ns),
      InstantAttribute(id: "\(ns)/runId", namespace: ns, name: "runId", valueType: .string, isIndexed: true),
      InstantAttribute(id: "\(ns)/name", namespace: ns, name: "name", valueType: .string, isIndexed: true),
      InstantAttribute(id: "\(ns)/value", namespace: ns, name: "value", valueType: .number, isIndexed: true),
      InstantAttribute(id: "\(ns)/seq", namespace: ns, name: "seq", valueType: .number, isIndexed: true),
      InstantAttribute(id: "\(ns)/clientId", namespace: ns, name: "clientId", valueType: .string, isIndexed: true),
      InstantAttribute(id: "\(ns)/descriptor", namespace: ns, name: "descriptor", valueType: .string, isIndexed: true),
      InstantAttribute(id: "\(ns)/payloadBytes", namespace: ns, name: "payloadBytes", valueType: .number),
      InstantAttribute(id: "\(ns)/updatedAtMs", namespace: ns, name: "updatedAtMs", valueType: .number, isIndexed: true),
    ]
  }
}

func counterUpsertOps(
  counterID: String,
  runID: String,
  seq: Int,
  clientID: String,
  descriptor: String,
  updatedAtMs: Double
) -> [InstantTripleOperation] {
  let ns = MacExerciseSchema.ns
  let now = InstantTimestamp(milliseconds: Int64(updatedAtMs))
  let txID = UUID().uuidString
  var ops: [InstantTripleOperation] = [
    .insert(
      InstantTriple(
        entityID: counterID,
        attributeID: InstantAttribute.primaryKeyID(namespace: ns),
        value: .string(counterID),
        txID: txID,
        txTime: now
      )
    ),
  ]
  let fields: [(String, InstantValue)] = [
    ("runId", .string(runID)),
    ("name", .string("mac-live")),
    ("value", .number(Double(seq))),
    ("seq", .number(Double(seq))),
    ("clientId", .string(clientID)),
    ("descriptor", .string(descriptor)),
    ("payloadBytes", .number(64)),
    ("updatedAtMs", .number(updatedAtMs)),
  ]
  for (name, value) in fields {
    ops.append(
      .insert(
        InstantTriple(
          entityID: counterID,
          attributeID: "\(ns)/\(name)",
          value: value,
          txID: txID,
          txTime: now
        )
      )
    )
  }
  return ops
}

func waitAuthenticated(_ runtime: InstantRuntime) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    if try await runtime.connectionStatus().state == .authenticated { return }
    try await Task.sleep(for: .milliseconds(25))
  }
  throw CLIError("auth timeout")
}

func waitForServerAcceptance(
  runtime: InstantRuntime,
  transactionID: String,
  timeoutSeconds: Double
) async throws {
  let stream = try await runtime.observeMutationLifecycle(id: transactionID)
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
      for await event in stream {
        switch event {
        case .serverAccepted: return
        case .failed(let m): throw CLIError("failed \(m.status)")
        case .waiting: continue
        }
      }
      throw CLIError("stream ended")
    }
    group.addTask {
      try await Task.sleep(for: .seconds(timeoutSeconds))
      throw CLIError("accept timeout")
    }
    _ = try await group.next()
    group.cancelAll()
  }
}

struct CLIError: Error, CustomStringConvertible {
  var description: String
  init(_ d: String) { description = d }
}
