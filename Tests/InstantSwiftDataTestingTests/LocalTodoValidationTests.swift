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
    expectNoDifference(run.summary.rowCount, 9)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(
      run.summary.events,
      [
        "seed",
        "search-tags",
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
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 9))
    expectNoDifference(
      result.evidence.map(\.caseID),
      Array(repeating: "validation.reminders", count: result.evidence.count)
    )

    let seed = result.evidence[0].details
    expectNoDifference(seed.listTitles, ["Family"])
    expectNoDifference(seed.reminderTitles, ["Pack lunch", "Read book"])
    expectNoDifference(seed.flaggedReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(seed.tagTitles, ["family"])

    let search = result.evidence[1].details
    expectNoDifference(search.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(search.reminderTagIDs, ["validation-reminders-pack-lunch#family"])

    let richFilters = result.evidence[2].details
    expectNoDifference(richFilters.scheduledReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(richFilters.todayReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(richFilters.priorityReminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(
      richFilters.stats,
      RemindersStats(allCount: 2, completedCount: 0, flaggedCount: 1, scheduledCount: 1, todayCount: 1)
    )

    let formEdit = result.evidence[3].details
    expectNoDifference(formEdit.reminderIDs, ["validation-reminders-pack-lunch"])
    expectNoDifference(formEdit.reminderTitles, ["Pack lunch and snacks"])
    expectNoDifference(formEdit.reminderNotes, ["Updated through validation"])
    expectNoDifference(formEdit.reminderTagIDs, ["validation-reminders-pack-lunch#family"])

    let readerRejection = result.evidence[5].details
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

    let writerUpdate = result.evidence[6].details
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
    expectNoDifference(rows.count, 9)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set([
      "validation.reminders"
    ]))
    expectNoDifference(Set(rows.map { $0["appID"] as? String ?? "" }), Set(["local-validation"]))
    expectNoDifference(
      rows.map { $0["event"] as? String ?? "" },
      [
        "seed",
        "search-tags",
        "rich-filters",
        "edit-rich-fields",
        "complete",
        "reader-rejection",
        "writer-update",
        "demoted-reader-rejection",
        "relaunch",
      ]
    )
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 9))

    let search = try #require(rows.first { $0["event"] as? String == "search-tags" })
    let searchDetails = try #require(search["details"] as? [String: Any])
    expectNoDifference(searchDetails["reminderIDs"] as? [String], ["validation-reminders-pack-lunch"])
    expectNoDifference(searchDetails["tagTitles"] as? [String], ["family"])

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
    expectNoDifference(rows.count, 9)
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
    expectNoDifference(run.result.recordCount, 223)
    expectNoDifference(run.result.exactCount, 28)
    expectNoDifference(run.result.adaptedCount, 190)
    expectNoDifference(run.result.blockedCount, 4)
    expectNoDifference(run.result.notApplicableCount, 1)
    expectNoDifference(run.summary.caseID, "validation.parity.report")
    expectNoDifference(run.summary.appID, "validation-parity-test")
    expectNoDifference(run.summary.rowCount, run.result.recordCount)
    expectNoDifference(run.summary.ok, false)
    expectNoDifference(
      run.summary.events,
      Array(repeating: "parity-record", count: run.result.recordCount)
    )
    expectNoDifference(run.summary.failedEvents, Array(repeating: "parity-record", count: 4))
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
      ("instant.persisted-object.indexeddb-connection-recovery", InstantParityCoverageStatus.blocked),
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
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, InfiniteQuery, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares."
    )
    #expect(
      run.result.records.contains {
        $0.id == "instant.live-transport.swift-to-typescript" && $0.status == .blocked
      }
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
    expectNoDifference(rows.count, 223)
    expectNoDifference(Set(rows.map { $0["case"] as? String ?? "" }), Set([
      "validation.parity.report"
    ]))
    expectNoDifference(Set(rows.map { $0["appID"] as? String ?? "" }), Set(["local-validation"]))
    expectNoDifference(Set(rows.map { $0["event"] as? String ?? "" }), Set(["parity-record"]))
    expectNoDifference(rows.filter { ($0["ok"] as? Bool) == false }.count, 5)
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
      "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, InfiniteQuery, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares."
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
    expectNoDifference((details["recordCount"] as? NSNumber)?.intValue, 223)
    expectNoDifference((details["exactCount"] as? NSNumber)?.intValue, 28)
    expectNoDifference((details["adaptedCount"] as? NSNumber)?.intValue, 190)
    expectNoDifference((details["blockedCount"] as? NSNumber)?.intValue, 4)
    expectNoDifference((details["notApplicableCount"] as? NSNumber)?.intValue, 1)
    expectNoDifference((details["swiftFileCount"] as? NSNumber)?.intValue, 22)
    expectNoDifference(
      details["blockedIDs"] as? [String],
      [
        "instant.persisted-object.indexeddb-connection-recovery",
        "instant.live-transport.swift-to-typescript",
        "instant.live-transport.typescript-to-swift",
        "sqlite.cloudkit-demo.remote-share",
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
  func validationRunE2EScriptOrchestratesLocalIntegrationEvidence() throws {
    let packageURL = packageRootURL()
    let scriptURL = packageURL.appendingPathComponent("validation/run-e2e.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"))
    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-todos"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-integrations"))
    #expect(script.contains("swift run instant-swift-data validation reminders --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation typed-drafts --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation platform-adapters --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation syncups-recording --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation parity-report --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation coverage --jsonl"))
    #expect(script.contains("swift run instant-swift-data-benchmarks"))
    #expect(script.contains("swift-local-integrations.jsonl"))
    #expect(script.contains("swift-reminders.jsonl"))
    #expect(script.contains("swift-typed-drafts.jsonl"))
    #expect(script.contains("swift-platform-adapters.jsonl"))
    #expect(script.contains("swift-syncups-recording.jsonl"))
    #expect(script.contains("swift-parity-report.jsonl"))
    #expect(script.contains("swift-coverage.jsonl"))
    #expect(script.contains("swift-benchmark.jsonl"))
    #expect(script.contains("INSTANT_SWIFT_DATA_NODE"))
    #expect(script.contains("validation/ts-runner/src/main.ts --fixtures"))
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
    #expect(runnerSource.contains("InstantSwiftDataPlatformAdapterValidation.run"))
    #expect(runnerSource.contains("runRemindersValidation()"))
    #expect(runnerSource.contains("runSyncUpsRecordingValidation()"))
    #expect(runnerSource.contains("runParityCoverageValidation()"))
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
          echo '{"case":"validation.local.integrations","side":"swift","event":"stub-integrations","appID":"local-validation","timestampMs":2,"ok":true,"details":{}}'
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
          echo '{"case":"validation.coverage","side":"swift","event":"stub-coverage","appID":"local-validation","timestampMs":6,"ok":true,"details":{}}'
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
      echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures","appID":"local-validation","timestampMs":8,"ok":true,"details":{}}'
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
        "INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS": benchmarkIterations
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
      "typescript-fixtures-start",
      "typescript-fixtures-complete",
      "typescript-boundary-pending",
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
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )

    let overrideNodeURL = tempURL.appendingPathComponent("override-node")
    try writeExecutable(
      """
      #!/bin/sh
      if [ "$1" != "validation/ts-runner/src/main.ts" ]; then
        echo "unexpected node script: $1" >&2
        exit 67
      fi
      echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures-override","appID":"local-validation","timestampMs":9,"ok":true,"details":{}}'
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
      echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures-bundled","appID":"local-validation","timestampMs":10,"ok":true,"details":{}}'
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

    try "stale integrations\n".write(
      to: resultsURL.appendingPathComponent("swift-local-integrations.jsonl"),
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
    try "stale typescript\n".write(
      to: resultsURL.appendingPathComponent("typescript-fixtures.jsonl"),
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
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
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
