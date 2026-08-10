import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// ADR 0015 / #155 — open-segment write recipe (offline, no network).
@Suite
struct OpenSegmentWriteRecipeTests {
  @Test
  func wordsJSONRoundTripsStrictly() throws {
    let words = [
      OpenSegmentWord(start: 0, end: 0.12, text: "open"),
      OpenSegmentWord(start: 0.13, end: 0.28, text: "segment"),
    ]
    let json = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
    let decoded = try OpenSegmentWriteRecipe.decodeWordsJSON(json)
    expectNoDifference(decoded, words)
    #expect(json.contains("\"text\":\"open\""))
    #expect(json.contains("\"start\":0"))
  }

  @Test
  func wordsJSONDecodeFailsLoudlyOnGarbage() {
    do {
      _ = try OpenSegmentWriteRecipe.decodeWordsJSON("{not-json")
      Issue.record("expected decode to throw")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.path, "wordsJSON")
      #expect(error.operation.contains("decode open-segment wordsJSON"))
    } catch {
      Issue.record("expected InstantError, got \(error)")
    }
  }

  @Test
  func wordsJSONDecodeFailsLoudlyOnWrongShape() {
    // Object instead of array — strict array decode must fail.
    do {
      _ = try OpenSegmentWriteRecipe.decodeWordsJSON(#"{"start":0,"end":1,"text":"x"}"#)
      Issue.record("expected decode to throw")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
    } catch {
      Issue.record("expected InstantError, got \(error)")
    }
  }

  @Test
  func openSegmentUpsertOperationsTouchOnlySegmentFields() throws {
    let words = [OpenSegmentWord(start: 0, end: 0.1, text: "hi")]
    let wordsJSON = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
    let ops = OpenSegmentWriteRecipe.openSegmentUpsertOperations(
      segmentID: "seg-1",
      recordingID: "rec-1",
      ownerUserID: "user-1",
      text: "hi",
      wordsJSON: wordsJSON,
      wordCount: 1,
      segmentIndex: 0,
      isFinal: false,
      startTimeSeconds: 0,
      endTimeSeconds: 0.1,
      updatedAtMs: 1_700_000_000_000,
      transactionID: "tx-1"
    )

    let attributeIDs = Set(ops.compactMap(\.insertedAttributeID))
    expectNoDifference(
      attributeIDs.contains(
        InstantAttribute.primaryKeyID(namespace: OpenSegmentWriteRecipe.segmentNamespace)
      ),
      true
    )
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/wordsJSON"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/ownerUserID"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/owner"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/recording"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/updatedAtMs"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/isFinal"))
    // Parent recording namespace must not appear on segment-only upsert.
    #expect(
      !attributeIDs.contains(where: {
        $0.hasPrefix(OpenSegmentWriteRecipe.recordingNamespace + "/")
      })
    )

    let wordsTriple = ops.compactMap(\.insertedTriple).first {
      $0.attributeID == "\(OpenSegmentWriteRecipe.segmentNamespace)/wordsJSON"
    }
    expectNoDifference(wordsTriple?.value, .string(wordsJSON))
    expectNoDifference(wordsTriple?.entityID, "seg-1")
  }

  @Test
  func operationsForFieldsIncludesEnsureRecordingWhenTitleSet() throws {
    let fields = OpenSegmentWriteFields(
      recordingID: "rec-1",
      segmentID: "seg-1",
      ownerUserID: "user-1",
      segmentIndex: 0,
      text: "hello world",
      words: [
        OpenSegmentWord(start: 0, end: 0.2, text: "hello"),
        OpenSegmentWord(start: 0.21, end: 0.4, text: "world"),
      ],
      isFinal: false,
      startTimeSeconds: 0,
      endTimeSeconds: 0.4,
      updatedAtMs: 42,
      ensureRecordingTitle: "Live session"
    )
    let ops = try OpenSegmentWriteRecipe.operations(for: fields, transactionID: "tx-ensure")
    let attributeIDs = Set(ops.compactMap(\.insertedAttributeID))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.recordingNamespace)/title"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.recordingNamespace)/ownerUserID"))
    #expect(attributeIDs.contains("\(OpenSegmentWriteRecipe.segmentNamespace)/wordsJSON"))

    let title = ops.compactMap(\.insertedTriple).first {
      $0.attributeID == "\(OpenSegmentWriteRecipe.recordingNamespace)/title"
    }
    expectNoDifference(title?.value, .string("Live session"))
  }

  @Test
  func operationsWithoutEnsureTitleAreSegmentOnly() throws {
    let fields = OpenSegmentWriteFields(
      recordingID: "rec-1",
      segmentID: "seg-1",
      ownerUserID: "user-1",
      segmentIndex: 2,
      text: "only segment",
      words: [OpenSegmentWord(start: 1, end: 1.1, text: "only")],
      isFinal: true,
      startTimeSeconds: 1,
      endTimeSeconds: 1.1,
      updatedAtMs: 99,
      ensureRecordingTitle: nil
    )
    let ops = try OpenSegmentWriteRecipe.operations(for: fields, transactionID: "tx-seg")
    let namespaces = Set(ops.compactMap(\.insertedTriple).map(\.entityID))
    expectNoDifference(namespaces, ["seg-1"])
    let isFinal = ops.compactMap(\.insertedTriple).first {
      $0.attributeID == "\(OpenSegmentWriteRecipe.segmentNamespace)/isFinal"
    }
    expectNoDifference(isFinal?.value, .bool(true))
  }

  @Test
  func segmentsQueryIsBoundedToRecording() {
    let plan = OpenSegmentWriteRecipe.segmentsForRecordingQuery(
      recordingID: "rec-9",
      limit: 50
    )
    expectNoDifference(plan.namespace, OpenSegmentWriteRecipe.segmentNamespace)
    expectNoDifference(plan.limit, 50)
    expectNoDifference(
      plan.filters,
      [.equals(field: "recordingID", value: .string("rec-9"))]
    )
  }

  @Test
  func recipeAttributesDeclareWordsJSONAndOwner() {
    let segmentAttrs = OpenSegmentWriteRecipe.segmentAttributes
    #expect(segmentAttrs.contains { $0.name == "wordsJSON" && $0.valueType == .string })
    #expect(segmentAttrs.contains { $0.name == "ownerUserID" && $0.valueType == .string })
    #expect(
      segmentAttrs.contains {
        $0.name == "owner" && $0.valueType == .ref && $0.linkNamespace == "$users"
      }
    )
    #expect(
      segmentAttrs.contains {
        $0.name == "recording" && $0.reverseIdentity
          == "\(OpenSegmentWriteRecipe.recordingNamespace)/segments"
      }
    )
  }
}

// MARK: - Triple op helpers for tests

extension InstantTripleOperation {
  fileprivate var insertedTriple: InstantTriple? {
    switch self {
    case let .insert(triple), let .merge(triple):
      return triple
    default:
      return nil
    }
  }

  fileprivate var insertedAttributeID: String? {
    insertedTriple?.attributeID
  }
}
