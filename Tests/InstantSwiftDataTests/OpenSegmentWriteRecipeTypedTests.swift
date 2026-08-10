import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataCore
import Testing

/// ADR 0015 / #155 — typed InstantEntityModel sketch for open-segment recipe.
@Suite
struct OpenSegmentWriteRecipeTypedTests {
  @Test
  func segmentDecodesAndWordsJSONIsStrict() throws {
    let words = [
      OpenSegmentWord(start: 0, end: 0.1, text: "typed"),
      OpenSegmentWord(start: 0.1, end: 0.2, text: "segment"),
    ]
    let wordsJSON = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
    let snapshot = InstantEntitySnapshot(
      id: "seg-typed-1",
      namespace: OpenSegmentWriteRecipe.segmentNamespace,
      values: [
        "recording": .one(.ref("rec-typed-1")),
        "ownerUserID": .one(.string("user-1")),
        "text": .one(.string("typed segment")),
        "wordsJSON": .one(.string(wordsJSON)),
        "wordCount": .one(.number(2)),
        "segmentIndex": .one(.number(0)),
        "isFinal": .one(.bool(false)),
        "startTimeSeconds": .one(.number(0)),
        "endTimeSeconds": .one(.number(0.2)),
        "updatedAtMs": .one(.number(1_700_000_000_000)),
      ]
    )
    let segment = try OpenSegmentRecipeSegment(snapshot: snapshot)
    expectNoDifference(segment.id.rawValue, "seg-typed-1")
    expectNoDifference(segment.recordingID.rawValue, "rec-typed-1")
    expectNoDifference(try segment.words(), words)
  }

  @Test
  func recordingDecodesOwnerAndTitle() throws {
    let snapshot = InstantEntitySnapshot(
      id: "rec-typed-1",
      namespace: OpenSegmentWriteRecipe.recordingNamespace,
      values: [
        "title": .one(.string("Recipe session")),
        "ownerUserID": .one(.string("user-1")),
        "updatedAtMs": .one(.number(99)),
      ]
    )
    let recording = try OpenSegmentRecipeRecording(snapshot: snapshot)
    expectNoDifference(recording.title, "Recipe session")
    expectNoDifference(recording.ownerUserID, "user-1")
    expectNoDifference(recording.updatedAtMs, 99)
  }

  @Test
  func typedMutationsCountMatchesEnsureFlag() throws {
    let base = OpenSegmentWriteFields(
      recordingID: "rec-1",
      segmentID: "seg-1",
      ownerUserID: "user-1",
      segmentIndex: 0,
      text: "hello",
      words: [OpenSegmentWord(start: 0, end: 0.1, text: "hello")],
      isFinal: false,
      startTimeSeconds: 0,
      endTimeSeconds: 0.1,
      updatedAtMs: 10,
      ensureRecordingTitle: nil
    )
    let segmentOnly = try OpenSegmentWriteRecipeTyped.mutations(for: base)
    expectNoDifference(segmentOnly.count, 1)

    var withEnsure = base
    withEnsure.ensureRecordingTitle = "Hello"
    let both = try OpenSegmentWriteRecipeTyped.mutations(for: withEnsure)
    expectNoDifference(both.count, 2)
  }

  @Test
  func localRuntimeAppliesOpenSegmentRecipeAndTypedDecode() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("open-segment-recipe-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "open-segment-write-recipe-typed",
        persistenceURL: cacheURL,
        initialAttributes: OpenSegmentWriteRecipe.attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    let fields = OpenSegmentWriteFields(
      recordingID: "rec-local-1",
      segmentID: "seg-local-1",
      ownerUserID: "user-local-1",
      segmentIndex: 0,
      text: "local open segment",
      words: [
        OpenSegmentWord(start: 0, end: 0.15, text: "local"),
        OpenSegmentWord(start: 0.16, end: 0.35, text: "open"),
        OpenSegmentWord(start: 0.36, end: 0.55, text: "segment"),
      ],
      isFinal: false,
      startTimeSeconds: 0,
      endTimeSeconds: 0.55,
      updatedAtMs: 1_234_567_890,
      ensureRecordingTitle: "Local recipe"
    )
    let ops = try OpenSegmentWriteRecipe.operations(
      for: fields,
      transactionID: "tx-local-1"
    )
    // transact = local materialize + durable outbox only (no network in this fixture).
    _ = try await runtime.transact(operations: ops, source: "test.open-segment-recipe")

    let emission = try await runtime.queryOnce(
      OpenSegmentWriteRecipe.openSegmentQuery(segmentID: "seg-local-1")
    )
    #expect(emission.values.count == 1)
    let segment = try OpenSegmentRecipeSegment(snapshot: emission.values[0])
    expectNoDifference(segment.text, "local open segment")
    expectNoDifference(try segment.words().map(\.text), ["local", "open", "segment"])
    expectNoDifference(segment.ownerUserID, "user-local-1")
    expectNoDifference(segment.isFinal, false)

    let recordingEmission = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "recipe.open-segment.recording",
        namespace: OpenSegmentWriteRecipe.recordingNamespace,
        filters: [.equals(field: "id", value: .string("rec-local-1"))],
        limit: 1
      )
    )
    let recording = try OpenSegmentRecipeRecording(snapshot: recordingEmission.values[0])
    expectNoDifference(recording.title, "Local recipe")
  }
}
