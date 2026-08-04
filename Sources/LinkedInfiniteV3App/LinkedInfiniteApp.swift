import Dependencies
import Foundation
import InstantSwiftData

public struct LinkedInfiniteAppConfiguration: Hashable, Sendable {
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
    let appID = configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "linked-infinite-v3-local"
    return Self(
      appID: appID,
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
    )
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class LinkedInfiniteBootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: LinkedInfiniteAppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: LinkedInfiniteAppConfiguration) {
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
            initialAttributes: LinkedInfiniteSeed.instantAttributes
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
  @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
  public struct LinkedInfiniteBootstrapScreen: View {
    @StateObject private var model: LinkedInfiniteBootstrapModel

    public init(model: LinkedInfiniteBootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if model.client != nil {
          LinkedInfiniteScreen()
        } else if let errorMessage = model.errorMessage {
          Text(errorMessage)
        } else {
          ProgressView("Opening Linked Infinite")
        }
      }
      .task { model.startIfNeeded() }
    }
  }

  /// Demonstrates one infinite root with linked children for list metrics.
  @MainActor
  @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
  public struct LinkedInfiniteScreen: View {
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var rows: [LinkedInfiniteListRow] = []
    @State private var phase: InfiniteQueryPhase = .idleEmpty
    @State private var message = ""
    @State private var subscription: InstantInfiniteQuerySubscription?
    private let wrapsInNavigationStack: Bool
    private let pageSize: Int

    public init(wrapsInNavigationStack: Bool = true, pageSize: Int = 3) {
      self.wrapsInNavigationStack = wrapsInNavigationStack
      self.pageSize = pageSize
    }

    public var body: some View {
      Group {
        if wrapsInNavigationStack {
          NavigationStack { content }
        } else {
          content
        }
      }
      .task { await startObservation() }
      .onDisappear { subscription?.unsubscribe() }
    }

    private var content: some View {
      List {
        Section {
          Button("Seed sample recordings", action: seedButtonTapped)
          Button("Load next page", action: loadNextPageButtonTapped)
            .disabled(!canLoadNextPage)
        }

        Section("Recordings (\(rows.count)) · \(phaseLabel)") {
          ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 4) {
              Text(row.title)
                .font(.headline)
              Text("\(row.wordCount) words")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .onAppear {
              if row.id == rows.last?.id {
                loadNextPageButtonTapped()
              }
            }
          }

          switch phase {
          case .loadingFirstPage:
            ProgressView("Loading recordings…")
          case .loadingNextPage:
            ProgressView("Loading older recordings…")
          case .failed(let error, _):
            Text(error.message)
              .foregroundStyle(.red)
          case .idleEmpty, .loaded:
            EmptyView()
          }
        }

        if !message.isEmpty {
          Section {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Linked Infinite")
    }

    private var canLoadNextPage: Bool {
      switch phase {
      case .loaded(canLoadNextPage: true):
        return true
      default:
        return false
      }
    }

    private var phaseLabel: String {
      switch phase {
      case .idleEmpty: "idle"
      case .loadingFirstPage: "loading first"
      case .loaded(let canLoad): canLoad ? "loaded · more" : "loaded · end"
      case .loadingNextPage: "loading next"
      case .failed: "failed"
      }
    }

    private func startObservation() async {
      subscription?.unsubscribe()
      phase = .loadingFirstPage
      let query = LinkedInfiniteListRow.pageQuery(pageSize: pageSize)
      let subscription = await db.subscribeInfiniteQuery(query.plan)
      self.subscription = subscription
      Task { @MainActor in
        for await snapshot in subscription.snapshots {
          apply(snapshot)
        }
      }
    }

    private func apply(_ snapshot: InstantInfiniteQuerySnapshot) {
      if let error = snapshot.error {
        phase = .failed(error, hadRows: !rows.isEmpty)
        message = error.recoveryMessage
        return
      }
      do {
        rows = try snapshot.values.map(LinkedInfiniteListRow.init(snapshot:))
        phase = snapshot.values.isEmpty && !snapshot.canLoadNextPage
          ? .idleEmpty
          : .loaded(canLoadNextPage: snapshot.canLoadNextPage)
        message =
          "page roots \(rows.count) · linked word counts from transcriptions include"
      } catch {
        phase = .failed(
          InstantError(
            code: .decodeFailed,
            operation: "decode linked infinite rows",
            message: String(describing: error),
            recovery: "Inspect included transcription snapshots."
          ),
          hadRows: !rows.isEmpty
        )
      }
    }

    private func seedButtonTapped() {
      Task {
        do {
          _ = try await LinkedInfiniteSeed.seed(
            using: db,
            now: now,
            makeID: { uuid().uuidString.lowercased() }
          )
          message = "Seeded \(LinkedInfiniteSeed.titles.count) recordings with transcriptions"
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func loadNextPageButtonTapped() {
      guard canLoadNextPage else { return }
      if case .loaded(let canLoad) = phase {
        phase = .loadingNextPage(canLoadNextPage: canLoad)
      }
      subscription?.loadNextPage()
    }
  }
#endif
