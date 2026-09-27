import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Persisting a live-query result must not copy every value for every sort comparison.
///
/// Each server refresh of a subscribed query builds an `InstantPersistedLiveQueryResult`, and
/// the initializer sorts the result's facts for a deterministic stored order. The comparator used
/// to build `(entityID, attributeID, value.comparableKey)` tuples eagerly, so every comparison
/// interpolated both values into new strings, even when the entity IDs already differed. A
/// Scribe recordings page carries a 4.8 KB `buildInfo` JSON string per row, and the phone
/// refreshed its subscribed queries about 4,800 times in one hour of recording (2026-09-26).
@Suite(.serialized)
struct InstantPersistedLiveQueryResultCostTests {
  /// A recordings list page shaped like Scribe's: 12 rows, each with a large JSON field, a
  /// transcription, two preview segments, and a few attachments.
  static func recordingsPageTriples() -> [InstantTriple] {
    let time = InstantTimestamp(milliseconds: 1)
    let buildInfo = String(repeating: #"{"commit":"0123456789abcdef","branch":"main"},"#, count: 105)
    var triples: [InstantTriple] = []
    func fact(_ entityID: String, _ attributeID: String, _ value: InstantValue) {
      triples.append(
        InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: "t", txTime: time)
      )
    }
    for row in 0..<12 {
      let recording = String(format: "%08x-recording-%04d", row * 7_919, row)
      fact(recording, "recordings/title", .string("Recording \(row)"))
      fact(recording, "recordings/buildInfo", .string(buildInfo))
      fact(recording, "recordings/updatedAtMs", .number(Double(1_790_000_000_000 + row)))
      fact(recording, "recordings/startedAtMs", .number(Double(1_789_990_000_000 + row)))
      fact(recording, "recordings/durationSeconds", .number(Double(row * 60)))
      fact(recording, "recordings/speakers", .string(#"[{"id":"s1","name":"Speaker 1"}]"#))
      fact(recording, "recordings/location", .string(#"{"latitude":40.7,"longitude":-73.9}"#))
      fact(recording, "recordings/ownerUserID", .string("owner-user-id"))
      let transcription = "\(recording)-transcription"
      fact(recording, "recordings/transcriptions", .ref(transcription))
      fact(transcription, "transcriptions/segmentCount", .number(Double(row * 40)))
      fact(transcription, "transcriptions/wordCount", .number(Double(row * 400)))
      for slot in 0..<2 {
        let segment = "\(recording)-segment-\(slot)"
        fact(recording, "recordings/previewSegment\(slot == 0 ? "A" : "B")", .ref(segment))
        fact(segment, "transcriptionSegments/text", .string(String(repeating: "spoken words ", count: 20)))
        fact(segment, "transcriptionSegments/startMs", .number(Double(slot * 4_000)))
        fact(segment, "transcriptionSegments/speakerID", .string("s1"))
      }
      for attachment in 0..<6 {
        let id = "\(recording)-attachment-\(attachment)"
        fact(recording, "recordings/attachments", .ref(id))
        fact(id, "recordingAttachments/kind", .string("image"))
        fact(id, "recordingAttachments/capturedAtMs", .number(Double(attachment)))
      }
    }
    return triples.shuffled()
  }

  /// The stored order is exactly the old tuple order, including ties on entity and attribute.
  @Test
  func storedOrderMatchesTheTupleOrder() {
    let time = InstantTimestamp(milliseconds: 1)
    let ties: [InstantTriple] = [
      .init(entityID: "a", attributeID: "x/tags", value: .string("b"), txID: "t", txTime: time),
      .init(entityID: "a", attributeID: "x/tags", value: .string("a"), txID: "t", txTime: time),
      .init(entityID: "a", attributeID: "x/tags", value: .number(3), txID: "t", txTime: time),
      .init(entityID: "a", attributeID: "x/tags", value: .bool(true), txID: "t", txTime: time),
      .init(entityID: "a", attributeID: "x/link", value: .ref("z"), txID: "t", txTime: time),
      .init(entityID: "b", attributeID: "x/link", value: .null, txID: "t", txTime: time),
    ]
    let triples = (Self.recordingsPageTriples() + ties).shuffled()
    let byTuple = triples.sorted {
      ($0.entityID, $0.attributeID, $0.value.comparableKey)
        < ($1.entityID, $1.attributeID, $1.value.comparableKey)
    }
    #expect(triples.sorted(by: InstantPersistedLiveQueryResult.storedOrder) == byTuple)
  }

  @Test
  func persistingARecordingsPageDoesNotCopyValuesPerComparison() {
    let replacement = InstantLiveQueryResultReplacement(
      key: "recordings-page",
      triples: Self.recordingsPageTriples(),
      pageInfo: nil
    )
    var checksum = 0
    let cost = ThreadCPUClock.measure {
      for _ in 0..<200 {
        let result = InstantPersistedLiveQueryResult(
          replacement: replacement,
          updatedAt: InstantTimestamp(milliseconds: 2)
        )
        checksum &+= result.triples.count
      }
    }
    #expect(checksum == 200 * replacement.triples.count)
    print("PERSISTED_RESULT_COST cpu_ms=\(cost.cpuMilliseconds) wall=\(cost.wall) (200 inits of \(replacement.triples.count) facts)")
  }
}
