import CustomDump
import Foundation
import Testing

extension InstantStoreTests {
  @Test
  func validationHarnessRecordsSwiftSchemaFixtureArtifacts() throws {
    let harness = try String(
      contentsOf: packageRootURL()
        .appendingPathComponent("validation/run-e2e.sh"),
      encoding: .utf8
    )

    let requiredArtifacts = [
      "swift-schema-generate.json",
      "swift-perms-generate.json",
      "swift-schema-verify.json",
      "swift-perms-verify.json",
      "swift-generated-schema-verify.json",
      "swift-generated-perms-verify.json",
      "generated.instant.schema.ts",
      "generated.instant.perms.ts",
    ]
    let requiredEvents = [
      "swift-schema-fixtures-start",
      "swift-schema-generate-complete",
      "swift-perms-generate-complete",
      "swift-schema-verify-complete",
      "swift-perms-verify-complete",
      "swift-generated-schema-verify-complete",
      "swift-generated-perms-verify-complete",
      "swift-schema-fixtures-complete",
    ]
    let requiredCommands = [
      "swift run instant-swift-data schema generate",
      "swift run instant-swift-data perms generate",
      "swift run instant-swift-data schema verify",
      "swift run instant-swift-data perms verify",
      "--example validation",
      "--from validation/fixtures/instant.schema.ts",
      "--from validation/fixtures/instant.perms.ts",
    ]

    expectNoDifference(requiredArtifacts.filter { !harness.contains($0) }, [])
    expectNoDifference(requiredEvents.filter { !harness.contains($0) }, [])
    expectNoDifference(requiredCommands.filter { !harness.contains($0) }, [])
  }

  @Test
  func validationHarnessNormalizesRelativeResultsDirectory() throws {
    let harness = try String(
      contentsOf: packageRootURL()
        .appendingPathComponent("validation/run-e2e.sh"),
      encoding: .utf8
    )

    let requiredLines = [
      #"if [[ "${RESULTS_DIR}" != /* ]]; then"#,
      #"  RESULTS_DIR="${PWD}/${RESULTS_DIR}""#,
    ]

    expectNoDifference(requiredLines.filter { !harness.contains($0) }, [])
    #expect(
      harness.range(of: #"RESULTS_DIR="${INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"#)!
        .upperBound
        <= harness.range(of: #"if [[ "${RESULTS_DIR}" != /* ]]; then"#)!.lowerBound
    )
    #expect(
      harness.range(of: #"fi"#, range: harness.range(of: #"if [[ "${RESULTS_DIR}" != /* ]]; then"#)!.lowerBound..<harness.endIndex)!
        .upperBound
        <= harness.range(of: #"mkdir -p "${RESULTS_DIR}""#)!.lowerBound
    )
  }
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
