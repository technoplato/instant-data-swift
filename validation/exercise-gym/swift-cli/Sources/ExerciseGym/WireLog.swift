import Foundation
import InstantSwiftDataCore

/// Thread-safe capture of Instant live WebSocket frames for the exercise gym.
actor WireLog {
  struct Frame: Sendable {
    var id: Int
    var atMs: Int64
    var direction: String
    var op: String
    var clientEventId: String?
    var byteLength: Int
    var body: String
    var txStepCount: Int?
    var txStepOps: [String: Int]
  }

  private var frames: [Frame] = []
  private var nextID = 1
  private var clientId: String
  private var descriptor: String
  private let runId: String
  private let suite: String

  init(clientId: String, descriptor: String, runId: String, suite: String) {
    self.clientId = clientId
    self.descriptor = descriptor
    self.runId = runId
    self.suite = suite
  }

  func setIdentity(clientId: String, descriptor: String) {
    self.clientId = clientId
    self.descriptor = descriptor
  }

  func record(direction: String, message: InstantLiveMessage) {
    // Rebuild a JSON object from InstantLiveJSONValue so nested tx-steps are not
    // lost to InstantLiveMessage's Codable re-encode edge cases.
    var object: [String: Any] = ["op": message.op]
    if let clientEventID = message.clientEventID {
      object["client-event-id"] = clientEventID
    }
    for (key, value) in message.fields {
      object[key] = jsonObject(from: value)
    }
    let data =
      (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
      ?? Data()
    let body = String(data: data, encoding: .utf8) ?? ""
    var stepCount: Int?
    var stepOps: [String: Int] = [:]
    if message.op == "transact" {
      if let steps = object["tx-steps"] as? [Any] {
        stepCount = steps.count
        for item in steps {
          if let parts = item as? [Any], let first = parts.first as? String {
            stepOps[first, default: 0] += 1
          }
        }
      } else if let steps = message.fields["tx-steps"]?.arrayValue {
        stepCount = steps.count
        for item in steps {
          if let parts = item.arrayValue, let first = parts.first?.stringValue {
            stepOps[first, default: 0] += 1
          }
        }
      }
    }
    frames.append(
      Frame(
        id: nextID,
        atMs: Int64(Date().timeIntervalSince1970 * 1_000),
        direction: direction,
        op: message.op,
        clientEventId: message.clientEventID,
        byteLength: data.count,
        body: body,
        txStepCount: stepCount,
        txStepOps: stepOps
      )
    )
    nextID += 1
  }

  private func jsonObject(from value: InstantLiveJSONValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case .bool(let value):
      return value
    case .number(let value):
      return value
    case .string(let value):
      return value
    case .array(let values):
      return values.map(jsonObject(from:))
    case .object(let values):
      return values.mapValues(jsonObject(from:))
    }
  }

  func writeJSONL(to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var lines: [String] = []
    for frame in frames {
      let row: [String: Any] = [
        "id": frame.id,
        "atMs": frame.atMs,
        "direction": frame.direction,
        "op": frame.op,
        "clientEventId": frame.clientEventId as Any,
        "byteLength": frame.byteLength,
        "body": frame.body,
        "txStepCount": frame.txStepCount as Any,
        "txStepOps": frame.txStepOps,
        "clientId": clientId,
        "descriptor": descriptor,
        "runId": runId,
        "suite": suite,
        "side": "swift",
      ]
      let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
      if let line = String(data: data, encoding: .utf8) {
        lines.append(line)
      }
    }
    try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
      .write(to: url, atomically: true, encoding: .utf8)
  }

  struct Summary: Sendable {
    var frames: Int
    var outbound: Int
    var inbound: Int
    var totalBytes: Int
    var byOp: [String: Int]
    var outboundTransact: Int
    var transactBytesTotal: Int
    var transactBytesP50: Int
    var transactBytesMax: Int
    var stepCountP50: Int
    var stepCountMin: Int
    var stepCountMax: Int
    var stepOpHist: [String: Int]

    func asDictionary() -> [String: Any] {
      [
        "frames": frames,
        "outbound": outbound,
        "inbound": inbound,
        "totalBytes": totalBytes,
        "byOp": byOp,
        "outboundTransact": outboundTransact,
        "transactBytesTotal": transactBytesTotal,
        "transactBytesP50": transactBytesP50,
        "transactBytesMax": transactBytesMax,
        "stepCountP50": stepCountP50,
        "stepCountMin": stepCountMin,
        "stepCountMax": stepCountMax,
        "stepOpHist": stepOpHist,
      ]
    }
  }

  func summary() -> Summary {
    var byOp: [String: Int] = [:]
    var outbound = 0
    var inbound = 0
    var totalBytes = 0
    var txBytes: [Int] = []
    var stepCounts: [Int] = []
    var stepOpHist: [String: Int] = [:]
    for f in frames {
      byOp[f.op, default: 0] += 1
      totalBytes += f.byteLength
      if f.direction == "outbound" {
        outbound += 1
        if f.op == "transact" {
          txBytes.append(f.byteLength)
          if let c = f.txStepCount { stepCounts.append(c) }
          for (k, v) in f.txStepOps { stepOpHist[k, default: 0] += v }
        }
      } else {
        inbound += 1
      }
    }
    txBytes.sort()
    stepCounts.sort()
    return Summary(
      frames: frames.count,
      outbound: outbound,
      inbound: inbound,
      totalBytes: totalBytes,
      byOp: byOp,
      outboundTransact: txBytes.count,
      transactBytesTotal: txBytes.reduce(0, +),
      transactBytesP50: percentile(txBytes, 0.5),
      transactBytesMax: txBytes.last ?? 0,
      stepCountP50: percentile(stepCounts, 0.5),
      stepCountMin: stepCounts.first ?? 0,
      stepCountMax: stepCounts.last ?? 0,
      stepOpHist: stepOpHist
    )
  }
}

private func percentile(_ values: [Int], _ p: Double) -> Int {
  guard !values.isEmpty else { return 0 }
  let idx = min(values.count - 1, max(0, Int(ceil(p * Double(values.count))) - 1))
  return values[idx]
}

/// Live transport that wraps `.live` and records every send/receive frame.
enum LoggingLiveTransport {
  static func make(wireLog: WireLog) -> InstantLiveTransportClient {
    InstantLiveTransportClient { request in
      let inner = try await InstantLiveTransportClient.live.connect(request)
      return InstantLiveWebSocketSession(
        send: { message in
          await wireLog.record(direction: "outbound", message: message)
          try await inner.send(message)
        },
        receive: {
          let message = try await inner.receive()
          await wireLog.record(direction: "inbound", message: message)
          return message
        },
        close: {
          await inner.close()
        }
      )
    }
  }
}
