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
  func validationRunE2EScriptOrchestratesLocalIntegrationEvidence() throws {
    let packageURL = packageRootURL()
    let scriptURL = packageURL.appendingPathComponent("validation/run-e2e.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"))
    #expect(script.contains("INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-todos"))
    #expect(script.contains("swift run instant-swift-data-validation-runner --local-integrations"))
    #expect(script.contains("swift run instant-swift-data-benchmarks"))
    #expect(script.contains("swift-local-integrations.jsonl"))
    #expect(script.contains("swift-benchmark.jsonl"))
    #expect(script.contains("node validation/ts-runner/src/main.ts --fixtures"))
    #expect(script.contains("rm -f"))
    #expect(script.contains(": > \"${RESULTS_DIR}/orchestrator.jsonl\""))
    #expect(script.contains("\"failed\":\"missing-required-file\""))
    #expect(script.contains("\"failed\":\"missing-swift\""))
    #expect(!script.contains("${3:-{}}"))

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
      case "$2:$3" in
        instant-swift-data-validation-runner:--local-todos)
          if [ "${SWIFT_STUB_FAIL_LOCAL_TODOS:-}" = "1" ]; then
            exit 42
          fi
          echo '{"case":"validation.local.todos","side":"swift","event":"stub-todos","appID":"local-validation","timestampMs":1,"ok":true,"details":{}}'
          ;;
        instant-swift-data-validation-runner:--local-integrations)
          echo '{"case":"validation.local.integrations","side":"swift","event":"stub-integrations","appID":"local-validation","timestampMs":2,"ok":true,"details":{}}'
          ;;
        instant-swift-data-benchmarks:--suite)
          expected="run instant-swift-data-benchmarks --suite local-todos --iterations ${INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS:-1} --app-id local-validation --jsonl"
          if [ "$*" != "$expected" ]; then
            echo "unexpected benchmark arguments: $*" >&2
            exit 65
          fi
          if [ "${SWIFT_STUB_FAIL_BENCHMARK:-}" = "1" ]; then
            exit 43
          fi
          echo '{"case":"benchmark.local.todos","side":"swift","event":"summary","appID":"local-validation","timestampMs":3,"ok":true,"details":{"suite":"local-todos","iterations":7}}'
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
      echo '{"case":"validation.typescript.fixtures","side":"typescript","event":"fixtures","appID":"local-validation","timestampMs":3,"ok":true,"details":{}}'
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
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
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
        atPath: resultsURL.appendingPathComponent("swift-benchmark.jsonl").path
      )
    )
    #expect(
      FileManager.default.fileExists(
        atPath: resultsURL.appendingPathComponent("typescript-fixtures.jsonl").path
      )
    )

    try "stale integrations\n".write(
      to: resultsURL.appendingPathComponent("swift-local-integrations.jsonl"),
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
      "swift-local-start",
      "swift-local-complete",
      "swift-local-integrations-start",
      "swift-local-integrations-complete",
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
  try String(contentsOf: url, encoding: .utf8)
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
