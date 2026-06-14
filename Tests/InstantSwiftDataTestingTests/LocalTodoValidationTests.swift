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
    expectNoDifference(run.summary.rowCount, 10)
    expectNoDifference(run.summary.ok, true)
    expectNoDifference(run.summary.events, platformAdapterValidationEvents)
    expectNoDifference(result.evidence.map(\.event), run.summary.events)
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 10))
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
      count: 10
    ))
    expectNoDifference(rows.map { $0["appID"] as? String ?? "" }, Array(
      repeating: "platform-adapter-validation",
      count: 10
    ))
    expectNoDifference(rows.map { $0["event"] as? String ?? "" }, platformAdapterValidationEvents)
    expectNoDifference(rows.map { $0["ok"] as? Bool ?? false }, Array(repeating: true, count: 10))

    let adapters = try rows.map { row in
      try #require((row["details"] as? [String: Any])?["adapter"] as? String)
    }
    expectNoDifference(adapters, platformAdapterValidationAdapters)

    let shares = try #require(rows.last?["details"] as? [String: Any])
    expectNoDifference((shares["shareIDs"] as? [String])?.count, 1)
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
  func validationRunE2EScriptOrchestratesLocalIntegrationEvidence() throws {
    let packageURL = packageRootURL()
    let scriptURL = packageURL.appendingPathComponent("validation/run-e2e.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"))
    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-todos"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-integrations"))
    #expect(script.contains("swift run instant-swift-data validation typed-drafts --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation platform-adapters --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation syncups-recording --jsonl"))
    #expect(script.contains("swift run instant-swift-data validation parity-report --jsonl"))
    #expect(script.contains("swift run instant-swift-data-benchmarks"))
    #expect(script.contains("swift-local-integrations.jsonl"))
    #expect(script.contains("swift-typed-drafts.jsonl"))
    #expect(script.contains("swift-platform-adapters.jsonl"))
    #expect(script.contains("swift-syncups-recording.jsonl"))
    #expect(script.contains("swift-parity-report.jsonl"))
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
    #expect(runnerSource.contains("--typed-drafts"))
    #expect(runnerSource.contains("runDraftValidation()"))
    #expect(runnerSource.contains("--platform-adapters"))
    #expect(runnerSource.contains("runPlatformAdapterValidation()"))
    #expect(runnerSource.contains("--syncups-recording"))
    #expect(runnerSource.contains("runSyncUpsRecordingValidation()"))

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
        instant-swift-data-validation-runner:--local-todos:)
          if [ "${SWIFT_STUB_FAIL_LOCAL_TODOS:-}" = "1" ]; then
            exit 42
          fi
          echo '{"case":"validation.local.todos","side":"swift","event":"stub-todos","appID":"local-validation","timestampMs":1,"ok":true,"details":{}}'
          ;;
        instant-swift-data-validation-runner:--local-integrations:)
          echo '{"case":"validation.local.integrations","side":"swift","event":"stub-integrations","appID":"local-validation","timestampMs":2,"ok":true,"details":{}}'
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
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
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
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
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
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
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
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
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
      "swift-macro-tests-start",
      "swift-macro-tests-complete",
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
      "swift-typed-drafts-start",
      "swift-typed-drafts-complete",
      "swift-platform-adapters-start",
      "swift-platform-adapters-complete",
      "swift-syncups-recording-start",
      "swift-syncups-recording-complete",
      "swift-parity-report-start",
      "swift-parity-report-complete",
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
  try process.run()
  process.waitUntilExit()

  let output = String(
    decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
    as: UTF8.self
  )
  let error = String(
    decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
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
  var environment = ProcessInfo.processInfo.environment
  environment["PATH"] = "\(binURL.path):\(environment["PATH", default: ""])"
  environment["INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"] = resultsURL.path
  for (key, value) in extraEnvironment {
    environment[key] = value
  }
  process.environment = environment
  try process.run()
  process.waitUntilExit()
  let output = String(
    decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
    as: UTF8.self
  )
  let error = String(
    decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
    as: UTF8.self
  )
  return (process.terminationStatus, output, error)
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
