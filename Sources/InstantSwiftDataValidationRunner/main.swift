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
      emit(
        caseID: requestedCaseID(),
        event: "failed",
        ok: false,
        appID: "local-validation",
        details: ["message": String(describing: error)]
      )
      exit(1)
    }
  }

  private static func requestedCaseID() -> String {
    switch Array(CommandLine.arguments.dropFirst()) {
    case ["--local-integrations"]:
      "validation.local.integrations"
    case [], ["--local-todos"]:
      "validation.local.todos"
    default:
      "validation.arguments"
    }
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty || arguments == ["--local-todos"] || arguments == ["--local-integrations"]
    else {
      throw ValidationFailure(
        caseID: "validation.arguments",
        appID: "local-validation",
        message: "Usage: instant-swift-data-validation-runner [--local-todos|--local-integrations]"
      )
    }

    if arguments == ["--local-integrations"] {
      let result = try await InstantSwiftDataLocalIntegrationValidation.run()
      for row in result.evidence {
        try writeJSONLine(row)
      }
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
