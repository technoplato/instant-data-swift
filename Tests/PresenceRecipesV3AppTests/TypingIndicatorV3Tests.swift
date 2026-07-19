import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import PresenceRecipesV3App
import Testing

// Canonical implementation source:
// upstream/instant/client/packages/vue/src/InstantVueRoom.ts::useTypingIndicator
// Canonical source test:
// upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts
// ::rooms.useTypingIndicator inputProps uses lowercase listener keys
//
// Swift adapts DOM listener-key casing into native key/submit/blur actions while
// preserving the source implementation's presence, timeout, write-only, and
// cleanup behavior exactly.
@Suite
@MainActor
struct TypingIndicatorV3Tests {
  @Test
  func sourcePortFiltersOnlyActivePeersAndHonorsWriteOnly() {
    let peers = [
      TypingIndicatorPresence(id: "peer-1", displayName: "Blob", chatInput: true),
      TypingIndicatorPresence(id: "peer-2", displayName: "Blob Jr", chatInput: false),
      TypingIndicatorPresence(id: "peer-3", displayName: "Blob Sr", chatInput: nil),
    ]

    var model = TypingIndicatorV3Model(
      profileID: "self",
      displayName: "Current user"
    )
    model.updatePeers(peers)
    expectNoDifference(model.activePeers, [peers[0]])

    model = TypingIndicatorV3Model(
      profileID: "self",
      displayName: "Current user",
      options: TypingIndicatorV3Options(writeOnly: true)
    )
    model.updatePeers(peers)
    expectNoDifference(model.activePeers, [])
  }

  @Test
  func sourcePortPublishesTrueThenNullForSubmitBlurAndCleanup() {
    let model = TypingIndicatorV3Model(
      profileID: "self",
      displayName: "Current user",
      options: TypingIndicatorV3Options(timeout: nil, stopOnSubmit: true)
    )

    model.keyDown(.character)
    expectNoDifference(model.presence.chatInput, true)

    model.keyDown(.submit)
    expectNoDifference(model.presence.chatInput, nil)

    model.keyDown(.character)
    model.blur()
    expectNoDifference(model.presence.chatInput, nil)

    model.keyDown(.character)
    model.stop()
    expectNoDifference(model.presence.chatInput, nil)
  }

  @Test(
    .dependencies {
      $0.continuousClock = TestClock()
    }
  )
  func sourcePortDefaultsToOneSecondAndResetsTheTimeout() async {
    @Dependency(\.continuousClock, as: TestClock<Duration>.self) var clock
    let model = TypingIndicatorV3Model(
      profileID: "self",
      displayName: "Current user"
    )

    model.keyDown(.character)
    await Task.yield()
    await clock.advance(by: .milliseconds(750))
    model.keyDown(.character)
    await Task.yield()
    await clock.advance(by: .milliseconds(999))
    expectNoDifference(model.presence.chatInput, true)

    await clock.advance(by: .milliseconds(1))
    await Task.yield()
    expectNoDifference(model.presence.chatInput, nil)
  }

  @Test(
    .dependencies {
      $0.continuousClock = TestClock()
    }
  )
  func sourcePortZeroTimeoutDisablesAutomaticClear() async {
    @Dependency(\.continuousClock, as: TestClock<Duration>.self) var clock
    let model = TypingIndicatorV3Model(
      profileID: "self",
      displayName: "Current user",
      options: TypingIndicatorV3Options(timeout: .zero)
    )

    model.keyDown(.character)
    await clock.advance(by: .seconds(10))
    expectNoDifference(model.presence.chatInput, true)
  }

  @Test
  func sourcePortEncodesTheCanonicalHyphenatedPresenceKeyAndNullClear() throws {
    let presence = TypingIndicatorPresence(
      id: "peer-1",
      displayName: "Blob",
      chatInput: nil
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(presence))
        as? [String: Any]
    )

    expectNoDifference(object["id"] as? String, "peer-1")
    expectNoDifference(object["displayName"] as? String, "Blob")
    #expect(object["chat-input"] is NSNull)
  }
}
