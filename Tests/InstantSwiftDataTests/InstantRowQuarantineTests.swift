import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// #278. On 2026-09-27 an iPhone's playback detail fetch failed with "Expected number for selected
/// Instant field 'wallClockStartedAtMs'": one section whose local facts had been partly pruned failed
/// the whole query, and recording 008 showed 27 of 237 sections. A row that fails to decode is left
/// out and reported loudly; the rest of the result still loads.
@Suite(.serialized)
struct InstantRowQuarantineTests {
  @Test
  func oneDamagedRowIsLeftOutAndReportedWhileTheRestOfTheQueryLoads() async throws {
    try await withQuarantineDatabase { db in
      try await seedSections(db, damagedIndex: 2)
      let diagnostics = QuarantineDiagnostics()
      let token = InstantDiagnostics.shared.addHandler { entry in
        diagnostics.record(entry)
      }
      defer { InstantDiagnostics.shared.removeHandler(token) }

      var sections: [QuarantineSection] = []
      try await withKnownIssue {
        sections = try await db.query(QuarantineSection.recordingQuery)
      } matching: { issue in
        issue.description.contains("section-2") && issue.description.contains("wallClockStartedAtMs")
      }

      expectNoDifference(sections.map(\.id.rawValue), ["section-0", "section-1", "section-3"])
      let records = diagnostics.quarantines()
      expectNoDifference(records.count, 1)
      expectNoDifference(records.first?["namespace"], QuarantineSection.instantNamespace)
      expectNoDifference(records.first?["quarantinedCount"], "1")
      expectNoDifference(records.first?["rowCount"], "4")
      expectNoDifference(records.first?["entityIDs"], "section-2")
      expectNoDifference(records.first?["path"], "wallClockStartedAtMs")
    }
  }

  @Test
  func aLiveQueryReportsADamagedRowOnceAndKeepsDeliveringGoodRows() async throws {
    try await withQuarantineDatabase { db in
      try await seedSections(db, damagedIndex: 1)
      let diagnostics = QuarantineDiagnostics()
      let token = InstantDiagnostics.shared.addHandler { entry in
        diagnostics.record(entry)
      }
      defer { InstantDiagnostics.shared.removeHandler(token) }

      try await withKnownIssue {
        let subscription = await db.subscribe(QuarantineSection.recordingQuery)
        var iterator = subscription.makeAsyncIterator()
        let first = try await iterator.next()
        expectNoDifference(first?.map(\.id.rawValue), ["section-0", "section-2", "section-3"])

        try await db.transact { QuarantineSection.goodCreate(index: 4) }
        var latest = first
        while latest?.count != 4 {
          latest = try await iterator.next()
        }
        expectNoDifference(
          latest?.map(\.id.rawValue),
          ["section-0", "section-2", "section-3", "section-4"]
        )
        subscription.cancel()
      } matching: { issue in
        issue.description.contains("section-1")
      }

      expectNoDifference(diagnostics.quarantines().map { $0["entityIDs"] }, ["section-1"])
    }
  }

  @Test
  func damagedIncludedChildrenAndRootsAreLeftOutOfAMappedFetch() async throws {
    try await withQuarantineDatabase { db in
      try await db.transact {
        QuarantineRecording.create(
          id: InstantID(rawValue: "recording-a"),
          QuarantineRecording.title.set("A"),
          QuarantineRecording.rank.set(1)
        )
        QuarantineRecording.create(
          id: InstantID(rawValue: "recording-b"),
          QuarantineRecording.title.set("B"),
          QuarantineRecording.rank.set(2)
        )
      }
      try await seedSections(db, damagedIndex: 2)
      try await db.transact {
        for index in 0..<4 {
          QuarantineSection.update(
            id: InstantID(rawValue: "section-\(index)"),
            QuarantineSection.recording.set(InstantID(rawValue: "recording-a"))
          )
        }
        // A recording row missing its required title.
        QuarantineRecording.update(id: InstantID(rawValue: "recording-c"), QuarantineRecording.rank.set(3))
      }

      let request = InstantFetchRequest(
        QuarantineRecording.query
          .order(QuarantineRecording.rank)
          .include(QuarantineRecording.sections, QuarantineSection.query.order(QuarantineSection.segmentIndex)),
        children: QuarantineRecording.sections,
        map: { recording, sections in
          "\(recording.title): \(sections.map(\.id.rawValue).joined(separator: ","))"
        }
      )
      var rows: [String] = []
      try await withKnownIssue {
        rows = try await request.load(using: db)
      } matching: { issue in
        issue.description.contains("section-2") || issue.description.contains("recording-c")
      }

      expectNoDifference(rows, ["A: section-0,section-1,section-3", "B: "])
    }
  }
}

// MARK: - Fixture

private let quarantineRecordingID = "recording-a"

private func withQuarantineDatabase(
  _ body: (InstantSwiftDataClient) async throws -> Void
) async throws {
  let persistenceURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-row-quarantine-\(UUID().uuidString).sqlite")
  defer { try? FileManager.default.removeItem(at: persistenceURL) }
  try await withDependencies {
    try await $0.bootstrapInstantSwiftData(
      appID: "row-quarantine-\(UUID().uuidString)",
      persistenceURL: persistenceURL,
      context: .test,
      initialAttributes: QuarantineRecording.instantAttributes + QuarantineSection.instantAttributes
    )
  } operation: {
    @Dependency(\.defaultInstantSwiftData) var db
    try await body(db)
  }
}

/// Four sections of one recording. The damaged one keeps its id, recording, and index but lost
/// `wallClockStartedAtMs`, the shape a pruned section had on the iPhone.
private func seedSections(_ db: InstantSwiftDataClient, damagedIndex: Int) async throws {
  try await db.transact {
    for index in 0..<4 where index != damagedIndex {
      QuarantineSection.goodCreate(index: index)
    }
    QuarantineSection.update(
      id: InstantID(rawValue: "section-\(damagedIndex)"),
      QuarantineSection.recordingID.set(quarantineRecordingID),
      QuarantineSection.segmentIndex.set(Double(damagedIndex)),
      QuarantineSection.text.set("damaged")
    )
  }
}

@InstantEntity("quarantine_recordings")
private struct QuarantineRecording: Hashable, Codable, InstantEntityModel {
  var id: InstantID<QuarantineRecording>
  var title: String
  var rank: Double?

  static let title = InstantAttributePath<QuarantineRecording, String>("title")
  static let rank = InstantAttributePath<QuarantineRecording, Double?>("rank")
  static let sections = InstantReverseRelation<QuarantineRecording, QuarantineSection>("sections")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.value(Self.title, operation: "decode quarantine recording")
    rank = try snapshot.value(Self.rank, operation: "decode quarantine recording")
  }
}

@InstantEntity("quarantine_sections")
private struct QuarantineSection: Hashable, Codable, InstantEntityModel {
  var id: InstantID<QuarantineSection>
  var recordingID: String
  var segmentIndex: Double
  var wallClockStartedAtMs: Double
  var text: String

  @InstantRelation(reverse: "sections")
  var recording: InstantID<QuarantineRecording>?

  static let recordingID = InstantAttributePath<QuarantineSection, String>("recordingID")
  static let segmentIndex = InstantAttributePath<QuarantineSection, Double>("segmentIndex")
  static let wallClockStartedAtMs = InstantAttributePath<QuarantineSection, Double>("wallClockStartedAtMs")
  static let text = InstantAttributePath<QuarantineSection, String>("text")
  static let recording = InstantAttributePath<QuarantineSection, InstantID<QuarantineRecording>?>("recording")

  static var recordingQuery: InstantEntityQuery<QuarantineSection> {
    query
      .where(recordingID == quarantineRecordingID)
      .order(segmentIndex)
  }

  static func goodCreate(index: Int) -> InstantMutation {
    create(
      id: InstantID(rawValue: "section-\(index)"),
      recordingID.set(quarantineRecordingID),
      segmentIndex.set(Double(index)),
      wallClockStartedAtMs.set(1_790_000_000_000 + Double(index) * 1_000),
      text.set("section \(index)")
    )
  }

  init(snapshot: InstantEntitySnapshot) throws {
    let operation = "decode quarantine section"
    id = InstantID(rawValue: snapshot.id)
    recordingID = try snapshot.value(Self.recordingID, operation: operation)
    segmentIndex = try snapshot.value(Self.segmentIndex, operation: operation)
    wallClockStartedAtMs = try snapshot.value(Self.wallClockStartedAtMs, operation: operation)
    text = try snapshot.value(Self.text, operation: operation)
    recording = try snapshot.value(Self.recording, operation: operation)
  }
}

private final class QuarantineDiagnostics: @unchecked Sendable {
  private let lock = NSLock()
  private var records: [[String: String]] = []

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.event == "query.row-decode-quarantined" else { return }
    lock.withLock { records.append(entry.metadata) }
  }

  func quarantines() -> [[String: String]] {
    lock.withLock { records }
  }
}
