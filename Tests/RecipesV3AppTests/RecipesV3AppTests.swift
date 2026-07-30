import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@testable import RecipesV3App

@Suite
struct RecipesV3AppTests {
  @Test
  func catalogMatchesTheUpstreamRecipeOrder() {
    expectNoDifference(
      InstantRecipeV3.allCases.map(\.rawValue),
      [
        "todos",
        "cursors",
        "custom-cursors",
        "reactions",
        "typing-indicator",
        "avatar-stack",
        "merge-tile-game",
        "auth",
      ]
    )
  }

  @Test @MainActor
  func legacyPublicConfigurationAndCatalogSurfaceStillCompiles() {
    var configuration = RecipesV3AppConfiguration(
      appID: "legacy-recipes",
      enablesLiveSync: false,
      profileID: "legacy-profile"
    )
    configuration.enablesLiveSync = true
    expectNoDifference(configuration.syncRoute, .cloud)

    _ = RecipesV3CatalogScreen(
      profileID: configuration.profileID,
      launchRecipe: .todos,
      isLive: configuration.enablesLiveSync
    )
    let model = RecipesV3BootstrapModel(configuration: configuration)
    let preservedConfiguration: RecipesV3AppConfiguration = model.configuration
    expectNoDifference(preservedConfiguration, configuration)
  }

  @Test
  func environmentConfigurationSelectsCloudAndLaunchesARecipe() throws {
    let configuration = RecipesV3AppConfiguration.environment(
      [
        "INSTANT_APP_ID": "app-123",
        "INSTANT_PERSISTENCE_PATH": "/tmp/instant-recipes.sqlite",
        "INSTANT_RECIPE": "custom-cursors",
        "INSTANT_RECIPE_PROFILE_ID": "profile-123",
      ],
      arguments: ["recipes-v3"],
      infoDictionary: [:],
      makeProfileID: { "generated" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "app-123",
        persistenceURL: URL(fileURLWithPath: "/tmp/instant-recipes.sqlite"),
        syncRoute: .cloud,
        profileID: "profile-123",
        launchRecipe: .customCursors
      )
    )
  }

  @Test
  func localConfigurationIgnoresUnexpandedBuildSettings() throws {
    let configuration = RecipesV3AppConfiguration.environment(
      [:],
      arguments: ["recipes-v3", "--recipe", "merge-tile-game"],
      infoDictionary: ["InstantAppID": "$(INSTANT_APP_ID)"],
      makeProfileID: { "generated-profile" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "recipes-v3-local",
        syncRoute: .localOnly,
        profileID: "generated-profile",
        launchRecipe: .mergeTileGame
      )
    )
  }

  @Test
  func environmentConfigurationForcesDesertHost() throws {
    let configuration = try RecipesV3AppConfiguration.validatedEnvironment(
      [
        "INSTANT_APP_ID": "desert-smoke",
        "INSTANT_SWIFT_DATA_SYNC_ROUTE": "desert-required",
        "INSTANT_DESERT_ROLE": "host",
        "INSTANT_DESERT_HOST": "127.0.0.1",
        "INSTANT_DESERT_PORT": "8787",
      ],
      arguments: ["recipes-v3"],
      infoDictionary: [:],
      makeProfileID: { "host-profile" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "desert-smoke",
        syncRoute: .desertRequired(
          RecipesV3DesertEndpoint(role: .host, host: "127.0.0.1", port: 8787)
        ),
        profileID: "host-profile"
      )
    )
    expectNoDifference(
      configuration.syncRoute.statusTitle,
      "Desert host · 127.0.0.1:8787"
    )
  }

  @Test
  func launchArgumentsForceDesertPeer() throws {
    let configuration = try RecipesV3AppConfiguration.validatedEnvironment(
      [:],
      arguments: [
        "recipes-v3",
        "--instant-app-id", "desert-smoke",
        "--sync-route", "desert-required",
        "--desert-role", "peer",
        "--desert-host", "127.0.0.1",
        "--desert-port", "8787",
        "--recipe", "todos",
      ],
      infoDictionary: [:],
      makeProfileID: { "peer-profile" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "desert-smoke",
        syncRoute: .desertRequired(
          RecipesV3DesertEndpoint(role: .peer, host: "127.0.0.1", port: 8787)
        ),
        profileID: "peer-profile",
        launchRecipe: .todos
      )
    )
    expectNoDifference(
      configuration.syncRoute.statusTitle,
      "Desert peer · 127.0.0.1:8787"
    )
  }

  @Test
  func forcedDesertModeRejectsMissingRole() {
    #expect(throws: RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_ROLE")){
      try RecipesV3AppConfiguration.validatedEnvironment(
        [
          "INSTANT_APP_ID": "desert-smoke",
          "INSTANT_SWIFT_DATA_SYNC_ROUTE": "desert-required",
        ],
        arguments: ["recipes-v3"],
        infoDictionary: [:]
      )
    }
  }

  @Test
  func forcedDesertModeRejectsInvalidPort() {
    #expect(
      throws: RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_DESERT_PORT",
        value: "70000",
        expected: "an integer from 1 through 65535"
      )
    ){
      try RecipesV3AppConfiguration.validatedEnvironment(
        [
          "INSTANT_APP_ID": "desert-smoke",
          "INSTANT_SWIFT_DATA_SYNC_ROUTE": "desert-required",
          "INSTANT_DESERT_ROLE": "peer",
          "INSTANT_DESERT_HOST": "127.0.0.1",
          "INSTANT_DESERT_PORT": "70000",
        ],
        arguments: ["recipes-v3"],
        infoDictionary: [:]
      )
    }
  }

  @Test
  func forcedDesertModeRejectsRecipesOutsideThePrototypeLane() {
    #expect(
      throws: RecipesV3ConfigurationError.unsupportedDesertRecipe("auth")
    ){
      try RecipesV3AppConfiguration.validatedEnvironment(
        [:],
        arguments: [
          "recipes-v3",
          "--instant-app-id", "desert-smoke",
          "--sync-route", "desert-required",
          "--desert-role", "peer",
          "--desert-host", "127.0.0.1",
          "--desert-port", "8787",
          "--recipe", "auth",
        ],
        infoDictionary: [:]
      )
    }
  }

  @Test @MainActor
  func unreachableForcedDesertPeerFailsBeforePublishingAClient() async throws {
    let reservation = try await InstantNetworkDesertHost.start(
      appID: "desert-port-reservation",
      host: "127.0.0.1",
      port: 0
    )
    let unavailablePort = reservation.port
    await reservation.stop()

    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-desert-unreachable-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let model = RecipesV3BootstrapModel(
      configuration: RecipesV3AppConfiguration(
        appID: "desert-unreachable",
        persistenceURL: persistenceURL,
        syncRoute: .desertRequired(
          RecipesV3DesertEndpoint(
            role: .peer,
            host: "127.0.0.1",
            port: unavailablePort
          )
        ),
        profileID: "unreachable-peer",
        launchRecipe: .todos
      ),
      configureDependencies: {
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.uuid = .constant(
          UUID(uuidString: "00000000-0000-0000-0000-000000000046")!
        )
      }
    )

    model.startIfNeeded()
    let deadline = ContinuousClock.now + .seconds(3)
    while model.errorMessage == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.client == nil)
    #expect(model.connectionStatus == nil)
    #expect(model.errorMessage?.contains("Network.framework") == true)
  }

  @Test
  func combinedSchemaContainsEveryDurableRecipeNamespace() {
    expectNoDifference(
      Set(RecipesV3AppConfiguration.initialAttributes.map(\.namespace)),
      Set(["todos", "boards", "$users"])
    )
  }
}
