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

public struct RecipesV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool
  public var profileID: String
  public var launchRecipe: InstantRecipeV3?

  public init(
    appID: String,
    persistenceURL: URL? = nil,
    enablesLiveSync: Bool,
    profileID: String,
    launchRecipe: InstantRecipeV3? = nil
  ) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
    self.profileID = profileID
    self.launchRecipe = launchRecipe
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    makeProfileID: () -> String = { UUID().uuidString.lowercased() }
  ) -> Self {
    let configuredAppID = normalizedConfigurationValue(
      environment["INSTANT_APP_ID"] ?? infoDictionary["InstantAppID"] as? String
    )
    let recipeName = normalizedConfigurationValue(environment["INSTANT_RECIPE"])
      ?? launchRecipeName(in: arguments)
    return Self(
      appID: configuredAppID ?? "recipes-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID != nil,
      profileID: normalizedConfigurationValue(environment["INSTANT_RECIPE_PROFILE_ID"])
        ?? makeProfileID(),
      launchRecipe: recipeName.flatMap(InstantRecipeV3.init(pathName:))
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

  private static func launchRecipeName(in arguments: [String]) -> String? {
    guard let optionIndex = arguments.lastIndex(of: "--recipe") else { return nil }
    let valueIndex = arguments.index(after: optionIndex)
    guard arguments.indices.contains(valueIndex) else { return nil }
    return normalizedConfigurationValue(arguments[valueIndex])
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class RecipesV3BootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: RecipesV3AppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: RecipesV3AppConfiguration) {
      self.configuration = configuration
    }

    public func startIfNeeded() {
      guard client == nil, task == nil else { return }
      task = Task { @MainActor [weak self, configuration] in
        do {
          var dependencies = DependencyValues()
          if configuration.enablesLiveSync {
            dependencies.instantLiveTransport = .live
          }
          try await dependencies.bootstrapInstantSwiftData(
            appID: configuration.appID,
            persistenceURL: configuration.persistenceURL,
            initialAttributes: RecipesV3AppConfiguration.initialAttributes
          )
          let client = dependencies.defaultInstantSwiftData
          prepareDependencies { $0.defaultInstantSwiftData = client }
          self?.client = client
          self?.task = nil
        } catch {
          self?.errorMessage = String(describing: error)
          self?.task = nil
        }
      }
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
        if model.client != nil {
          RecipesV3CatalogScreen(
            profileID: model.configuration.profileID,
            launchRecipe: model.configuration.launchRecipe,
            isLive: model.configuration.enablesLiveSync
          )
        } else if let errorMessage = model.errorMessage {
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
    private let isLive: Bool

    public init(
      profileID: String,
      launchRecipe: InstantRecipeV3? = nil,
      isLive: Bool = false
    ) {
      self.profileID = profileID
      self.isLive = isLive
      _path = State(initialValue: launchRecipe.map { [$0] } ?? [])
    }

    public var body: some View {
      NavigationStack(path: $path) {
        #if os(watchOS)
          List {
            Section {
              Label(
                isLive ? "Connected" : "Local only",
                systemImage: isLive ? "bolt.horizontal.circle.fill" : "externaldrive"
              )
              .foregroundStyle(isLive ? .green : .secondary)
            }

            ForEach(InstantRecipeV3.allCases) { recipe in
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
            Label(
              isLive ? "Connected to InstantDB" : "Local data only",
              systemImage: isLive ? "bolt.horizontal.circle.fill" : "externaldrive"
            )
            .foregroundStyle(isLive ? .green : .secondary)
          }

          Section {
            ForEach(InstantRecipeV3.allCases) { recipe in
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
