import CryptoKit
import Foundation
import os

public struct InstantDBLogSpoolLimits: Equatable, Sendable {
  public var maximumRows: Int
  public var maximumBytes: Int
  public var maximumAge: TimeInterval

  public init(
    maximumRows: Int,
    maximumBytes: Int,
    maximumAge: TimeInterval
  ) {
    self.maximumRows = max(1, maximumRows)
    self.maximumBytes = max(1, maximumBytes)
    self.maximumAge = max(0, maximumAge)
  }

  public static let device = Self(
    maximumRows: 4_096,
    maximumBytes: InstantDBLogWireLimits.maximumDeviceSpoolBytes,
    maximumAge: 7 * 24 * 60 * 60
  )

  public static let collector = Self(
    maximumRows: 50_000,
    maximumBytes: 64 * 1_024 * 1_024,
    maximumAge: 14 * 24 * 60 * 60
  )
}

enum InstantDBLogSpoolError: Error, Equatable, LocalizedError, Sendable {
  case malformedRow(reason: String)
  case rowExceedsMaximumBytes(actual: Int, maximum: Int)

  var errorDescription: String? {
    switch self {
    case .malformedRow(let reason):
      "Diagnostics row is not valid JSONL evidence: \(reason)"
    case .rowExceedsMaximumBytes(let actual, let maximum):
      "Diagnostics row is \(actual) bytes and exceeds the \(maximum)-byte absolute limit."
    }
  }
}

struct InstantDBLogSpoolRecord: Equatable, Sendable {
  var id: String
  var isProtectedEvidence: Bool
  var line: Data
  var timestampMs: Double
}

struct InstantDBLogSpoolStatistics: Equatable, Sendable {
  var byteCount: Int
  var rowCount: Int
}

/// A crash-recoverable JSON-lines journal with hard row, byte, and age ceilings.
///
/// Callers enqueue work onto a bounded utility buffer; this actor intentionally performs file I/O
/// serially so a partially written final row can be discarded without corrupting earlier evidence.
actor InstantDBLogJSONLSpool {
  private struct Header: Decodable {
    var id: String?
    var isProtectedEvidence: Bool?
    var issueReferences: [IssueLogReference]?
    var level: String?
    var timestampMs: Double
  }

  private let limits: InstantDBLogSpoolLimits
  private let now: @Sendable () -> Date
  private let reportFailure: @Sendable (String) -> Void
  private let url: URL
  private var reportedFailureCount = 0
  private var fileHandle: FileHandle?
  private var isLoaded = false
  private var storage: [InstantDBLogSpoolRecord] = []

  init(
    url: URL,
    limits: InstantDBLogSpoolLimits = .device,
    now: @escaping @Sendable () -> Date = { Date() },
    reportFailure: @escaping @Sendable (String) -> Void = { message in
      Logger(subsystem: "InstantDBLogger", category: "JSONLSpool").error(
        "\(message, privacy: .public)"
      )
    }
  ) {
    self.limits = limits
    self.now = now
    self.reportFailure = reportFailure
    self.url = url
  }

  deinit {
    try? fileHandle?.close()
  }

  func append(_ record: InstantDBLogSpoolRecord) throws {
    guard record.line.count <= limits.maximumBytes else {
      throw InstantDBLogSpoolError.rowExceedsMaximumBytes(
        actual: record.line.count,
        maximum: limits.maximumBytes
      )
    }
    try loadIfNeeded()
    storage.append(record)
    let didPrune = prune()
    if didPrune {
      try rewrite()
    } else {
      try writableFileHandle().write(contentsOf: record.line)
    }
  }

  func append(line: Data) throws {
    try append(Self.record(from: Self.normalized(line)))
  }

  func records(limit: Int? = nil) throws -> [InstantDBLogSpoolRecord] {
    try loadIfNeeded()
    if prune() {
      try rewrite()
    }
    guard let limit else { return storage }
    return Array(storage.prefix(max(0, limit)))
  }

  func acknowledge(ids: Set<String>) throws {
    guard !ids.isEmpty else { return }
    try loadIfNeeded()
    let priorCount = storage.count
    storage.removeAll { ids.contains($0.id) }
    if storage.count != priorCount {
      try rewrite()
    }
  }

  func containsAny(ids: Set<String>) throws -> Bool {
    try loadIfNeeded()
    return storage.contains { ids.contains($0.id) }
  }

  func statistics() throws -> InstantDBLogSpoolStatistics {
    let records = try records()
    return InstantDBLogSpoolStatistics(
      byteCount: records.reduce(into: 0) { $0 += $1.line.count },
      rowCount: records.count
    )
  }

  func synchronize() throws {
    try loadIfNeeded()
    try fileHandle?.synchronize()
  }

  private func loadIfNeeded() throws {
    guard !isLoaded else { return }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    guard FileManager.default.fileExists(atPath: url.path) else {
      try Data().write(to: url, options: .atomic)
      try enforcePrivatePermissions()
      let handle = try FileHandle(forWritingTo: url)
      _ = try handle.seekToEnd()
      fileHandle = handle
      isLoaded = true
      return
    }

    let data = try Data(contentsOf: url)
    let endedOnRowBoundary = data.isEmpty || data.last == Character("\n").asciiValue
    var slices = data.split(
      separator: Character("\n").asciiValue!,
      omittingEmptySubsequences: false
    )
    if !slices.isEmpty {
      slices.removeLast()
    }
    var recovered: [InstantDBLogSpoolRecord] = []
    var malformedRowCount = 0
    var firstMalformedRow: (line: Int, reason: String)?
    for (index, slice) in slices.enumerated() {
      do {
        recovered.append(try Self.record(from: Self.normalized(Data(slice))))
      } catch {
        malformedRowCount += 1
        if firstMalformedRow == nil {
          firstMalformedRow = (index + 1, error.localizedDescription)
        }
      }
    }
    storage = recovered
    if let firstMalformedRow {
      reportBoundedFailure(
        "Diagnostics journal \(url.path) omitted \(malformedRowCount) malformed complete JSON "
          + "row(s); first failure at line \(firstMalformedRow.line): "
          + firstMalformedRow.reason
      )
    }
    let retainedByteCount = storage.reduce(into: 0) { $0 += $1.line.count }
    let needsRepair =
      !endedOnRowBoundary
      || malformedRowCount > 0
      || retainedByteCount != data.count
    if prune() || needsRepair {
      try rewrite()
    } else {
      try enforcePrivatePermissions()
      let handle = try FileHandle(forWritingTo: url)
      _ = try handle.seekToEnd()
      fileHandle = handle
    }
    isLoaded = true
  }

  @discardableResult
  private func prune() -> Bool {
    var changed = false
    let cutoffMs = (now().timeIntervalSince1970 - limits.maximumAge) * 1_000
    let priorAgeCount = storage.count
    storage.removeAll { $0.timestampMs < cutoffMs }
    changed = changed || storage.count != priorAgeCount

    var byteCount = storage.reduce(into: 0) { $0 += $1.line.count }
    while storage.count > limits.maximumRows || byteCount > limits.maximumBytes {
      let removalIndex =
        oldestIndex(where: { !$0.isProtectedEvidence })
        ?? oldestIndex(where: { _ in true })
      guard let removalIndex else { break }
      byteCount -= storage[removalIndex].line.count
      storage.remove(at: removalIndex)
      changed = true
    }
    return changed
  }

  private func oldestIndex(
    where predicate: (InstantDBLogSpoolRecord) -> Bool
  ) -> Int? {
    storage.indices
      .filter { predicate(storage[$0]) }
      .min { storage[$0].timestampMs < storage[$1].timestampMs }
  }

  private func rewrite() throws {
    try fileHandle?.close()
    fileHandle = nil
    let data = storage.reduce(into: Data()) { $0.append($1.line) }
    try data.write(to: url, options: .atomic)
    try enforcePrivatePermissions()
    let handle = try FileHandle(forWritingTo: url)
    _ = try handle.seekToEnd()
    fileHandle = handle
  }

  private func writableFileHandle() throws -> FileHandle {
    if let fileHandle { return fileHandle }
    let handle = try FileHandle(forWritingTo: url)
    _ = try handle.seekToEnd()
    fileHandle = handle
    return handle
  }

  private static func normalized(_ data: Data) -> Data {
    var data = data
    while data.last == Character("\n").asciiValue {
      data.removeLast()
    }
    data.append(Character("\n").asciiValue!)
    return data
  }

  private func enforcePrivatePermissions() throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o600)],
      ofItemAtPath: url.path
    )
  }

  private func reportBoundedFailure(_ message: String) {
    let maximumReports = 20
    if reportedFailureCount < maximumReports {
      reportedFailureCount += 1
      reportFailure(message)
    } else if reportedFailureCount == maximumReports {
      reportedFailureCount += 1
      reportFailure(
        "Further diagnostics journal failures are suppressed after \(maximumReports) reports."
      )
    }
  }

  private static func record(from line: Data) throws -> InstantDBLogSpoolRecord {
    let header: Header
    do {
      header = try JSONDecoder().decode(Header.self, from: line)
    } catch {
      throw InstantDBLogSpoolError.malformedRow(reason: error.localizedDescription)
    }
    guard header.timestampMs.isFinite else {
      throw InstantDBLogSpoolError.malformedRow(reason: "timestampMs must be finite")
    }
    let id =
      header.id?.isEmpty == false
      ? header.id!
      : SHA256.hash(data: line).map { String(format: "%02x", $0) }.joined()
    let isProtectedEvidence =
      header.isProtectedEvidence
      ?? header.level.map { $0 == "error" || $0 == "critical" }
      ?? false
      || !(header.issueReferences ?? []).isEmpty
    return InstantDBLogSpoolRecord(
      id: id,
      isProtectedEvidence: isProtectedEvidence,
      line: line,
      timestampMs: header.timestampMs
    )
  }
}
