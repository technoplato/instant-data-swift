import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite(.serialized)
struct LocalTodoValidationTests {
  @Test
  func validationEvidenceRowsEncodeDocumentedJSONKeys() throws {
    let row = ValidationEvidenceRow(
      caseID: "validation.local.todos",
      side: "swift",
      event: "seed",
      appID: "validation-test",
      entityID: "todo-1",
      timestampMs: 123,
      ok: true,
      details: LocalTodoValidationDetails(
        cachePath: "/tmp/state.sqlite",
        todoIDs: ["todo-1"],
        todoTexts: ["Ship the JSONL contract"],
        pendingMutationIDs: ["tx-1"],
        queryCacheCount: 1
      )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let object = try #require(
      JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any]
    )

    expectNoDifference(
      Set(object.keys),
      ["appID", "case", "details", "entityID", "event", "ok", "side", "timestampMs"]
    )
    expectNoDifference(object["case"] as? String, "validation.local.todos")
    expectNoDifference(object["appID"] as? String, "validation-test")
    expectNoDifference(object["entityID"] as? String, "todo-1")
    expectNoDifference((object["timestampMs"] as? NSNumber)?.int64Value, 123)
    expectNoDifference(object["caseID"] as? String, nil)

    let details = try #require(object["details"] as? [String: Any])
    expectNoDifference(details["cachePath"] as? String, "/tmp/state.sqlite")
    expectNoDifference(details["todoTexts"] as? [String], ["Ship the JSONL contract"])
  }

  @Test
  func validationEvidenceSummaryCapturesFailures() throws {
    let rows = [
      evidenceRow(event: "seed", ok: true),
      evidenceRow(event: "update", ok: false),
    ]

    let summary = InstantSwiftDataTestHarness.summarize(rows)

    expectNoDifference(summary.caseID, "validation.local.todos")
    expectNoDifference(summary.side, "swift")
    expectNoDifference(summary.appID, "validation-test")
    expectNoDifference(summary.rowCount, 2)
    expectNoDifference(summary.ok, false)
    expectNoDifference(summary.events, ["seed", "update"])
    expectNoDifference(summary.failedEvents, ["update"])

    do {
      _ = try InstantSwiftDataTestHarness.requireAllEvidenceOK(rows)
      #expect(Bool(false), "Expected failed evidence rows to throw.")
    } catch let error as InstantValidationFailure {
      expectNoDifference(error.summary, summary)
      #expect(error.description.contains("update"))
    }

    do {
      let empty: [ValidationEvidenceRow<LocalTodoValidationDetails>] = []
      _ = try InstantSwiftDataTestHarness.requireAllEvidenceOK(empty)
      #expect(Bool(false), "Expected empty evidence rows to throw.")
    } catch let error as InstantValidationFailure {
      expectNoDifference(error.summary.rowCount, 0)
      #expect(error.description.contains("at least one"))
    }
  }

  @Test
  func localTodoValidationProducesEvidenceAndPersistsCache() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runLocalTodoValidation(
      appID: "validation-test",
      cacheURL: cacheURL
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.local.todos")
    expectNoDifference(run.summary.rowCount, 8)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(
      run.summary.events,
      [
        "seed", "update", "cache", "reset", "relaunch", "offline-write",
        "offline-relaunch", "reconnect-flush",
      ]
    )
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 8))
    expectNoDifference(
      result.evidence.map(\.caseID),
      Array(repeating: "validation.local.todos", count: result.evidence.count)
    )
    expectNoDifference(result.evidence[6].details.connectionState, "closed")
    expectNoDifference(
      result.evidence[6].details.todoTexts,
      ["Validate restart restore while closed"]
    )
    expectNoDifference(result.evidence[6].details.pendingMutationIDs.count, 4)
    expectNoDifference(result.evidence.last?.details.connectionState, "opened")
    expectNoDifference(
      result.evidence.last?.details.todoTexts,
      ["Validate restart restore while closed"]
    )
    expectNoDifference(result.evidence.last?.details.pendingMutationIDs, [])
    expectNoDifference(result.evidence.last?.details.confirmedMutationIDs.count, 4)
  }

  @Test
  func localIntegrationValidationProducesEvidenceAndPersistsLocalSurfaces() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runLocalIntegrationValidation(
      appID: "validation-integrations-test",
      cacheURL: cacheURL
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-integrations-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.local.integrations")
    expectNoDifference(run.summary.rowCount, 9)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(
      run.summary.events,
      [
        "auth", "room-presence", "room-topic", "file", "stream", "share-create",
        "share-accept", "share-revoke", "relaunch",
      ]
    )
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 9))
    expectNoDifference(
      result.evidence.map(\.caseID),
      Array(repeating: "validation.local.integrations", count: result.evidence.count)
    )

    let fileEvidence = result.evidence[3].details
    expectNoDifference(fileEvidence.fileIDs.count, 1)
    expectNoDifference(fileEvidence.fileByteCounts, [23])
    expectNoDifference(fileEvidence.fileContentDigests.count, 1)

    let acceptEvidence = result.evidence[6].details
    expectNoDifference(acceptEvidence.activeShareIDs.count, 1)
    expectNoDifference(acceptEvidence.shareMemberUserIDs, ["user-1", "user-2"])

    let revokeEvidence = result.evidence[7].details
    expectNoDifference(revokeEvidence.activeShareIDs, [])
    expectNoDifference(revokeEvidence.revokedShareIDs.count, 1)
    expectNoDifference(revokeEvidence.shareMemberUserIDs, ["user-1", "user-2"])

    let relaunchEvidence = try #require(result.evidence.last?.details)
    expectNoDifference(relaunchEvidence.authUserID, "user-1")
    expectNoDifference(relaunchEvidence.roomMemberIDs, ["user-1"])
    expectNoDifference(relaunchEvidence.topicMessageIDs.count, 1)
    expectNoDifference(relaunchEvidence.fileIDs.count, 1)
    expectNoDifference(relaunchEvidence.fileContentDigests, fileEvidence.fileContentDigests)
    expectNoDifference(relaunchEvidence.streamChunkIDs.count, 1)
    expectNoDifference(relaunchEvidence.activeShareIDs, [])
  }
}

private func temporaryCacheURL() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataValidationTests-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("state.sqlite")
}

private func evidenceRow(
  event: String,
  ok: Bool
) -> ValidationEvidenceRow<LocalTodoValidationDetails> {
  ValidationEvidenceRow(
    caseID: "validation.local.todos",
    side: "swift",
    event: event,
    appID: "validation-test",
    timestampMs: 123,
    ok: ok,
    details: LocalTodoValidationDetails(
      cachePath: "/tmp/state.sqlite",
      todoIDs: [],
      todoTexts: [],
      pendingMutationIDs: [],
      queryCacheCount: 0
    )
  )
}
