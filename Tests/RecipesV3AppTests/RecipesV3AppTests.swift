import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing
import TodosV3App

@testable import RecipesV3App

#if os(macOS)
  import AppKit
  import SwiftUI
#endif

@Suite(.serialized)
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
  func interactiveDemoConfigurationKeepsNormalAndDesertStoresSeparate() throws {
    let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
      [
        "INSTANT_APP_ID": "cloud-app",
        "INSTANT_PERSISTENCE_PATH": "/tmp/instant-recipes.sqlite",
        "INSTANT_RECIPE_PROFILE_ID": "profile-123",
      ],
      arguments: ["recipes-v3", "--recipe", "todos"],
      infoDictionary: [:],
      defaultDesertEndpoint: RecipesV3DesertEndpoint(
        role: .peer,
        host: "127.0.0.1",
        port: 49_800
      ),
      makeProfileID: { "generated-profile" }
    )

    expectNoDifference(configuration.forcedMode, nil)
    expectNoDifference(
      try configuration.appConfiguration(for: .normal),
      RecipesV3AppConfiguration(
        appID: "cloud-app",
        persistenceURL: URL(fileURLWithPath: "/tmp/instant-recipes.sqlite"),
        syncRoute: .cloud,
        profileID: "profile-123",
        launchRecipe: .todos
      )
    )
    expectNoDifference(
      try configuration.appConfiguration(for: .desert),
      RecipesV3AppConfiguration(
        appID: "cloud-app-desert",
        persistenceURL: URL(fileURLWithPath: "/tmp/instant-recipes-desert.sqlite"),
        syncRoute: .desertRequired(
          RecipesV3DesertEndpoint(
            role: .peer,
            host: "127.0.0.1",
            port: 49_800
          )
        ),
        profileID: "profile-123",
        launchRecipe: .todos
      )
    )
  }

  @Test
  func unavailableDesertModeCannotResolveToTheNormalRoute() {
    let configuration = RecipesV3DemoConfiguration(
      normal: RecipesV3AppConfiguration(
        appID: "cloud-app",
        syncRoute: .cloud,
        profileID: "profile-123"
      ),
      desert: nil
    )

    #expect(throws: RecipesV3ConfigurationError.unavailableDemoMode(.desert)){
      try configuration.appConfiguration(for: .desert)
    }
  }

  @Test
  func environmentAndArgumentsUseDeterministicRoutePrecedence() throws {
    struct TestCase {
      var environmentRoute: String
      var argumentRoute: String
      var expectedMode: RecipesV3DemoMode
    }

    let cases = [
      TestCase(
        environmentRoute: "current",
        argumentRoute: "desert-required",
        expectedMode: .normal
      ),
      TestCase(
        environmentRoute: "desert-required",
        argumentRoute: "current",
        expectedMode: .desert
      ),
      TestCase(
        environmentRoute: " ",
        argumentRoute: "desert-required",
        expectedMode: .desert
      ),
      TestCase(
        environmentRoute: "$(INSTANT_SWIFT_DATA_SYNC_ROUTE)",
        argumentRoute: "current",
        expectedMode: .normal
      ),
    ]

    for testCase in cases {
      let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
        [
          "INSTANT_APP_ID": "precedence-app",
          "INSTANT_SWIFT_DATA_SYNC_ROUTE": testCase.environmentRoute,
          "INSTANT_DESERT_ROLE": "host",
          "INSTANT_DESERT_HOST": "127.0.0.1",
          "INSTANT_DESERT_PORT": "8787",
        ],
        arguments: [
          "recipes-v3",
          "--sync-route", testCase.argumentRoute,
          "--desert-role", "peer",
          "--desert-host", "127.0.0.2",
          "--desert-port", "8788",
        ],
        infoDictionary: [:],
        defaultDesertEndpoint: nil,
        makeProfileID: { "precedence-profile" }
      )

      expectNoDifference(configuration.forcedMode, testCase.expectedMode)
    }
  }

  @Test
  func blankEndpointEnvironmentValuesFallThroughToArguments() throws {
    let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
      [
        "INSTANT_APP_ID": "precedence-app",
        "INSTANT_SWIFT_DATA_SYNC_ROUTE": "desert-required",
        "INSTANT_DESERT_ROLE": " ",
        "INSTANT_DESERT_HOST": "$(INSTANT_DESERT_HOST)",
        "INSTANT_DESERT_PORT": "",
      ],
      arguments: [
        "recipes-v3",
        "--desert-role", "peer",
        "--desert-host", "127.0.0.2",
        "--desert-port", "8788",
      ],
      infoDictionary: [:],
      defaultDesertEndpoint: nil,
      makeProfileID: { "precedence-profile" }
    )

    expectNoDifference(
      try configuration.appConfiguration(for: .desert).syncRoute,
      .desertRequired(
        RecipesV3DesertEndpoint(
          role: .peer,
          host: "127.0.0.2",
          port: 8788
        )
      )
    )
  }

  @Test
  func blankAppIDEnvironmentValuesFallThroughToArguments() throws {
    for environmentAppID in [" ", "$(INSTANT_APP_ID)"] {
      let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
        [
          "INSTANT_APP_ID": environmentAppID,
          "INSTANT_SWIFT_DATA_SYNC_ROUTE": " ",
        ],
        arguments: [
          "recipes-v3",
          "--instant-app-id", "argument-app",
          "--sync-route", "desert-required",
          "--desert-role", "peer",
          "--desert-host", "127.0.0.2",
          "--desert-port", "8788",
        ],
        infoDictionary: [:],
        defaultDesertEndpoint: nil,
        makeProfileID: { "precedence-profile" }
      )

      expectNoDifference(configuration.forcedMode, .desert)
      expectNoDifference(
        try configuration.appConfiguration(for: .desert).appID,
        "argument-app"
      )
    }
  }

  @Test @MainActor
  func modePreferenceDefaultsToNormalAndPersistsBothSelections() async throws {
    var storedMode: RecipesV3DemoMode?
    let storage = RecipesV3ModeStorage(
      load: { storedMode },
      save: { storedMode = $0 }
    )
    let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
      [:],
      arguments: ["recipes-v3"],
      infoDictionary: [:],
      defaultDesertEndpoint: RecipesV3DesertEndpoint(
        role: .host,
        host: "127.0.0.1",
        port: 49_800
      ),
      makeProfileID: { "profile-123" }
    )

    let firstModel = RecipesV3DemoModel(
      configuration: configuration,
      modeStorage: storage
    )
    expectNoDifference(firstModel.mode, .normal)

    firstModel.mode = .desert
    try await waitForModeTransition(firstModel)
    expectNoDifference(storedMode, .desert)

    let secondModel = RecipesV3DemoModel(
      configuration: configuration,
      modeStorage: storage
    )
    expectNoDifference(secondModel.mode, .desert)

    secondModel.mode = .normal
    try await waitForModeTransition(secondModel)
    expectNoDifference(storedMode, .normal)

    let thirdModel = RecipesV3DemoModel(
      configuration: configuration,
      modeStorage: storage
    )
    expectNoDifference(thirdModel.mode, .normal)
  }

  @Test @MainActor
  func userDefaultsModeStorageRoundTripsBothModes() throws {
    let suiteName = "RecipesV3ModeStorageTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let storage = RecipesV3ModeStorage.userDefaults(suiteName: suiteName)

    expectNoDifference(storage.load(), nil)
    storage.save(.desert)
    expectNoDifference(storage.load(), .desert)
    storage.save(.normal)
    expectNoDifference(storage.load(), .normal)
  }

  @Test @MainActor
  func forcedLaunchRouteOverridesPersistedNormalPreference() throws {
    var savedModes: [RecipesV3DemoMode] = []
    let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
      [
        "INSTANT_APP_ID": "desert-smoke",
        "INSTANT_SWIFT_DATA_SYNC_ROUTE": "desert-required",
        "INSTANT_DESERT_ROLE": "host",
        "INSTANT_DESERT_HOST": "127.0.0.1",
        "INSTANT_DESERT_PORT": "8787",
      ],
      arguments: ["recipes-v3"],
      infoDictionary: [:],
      defaultDesertEndpoint: nil,
      makeProfileID: { "forced-profile" }
    )
    let model = RecipesV3DemoModel(
      configuration: configuration,
      modeStorage: RecipesV3ModeStorage(
        load: { .normal },
        save: { savedModes.append($0) }
      )
    )

    expectNoDifference(configuration.forcedMode, .desert)
    expectNoDifference(model.mode, .desert)
    #expect(model.allowsModeSelection == false)

    model.mode = .normal

    expectNoDifference(model.mode, .desert)
    expectNoDifference(savedModes, [])
    expectNoDifference(
      model.bootstrapModel?.configuration.syncRoute,
      .desertRequired(
        RecipesV3DesertEndpoint(role: .host, host: "127.0.0.1", port: 8787)
      )
    )
  }

  @Test @MainActor
  func explicitCurrentRouteOverridesPersistedDesertPreference() throws {
    let configuration = try RecipesV3DemoConfiguration.validatedEnvironment(
      ["INSTANT_APP_ID": "cloud-app"],
      arguments: ["recipes-v3", "--sync-route", "current"],
      infoDictionary: [:],
      defaultDesertEndpoint: RecipesV3DesertEndpoint(
        role: .host,
        host: "127.0.0.1",
        port: 49_800
      ),
      makeProfileID: { "forced-profile" }
    )
    let model = RecipesV3DemoModel(
      configuration: configuration,
      modeStorage: RecipesV3ModeStorage(
        load: { .desert },
        save: { _ in }
      )
    )

    expectNoDifference(configuration.forcedMode, .normal)
    expectNoDifference(model.mode, .normal)
    #expect(model.allowsModeSelection == false)
    expectNoDifference(
      try #require(model.activeConfiguration).syncRoute,
      .cloud
    )
  }

  @Test @MainActor
  func changingModeStopsTheDesertHostBeforePublishingNormal() async throws {
    let reservation = try await InstantNetworkDesertHost.start(
      appID: "desert-mode-reservation",
      host: "127.0.0.1",
      port: 0
    )
    let port = reservation.port
    await reservation.stop()

    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-mode-switch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let normalConfiguration = RecipesV3AppConfiguration(
      appID: "recipes-mode-normal",
      persistenceURL: temporaryDirectory.appendingPathComponent("normal.sqlite"),
      syncRoute: .localOnly,
      profileID: "mode-profile"
    )
    let desertConfiguration = RecipesV3AppConfiguration(
      appID: "recipes-mode-desert",
      persistenceURL: temporaryDirectory.appendingPathComponent("desert.sqlite"),
      syncRoute: .desertRequired(
        RecipesV3DesertEndpoint(
          role: .host,
          host: "127.0.0.1",
          port: port
        )
      ),
      profileID: "mode-profile"
    )
    let model = RecipesV3DemoModel(
      configuration: RecipesV3DemoConfiguration(
        normal: normalConfiguration,
        desert: desertConfiguration
      ),
      modeStorage: RecipesV3ModeStorage(
        load: { .desert },
        save: { _ in }
      ),
      configureDependencies: {
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.uuid = .constant(
          UUID(uuidString: "00000000-0000-0000-0000-000000000047")!
        )
      }
    )
    let desertBootstrap = try #require(model.bootstrapModel)
    desertBootstrap.startIfNeeded()
    let startDeadline = ContinuousClock.now + .seconds(3)
    while desertBootstrap.client == nil, ContinuousClock.now < startDeadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(desertBootstrap.client != nil)

    model.mode = .normal
    try await waitForModeTransition(model)

    expectNoDifference(model.bootstrapModel?.configuration, normalConfiguration)
    let reboundHost = try await InstantNetworkDesertHost.start(
      appID: "desert-mode-rebound",
      host: "127.0.0.1",
      port: port
    )
    await reboundHost.stop()
  }

  @Test @MainActor
  func recipeMutationsUseTheNewClientAfterEachModeSwitch() async throws {
    let reservation = try await InstantNetworkDesertHost.start(
      appID: "desert-mode-client-reservation",
      host: "127.0.0.1",
      port: 0
    )
    let port = reservation.port
    await reservation.stop()

    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-client-switch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let model = RecipesV3DemoModel(
      configuration: RecipesV3DemoConfiguration(
        normal: RecipesV3AppConfiguration(
          appID: "recipes-client-normal",
          persistenceURL: temporaryDirectory.appendingPathComponent("normal.sqlite"),
          syncRoute: .localOnly,
          profileID: "client-profile"
        ),
        desert: RecipesV3AppConfiguration(
          appID: "recipes-client-desert",
          persistenceURL: temporaryDirectory.appendingPathComponent("desert.sqlite"),
          syncRoute: .desertRequired(
            RecipesV3DesertEndpoint(
              role: .host,
              host: "127.0.0.1",
              port: port
            )
          ),
          profileID: "client-profile"
        )
      ),
      modeStorage: RecipesV3ModeStorage(
        load: { .normal },
        save: { _ in }
      ),
      configureDependencies: {
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.uuid = .constant(
          UUID(uuidString: "00000000-0000-0000-0000-000000000048")!
        )
      }
    )

    do {
      let firstNormalClient = try await startClient(in: model)
      try await createTodo(
        id: "normal-before-switch",
        text: "Normal before switch",
        using: firstNormalClient
      )
      let firstNormalTodos = await observedTodoIDs(using: firstNormalClient)
      expectNoDifference(
        firstNormalTodos,
        ["normal-before-switch"]
      )

      model.mode = .desert
      try await waitForModeTransition(model)
      let desertClient = try await startClient(in: model)
      try await createTodo(
        id: "desert-after-switch",
        text: "Desert after switch",
        using: desertClient
      )
      let desertTodos = await observedTodoIDs(using: desertClient)
      expectNoDifference(
        desertTodos,
        ["desert-after-switch"]
      )

      model.mode = .normal
      try await waitForModeTransition(model)
      let secondNormalClient = try await startClient(in: model)
      try await createTodo(
        id: "normal-after-switch",
        text: "Normal after switch",
        using: secondNormalClient
      )
      let secondNormalTodos = await observedTodoIDs(using: secondNormalClient)
      expectNoDifference(
        Set(secondNormalTodos),
        Set(["normal-before-switch", "normal-after-switch"])
      )
    } catch {
      await model.shutdown()
      throw error
    }

    await model.shutdown()
    let reboundHost = try await InstantNetworkDesertHost.start(
      appID: "desert-mode-client-rebound",
      host: "127.0.0.1",
      port: port
    )
    await reboundHost.stop()
  }

  #if os(macOS)
    @Test @MainActor
    func scopedClientReachesEveryRecipeDependencyHelper() async throws {
      let recorder = RecipesV3ScopedDependencyRecorder()
      let client = recipesV3ScopedDependencyClient(recorder: recorder)
      let todos = NSHostingView(
        rootView: RecipesV3RecipeScreen(
          recipe: .todos,
          profileID: "scoped-todos"
        )
        .dependency(\.defaultInstantSwiftData, client)
      )
      let reactions = NSHostingView(
        rootView: RecipesV3RecipeScreen(
          recipe: .reactions,
          profileID: "scoped-reactions"
        )
        .dependency(\.defaultInstantSwiftData, client)
      )
      let mergeTileGame = NSHostingView(
        rootView: RecipesV3RecipeScreen(
          recipe: .mergeTileGame,
          profileID: "scoped-merge-tile-game"
        )
        .dependency(\.defaultInstantSwiftData, client)
      )
      let auth = NSHostingView(
        rootView: RecipesV3RecipeScreen(
          recipe: .auth,
          profileID: "scoped-auth"
        )
        .dependency(\.defaultInstantSwiftData, client)
      )
      let compositeFetch = NSHostingView(
        rootView: RecipesV3ScopedCompositeFetchFixture()
          .dependency(\.defaultInstantSwiftData, client)
      )

      for hostingView in [todos, reactions, mergeTileGame, auth] {
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
        hostingView.layoutSubtreeIfNeeded()
      }
      compositeFetch.frame = NSRect(x: 0, y: 0, width: 360, height: 80)
      compositeFetch.layoutSubtreeIfNeeded()

      let expectedEvents: Set<String> = [
        "auth",
        "presence",
        "query:boards",
        "query:todos",
        "room",
        "topic",
      ]
      let deadline = ContinuousClock.now + .seconds(3)
      while ContinuousClock.now < deadline {
        let events = await recorder.events()
        let todoQueryCount = await recorder.count(for: "query:todos")
        if events.isSuperset(of: expectedEvents), todoQueryCount >= 2 {
          break
        }
        try await Task.sleep(for: .milliseconds(20))
      }

      let events = await recorder.events()
      let todoQueryCount = await recorder.count(for: "query:todos")
      #expect(events.isSuperset(of: expectedEvents))
      #expect(todoQueryCount >= 2)
      withExtendedLifetime((todos, reactions, mergeTileGame, auth, compositeFetch)) {}
    }

    @Test @MainActor
    func unimplementedScopedClientKeepsAutomaticFetchInert() async throws {
      let hostingView = NSHostingView(
        rootView: RecipesV3ScopedCompositeFetchFixture()
          .dependency(
            \.defaultInstantSwiftData,
            .unimplemented("Automatic observation must remain inert.")
          )
      )
      hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 80)
      hostingView.layoutSubtreeIfNeeded()

      try await Task.sleep(for: .milliseconds(100))
      withExtendedLifetime(hostingView) {}
    }
  #endif

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
  func forcedDesertModeAcceptsEveryCatalogRecipe() throws {
    for recipe in InstantRecipeV3.allCases {
      let configuration = try RecipesV3AppConfiguration.validatedEnvironment(
        [:],
        arguments: [
          "recipes-v3",
          "--instant-app-id", "desert-smoke",
          "--sync-route", "desert-required",
          "--desert-role", "peer",
          "--desert-host", "127.0.0.1",
          "--desert-port", "8787",
          "--recipe", recipe.rawValue,
        ],
        infoDictionary: [:]
      )

      expectNoDifference(configuration.launchRecipe, recipe)
    }
  }

  @Test
  func forcedDesertCatalogKeepsEveryRecipeVisible() {
    let route = RecipesV3SyncRoute.desertRequired(
      RecipesV3DesertEndpoint(role: .host, host: "127.0.0.1", port: 8787)
    )

    expectNoDifference(route.visibleRecipes, InstantRecipeV3.allCases)
  }

  @Test @MainActor
  func authCompositionAllowsExternalProvidersOnlyOutsideDesertMode() {
    let desertRoute = RecipesV3SyncRoute.desertRequired(
      RecipesV3DesertEndpoint(role: .peer, host: "127.0.0.1", port: 8787)
    )

    expectNoDifference(
      [
        RecipesV3SyncRoute.localOnly.allowsExternalAuthProviders,
        RecipesV3SyncRoute.cloud.allowsExternalAuthProviders,
        desertRoute.allowsExternalAuthProviders,
      ],
      [true, true, false]
    )

    let screen = RecipesV3RecipeScreen(
      recipe: .auth,
      profileID: "desert-profile",
      syncRoute: desertRoute
    )
    expectNoDifference(screen.syncRoute, desertRoute)
  }

  @Test
  func catalogKeepsTransportBannerOutsideNavigationContainer() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: packageRoot.appendingPathComponent(
        "Sources/RecipesV3App/RecipesV3App.swift"
      ),
      encoding: .utf8
    )
    let catalogStart = try #require(
      source.range(of: "public struct RecipesV3CatalogScreen: View {")
    )
    let catalogEnd = try #require(
      source.range(of: "public struct RecipesV3RecipeScreen: View {")
    )
    let catalogSource = source[catalogStart.lowerBound..<catalogEnd.lowerBound]

    let catalogLines = catalogSource.split(separator: "\n").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    let containerLine = try #require(
      catalogLines.firstIndex(of: "VStack(spacing: 0) {")
    )
    expectNoDifference(
      Array(catalogLines[containerLine...containerLine + 3]),
      [
        "VStack(spacing: 0) {",
        "transportStatusBanner",
        "catalogNavigation",
        "}",
      ]
    )
    #expect(catalogSource.contains(".safeAreaInset(edge: .top") == false)
  }

  @Test
  func requiredDesertTransportErrorClearsOnlyAfterRecoverySucceeds() {
    var blockingError: RecipesV3BlockingError?

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .opened,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(blockingError, nil)

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .errored,
      lastErrorMessage: "Mutation rejected.",
      requiresHealthyConnection: true
    )
    expectNoDifference(blockingError, nil)

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .closed,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(
      blockingError,
      .transport("The required Desert connection is no longer available.")
    )

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .connecting,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(
      blockingError,
      .transport("The required Desert connection is no longer available.")
    )

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .opened,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(blockingError, nil)

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .connecting,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(
      blockingError,
      .transport("The required Desert connection is reconnecting.")
    )

    blockingError = RecipesV3BlockingError.reducing(
      blockingError,
      state: .authenticated,
      lastErrorMessage: nil,
      requiresHealthyConnection: true
    )
    expectNoDifference(blockingError, nil)
  }

  @Test
  func healthyTransportStatusDoesNotClearABootstrapError() {
    for state in [
      InstantConnectionState.connecting,
      .opened,
      .authenticated,
    ] {
      expectNoDifference(
        RecipesV3BlockingError.reducing(
          .bootstrap("Initial bootstrap failed."),
          state: state,
          lastErrorMessage: nil,
          requiresHealthyConnection: true
        ),
        .bootstrap("Initial bootstrap failed.")
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

  @Test @MainActor
  func unreachableInteractiveDesertPeerCanRecoverToNormal() async throws {
    let reservation = try await InstantNetworkDesertHost.start(
      appID: "desert-recovery-port-reservation",
      host: "127.0.0.1",
      port: 0
    )
    let unavailablePort = reservation.port
    await reservation.stop()

    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-desert-recovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    var storedMode = RecipesV3DemoMode.desert
    let model = RecipesV3DemoModel(
      configuration: RecipesV3DemoConfiguration(
        normal: RecipesV3AppConfiguration(
          appID: "desert-recovery-normal",
          persistenceURL: temporaryDirectory.appendingPathComponent("normal.sqlite"),
          syncRoute: .localOnly,
          profileID: "recovery-profile"
        ),
        desert: RecipesV3AppConfiguration(
          appID: "desert-recovery-peer",
          persistenceURL: temporaryDirectory.appendingPathComponent("desert.sqlite"),
          syncRoute: .desertRequired(
            RecipesV3DesertEndpoint(
              role: .peer,
              host: "127.0.0.1",
              port: unavailablePort
            )
          ),
          profileID: "recovery-profile"
        )
      ),
      modeStorage: RecipesV3ModeStorage(
        load: { storedMode },
        save: { storedMode = $0 }
      ),
      configureDependencies: {
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.uuid = .constant(
          UUID(uuidString: "00000000-0000-0000-0000-000000000049")!
        )
      }
    )

    do {
      let failedDesertBootstrap = try #require(model.bootstrapModel)
      failedDesertBootstrap.startIfNeeded()
      let deadline = ContinuousClock.now + .seconds(3)
      while failedDesertBootstrap.errorMessage == nil,
        ContinuousClock.now < deadline
      {
        try await Task.sleep(for: .milliseconds(20))
      }

      #expect(failedDesertBootstrap.client == nil)
      #expect(failedDesertBootstrap.errorMessage != nil)
      #expect(model.allowsModeSelection)

      model.mode = .normal
      try await waitForModeTransition(model)
      let normalClient = try await startClient(in: model)
      expectNoDifference(model.mode, .normal)
      expectNoDifference(storedMode, .normal)
      expectNoDifference(model.activeConfiguration?.syncRoute, .localOnly)

      try await createTodo(
        id: "normal-after-desert-failure",
        text: "Recovered from Desert",
        using: normalClient
      )
      let recoveredTodoIDs = await observedTodoIDs(using: normalClient)
      expectNoDifference(
        recoveredTodoIDs,
        ["normal-after-desert-failure"]
      )
    } catch {
      await model.shutdown()
      throw error
    }

    await model.shutdown()
  }

  @Test
  func combinedSchemaContainsEveryDurableRecipeNamespace() {
    expectNoDifference(
      Set(RecipesV3AppConfiguration.initialAttributes.map(\.namespace)),
      Set(["todos", "boards", "$users"])
    )
  }
}

@MainActor
private func waitForModeTransition(
  _ model: RecipesV3DemoModel
) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while model.isSwitchingMode || model.bootstrapModel == nil,
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(model.isSwitchingMode == false)
  #expect(model.bootstrapModel != nil)
}

@MainActor
private func startClient(
  in model: RecipesV3DemoModel
) async throws -> InstantSwiftDataClient {
  let bootstrap = try #require(model.bootstrapModel)
  bootstrap.startIfNeeded()
  let deadline = ContinuousClock.now + .seconds(3)
  while bootstrap.client == nil, bootstrap.errorMessage == nil,
    ContinuousClock.now < deadline
  {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(bootstrap.errorMessage == nil)
  return try #require(bootstrap.client)
}

private func createTodo(
  id: String,
  text: String,
  using client: InstantSwiftDataClient
) async throws {
  try await client.transact(id: "create-\(id)") {
    Todo.create(
      id: InstantID(rawValue: id),
      Todo.text.set(text),
      Todo.isCompleted.set(false),
      Todo.createdAt.set(Date(timeIntervalSince1970: 1_800_000_000))
    )
  }
}

private func observedTodoIDs(
  using client: InstantSwiftDataClient
) async -> [String] {
  let stream = await client.observe(Todo.query.plan)
  var iterator = stream.makeAsyncIterator()
  return await iterator.next()?.values.map(\.id) ?? []
}

#if os(macOS)
  private actor RecipesV3ScopedDependencyRecorder {
    private var recordedEvents: [String: Int] = [:]

    func record(_ event: String) {
      recordedEvents[event, default: 0] += 1
    }

    func events() -> Set<String> {
      Set(recordedEvents.keys)
    }

    func count(for event: String) -> Int {
      recordedEvents[event, default: 0]
    }
  }

  @MainActor
  private struct RecipesV3ScopedCompositeFetchFixture: View {
    @Fetch(
      wrappedValue: 0,
      RecipesV3ScopedTodoCountRequest()
    )
    private var todoCount: Int

    var body: some View {
      Text("\(todoCount) todos")
    }
  }

  private struct RecipesV3ScopedTodoCountRequest: InstantFetchKeyRequest {
    var fetchRequest: InstantFetchRequest<Int> {
      InstantFetchRequest(Todo.query) { $0.count }
    }
  }

  private func recipesV3ScopedDependencyClient(
    recorder: RecipesV3ScopedDependencyRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: 0,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { plan in
        await recorder.record("query:\(plan.namespace)")
        return AsyncStream { continuation in
          continuation.yield(
            InstantQueryEmission(
              queryID: plan.id,
              sequence: 0,
              values: []
            )
          )
        }
      },
      pendingMutations: { [] },
      localID: { "scoped-\($0)" },
      observeAuthSession: {
        await recorder.record("auth")
        return AsyncStream { continuation in
          continuation.yield(nil)
        }
      },
      joinRoom: { room in
        await recorder.record("room")
        return room
      },
      observeRoomPresence: { _ in
        await recorder.record("presence")
        return AsyncStream { continuation in
          continuation.yield([])
        }
      },
      observeRoomTopicMessages: { _, _ in
        await recorder.record("topic")
        return AsyncStream { continuation in
          continuation.yield([])
        }
      }
    )
  }
#endif
