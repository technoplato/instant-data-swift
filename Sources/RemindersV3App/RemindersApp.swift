import Dependencies
import Foundation
import InstantSwiftData

public struct RemindersV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool
  public var userIDOverride: InstantID<RemindersV3User>?
  public var refreshTokenOverride: String?

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    persistenceURL: URL? = nil,
    enablesLiveSync: Bool,
    userIDOverride: InstantID<RemindersV3User>? = nil,
    refreshTokenOverride: String? = nil
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
    self.userIDOverride = userIDOverride
    self.refreshTokenOverride = refreshTokenOverride
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment,
    bundledAppID: String? = Bundle.main.object(forInfoDictionaryKey: "InstantAppID") as? String,
    bundledUserID: String? = Bundle.main.object(forInfoDictionaryKey: "RemindersUserID") as? String
  ) -> Self {
    let configuredAppID = [environment["INSTANT_APP_ID"], bundledAppID]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    return Self(
      appID: configuredAppID ?? "reminders-v3-local",
      apiURI: environment["INSTANT_API_URI"]
        .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        ?? InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: environment["INSTANT_WEBSOCKET_URI"]
        .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        ?? InstantRuntimeConfiguration.defaultWebSocketURI,
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID != nil,
      userIDOverride: [environment["REMINDERS_V3_USER_ID"], bundledUserID]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        .map(InstantID.init(rawValue:)),
      refreshTokenOverride: environment["REMINDERS_V3_REFRESH_TOKEN"]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }
    )
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class RemindersV3BootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: RemindersV3AppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: RemindersV3AppConfiguration) {
      self.configuration = configuration
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "reminders-v3",
        category: "bootstrap",
        event: "bootstrap.model-created",
        message: "Created the Reminders bootstrap model.",
        metadata: [
          "appID": configuration.appID,
          "liveSync": String(configuration.enablesLiveSync),
          "apiHost": configuration.apiURI.host ?? "none",
          "websocketHost": configuration.websocketURI.host ?? "none",
          "persistencePath": configuration.persistenceURL?.path ?? "default",
          "usesUserOverride": String(configuration.userIDOverride != nil),
          "usesRefreshTokenOverride": String(configuration.refreshTokenOverride != nil),
        ]
      )
    }

    public func startIfNeeded() {
      guard client == nil, task == nil else {
        InstantDiagnostics.shared.record(
          .trace,
          subsystem: "reminders-v3",
          category: "bootstrap",
          event: "bootstrap.start-skipped",
          message: "Skipped duplicate bootstrap request.",
          metadata: [
            "hasClient": String(client != nil),
            "hasTask": String(task != nil),
          ]
        )
        return
      }
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "bootstrap",
        event: "bootstrap.started",
        message: "Starting the Reminders data stack.",
        metadata: [
          "appID": configuration.appID,
          "liveSync": String(configuration.enablesLiveSync),
        ]
      )
      task = Task { @MainActor [weak self, configuration] in
        do {
          var dependencies = DependencyValues()
          if configuration.enablesLiveSync {
            dependencies.instantLiveTransport = .live
          }
          try await dependencies.bootstrapInstantSwiftData(
            appID: configuration.appID,
            apiURI: configuration.apiURI,
            websocketURI: configuration.websocketURI,
            persistenceURL: configuration.persistenceURL,
            initialAttributes: RemindersV3Schema.attributes
          )
          let client = dependencies.defaultInstantSwiftData
          if let refreshToken = configuration.refreshTokenOverride {
            _ = try await client.signInWithRefreshToken(
              refreshToken,
              userID: configuration.userIDOverride?.rawValue
            )
          }
          prepareDependencies { $0.defaultInstantSwiftData = client }
          self?.client = client
          self?.task = nil
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "bootstrap",
            event: "bootstrap.completed",
            message: "Reminders data stack is ready.",
            metadata: [
              "appID": configuration.appID,
              "liveSync": String(configuration.enablesLiveSync),
              "hasRuntime": String(client.runtime != nil),
            ]
          )
        } catch {
          self?.errorMessage = String(describing: error)
          self?.task = nil
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "bootstrap",
            event: "bootstrap.failed",
            message: "Reminders data stack failed to start.",
            metadata: ["appID": configuration.appID]
          )
        }
      }
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct RemindersV3BootstrapScreen: View {
    @StateObject private var model: RemindersV3BootstrapModel

    public init(model: RemindersV3BootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if model.client != nil {
          if let userID = model.configuration.userIDOverride {
            RemindersV3Screen(userID: userID)
          } else {
            RemindersV3Screen()
          }
        } else if let errorMessage = model.errorMessage {
          Text(errorMessage)
        } else {
          ProgressView("Opening Reminders")
        }
      }
      .task { model.startIfNeeded() }
      .onAppear {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "ui",
          event: "bootstrap-screen.appeared",
          message: "Bootstrap screen appeared."
        )
      }
      .onDisappear {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "ui",
          event: "bootstrap-screen.disappeared",
          message: "Bootstrap screen disappeared."
        )
      }
    }
  }
#endif
