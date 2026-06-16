import CustomDump
import Foundation
import InstantSwiftDataCLIParsing
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
  func serverTransactionLoopbackValidationProducesEvidenceAndPreservesOutbox() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runServerTransactionLoopbackValidation(
      appID: "validation-server-loopback-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_002_000_000) }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-server-loopback-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.server.transaction.loopback")
    expectNoDifference(run.summary.rowCount, 4)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(
      run.summary.events,
      ["local-outbox", "server-apply", "observer-publish", "relaunch"]
    )
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 4))

    let serverApply = try #require(result.evidence.first { $0.event == "server-apply" }?.details)
    let localOutbox = try #require(result.evidence.first { $0.event == "local-outbox" }?.details)
    expectNoDifference(serverApply.changedEntityIDs, ["validation-loopback-server"])
    expectNoDifference(serverApply.emissionQueryIDs, [TodoExample.query.id])
    expectNoDifference(serverApply.pendingMutationIDs, ["validation.loopback.local"])
    expectNoDifference(serverApply.processedTransactionID, "validation.loopback.server")
    expectNoDifference(serverApply.storeRevision, localOutbox.storeRevision + 1)
    expectNoDifference(serverApply.outboxRevision, localOutbox.outboxRevision)

    let observerPublish = try #require(
      result.evidence.first { $0.event == "observer-publish" }?.details
    )
    expectNoDifference(
      observerPublish.observerTodoIDs,
      ["validation-loopback-local", "validation-loopback-server"]
    )

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.todoIDs, ["validation-loopback-local", "validation-loopback-server"])
    expectNoDifference(finalDetails.pendingMutationIDs, ["validation.loopback.local"])
    expectNoDifference(finalDetails.pendingMutationCount, 1)
    expectNoDifference(finalDetails.processedTransactionID, "validation.loopback.server")
    expectNoDifference(finalDetails.outboxRevision, localOutbox.outboxRevision)
  }

  @Test
  func serverTransactionLoopbackValidationConsumesTypeScriptContract() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runServerTransactionLoopbackValidation(
      appID: "validation-server-loopback-typescript-test",
      cacheURL: cacheURL,
      typeScriptServerTransactionContract: TypeScriptServerTransactionContract(
        appID: "validation-server-loopback-typescript-test",
        transactionID: "validation.typescript.server.tx",
        processedTransactionID: "validation.typescript.processed",
        entityID: "validation-typescript-server",
        text: "TypeScript-authored server transaction",
        createdAtMs: 1_700_002_000_003
      ),
      timestamp: { InstantTimestamp(milliseconds: 1_700_002_000_000) }
    )
    let result = run.result

    expectNoDifference(run.summary.rowCount, 5)
    expectNoDifference(
      run.summary.events,
      [
        "local-outbox",
        "server-apply",
        "observer-publish",
        "typescript-contract-apply",
        "relaunch",
      ]
    )
    let typeScriptApply = try #require(
      result.evidence.first { $0.event == "typescript-contract-apply" }?.details
    )
    expectNoDifference(typeScriptApply.changedEntityIDs, ["validation-typescript-server"])
    expectNoDifference(typeScriptApply.emissionQueryIDs, [TodoExample.query.id])
    expectNoDifference(typeScriptApply.mutationTransactionID, "validation.typescript.server.tx")
    expectNoDifference(typeScriptApply.processedTransactionID, "validation.typescript.processed")
    expectNoDifference(
      typeScriptApply.observerTodoIDs,
      [
        "validation-loopback-local",
        "validation-loopback-server",
        "validation-typescript-server",
      ]
    )

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(
      finalDetails.todoIDs,
      [
        "validation-loopback-local",
        "validation-loopback-server",
        "validation-typescript-server",
      ]
    )
    expectNoDifference(finalDetails.pendingMutationIDs, ["validation.loopback.local"])
    expectNoDifference(finalDetails.pendingMutationCount, 1)
    expectNoDifference(finalDetails.mutationTransactionID, "validation.typescript.server.tx")
    expectNoDifference(finalDetails.processedTransactionID, "validation.typescript.processed")
    expectNoDifference(finalDetails.outboxRevision, typeScriptApply.outboxRevision)
  }

  @Test
  func serverTransactionLoopbackValidationRejectsEmptyTypeScriptContractOperations() async throws {
    do {
      _ = try await InstantSwiftDataTestHarness.runServerTransactionLoopbackValidation(
        appID: "validation-server-loopback-empty-typescript-test",
        cacheURL: temporaryCacheURL(),
        typeScriptServerTransactionContract: TypeScriptServerTransactionContract(
          appID: "validation-server-loopback-empty-typescript-test",
          transactionID: "validation.typescript.empty.tx",
          processedTransactionID: "validation.typescript.empty.processed",
          entityID: "validation-typescript-empty",
          text: "Empty TypeScript-authored server transaction",
          createdAtMs: 4_100_002_000_003,
          operations: []
        ),
        timestamp: { InstantTimestamp(milliseconds: 1_700_002_000_000) }
      )
      #expect(Bool(false), "Expected empty TypeScript contract operations to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "decode TypeScript server transaction contract")
      #expect(error.message.contains("must include at least one operation"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func cloudKitDemoValidationHarnessProvesSharedCounterRoles() async throws {
    let cacheURL = temporaryCacheURL()
    let idGenerator = ValidationIDGenerator(["cloudkit-demo-share", "cloudkit-demo-token"])

    let run = try await InstantSwiftDataTestHarness.runCloudKitDemoValidation(
      appID: "validation-cloudkit-demo-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_003_000_000) },
      makeID: { idGenerator.next() }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-cloudkit-demo-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(result.counterID, "validation-cloudkit-demo-counter")
    expectNoDifference(result.shareID, "cloudkit-demo-share")
    expectNoDifference(run.summary.caseID, "validation.cloudkit.demo")
    expectNoDifference(run.summary.rowCount, 7)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, [
      "owner-create",
      "share-create",
      "reader-accept",
      "reader-reject",
      "writer-promote",
      "writer-update",
      "relaunch",
    ])
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 7))

    let ownerCreate = try #require(result.evidence.first { $0.event == "owner-create" }?.details)
    expectNoDifference(ownerCreate.authUserID, "user-1")
    expectNoDifference(ownerCreate.counterCounts, [2])
    expectNoDifference(ownerCreate.sharedCounterIDs, [])

    let readerAccept = try #require(result.evidence.first { $0.event == "reader-accept" }?.details)
    expectNoDifference(readerAccept.authUserID, "user-2")
    expectNoDifference(readerAccept.counterIDs, ["validation-cloudkit-demo-counter"])
    expectNoDifference(readerAccept.counterCounts, [2])
    expectNoDifference(readerAccept.sharedCounterIDs, ["validation-cloudkit-demo-counter"])
    expectNoDifference(readerAccept.shareIDs, ["cloudkit-demo-share"])
    expectNoDifference(readerAccept.shareRoles, [.reader])
    expectNoDifference(readerAccept.shareMemberCounts, [2])
    expectNoDifference(readerAccept.shareMemberUserIDs, ["user-1", "user-2"])

    let readerReject = try #require(result.evidence.first { $0.event == "reader-reject" }?.details)
    expectNoDifference(readerReject.rejectedOperations, ["reader-increment"])
    expectNoDifference(readerReject.counterCounts, [2])
    expectNoDifference(readerReject.pendingMutationIDs, readerAccept.pendingMutationIDs)

    let writerPromote = try #require(result.evidence.first { $0.event == "writer-promote" }?.details)
    expectNoDifference(writerPromote.authUserID, "user-1")
    expectNoDifference(writerPromote.shareRoles, [.owner])
    expectNoDifference(writerPromote.shareMemberUserIDs, ["user-1", "user-2"])

    let writerUpdate = try #require(result.evidence.first { $0.event == "writer-update" }?.details)
    expectNoDifference(writerUpdate.authUserID, "user-2")
    expectNoDifference(writerUpdate.counterCounts, [3])
    expectNoDifference(writerUpdate.shareRoles, [.writer])

    let relaunch = try #require(result.evidence.last?.details)
    expectNoDifference(relaunch.authUserID, "user-2")
    expectNoDifference(relaunch.counterCounts, [3])
    expectNoDifference(relaunch.shareIDs, ["cloudkit-demo-share"])
    expectNoDifference(relaunch.shareRoles, [.writer])
    expectNoDifference(relaunch.shareMemberCounts, [2])
    expectNoDifference(relaunch.shareMemberUserIDs, ["user-1", "user-2"])
  }

  @Test
  func validationRunnerCloudKitDemoCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--cloudkit-demo"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --cloudkit-demo failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 7)
    expectNoDifference(
      rows.map { $0["case"] as? String ?? "" },
      Array(repeating: "validation.cloudkit.demo", count: 7)
    )
    expectNoDifference(
      rows.map { $0["appID"] as? String ?? "" },
      Array(repeating: "cloudkit-demo-validation", count: 7)
    )
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, [
      "owner-create",
      "share-create",
      "reader-accept",
      "reader-reject",
      "writer-promote",
      "writer-update",
      "relaunch",
    ])
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 7))

    let readerReject = try #require(
      rows.first { $0["event"] as? String == "reader-reject" }?["details"] as? [String: Any]
    )
    expectNoDifference(readerReject["rejectedOperations"] as? [String], ["reader-increment"])
    expectNoDifference((readerReject["counterCounts"] as? [NSNumber])?.map(\.intValue), [2])

    let relaunch = try #require(
      rows.first { $0["event"] as? String == "relaunch" }?["details"] as? [String: Any]
    )
    expectNoDifference(relaunch["authUserID"] as? String, "user-2")
    expectNoDifference((relaunch["counterCounts"] as? [NSNumber])?.map(\.intValue), [3])
    expectNoDifference(relaunch["shareRoles"] as? [String], ["writer"])
    expectNoDifference((relaunch["shareMemberCounts"] as? [NSNumber])?.map(\.intValue), [2])
    expectNoDifference(relaunch["shareMemberUserIDs"] as? [String], ["user-1", "user-2"])
  }

  @Test
  func liveSessionValidationHarnessProvesProtocolHandshakeAndQueryIngress() async throws {
    let idGenerator = ValidationIDGenerator(["event-init", "event-query"])

    let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
      appID: "validation-live-session-test",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      timestamp: { InstantTimestamp(milliseconds: 1_700_004_000_000) },
      makeID: { idGenerator.next() }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-live-session-test")
    expectNoDifference(
      result.websocketURL.absoluteString,
      "wss://ws.example.test/runtime/session?app_id=validation-live-session-test"
    )
    expectNoDifference(run.summary.caseID, "validation.live.session")
    expectNoDifference(run.summary.rowCount, 5)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
    ])
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 5))

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.sentOps, ["init", "add-query"])
    expectNoDifference(finalDetails.receivedOps, ["init-ok", "add-query-ok"])
    expectNoDifference(finalDetails.clientEventIDs, ["event-init", "event-query"])
    expectNoDifference(finalDetails.sessionID, "local-session-validation-live-session-test")
    expectNoDifference(finalDetails.proofLevel, "local-protocol")
    expectNoDifference(finalDetails.remoteBoundary, "pending-cross-client-sync")
  }

  @Test
  func liveSessionValidationHarnessCanProveLocalTransaction() async throws {
    let idGenerator = ValidationIDGenerator(["event-init", "event-query", "event-tx"])

    let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
      appID: "validation-live-transaction-test",
      caseID: "validation.live.transaction",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      includeTransaction: true,
      timestamp: { InstantTimestamp(milliseconds: 1_700_004_000_000) },
      makeID: { idGenerator.next() }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-live-transaction-test")
    expectNoDifference(run.summary.caseID, "validation.live.transaction")
    expectNoDifference(run.summary.rowCount, 8)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
      "send-transact",
      "receive-transact-ok",
      "receive-transaction-refresh",
    ])
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 8))

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.sentOps, ["init", "add-query", "transact"])
    expectNoDifference(finalDetails.receivedOps, [
      "init-ok", "add-query-ok", "transact-ok", "refresh-ok",
    ])
    expectNoDifference(finalDetails.clientEventIDs, ["event-init", "event-query", "event-tx"])
    expectNoDifference(finalDetails.transactionID, "local-event-tx")
    expectNoDifference(finalDetails.transactionISN, "local-isn-event-tx")
    expectNoDifference(finalDetails.processedTransactionID, "local-event-tx")
  }

  @Test
  func validationRunnerLiveSessionCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--live-session"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --live-session failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 5)
    expectNoDifference(
      rows.map { $0["case"] as? String ?? "" },
      Array(repeating: "validation.live.session", count: 5)
    )
    expectNoDifference(
      rows.map { $0["appID"] as? String ?? "" },
      Array(repeating: "live-session-validation", count: 5)
    )
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
    ])
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 5))

    let finalDetails = try #require(rows.last?["details"] as? [String: Any])
    expectNoDifference(finalDetails["sentOps"] as? [String], ["init", "add-query"])
    expectNoDifference(finalDetails["receivedOps"] as? [String], ["init-ok", "add-query-ok"])
    expectNoDifference(finalDetails["sessionID"] as? String, "local-session-live-session-validation")
    expectNoDifference(finalDetails["proofLevel"] as? String, "local-protocol")
    expectNoDifference(finalDetails["remoteBoundary"] as? String, "pending-cross-client-sync")
  }

  @Test
  func validationRunnerLiveTransactionCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--live-transaction"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --live-transaction failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 8)
    expectNoDifference(
      rows.map { $0["case"] as? String ?? "" },
      Array(repeating: "validation.live.transaction", count: 8)
    )
    expectNoDifference(
      rows.map { $0["appID"] as? String ?? "" },
      Array(repeating: "live-transaction-validation", count: 8)
    )
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
      "send-transact",
      "receive-transact-ok",
      "receive-transaction-refresh",
    ])
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 8))

    let finalDetails = try #require(rows.last?["details"] as? [String: Any])
    expectNoDifference(finalDetails["sentOps"] as? [String], ["init", "add-query", "transact"])
    expectNoDifference(finalDetails["receivedOps"] as? [String], [
      "init-ok", "add-query-ok", "transact-ok", "refresh-ok",
    ])
    expectNoDifference(finalDetails["transactionID"] as? String != nil, true)
    expectNoDifference(finalDetails["transactionISN"] as? String != nil, true)
    expectNoDifference(finalDetails["processedTransactionID"] as? String != nil, true)
    expectNoDifference(finalDetails["proofLevel"] as? String, "local-protocol")
  }

  @Test
  func validationRunnerCloudKitDemoFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--cloudkit-demo"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.cloudkit.demo"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.cloudkit.demo")
    expectNoDifference(row["appID"] as? String, "cloudkit-demo-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
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

    let presenceEvidence = result.evidence[1].details
    expectNoDifference(presenceEvidence.roomType, "chat")
    expectNoDifference(presenceEvidence.roomID, "validation")
    expectNoDifference(presenceEvidence.topic, "sendEmoji")
    expectNoDifference(presenceEvidence.roomMemberIDs, ["user-1"])
    expectNoDifference(presenceEvidence.roomPresenceValueKeys, ["name", "status"])

    let topicEvidence = result.evidence[2].details
    expectNoDifference(topicEvidence.roomType, "chat")
    expectNoDifference(topicEvidence.roomID, "validation")
    expectNoDifference(topicEvidence.topic, "sendEmoji")
    expectNoDifference(topicEvidence.topicMessageIDs.count, 1)
    expectNoDifference(topicEvidence.topicPayloadKeys, ["emoji"])

    let acceptEvidence = result.evidence[6].details
    expectNoDifference(acceptEvidence.activeShareIDs.count, 1)
    expectNoDifference(acceptEvidence.shareMemberUserIDs, ["user-1", "user-2"])

    let revokeEvidence = result.evidence[7].details
    expectNoDifference(revokeEvidence.activeShareIDs, [])
    expectNoDifference(revokeEvidence.revokedShareIDs.count, 1)
    expectNoDifference(revokeEvidence.shareMemberUserIDs, ["user-1", "user-2"])

    let relaunchEvidence = try #require(result.evidence.last?.details)
    expectNoDifference(relaunchEvidence.authUserID, "user-1")
    expectNoDifference(relaunchEvidence.roomType, "chat")
    expectNoDifference(relaunchEvidence.roomID, "validation")
    expectNoDifference(relaunchEvidence.topic, "sendEmoji")
    expectNoDifference(relaunchEvidence.roomMemberIDs, ["user-1"])
    expectNoDifference(relaunchEvidence.roomPresenceValueKeys, ["name", "status"])
    expectNoDifference(relaunchEvidence.topicMessageIDs.count, 1)
    expectNoDifference(relaunchEvidence.topicPayloadKeys, ["emoji"])
    expectNoDifference(relaunchEvidence.fileIDs.count, 1)
    expectNoDifference(relaunchEvidence.fileContentDigests, fileEvidence.fileContentDigests)
    expectNoDifference(relaunchEvidence.streamChunkIDs.count, 1)
    expectNoDifference(relaunchEvidence.activeShareIDs, [])
  }

  @Test
  func remindersValidationProducesEvidenceAndPersistsLocalSurfaces() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runRemindersValidation(
      appID: "validation-reminders-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-reminders-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.reminders")
    expectNoDifference(run.summary.rowCount, 10)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(
      run.summary.events,
      [
        "seed",
        "search-tags",
        "search-token-model",
        "rich-filters",
        "edit-rich-fields",
        "complete",
        "reader-rejection",
        "writer-update",
        "demoted-reader-rejection",
        "relaunch",
      ]
    )
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 10))
    expectNoDifference(
      result.evidence.map(\.caseID),
      Array(repeating: "validation.reminders", count: result.evidence.count)
    )

    let seed = result.evidence[0].details
    expectNoDifference(seed.listTitles, ["Family"])
    expectNoDifference(seed.reminderTitles, ["Pack lunch", "Read book"])
    expectNoDifference(seed.flaggedReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(seed.priorityRanksByReminderID, ["validation-reminders-pack-lunch": 3])
    expectNoDifference(seed.tagTitles, ["family"])

    let search = result.evidence[1].details
    expectNoDifference(search.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(search.reminderTagIDs, ["validation-reminders-pack-lunch#family"])

    let searchTokenModel = result.evidence[2].details
    expectNoDifference(searchTokenModel.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(searchTokenModel.searchTokens, ["tag:family"])
    expectNoDifference(searchTokenModel.tagSuggestionTitles, ["family"])
    expectNoDifference(searchTokenModel.searchCompletedCount, 0)

    let richFilters = result.evidence[3].details
    expectNoDifference(richFilters.scheduledReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(richFilters.todayReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(richFilters.priorityReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(richFilters.priorityRanksByReminderID, ["validation-reminders-pack-lunch": 3])
    expectNoDifference(
      richFilters.stats,
      RemindersStats(allCount: 2, completedCount: 0, flaggedCount: 1, scheduledCount: 1, todayCount: 1)
    )

    let formEdit = result.evidence[4].details
    expectNoDifference(formEdit.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(formEdit.reminderTitles, ["Pack lunch and snacks"])
    expectNoDifference(formEdit.reminderNotes, ["Updated through validation"])
    expectNoDifference(formEdit.reminderTagIDs, ["validation-reminders-pack-lunch#family"])

    let readerRejection = result.evidence[6].details
    expectNoDifference(
      readerRejection.rejectedOperations,
      ["reader-update:permissionRejected:remindersLists:validation-reminders-list"]
    )
    expectNoDifference(
      readerRejection.shareRoleSummaries,
      [
        "remindersLists:validation-reminders-list:user-1:owner",
        "remindersLists:validation-reminders-list:user-2:reader",
      ]
    )

    let writerUpdate = result.evidence[7].details
    expectNoDifference(writerUpdate.reminderTitles, ["Writer edit"])
    expectNoDifference(
      writerUpdate.shareRoleSummaries,
      [
        "remindersLists:validation-reminders-list:user-1:owner",
        "remindersLists:validation-reminders-list:user-2:writer",
      ]
    )

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.reminderTitles, ["Writer edit"])
    expectNoDifference(finalDetails.completedReminderIDs, ["validation-reminders-read-book"])
    expectNoDifference(finalDetails.flaggedReminderIDs, [])
    expectNoDifference(finalDetails.scheduledReminderIDs, [])
    expectNoDifference(finalDetails.priorityReminderIDs, [])
    expectNoDifference(finalDetails.priorityRanksByReminderID, [:])
    expectNoDifference(finalDetails.pendingMutationIDs.count, 6)
    expectNoDifference(
      finalDetails.stats,
      RemindersStats(allCount: 1, completedCount: 1, flaggedCount: 0, scheduledCount: 0, todayCount: 0)
    )
  }

  @Test
  func draftValidationHarnessSummarizesGeneratedDraftEvidence() async throws {
    let cacheURL = temporaryCacheURL()
    let idGenerator = ValidationIDGenerator([
      "draft-validation-created",
      "draft-validation-author",
      "draft-validation-post",
    ])

    let run = try await InstantSwiftDataTestHarness.runDraftValidation(
      appID: "validation-drafts-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_001_000_000) },
      makeID: { idGenerator.next() }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-drafts-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.typed.drafts")
    expectNoDifference(run.summary.rowCount, 4)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, ["create", "edit", "relation", "relaunch"])
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 4))

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.draftTodoIDs, ["draft-validation-created"])
    expectNoDifference(finalDetails.draftTodoTitles, ["Edit from generated draft"])
    expectNoDifference(finalDetails.draftPostIDs, ["draft-validation-post"])
    expectNoDifference(finalDetails.draftPostAuthorIDs, ["draft-validation-author"])
    expectNoDifference(finalDetails.draftPostAuthorAttributeValueType, "ref")
    expectNoDifference(finalDetails.draftPostAuthorReverseIdentity, "draftValidationAuthors/posts")
    expectNoDifference(
      finalDetails.pendingMutationIDs.sorted(),
      [
        "validation.typed-drafts.author",
        "validation.typed-drafts.create",
        "validation.typed-drafts.edit",
        "validation.typed-drafts.post",
      ]
    )

    let createMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.create"
      }
    )
    expectNoDifference(createMutation.transactionID, "validation.typed-drafts.create")
    expectNoDifference(createMutation.preconditionKinds, ["entity-missing"])
    expectNoDifference(createMutation.txStepKinds, Array(repeating: "add-triple", count: 5))
    expectNoDifference(createMutation.txStepOptionModes, Array(repeating: "create", count: 5))

    let editMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.edit"
      }
    )
    expectNoDifference(editMutation.preconditionKinds, [])
    expectNoDifference(editMutation.txStepOptionModes, Array(repeating: "none", count: 5))

    let postMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.post"
      }
    )
    expectNoDifference(postMutation.operationValueTypes, ["string", "string", "ref"])
    expectNoDifference(postMutation.refAttributeIDs, ["draftValidationPosts/author"])
  }

  @Test
  func validationRunnerTypedDraftsCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--typed-drafts"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --typed-drafts failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.map { $0["case"] as? String ?? "" }, [
      "validation.typed.drafts",
      "validation.typed.drafts",
      "validation.typed.drafts",
      "validation.typed.drafts",
    ])
    expectNoDifference(rows.map { $0["appID"] as? String ?? "" }, [
      "draft-validation",
      "draft-validation",
      "draft-validation",
      "draft-validation",
    ])
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, [
      "create",
      "edit",
      "relation",
      "relaunch",
    ])
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 4))
  }

  @Test
  func validationRunnerTypedDraftsFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--typed-drafts"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.typed.drafts"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.typed.drafts")
    expectNoDifference(row["appID"] as? String, "draft-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
  }

  @Test
  func platformAdapterValidationHarnessSummarizesWrapperEvidence() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runPlatformAdapterValidation(
      appID: "validation-adapters-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_002_000_000) }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-adapters-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.platform.adapters")
    expectNoDifference(run.summary.rowCount, platformAdapterValidationEvents.count)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, platformAdapterValidationEvents)
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(
      result.evidence.map(\.ok),
      Array(repeating: true, count: platformAdapterValidationEvents.count)
    )
    expectNoDifference(result.evidence.map(\.details.adapter), platformAdapterValidationAdapters)

    let fetchAll = result.evidence[0].details
    expectNoDifference(fetchAll.todoIDs.count, 1)
    expectNoDifference(fetchAll.todoTitles, ["Bind public adapter wrappers"])
    expectNoDifference(fetchAll.todoCount, 1)

    let fetchOne = result.evidence[1].details
    expectNoDifference(fetchOne.selectedTodoID, fetchAll.todoIDs.first)
    expectNoDifference(fetchOne.selectedTodoTitle, "Bind public adapter wrappers")

    let localID = try #require(result.evidence[3].details.localID)
    #expect(!localID.isEmpty)
    expectNoDifference(result.evidence[4].details.authUserID, "adapter-user")
    expectNoDifference(result.evidence[5].details.roomMemberIDs, ["adapter-user"])
    expectNoDifference(result.evidence[6].details.topicMessageIDs.count, 1)
    expectNoDifference(result.evidence[7].details.fileIDs.count, 1)
    expectNoDifference(result.evidence[8].details.streamChunkIDs.count, 1)
    expectNoDifference(result.evidence[9].details.shareIDs.count, 1)

    let projectedBindings = try #require(
      result.evidence.first { $0.event == "projected-bindings" }?.details
    )
    expectNoDifference(projectedBindings.adapter, "Projected bindings")
    expectNoDifference(projectedBindings.bindingAdapters, projectedBindingAdapters)
    expectNoDifference(projectedBindings.todoTitles, ["Bind public adapter wrappers"])
    expectNoDifference(projectedBindings.todoCount, 1)
    expectNoDifference(projectedBindings.authUserID, "adapter-user")
    expectNoDifference(projectedBindings.roomMemberIDs, ["adapter-user"])
    expectNoDifference(projectedBindings.topicMessageIDs.count, 1)
    expectNoDifference(projectedBindings.fileIDs.count, 1)
    expectNoDifference(projectedBindings.streamChunkIDs.count, 1)
    expectNoDifference(projectedBindings.shareIDs.count, 1)

    let filteredReload = try #require(
      result.evidence.first { $0.event == "fetch-all-filtered-reload" }?.details
    )
    expectNoDifference(
      filteredReload.fetchAllTitleBatches,
      [[], ["Engineering"], [], ["Engineering"]]
    )
    expectNoDifference(
      filteredReload.fetchTitleBatches,
      [[], ["Engineering"], [], ["Engineering"]]
    )
    expectNoDifference(filteredReload.queryCount, 6)
    expectNoDifference(filteredReload.observationCount, 0)

    let dynamic = try #require(
      result.evidence.first { $0.event == "fetch-all-dynamic-query" }?.details
    )
    expectNoDifference(dynamic.previousTodoTitles, ["Open dynamic"])
    expectNoDifference(dynamic.todoTitles, ["Done dynamic"])
    expectNoDifference(dynamic.queryCount, 2)
    expectNoDifference(dynamic.observationCount, 0)

    let fetchOneDynamic = try #require(
      result.evidence.first { $0.event == "fetch-one-dynamic-query" }?.details
    )
    expectNoDifference(fetchOneDynamic.previousTodoTitles, ["Open single"])
    expectNoDifference(fetchOneDynamic.todoTitles, ["Done single"])
    expectNoDifference(fetchOneDynamic.selectedTodoTitle, "Done single")
    expectNoDifference(fetchOneDynamic.queryCount, 2)
    expectNoDifference(fetchOneDynamic.observationCount, 0)

    let fetchRequestDynamic = try #require(
      result.evidence.first { $0.event == "fetch-request-dynamic-query" }?.details
    )
    expectNoDifference(fetchRequestDynamic.previousTodoTitles, ["Open request"])
    expectNoDifference(fetchRequestDynamic.todoTitles, ["Done request"])
    expectNoDifference(fetchRequestDynamic.todoCount, 2)
    expectNoDifference(fetchRequestDynamic.queryCount, 4)
    expectNoDifference(fetchRequestDynamic.observationCount, 0)

    let nilQuery = try #require(
      result.evidence.first { $0.event == "fetch-all-nil-query" }?.details
    )
    expectNoDifference(nilQuery.previousTodoTitles, ["Cached nil query"])
    expectNoDifference(nilQuery.todoTitles, [])
    expectNoDifference(nilQuery.queryCount, 0)
    expectNoDifference(nilQuery.observationCount, 0)
    expectNoDifference(nilQuery.nilQueryCleared, true)

    let fetchOneNilQuery = try #require(
      result.evidence.first { $0.event == "fetch-one-nil-query" }?.details
    )
    expectNoDifference(fetchOneNilQuery.previousTodoTitles, ["Cached optional nil query"])
    expectNoDifference(fetchOneNilQuery.todoTitles, [])
    expectNoDifference(fetchOneNilQuery.selectedTodoTitle, nil)
    expectNoDifference(fetchOneNilQuery.queryCount, 0)
    expectNoDifference(fetchOneNilQuery.observationCount, 0)
    expectNoDifference(fetchOneNilQuery.nilQueryCleared, true)

    let fetchRequestNil = try #require(
      result.evidence.first { $0.event == "fetch-request-nil-request" }?.details
    )
    expectNoDifference(fetchRequestNil.previousTodoTitles, ["Cached request nil"])
    expectNoDifference(fetchRequestNil.todoTitles, [])
    expectNoDifference(fetchRequestNil.todoCount, 0)
    expectNoDifference(fetchRequestNil.queryCount, 0)
    expectNoDifference(fetchRequestNil.observationCount, 0)
    expectNoDifference(fetchRequestNil.nilQueryCleared, nil)
    expectNoDifference(fetchRequestNil.nilRequestCleared, true)

    let cachedPrior = try #require(
      result.evidence.first { $0.event == "fetch-all-cached-prior-error" }?.details
    )
    expectNoDifference(cachedPrior.previousTodoTitles, ["Cached before error"])
    expectNoDifference(cachedPrior.todoTitles, ["Cached before error"])
    expectNoDifference(cachedPrior.queryCount, 2)
    expectNoDifference(cachedPrior.loadErrorOperation, "query dynamic FetchAll")

    let cancellation = try #require(
      result.evidence.first { $0.event == "fetch-all-cancellation" }?.details
    )
    expectNoDifference(cancellation.queryCount, 0)
    expectNoDifference(cancellation.observationCount, 1)
    expectNoDifference(cancellation.cancellationTerminated, true)
    expectNoDifference(cancellation.isLoading, false)

    let requestCancellation = try #require(
      result.evidence.first { $0.event == "fetch-request-cancellation" }?.details
    )
    expectNoDifference(requestCancellation.queryCount, 0)
    expectNoDifference(requestCancellation.observationCount, 1)
    expectNoDifference(requestCancellation.cancellationTerminated, true)
    expectNoDifference(requestCancellation.isLoading, false)

    let infiniteCancellation = try #require(
      result.evidence.first { $0.event == "infinite-query-dynamic-cancellation" }?.details
    )
    expectNoDifference(infiniteCancellation.todoTitles, ["Second infinite subscription"])
    expectNoDifference(infiniteCancellation.previousTodoTitles, ["First infinite subscription"])
    expectNoDifference(infiniteCancellation.observationCount, 2)
    expectNoDifference(infiniteCancellation.cancellationTerminated, true)
    expectNoDifference(infiniteCancellation.isLoading, false)

    let infiniteLoad = try #require(
      result.evidence.first { $0.event == "infinite-query-dynamic-load" }?.details
    )
    expectNoDifference(infiniteLoad.previousTodoTitles, ["Fresh infinite load"])
    expectNoDifference(infiniteLoad.fetchAllTitleBatches, [["Fresh infinite load"], []])
    expectNoDifference(infiniteLoad.todoTitles, [])
    expectNoDifference(infiniteLoad.queryCount, 3)
    expectNoDifference(infiniteLoad.nilQueryCleared, true)
    expectNoDifference(infiniteLoad.isLoading, false)
    expectNoDifference(infiniteLoad.loadErrorOperation, nil)
  }

  @Test
  func validationRunnerPlatformAdaptersCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--platform-adapters"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --platform-adapters failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.map { $0["case"] as? String ?? "" }, Array(
      repeating: "validation.platform.adapters",
      count: platformAdapterValidationEvents.count
    ))
    expectNoDifference(rows.map { $0["appID"] as? String ?? "" }, Array(
      repeating: "platform-adapter-validation",
      count: platformAdapterValidationEvents.count
    ))
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, platformAdapterValidationEvents)
    expectNoDifference(
      rows.map { $0["ok"] as? Bool ?? false },
      Array(repeating: true, count: platformAdapterValidationEvents.count)
    )

    let adapters = try rows.map { row in
      try #require((row["details"] as? [String: Any])?["adapter"] as? String)
    }
    expectNoDifference(adapters, platformAdapterValidationAdapters)

    let shares = try #require(
      rows.first { $0["event"] as? String == "shares" }?["details"] as? [String: Any]
    )
    expectNoDifference((shares["shareIDs"] as? [String])?.count, 1)

    let projectedBindings = try #require(
      rows.first { $0["event"] as? String == "projected-bindings" }?["details"]
        as? [String: Any]
    )
    expectNoDifference(projectedBindings["adapter"] as? String, "Projected bindings")
    expectNoDifference(projectedBindings["bindingAdapters"] as? [String], projectedBindingAdapters)
    expectNoDifference(projectedBindings["todoTitles"] as? [String], [
      "Bind public adapter wrappers"
    ])
    expectNoDifference(projectedBindings["authUserID"] as? String, "adapter-user")

    let cancellation = try #require(
      rows.first { $0["event"] as? String == "fetch-all-cancellation" }?["details"]
        as? [String: Any]
    )
    expectNoDifference((cancellation["cancellationTerminated"] as? NSNumber)?.boolValue, true)

    let requestCancellation = try #require(
      rows.first { $0["event"] as? String == "fetch-request-cancellation" }?["details"]
        as? [String: Any]
    )
    expectNoDifference(
      (requestCancellation["cancellationTerminated"] as? NSNumber)?.boolValue,
      true
    )

    let infiniteCancellation = try #require(
      rows.first { $0["event"] as? String == "infinite-query-dynamic-cancellation" }?["details"]
        as? [String: Any]
    )
    expectNoDifference(
      infiniteCancellation["todoTitles"] as? [String],
      ["Second infinite subscription"]
    )
    expectNoDifference(
      (infiniteCancellation["cancellationTerminated"] as? NSNumber)?.boolValue,
      true
    )

    let infiniteLoad = try #require(
      rows.first { $0["event"] as? String == "infinite-query-dynamic-load" }?["details"]
        as? [String: Any]
    )
    expectNoDifference(
      infiniteLoad["previousTodoTitles"] as? [String],
      ["Fresh infinite load"]
    )
    expectNoDifference((infiniteLoad["nilQueryCleared"] as? NSNumber)?.boolValue, true)
  }

  @Test
  func validationRunnerPlatformAdaptersFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--platform-adapters"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.platform.adapters"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.platform.adapters")
    expectNoDifference(row["appID"] as? String, "platform-adapter-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
  }

  @Test
  func validationRunnerRemindersCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--reminders"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --reminders failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 10)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set([
      "validation.reminders"
    ]))
    expectNoDifference(Set(rows.map { $0["appID"] as? String ?? "" }), Set(["local-validation"]))
    expectNoDifference(
      rows.map { $0["event"] as? String ?? "" },
      [
        "seed",
        "search-tags",
        "search-token-model",
        "rich-filters",
        "edit-rich-fields",
        "complete",
        "reader-rejection",
        "writer-update",
        "demoted-reader-rejection",
        "relaunch",
      ]
    )
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 10))

    let search = try #require(rows.first { $0["event"] as? String == "search-tags" })
    let searchDetails = try #require(search["details"] as? [String: Any])
    expectNoDifference(searchDetails["reminderIDs"] as? [String], ["validation-reminders-pack-lunch"])
    expectNoDifference(searchDetails["tagTitles"] as? [String], ["family"])

    let tokenSearch = try #require(rows.first { $0["event"] as? String == "search-token-model" })
    let tokenSearchDetails = try #require(tokenSearch["details"] as? [String: Any])
    expectNoDifference(tokenSearchDetails["reminderIDs"] as? [String], ["validation-reminders-pack-lunch"])
    expectNoDifference(tokenSearchDetails["searchTokens"] as? [String], ["tag:family"])
    expectNoDifference(tokenSearchDetails["tagSuggestionTitles"] as? [String], ["family"])
    expectNoDifference(tokenSearchDetails["searchCompletedCount"] as? Int, 0)

    let reader = try #require(rows.first { $0["event"] as? String == "reader-rejection" })
    let readerDetails = try #require(reader["details"] as? [String: Any])
    expectNoDifference(
      readerDetails["rejectedOperations"] as? [String],
      ["reader-update:permissionRejected:remindersLists:validation-reminders-list"]
    )
  }

  @Test
  func validationRunnerLocalRemindersAliasEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--local-reminders"])

    #expect(result.status == 0)
    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 10)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set(["validation.reminders"]))
  }

  @Test
  func validationRunnerRemindersFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--reminders"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.reminders"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.reminders")
    expectNoDifference(row["appID"] as? String, "local-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
  }

  @Test
  func syncUpsRecordingValidationHarnessSummarizesEvidence() async throws {
    let cacheURL = temporaryCacheURL()

    let run = try await InstantSwiftDataTestHarness.runSyncUpsRecordingValidation(
      appID: "validation-syncups-test",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) }
    )
    let result = run.result

    expectNoDifference(result.appID, "validation-syncups-test")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(run.summary.caseID, "validation.syncups.recording")
    expectNoDifference(run.summary.rowCount, 7)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, syncUpsRecordingValidationEvents)
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 7))

    let meetingSave = result.evidence[4].details
    expectNoDifference(meetingSave.meetingTranscripts, ["Reviewed launch risks. Final notes."])
    expectNoDifference(meetingSave.recording?.meetingID, result.meetingID)
    expectNoDifference(meetingSave.recording?.soundEffectPlayCount, 1)

    let openSettings = result.evidence[5].details
    expectNoDifference(openSettings.recording?.authorizationStatus, .denied)
    expectNoDifference(openSettings.recording?.alert, .speechRecognitionDenied)
    expectNoDifference(openSettings.alertOutcome, .settingsOpened)
    expectNoDifference(openSettings.openSettingsCount, 1)

    let relaunch = result.evidence[6].details
    expectNoDifference(relaunch.meetingTranscripts, ["Reviewed launch risks. Final notes."])
    expectNoDifference(relaunch.recording?.meetingID, result.meetingID)
  }

  @Test
  func validationRunnerSyncUpsRecordingCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--syncups-recording"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --syncups-recording failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.map { $0["case"] as? String ?? "" }, Array(
      repeating: "validation.syncups.recording",
      count: 7
    ))
    expectNoDifference(rows.map { $0["appID"] as? String ?? "" }, Array(
      repeating: "syncups-recording-validation",
      count: 7
    ))
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, syncUpsRecordingValidationEvents)
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 7))

    let meetingSave = try #require(rows[4]["details"] as? [String: Any])
    expectNoDifference(meetingSave["meetingTranscripts"] as? [String], [
      "Reviewed launch risks. Final notes."
    ])
    let settings = try #require(rows[5]["details"] as? [String: Any])
    expectNoDifference((settings["openSettingsCount"] as? NSNumber)?.intValue, 1)
  }

  @Test
  func validationRunnerSyncUpsRecordingFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--syncups-recording"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.syncups.recording"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.syncups.recording")
    expectNoDifference(row["appID"] as? String, "syncups-recording-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
  }

  @Test
  func parityCoverageValidationHarnessSummarizesIncompleteCoverage() throws {
    let run = try InstantSwiftDataTestHarness.runParityCoverageValidation(
      appID: "validation-parity-test",
      timestamp: { InstantTimestamp(milliseconds: 1_700_003_000_000) }
    )

    expectNoDifference(run.result.event, "parity-report")
    expectNoDifference(run.result.coverageComplete, false)
    expectNoDifference(run.result.recordCount, 226)
    expectNoDifference(run.result.exactCount, 28)
    expectNoDifference(run.result.adaptedCount, 195)
    expectNoDifference(run.result.blockedCount, 2)
    expectNoDifference(run.result.notApplicableCount, 1)
    expectNoDifference(run.summary.caseID, "validation.parity.report")
    expectNoDifference(run.summary.appID, "validation-parity-test")
    expectNoDifference(run.summary.rowCount, run.result.recordCount)
    expectNoDifference(run.summary.ok, false)
    expectNoDifference(
      run.summary.events,
      Array(repeating: "parity-record", count: run.result.recordCount)
    )
    expectNoDifference(run.summary.failedEvents, Array(repeating: "parity-record", count: 2))
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/store.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/serializeSchema.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/object.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/PersistedObject.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/utils/weakHashLegacy.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/simple.e2e.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/cookieSync.e2e.test.ts + upstream/instant/client/packages/core/src/Reactor.js + upstream/instant/client/packages/core/src/routeHandlerProtocol.ts + upstream/instant/client/packages/core/src/createRouteHandler.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts + upstream/instant/client/packages/core/src/infiniteQuery.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts"
      )
    )
    #expect(
      run.result.sourceFiles.contains(
        "upstream/instant/client/packages/core/__tests__/src/instaqlInference.test.ts"
      )
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.reminders.search-tags" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.reminders.form-model" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.fetch-one.dynamic-query" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.fetch-one.nil-query" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.cloudkit-demo.local-counter-share" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "sqlite.cloudkit-demo.remote-share" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.store.new-attrs" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.store.update-attr" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.store.delete-attr" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.store.deep-merge" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.simple-e2e.can-make-query" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.cookie-sync.startup-old" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.cookie-sync.startup-recent" && $0.status == .adapted
      }
    )
    for id in [
      "instant.infinite-query.initial-snapshot",
      "instant.infinite-query.no-order-field",
      "instant.infinite-query.adding-new-numbers",
      "instant.infinite-query.adding-negative-numbers",
      "instant.infinite-query.add-zero-twice",
      "instant.infinite-query.descending",
      "instant.infinite-query.duplicate-boundary-desc",
      "instant.infinite-query.rapid-load-next-page",
      "instant.infinite-query.deleting-item",
      "instant.infinite-query.update-out-of-window",
      "instant.infinite-query.page-size-one-asc",
      "instant.infinite-query.page-size-one-desc",
      "instant.infinite-query.typed-client-adapter",
    ] {
      #expect(
        run.result.records.contains { $0.id == id && $0.status == .adapted },
        "Expected adapted infinite-query parity record \(id)"
      )
    }
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.query-subs-round-trips" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.optimistic-refresh-preserves-local" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.pending-cleanup-keeps-waiting" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.get-local-id-stability" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.rewrite-mutations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.reactor.rewrite-mutations-multiple" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.instaql-inference.many-to-many" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.instaql-inference.one-to-one" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.instaql-inference.one-to-one-without-inference"
          && $0.status == .adapted
      }
    )
    for expected in [
      ("instant.utils.date-coercion.valid-strings", InstantParityCoverageStatus.exact),
      ("instant.utils.date-coercion.invalid-strings", InstantParityCoverageStatus.adapted),
      ("instant.utils.date-coercion.date-instances", InstantParityCoverageStatus.adapted),
      ("instant.utils.date-coercion.number-timestamps", InstantParityCoverageStatus.exact),
      ("instant.utils.date-coercion.unsupported-types", InstantParityCoverageStatus.adapted),
    ] {
      #expect(
        run.result.records.contains { $0.id == expected.0 && $0.status == expected.1 },
        "Expected \(expected.1.rawValue) date coercion parity record \(expected.0)"
      )
    }
    for id in [
      "instant.utils.object-path-mutation.assoc-shallow",
      "instant.utils.object-path-mutation.assoc-nested",
      "instant.utils.object-path-mutation.insert-objects",
      "instant.utils.object-path-mutation.insert-arrays",
      "instant.utils.object-path-mutation.dissoc-shallow",
      "instant.utils.object-path-mutation.dissoc-nested",
      "instant.utils.object-path-mutation.dissoc-arrays",
    ] {
      #expect(
        run.result.records.contains { $0.id == id && $0.status == .adapted },
        "Expected adapted object path parity record \(id)"
      )
    }
    for id in [
      "instant.weak-hash.integer-collision-stress",
      "instant.weak-hash.object-order-undefined",
      "instant.weak-hash.undefined-explicitness",
      "instant.weak-hash.to-json-output",
      "instant.weak-hash.bigint-values",
      "instant.weak-hash.known-query",
    ] {
      #expect(
        run.result.records.contains { $0.id == id && $0.status == .adapted },
        "Expected adapted weak hash parity record \(id)"
      )
    }
    for expected in [
      ("instant.persisted-object.saves-values", InstantParityCoverageStatus.adapted),
      ("instant.persisted-object.merges-existing-values", InstantParityCoverageStatus.adapted),
      ("instant.persisted-object.load-notification", InstantParityCoverageStatus.notApplicable),
      ("instant.persisted-object.gc-max-items", InstantParityCoverageStatus.adapted),
      ("instant.persisted-object.gc-max-size", InstantParityCoverageStatus.adapted),
      ("instant.persisted-object.gc-max-age", InstantParityCoverageStatus.adapted),
      ("instant.persisted-object.indexeddb-connection-recovery", InstantParityCoverageStatus.adapted),
    ] {
      #expect(
        run.result.records.contains { $0.id == expected.0 && $0.status == expected.1 },
        "Expected \(expected.1.rawValue) PersistedObject parity record \(expected.0)"
      )
    }
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.chunk-arrays" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.chunk-structure" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.operation-structure" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.create-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.update-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.merge-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.delete-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.link-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.unlink-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.entity-existence" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.attribute-types" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.chained-operations" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.multiple-entity-types" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.transaction-validation.link-relationships" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.website.app-builder.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.website.chat.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.website.microblog.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.website.stroopwafel.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.auth.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.typing-indicator.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.avatar-stack.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.cursors.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.custom-cursors.local-cli" && $0.status == .adapted
      }
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.recipe.merge-tile-game.local-cli" && $0.status == .adapted
      }
    )
    let platformAdapterBinding = try #require(
      run.result.records.first { $0.id == "instant.react-common.platform-adapter-bindings" }
    )
    expectNoDifference(platformAdapterBinding.sourceKind.rawValue, "instant-typescript")
    expectNoDifference(platformAdapterBinding.sourceFile, "upstream/instant/client/packages/react-common/src")
    expectNoDifference(
      platformAdapterBinding.sourceTestName,
      "useQuery, useAuth, useId, room, storage, streams, and shares hooks"
    )
    expectNoDifference(
      platformAdapterBinding.swiftFile,
      "Tests/InstantSwiftDataTests/BootstrapTests.swift"
    )
    expectNoDifference(
      platformAdapterBinding.swiftTestName,
      "platformAdapterValidationProvesWrappersBindLocalRuntime"
    )
    expectNoDifference(platformAdapterBinding.surface, "adapter-bindings")
    expectNoDifference(platformAdapterBinding.status, .adapted)
    expectNoDifference(
      platformAdapterBinding.notes,
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, InfiniteQuery, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares, plus dynamic InfiniteQuery and live wrapper replacement/cancellation evidence."
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.live-transport.swift-to-typescript" && $0.status == .blocked
      }
    )
  }

  @Test
  func parityCoverageValidationHarnessAcceptsCredentialedLiveBoundaryArtifacts() throws {
    let homeURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataValidationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: homeURL) }

    try """
      {"case":"validation.typescript.boundary","side":"typescript","event":"swift-to-typescript-boundary","appID":"remote-app","timestampMs":1,"ok":true,"details":{"proofLevel":"real-swift-websocket-to-typescript-admin-sse","remoteBoundary":"swift-websocket-to-typescript-admin-sse"}}

      """.write(
        to: homeURL.appendingPathComponent("typescript-swift-boundary.jsonl"),
        atomically: true,
        encoding: .utf8
      )
    try """
      {"case":"validation.typescript.boundary","side":"typescript","event":"swift-observe-refresh","appID":"remote-app","timestampMs":2,"ok":true,"details":{"entityID":"typescript-live-boundary-test","swiftAppliedRefreshCount":1,"swiftCachedEntityIDs":["typescript-live-boundary-test"],"swiftCachedTodoTexts":["TypeScript live boundary test"]}}
      {"case":"validation.typescript.boundary","side":"typescript","event":"typescript-to-swift-boundary","appID":"remote-app","timestampMs":3,"ok":true,"details":{"proofLevel":"real-typescript-admin-http-to-swift-websocket","remoteBoundary":"typescript-admin-http-to-swift-websocket","entityID":"typescript-live-boundary-test"}}

      """.write(
        to: homeURL.appendingPathComponent("swift-typescript-boundary.jsonl"),
        atomically: true,
        encoding: .utf8
      )

    let run = try InstantSwiftDataTestHarness.runParityCoverageValidation(
      appID: "validation-parity-test",
      artifactsDirectory: homeURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_003_000_000) }
    )

    expectNoDifference(run.result.coverageComplete, true)
    expectNoDifference(run.result.adaptedCount, 197)
    expectNoDifference(run.result.blockedCount, 0)
    expectNoDifference(run.summary.ok, true)
    let swiftToTypeScript = try #require(
      run.result.records.first { $0.id == "instant.live-transport.swift-to-typescript" }
    )
    expectNoDifference(swiftToTypeScript.status, .adapted)
    #expect(
      swiftToTypeScript.notes.contains(
        "Credentialed validation artifact proves a Swift live WebSocket write was observed by TypeScript admin SSE."
      )
    )
    let typeScriptToSwift = try #require(
      run.result.records.first { $0.id == "instant.live-transport.typescript-to-swift" }
    )
    expectNoDifference(typeScriptToSwift.status, .adapted)
    #expect(
      typeScriptToSwift.notes.contains(
        "Credentialed validation artifact proves a TypeScript admin HTTP write was observed by Swift's live WebSocket observer and applied into the Swift runtime cache."
      )
    )
  }

  @Test
  func validationRunnerParityReportCommandEmitsJSONL() throws {
    let result = try runValidationRunner(arguments: ["--parity-report"])

    #expect(
      result.status == 0,
      """
      instant-swift-data-validation-runner --parity-report failed.
      stdout:
      \(result.stdout)
      stderr:
      \(result.stderr)
      """
    )

    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 226)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set([
      "validation.parity.report"
    ]))
    expectNoDifference(Set(rows.map { $0["appID"] as? String ?? "" }), Set(["local-validation"]))
    expectNoDifference(Set(rows.map { $0["event"] as? String ?? "" }), Set(["parity-record"]))
    expectNoDifference(rows.filter { ($0["ok"] as? Bool) == false }.count, 2)
    let platformAdapterBinding = try #require(rows.first { row in
      row["entityID"] as? String == "instant.react-common.platform-adapter-bindings"
    })
    expectNoDifference(platformAdapterBinding["side"] as? String, "instant-typescript")
    expectNoDifference(platformAdapterBinding["ok"] as? Bool, true)
    let platformAdapterBindingDetails = try #require(
      platformAdapterBinding["details"] as? [String: Any]
    )
    expectNoDifference(platformAdapterBindingDetails["sourceKind"] as? String, "instant-typescript")
    expectNoDifference(
      platformAdapterBindingDetails["sourceFile"] as? String,
      "upstream/instant/client/packages/react-common/src"
    )
    expectNoDifference(
      platformAdapterBindingDetails["sourceTestName"] as? String,
      "useQuery, useAuth, useId, room, storage, streams, and shares hooks"
    )
    expectNoDifference(
      platformAdapterBindingDetails["swiftFile"] as? String,
      "Tests/InstantSwiftDataTests/BootstrapTests.swift"
    )
    expectNoDifference(
      platformAdapterBindingDetails["swiftTestName"] as? String,
      "platformAdapterValidationProvesWrappersBindLocalRuntime"
    )
    expectNoDifference(platformAdapterBindingDetails["surface"] as? String, "adapter-bindings")
    expectNoDifference(platformAdapterBindingDetails["status"] as? String, "adapted")
    expectNoDifference(
      platformAdapterBindingDetails["notes"] as? String,
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, InfiniteQuery, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares, plus dynamic InfiniteQuery and live wrapper replacement/cancellation evidence."
    )

    let first = try #require(rows.first)
    expectNoDifference(first["entityID"] as? String, "instant.store.simple-add")
    expectNoDifference(first["side"] as? String, "instant-typescript")
    expectNoDifference(first["ok"] as? Bool, true)
    let firstDetails = try #require(first["details"] as? [String: Any])
    expectNoDifference(firstDetails["status"] as? String, "exact")

    let blocked = try #require(
      rows.first { row in
        row["entityID"] as? String == "instant.live-transport.swift-to-typescript"
      }
    )
    expectNoDifference(blocked["ok"] as? Bool, false)
    let blockedDetails = try #require(blocked["details"] as? [String: Any])
    expectNoDifference(blockedDetails["status"] as? String, "blocked")
  }

  @Test
  func validationRunnerCoverageCommandEmitsSummaryJSONL() throws {
    let result = try runValidationRunner(arguments: ["--coverage"])

    #expect(result.status == 0)
    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 1)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set(["validation.coverage"]))
    expectNoDifference(Set(rows.map { $0["appID"] as? String ?? "" }), Set(["local-validation"]))
    let row = try #require(rows.first)
    expectNoDifference(row["side"] as? String, "swift")
    expectNoDifference(row["event"] as? String, "coverage-summary")
    expectNoDifference(row["ok"] as? Bool, false)
    let details = try #require(row["details"] as? [String: Any])
    expectNoDifference(details["event"] as? String, "coverage")
    expectNoDifference(details["ok"] as? Bool, false)
    expectNoDifference(details["coverageComplete"] as? Bool, false)
    expectNoDifference((details["recordCount"] as? NSNumber)?.intValue, 226)
    expectNoDifference((details["exactCount"] as? NSNumber)?.intValue, 28)
    expectNoDifference((details["adaptedCount"] as? NSNumber)?.intValue, 195)
    expectNoDifference((details["blockedCount"] as? NSNumber)?.intValue, 2)
    expectNoDifference((details["notApplicableCount"] as? NSNumber)?.intValue, 1)
    expectNoDifference((details["swiftFileCount"] as? NSNumber)?.intValue, 24)
    expectNoDifference(
      details["blockedIDs"] as? [String],
      [
        "instant.live-transport.swift-to-typescript",
        "instant.live-transport.typescript-to-swift",
      ]
    )
  }

  @Test
  func validationRunnerParityReportFailureEmitsMappedJSONL() throws {
    let result = try runValidationRunner(
      arguments: ["--parity-report"],
      environment: [
        "INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE": "validation.parity.report"
      ]
    )

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.parity.report")
    expectNoDifference(row["appID"] as? String, "local-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
  }

  @Test
  func validationRunnerMalformedArgumentsEmitMappedJSONL() throws {
    let result = try runValidationRunner(arguments: ["--local-todos", "--coverage"])

    #expect(result.status == 1)
    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 1)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.arguments")
    expectNoDifference(row["appID"] as? String, "local-validation")
    expectNoDifference(row["event"] as? String, "failed")
    expectNoDifference(row["ok"] as? Bool, false)
    let details = try #require(row["details"] as? [String: Any])
    expectNoDifference(
      details["message"] as? String,
      CLIValidationRunnerUsage.validationRunner
    )
  }

  @Test
  func typeScriptLiveSessionContractVerifierConsumesSwiftEvidence() throws {
    let packageURL = packageRootURL()
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataLiveSessionContract-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

    let appID = "remote-validation-test"
    let artifactURL = tempURL.appendingPathComponent("swift-live-session.jsonl")
    try """
    {"case":"validation.live.session","side":"swift","event":"session-url","appID":"remote-validation-test","timestampMs":1,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"send-init","appID":"remote-validation-test","timestampMs":2,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"receive-init-ok","appID":"remote-validation-test","timestampMs":3,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"send-add-query","appID":"remote-validation-test","timestampMs":4,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"receive-query","appID":"remote-validation-test","timestampMs":5,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok","add-query-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id=remote-validation-test"}}

    """.write(to: artifactURL, atomically: true, encoding: .utf8)

    let result = try runTypeScriptValidationRunner(
      arguments: ["--swift-live-session-contract", artifactURL.path, "--app-id", appID],
      currentDirectory: packageURL
    )

    #expect(result.status == 0, "TypeScript live-session verifier failed: \(result.stderr)")
    let rows = try parseJSONLines(result.stdout)
    expectNoDifference(rows.count, 1)
    let row = try #require(rows.first)
    expectNoDifference(row["case"] as? String, "validation.typescript.live-session-contract")
    expectNoDifference(row["event"] as? String, "swift-live-session-contract")
    expectNoDifference(row["appID"] as? String, appID)
    expectNoDifference(row["ok"] as? Bool, true)

    let details = try #require(row["details"] as? [String: Any])
    expectNoDifference(details["proofLevel"] as? String, "contract-only")
    expectNoDifference(details["remoteBoundary"] as? String, "pending-cross-client-sync")
    expectNoDifference(
      details["actualEvents"] as? [String],
      ["session-url", "send-init", "receive-init-ok", "send-add-query", "receive-query"]
    )
    expectNoDifference(details["sentOps"] as? [String], ["init", "add-query"])
    expectNoDifference(details["receivedOps"] as? [String], ["init-ok", "add-query-ok"])
    expectNoDifference(details["swiftProofLevel"] as? String, "local-protocol")

    let refreshArtifactURL = tempURL.appendingPathComponent("swift-live-session-refresh.jsonl")
    try """
    {"case":"validation.live.session","side":"swift","event":"session-url","appID":"remote-validation-test","timestampMs":1,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"send-init","appID":"remote-validation-test","timestampMs":2,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"receive-init-ok","appID":"remote-validation-test","timestampMs":3,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"send-add-query","appID":"remote-validation-test","timestampMs":4,"ok":true,"details":{}}
    {"case":"validation.live.session","side":"swift","event":"receive-refresh","appID":"remote-validation-test","timestampMs":5,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok","refresh-ok"],"proofLevel":"live-websocket-session","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id=remote-validation-test"}}

    """.write(to: refreshArtifactURL, atomically: true, encoding: .utf8)

    let refresh = try runTypeScriptValidationRunner(
      arguments: ["--swift-live-session-contract", refreshArtifactURL.path, "--app-id", appID],
      currentDirectory: packageURL
    )
    #expect(refresh.status == 0, "TypeScript refresh verifier failed: \(refresh.stderr)")
    let refreshRows = try parseJSONLines(refresh.stdout)
    let refreshDetails = try #require(refreshRows.first?["details"] as? [String: Any])
    expectNoDifference(
      refreshDetails["actualEvents"] as? [String],
      ["session-url", "send-init", "receive-init-ok", "send-add-query", "receive-refresh"]
    )
    expectNoDifference(refreshDetails["receivedOps"] as? [String], ["init-ok", "refresh-ok"])
    expectNoDifference(refreshDetails["swiftProofLevel"] as? String, "live-websocket-session")

    let mismatch = try runTypeScriptValidationRunner(
      arguments: ["--swift-live-session-contract", artifactURL.path, "--app-id", "wrong-app"],
      currentDirectory: packageURL
    )
    #expect(mismatch.status == 1)
    let mismatchRows = try parseJSONLines(mismatch.stdout)
    let mismatchDetails = try #require(mismatchRows.first?["details"] as? [String: Any])
    let issues = try #require(mismatchDetails["issues"] as? [[String: Any]])
    #expect(issues.contains { ($0["path"] as? String) == "$[0].appID" })
  }

  @Test
  func typeScriptLocalIntegrationsContractVerifierRequiresRelaunchRoomKeys() throws {
    let packageURL = packageRootURL()
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataLocalIntegrationsContract-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

    let appID = "local-validation-test"
    let artifactURL = tempURL.appendingPathComponent("swift-local-integrations.jsonl")

    func jsonArray(_ strings: [String]) throws -> String {
      String(decoding: try JSONEncoder().encode(strings), as: UTF8.self)
    }

    func artifact(
      relaunchPresenceKeys: [String] = ["name", "status"],
      relaunchPayloadKeys: [String] = ["emoji"]
    ) throws -> String {
      let relaunchPresenceKeys = try jsonArray(relaunchPresenceKeys)
      let relaunchPayloadKeys = try jsonArray(relaunchPayloadKeys)
      return """
      {"case":"validation.local.integrations","side":"swift","event":"auth","appID":"\(appID)","timestampMs":1,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"room-presence","appID":"\(appID)","timestampMs":2,"ok":true,"details":{"authUserID":"user-1","roomType":"chat","roomID":"validation","topic":"sendEmoji","roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"]}}
      {"case":"validation.local.integrations","side":"swift","event":"room-topic","appID":"\(appID)","timestampMs":3,"ok":true,"details":{"roomType":"chat","roomID":"validation","topic":"sendEmoji","topicMessageIDs":["topic-1"],"topicPayloadKeys":["emoji"]}}
      {"case":"validation.local.integrations","side":"swift","event":"file","appID":"\(appID)","timestampMs":4,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"stream","appID":"\(appID)","timestampMs":5,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"share-create","appID":"\(appID)","timestampMs":6,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"share-accept","appID":"\(appID)","timestampMs":7,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"share-revoke","appID":"\(appID)","timestampMs":8,"ok":true,"details":{}}
      {"case":"validation.local.integrations","side":"swift","event":"relaunch","appID":"\(appID)","timestampMs":9,"ok":true,"details":{"roomType":"chat","roomID":"validation","topic":"sendEmoji","roomMemberIDs":["user-1"],"roomPresenceValueKeys":\(relaunchPresenceKeys),"topicMessageIDs":["topic-1"],"topicPayloadKeys":\(relaunchPayloadKeys)}}

      """
    }

    try artifact().write(to: artifactURL, atomically: true, encoding: .utf8)
    let valid = try runTypeScriptValidationRunner(
      arguments: ["--swift-local-integrations-contract", artifactURL.path, "--app-id", appID],
      currentDirectory: packageURL
    )
    #expect(valid.status == 0, "TypeScript local-integrations verifier failed: \(valid.stderr)")
    let validRows = try parseJSONLines(valid.stdout)
    let validDetails = try #require(validRows.first?["details"] as? [String: Any])
    expectNoDifference(validRows.first?["ok"] as? Bool, true)
    expectNoDifference(validDetails["roomPresenceValueKeys"] as? [String], ["name", "status"])
    expectNoDifference(validDetails["topicPayloadKeys"] as? [String], ["emoji"])

    try artifact(
      relaunchPresenceKeys: ["wrong"],
      relaunchPayloadKeys: ["wrong"]
    )
    .write(to: artifactURL, atomically: true, encoding: .utf8)
    let invalid = try runTypeScriptValidationRunner(
      arguments: ["--swift-local-integrations-contract", artifactURL.path, "--app-id", appID],
      currentDirectory: packageURL
    )
    #expect(invalid.status == 1)
    let invalidRows = try parseJSONLines(invalid.stdout)
    let invalidDetails = try #require(invalidRows.first?["details"] as? [String: Any])
    expectNoDifference(invalidRows.first?["ok"] as? Bool, false)
    let issues = try #require(invalidDetails["issues"] as? [[String: Any]])
    #expect(issues.contains { ($0["path"] as? String) == "$.relaunch.details.roomPresenceValueKeys" })
    #expect(issues.contains { ($0["path"] as? String) == "$.relaunch.details.topicPayloadKeys" })
  }

  @Test
  func validationRunE2EScriptOrchestratesLocalIntegrationEvidence() throws {
    let packageURL = packageRootURL()
    let scriptURL = packageURL.appendingPathComponent("validation/run-e2e.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"))
    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-todos"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-integrations"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --server-transaction-loopback"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --cloudkit-demo"))
    #expect(script.contains("swift run instant-swift-data validation live-session --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation live-observe --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation reminders --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation typed-drafts --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation platform-adapters --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation syncups-recording --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation parity-report --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation coverage --jsonl"))
    #expect(script.contains("swift run instant-swift-data-benchmarks"))
    #expect(script.contains("swift run instant-swift-data admin transact validationTransport"))
    #expect(script.contains("swift run instant-swift-data outbox transport --json"))
    #expect(script.contains("swift-local-integrations.jsonl"))
    #expect(script.contains("swift-server-transaction-loopback.jsonl"))
    #expect(script.contains("swift-cloudkit-demo.jsonl"))
    #expect(script.contains("swift-live-session.jsonl"))
    #expect(script.contains("swift-live-observe.jsonl"))
    #expect(script.contains("swift-reminders.jsonl"))
    #expect(script.contains("swift-typed-drafts.jsonl"))
    #expect(script.contains("swift-platform-adapters.jsonl"))
    #expect(script.contains("swift-syncups-recording.jsonl"))
    #expect(script.contains("swift-parity-report.jsonl"))
    #expect(script.contains("swift-coverage.jsonl"))
    #expect(script.contains("swift-coverage-final.jsonl"))
    #expect(script.contains("INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR"))
    #expect(script.contains("swift-transport-contract.json"))
    #expect(script.contains("typescript-server-transaction-contract.json"))
    #expect(script.contains("swift-typescript-server-transaction-contract.jsonl"))
    #expect(script.contains("swift-benchmark.jsonl"))
    #expect(script.contains("INSTANT_SWIFT_DATA_NODE"))
    #expect(script.contains("validation/ts-runner/src/main.ts --fixtures"))
    #expect(script.contains("--swift-transport-contract"))
    #expect(script.contains("--swift-live-session-contract"))
    #expect(script.contains("--typescript-server-transaction-contract"))
    #expect(script.contains("INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT"))
    #expect(script.contains("--boundary-preflight"))
    #expect(script.contains("--boundary-admin-smoke"))
    #expect(script.contains("--boundary-swift-live-observe"))
    #expect(script.contains("--boundary-typescript-live-observe"))
    #expect(script.contains("INSTANT_SWIFT_DATA_REMOTE_APP_ID"))
    #expect(script.contains("INSTANT_SWIFT_DATA_REQUIRE_REMOTE_PREFLIGHT"))
    #expect(script.contains("INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY"))
    #expect(script.contains("INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY"))
    #expect(script.contains("typescript-swift-boundary.jsonl"))
    #expect(script.contains("swift-typescript-boundary.jsonl"))
    #expect(script.contains("rm -f"))
    #expect(script.contains(": > \"${RESULTS_DIR}/orchestrator.jsonl\""))
    #expect(script.contains("\"failed\":\"missing-required-file\""))
    #expect(script.contains("\"failed\":\"missing-swift\""))
    #expect(script.contains("\"failed\":\"missing-node\""))
    #expect(!script.contains("${3:-{}}"))

    let runnerSource = try String(
      contentsOf: packageURL.appendingPathComponent(
        "Sources/InstantSwiftDataValidationRunner/main.swift"
      ),
      encoding: .utf8
    )
    #expect(runnerSource.contains("runDraftValidation()"))
    #expect(runnerSource.contains("runCloudKitDemoValidation"))
    #expect(runnerSource.contains("runLiveSessionValidation"))
    #expect(runnerSource.contains("InstantSwiftDataPlatformAdapterValidation.run"))
    #expect(runnerSource.contains("InstantSwiftDataRemindersValidation.run"))
    #expect(runnerSource.contains("runSyncUpsRecordingValidation()"))
    #expect(runnerSource.contains("runParityCoverageValidation("))
    #expect(runnerSource.contains("validationCoverageArtifactsDirectory()"))
    #expect(runnerSource.contains("CLIValidationRunnerArguments.parse"))
    #expect(!runnerSource.contains("arguments == [\"--coverage\"]"))

    let parserSource = try String(
      contentsOf: packageURL.appendingPathComponent(
        "Sources/InstantSwiftDataCLI/CLIArgumentParser.swift"
      ),
      encoding: .utf8
    )
    #expect(parserSource.contains("CLIValidationRunnerParser"))
    #expect(parserSource.contains("--typed-drafts"))
    #expect(parserSource.contains("--cloudkit-demo"))
    #expect(parserSource.contains("--platform-adapters"))
    #expect(parserSource.contains("--reminders\", \"--local-reminders"))
    #expect(parserSource.contains("--syncups-recording"))
    #expect(parserSource.contains("--parity-report"))
    #expect(parserSource.contains("--coverage"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-n", scriptURL.path]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let error = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
    #expect(process.terminationStatus == 0, "run-e2e.sh syntax check failed: \(error)")

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataRunE2E-\(UUID().uuidString)", isDirectory: true)
    let binURL = tempURL.appendingPathComponent("bin", isDirectory: true)
    let resultsURL = tempURL.appendingPathComponent("results", isDirectory: true)
    let benchmarkIterations = "7"
    try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resultsURL, withIntermediateDirectories: true)

    try writeExecutable(
      """
      #!/bin/sh
      case "$1:$2" in
        package:resolve)
          exit 0
          ;;
        build:--scratch-path)
          if echo "$*" | grep -q -- "--target InstantSwiftDataMacros"; then
            exit 0
          fi
          ;;
        test:--scratch-path)
          if echo "$*" | grep -q -- "InstantSwiftDataMacrosTests.InstantEntityMacroTests"; then
            echo "macro tests passed"
            exit 0
          fi
          ;;
      esac
      case "$2:$3:$4" in
        instant-swift-data:schema:generate)
          output=""
          while [ "$#" -gt 0 ]; do
            if [ "$1" = "--to" ]; then
              shift
              output="$1"
              break
            fi
            shift
          done
          if [ -n "$output" ]; then
            mkdir -p "$(dirname "$output")"
            echo "// generated schema" > "$output"
          fi
          echo '{"example":"validation","kind":"schema","fileName":"instant.schema.ts","byteCount":19,"transport":"not-implemented-local-cache-only"}'
          ;;
        instant-swift-data:perms:generate)
          output=""
          while [ "$#" -gt 0 ]; do
            if [ "$1" = "--to" ]; then
              shift
              output="$1"
              break
            fi
            shift
          done
          if [ -n "$output" ]; then
            mkdir -p "$(dirname "$output")"
            echo "// generated perms" > "$output"
          fi
          echo '{"example":"validation","kind":"permissions","fileName":"instant.perms.ts","byteCount":18,"transport":"not-implemented-local-cache-only"}'
          ;;
        instant-swift-data:schema:verify)
          echo '{"example":"validation","kind":"schema","ok":true,"path":"validation/fixtures/instant.schema.ts"}'
          ;;
        instant-swift-data:perms:verify)
          echo '{"example":"validation","kind":"permissions","ok":true,"path":"validation/fixtures/instant.perms.ts"}'
          ;;
        instant-swift-data-validation-runner:--local-todos:)
          if [ "${SWIFT_STUB_FAIL_LOCAL_TODOS:-}" = "1" ]; then
            exit 42
          fi
          echo '{"case":"validation.local.todos","side":"swift","event":"stub-todos","appID":"local-validation","timestampMs":1,"ok":true,"details":{}}'
          ;;
        instant-swift-data-validation-runner:--local-integrations:)
          integration_details_base='"cachePath":"/tmp/stub-local-integrations.sqlite","authUserID":"user-1","roomType":"chat","roomID":"validation","topic":"sendEmoji"'
          echo '{"case":"validation.local.integrations","side":"swift","event":"auth","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":[],"roomPresenceValueKeys":[],"topicMessageIDs":[],"topicPayloadKeys":[],"fileIDs":[],"fileByteCounts":[],"fileContentDigests":[],"streamChunkIDs":[],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"room-presence","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":[],"topicPayloadKeys":[],"fileIDs":[],"fileByteCounts":[],"fileContentDigests":[],"streamChunkIDs":[],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"room-topic","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":[],"fileByteCounts":[],"fileContentDigests":[],"streamChunkIDs":[],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"file","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":[],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"stream","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":["chunk-stub"],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"share-create","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":["chunk-stub"],"activeShareIDs":["share-stub"],"revokedShareIDs":[],"shareMemberUserIDs":["user-1"]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"share-accept","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":["chunk-stub"],"activeShareIDs":["share-stub"],"revokedShareIDs":[],"shareMemberUserIDs":["user-1","user-2"]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"share-revoke","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":["chunk-stub"],"activeShareIDs":[],"revokedShareIDs":["share-stub"],"shareMemberUserIDs":["user-1","user-2"]}}'
          echo '{"case":"validation.local.integrations","side":"swift","event":"relaunch","appID":"local-validation","timestampMs":2,"ok":true,"details":{'"$integration_details_base"',"roomMemberIDs":["user-1"],"roomPresenceValueKeys":["name","status"],"topicMessageIDs":["topic-stub"],"topicPayloadKeys":["emoji"],"fileIDs":["file-stub"],"fileByteCounts":[23],"fileContentDigests":["fnv1a64:stub"],"streamChunkIDs":["chunk-stub"],"activeShareIDs":[],"revokedShareIDs":[],"shareMemberUserIDs":[]}}'
          ;;
        instant-swift-data-validation-runner:--server-transaction-loopback:)
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"stub-server-loopback","appID":"local-validation","timestampMs":2,"ok":true,"details":{}}'
          ;;
        instant-swift-data-validation-runner:--cloudkit-demo:)
          echo '{"case":"validation.cloudkit.demo","side":"swift","event":"stub-cloudkit-demo","appID":"cloudkit-demo-validation","timestampMs":3,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:live-session)
          expected="run instant-swift-data validation live-session --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected live session arguments: $*" >&2
            exit 65
          fi
          remote_app_id="${INSTANT_SWIFT_DATA_REMOTE_APP_ID:-local-validation}"
          if [ "${INSTANT_APP_ID:-}" != "$remote_app_id" ]; then
            echo "unexpected live session app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          echo '{"case":"validation.live.session","side":"swift","event":"stub-live-session","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok","add-query-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          ;;
        instant-swift-data:validation:live-transaction)
          expected="run instant-swift-data validation live-transaction --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected live transaction arguments: $*" >&2
            exit 65
          fi
          remote_app_id="${INSTANT_SWIFT_DATA_REMOTE_APP_ID:-local-validation}"
          if [ "${INSTANT_APP_ID:-}" != "$remote_app_id" ]; then
            echo "unexpected live transaction app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          echo '{"case":"validation.live.transaction","side":"swift","event":"session-url","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":[],"receivedOps":[],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"send-init","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init"],"receivedOps":[],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"receive-init-ok","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init"],"receivedOps":["init-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"send-add-query","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"receive-query","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok","add-query-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"send-transact","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query","transact"],"receivedOps":["init-ok","add-query-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"receive-transact-ok","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query","transact"],"receivedOps":["init-ok","add-query-ok","transact-ok"],"transactionID":"local-stub-tx","transactionISN":"local-isn-stub-tx","proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.transaction","side":"swift","event":"receive-transaction-refresh","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query","transact"],"receivedOps":["init-ok","add-query-ok","transact-ok","refresh-ok"],"transactionID":"local-stub-tx","transactionISN":"local-isn-stub-tx","processedTransactionID":"local-stub-tx","proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          ;;
        instant-swift-data:validation:live-observe)
          expected="run instant-swift-data validation live-observe --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected live observe arguments: $*" >&2
            exit 65
          fi
          remote_app_id="${INSTANT_SWIFT_DATA_REMOTE_APP_ID:-local-validation}"
          if [ "${INSTANT_APP_ID:-}" != "$remote_app_id" ]; then
            echo "unexpected live observe app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          echo '{"case":"validation.live.observe","side":"swift","event":"session-url","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":[],"receivedOps":[],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.observe","side":"swift","event":"send-init","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init"],"receivedOps":[],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.observe","side":"swift","event":"receive-init-ok","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init"],"receivedOps":["init-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.observe","side":"swift","event":"send-add-query","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          echo '{"case":"validation.live.observe","side":"swift","event":"receive-query","appID":"'"$remote_app_id"'","timestampMs":3,"ok":true,"details":{"sentOps":["init","add-query"],"receivedOps":["init-ok","add-query-ok"],"proofLevel":"local-protocol","remoteBoundary":"pending-cross-client-sync","websocketURL":"wss://api.instantdb.com/runtime/session?app_id='"$remote_app_id"'"}}'
          ;;
        instant-swift-data:validation:reminders)
          expected="run instant-swift-data validation reminders --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected reminders arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected reminders app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          if [ "${SWIFT_STUB_FAIL_REMINDERS:-}" = "1" ]; then
            exit 46
          fi
          echo '{"case":"validation.reminders","side":"swift","event":"stub-reminders","appID":"local-validation","timestampMs":3,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:typed-drafts)
          expected="run instant-swift-data validation typed-drafts --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected typed draft arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected typed draft app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          if [ "${SWIFT_STUB_FAIL_TYPED_DRAFTS:-}" = "1" ]; then
            exit 44
          fi
          echo '{"case":"validation.typed.drafts","side":"swift","event":"stub-drafts","appID":"local-validation","timestampMs":3,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:platform-adapters)
          expected="run instant-swift-data validation platform-adapters --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected platform adapter arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected platform adapter app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          echo '{"case":"validation.platform.adapters","side":"swift","event":"stub-adapters","appID":"local-validation","timestampMs":4,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:syncups-recording)
          expected="run instant-swift-data validation syncups-recording --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected syncups recording arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected syncups recording app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          if [ "${SWIFT_STUB_FAIL_SYNCUPS_RECORDING:-}" = "1" ]; then
            exit 45
          fi
          echo '{"case":"validation.syncups.recording","side":"swift","event":"stub-syncups-recording","appID":"local-validation","timestampMs":5,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:parity-report)
          expected="run instant-swift-data validation parity-report --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected parity report arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected parity report app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          echo '{"case":"validation.parity.report","side":"swift","event":"stub-parity","appID":"local-validation","timestampMs":6,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:coverage)
          expected="run instant-swift-data validation coverage --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected coverage arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected coverage app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          coverage_event="stub-coverage"
          if [ -n "${INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR:-}" ]; then
            if [ "${SWIFT_STUB_FAIL_FINAL_COVERAGE:-}" = "1" ]; then
              exit 48
            fi
            coverage_event="stub-coverage-final"
          fi
          echo '{"case":"validation.coverage","side":"swift","event":"'"$coverage_event"'","appID":"local-validation","timestampMs":6,"ok":true,"details":{}}'
          ;;
        instant-swift-data:validation:server-transaction-loopback)
          expected="run instant-swift-data validation server-transaction-loopback --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected TypeScript contract loopback arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected TypeScript contract loopback app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          if [ ! -s "${INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT:-}" ]; then
            echo "missing TypeScript server transaction contract: ${INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT:-}" >&2
            exit 67
          fi
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"local-outbox","appID":"local-validation","timestampMs":6,"ok":true,"details":{"pendingMutationIDs":["validation.loopback.local"],"todoIDs":["validation-loopback-local"]}}'
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"server-apply","appID":"local-validation","timestampMs":6,"ok":true,"details":{"mutationTransactionID":"validation.loopback.server","processedTransactionID":"validation.loopback.server","changedEntityIDs":["validation-loopback-server"],"todoIDs":["validation-loopback-local","validation-loopback-server"]}}'
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"observer-publish","appID":"local-validation","timestampMs":6,"ok":true,"details":{"mutationTransactionID":"validation.loopback.server","processedTransactionID":"validation.loopback.server","observerTodoIDs":["validation-loopback-local","validation-loopback-server"],"todoIDs":["validation-loopback-local","validation-loopback-server"]}}'
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"typescript-contract-apply","appID":"local-validation","timestampMs":6,"ok":true,"details":{"mutationTransactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","changedEntityIDs":["validation-typescript-server"],"observerTodoIDs":["validation-loopback-local","validation-loopback-server","validation-typescript-server"],"todoIDs":["validation-loopback-local","validation-loopback-server","validation-typescript-server"]}}'
          echo '{"case":"validation.server.transaction.loopback","side":"swift","event":"relaunch","appID":"local-validation","timestampMs":6,"ok":true,"details":{"mutationTransactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","pendingMutationIDs":["validation.loopback.local"],"todoIDs":["validation-loopback-local","validation-loopback-server","validation-typescript-server"]}}'
          ;;
        instant-swift-data-benchmarks:--suite:local-todos)
          expected="run instant-swift-data-benchmarks --suite local-todos --iterations ${INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS:-1} --app-id local-validation --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected benchmark arguments: $*" >&2
            exit 65
          fi
          if [ "${SWIFT_STUB_FAIL_BENCHMARK:-}" = "1" ]; then
            exit 43
          fi
          echo '{"case":"benchmark.local.todos","side":"swift","event":"summary","appID":"local-validation","timestampMs":7,"ok":true,"details":{"suite":"local-todos","iterations":7}}'
          ;;
        instant-swift-data:admin:transact)
          if [ "$5:$6:$7:$8:$9:${10}:${11}" != 'validationTransport:contract-note:--merge:{"done":false,"title":"Swift transport contract"}:--transaction-id:validation-transport-contract:--json' ]; then
            echo "unexpected admin transact arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected transport contract app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          case "${INSTANT_SWIFT_DATA_HOME:-}" in
            */transport-contract-home)
              ;;
            *)
              echo "unexpected transport contract home: ${INSTANT_SWIFT_DATA_HOME:-}" >&2
              exit 67
              ;;
          esac
          echo '{"appID":"local-validation","event":"transact","changedID":"contract-note","transport":"not-implemented-local-cache-only","namespace":"validationTransport","transactionID":"validation-transport-contract","changedEntityIDs":["contract-note"],"tripleCount":3,"pendingMutationCount":1,"snapshotCount":1,"snapshots":[]}'
          ;;
        instant-swift-data:outbox:transport)
          if [ "$5" != "--json" ] || [ -n "${6:-}" ]; then
            echo "unexpected outbox transport arguments: $*" >&2
            exit 65
          fi
          if [ "${INSTANT_APP_ID:-}" != "local-validation" ]; then
            echo "unexpected outbox transport app id: ${INSTANT_APP_ID:-}" >&2
            exit 66
          fi
          case "${INSTANT_SWIFT_DATA_HOME:-}" in
            */transport-contract-home)
              ;;
            *)
              echo "unexpected outbox transport home: ${INSTANT_SWIFT_DATA_HOME:-}" >&2
              exit 67
              ;;
          esac
          echo '{"appID":"local-validation","event":"transport","transport":"not-implemented-local-cache-only","includeFailed":false,"mutationCount":1,"txStepCount":3,"preconditionCount":0,"mutations":[{"mutationID":"validation-transport-contract","transactionID":"validation-transport-contract","status":"pending","preconditions":[],"txSteps":[["add-triple","contract-note","validationTransport/id","contract-note"],["add-triple","contract-note","validationTransport/done",false],["add-triple","contract-note","validationTransport/title","Swift transport contract"]]}]}'
          ;;
        *)
          echo "unexpected swift arguments: $*" >&2
          exit 64
          ;;
      esac
      """,
      to: binURL.appendingPathComponent("swift")
    )
    try writeExecutable(
      """
      #!/bin/sh
      if [ "$1" != "validation/ts-runner/src/main.ts" ]; then
        echo "unexpected node script: $1" >&2
        exit 67
      fi
      remote_app_id="${INSTANT_SWIFT_DATA_REMOTE_APP_ID:-local-validation}"
      case "$2" in
        --fixtures)
          if [ "$3:$4" != "--app-id:local-validation" ]; then
            echo "unexpected fixture arguments: $*" >&2
            exit 68
          fi
          echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures","appID":"local-validation","timestampMs":8,"ok":true,"details":{}}'
          ;;
        --swift-transport-contract)
          if [ "$4:$5" != "--app-id:local-validation" ]; then
            echo "unexpected transport contract arguments: $*" >&2
            exit 73
          fi
          if [ ! -s "$3" ]; then
            echo "missing swift transport contract artifact: $3" >&2
            exit 74
          fi
          echo '{"case":"validation.typescript.transport-contract","side":"typescript","event":"swift-transport-contract","appID":"local-validation","timestampMs":9,"ok":true,"details":{"proofLevel":"contract-only","remoteBoundary":"pending"}}'
          ;;
        --swift-local-integrations-contract)
          if [ "$4:$5" != "--app-id:local-validation" ]; then
            echo "unexpected local integrations contract arguments: $*" >&2
            exit 80
          fi
          if [ ! -s "$3" ]; then
            echo "missing swift local integrations contract artifact: $3" >&2
            exit 81
          fi
          echo '{"case":"validation.typescript.local-integrations-contract","side":"typescript","event":"swift-local-integrations-contract","appID":"local-validation","timestampMs":9,"ok":true,"details":{"proofLevel":"contract-only","remoteBoundary":"local-room-contract","room":{"type":"chat","id":"validation"},"topic":"sendEmoji","roomMemberIDs":["user-1"],"topicMessageIDs":["topic-stub"],"roomPresenceValueKeys":["name","status"],"topicPayloadKeys":["emoji"]}}'
          ;;
        --swift-live-session-contract)
          if [ "$4:$5" != "--app-id:$remote_app_id" ]; then
            echo "unexpected live session contract arguments: $*" >&2
            exit 76
          fi
          if [ ! -s "$3" ]; then
            echo "missing swift live session contract artifact: $3" >&2
            exit 77
          fi
          echo '{"case":"validation.typescript.live-session-contract","side":"typescript","event":"swift-live-session-contract","appID":"'"$remote_app_id"'","timestampMs":9,"ok":true,"details":{"proofLevel":"contract-only","remoteBoundary":"pending-cross-client-sync"}}'
          ;;
        --swift-live-transaction-contract)
          if [ "$4:$5" != "--app-id:$remote_app_id" ]; then
            echo "unexpected live transaction contract arguments: $*" >&2
            exit 78
          fi
          if [ ! -s "$3" ]; then
            echo "missing swift live transaction contract artifact: $3" >&2
            exit 79
          fi
          echo '{"case":"validation.typescript.live-transaction-contract","side":"typescript","event":"swift-live-transaction-contract","appID":"'"$remote_app_id"'","timestampMs":9,"ok":true,"details":{"proofLevel":"contract-only","remoteBoundary":"pending-cross-client-sync","transactionID":"local-stub-tx","processedTransactionID":"local-stub-tx","transactionISN":"local-isn-stub-tx"}}'
          ;;
        --typescript-server-transaction-contract)
          if [ "$4:$5" != "--app-id:local-validation" ]; then
            echo "unexpected TypeScript server transaction contract arguments: $*" >&2
            exit 75
          fi
          mkdir -p "$(dirname "$3")"
          printf '%s\n' '{"case":"validation.typescript.server.transaction.contract","event":"typescript-server-transaction-contract","appID":"local-validation","transactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","entityID":"validation-typescript-server","text":"TypeScript-authored server transaction","createdAtMs":4100002000003,"operations":[{"type":"requireEntityMissing","entityID":"validation-typescript-server","namespace":"todos"},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/id","value":{"type":"string","string":"validation-typescript-server"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/text","value":{"type":"string","string":"TypeScript-authored server transaction"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/isCompleted","value":{"type":"bool","bool":false},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/createdAt","value":{"type":"date","dateMs":4100002000003},"txTimeMs":4100002000003}]}' > "$3"
          echo '{"case":"validation.typescript.server.transaction.contract","side":"typescript","event":"typescript-server-transaction-contract","appID":"local-validation","timestampMs":10,"ok":true,"details":{"proofLevel":"contract-only","remoteBoundary":"pending","transactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","operationCount":5}}'
          ;;
        --boundary-preflight|--boundary-admin-smoke)
          if [ "$3:$4" != "--app-id:$remote_app_id" ]; then
            echo "unexpected boundary arguments: $*" >&2
            exit 69
          fi
          if [ "${EXPECT_TS_REQUIRE_BOUNDARY:-}" = "1" ]; then
            if [ "$2" != "--boundary-admin-smoke" ]; then
              echo "expected required boundary smoke: $*" >&2
              exit 73
            fi
            if [ "${5:-}" != "--require-boundary" ]; then
              echo "missing required boundary flag: $*" >&2
              exit 71
            fi
          elif [ "$2" != "--boundary-preflight" ]; then
            echo "unexpected required boundary smoke: $*" >&2
            exit 74
          elif [ -n "${5:-}" ]; then
            echo "unexpected optional boundary flag: $*" >&2
            exit 72
          fi
          if [ "${TS_STUB_FAIL_BOUNDARY:-}" = "1" ]; then
            echo '{"case":"validation.typescript.boundary","side":"typescript","event":"preflight-skipped","appID":"'"$remote_app_id"'","timestampMs":9,"ok":false,"details":{"missing":["INSTANT_SWIFT_DATA_REMOTE_APP_ID or INSTANT_APP_ID"]}}'
            exit 47
          fi
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"preflight-skipped","appID":"'"$remote_app_id"'","timestampMs":9,"ok":false,"details":{"missing":["INSTANT_SWIFT_DATA_REMOTE_APP_ID or INSTANT_APP_ID"]}}'
          ;;
        --boundary-swift-live-observe)
          if [ "$3:$4:$5" != "--app-id:$remote_app_id:--require-boundary" ]; then
            echo "unexpected Swift-to-TypeScript boundary arguments: $*" >&2
            exit 82
          fi
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"swift-to-typescript-boundary","appID":"'"$remote_app_id"'","timestampMs":9,"ok":true,"details":{"proofLevel":"real-swift-websocket-to-typescript-admin-sse","remoteBoundary":"swift-websocket-to-typescript-admin-sse"}}'
          ;;
        --boundary-typescript-live-observe)
          if [ "$3:$4:$5" != "--app-id:$remote_app_id:--require-boundary" ]; then
            echo "unexpected TypeScript-to-Swift boundary arguments: $*" >&2
            exit 83
          fi
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"swift-observe-refresh","appID":"'"$remote_app_id"'","timestampMs":8,"ok":true,"details":{"entityID":"typescript-live-boundary-stub","swiftAppliedRefreshCount":1,"swiftCachedEntityIDs":["typescript-live-boundary-stub"],"swiftCachedTodoTexts":["TypeScript live boundary stub"]}}'
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"typescript-to-swift-boundary","appID":"'"$remote_app_id"'","timestampMs":9,"ok":true,"details":{"proofLevel":"real-typescript-admin-http-to-swift-websocket","remoteBoundary":"typescript-admin-http-to-swift-websocket","entityID":"typescript-live-boundary-stub"}}'
          ;;
        *)
          echo "unexpected node arguments: $*" >&2
          exit 70
          ;;
      esac
      """,
      to: binURL.appendingPathComponent("node")
    )
    let schemaFixtureEvents = [
      "swift-schema-fixtures-start",
      "swift-schema-generate-complete",
      "swift-perms-generate-complete",
      "swift-schema-verify-complete",
      "swift-perms-verify-complete",
      "swift-generated-schema-verify-complete",
      "swift-generated-perms-verify-complete",
      "swift-schema-fixtures-complete",
    ]

    let firstRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_REMOTE_APP_ID": "remote-validation",
        "INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS": benchmarkIterations,
      ]
    )
    #expect(firstRun.status == 0, "run-e2e.sh failed: \(firstRun.stderr)")
    let successRows = try readJSONLines(resultsURL.appendingPathComponent("orchestrator.jsonl"))
    expectNoDifference(successRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
      "swift-coverage-start",
      "swift-coverage-complete",
      "swift-benchmark-start",
      "swift-benchmark-complete",
      "swift-transport-contract-start",
      "swift-transport-contract-transact-complete",
      "swift-transport-contract-complete",
      "typescript-fixtures-start",
      "typescript-fixtures-complete",
      "typescript-transport-contract-start",
      "typescript-transport-contract-complete",
      "typescript-local-integrations-contract-start",
      "typescript-local-integrations-contract-complete",
      "typescript-live-session-contract-start",
      "typescript-live-session-contract-complete",
      "typescript-live-transaction-contract-start",
      "typescript-live-transaction-contract-complete",
      "typescript-server-transaction-contract-start",
      "typescript-server-transaction-contract-complete",
      "swift-typescript-server-transaction-contract-start",
      "swift-typescript-server-transaction-contract-complete",
      "typescript-boundary-preflight-start",
      "typescript-boundary-preflight-complete",
      "swift-coverage-final-start",
      "swift-coverage-final-complete",
      "complete",
    ])
    expectNoDifference(successRows.last?["ok"] as? Bool, true)
    #expect(
      FileManager.default.fileExists(atPath: resultsURL.appendingPathComponent("swift-local.jsonl").path)
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-local-integrations.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-server-transaction-loopback.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-cloudkit-demo.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-live-session.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-live-transaction.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-live-observe.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-reminders.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-typed-drafts.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-platform-adapters.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-syncups-recording.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-parity-report.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage-final.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-transport-contract.json").path
      )
    )
    let finalCoverageRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-coverage-final.jsonl")
    )
    expectNoDifference(
      finalCoverageRows.map { $0["event"] as? String ?? "" },
      ["stub-coverage-final"]
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-transport-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-local-integrations-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-live-transaction-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.json").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-boundary.jsonl").path
      )
    )
    let transportContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-transport-contract.jsonl")
    )
    expectNoDifference(
      transportContractRows.map { $0["event"] as? String ?? "" },
      ["swift-transport-contract"]
    )
    expectNoDifference(transportContractRows.first?["ok"] as? Bool, true)
    let localIntegrationsContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-local-integrations-contract.jsonl")
    )
    expectNoDifference(
      localIntegrationsContractRows.map { $0["event"] as? String ?? "" },
      ["swift-local-integrations-contract"]
    )
    expectNoDifference(localIntegrationsContractRows.first?["ok"] as? Bool, true)
    let localIntegrationsContractDetails = try #require(
      localIntegrationsContractRows.first?["details"] as? [String: Any]
    )
    expectNoDifference(
      localIntegrationsContractDetails["roomPresenceValueKeys"] as? [String],
      ["name", "status"]
    )
    expectNoDifference(localIntegrationsContractDetails["topicPayloadKeys"] as? [String], ["emoji"])
    let swiftLiveSessionRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-live-session.jsonl")
    )
    expectNoDifference(swiftLiveSessionRows.first?["appID"] as? String, "remote-validation")
    let liveSessionContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl")
    )
    expectNoDifference(
      liveSessionContractRows.map { $0["event"] as? String ?? "" },
      ["swift-live-session-contract"]
    )
    expectNoDifference(liveSessionContractRows.first?["ok"] as? Bool, true)
    expectNoDifference(liveSessionContractRows.first?["appID"] as? String, "remote-validation")
    let swiftLiveTransactionRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-live-transaction.jsonl")
    )
    expectNoDifference(swiftLiveTransactionRows.first?["appID"] as? String, "remote-validation")
    let swiftLiveObserveRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-live-observe.jsonl")
    )
    expectNoDifference(swiftLiveObserveRows.first?["appID"] as? String, "remote-validation")
    let liveTransactionContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-transaction-contract.jsonl")
    )
    expectNoDifference(
      liveTransactionContractRows.map { $0["event"] as? String ?? "" },
      ["swift-live-transaction-contract"]
    )
    expectNoDifference(liveTransactionContractRows.first?["ok"] as? Bool, true)
    expectNoDifference(liveTransactionContractRows.first?["appID"] as? String, "remote-validation")
    let typeScriptServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      typeScriptServerContractRows.map { $0["event"] as? String ?? "" },
      ["typescript-server-transaction-contract"]
    )
    expectNoDifference(typeScriptServerContractRows.first?["ok"] as? Bool, true)
    let swiftTypeScriptServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      swiftTypeScriptServerContractRows.map { $0["event"] as? String ?? "" },
      [
        "local-outbox",
        "server-apply",
        "observer-publish",
        "typescript-contract-apply",
        "relaunch",
      ]
    )
    expectNoDifference(swiftTypeScriptServerContractRows.map { $0["ok"] as? Bool }, [
      true, true, true, true, true,
    ])
    let boundaryRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-boundary.jsonl")
    )
    expectNoDifference(boundaryRows.map { $0["event"] as? String ?? "" }, ["preflight-skipped"])
    expectNoDifference(boundaryRows.first?["ok"] as? Bool, false)
    expectNoDifference(boundaryRows.first?["appID"] as? String, "remote-validation")

    let overrideNodeURL = tempURL.appendingPathComponent("override-node")
    try writeExecutable(
      """
      #!/bin/sh
      if [ "$1" != "validation/ts-runner/src/main.ts" ]; then
        echo "unexpected node script: $1" >&2
        exit 67
      fi
      case "$2" in
        --fixtures)
          echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures-override","appID":"local-validation","timestampMs":9,"ok":true,"details":{}}'
          ;;
        --swift-transport-contract)
          echo '{"case":"validation.typescript.transport-contract","side":"typescript","event":"transport-override","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --swift-local-integrations-contract)
          echo '{"case":"validation.typescript.local-integrations-contract","side":"typescript","event":"local-integrations-override","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --swift-live-session-contract)
          echo '{"case":"validation.typescript.live-session-contract","side":"typescript","event":"live-session-override","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --swift-live-transaction-contract)
          echo '{"case":"validation.typescript.live-transaction-contract","side":"typescript","event":"live-transaction-override","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --typescript-server-transaction-contract)
          mkdir -p "$(dirname "$3")"
          printf '%s\n' '{"case":"validation.typescript.server.transaction.contract","event":"typescript-server-transaction-contract","appID":"local-validation","transactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","entityID":"validation-typescript-server","text":"TypeScript-authored server transaction","createdAtMs":4100002000003,"operations":[{"type":"requireEntityMissing","entityID":"validation-typescript-server","namespace":"todos"},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/id","value":{"type":"string","string":"validation-typescript-server"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/text","value":{"type":"string","string":"TypeScript-authored server transaction"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/isCompleted","value":{"type":"bool","bool":false},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/createdAt","value":{"type":"date","dateMs":4100002000003},"txTimeMs":4100002000003}]}' > "$3"
          echo '{"case":"validation.typescript.server.transaction.contract","side":"typescript","event":"server-contract-override","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --boundary-preflight)
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"boundary-override","appID":"local-validation","timestampMs":11,"ok":false,"details":{}}'
          ;;
        *)
          echo "unexpected node arguments: $*" >&2
          exit 68
          ;;
      esac
      """,
      to: overrideNodeURL
    )
    let overrideRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_NODE": overrideNodeURL.path
      ]
    )
    #expect(overrideRun.status == 0, "run-e2e.sh with node override failed: \(overrideRun.stderr)")
    let overrideTypeScriptRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-fixtures.jsonl")
    )
    expectNoDifference(
      overrideTypeScriptRows.map { $0["event"] as? String ?? "" },
      ["fixtures-override"]
    )
    let overrideTransportRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-transport-contract.jsonl")
    )
    expectNoDifference(
      overrideTransportRows.map { $0["event"] as? String ?? "" },
      ["transport-override"]
    )
    let overrideLocalIntegrationsRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-local-integrations-contract.jsonl")
    )
    expectNoDifference(
      overrideLocalIntegrationsRows.map { $0["event"] as? String ?? "" },
      ["local-integrations-override"]
    )
    let overrideLiveSessionRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl")
    )
    expectNoDifference(
      overrideLiveSessionRows.map { $0["event"] as? String ?? "" },
      ["live-session-override"]
    )
    let overrideLiveTransactionRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-transaction-contract.jsonl")
    )
    expectNoDifference(
      overrideLiveTransactionRows.map { $0["event"] as? String ?? "" },
      ["live-transaction-override"]
    )
    let overrideServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      overrideServerContractRows.map { $0["event"] as? String ?? "" },
      ["server-contract-override"]
    )
    let overrideSwiftServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      overrideSwiftServerContractRows.map { $0["event"] as? String ?? "" },
      [
        "local-outbox",
        "server-apply",
        "observer-publish",
        "typescript-contract-apply",
        "relaunch",
      ]
    )
    let overrideBoundaryRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-boundary.jsonl")
    )
    expectNoDifference(
      overrideBoundaryRows.map { $0["event"] as? String ?? "" },
      ["boundary-override"]
    )
    let overrideRows = try readJSONLines(resultsURL.appendingPathComponent("orchestrator.jsonl"))
    expectNoDifference(
      overrideRows.first(where: { $0["event"] as? String == "typescript-fixtures-start" })?["ok"]
        as? Bool,
      true
    )

    let bundledHomeURL = tempURL.appendingPathComponent("home", isDirectory: true)
    let bundledNodeURL = bundledHomeURL
      .appendingPathComponent(
        ".cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin",
        isDirectory: true
      )
      .appendingPathComponent("node")
    try FileManager.default.createDirectory(
      at: bundledNodeURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try writeExecutable(
      """
      #!/bin/sh
      if [ "$1" != "validation/ts-runner/src/main.ts" ]; then
        echo "unexpected bundled node script: $1" >&2
        exit 67
      fi
      case "$2" in
        --fixtures)
          echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures-bundled","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
          ;;
        --swift-transport-contract)
          echo '{"case":"validation.typescript.transport-contract","side":"typescript","event":"transport-bundled","appID":"local-validation","timestampMs":11,"ok":true,"details":{}}'
          ;;
        --swift-local-integrations-contract)
          echo '{"case":"validation.typescript.local-integrations-contract","side":"typescript","event":"local-integrations-bundled","appID":"local-validation","timestampMs":11,"ok":true,"details":{}}'
          ;;
        --swift-live-session-contract)
          echo '{"case":"validation.typescript.live-session-contract","side":"typescript","event":"live-session-bundled","appID":"local-validation","timestampMs":11,"ok":true,"details":{}}'
          ;;
        --swift-live-transaction-contract)
          echo '{"case":"validation.typescript.live-transaction-contract","side":"typescript","event":"live-transaction-bundled","appID":"local-validation","timestampMs":11,"ok":true,"details":{}}'
          ;;
        --typescript-server-transaction-contract)
          mkdir -p "$(dirname "$3")"
          printf '%s\n' '{"case":"validation.typescript.server.transaction.contract","event":"typescript-server-transaction-contract","appID":"local-validation","transactionID":"validation.typescript.server.tx","processedTransactionID":"validation.typescript.server.processed","entityID":"validation-typescript-server","text":"TypeScript-authored server transaction","createdAtMs":4100002000003,"operations":[{"type":"requireEntityMissing","entityID":"validation-typescript-server","namespace":"todos"},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/id","value":{"type":"string","string":"validation-typescript-server"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/text","value":{"type":"string","string":"TypeScript-authored server transaction"},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/isCompleted","value":{"type":"bool","bool":false},"txTimeMs":4100002000003},{"type":"insert","entityID":"validation-typescript-server","attributeID":"todos/createdAt","value":{"type":"date","dateMs":4100002000003},"txTimeMs":4100002000003}]}' > "$3"
          echo '{"case":"validation.typescript.server.transaction.contract","side":"typescript","event":"server-contract-bundled","appID":"local-validation","timestampMs":11,"ok":true,"details":{}}'
          ;;
        --boundary-preflight)
          echo '{"case":"validation.typescript.boundary","side":"typescript","event":"boundary-bundled","appID":"local-validation","timestampMs":12,"ok":false,"details":{}}'
          ;;
        *)
          echo "unexpected bundled node arguments: $*" >&2
          exit 68
          ;;
      esac
      """,
      to: bundledNodeURL
    )
    let bundledBinURL = tempURL.appendingPathComponent("bundled-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bundledBinURL, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: binURL.appendingPathComponent("swift"),
      to: bundledBinURL.appendingPathComponent("swift")
    )
    let bundledRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "HOME": bundledHomeURL.path,
        "PATH": "\(bundledBinURL.path):/usr/bin:/bin",
      ]
    )
    #expect(bundledRun.status == 0, "run-e2e.sh with bundled node failed: \(bundledRun.stderr)")
    let bundledTypeScriptRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-fixtures.jsonl")
    )
    expectNoDifference(
      bundledTypeScriptRows.map { $0["event"] as? String ?? "" },
      ["fixtures-bundled"]
    )
    let bundledTransportRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-transport-contract.jsonl")
    )
    expectNoDifference(
      bundledTransportRows.map { $0["event"] as? String ?? "" },
      ["transport-bundled"]
    )
    let bundledLocalIntegrationsRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-local-integrations-contract.jsonl")
    )
    expectNoDifference(
      bundledLocalIntegrationsRows.map { $0["event"] as? String ?? "" },
      ["local-integrations-bundled"]
    )
    let bundledLiveSessionRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl")
    )
    expectNoDifference(
      bundledLiveSessionRows.map { $0["event"] as? String ?? "" },
      ["live-session-bundled"]
    )
    let bundledLiveTransactionRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-live-transaction-contract.jsonl")
    )
    expectNoDifference(
      bundledLiveTransactionRows.map { $0["event"] as? String ?? "" },
      ["live-transaction-bundled"]
    )
    let bundledServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      bundledServerContractRows.map { $0["event"] as? String ?? "" },
      ["server-contract-bundled"]
    )
    let bundledSwiftServerContractRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl")
    )
    expectNoDifference(
      bundledSwiftServerContractRows.map { $0["event"] as? String ?? "" },
      [
        "local-outbox",
        "server-apply",
        "observer-publish",
        "typescript-contract-apply",
        "relaunch",
      ]
    )
    let bundledBoundaryRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-boundary.jsonl")
    )
    expectNoDifference(
      bundledBoundaryRows.map { $0["event"] as? String ?? "" },
      ["boundary-bundled"]
    )

    let liveBoundaryRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_REMOTE_APP_ID": "remote-validation",
        "INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY": "1",
        "INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY": "1",
      ]
    )
    #expect(liveBoundaryRun.status == 0, "live-boundary run-e2e.sh failed: \(liveBoundaryRun.stderr)")
    let liveBoundaryRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(
      liveBoundaryRows.suffix(7).map { $0["event"] as? String ?? "" },
      [
        "typescript-swift-boundary-start",
        "typescript-swift-boundary-complete",
        "swift-typescript-boundary-start",
        "swift-typescript-boundary-complete",
        "swift-coverage-final-start",
        "swift-coverage-final-complete",
        "complete",
      ]
    )
    expectNoDifference(liveBoundaryRows.last?["ok"] as? Bool, true)
    let liveSwiftToTypeScriptRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-swift-boundary.jsonl")
    )
    expectNoDifference(
      liveSwiftToTypeScriptRows.map { $0["event"] as? String ?? "" },
      ["swift-to-typescript-boundary"]
    )
    let liveTypeScriptToSwiftRows = try readJSONLines(
      resultsURL.appendingPathComponent("swift-typescript-boundary.jsonl")
    )
    expectNoDifference(
      liveTypeScriptToSwiftRows.map { $0["event"] as? String ?? "" },
      [
        "swift-observe-refresh",
        "typescript-to-swift-boundary",
      ]
    )

    let missingNodeRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_NODE": tempURL.appendingPathComponent("missing-node").path
      ]
    )
    #expect(missingNodeRun.status == 1)
    #expect(
      missingNodeRun.stderr.contains(
        "INSTANT_SWIFT_DATA_NODE must point to an executable Node.js binary."
      )
    )
    let missingNodeRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(missingNodeRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
      "swift-coverage-start",
      "swift-coverage-complete",
      "swift-benchmark-start",
      "swift-benchmark-complete",
      "swift-transport-contract-start",
      "swift-transport-contract-transact-complete",
      "swift-transport-contract-complete",
      "missing-node",
      "complete",
    ])
    expectNoDifference(missingNodeRows.last?["ok"] as? Bool, false)
    let missingNodeDetails = try #require(missingNodeRows.last?["details"] as? [String: Any])
    expectNoDifference(missingNodeDetails["failed"] as? String, "missing-node")
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-transport-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.json").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-boundary.jsonl").path
      )
    )

    try "stale integrations\n".write(
      to: resultsURL.appendingPathComponent("swift-local-integrations.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale server loopback\n".write(
      to: resultsURL.appendingPathComponent("swift-server-transaction-loopback.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale cloudkit demo\n".write(
      to: resultsURL.appendingPathComponent("swift-cloudkit-demo.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale reminders\n".write(
      to: resultsURL.appendingPathComponent("swift-reminders.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typed drafts\n".write(
      to: resultsURL.appendingPathComponent("swift-typed-drafts.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale parity report\n".write(
      to: resultsURL.appendingPathComponent("swift-parity-report.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale coverage\n".write(
      to: resultsURL.appendingPathComponent("swift-coverage.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale final coverage\n".write(
      to: resultsURL.appendingPathComponent("swift-coverage-final.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale platform adapters\n".write(
      to: resultsURL.appendingPathComponent("swift-platform-adapters.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale syncups recording\n".write(
      to: resultsURL.appendingPathComponent("swift-syncups-recording.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale benchmark\n".write(
      to: resultsURL.appendingPathComponent("swift-benchmark.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale swift transport contract transact\n".write(
      to: resultsURL.appendingPathComponent("swift-transport-contract-transact.json"),
      atomically: true,
      encoding: .utf8
    )
    try "stale swift transport contract\n".write(
      to: resultsURL.appendingPathComponent("swift-transport-contract.json"),
      atomically: true,
      encoding: .utf8
    )
    let staleTransportHomeURL = resultsURL.appendingPathComponent(
      "transport-contract-home",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: staleTransportHomeURL,
      withIntermediateDirectories: true
    )
    try "stale transport home\n".write(
      to: staleTransportHomeURL.appendingPathComponent("cache.sqlite"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript\n".write(
      to: resultsURL.appendingPathComponent("typescript-fixtures.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript transport contract\n".write(
      to: resultsURL.appendingPathComponent("typescript-transport-contract.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript live session contract\n".write(
      to: resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript server transaction contract\n".write(
      to: resultsURL.appendingPathComponent("typescript-server-transaction-contract.json"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript server transaction contract evidence\n".write(
      to: resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale swift typescript server transaction contract\n".write(
      to: resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale boundary\n".write(
      to: resultsURL.appendingPathComponent("typescript-boundary.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let failedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: ["SWIFT_STUB_FAIL_LOCAL_TODOS": "1"]
    )
    #expect(failedRun.status == 42)
    let failedRows = try readJSONLines(resultsURL.appendingPathComponent("orchestrator.jsonl"))
    expectNoDifference(failedRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-failed",
      "complete",
    ])
    expectNoDifference(failedRows.last?["ok"] as? Bool, false)
    let failedDetails = try #require(failedRows.last?["details"] as? [String: Any])
    expectNoDifference(failedDetails["failed"] as? String, "swift-local")
    expectNoDifference((failedDetails["exitCode"] as? NSNumber)?.intValue, 42)
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-local-integrations.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-server-transaction-loopback.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-cloudkit-demo.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-reminders.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-typed-drafts.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-parity-report.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage-final.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-platform-adapters.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-syncups-recording.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-transport-contract-transact.json").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-transport-contract.json").path
      )
    )
    #expect(!FileManager.default.fileExists(atPath: staleTransportHomeURL.path))
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-transport-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-live-session-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.json").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-typescript-server-transaction-contract.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-boundary.jsonl").path
      )
    )

    let typedDraftFailedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: ["SWIFT_STUB_FAIL_TYPED_DRAFTS": "1"]
    )
    #expect(typedDraftFailedRun.status == 44)
    let typedDraftFailedRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(typedDraftFailedRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-failed",
      "complete",
    ])
    expectNoDifference(typedDraftFailedRows.last?["ok"] as? Bool, false)
    let typedDraftFailedDetails = try #require(
      typedDraftFailedRows.last?["details"] as? [String: Any]
    )
    expectNoDifference(typedDraftFailedDetails["failed"] as? String, "swift-typed-drafts")
    expectNoDifference((typedDraftFailedDetails["exitCode"] as? NSNumber)?.intValue, 44)
    expectNoDifference(
      try String(
        contentsOf: resultsURL.appendingPathComponent("swift-typed-drafts.jsonl"),
        encoding: .utf8
      ),
      ""
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-platform-adapters.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-syncups-recording.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-parity-report.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )

    let syncUpsRecordingFailedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: ["SWIFT_STUB_FAIL_SYNCUPS_RECORDING": "1"]
    )
    #expect(syncUpsRecordingFailedRun.status == 45)
    let syncUpsRecordingFailedRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(syncUpsRecordingFailedRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-failed",
      "complete",
    ])
    expectNoDifference(syncUpsRecordingFailedRows.last?["ok"] as? Bool, false)
    let syncUpsRecordingFailedDetails = try #require(
      syncUpsRecordingFailedRows.last?["details"] as? [String: Any]
    )
    expectNoDifference(syncUpsRecordingFailedDetails["failed"] as? String, "swift-syncups-recording")
    expectNoDifference((syncUpsRecordingFailedDetails["exitCode"] as? NSNumber)?.intValue, 45)
    expectNoDifference(
      try String(
        contentsOf: resultsURL.appendingPathComponent("swift-syncups-recording.jsonl"),
        encoding: .utf8
      ),
      ""
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-parity-report.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-coverage.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )

    try "stale benchmark\n".write(
      to: resultsURL.appendingPathComponent("swift-benchmark.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale typescript\n".write(
      to: resultsURL.appendingPathComponent("typescript-fixtures.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let benchmarkFailedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS": benchmarkIterations,
        "SWIFT_STUB_FAIL_BENCHMARK": "1",
      ]
    )
    #expect(benchmarkFailedRun.status == 43)
    let benchmarkFailedRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(benchmarkFailedRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
      "swift-coverage-start",
      "swift-coverage-complete",
      "swift-benchmark-start",
      "swift-benchmark-failed",
      "complete",
    ])
    expectNoDifference(benchmarkFailedRows.last?["ok"] as? Bool, false)
    let benchmarkFailedDetails = try #require(
      benchmarkFailedRows.last?["details"] as? [String: Any]
    )
    expectNoDifference(benchmarkFailedDetails["failed"] as? String, "swift-benchmark")
    expectNoDifference((benchmarkFailedDetails["exitCode"] as? NSNumber)?.intValue, 43)
    expectNoDifference(
      try String(
        contentsOf: resultsURL.appendingPathComponent("swift-benchmark.jsonl"),
        encoding: .utf8
      ),
      ""
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )

    let finalCoverageFailedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS": benchmarkIterations,
        "SWIFT_STUB_FAIL_FINAL_COVERAGE": "1",
      ]
    )
    #expect(finalCoverageFailedRun.status == 48)
    let finalCoverageFailedRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(
      finalCoverageFailedRows.suffix(3).map { $0["event"] as? String ?? "" },
      [
        "swift-coverage-final-start",
        "swift-coverage-final-failed",
        "complete",
      ]
    )
    expectNoDifference(finalCoverageFailedRows.last?["ok"] as? Bool, false)
    let finalCoverageFailedDetails = try #require(
      finalCoverageFailedRows.last?["details"] as? [String: Any]
    )
    expectNoDifference(finalCoverageFailedDetails["failed"] as? String, "swift-coverage-final")
    expectNoDifference((finalCoverageFailedDetails["exitCode"] as? NSNumber)?.intValue, 48)
    expectNoDifference(
      try String(
        contentsOf: resultsURL.appendingPathComponent("swift-coverage-final.jsonl"),
        encoding: .utf8
      ),
      ""
    )

    try "stale typescript\n".write(
      to: resultsURL.appendingPathComponent("typescript-fixtures.jsonl"),
      atomically: true,
      encoding: .utf8
    )
    try "stale boundary\n".write(
      to: resultsURL.appendingPathComponent("typescript-boundary.jsonl"),
      atomically: true,
      encoding: .utf8
    )

    let boundaryFailedRun = try runValidationRunE2E(
      scriptURL: scriptURL,
      resultsURL: resultsURL,
      binURL: binURL,
      extraEnvironment: [
        "EXPECT_TS_REQUIRE_BOUNDARY": "1",
        "INSTANT_SWIFT_DATA_REQUIRE_REMOTE_PREFLIGHT": "1",
        "INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS": benchmarkIterations,
        "TS_STUB_FAIL_BOUNDARY": "1",
      ]
    )
    #expect(boundaryFailedRun.status == 47)
    let boundaryFailedRows = try readJSONLines(
      resultsURL.appendingPathComponent("orchestrator.jsonl")
    )
    expectNoDifference(boundaryFailedRows.map { $0["event"] as? String ?? "" }, [
      "start",
    ] + schemaFixtureEvents + [
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-server-transaction-loopback-start",
      "swift-server-transaction-loopback-complete",
      "swift-cloudkit-demo-start",
      "swift-cloudkit-demo-complete",
      "swift-live-session-start",
      "swift-live-session-complete",
      "swift-live-transaction-start",
      "swift-live-transaction-complete",
      "swift-live-observe-start",
      "swift-live-observe-complete",
      "swift-reminders-start",
      "swift-reminders-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
      "swift-coverage-start",
      "swift-coverage-complete",
      "swift-benchmark-start",
      "swift-benchmark-complete",
      "swift-transport-contract-start",
      "swift-transport-contract-transact-complete",
      "swift-transport-contract-complete",
      "typescript-fixtures-start",
      "typescript-fixtures-complete",
      "typescript-transport-contract-start",
      "typescript-transport-contract-complete",
      "typescript-local-integrations-contract-start",
      "typescript-local-integrations-contract-complete",
      "typescript-live-session-contract-start",
      "typescript-live-session-contract-complete",
      "typescript-live-transaction-contract-start",
      "typescript-live-transaction-contract-complete",
      "typescript-server-transaction-contract-start",
      "typescript-server-transaction-contract-complete",
      "swift-typescript-server-transaction-contract-start",
      "swift-typescript-server-transaction-contract-complete",
      "typescript-boundary-preflight-start",
      "typescript-boundary-preflight-failed",
      "complete",
    ])
    expectNoDifference(boundaryFailedRows.last?["ok"] as? Bool, false)
    let boundaryStartRow = try #require(
      boundaryFailedRows.first {
        $0["event"] as? String == "typescript-boundary-preflight-start"
      }
    )
    let boundaryStartDetails = try #require(
      boundaryStartRow["details"] as? [String: Any]
    )
    expectNoDifference(boundaryStartDetails["required"] as? Bool, true)
    let boundaryFailedDetails = try #require(
      boundaryFailedRows.last?["details"] as? [String: Any]
    )
    expectNoDifference(boundaryFailedDetails["failed"] as? String, "typescript-boundary-preflight")
    expectNoDifference((boundaryFailedDetails["exitCode"] as? NSNumber)?.intValue, 47)
    let boundaryFailureRows = try readJSONLines(
      resultsURL.appendingPathComponent("typescript-boundary.jsonl")
    )
    expectNoDifference(
      boundaryFailureRows.map { $0["event"] as? String ?? "" },
      ["preflight-skipped"]
    )
  }
}

private let platformAdapterValidationEvents = [
  "fetch-all",
  "fetch-one",
  "fetch",
  "local-id",
  "auth-session",
  "room-presence",
  "room-topic-messages",
  "stored-files",
  "stream-chunks",
  "shares",
  "projected-bindings",
  "fetch-all-filtered-reload",
  "fetch-all-dynamic-query",
  "fetch-one-dynamic-query",
  "fetch-request-dynamic-query",
  "fetch-all-nil-query",
  "fetch-one-nil-query",
  "fetch-request-nil-request",
  "fetch-all-cached-prior-error",
  "fetch-all-cancellation",
  "fetch-request-cancellation",
  "infinite-query-dynamic-cancellation",
  "infinite-query-dynamic-load",
  "live-wrapper-dynamic-cancellation",
]

private let platformAdapterValidationAdapters = [
  "@FetchAll",
  "@FetchOne",
  "@Fetch",
  "@LocalID",
  "@AuthSession",
  "@RoomPresence",
  "@RoomTopicMessages",
  "@StoredFiles",
  "@StreamChunks",
  "@Shares",
  "Projected bindings",
  "@FetchAll/@Fetch(filtered)",
  "@FetchAll(dynamic)",
  "@FetchOne(dynamic)",
  "@Fetch(request dynamic)",
  "@FetchAll(nil)",
  "@FetchOne(nil)",
  "@Fetch(request nil)",
  "@FetchAll(error)",
  "@FetchAll(cancellation)",
  "@Fetch(request cancellation)",
  "@InfiniteQuery(dynamic cancellation)",
  "@InfiniteQuery(dynamic load)",
  "@RoomPresence(dynamic cancellation)",
]

private let projectedBindingAdapters = [
  "@FetchAll",
  "@InfiniteQuery",
  "@FetchOne",
  "@Fetch",
  "@LocalID",
  "@AuthSession",
  "@RoomPresence",
  "@RoomTopicMessages",
  "@StoredFiles",
  "@StreamChunks",
  "@Shares",
]

private let syncUpsRecordingValidationEvents = [
  "seed",
  "speech-task",
  "speaker-advance",
  "finish",
  "meeting-save",
  "settings-open",
  "relaunch",
]

private func temporaryCacheURL() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataValidationTests-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("state.sqlite")
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

@discardableResult
private func runTypeScriptValidationRunner(
  arguments: [String],
  currentDirectory: URL,
  environment: [String: String?] = [:]
) throws -> (status: Int32, stdout: String, stderr: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["node", "validation/ts-runner/src/main.ts"] + arguments
  process.currentDirectoryURL = currentDirectory
  var processEnvironment = ProcessInfo.processInfo.environment
  for (key, value) in environment {
    processEnvironment[key] = value
  }
  process.environment = processEnvironment

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe
  let outputCapture = ValidationPipeCapture()
  let errorCapture = ValidationPipeCapture()
  outputPipe.fileHandleForReading.readabilityHandler = { handle in
    outputCapture.append(handle.availableData)
  }
  errorPipe.fileHandleForReading.readabilityHandler = { handle in
    errorCapture.append(handle.availableData)
  }
  try process.run()
  process.waitUntilExit()
  outputPipe.fileHandleForReading.readabilityHandler = nil
  errorPipe.fileHandleForReading.readabilityHandler = nil
  outputCapture.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
  errorCapture.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

  let output = String(decoding: outputCapture.data(), as: UTF8.self)
  let error = String(decoding: errorCapture.data(), as: UTF8.self)
  return (process.terminationStatus, output, error)
}

@discardableResult
private func runValidationRunner(
  arguments: [String],
  environment: [String: String?] = [:]
) throws -> (status: Int32, stdout: String, stderr: String) {
  let packageURL = packageRootURL()
  let executableURL = packageURL.appendingPathComponent(
    ".build/debug/instant-swift-data-validation-runner"
  )

  let process = Process()
  if FileManager.default.isExecutableFile(atPath: executableURL.path) {
    process.executableURL = executableURL
    process.arguments = arguments
  } else {
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run", "instant-swift-data-validation-runner"] + arguments
  }
  process.currentDirectoryURL = packageURL
  var processEnvironment = ProcessInfo.processInfo.environment
  for (key, value) in environment {
    processEnvironment[key] = value
  }
  process.environment = processEnvironment

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe
  let outputCapture = ValidationPipeCapture()
  let errorCapture = ValidationPipeCapture()
  outputPipe.fileHandleForReading.readabilityHandler = { handle in
    outputCapture.append(handle.availableData)
  }
  errorPipe.fileHandleForReading.readabilityHandler = { handle in
    errorCapture.append(handle.availableData)
  }
  try process.run()
  process.waitUntilExit()
  outputPipe.fileHandleForReading.readabilityHandler = nil
  errorPipe.fileHandleForReading.readabilityHandler = nil
  outputCapture.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
  errorCapture.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

  let output = String(
    decoding: outputCapture.data(),
    as: UTF8.self
  )
  let error = String(
    decoding: errorCapture.data(),
    as: UTF8.self
  )
  return (process.terminationStatus, output, error)
}

@discardableResult
private func runValidationRunE2E(
  scriptURL: URL,
  resultsURL: URL,
  binURL: URL,
  extraEnvironment: [String: String] = [:]
) throws -> (status: Int32, stdout: String, stderr: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = [scriptURL.path]
  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe
  let outputCapture = ValidationPipeCapture()
  let errorCapture = ValidationPipeCapture()
  outputPipe.fileHandleForReading.readabilityHandler = { handle in
    outputCapture.append(handle.availableData)
  }
  errorPipe.fileHandleForReading.readabilityHandler = { handle in
    errorCapture.append(handle.availableData)
  }
  var environment = ProcessInfo.processInfo.environment
  environment["PATH"] = "\(binURL.path):\(environment["PATH", default: ""])"
  environment["INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"] = resultsURL.path
  for (key, value) in extraEnvironment {
    environment[key] = value
  }
  process.environment = environment
  try process.run()
  process.waitUntilExit()
  outputPipe.fileHandleForReading.readabilityHandler = nil
  errorPipe.fileHandleForReading.readabilityHandler = nil
  outputCapture.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
  errorCapture.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
  let output = String(
    decoding: outputCapture.data(),
    as: UTF8.self
  )
  let error = String(
    decoding: errorCapture.data(),
    as: UTF8.self
  )
  return (process.terminationStatus, output, error)
}

// Protected by an NSLock because FileHandle readability handlers run concurrently.
private final class ValidationPipeCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = Data()

  func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    storage.append(data)
    lock.unlock()
  }

  func data() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

private func writeExecutable(_ contents: String, to url: URL) throws {
  try contents.write(to: url, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],
    ofItemAtPath: url.path
  )
}

private func readJSONLines(_ url: URL) throws -> [[String: Any]] {
  try parseJSONLines(String(contentsOf: url, encoding: .utf8))
}

private func parseJSONLines(_ output: String) throws -> [[String: Any]] {
  try output
    .split(separator: "\n")
    .map { line in
      let data = Data(line.utf8)
      let object = try JSONSerialization.jsonObject(with: data)
      guard let row = object as? [String: Any] else {
        throw ValidationScriptTestError.invalidJSONLine(String(line))
      }
      return row
    }
}

private enum ValidationScriptTestError: Error {
  case invalidJSONLine(String)
}

private final class ValidationIDGenerator: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: [String]

  init(_ ids: [String]) {
    self.ids = ids
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    return ids.isEmpty ? UUID().uuidString.lowercased() : ids.removeFirst()
  }
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
