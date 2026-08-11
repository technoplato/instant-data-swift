import Dependencies
import Foundation
import InstantSwiftData

public struct TranscriptionAppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public static let localAppID = "transcription-local"

  public init(appID: String, persistenceURL: URL? = nil, enablesLiveSync: Bool) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configured = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let appID = configured.flatMap { $0.isEmpty ? nil : $0 } ?? Self.localAppID
    return Self(
      appID: appID,
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configured?.isEmpty == false
    )
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class TranscriptionBootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: TranscriptionAppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: TranscriptionAppConfiguration) {
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
            initialAttributes:
              Recording.instantAttributes
              + Transcription.instantAttributes
              + Segment.instantAttributes
              + Preference.instantAttributes
          )
          let client = dependencies.defaultInstantSwiftData
          prepareDependencies { $0.defaultInstantSwiftData = client }
          // Seed singleton preference once (idempotent enough for local demo).
          client.send(EnsurePreference())
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
  @available(iOS 17.0, macOS 14.0, *)
  public struct TranscriptionBootstrapScreen: View {
    @StateObject private var model: TranscriptionBootstrapModel

    public init(model: TranscriptionBootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if let client = model.client {
          TranscriptionRootScreen()
            .dependency(\.defaultInstantSwiftData, client)
        } else if let errorMessage = model.errorMessage {
          ContentUnavailableView(
            "Bootstrap failed",
            systemImage: "exclamationmark.triangle",
            description: Text(errorMessage)
          )
        } else {
          ProgressView("Opening Transcription")
        }
      }
      .task { model.startIfNeeded() }
    }
  }
#endif
