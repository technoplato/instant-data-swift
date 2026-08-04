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
      LinkedInfiniteDurableLog.resetSession(reason: "bootstrap-model-init")
      LinkedInfiniteDurableLog.log(
        "bootstrap.model.init",
        [
          "appID": configuration.appID,
          "enablesLiveSync": configuration.enablesLiveSync,
          "persistencePath": configuration.persistenceURL?.path ?? "nil",
          "logPath": LinkedInfiniteDurableLog.path,
        ]
      )
    }

    public func startIfNeeded() {
      guard client == nil, task == nil else {
        LinkedInfiniteDurableLog.log(
          "bootstrap.start.skipped",
          [
            "hasClient": client != nil,
            "hasTask": task != nil,
          ]
        )
        return
      }
      LinkedInfiniteDurableLog.log("bootstrap.start.begin", [:])
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
          LinkedInfiniteDurableLog.log(
            "bootstrap.start.success",
            [
              "appID": configuration.appID,
              "attributeCount": LinkedInfiniteSeed.instantAttributes.count,
            ]
          )
          self?.client = client
          self?.task = nil
        } catch {
          LinkedInfiniteDurableLog.log(
            "bootstrap.start.failed",
            [
              "error": String(describing: error),
            ]
          )
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
    @State private var loadedPageCount = 0
    @State private var didBootstrapSeed = false
    @State private var seedInFlight = false
    @State private var snapshotOrdinal = 0
    @State private var loadNextAttemptCount = 0
    @State private var seedAttemptCount = 0
    /// Hold last good rows across empty infinite flashes (live preBootstrap).
    @State private var lastGoodRows: [LinkedInfiniteListRow] = []
    private let wrapsInNavigationStack: Bool
    private let pageSize: Int
    private let defaultLoadedPages: Int
    private let screenInstanceID = UUID().uuidString.lowercased()

    public init(
      wrapsInNavigationStack: Bool = true,
      pageSize: Int = 3,
      defaultLoadedPages: Int = 5
    ) {
      self.wrapsInNavigationStack = wrapsInNavigationStack
      self.pageSize = pageSize
      self.defaultLoadedPages = max(1, defaultLoadedPages)
    }

    public var body: some View {
      Group {
        if wrapsInNavigationStack {
          NavigationStack { content }
        } else {
          content
        }
      }
      .task {
        LinkedInfiniteDurableLog.log(
          "screen.task.begin",
          [
            "screenInstanceID": screenInstanceID,
            "pageSize": pageSize,
            "defaultLoadedPages": defaultLoadedPages,
            "logPath": LinkedInfiniteDurableLog.path,
          ]
        )
        await startObservation()
      }
    }

    private var content: some View {
      List {
        Section {
          Button("Seed sample recordings", action: seedButtonTapped)
            .disabled(seedInFlight)
          Button("Load next page", action: { loadNextPageButtonTapped(reason: "user-button") })
            .disabled(!canLoadNextPage)
          Text("Page size \(pageSize) · auto-load \(defaultLoadedPages) pages · loaded \(loadedPageCount)")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text("log: \(LinkedInfiniteDurableLog.path)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
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
              LinkedInfiniteDurableLog.log(
                "row.onAppear",
                [
                  "rowID": row.id.rawValue,
                  "title": row.title,
                  "isLast": row.id == rows.last?.id,
                  "rowsCount": rows.count,
                  "canLoadNextPage": canLoadNextPage,
                  "phase": phaseLabel,
                ]
              )
              if row.id == rows.last?.id {
                loadNextPageButtonTapped(reason: "last-row-onAppear")
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
      LinkedInfiniteDurableLog.log(
        "observe.begin",
        [
          "screenInstanceID": screenInstanceID,
          "hadSubscription": subscription != nil,
          "pageSize": pageSize,
          "defaultLoadedPages": defaultLoadedPages,
          "priorRowsCount": rows.count,
          "priorPhase": phaseLabel,
        ]
      )
      subscription?.unsubscribe()
      phase = .loadingFirstPage
      loadedPageCount = 0
      snapshotOrdinal = 0
      let query = LinkedInfiniteListRow.pageQuery(pageSize: pageSize)
      let plan = query.plan
      LinkedInfiniteDurableLog.log(
        "observe.plan",
        [
          "planID": plan.id,
          "namespace": plan.namespace,
          "limit": plan.limit as Any,
          "includeNames": plan.includes?.map(\.name) ?? [],
          "cacheKey": plan.cacheKey,
        ]
      )
      let subscription = await db.subscribeInfiniteQuery(plan)
      self.subscription = subscription
      LinkedInfiniteDurableLog.log(
        "observe.subscribed",
        [
          "planID": plan.id,
          "screenInstanceID": screenInstanceID,
        ]
      )
      Task { @MainActor in
        var emissionIndex = 0
        for await snapshot in subscription.snapshots {
          emissionIndex += 1
          LinkedInfiniteDurableLog.log(
            "observe.snapshot.received",
            [
              "emissionIndex": emissionIndex,
              "screenInstanceID": screenInstanceID,
            ]
          )
          apply(snapshot)
        }
        LinkedInfiniteDurableLog.log(
          "observe.stream.finished",
          [
            "emissionCount": emissionIndex,
            "screenInstanceID": screenInstanceID,
            "finalRowsCount": rows.count,
            "finalPhase": phaseLabel,
          ]
        )
      }
    }

    private func apply(_ snapshot: InstantInfiniteQuerySnapshot) {
      snapshotOrdinal += 1
      let previousRowsCount = rows.count
      let previousPhase = phaseLabel

      LinkedInfiniteDurableLog.log(
        "snapshot.apply.begin",
        [
          "snapshotOrdinal": snapshotOrdinal,
          "queryID": snapshot.queryID,
          "sequence": snapshot.sequence,
          "rawValueCount": snapshot.values.count,
          "canLoadNextPage": snapshot.canLoadNextPage,
          "hasError": snapshot.error != nil,
          "pageInfoHasNext": snapshot.pageInfo?.hasNextPage as Any,
          "previousRowsCount": previousRowsCount,
          "previousPhase": previousPhase,
          "lastGoodRowsCount": lastGoodRows.count,
        ]
      )

      if let error = snapshot.error {
        phase = .failed(error, hadRows: !rows.isEmpty || !lastGoodRows.isEmpty)
        message = error.recoveryMessage
        LinkedInfiniteDurableLog.log(
          "snapshot.apply.error",
          [
            "snapshotOrdinal": snapshotOrdinal,
            "code": error.code.rawValue,
            "message": error.message,
          ]
        )
        return
      }

      do {
        let decoded = try snapshot.values.map(LinkedInfiniteListRow.init(snapshot:))

        // Hold last good paint across empty live flashes.
        if decoded.isEmpty, !lastGoodRows.isEmpty {
          LinkedInfiniteDurableLog.log(
            "snapshot.apply.held-last-good",
            [
              "snapshotOrdinal": snapshotOrdinal,
              "heldCount": lastGoodRows.count,
              "rawValueCount": 0,
              "canLoadNextPage": snapshot.canLoadNextPage,
            ]
          )
          // Keep rows; only update paging flag if library says more are available.
          if snapshot.canLoadNextPage {
            phase = .loaded(canLoadNextPage: true)
          }
          return
        }

        rows = decoded
        if !decoded.isEmpty {
          lastGoodRows = decoded
        }

        if rows.count > previousRowsCount || (loadedPageCount == 0 && !rows.isEmpty) {
          loadedPageCount = max(1, (rows.count + pageSize - 1) / max(pageSize, 1))
        }

        phase =
          rows.isEmpty && !snapshot.canLoadNextPage
          ? .idleEmpty
          : .loaded(canLoadNextPage: snapshot.canLoadNextPage)

        message =
          "\(rows.count) roots · \(loadedPageCount)/\(defaultLoadedPages) pages · word counts from include"

        LinkedInfiniteDurableLog.log(
          "snapshot.apply.decoded",
          [
            "snapshotOrdinal": snapshotOrdinal,
            "decodedRowsCount": rows.count,
            "decodedTitles": rows.prefix(5).map(\.title),
            "decodedWordCounts": rows.prefix(5).map(\.wordCount),
            "loadedPageCount": loadedPageCount,
            "phase": phaseLabel,
            "canLoadNextPage": canLoadNextPage,
            "rowsDelta": rows.count - previousRowsCount,
          ]
        )

        // Bootstrap seed only once, when truly empty and not already seeding.
        if rows.isEmpty, lastGoodRows.isEmpty, !didBootstrapSeed, !seedInFlight {
          didBootstrapSeed = true
          LinkedInfiniteDurableLog.log(
            "snapshot.apply.bootstrap-seed.trigger",
            [
              "snapshotOrdinal": snapshotOrdinal,
              "reason": "empty-first-page",
            ]
          )
          seedButtonTapped(autoLoadPages: true, reason: "bootstrap-empty")
          return
        }

        if snapshot.canLoadNextPage, loadedPageCount < defaultLoadedPages {
          LinkedInfiniteDurableLog.log(
            "snapshot.apply.auto-load-next",
            [
              "snapshotOrdinal": snapshotOrdinal,
              "loadedPageCount": loadedPageCount,
              "defaultLoadedPages": defaultLoadedPages,
            ]
          )
          loadNextPageButtonTapped(reason: "auto-load-default-pages")
        } else {
          LinkedInfiniteDurableLog.log(
            "snapshot.apply.auto-load-skip",
            [
              "snapshotOrdinal": snapshotOrdinal,
              "loadedPageCount": loadedPageCount,
              "defaultLoadedPages": defaultLoadedPages,
              "canLoadNextPage": snapshot.canLoadNextPage,
              "reason": !snapshot.canLoadNextPage
                ? "library-canLoadNextPage-false"
                : "already-at-or-past-default-pages",
            ]
          )
        }

        Task { @MainActor in
          await logFullNamespaceProbe(trigger: "after-snapshot-\(snapshotOrdinal)")
        }
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
        LinkedInfiniteDurableLog.log(
          "snapshot.apply.decode-failed",
          [
            "snapshotOrdinal": snapshotOrdinal,
            "error": String(describing: error),
          ]
        )
      }
    }

    private func seedButtonTapped() {
      seedButtonTapped(autoLoadPages: true, reason: "user-button")
    }

    private func seedButtonTapped(autoLoadPages: Bool, reason: String) {
      guard !seedInFlight else {
        LinkedInfiniteDurableLog.log(
          "seed.skipped-in-flight",
          ["reason": reason, "attempt": seedAttemptCount]
        )
        return
      }
      seedInFlight = true
      seedAttemptCount += 1
      let attempt = seedAttemptCount
      LinkedInfiniteDurableLog.log(
        "seed.begin",
        [
          "attempt": attempt,
          "reason": reason,
          "autoLoadPages": autoLoadPages,
          "seedTitleCount": LinkedInfiniteSeed.titles.count,
          "beforeRowsCount": rows.count,
          "beforePhase": phaseLabel,
          "beforeCanLoadNextPage": canLoadNextPage,
        ]
      )
      Task {
        defer { seedInFlight = false }
        do {
          let seeded = try await LinkedInfiniteSeed.seed(
            using: db,
            now: now,
            makeID: { uuid().uuidString.lowercased() }
          )
          // Optimistically show seeded rows until infinite re-emits.
          if rows.isEmpty, !seeded.isEmpty {
            rows = seeded
            lastGoodRows = seeded
            loadedPageCount = max(1, (seeded.count + pageSize - 1) / max(pageSize, 1))
            phase = .loaded(canLoadNextPage: seeded.count > pageSize)
          }
          message =
            "Seeded \(seeded.count) recordings"
            + (autoLoadPages ? " · loading pages…" : "")
          LinkedInfiniteDurableLog.log(
            "seed.success",
            [
              "attempt": attempt,
              "reason": reason,
              "seededCount": seeded.count,
              "seededTitles": seeded.prefix(5).map(\.title),
              "afterPhase": phaseLabel,
              "afterCanLoadNextPage": canLoadNextPage,
              "afterRowsCount": rows.count,
              "autoLoadPages": autoLoadPages,
            ]
          )
          await logFullNamespaceProbe(trigger: "after-seed-\(attempt)")
          if autoLoadPages {
            // Prefer library loadNext; do not reset loadedPageCount to 0.
            if canLoadNextPage {
              loadNextPageButtonTapped(reason: "seed-auto-load")
            } else {
              // Force one expand attempt even if phase lags (library may still expand).
              LinkedInfiniteDurableLog.log(
                "seed.auto-load.force-loadNext",
                [
                  "attempt": attempt,
                  "phase": phaseLabel,
                  "rowsCount": rows.count,
                ]
              )
              subscription?.loadNextPage()
              phase = .loadingNextPage(canLoadNextPage: true)
            }
          }
        } catch {
          message = String(describing: error)
          LinkedInfiniteDurableLog.log(
            "seed.failed",
            [
              "attempt": attempt,
              "reason": reason,
              "error": String(describing: error),
            ]
          )
        }
      }
    }

    private func loadNextPageButtonTapped(reason: String) {
      loadNextAttemptCount += 1
      let attempt = loadNextAttemptCount
      LinkedInfiniteDurableLog.log(
        "loadNext.attempt",
        [
          "attempt": attempt,
          "reason": reason,
          "canLoadNextPage": canLoadNextPage,
          "phase": phaseLabel,
          "rowsCount": rows.count,
          "loadedPageCount": loadedPageCount,
          "hasSubscription": subscription != nil,
        ]
      )
      // Allow force path after seed even if phase not yet .loaded(true).
      let allow =
        canLoadNextPage
        || reason == "seed-auto-load"
        || reason.hasPrefix("auto-load")
      guard allow, subscription != nil else {
        LinkedInfiniteDurableLog.log(
          "loadNext.blocked",
          [
            "attempt": attempt,
            "reason": reason,
            "phase": phaseLabel,
            "rowsCount": rows.count,
          ]
        )
        return
      }
      if case .loaded(let canLoad) = phase {
        phase = .loadingNextPage(canLoadNextPage: canLoad)
      } else {
        phase = .loadingNextPage(canLoadNextPage: true)
      }
      LinkedInfiniteDurableLog.log(
        "loadNext.invoked",
        [
          "attempt": attempt,
          "reason": reason,
          "phaseAfterMark": phaseLabel,
        ]
      )
      subscription?.loadNextPage()
    }

    private func logFullNamespaceProbe(trigger: String) async {
      do {
        let recordings = try await db.query(
          LinkedInfiniteRecording.query.order(
            LinkedInfiniteRecording.updatedAt,
            .descending
          )
        )
        let transcriptions = try await db.query(
          LinkedInfiniteTranscription.query.order(
            LinkedInfiniteTranscription.updatedAt,
            .descending
          )
        )
        LinkedInfiniteDurableLog.log(
          "probe.full-namespace",
          [
            "trigger": trigger,
            "recordingCount": recordings.count,
            "transcriptionCount": transcriptions.count,
            "recordingTitles": recordings.prefix(5).map(\.title),
            "uiRowsCount": rows.count,
            "uiCanLoadNextPage": canLoadNextPage,
            "uiPhase": phaseLabel,
            "uiLoadedPageCount": loadedPageCount,
            "mismatchSuggestsInfiniteWindowStuck":
              recordings.count > rows.count && !canLoadNextPage,
          ]
        )
      } catch {
        LinkedInfiniteDurableLog.log(
          "probe.full-namespace.failed",
          [
            "trigger": trigger,
            "error": String(describing: error),
          ]
        )
      }
    }
  }
#endif
