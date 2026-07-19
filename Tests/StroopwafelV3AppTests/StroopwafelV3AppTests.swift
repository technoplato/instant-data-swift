import CustomDump
import InstantSwiftData
import StroopwafelV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical source:
// jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614
@Suite
struct StroopwafelV3AppTests {
  @Test
  func appConfigurationChoosesLocalOrLiveRuntimeFromEnvironment() {
    expectNoDifference(
      StroopwafelV3AppConfiguration.environment([:]),
      StroopwafelV3AppConfiguration(
        appID: "stroopwafel-v3-local",
        enablesLiveSync: false
      )
    )
    expectNoDifference(
      StroopwafelV3AppConfiguration.environment([
        "INSTANT_APP_ID": "canonical-app",
        "INSTANT_PERSISTENCE_PATH": "/tmp/stroopwafel.sqlite",
      ]),
      StroopwafelV3AppConfiguration(
        appID: "canonical-app",
        persistenceURL: URL(fileURLWithPath: "/tmp/stroopwafel.sqlite"),
        enablesLiveSync: true
      )
    )
    expectNoDifference(StroopwafelV3AuthProviders.all, [])
  }

  #if canImport(SwiftUI)
    @MainActor
    @Test
    func runnableScreenSyntaxCompiles() {
      let screen: any View = StroopwafelV3Screen()
      _ = screen
    }
  #endif

  @Test
  func appModelsPreserveCanonicalNamespacesAttributesAndLinks() {
    expectNoDifference(
      StroopwafelV3Schema.attributes,
      StroopwafelExample.attributes
    )
    expectNoDifference(StroopwafelV3User.instantNamespace, "$users")
    expectNoDifference(StroopwafelV3Room.instantNamespace, "rooms")
    expectNoDifference(StroopwafelV3Game.instantNamespace, "games")
    expectNoDifference(StroopwafelV3Point.instantNamespace, "points")
    expectNoDifference(
      StroopwafelV3Room.users.attributeID,
      "rooms/users"
    )
    expectNoDifference(
      StroopwafelV3Game.points.attributeID,
      "games/points"
    )
  }

  @Test
  func jsonWireValuesPreserveCanonicalShapes() throws {
    let ids = StroopwafelV3StringList(["user-host", "user-guest"])
    let colors = StroopwafelV3ColorSequence([
      .init(color: "red", label: "green"),
      .init(color: "blue", label: "yellow"),
    ])

    expectNoDifference(
      ids.instantValue,
      .json(.array([.string("user-host"), .string("user-guest")]))
    )
    expectNoDifference(
      colors.instantValue,
      .json(
        .array([
          .object(["color": .string("red"), "label": .string("green")]),
          .object(["color": .string("blue"), "label": .string("yellow")]),
        ])
      )
    )
  }

  @Test
  func typedQueriesPreserveCanonicalRoomAndGameIncludes() {
    let roomQuery = StroopwafelV3Room.forCode("AB12").plan
    expectNoDifference(roomQuery.namespace, "rooms")
    expectNoDifference(roomQuery.filters, [
      .equals(field: "code", value: .string("AB12"))
    ])
    expectNoDifference(roomQuery.includes?.map(\.name), ["users"])

    let gameQuery = StroopwafelV3Game.byID(
      InstantID(rawValue: "game-1")
    ).plan
    expectNoDifference(gameQuery.namespace, "games")
    expectNoDifference(gameQuery.filters, [
      .equals(field: "id", value: .string("game-1"))
    ])
    expectNoDifference(gameQuery.includes?.map(\.name), ["users", "rooms", "points"])
    expectNoDifference(
      gameQuery.includes?.first { $0.name == "rooms" }?.query?.includes?.map(\.name),
      ["users"]
    )
  }
}
