import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

@Suite("InstantError presentation")
struct InstantErrorPresentationTests {
  @Test
  func localizedDescriptionIncludesOperationMessageAndRecovery() {
    let error = InstantError(
      code: .validationFailed,
      operation: "validate deferred value residency",
      path: "sharedRecordings/timeline",
      message:
        "Deferred local residency names attribute 'sharedRecordings/timeline', but that ID is not in the Instant schema.",
      recovery: "Declare the attribute before enabling deferred local residency."
    )

    let description = error.localizedDescription
    #expect(description.contains("Schema or configuration validation failed"))
    #expect(description.contains("validate deferred value residency"))
    #expect(description.contains("sharedRecordings/timeline"))
    #expect(description.contains("Declare the attribute"))
    #expect(!description.contains("error 1"))
    #expect(error.errorCode == 1)
    #expect(error.failureReason?.contains("validation") == true)
    #expect(error.recoverySuggestion == error.recovery)
  }

  @Test
  func nsErrorBridgePreservesStableCodeAndUserInfo() {
    let error = InstantError(
      code: .persistenceFailed,
      operation: "open local cache",
      message: "SQLite could not open /tmp/instant.sqlite.",
      recovery: "Check that the cache directory is writable."
    )
    let nsError = error as NSError
    expectNoDifference(nsError.domain, InstantError.errorDomain)
    expectNoDifference(nsError.code, InstantError.Code.persistenceFailed.stableErrorCode)
    expectNoDifference(
      nsError.userInfo["InstantErrorCode"] as? String,
      InstantError.Code.persistenceFailed.rawValue
    )
    expectNoDifference(
      nsError.userInfo["InstantErrorOperation"] as? String,
      "open local cache"
    )
    #expect((nsError.localizedDescription).contains("Local Instant cache failed"))
    #expect(!(nsError.localizedDescription).contains("error 1"))
  }

  @Test
  func everyCodeHasUniqueStableErrorCode() {
    let codes = InstantError.Code.allCases.map(\.stableErrorCode)
    expectNoDifference(Set(codes).count, codes.count)
    #expect(codes.min() == 1)
  }
}
