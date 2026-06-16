import Foundation
import InstantSwiftDataCLIParsing
import InstantSwiftDataCore
import InstantSwiftDataTesting

@main
struct InstantSwiftDataValidationRunner {
  static func main() async {
    do {
      try await run()
    } catch let error as ValidationFailure {
      emit(
        caseID: error.caseID,
        event: "failed",
        ok: false,
        appID: error.appID,
        details: ["message": error.message]
      )
      exit(1)
    } catch let error as CLIValidationRunnerArgumentError {
      emit(
        caseID: "validation.arguments",
        event: "failed",
        ok: false,
        appID: CLIValidationRunnerInvocation.localTodos.appID,
        details: ["message": error.description]
      )
      exit(1)
    } catch {
      let caseID = requestedCaseID()
      emit(
        caseID: caseID,
        event: "failed",
        ok: false,
        appID: requestedAppID(),
        details: ["message": String(describing: error)]
      )
      exit(1)
    }
  }

  private static func requestedCaseID() -> String {
    (try? CLIValidationRunnerArguments.parse(Array(CommandLine.arguments.dropFirst())))?.caseID
      ?? "validation.arguments"
  }

  private static func requestedAppID() -> String {
    (try? CLIValidationRunnerArguments.parse(Array(CommandLine.arguments.dropFirst())))?.appID
      ?? CLIValidationRunnerInvocation.localTodos.appID
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let invocation = try CLIValidationRunnerArguments.parse(arguments)

    if ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE"]
      == invocation.caseID
    {
      throw ForcedValidationRunnerFailure(caseID: invocation.caseID)
    }

    switch invocation {
    case .localIntegrations:
      let result = try await InstantSwiftDataLocalIntegrationValidation.run(
        appID: invocation.appID
      )
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .reminders:
      let result = try await InstantSwiftDataRemindersValidation.run(appID: invocation.appID)
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .serverTransactionLoopback:
      let run = try await InstantSwiftDataTestHarness.runServerTransactionLoopbackValidation(
        appID: invocation.appID
      )
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .cloudKitDemo:
      let run = try await InstantSwiftDataTestHarness.runCloudKitDemoValidation(
        appID: invocation.appID
      )
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .liveSession:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .liveTransaction:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID,
          caseID: invocation.caseID,
          includeTransaction: true
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .liveObserve:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID,
          caseID: invocation.caseID
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .typedDrafts:
      let run = try await InstantSwiftDataTestHarness.runDraftValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .platformAdapters:
      let result = try await InstantSwiftDataPlatformAdapterValidation.run(
        appID: invocation.appID
      )
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .syncUpsRecording:
      let run = try await InstantSwiftDataTestHarness.runSyncUpsRecordingValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .parityReport:
      let run = try InstantSwiftDataTestHarness.runParityCoverageValidation()
      for row in run.result.evidenceRows(appID: run.summary.appID ?? "local-validation") {
        try writeJSONLine(row)
      }

    case .coverage:
      let run = try InstantSwiftDataTestHarness.runParityCoverageValidation()
      let summary = InstantParityCoverageSummary(run.result)
      try writeJSONLine(
        ValidationEvidenceRow(
          caseID: "validation.coverage",
          side: "swift",
          event: "coverage-summary",
          appID: run.summary.appID ?? "local-validation",
          timestampMs: 0,
          ok: summary.ok,
          details: summary
        )
      )

    case .localTodos:
      let run = try await InstantSwiftDataTestHarness.runLocalTodoValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func emit(
    caseID: String,
    event: String,
    ok: Bool,
    appID: String,
    details: [String: String]
  ) {
    let row = ValidationEvidenceRow(
      caseID: caseID,
      side: "swift",
      event: event,
      appID: appID,
      entityID: nil,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
      ok: ok,
      details: details
    )
    try? writeJSONLine(row)
  }

  private static func writeJSONLine<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

private struct ValidationFailure: Error {
  var caseID: String
  var appID: String
  var message: String
}

private struct ForcedValidationRunnerFailure: Error, CustomStringConvertible {
  var caseID: String

  var description: String {
    "Forced validation runner failure for \(caseID)."
  }
}
