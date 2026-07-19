import Dependencies
import Foundation
import InstantSwiftData

public struct VoiceTrailAppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public init(
    appID: String,
    persistenceURL: URL? = nil,
    enablesLiveSync: Bool
  ) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configuredAppID = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let appID = configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "voicetrail-v3-local"
    return Self(
      appID: appID,
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
    )
  }
}

public struct VoiceTrailAppBootstrapper: Sendable {
  public var bootstrap: @Sendable (VoiceTrailAppConfiguration) async throws
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
      }
      try await dependencies.bootstrapInstantSwiftData(
        appID: configuration.appID,
        persistenceURL: configuration.persistenceURL,
        initialAttributes: VoiceTrailSchema.attributes,
        liveShareContract: .v3CaptureRecordings
      )
      return dependencies.defaultInstantSwiftData
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
          VoiceTrailRootScreen()
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
