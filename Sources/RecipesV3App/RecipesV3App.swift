import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData
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

public enum RecipesV3ConfigurationError: Error, Equatable, Sendable {
  case missingValue(String)
  case invalidValue(key: String, value: String, expected: String)
  case unsupportedDesertRecipe(String)
}

extension RecipesV3ConfigurationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingValue(let key):
      "Desert mode requires \(key)."
    case .invalidValue(let key, let value, let expected):
      "Invalid \(key) value ‘\(value)’; expected \(expected)."
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
    let configuredAppID = normalizedConfigurationValue(
      environment["INSTANT_APP_ID"]
        ?? launchOption("--instant-app-id", in: arguments)
        ?? infoDictionary["InstantAppID"] as? String
    )
    let recipeName =
      normalizedConfigurationValue(environment["INSTANT_RECIPE"])
      ?? launchRecipeName(in: arguments)
    return Self(
      appID: configuredAppID ?? "recipes-v3-local",
      persistenceURL: normalizedConfigurationValue(
        environment["INSTANT_PERSISTENCE_PATH"]
          ?? launchOption("--persistence-path", in: arguments)
      )
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
    let configuredAppID = normalizedConfigurationValue(
      environment["INSTANT_APP_ID"]
        ?? launchOption("--instant-app-id", in: arguments)
        ?? infoDictionary["InstantAppID"] as? String
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
      persistenceURL: normalizedConfigurationValue(
        environment["INSTANT_PERSISTENCE_PATH"]
          ?? launchOption("--persistence-path", in: arguments)
      )
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

  private static func normalizedConfigurationValue(_ value: String?) -> String? {
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
    let configuredRoute = normalizedConfigurationValue(
      environment["INSTANT_SWIFT_DATA_SYNC_ROUTE"]
        ?? launchOption("--sync-route", in: arguments)
    )

    switch configuredRoute {
    case nil, "current":
      return configuredAppID == nil ? .localOnly : .cloud

    case "desert-required":
      guard configuredAppID != nil else {
        throw RecipesV3ConfigurationError.missingValue("INSTANT_APP_ID")
      }
      let roleValue = normalizedConfigurationValue(
        environment["INSTANT_DESERT_ROLE"]
          ?? launchOption("--desert-role", in: arguments)
      )
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

      guard
        let host = normalizedConfigurationValue(
          environment["INSTANT_DESERT_HOST"]
            ?? launchOption("--desert-host", in: arguments)
        )
      else {
        throw RecipesV3ConfigurationError.missingValue("INSTANT_DESERT_HOST")
      }

      let portValue = normalizedConfigurationValue(
        environment["INSTANT_DESERT_PORT"]
          ?? launchOption("--desert-port", in: arguments)
      )
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
      return .desertRequired(
        RecipesV3DesertEndpoint(role: role, host: host, port: port)
      )

    case let configuredRoute?:
      throw RecipesV3ConfigurationError.invalidValue(
        key: "INSTANT_SWIFT_DATA_SYNC_ROUTE",
        value: configuredRoute,
        expected: "current or desert-required"
      )
    }
  }

  private static func launchOption(_ name: String, in arguments: [String]) -> String? {
    guard let optionIndex = arguments.lastIndex(of: name) else { return nil }
    let valueIndex = arguments.index(after: optionIndex)
    guard arguments.indices.contains(valueIndex) else { return nil }
    return normalizedConfigurationValue(arguments[valueIndex])
  }

  private static func launchRecipeName(in arguments: [String]) -> String? {
    launchOption("--recipe", in: arguments)
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
    private var statusTask: Task<Void, Never>?
    private var task: Task<Void, Never>?

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
      self.errorMessage = String(describing: configurationError)
    }

    public func startIfNeeded() {
      guard canStart, client == nil, task == nil else { return }
      task = Task { @MainActor [weak self, configuration] in
        var startedDesertHost: InstantNetworkDesertHost?
        do {
          var dependencies = DependencyValues()
          self?.configureDependencies(&dependencies)
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
          let status: InstantConnectionStatus
          switch configuration.syncRoute {
          case .desertRequired:
            status = try await client.connect()
          case .localOnly, .cloud:
            status = try await client.connectionStatus()
          }
          prepareDependencies { $0.defaultInstantSwiftData = client }
          self?.desertHost = startedDesertHost
          self?.connectionStatus = status
          self?.client = client
          self?.errorMessage = nil
          self?.observeConnectionStatus(
            client: client,
            requiresHealthyConnection: configuration.syncRoute.isDesertRequired
          )
          self?.task = nil
        } catch {
          if let startedDesertHost {
            await startedDesertHost.stop()
          }
          self?.errorMessage = String(describing: error)
          self?.task = nil
        }
      }
    }

    private func observeConnectionStatus(
      client: InstantSwiftDataClient,
      requiresHealthyConnection: Bool
    ) {
      statusTask?.cancel()
      statusTask = Task { @MainActor [weak self, client] in
        do {
          let statuses = try await client.observeConnectionStatus()
          for await status in statuses {
            guard let self else { return }
            self.connectionStatus = status
            if requiresHealthyConnection, status.state == .errored || status.state == .closed {
              self.errorMessage =
                status.lastErrorMessage
                ?? "The required Desert connection is no longer available."
            }
          }
        } catch is CancellationError {
        } catch {
          if requiresHealthyConnection {
            self?.errorMessage = String(describing: error)
          }
        }
      }
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
  public struct RecipesV3BootstrapScreen: View {
    @StateObject private var model: RecipesV3BootstrapModel

    public init(model: RecipesV3BootstrapModel) {
      _model = StateObject(wrappedValue: model)
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
        } else if model.client != nil {
          RecipesV3CatalogScreen(
            profileID: model.configuration.profileID,
            launchRecipe: model.configuration.launchRecipe,
            syncRoute: model.configuration.syncRoute,
            connectionStatus: model.connectionStatus
          )
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
      connectionStatus: InstantConnectionStatus? = nil
    ) {
      self.profileID = profileID
      self.syncRoute = syncRoute
      self.connectionStatus = connectionStatus
      _path = State(initialValue: launchRecipe.map { [$0] } ?? [])
    }

    public var body: some View {
      NavigationStack(path: $path) {
        #if os(watchOS)
          List {
            Section {
              Label(
                syncRoute.statusTitle,
                systemImage: syncRoute == .localOnly
                  ? "externaldrive"
                  : "bolt.horizontal.circle.fill"
              )
              .foregroundStyle(syncRoute == .localOnly ? Color.secondary : Color.green)
            }

            ForEach(syncRoute.visibleRecipes) { recipe in
              NavigationLink(value: recipe) {
                Label(recipe.title, systemImage: recipe.systemImage)
              }
            }
          }
          .navigationTitle("Recipes")
          .navigationDestination(for: InstantRecipeV3.self) { recipe in
            RecipesV3RecipeScreen(recipe: recipe, profileID: profileID)
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
            RecipesV3RecipeScreen(recipe: recipe, profileID: profileID)
          }
        #endif
      }
      #if !os(watchOS)
        .safeAreaInset(edge: .top, spacing: 0) {
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
          .background(.bar)
        }
      #endif
    }

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

    public init(recipe: InstantRecipeV3, profileID: String) {
      self.recipe = recipe
      self.profileID = profileID
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
        AuthV3LoginScreen()
      }
    }
  }
#endif
