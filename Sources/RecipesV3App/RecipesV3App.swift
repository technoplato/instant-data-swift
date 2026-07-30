import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData
import Observation
import PresenceRecipesV3App
import TodosV3App

public enum InstantRecipeV3: String, CaseIterable, Hashable, Identifiable, Sendable {
  case todos
  case cursors
  case customCursors = "custom-cursors"
  case reactions
  case typingIndicator = "typing-indicator"
  case avatarStack = "avatar-stack"
  case mergeTileGame = "merge-tile-game"
  case auth

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .todos: "Todos"
    case .cursors: "Cursors"
    case .customCursors: "Custom Cursors"
    case .reactions: "Reactions"
    case .typingIndicator: "Typing Indicator"
    case .avatarStack: "Avatar Stack"
    case .mergeTileGame: "Merge Tile Game"
    case .auth: "Auth"
    }
  }

  public var summary: String {
    switch self {
    case .todos: "Realtime CRUD with optimistic local state"
    case .cursors: "Share normalized pointer positions with presence"
    case .customCursors: "Add names, colors, and custom cursor rendering"
    case .reactions: "Publish ephemeral emoji events over a room topic"
    case .typingIndicator: "Publish and expire per-input typing presence"
    case .avatarStack: "Render the current online presence roster"
    case .mergeTileGame: "Merge durable board state with live player presence"
    case .auth: "Magic code, guest, native, and browser provider flows"
    }
  }

  public var systemImage: String {
    switch self {
    case .todos: "checklist"
    case .cursors: "cursorarrow.motionlines"
    case .customCursors: "person.crop.circle.badge.checkmark"
    case .reactions: "hand.thumbsup"
    case .typingIndicator: "ellipsis.message"
    case .avatarStack: "person.3"
    case .mergeTileGame: "square.grid.2x2"
    case .auth: "person.badge.key"
    }
  }

  public init?(pathName: String) {
    self.init(rawValue: pathName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

public enum RecipesV3DesertRole: String, Hashable, Sendable {
  case host
  case peer
}

public struct RecipesV3DesertEndpoint: Hashable, Sendable {
  public var role: RecipesV3DesertRole
  public var host: String
  public var port: UInt16

  public init(role: RecipesV3DesertRole, host: String, port: UInt16) {
    self.role = role
    self.host = host
    self.port = port
  }
}

public enum RecipesV3SyncRoute: Hashable, Sendable {
  case localOnly
  case cloud
  case desertRequired(RecipesV3DesertEndpoint)

  public var allowsExternalAuthProviders: Bool {
    switch self {
    case .localOnly, .cloud:
      true
    case .desertRequired:
      false
    }
  }

  public var statusTitle: String {
    switch self {
    case .localOnly:
      "Local data only"
    case .cloud:
      "InstantDB cloud"
    case .desertRequired(let endpoint):
      switch endpoint.role {
      case .host:
        "Desert host · \(endpoint.host):\(endpoint.port)"
      case .peer:
        "Desert peer · \(endpoint.host):\(endpoint.port)"
      }
    }
  }
}

public enum RecipesV3DemoMode: String, CaseIterable, Hashable, Identifiable, Sendable {
  case normal
  case desert

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .normal:
      "Normal"
    case .desert:
      "Desert"
    }
  }

  var isDesert: Bool {
    get { self == .desert }
    set { self = newValue ? .desert : .normal }
  }
}

@MainActor
struct RecipesV3ModeStorage {
  static let userDefaultsKey = "instant-recipes-v3.sync-mode"

  private let loadMode: () -> RecipesV3DemoMode?
  private let saveMode: (RecipesV3DemoMode) -> Void

  init(
    load: @escaping () -> RecipesV3DemoMode?,
    save: @escaping (RecipesV3DemoMode) -> Void
  ) {
    self.loadMode = load
    self.saveMode = save
  }

  func load() -> RecipesV3DemoMode? {
    loadMode()
  }

  func save(_ mode: RecipesV3DemoMode) {
    saveMode(mode)
  }

  static func userDefaults(suiteName: String? = nil) -> Self {
    Self(
      load: {
        let defaults =
          suiteName.flatMap(UserDefaults.init(suiteName:))
          ?? UserDefaults.standard
        return defaults.string(forKey: userDefaultsKey)
          .flatMap(RecipesV3DemoMode.init(rawValue:))
      },
      save: { mode in
        let defaults =
          suiteName.flatMap(UserDefaults.init(suiteName:))
          ?? UserDefaults.standard
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
      }
    )
  }

  static var live: Self {
    userDefaults()
  }
}

enum RecipesV3BlockingError: Equatable, Sendable {
  case bootstrap(String)
  case transport(String)

  var message: String {
    switch self {
    case .bootstrap(let message), .transport(let message):
      message
    }
  }

  static func reducing(
    _ current: Self?,
    state: InstantConnectionState,
    lastErrorMessage: String?,
    requiresHealthyConnection: Bool
  ) -> Self? {
    guard requiresHealthyConnection else { return current }

    switch state {
    case .closed:
      if case .bootstrap = current {
        return current
      }
      return .transport(
        lastErrorMessage
          ?? "The required Desert connection is no longer available."
      )

    case .connecting:
      if case .bootstrap = current {
        return current
      }
      return current
        ?? .transport("The required Desert connection is reconnecting.")

    case .opened, .authenticated:
      guard let current else { return nil }
      switch current {
      case .bootstrap:
        return current
      case .transport:
        return nil
      }

    case .errored:
      // Runtime operation rejection is intentionally isolated per item but is
      // also represented by `.errored`. Keep the catalog available and let its
      // status banner plus the owning recipe surface that failure. A truly
      // unavailable required route transitions to `.closed`.
      return current
    }
  }
}

public enum RecipesV3ConfigurationError: Error, Equatable, Sendable {
  case missingValue(String)
  case invalidValue(key: String, value: String, expected: String)
  case unavailableDemoMode(RecipesV3DemoMode)
  case unsupportedDesertRecipe(String)
}

extension RecipesV3ConfigurationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingValue(let key):
      "Desert mode requires \(key)."
    case .invalidValue(let key, let value, let expected):
      "Invalid \(key) value ‘\(value)’; expected \(expected)."
    case .unavailableDemoMode(let mode):
      "The \(mode.title) demo mode is unavailable because this launch has no matching transport configuration."
    case .unsupportedDesertRecipe(let recipe):
      "The ‘\(recipe)’ recipe does not support the selected Desert transport capabilities."
    }
  }
}

public struct RecipesV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var syncRoute: RecipesV3SyncRoute
  public var profileID: String
  public var launchRecipe: InstantRecipeV3?
  public var enablesLiveSync: Bool {
    get { syncRoute != .localOnly }
    set { syncRoute = newValue ? .cloud : .localOnly }
  }

  public init(
    appID: String,
    persistenceURL: URL? = nil,
    syncRoute: RecipesV3SyncRoute,
    profileID: String,
    launchRecipe: InstantRecipeV3? = nil
  ) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.syncRoute = syncRoute
    self.profileID = profileID
    self.launchRecipe = launchRecipe
  }

  public init(
    appID: String,
    persistenceURL: URL? = nil,
    enablesLiveSync: Bool,
    profileID: String,
    launchRecipe: InstantRecipeV3? = nil
  ) {
    self.init(
      appID: appID,
      persistenceURL: persistenceURL,
      syncRoute: enablesLiveSync ? .cloud : .localOnly,
      profileID: profileID,
      launchRecipe: launchRecipe
    )
  }

  /// Preserves the pre-Desert configuration contract for source compatibility.
  /// Use `validatedEnvironment` at executable composition roots that support forced Desert mode.
  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    makeProfileID: () -> String = { UUID().uuidString.lowercased() }
  ) -> Self {
    let configuredAppID =
      normalizedConfigurationValue(environment["INSTANT_APP_ID"])
      ?? launchOption("--instant-app-id", in: arguments)
      ?? normalizedConfigurationValue(
        infoDictionary["InstantAppID"] as? String
      )
    let recipeName =
      normalizedConfigurationValue(environment["INSTANT_RECIPE"])
      ?? launchRecipeName(in: arguments)
    return Self(
      appID: configuredAppID ?? "recipes-v3-local",
      persistenceURL: (normalizedConfigurationValue(environment["INSTANT_PERSISTENCE_PATH"])
        ?? launchOption("--persistence-path", in: arguments))
        .map(URL.init(fileURLWithPath:)),
      syncRoute: configuredAppID == nil ? .localOnly : .cloud,
      profileID: normalizedConfigurationValue(environment["INSTANT_RECIPE_PROFILE_ID"])
        ?? makeProfileID(),
      launchRecipe: recipeName.flatMap(InstantRecipeV3.init(pathName:))
    )
  }

  public static func validatedEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    makeProfileID: () -> String = { UUID().uuidString.lowercased() }
  ) throws -> Self {
    let configuredAppID =
      normalizedConfigurationValue(environment["INSTANT_APP_ID"])
      ?? launchOption("--instant-app-id", in: arguments)
      ?? normalizedConfigurationValue(
        infoDictionary["InstantAppID"] as? String
      )
    let recipeName =
      normalizedConfigurationValue(environment["INSTANT_RECIPE"])
      ?? launchRecipeName(in: arguments)
    let syncRoute = try syncRoute(
      configuredAppID: configuredAppID,
      environment: environment,
      arguments: arguments
    )
    let launchRecipe = recipeName.flatMap(InstantRecipeV3.init(pathName:))
    return Self(
      appID: configuredAppID ?? "recipes-v3-local",
      persistenceURL: (normalizedConfigurationValue(environment["INSTANT_PERSISTENCE_PATH"])
        ?? launchOption("--persistence-path", in: arguments))
        .map(URL.init(fileURLWithPath:)),
      syncRoute: syncRoute,
      profileID: normalizedConfigurationValue(environment["INSTANT_RECIPE_PROFILE_ID"])
        ?? makeProfileID(),
      launchRecipe: launchRecipe
    )
  }

  public static var initialAttributes: [InstantAttribute] {
    Todo.instantAttributes
      + MergeTileGameV3Board.instantAttributes
      + AuthV3User.instantAttributes
  }

  fileprivate static func normalizedConfigurationValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty,
      !value.contains("$(")
    else { return nil }
    return value
  }

  private static func syncRoute(
    configuredAppID: String?,
    environment: [String: String],
    arguments: [String]
  ) throws -> RecipesV3SyncRoute {
    let configuredRoute = configuredSyncRoute(
      environment: environment,
      arguments: arguments
    )

    switch configuredRoute {
    case nil, "current":
      return configuredAppID == nil ? .localOnly : .cloud

    case "desert-required":
      guard configuredAppID != nil else {
        throw RecipesV3ConfigurationError.missingValue("INSTANT_APP_ID")
      }
      guard
        let endpoint = try desertEndpoint(
          environment: environment,
          arguments: arguments,
          defaultEndpoint: nil
        )
      else {
        throw RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_ROLE")
      }
      return .desertRequired(endpoint)

    case let configuredRoute?:
      throw RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_SWIFT_DATA_SYNC_ROUTE",
        value: configuredRoute,
        expected: "current or desert-required"
      )
    }
  }

  fileprivate static func configuredSyncRoute(
    environment: [String: String],
    arguments: [String]
  ) -> String? {
    normalizedConfigurationValue(environment["INSTANT_SWIFT_DATA_SYNC_ROUTE"])
      ?? launchOption("--sync-route", in: arguments)
  }

  fileprivate static func desertEndpoint(
    environment: [String: String],
    arguments: [String],
    defaultEndpoint: RecipesV3DesertEndpoint?
  ) throws -> RecipesV3DesertEndpoint? {
    let roleValue =
      normalizedConfigurationValue(environment["INSTANT_DESERT_ROLE"])
      ?? launchOption("--desert-role", in: arguments)
    let hostValue =
      normalizedConfigurationValue(environment["INSTANT_DESERT_HOST"])
      ?? launchOption("--desert-host", in: arguments)
    let portValue =
      normalizedConfigurationValue(environment["INSTANT_DESERT_PORT"])
      ?? launchOption("--desert-port", in: arguments)
    guard roleValue != nil || hostValue != nil || portValue != nil else {
      return defaultEndpoint
    }
    guard let roleValue else {
      throw RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_ROLE")
    }
    guard let role = RecipesV3DesertRole(rawValue: roleValue) else {
      throw RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_DESERT_ROLE",
        value: roleValue,
        expected: "host or peer"
      )
    }
    guard let hostValue else {
      throw RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_HOST")
    }
    guard let portValue else {
      throw RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_PORT")
    }
    guard let port = UInt16(portValue), port > 0 else {
      throw RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_DESERT_PORT",
        value: portValue,
        expected: "an integer from 1 through 65535"
      )
    }
    return RecipesV3DesertEndpoint(
      role: role,
      host: hostValue,
      port: port
    )
  }

  fileprivate static func launchOption(_ name: String, in arguments: [String]) -> String? {
    guard let optionIndex = arguments.lastIndex(of: name) else { return nil }
    let valueIndex = arguments.index(after: optionIndex)
    guard arguments.indices.contains(valueIndex) else { return nil }
    return normalizedConfigurationValue(arguments[valueIndex])
  }

  private static func launchRecipeName(in arguments: [String]) -> String? {
    launchOption("--recipe", in: arguments)
  }
}

public struct RecipesV3DemoConfiguration: Hashable, Sendable {
  public let normal: RecipesV3AppConfiguration
  public let desert: RecipesV3AppConfiguration?
  public let forcedMode: RecipesV3DemoMode?

  private let forcedConfiguration: RecipesV3AppConfiguration?

  public init(
    normal: RecipesV3AppConfiguration,
    desert: RecipesV3AppConfiguration?
  ) {
    self.normal = normal
    self.desert = desert
    self.forcedMode = nil
    self.forcedConfiguration = nil
  }

  fileprivate init(
    forcedConfiguration: RecipesV3AppConfiguration,
    mode: RecipesV3DemoMode
  ) {
    self.normal = forcedConfiguration
    self.desert = mode == .desert ? forcedConfiguration : nil
    self.forcedMode = mode
    self.forcedConfiguration = forcedConfiguration
  }

  public var allowsModeSelection: Bool {
    forcedMode == nil && desert != nil
  }

  public static var platformDefaultDesertEndpoint: RecipesV3DesertEndpoint? {
    #if os(macOS)
      RecipesV3DesertEndpoint(
        role: .host,
        host: "127.0.0.1",
        port: 49_800
      )
    #elseif os(iOS) && targetEnvironment(simulator)
      RecipesV3DesertEndpoint(
        role: .peer,
        host: "127.0.0.1",
        port: 49_800
      )
    #else
      nil
    #endif
  }

  public func resolvedMode(
    storedMode: RecipesV3DemoMode?
  ) -> RecipesV3DemoMode {
    if let forcedMode {
      return forcedMode
    }
    guard storedMode == .desert, desert != nil else {
      return .normal
    }
    return .desert
  }

  public func appConfiguration(
    for mode: RecipesV3DemoMode
  ) throws -> RecipesV3AppConfiguration {
    if let forcedConfiguration, forcedMode == mode {
      return forcedConfiguration
    }
    switch mode {
    case .normal:
      guard forcedMode == nil else {
        throw RecipesV3ConfigurationError.unavailableDemoMode(mode)
      }
      return normal
    case .desert:
      guard let desert else {
        throw RecipesV3ConfigurationError.unavailableDemoMode(mode)
      }
      return desert
    }
  }

  public static func validatedEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    defaultDesertEndpoint: RecipesV3DesertEndpoint? = platformDefaultDesertEndpoint,
    makeProfileID: () -> String = { UUID().uuidString.lowercased() }
  ) throws -> Self {
    let configuredRoute = RecipesV3AppConfiguration.configuredSyncRoute(
      environment: environment,
      arguments: arguments
    )
    let launchConfiguration = try RecipesV3AppConfiguration.validatedEnvironment(
      environment,
      arguments: arguments,
      infoDictionary: infoDictionary,
      makeProfileID: makeProfileID
    )

    switch configuredRoute {
    case "desert-required":
      return Self(
        forcedConfiguration: launchConfiguration,
        mode: .desert
      )

    case "current":
      return Self(
        forcedConfiguration: launchConfiguration,
        mode: .normal
      )

    case nil:
      let endpoint = try RecipesV3AppConfiguration.desertEndpoint(
        environment: environment,
        arguments: arguments,
        defaultEndpoint: defaultDesertEndpoint
      )
      let desertConfiguration = endpoint.map { endpoint in
        RecipesV3AppConfiguration(
          appID: desertAppID(for: launchConfiguration),
          persistenceURL: desertPersistenceURL(
            from: launchConfiguration.persistenceURL
          ),
          syncRoute: .desertRequired(endpoint),
          profileID: launchConfiguration.profileID,
          launchRecipe: launchConfiguration.launchRecipe
        )
      }
      return Self(
        normal: launchConfiguration,
        desert: desertConfiguration
      )

    case let configuredRoute?:
      throw RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_SWIFT_DATA_SYNC_ROUTE",
        value: configuredRoute,
        expected: "current or desert-required"
      )
    }
  }

  private static func desertAppID(
    for normalConfiguration: RecipesV3AppConfiguration
  ) -> String {
    switch normalConfiguration.syncRoute {
    case .localOnly:
      return "recipes-v3-desert"
    case .cloud, .desertRequired:
      return "\(normalConfiguration.appID)-desert"
    }
  }

  private static func desertPersistenceURL(from url: URL?) -> URL? {
    guard let url else { return nil }
    let fileExtension = url.pathExtension
    let stem = url.deletingPathExtension().lastPathComponent
    let filename =
      fileExtension.isEmpty
      ? "\(stem)-desert"
      : "\(stem)-desert.\(fileExtension)"
    return url.deletingLastPathComponent().appendingPathComponent(filename)
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class RecipesV3BootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var connectionStatus: InstantConnectionStatus?
    @Published public private(set) var errorMessage: String?

    public let configuration: RecipesV3AppConfiguration
    private let canStart: Bool
    private let configureDependencies: (inout DependencyValues) -> Void
    private var desertHost: InstantNetworkDesertHost?
    private var blockingError: RecipesV3BlockingError?
    private var statusTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(configuration: RecipesV3AppConfiguration) {
      self.configuration = configuration
      self.canStart = true
      self.configureDependencies = { _ in }
    }

    init(
      configuration: RecipesV3AppConfiguration,
      configureDependencies: @escaping (inout DependencyValues) -> Void
    ) {
      self.configuration = configuration
      self.canStart = true
      self.configureDependencies = configureDependencies
    }

    public init(configurationError: any Error) {
      self.configuration = RecipesV3AppConfiguration(
        appID: "recipes-v3-configuration-error",
        syncRoute: .localOnly,
        profileID: "configuration-error"
      )
      self.canStart = false
      self.configureDependencies = { _ in }
      let message = String(describing: configurationError)
      self.blockingError = .bootstrap(message)
      self.errorMessage = message
    }

    public func startIfNeeded() {
      guard canStart, client == nil, task == nil, stopTask == nil else { return }
      generation &+= 1
      let generation = generation
      let configureDependencies = configureDependencies
      task = Task {
        @MainActor [weak self, configuration, configureDependencies] in
        var startedDesertHost: InstantNetworkDesertHost?
        var startedClient: InstantSwiftDataClient?
        do {
          var dependencies = DependencyValues()
          configureDependencies(&dependencies)
          switch configuration.syncRoute {
          case .localOnly:
            break
          case .cloud:
            dependencies.instantLiveTransport = .live
          case .desertRequired(let endpoint):
            dependencies.instantSyncRoutePolicy = .desertRequired
            switch endpoint.role {
            case .host:
              let host = try await InstantNetworkDesertHost.start(
                appID: configuration.appID,
                initialAttributes: RecipesV3AppConfiguration.initialAttributes,
                host: endpoint.host,
                port: endpoint.port
              )
              startedDesertHost = host
              dependencies.instantDesertSyncTransportFactory = InstantSyncTransportFactory(
                adapter: "network-framework-host",
                transport: .inProcess,
                makeTransport: { host.transport }
              )

            case .peer:
              dependencies.instantDesertSyncTransportFactory = InstantSyncTransportFactory(
                adapter: "network-framework-peer",
                transport: .networkFramework,
                makeTransport: {
                  InstantLiveTransportClient.networkFramework(
                    host: endpoint.host,
                    port: endpoint.port
                  )
                }
              )
            }
          }
          try await dependencies.bootstrapInstantSwiftData(
            appID: configuration.appID,
            persistenceURL: configuration.persistenceURL,
            initialAttributes: RecipesV3AppConfiguration.initialAttributes
          )
          let client = dependencies.defaultInstantSwiftData
          startedClient = client
          let status: InstantConnectionStatus
          switch configuration.syncRoute {
          case .desertRequired:
            status = try await client.connect()
          case .localOnly, .cloud:
            status = try await client.connectionStatus()
          }
          try Task.checkCancellation()
          guard let self, self.generation == generation, self.stopTask == nil else {
            throw CancellationError()
          }
          self.desertHost = startedDesertHost
          self.connectionStatus = status
          self.client = client
          self.setBlockingError(nil)
          self.observeConnectionStatus(
            client: client,
            requiresHealthyConnection: configuration.syncRoute.isDesertRequired,
            generation: generation
          )
          if self.generation == generation {
            self.task = nil
          }
        } catch {
          if let startedClient {
            _ = try? await startedClient.closeConnection()
          }
          if let startedDesertHost {
            await startedDesertHost.stop()
          }
          guard let self, self.generation == generation else { return }
          if !Task.isCancelled, !(error is CancellationError) {
            self.setBlockingError(.bootstrap(String(describing: error)))
          }
          self.task = nil
        }
      }
    }

    public func stop() async {
      if let stopTask {
        await stopTask.value
        return
      }

      generation &+= 1
      let startupTask = task
      task = nil
      startupTask?.cancel()

      let observationTask = statusTask
      statusTask = nil
      observationTask?.cancel()

      let client = client
      let desertHost = desertHost
      self.client = nil
      self.desertHost = nil

      connectionStatus = nil
      setBlockingError(nil)

      let cleanupTask = Task { @MainActor in
        await startupTask?.value
        if let client {
          _ = try? await client.closeConnection()
        }
        await observationTask?.value
        if let desertHost {
          await desertHost.stop()
        }
      }
      stopTask = cleanupTask
      await cleanupTask.value
      stopTask = nil
    }

    private func observeConnectionStatus(
      client: InstantSwiftDataClient,
      requiresHealthyConnection: Bool,
      generation: UInt64
    ) {
      statusTask?.cancel()
      statusTask = Task { @MainActor [weak self, client] in
        do {
          let statuses = try await client.observeConnectionStatus()
          for await status in statuses {
            guard let self, self.generation == generation else { return }
            self.connectionStatus = status
            let blockingError = RecipesV3BlockingError.reducing(
              self.blockingError,
              state: status.state,
              lastErrorMessage: status.lastErrorMessage,
              requiresHealthyConnection: requiresHealthyConnection
            )
            if blockingError != self.blockingError {
              self.setBlockingError(blockingError)
            }
          }
        } catch is CancellationError {
        } catch {
          if requiresHealthyConnection,
            let self,
            self.generation == generation
          {
            self.setBlockingError(.transport(String(describing: error)))
          }
        }
      }
    }

    private func setBlockingError(_ blockingError: RecipesV3BlockingError?) {
      self.blockingError = blockingError
      self.errorMessage = blockingError?.message
    }
  }

  @MainActor
  @Observable
  public final class RecipesV3DemoModel {
    public var mode: RecipesV3DemoMode {
      didSet {
        modeDidChange(from: oldValue)
      }
    }

    public private(set) var bootstrapModel: RecipesV3BootstrapModel?
    public private(set) var isSwitchingMode = false

    public let configuration: RecipesV3DemoConfiguration

    @ObservationIgnored
    private let configureDependencies: (inout DependencyValues) -> Void
    @ObservationIgnored private let modeStorage: RecipesV3ModeStorage
    @ObservationIgnored private var isCorrectingMode = false
    @ObservationIgnored private var transitionTask: Task<Void, Never>?

    public convenience init(configuration: RecipesV3DemoConfiguration) {
      self.init(
        configuration: configuration,
        modeStorage: .live,
        configureDependencies: { _ in }
      )
    }

    init(
      configuration: RecipesV3DemoConfiguration,
      modeStorage: RecipesV3ModeStorage,
      configureDependencies: @escaping (inout DependencyValues) -> Void = { _ in }
    ) {
      self.configuration = configuration
      self.modeStorage = modeStorage
      self.configureDependencies = configureDependencies
      let mode = configuration.resolvedMode(
        storedMode: modeStorage.load()
      )
      self.mode = mode
      do {
        self.bootstrapModel = RecipesV3BootstrapModel(
          configuration: try configuration.appConfiguration(for: mode),
          configureDependencies: configureDependencies
        )
      } catch {
        self.bootstrapModel = RecipesV3BootstrapModel(
          configurationError: error
        )
      }
    }

    public init(configurationError: any Error) {
      let bootstrapModel = RecipesV3BootstrapModel(
        configurationError: configurationError
      )
      self.configuration = RecipesV3DemoConfiguration(
        forcedConfiguration: bootstrapModel.configuration,
        mode: .normal
      )
      self.modeStorage = .live
      self.configureDependencies = { _ in }
      self.mode = .normal
      self.bootstrapModel = bootstrapModel
    }

    public var allowsModeSelection: Bool {
      configuration.allowsModeSelection && !isSwitchingMode
    }

    public var activeConfiguration: RecipesV3AppConfiguration? {
      try? configuration.appConfiguration(for: mode)
    }

    public func shutdown() async {
      let transitionTask = transitionTask
      self.transitionTask = nil
      transitionTask?.cancel()
      await transitionTask?.value

      let bootstrapModel = bootstrapModel
      self.bootstrapModel = nil
      if let bootstrapModel {
        await bootstrapModel.stop()
      }
      isSwitchingMode = false
    }

    private func modeDidChange(from previousMode: RecipesV3DemoMode) {
      guard !isCorrectingMode, mode != previousMode else { return }
      guard configuration.allowsModeSelection, !isSwitchingMode else {
        restoreMode(previousMode)
        return
      }

      let requestedMode = mode
      let requestedConfiguration: RecipesV3AppConfiguration
      do {
        requestedConfiguration = try configuration.appConfiguration(
          for: requestedMode
        )
      } catch {
        restoreMode(previousMode)
        return
      }
      let previousBootstrap = bootstrapModel
      modeStorage.save(requestedMode)
      bootstrapModel = nil
      isSwitchingMode = true

      transitionTask = Task { @MainActor [weak self, previousBootstrap] in
        if let previousBootstrap {
          await previousBootstrap.stop()
        }
        guard !Task.isCancelled, let self else { return }
        guard self.mode == requestedMode else {
          self.isSwitchingMode = false
          return
        }
        self.bootstrapModel = RecipesV3BootstrapModel(
          configuration: requestedConfiguration,
          configureDependencies: self.configureDependencies
        )
        self.isSwitchingMode = false
        self.transitionTask = nil
      }
    }

    private func restoreMode(_ mode: RecipesV3DemoMode) {
      isCorrectingMode = true
      self.mode = mode
      isCorrectingMode = false
    }

  }

  extension RecipesV3SyncRoute {
    fileprivate var isDesertRequired: Bool {
      if case .desertRequired = self { return true }
      return false
    }

    var visibleRecipes: [InstantRecipeV3] {
      InstantRecipeV3.allCases
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct RecipesV3DemoScreen: View {
    public let model: RecipesV3DemoModel

    public init(model: RecipesV3DemoModel) {
      self.model = model
    }

    public var body: some View {
      VStack(spacing: 0) {
        if let bootstrapModel = model.bootstrapModel {
          RecipesV3ObservedModeBar(
            model: model,
            bootstrapModel: bootstrapModel
          )
          RecipesV3BootstrapScreen(
            model: bootstrapModel,
            showsTransportStatus: false
          )
          .id(ObjectIdentifier(bootstrapModel))
        } else {
          RecipesV3ModeBar(
            model: model,
            connectionStatus: nil,
            errorMessage: nil
          )
          ProgressView("Switching sync mode")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  private struct RecipesV3ObservedModeBar: View {
    @Bindable var model: RecipesV3DemoModel
    @ObservedObject var bootstrapModel: RecipesV3BootstrapModel

    var body: some View {
      RecipesV3ModeBar(
        model: model,
        connectionStatus: bootstrapModel.connectionStatus,
        errorMessage: bootstrapModel.errorMessage
      )
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  private struct RecipesV3ModeBar: View {
    @Bindable var model: RecipesV3DemoModel
    let connectionStatus: InstantConnectionStatus?
    let errorMessage: String?

    var body: some View {
      HStack(spacing: 12) {
        Label(statusTitle, systemImage: statusSymbol)
        .foregroundStyle(statusColor)
        .lineLimit(2)
        .accessibilityIdentifier("recipes-v3-transport-status")
        Spacer(minLength: 8)
        Toggle("Desert", isOn: $model.mode.isDesert)
        .disabled(!model.allowsModeSelection)
        .accessibilityLabel("Desert mode")
        .accessibilityValue(model.mode.title)
        .accessibilityHint(modeControlHint)
        .accessibilityIdentifier("recipes-v3-mode-toggle")
      }
      .font(.caption)
      .padding(.horizontal)
      .padding(.vertical, 8)
      #if os(tvOS) || os(watchOS)
        .background(Color.black.opacity(0.2))
      #else
        .background(.bar)
      #endif
    }

    private var route: RecipesV3SyncRoute? {
      model.activeConfiguration?.syncRoute
    }

    private var statusTitle: String {
      if model.isSwitchingMode {
        return "\(routeTitle) · Switching"
      }
      if errorMessage != nil {
        return "\(routeTitle) · Error"
      }
      guard let route else {
        return "Sync mode unavailable"
      }
      if route == .localOnly {
        return route.statusTitle
      }
      guard let connectionStatus else {
        return "\(route.statusTitle) · Opening"
      }
      switch connectionStatus.state {
      case .opened, .authenticated:
        return "\(route.statusTitle) · Connected"
      case .connecting:
        return "\(route.statusTitle) · Connecting"
      case .closed:
        return "\(route.statusTitle) · Closed"
      case .errored:
        return "\(route.statusTitle) · Error"
      }
    }

    private var statusSymbol: String {
      if model.isSwitchingMode { return "arrow.triangle.2.circlepath" }
      if errorMessage != nil || route == nil {
        return "exclamationmark.triangle.fill"
      }
      if route == .localOnly { return "externaldrive" }
      if connectionStatus?.state == .errored || connectionStatus?.state == .closed {
        return "exclamationmark.triangle.fill"
      }
      if connectionStatus == nil || connectionStatus?.state == .connecting {
        return "arrow.triangle.2.circlepath"
      }
      return "bolt.horizontal.circle.fill"
    }

    private var statusColor: Color {
      if model.isSwitchingMode || route == .localOnly { return .secondary }
      if errorMessage != nil || route == nil
        || connectionStatus?.state == .errored
        || connectionStatus?.state == .closed
      {
        return .red
      }
      if connectionStatus == nil || connectionStatus?.state == .connecting {
        return .secondary
      }
      return .green
    }

    private var routeTitle: String {
      model.activeConfiguration?.syncRoute.statusTitle ?? "Sync mode unavailable"
    }

    private var modeControlHint: String {
      if model.isSwitchingMode {
        return "Wait for the current sync mode change to finish."
      }
      if model.configuration.forcedMode != nil {
        return "The sync mode is fixed by the launch configuration."
      }
      if model.configuration.desert == nil {
        return "Interactive Desert mode is available in the macOS and iOS Simulator demos."
      }
      return "Switches every recipe between its normal route and the required Desert route."
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct RecipesV3BootstrapScreen: View {
    @ObservedObject private var model: RecipesV3BootstrapModel
    private let showsTransportStatus: Bool

    public init(
      model: RecipesV3BootstrapModel,
      showsTransportStatus: Bool = true
    ) {
      self.model = model
      self.showsTransportStatus = showsTransportStatus
    }

    public var body: some View {
      Group {
        if let errorMessage = model.errorMessage {
          VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
              .font(.largeTitle)
            Text("Could not open Instant Recipes")
              .font(.headline)
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding()
          .accessibilityIdentifier("recipes-v3-bootstrap-error")
        } else if let client = model.client {
          RecipesV3CatalogScreen(
            profileID: model.configuration.profileID,
            launchRecipe: model.configuration.launchRecipe,
            syncRoute: model.configuration.syncRoute,
            connectionStatus: model.connectionStatus,
            showsTransportStatus: showsTransportStatus
          )
          .dependency(\.defaultInstantSwiftData, client)
        } else {
          ProgressView("Opening Instant Recipes")
        }
      }
      .task { model.startIfNeeded() }
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct RecipesV3CatalogScreen: View {
    @State private var path: [InstantRecipeV3]
    private let profileID: String
    private let syncRoute: RecipesV3SyncRoute
    private let connectionStatus: InstantConnectionStatus?
    private let showsTransportStatus: Bool

    public init(
      profileID: String,
      launchRecipe: InstantRecipeV3? = nil,
      isLive: Bool = false
    ) {
      self.init(
        profileID: profileID,
        launchRecipe: launchRecipe,
        syncRoute: isLive ? .cloud : .localOnly
      )
    }

    public init(
      profileID: String,
      launchRecipe: InstantRecipeV3? = nil,
      syncRoute: RecipesV3SyncRoute,
      connectionStatus: InstantConnectionStatus? = nil,
      showsTransportStatus: Bool = true
    ) {
      self.profileID = profileID
      self.syncRoute = syncRoute
      self.connectionStatus = connectionStatus
      self.showsTransportStatus = showsTransportStatus
      _path = State(initialValue: launchRecipe.map { [$0] } ?? [])
    }

    public var body: some View {
      #if os(watchOS)
        catalogNavigation
      #else
        if showsTransportStatus {
          VStack(spacing: 0) {
            transportStatusBanner
            catalogNavigation
          }
        } else {
          catalogNavigation
        }
      #endif
    }

    private var catalogNavigation: some View {
      NavigationStack(path: $path) {
        #if os(watchOS)
          List {
            if showsTransportStatus {
              Section {
                Label(
                  syncRoute.statusTitle,
                  systemImage: syncRoute == .localOnly
                    ? "externaldrive"
                    : "bolt.horizontal.circle.fill"
                )
                .foregroundStyle(syncRoute == .localOnly ? Color.secondary : Color.green)
              }
            }

            ForEach(syncRoute.visibleRecipes) { recipe in
              NavigationLink(value: recipe) {
                Label(recipe.title, systemImage: recipe.systemImage)
              }
            }
          }
          .navigationTitle("Recipes")
          .navigationDestination(for: InstantRecipeV3.self) { recipe in
            RecipesV3RecipeScreen(
              recipe: recipe,
              profileID: profileID,
              syncRoute: syncRoute
            )
          }
        #else
          List {
            Section {
              ForEach(syncRoute.visibleRecipes) { recipe in
                NavigationLink(value: recipe) {
                  VStack(alignment: .leading, spacing: 4) {
                    Label(recipe.title, systemImage: recipe.systemImage)
                      .font(.headline)
                    Text(recipe.summary)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
          .navigationTitle("Instant Recipes")
          .navigationDestination(for: InstantRecipeV3.self) { recipe in
            RecipesV3RecipeScreen(
              recipe: recipe,
              profileID: profileID,
              syncRoute: syncRoute
            )
          }
        #endif
      }
    }

    #if !os(watchOS)
      private var transportStatusBanner: some View {
        HStack {
          Label(
            statusTitle,
            systemImage: statusSymbol
          )
          .foregroundStyle(statusColor)
          Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        #if os(tvOS)
          .background(Color.black.opacity(0.2))
        #else
          .background(.bar)
        #endif
        .accessibilityIdentifier("recipes-v3-transport-status")
      }
    #endif

    private var statusTitle: String {
      guard syncRoute.isDesertRequired, let connectionStatus else {
        return syncRoute.statusTitle
      }
      switch connectionStatus.state {
      case .opened, .authenticated:
        return "\(syncRoute.statusTitle) · Connected"
      case .connecting:
        return "\(syncRoute.statusTitle) · Connecting"
      case .closed:
        return "\(syncRoute.statusTitle) · Closed"
      case .errored:
        return "\(syncRoute.statusTitle) · Error"
      }
    }

    private var statusSymbol: String {
      if syncRoute == .localOnly { return "externaldrive" }
      if connectionStatus?.state == .errored || connectionStatus?.state == .closed {
        return "exclamationmark.triangle.fill"
      }
      return "bolt.horizontal.circle.fill"
    }

    private var statusColor: Color {
      if syncRoute == .localOnly { return .secondary }
      if connectionStatus?.state == .errored || connectionStatus?.state == .closed {
        return .red
      }
      return .green
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct RecipesV3RecipeScreen: View {
    public var recipe: InstantRecipeV3
    public var profileID: String
    public var syncRoute: RecipesV3SyncRoute

    public init(
      recipe: InstantRecipeV3,
      profileID: String,
      syncRoute: RecipesV3SyncRoute = .localOnly
    ) {
      self.recipe = recipe
      self.profileID = profileID
      self.syncRoute = syncRoute
    }

    @ViewBuilder
    public var body: some View {
      switch recipe {
      case .todos:
        TodosScreen(wrapsInNavigationStack: false)
      case .cursors:
        CursorsV3Screen(profileID: profileID)
      case .customCursors:
        CustomCursorsV3Screen(
          profileID: profileID,
          name: String(profileID.prefix(8))
        )
      case .reactions:
        ReactionsV3Screen()
      case .typingIndicator:
        TypingIndicatorV3Screen(
          roomID: "1234",
          profileID: profileID,
          options: TypingIndicatorV3Options(stopOnSubmit: true)
        )
      case .avatarStack:
        AvatarStackV3Screen(profileID: profileID)
      case .mergeTileGame:
        MergeTileGameV3Screen(profileID: profileID)
      case .auth:
        AuthV3LoginScreen(
          allowsExternalProviders: syncRoute.allowsExternalAuthProviders
        )
      }
    }
  }
#endif
