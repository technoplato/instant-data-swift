import Foundation
import InstantSwiftData
import LinkedInfiniteV3App

#if canImport(Darwin)
  import Darwin
#endif

// MARK: - Process metrics

/// Darwin process footprint probe (same idea as Scribe's TASK_VM_INFO sample).
public enum RecipesProcessMetricsProbe {
  public struct Snapshot: Equatable, Sendable {
    var physicalFootprintBytes: UInt64
    var residentBytes: UInt64
    var virtualBytes: UInt64
    var threadCount: UInt32
  }

  public static func sample() -> Snapshot? {
    #if canImport(Darwin)
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
      )
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
      }
      guard result == KERN_SUCCESS else { return nil }

      var threadList: thread_act_array_t?
      var threadCount: mach_msg_type_number_t = 0
      let threadsResult = task_threads(mach_task_self_, &threadList, &threadCount)
      if threadsResult == KERN_SUCCESS, let list = threadList {
        let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), size)
      }

      return Snapshot(
        physicalFootprintBytes: UInt64(info.phys_footprint),
        residentBytes: UInt64(info.resident_size),
        virtualBytes: UInt64(info.virtual_size),
        threadCount: threadsResult == KERN_SUCCESS ? threadCount : 0
      )
    #else
      return nil
    #endif
  }

  public static func formatBytes(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 {
      return String(format: "%.2f GB", mb / 1024)
    }
    if mb >= 10 {
      return String(format: "%.0f MB", mb)
    }
    return String(format: "%.1f MB", mb)
  }
}

// MARK: - Log ring

/// Newest-first in-memory log for the recipes debug panel (and optional InstantDiagnostics bridge).
@MainActor
public final class RecipesDebugLogRing: ObservableObject {
  public static let shared = RecipesDebugLogRing()

  public struct Entry: Identifiable, Equatable, Sendable {
    public var id: UInt64
    public var timestamp: Date
    public var level: String
    public var category: String
    public var name: String
    public var message: String
    public var metadataSummary: String
  }

  @Published public private(set) var entries: [Entry] = []
  @Published public private(set) var peakFootprintBytes: UInt64 = 0
  @Published public private(set) var latestMetrics: RecipesProcessMetricsProbe.Snapshot?
  @Published public private(set) var metricsHistory: [(id: UInt64, megabytes: Double)] = []

  private var nextID: UInt64 = 1
  private var metricsID: UInt64 = 1
  private let capacity = 400
  private let metricsCapacity = 72
  private var diagnosticsToken: UUID?
  private var didInstallDiagnostics = false

  private init() {}

  /// Install InstantDiagnostics file + handler once per process.
  public func installDiagnosticsBridgeIfNeeded() {
    guard !didInstallDiagnostics else { return }
    didInstallDiagnostics = true

    installLinkedInfiniteLogSinkIfNeeded()

    let logURL =
      FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-instant-swift-data.jsonl", isDirectory: false)
    InstantDiagnostics.shared.configure(
      InstantDiagnosticsConfiguration(fileURL: logURL, minimumLevel: .info)
    )
    diagnosticsToken = InstantDiagnostics.shared.addHandler { [weak self] entry in
      Task { @MainActor in
        self?.append(
          level: entry.level.rawValue,
          category: entry.category,
          name: entry.event,
          message: entry.message,
          metadata: entry.metadata
        )
      }
    }
    append(
      level: "info",
      category: "recipes-debug",
      name: "diagnostics.bridge.ready",
      message: "InstantDiagnostics bridged into recipes debug panel.",
      metadata: [
        "fileURL": logURL.path,
        "linkedInfiniteLog": LinkedInfiniteDurableLog.path,
      ]
    )
  }

  public func append(
    level: String,
    category: String,
    name: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    let id = nextID
    nextID &+= 1
    let meta = metadata
      .sorted { $0.key < $1.key }
      .prefix(8)
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: " ")
    let entry = Entry(
      id: id,
      timestamp: Date(),
      level: level,
      category: category,
      name: name,
      message: message,
      metadataSummary: meta
    )
    entries.insert(entry, at: 0)
    if entries.count > capacity {
      entries.removeLast(entries.count - capacity)
    }
  }

  public func recordMetricsSample() {
    guard let snapshot = RecipesProcessMetricsProbe.sample() else { return }
    latestMetrics = snapshot
    peakFootprintBytes = max(peakFootprintBytes, snapshot.physicalFootprintBytes)
    let id = metricsID
    metricsID &+= 1
    let mb = Double(snapshot.physicalFootprintBytes) / 1_048_576
    metricsHistory.append((id: id, megabytes: mb))
    if metricsHistory.count > metricsCapacity {
      metricsHistory.removeFirst(metricsHistory.count - metricsCapacity)
    }
  }

  public func clearLogs() {
    entries.removeAll(keepingCapacity: true)
    append(
      level: "info",
      category: "recipes-debug",
      name: "logs.cleared",
      message: "In-memory panel logs cleared.",
      metadata: [:]
    )
  }

  /// Failed outbox rows for the debug panel (newest-first).
  @Published public private(set) var failedOutboxRows: [RecipesOutboxFailureRow] = []
  @Published public private(set) var outboxRefreshError: String?

  public func refreshFailedOutbox(using client: InstantSwiftDataClient) async {
    do {
      let failed = try await client.failedMutations()
      failedOutboxRows = failed
        .sorted { $0.createdAt.milliseconds > $1.createdAt.milliseconds }
        .map(RecipesOutboxFailureRow.init(mutation:))
      outboxRefreshError = nil
    } catch {
      outboxRefreshError = String(describing: error)
    }
  }
}

/// One failed outbox mutation, ready for the panel (id + human reason).
public struct RecipesOutboxFailureRow: Identifiable, Hashable, Sendable {
  public var id: String
  public var status: String
  public var failureMessage: String
  public var plainEnglish: String
  public var isLegacyUnknownOverlay: Bool

  public init(mutation: PendingMutation) {
    id = mutation.id
    status = mutation.status.rawValue
    let message = mutation.failureMessage ?? "(no failure message)"
    failureMessage = message
    // Pre-overlay rows were written before optimisticOverlayState existed. The
    // library refuses to invent their local cache effect for retry/discard, but
    // still isolates them so live apply continues (#134).
    isLegacyUnknownOverlay = mutation.isLegacyUnknownOverlayCandidate
    plainEnglish =
      if isLegacyUnknownOverlay {
        """
        Old failed write from before the library stored optimistic-overlay metadata. \
        It is isolated (not retried, not discarded automatically) so it cannot kill live sync. \
        Wipe the local recipes database if you do not need this write.
        """
      } else {
        "Server rejected this write. Inspect the message; discard or fix schema/data, then retry."
      }
  }
}

extension RecipesDebugLogRing {
  /// Best-effort local SQLite wipe for the recipes app id.
  /// Caller should close the Instant connection first, then restart the host.
  public static func wipeLocalRecipesCache(appID: String) throws -> URL {
    #if os(macOS)
      let home = FileManager.default.homeDirectoryForCurrentUser
    #else
      // iOS/tvOS/watchOS: prefer Application Support under the app container.
      let home =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    #endif
    let directory = home.appendingPathComponent(".instant-swift-data/apps", isDirectory: true)
    let base = directory.appendingPathComponent("\(appID).sqlite")
    let candidates = [
      base,
      URL(fileURLWithPath: base.path + "-wal"),
      URL(fileURLWithPath: base.path + "-shm"),
    ]
    for url in candidates {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
    return base
  }

  public func copyableSummary(recipeLabel: String) -> String {
    var lines: [String] = []
    lines.append("recipes-v3 debug panel")
    lines.append("recipe: \(recipeLabel)")
    lines.append("pid: \(ProcessInfo.processInfo.processIdentifier)")
    lines.append("host: \(ProcessInfo.processInfo.hostName)")
    if let metrics = latestMetrics {
      lines.append(
        "footprint: \(RecipesProcessMetricsProbe.formatBytes(metrics.physicalFootprintBytes))"
      )
      lines.append(
        "resident: \(RecipesProcessMetricsProbe.formatBytes(metrics.residentBytes))"
      )
      lines.append(
        "virtual: \(RecipesProcessMetricsProbe.formatBytes(metrics.virtualBytes))"
      )
      lines.append("threads: \(metrics.threadCount)")
    }
    lines.append(
      "peakFootprint: \(RecipesProcessMetricsProbe.formatBytes(peakFootprintBytes))"
    )
    lines.append("linkedInfiniteLog: \(LinkedInfiniteDurableLog.path)")
    lines.append("--- logs (newest first) ---")
    for entry in entries.prefix(80) {
      let ts = ISO8601DateFormatter().string(from: entry.timestamp)
      lines.append(
        "[\(ts)] \(entry.level) \(entry.category)/\(entry.name) \(entry.message) \(entry.metadataSummary)"
      )
    }
    return lines.joined(separator: "\n")
  }
}

// MARK: - Durable log fan-in

extension RecipesDebugLogRing {
  /// Mirror Linked Infinite durable JSONL into the panel ring.
  public func installLinkedInfiniteLogSinkIfNeeded() {
    LinkedInfiniteDurableLog.setDebugSink { event, fields in
      Task { @MainActor in
        RecipesDebugLogRing.shared.append(
          level: "info",
          category: "linked-infinite",
          name: event,
          message: event,
          metadata: fields
        )
      }
    }
  }
}
