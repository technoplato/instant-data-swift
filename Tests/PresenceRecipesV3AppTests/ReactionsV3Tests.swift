import CustomDump
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical implementation source:
// upstream/instant/client/www/lib/recipes/reactions.tsx
//
// Swift keeps the source room, topic, payload keys, four reaction names, local
// immediate animation, and invalid-name filtering. The DOM animation itself is
// adapted to native SwiftUI rendering.
@Suite
@MainActor
struct ReactionsV3Tests {
  #if canImport(SwiftUI)
    @Test
    func desiredRoomTopicSyntaxCompiles() {
      let screen: any View = ReactionsV3Screen(roomID: "123")
      _ = screen

      expectNoDifference(ReactionsV3Room.roomType, "topics-example")
      expectNoDifference(ReactionsV3Room.Topic.emoji.rawValue, "emoji")
    }
  #endif

  @Test
  func payloadMatchesTheCanonicalSourceExactly() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(
        decoding: try encoder.encode(
          ReactionsV3Payload(
            name: "wave",
            directionAngle: 90,
            rotationAngle: 180
          )
        ),
        as: UTF8.self
      ),
      #"{"directionAngle":90,"name":"wave","rotationAngle":180}"#
    )
  }

  @Test
  func sourcePortUsesExactlyFourNamesAndSymbols() {
    expectNoDifference(
      ReactionsV3Name.allCases,
      [.fire, .wave, .confetti, .heart]
    )
    expectNoDifference(
      ReactionsV3Name.allCases.map(\.symbol),
      ["🔥", "👋", "🎉", "❤️"]
    )
  }

  @Test
  func sourcePortAnimatesLocallyThenPublishesTheSamePayload() throws {
    let model = ReactionsV3Model()

    let payload = model.reactionButtonTapped(
      .heart,
      directionAngle: 45,
      rotationAngle: 270
    )

    expectNoDifference(
      payload,
      ReactionsV3Payload(
        name: "heart",
        directionAngle: 45,
        rotationAngle: 270
      )
    )
    expectNoDifference(
      model.animations.map(\.payload),
      [payload]
    )
  }

  @Test
  func locallyAnimatedReactionIsNotAnimatedAgainByItsTopicEcho() {
    let model = ReactionsV3Model()
    let payload = model.reactionButtonTapped(
      .heart,
      directionAngle: 45,
      rotationAngle: 270
    )

    model.observe([payload])

    expectNoDifference(model.animations.map(\.payload), [payload])
  }

  @Test
  func sourcePortAnimatesEachObservedValidPayloadOnceAndIgnoresUnknownNames() {
    let model = ReactionsV3Model()
    let fire = ReactionsV3Payload(name: "fire", directionAngle: 10, rotationAngle: 20)
    let unknown = ReactionsV3Payload(name: "sparkle", directionAngle: 30, rotationAngle: 40)
    let wave = ReactionsV3Payload(name: "wave", directionAngle: 50, rotationAngle: 60)

    model.observe([fire, unknown])
    model.observe([fire, unknown, wave])
    model.observe([fire, unknown, wave])

    expectNoDifference(
      model.animations.map(\.payload),
      [fire, wave]
    )
  }
}
