import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// Upstream `Reactor.updateUser` (`Reactor.js` 2240-2274), which `changeCurrentUser` runs whenever a
/// sign-in changes the user, fails every pending mutation with `user-changed` ("User changed while
/// transaction was in progress.") and drops it. This runtime keeps its durable outbox across auth
/// changes instead: `PendingMutation` records no user, and delivery resumes on the next connection
/// with whatever session is current.
///
/// Scribe depends on that for a guest who signs in to an account that already exists: the guest's
/// recordings must still reach the server, where rules that admit a linked guest's rows accept them
/// and the account then adopts them (Scribe ADR 0005 and ADR 0014 section 9; Instant's guest-auth
/// docs, "Handling conflicting users"). Rules that require direct ownership reject such a write
/// instead: on 2026-09-28 a guest create queued offline was denied after linking (#113 audit). This
/// suite pins the divergence so a future parity port of `updateUser` has to face that consequence
/// explicitly.
@Suite(.serialized)
struct InstantGuestPromotionOutboxTests {
  @Test("a guest's pending write survives a link into an existing account and is sent afterwards")
  func guestWriteIsDeliveredAfterLinkingIntoExistingAccount() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-guest-promotion-outbox-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "after-guest-promotion")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-outbox",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        guestAuthenticator: InstantGuestAuthenticator { _ in
          InstantGuestAuthVerification(userID: "guest-user", refreshToken: "guest-refresh-token")
        },
        oauthExchange: InstantOAuthExchange { _ in
          InstantOAuthVerification(
            userID: "existing-primary-user",
            refreshToken: "primary-refresh-token",
            email: "existing@example.com",
            type: .user,
            guestPromotionLinkEvidence: .instantServerAcceptedGuestToken
          )
        },
        liveTransport: liveSession.transport
      )
    )

    _ = try await runtime.signInAsGuest()
    let write = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-guest-write",
        operations: TodoExample.createOperations(
          id: "todo-guest-write",
          text: "Written while signed in as a guest",
          createdAt: createdAt,
          transactionID: "tx-guest-write"
        )
      ),
      createdAt: createdAt
    )
    let pendingAsGuest = await runtime.pendingMutations()
    expectNoDifference(pendingAsGuest.map(\.id), [write.transactionID])

    let promotion = try await runtime.promoteGuestWithOAuth(code: "authorization-code")
    expectNoDifference(promotion.guestUserID, "guest-user")
    expectNoDifference(promotion.session.userID, "existing-primary-user")
    expectNoDifference(promotion.disposition, .linkedToExistingUser)

    // Upstream would have failed and dropped the write here; it is still queued for delivery.
    let pending = await runtime.pendingMutations()
    let failed = await runtime.failedMutations()
    let deliverable = await runtime.outboxTransportMutations()
    expectNoDifference(pending.map(\.id), [write.transactionID])
    expectNoDifference(failed.map(\.id), [])
    expectNoDifference(deliverable.map(\.mutationID), [write.transactionID])

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the guest write to be sent under the promoted session",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = await liveSession.sentMessages()
    expectNoDifference(sent.map(\.op), ["init", "transact"])
    expectNoDifference(sent.first?.fields["refresh-token"], .string("primary-refresh-token"))
    expectNoDifference(sent.last?.clientEventID, write.transactionID)
    _ = try await runtime.closeConnection()
  }
}
