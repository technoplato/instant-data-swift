import Foundation

/// Append-only JSONL logger for diagnosing Linked Infinite paging from disk.
///
/// Default path: `/tmp/linked-infinite-debug.jsonl`
/// Override with `LINKED_INFINITE_LOG_PATH`.
public enum LinkedInfiniteDurableLog: Sendable {
  public static let defaultPath = "/tmp/linked-infinite-debug.jsonl"

  public static var path: String {
    let env = ProcessInfo.processInfo.environment["LINKED_INFINITE_LOG_PATH"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let env, !env.isEmpty { return env }
    return defaultPath
  }

  public static var fileURL: URL { URL(fileURLWithPath: path) }

  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var sessionID = UUID().uuidString.lowercased()
    var sequence: Int64 = 0
    /// Optional fan-out for in-app debug panels (set by recipes-v3).
    var sink: (@Sendable (String, [String: String]) -> Void)?
  }

  private static let state = State()

  /// Install a process-wide sink that receives every durable log line as strings.
  public static func setDebugSink(_ sink: (@Sendable (String, [String: String]) -> Void)?) {
    state.lock.lock()
    state.sink = sink
    state.lock.unlock()
  }

  public static func resetSession(reason: String) {
    state.lock.lock()
    state.sessionID = UUID().uuidString.lowercased()
    state.sequence = 0
    state.lock.unlock()
    log(
      "session.reset",
      [
        "reason": reason,
        "path": path,
        "processID": ProcessInfo.processInfo.processIdentifier,
        "host": ProcessInfo.processInfo.hostName,
      ]
    )
  }

  public static func log(_ event: String, _ fields: [String: Any] = [:]) {
    state.lock.lock()
    state.sequence += 1
    let seq = state.sequence
    let sid = state.sessionID
    let sink = state.sink
    state.lock.unlock()

    var payload: [String: Any] = [
      "ts": iso8601Now(),
      "tsMs": Int64((Date().timeIntervalSince1970 * 1000).rounded()),
      "session": sid,
      "seq": seq,
      "event": event,
      "source": "linked-infinite-recipe",
    ]
    for (key, value) in fields {
      payload[key] = sanitize(value)
    }

    if let sink {
      var stringFields: [String: String] = [
        "seq": String(seq),
        "session": sid,
      ]
      for (key, value) in fields {
        stringFields[key] = String(describing: sanitize(value))
      }
      sink(event, stringFields)
    }

    guard JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
      var line = String(data: data, encoding: .utf8)
    else {
      appendRaw("{\"event\":\"log.encode.failed\",\"rawEvent\":\(jsonString(event))}\n")
      return
    }
    line.append("\n")
    appendRaw(line)
  }

  private static func appendRaw(_ line: String) {
    let url = fileURL
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else {
      // Last-resort stderr so silence is never total.
      fputs(line, stderr)
      return
    }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    if let data = line.data(using: .utf8) {
      try? handle.write(contentsOf: data)
    }
    try? handle.synchronize()
  }

  private static func iso8601Now() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  private static func jsonString(_ value: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
  }

  private static func sanitize(_ value: Any) -> Any {
    switch value {
    case let v as String: return v
    case let v as Int: return v
    case let v as Int64: return v
    case let v as Double: return v
    case let v as Bool: return v
    case let v as [String]: return v
    case let v as [Int]: return v
    case let v as [String: Any]:
      return v.mapValues { sanitize($0) }
    case let v as [Any]:
      return v.map { sanitize($0) }
    case let v as CustomStringConvertible:
      return v.description
    default:
      return String(describing: value)
    }
  }
}
