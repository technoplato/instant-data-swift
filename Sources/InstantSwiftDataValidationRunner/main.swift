import Foundation
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
    } catch {
      let caseID = requestedCaseID()
      emit(
        caseID: caseID,
        event: "failed",
        ok: false,
        appID: requestedAppID(caseID: caseID),
        details: ["message": String(describing: error)]
      )
      exit(1)
    }
  }

  private static func requestedCaseID() -> String {
    switch Array(CommandLine.arguments.dropFirst()) {
    case ["--local-integrations"]:
      "validation.local.integrations"
    case ["--reminders"], ["--local-reminders"]:
      "validation.reminders"
    case ["--typed-drafts"]:
      "validation.typed.drafts"
    case ["--platform-adapters"]:
      "validation.platform.adapters"
    case ["--syncups-recording"]:
      "validation.syncups.recording"
    case ["--parity-report"]:
      "validation.parity.report"
    case ["--coverage"]:
      "validation.coverage"
    case [], ["--local-todos"]:
      "validation.local.todos"
    default:
      "validation.arguments"
    }
  }

  private static func requestedAppID(caseID: String) -> String {
    switch caseID {
    case "validation.typed.drafts":
      "draft-validation"
    case "validation.platform.adapters":
      "platform-adapter-validation"
    case "validation.syncups.recording":
      "syncups-recording-validation"
    default:
      "local-validation"
    }
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty
      || arguments == ["--local-todos"]
      || arguments == ["--local-integrations"]
      || arguments == ["--reminders"]
      || arguments == ["--local-reminders"]
      || arguments == ["--typed-drafts"]
      || arguments == ["--platform-adapters"]
      || arguments == ["--syncups-recording"]
      || arguments == ["--parity-report"]
      || arguments == ["--coverage"]
    else {
      throw ValidationFailure(
        caseID: "validation.arguments",
        appID: "local-validation",
        message:
          "Usage: instant-swift-data-validation-runner [--local-todos|--local-integrations|--reminders|--local-reminders|--typed-drafts|--platform-adapters|--syncups-recording|--parity-report|--coverage]"
      )
    }

    if ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE"]
      == requestedCaseID()
    {
      throw ForcedValidationRunnerFailure(caseID: requestedCaseID())
    }

    if arguments == ["--local-integrations"] {
      let run = try await InstantSwiftDataTestHarness.runLocalIntegrationValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    } else if arguments == ["--reminders"] || arguments == ["--local-reminders"] {
      let run = try await InstantSwiftDataTestHarness.runRemindersValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    } else if arguments == ["--typed-drafts"] {
      let run = try await InstantSwiftDataTestHarness.runDraftValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    } else if arguments == ["--platform-adapters"] {
      let result = try await InstantSwiftDataPlatformAdapterValidation.run(
        appID: requestedAppID(caseID: "validation.platform.adapters")
      )
      for row in result.evidence {
        try writeJSONLine(row)
      }
    } else if arguments == ["--syncups-recording"] {
      let run = try await InstantSwiftDataTestHarness.runSyncUpsRecordingValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    } else if arguments == ["--parity-report"] {
      let run = try InstantSwiftDataTestHarness.runParityCoverageValidation()
      for row in run.result.evidenceRows(appID: run.summary.appID ?? "local-validation") {
        try writeJSONLine(row)
      }
    } else if arguments == ["--coverage"] {
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
    } else {
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
