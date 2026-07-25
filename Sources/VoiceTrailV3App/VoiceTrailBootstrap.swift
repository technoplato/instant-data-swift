import Dependencies
import Foundation
import InstantSwiftData

public struct VoiceTrailAppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool
  public var userIDOverride: InstantID<VoiceTrailUser>?
  public var refreshTokenOverride: String?
  public var isDemoMode: Bool

  public init(
    appID: String,
    persistenceURL: URL? = nil,
    enablesLiveSync: Bool,
    userIDOverride: InstantID<VoiceTrailUser>? = nil,
    refreshTokenOverride: String? = nil,
    isDemoMode: Bool = false
  ) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
    self.userIDOverride = userIDOverride
    self.refreshTokenOverride = refreshTokenOverride
    self.isDemoMode = isDemoMode
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    bundledAppID: String? = Bundle.main.object(forInfoDictionaryKey: "InstantAppID") as? String,
    bundledDemoMode: Bool = Bundle.main.object(forInfoDictionaryKey: "VoiceTrailDemoMode")
      as? Bool ?? false
  ) -> Self {
    let isDemoMode = environment["VOICE_TRAIL_DEMO_MODE"] == "1" || bundledDemoMode
    let configuredAppID = [environment["INSTANT_APP_ID"], bundledAppID]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    let configuredUserID = environment["VOICE_TRAIL_USER_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let configuredRefreshToken = environment["VOICE_TRAIL_REFRESH_TOKEN"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Self(
      appID: isDemoMode ? "voicetrail-v3-watch-demo" : configuredAppID ?? "voicetrail-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: !isDemoMode && configuredAppID != nil,
      userIDOverride: isDemoMode
        ? VoiceTrailWatchDemo.userID
        : configuredUserID.flatMap { $0.isEmpty ? nil : InstantID(rawValue: $0) },
      refreshTokenOverride: isDemoMode
        ? VoiceTrailWatchDemo.refreshToken
        : configuredRefreshToken.flatMap { $0.isEmpty ? nil : $0 },
      isDemoMode: isDemoMode
    )
  }
}

public enum VoiceTrailWatchDemo {
  public static let userID = InstantID<VoiceTrailUser>(rawValue: "voicetrail-watch-demo-user")
  public static let refreshToken = "voicetrail-watch-demo-refresh"
}

public struct VoiceTrailAppBootstrapper: Sendable {
  public var bootstrap:
    @Sendable (VoiceTrailAppConfiguration) async throws
      -> InstantSwiftDataClient

  public init(
    bootstrap: @escaping @Sendable (VoiceTrailAppConfiguration) async throws
      -> InstantSwiftDataClient
  ) {
    self.bootstrap = bootstrap
  }

  public static var live: Self {
    Self { configuration in
      var dependencies = DependencyValues()
      if configuration.enablesLiveSync {
        dependencies.instantLiveTransport = .live
      } else {
        dependencies.instantMagicCodeExchange = .local
        dependencies.instantRefreshTokenVerifier = .local
        dependencies.instantGuestAuthenticator = .local
        dependencies.instantAuthTokenInvalidator = .local
      }
      try await dependencies.bootstrapInstantSwiftData(
        appID: configuration.appID,
        persistenceURL: configuration.persistenceURL,
        initialAttributes: VoiceTrailSchema.attributes,
        liveShareContract: .v3CaptureRecordings
      )
      let client = dependencies.defaultInstantSwiftData
      if let refreshToken = configuration.refreshTokenOverride {
        _ = try await client.signInWithRefreshToken(
          refreshToken,
          userID: configuration.userIDOverride?.rawValue
        )
      }
      return client
    }
  }
}

public enum VoiceTrailBootstrapPhase: Hashable, Sendable {
  case idle
  case loading
  case ready
  case failed(String)
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class VoiceTrailBootstrapModel: ObservableObject {
    @Published public private(set) var phase: VoiceTrailBootstrapPhase = .idle

    public let configuration: VoiceTrailAppConfiguration
    private let bootstrapper: VoiceTrailAppBootstrapper
    private var task: Task<Void, Never>?

    public init(
      configuration: VoiceTrailAppConfiguration,
      bootstrapper: VoiceTrailAppBootstrapper = .live
    ) {
      self.configuration = configuration
      self.bootstrapper = bootstrapper
    }

    public func startIfNeeded() {
      guard phase == .idle else { return }
      phase = .loading
      task = Task { @MainActor [weak self, bootstrapper, configuration] in
        do {
          let client = try await bootstrapper.bootstrap(configuration)
          try Task.checkCancellation()
          guard let self else { return }
          prepareDependencies {
            $0.defaultInstantSwiftData = client
          }
          self.phase = .ready
          self.task = nil
        } catch is CancellationError {
          self?.phase = .idle
          self?.task = nil
        } catch {
          self?.phase = .failed(String(describing: error))
          self?.task = nil
        }
      }
    }

    public func retryButtonTapped() {
      task?.cancel()
      task = nil
      phase = .idle
      startIfNeeded()
    }
  }

  @MainActor
  public struct VoiceTrailBootstrapScreen: View {
    @StateObject private var model: VoiceTrailBootstrapModel

    public init(model: VoiceTrailBootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        switch model.phase {
        case .idle, .loading:
          ProgressView("Opening VoiceTrail")
        case .ready:
          #if os(watchOS)
            VoiceTrailWatchRootScreen(
              injectedUserID: model.configuration.userIDOverride,
              isDemoMode: model.configuration.isDemoMode,
              usesLocalStoreOnly: !model.configuration.enablesLiveSync
            )
          #else
            VoiceTrailRootScreen()
          #endif
        case let .failed(message):
          VStack {
            Text("VoiceTrail could not start")
            Text(message).font(.caption)
            Button("Retry", action: model.retryButtonTapped)
          }
        }
      }
      .task { model.startIfNeeded() }
    }
  }
#endif
