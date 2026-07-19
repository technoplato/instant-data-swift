import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantAuthV3AppLiveValidationTests {
  @Test
  func evidenceDecodesTheExactAppOwnedAuthLifecycle() throws {
    let data = Data(
      #"{"userNamespace":"$users","providerIDs":["magic-code","apple","google","github","enterprise-oidc"],"signedInStatus":"signedIn","relaunchedStatus":"signedIn","signedOutStatus":"signedOut","auth":{"userID":"auth-v3-user","serverVerifiedSignIn":true,"durableRelaunch":true,"localSessionCleared":true,"invalidatedTokenRejected":true,"rejectionCode":"authFailed"}}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantAuthV3AppLiveValidationDetails.self,
      from: data
    )

    expectNoDifference(details.userNamespace, "$users")
    expectNoDifference(
      details.providerIDs,
      ["magic-code", "apple", "google", "github", "enterprise-oidc"]
    )
    expectNoDifference(details.signedInStatus, "signedIn")
    expectNoDifference(details.relaunchedStatus, "signedIn")
    expectNoDifference(details.signedOutStatus, "signedOut")
    expectNoDifference(details.auth.userID, "auth-v3-user")
    expectNoDifference(details.auth.serverVerifiedSignIn, true)
    expectNoDifference(details.auth.durableRelaunch, true)
    expectNoDifference(details.auth.localSessionCleared, true)
    expectNoDifference(details.auth.invalidatedTokenRejected, true)
    expectNoDifference(details.auth.rejectionCode, "authFailed")
  }
}
