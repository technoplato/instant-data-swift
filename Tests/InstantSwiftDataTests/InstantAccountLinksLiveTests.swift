import CustomDump
import Dependencies
import Foundation
import Testing

@testable import InstantSwiftData

/// Live: a guest links an email identity through a second sign-in, reads the link, and unlinks it, on a throwaway
/// Instant app whose rules include ``InstantAccountLinks/permissionRulesTemplate`` (#361).
///
/// The fake server behind ``InstantSecondSignInTests`` and ``InstantAccountLinksTests`` cannot evaluate Instant's
/// permission rules, so this test sends the same writes to the real server. It runs only when all three are set:
///
/// - `INSTANT_ACCOUNT_LINK_LIVE_APP_ID`: a throwaway app with the `accountLinks` schema and rules. Never production.
/// - `INSTANT_ACCOUNT_LINK_LIVE_EMAIL`: an existing user of that app.
/// - `INSTANT_ACCOUNT_LINK_LIVE_CODE`: a fresh magic code for that email, for example from the admin API's
///   `generateMagicCode`, which sends no email.
///
/// Only the email delivery is replaced: the magic-code exchange's `send` records the pending code locally, as the live
/// `send` does after Instant emails it, because Instant's mail provider refuses test addresses such as `example.com`
/// ("HTTP 500 email-send-failed"). The verify exchange, the invite and join writes, the reads, the unlink, and the
/// token revocation all run against the real server. The guest it signs in stays on the app; the test prints its id so
/// the caller can delete it.
@Suite(.serialized)
struct InstantAccountLinksLiveTests {
  @Test
  func aGuestLinksAnEmailIdentityThroughASecondSignInAndUnlinksIt() async throws {
    guard let live = LiveAccountLinkEnvironment() else { return }
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-account-link-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }

    try await withDependencies {
      $0.instantLiveTransport = .live
      $0.instantGuestAuthenticator = .live
      $0.instantRefreshTokenVerifier = .live
      $0.instantAuthTokenInvalidator = .live
      $0.instantMagicCodeExchange = InstantMagicCodeExchange(
        send: { request in
          InstantMagicCodeChallenge(
            appID: request.appID,
            email: request.email,
            code: "",
            createdAt: request.sentAt,
            expiresAt: InstantTimestamp(milliseconds: request.sentAt.milliseconds + 10 * 60 * 1000)
          )
        },
        verify: InstantMagicCodeExchange.live.verify
      )
      try await $0.bootstrapInstantSwiftData(
        appID: live.appID,
        persistenceURL: home.appendingPathComponent("\(live.appID).sqlite"),
        context: .live,
        initialAttributes: []
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var primary
      _ = try await primary.connect()
      let guest = try await primary.signInAsGuest()
      print("InstantAccountLinksLiveTests: guest \(guest.userID)")
      let links = InstantAccountLinks.default
      let second = try await InstantSecondSignIn.open(beside: primary, registering: links.attributes)
      do {
        _ = try await second.sendMagicCode(email: live.email)
        let member = try await second.signInWithMagicCode(email: live.email, code: live.code)
        print("InstantAccountLinksLiveTests: member \(member.userID)")
        #expect(member.userID != guest.userID)
        #expect(try await primary.authSession()?.userID == guest.userID)

        let linked = try await links.link(
          primary: primary,
          second: second,
          secondProvider: .magicCode,
          deviceName: "InstantAccountLinksLiveTests"
        )
        print("InstantAccountLinksLiveTests: link \(linked.id)")
        expectNoDifference(Set(linked.members.map(\.userID)), [guest.userID, member.userID])

        let readByPrimary = try #require(try await links.accountLink(sharingSessionOf: primary))
        expectNoDifference(readByPrimary.id, linked.id)
        expectNoDifference(Set(readByPrimary.members.map(\.userID)), [guest.userID, member.userID])
        let readBySecond = try #require(try await links.accountLink(of: second))
        expectNoDifference(readBySecond.id, linked.id)

        let remaining = try await links.unlink(memberUserID: member.userID, primary: primary)
        #expect(remaining == nil)
        #expect(try await links.accountLink(sharingSessionOf: primary) == nil)
        #expect(try await links.accountLink(of: second) == nil)
      } catch {
        await second.close()
        throw error
      }
      await second.close()
      #expect(try await primary.authSession()?.userID == guest.userID)
    }
  }
}

/// The live test's inputs, or `nil` (the test returns early) when any is missing or the app is production.
private struct LiveAccountLinkEnvironment {
  static let productionAppIDs: Set<String> = ["e7c49961-d702-46a1-82c1-fca9a61f6a4d"]

  var appID: String
  var email: String
  var code: String

  init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
    func value(_ name: String) -> String? {
      environment[name].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    guard
      let appID = value("INSTANT_ACCOUNT_LINK_LIVE_APP_ID"),
      let email = value("INSTANT_ACCOUNT_LINK_LIVE_EMAIL"),
      let code = value("INSTANT_ACCOUNT_LINK_LIVE_CODE"),
      !Self.productionAppIDs.contains(appID.lowercased())
    else { return nil }
    self.appID = appID
    self.email = email
    self.code = code
  }
}
