import Dependencies
import Foundation
import InstantSwiftData

public struct RemindersV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public init(appID: String, persistenceURL: URL? = nil, enablesLiveSync: Bool) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configuredAppID = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Self(
      appID: configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "reminders-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
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
            initialAttributes: RemindersV3Schema.attributes
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
  public struct RemindersV3BootstrapScreen: View {
    @StateObject private var model: RemindersV3BootstrapModel

    public init(model: RemindersV3BootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if model.client != nil {
          RemindersV3Screen()
        } else if let errorMessage = model.errorMessage {
          Text(errorMessage)
        } else {
          ProgressView("Opening Reminders")
        }
      }
      .task { model.startIfNeeded() }
    }
  }
#endif
