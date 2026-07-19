import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

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
  #if canImport(SwiftUI)
    @Test
    func desiredRoomPresenceSyntaxCompiles() {
      let screen: any View = TypingIndicatorV3Screen(
        roomID: "typing-room",
        profileID: "current-user"
      )
      _ = screen

      expectNoDifference(TypingIndicatorV3Room.roomType, "typing-indicator-example")
    }
  #endif

  @Test
  func sourcePortFiltersOnlyActivePeersAndHonorsWriteOnly() {
    let peers = [
      TypingIndicatorPresence(id: "peer-1", chatInput: true),
      TypingIndicatorPresence(id: "peer-2", chatInput: false),
      TypingIndicatorPresence(id: "peer-3", chatInput: nil),
    ]

    var model = TypingIndicatorV3Model(profileID: "self")
    model.updatePeers(peers)
    expectNoDifference(model.activePeers, [peers[0]])

    model = TypingIndicatorV3Model(
      profileID: "self",
      options: TypingIndicatorV3Options(writeOnly: true)
    )
    model.updatePeers(peers)
    expectNoDifference(model.activePeers, [])
  }

  @Test
  func sourcePortPublishesTrueFalseAndNullAtTheCanonicalTransitions() {
    let model = TypingIndicatorV3Model(
      profileID: "self",
      options: TypingIndicatorV3Options(timeout: nil, stopOnSubmit: true)
    )

    model.keyDown(.character)
    expectNoDifference(model.presence.chatInput, true)

    model.keyDown(.submit)
    expectNoDifference(model.presence.chatInput, false)

    model.keyDown(.character)
    model.blur()
    expectNoDifference(model.presence.chatInput, false)

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
    let model = TypingIndicatorV3Model(profileID: "self")

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
      options: TypingIndicatorV3Options(timeout: .zero)
    )

    model.keyDown(.character)
    await clock.advance(by: .seconds(10))
    expectNoDifference(model.presence.chatInput, true)
  }

  @Test
  func sourcePortEncodesInitialAbsenceAndCanonicalHyphenatedNullClear() throws {
    let initialObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(TypingIndicatorPresence(id: "peer-1"))
      ) as? [String: Any]
    )
    expectNoDifference(Set(initialObject.keys), ["id"])
    expectNoDifference(initialObject["id"] as? String, "peer-1")

    let clearedObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
          TypingIndicatorPresence(id: "peer-1", chatInput: nil)
        )
      )
        as? [String: Any]
    )

    expectNoDifference(Set(clearedObject.keys), ["chat-input", "id"])
    expectNoDifference(clearedObject["id"] as? String, "peer-1")
    #expect(clearedObject["chat-input"] is NSNull)
  }
}
