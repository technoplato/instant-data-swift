import Foundation

public struct InstantInfiniteQuerySnapshot: Hashable, Codable, Sendable {
  public var queryID: String
  public var sequence: Int64
  public var values: [InstantEntitySnapshot]
  public var pageInfo: InstantQueryPageInfo?
  public var canLoadNextPage: Bool
  public var error: InstantError?

  public init(
    queryID: String,
    sequence: Int64,
    values: [InstantEntitySnapshot],
    pageInfo: InstantQueryPageInfo? = nil,
    canLoadNextPage: Bool,
    error: InstantError? = nil
  ) {
    self.queryID = queryID
    self.sequence = sequence
    self.values = values
    self.pageInfo = pageInfo
    self.canLoadNextPage = canLoadNextPage
    self.error = error
  }
}

public struct InstantInfiniteQuerySubscription: Sendable {
  public var snapshots: AsyncStream<InstantInfiniteQuerySnapshot>
  public var loadNextPage: @Sendable () -> Void
  public var unsubscribe: @Sendable () -> Void

  public init(
    snapshots: AsyncStream<InstantInfiniteQuerySnapshot>,
    loadNextPage: @escaping @Sendable () -> Void,
    unsubscribe: @escaping @Sendable () -> Void
  ) {
    self.snapshots = snapshots
    self.loadNextPage = loadNextPage
    self.unsubscribe = unsubscribe
  }
}

extension InstantRuntime {
  public func subscribeInfiniteQuery(
    _ plan: InstantQueryPlan
  ) async -> InstantInfiniteQuerySubscription {
    if let error = await infiniteQueryValidationError(for: plan.infiniteObservationPlan) {
      let stream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      stream.continuation.yield(
        InstantInfiniteQuerySnapshot(
          queryID: plan.id,
          sequence: 0,
          values: [],
          canLoadNextPage: false,
          error: error
        )
      )
      stream.continuation.finish()
      return InstantInfiniteQuerySubscription(
        snapshots: stream.stream,
        loadNextPage: {},
        unsubscribe: {}
      )
    }

    if configuration.liveTransport != nil {
      let stream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      let coordinator = InstantLiveInfiniteQueryCoordinator(
        runtime: self,
        plan: plan,
        continuation: stream.continuation
      )
      await coordinator.start()
      stream.continuation.onTermination = { @Sendable _ in
        Task { await coordinator.unsubscribe() }
      }
      return InstantInfiniteQuerySubscription(
        snapshots: stream.stream,
        loadNextPage: {
          Task { await coordinator.loadNextPage() }
        },
        unsubscribe: {
          Task { await coordinator.unsubscribe() }
        }
      )
    }

    let coordinator = InstantInfiniteQueryCoordinator(plan: plan)
    let stream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let observation = await observe(plan.infiniteObservationPlan)
    let task = Task {
      for await emission in observation {
        let snapshot = await coordinator.snapshot(for: emission)
        stream.continuation.yield(snapshot)
      }
      stream.continuation.finish()
    }

    stream.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }

    return InstantInfiniteQuerySubscription(
      snapshots: stream.stream,
      loadNextPage: {
        Task {
          guard let snapshot = await coordinator.loadNextPage() else { return }
          stream.continuation.yield(snapshot)
        }
      },
      unsubscribe: {
        task.cancel()
        stream.continuation.finish()
      }
    )
  }

  public func infiniteQueryInitialSnapshot(
    _ plan: InstantQueryPlan
  ) async throws -> InstantInfiniteQuerySnapshot {
    let emission = try await queryOnce(plan.infiniteFirstPagePlan)
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: emission.sequence,
      values: emission.values,
      pageInfo: emission.pageInfo,
      canLoadNextPage: false
    )
  }
}

private enum InstantLiveInfiniteForwardChunkKey: Hashable, Sendable {
  case preBootstrap
  case cursor(InstantQueryCursor, afterInclusive: Bool)
}

private enum InstantLiveInfiniteSubscriptionKey: Hashable, Sendable {
  case forward(InstantLiveInfiniteForwardChunkKey)
  case reverse(InstantQueryCursor)
}

private struct InstantLiveInfiniteChunk: Sendable {
  var data: [InstantEntitySnapshot]
  var sequence: Int64
  var pageInfo: InstantQueryPageInfo?
  var hasMore: Bool
  var endCursor: InstantQueryCursor?
}

private struct InstantLiveInfiniteReverseAdvance: Hashable, Sendable {
  var startCursor: InstantQueryCursor
  var endCursor: InstantQueryCursor
}

private actor InstantLiveInfiniteQueryCoordinator {
  private let runtime: InstantRuntime
  private let plan: InstantQueryPlan
  private let pageSize: Int
  private let continuation: AsyncStream<InstantInfiniteQuerySnapshot>.Continuation
  private var starterTask: Task<Void, Never>?
  private var subscriptions: [InstantLiveInfiniteSubscriptionKey: Task<Void, Never>] = [:]
  private var forwardKeys: [InstantLiveInfiniteForwardChunkKey] = []
  private var forwardChunks: [InstantLiveInfiniteForwardChunkKey: InstantLiveInfiniteChunk] = [:]
  private var reverseKeys: [InstantQueryCursor] = []
  private var reverseChunks: [InstantQueryCursor: InstantLiveInfiniteChunk] = [:]
  private var advancedForwardChunks: Set<InstantLiveInfiniteForwardChunkKey> = []
  private var advancedReverseChunks: Set<InstantLiveInfiniteReverseAdvance> = []
  private var hasKickstarted = false
  private var isActive = true
  private var nextPlanID = 0
  /// Local-first expansion while waiting for server liveTuple cursors.
  private var preBootstrapLoadedPages = 1
  private var preBootstrapExpandInFlight = false
  private var preBootstrapExpandPending = false

  init(
    runtime: InstantRuntime,
    plan: InstantQueryPlan,
    continuation: AsyncStream<InstantInfiniteQuerySnapshot>.Continuation
  ) {
    self.runtime = runtime
    self.plan = plan
    self.pageSize = InstantInfiniteQueryCoordinator.pageSize(for: plan)
    self.continuation = continuation
  }

  func start() {
    guard isActive, starterTask == nil else { return }
    let starterPlan = chunkPlan(
      name: "starter",
      order: resolvedOrder,
      limit: pageSize,
      after: nil,
      before: nil
    )
    starterTask = Task { [runtime] in
      let auth = try? await runtime.authSession()
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.subscribe.started",
        message: "Live infinite query coordinator started its starter subscription.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "planID": plan.id,
          "hasIncludes": ((plan.includes?.isEmpty) == false).description,
        ].merging(InstantInfiniteQueryDiagnostics.authMetadata(auth)) { _, new in new },
        correlationID: plan.id
      )
      let observation = await runtime.observeLiveInfiniteQueryChunk(starterPlan)
      for await emission in observation {
        guard !Task.isCancelled else { break }
        self.receiveStarter(emission)
      }
    }
  }

  func loadNextPage() {
    guard isActive else { return }

    // Before live cursors exist, expand from the local full observation window
    // (starter emissions are limit-sized and never grow on their own).
    if !hasKickstarted {
      // Already closed (short page or expand found no growth): republish so
      // consumers leave isLoadingNextPage without more queryLocally work.
      if let chunk = forwardChunks[.preBootstrap], !chunk.hasMore {
        InstantInfiniteQueryDiagnostics.record(
          event: "infinite.load-next.noop-closed",
          message:
            "loadNextPage no-op: pre-kickstart window already closed (local fullness).",
          metadata: [
            "namespace": plan.namespace,
            "pageSize": pageSize.description,
            "resultCount": chunk.data.count.description,
            "hasKickstarted": "false",
            "phase": "preBootstrap",
          ],
          correlationID: plan.id
        )
        pushSnapshot()
        return
      }
      Task { await self.expandPreBootstrapFromLocalStore() }
      return
    }

    guard let key = forwardKeys.last,
      case .cursor = key,
      let chunk = forwardChunks[key],
      let endCursor = chunk.endCursor,
      advancedForwardChunks.insert(key).inserted
    else {
      // Never leave consumers stuck on "loading next" when we cannot advance
      // (already advanced, missing cursor, or empty forward window).
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.load-next.noop-cannot-advance",
        message:
          "loadNextPage no-op: cannot advance forward cursor after kickstart.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "hasKickstarted": "true",
          "phase": "liveCursor",
          "forwardChunkCount": forwardKeys.count.description,
        ],
        correlationID: plan.id
      )
      pushSnapshot()
      return
    }
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.load-next.advance-cursor",
      message: "loadNextPage advancing past the current live forward cursor.",
      metadata: [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "chunkResultCount": chunk.data.count.description,
        "endEntityFingerprint": InstantInfiniteQueryDiagnostics.fingerprint(
          endCursor.entityID
        ),
        "phase": "liveCursor",
      ],
      correlationID: plan.id
    )
    freezeForward(key: key, chunk: chunk)
    pushNewForward(startCursor: endCursor)
  }

  func unsubscribe() {
    guard isActive else { return }
    isActive = false
    starterTask?.cancel()
    starterTask = nil
    for task in subscriptions.values {
      task.cancel()
    }
    subscriptions.removeAll()
    continuation.finish()
  }

  private func receiveStarter(_ emission: InstantQueryEmission) {
    guard isActive, !hasKickstarted else { return }

    // Server-backed page info with opaque live tuple → real live infinite chunks.
    if emission.values.count >= pageSize,
      let startCursor = emission.pageInfo?.startCursor,
      startCursor.liveTuple != nil
    {
      forwardKeys.removeAll { $0 == .preBootstrap }
      forwardChunks[.preBootstrap] = nil
      hasKickstarted = true
      preBootstrapExpandInFlight = false
      var kickMeta: [String: String] = [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "resultCount": emission.values.count.description,
        "phase": "kickstart",
        "hasMoreSource": "liveTupleKickstart",
      ]
      kickMeta.merge(InstantInfiniteQueryDiagnostics.cursorMetadata(emission.pageInfo)) {
        _, new in new
      }
      kickMeta.merge(
        InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: emission.values)
      ) { _, new in new }
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.kickstart",
        message:
          "Full starter page with liveTuple cursor; switching to live infinite chunks.",
        metadata: kickMeta,
        correlationID: plan.id
      )
      pushNewForward(startCursor: startCursor, afterInclusive: true)
      pushNewReverse(startCursor: startCursor)
      return
    }

    // Local-first / pre-cursor phase.
    // Never clobber a non-empty optimistic page with an empty live emission
    // (logs showed 3→0 flashes while the store still held 20 roots).
    if emission.values.isEmpty,
      let existing = forwardChunks[.preBootstrap],
      !existing.data.isEmpty
    {
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.starter.empty-ignored",
        message:
          "Ignored empty starter emission over a non-empty pre-bootstrap window.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "existingCount": existing.data.count.description,
          "phase": "preBootstrap",
        ],
        correlationID: plan.id
      )
      return
    }

    // Keep expanded local window if we already loadNext'd past the starter.
    let data: [InstantEntitySnapshot]
    if let existing = forwardChunks[.preBootstrap],
      existing.data.count > emission.values.count,
      !emission.values.isEmpty
    {
      // Prefer the larger expanded local window unless starter grew.
      data = existing.data
    } else {
      data = emission.values
      // Reset expansion baseline when starter content changes identity/size down.
      if emission.values.count <= pageSize {
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages)
      }
    }

    // Pre-kickstart can only expand the local store. Remote `hasNextPage` without
    // a liveTuple kickstart is not actionable — trusting it (1.5.0) left
    // canLoadNextPage=true on short pages forever, and Scribe's list UI
    // onAppear auto-load thrashed until Jetsam (~4 GB, iPad 2026-08-04/05).
    // 1.4.0 always set hasMore=false here; keep local fullness as the only signal.
    let existingClosedWithoutGrowth =
      forwardChunks[.preBootstrap].map { existing in
        !existing.hasMore && existing.data.count >= data.count
      } ?? false
    let remoteHasNext = emission.pageInfo?.hasNextPage
    let localFull = data.count >= pageSize
    let hasMore = !existingClosedWithoutGrowth && localFull
    let hasMoreSource: String
    if existingClosedWithoutGrowth {
      hasMoreSource = "keptClosed"
    } else if localFull {
      hasMoreSource = "localFullness"
    } else {
      hasMoreSource = "shortPageClosed"
    }

    var starterMeta: [String: String] = [
      "namespace": plan.namespace,
      "pageSize": pageSize.description,
      "emissionCount": emission.values.count.description,
      "windowCount": data.count.description,
      "canLoadNextPage": hasMore.description,
      "hasMoreSource": hasMoreSource,
      "remoteHasNextPageIgnored": remoteHasNext.map {
        ($0 && !hasMore).description
      } ?? "nil",
      "remoteHasNextPageRaw": remoteHasNext.map(\.description) ?? "nil",
      "localFullness": localFull.description,
      "phase": "preBootstrap",
      "preBootstrapLoadedPages": preBootstrapLoadedPages.description,
    ]
    starterMeta.merge(InstantInfiniteQueryDiagnostics.cursorMetadata(emission.pageInfo)) {
      _, new in new
    }
    starterMeta.merge(InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: data)) {
      _, new in new
    }
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.starter.snapshot",
      message: hasMore
        ? "Pre-kickstart starter page can expand from local fullness."
        : "Pre-kickstart starter page closed (short of page size or already closed).",
      metadata: starterMeta,
      correlationID: plan.id
    )

    setForwardChunk(
      key: .preBootstrap,
      chunk: InstantLiveInfiniteChunk(
        data: data,
        sequence: emission.sequence,
        pageInfo: InstantQueryPageInfo(
          startCursor: data.first.map {
            InstantQueryCursor(entityID: $0.id, sortValue: nil)
          },
          endCursor: data.last.map {
            InstantQueryCursor(entityID: $0.id, sortValue: nil)
          },
          hasPreviousPage: false,
          hasNextPage: hasMore
        ),
        hasMore: hasMore,
        endCursor: data.last.map {
          InstantQueryCursor(entityID: $0.id, sortValue: nil)
        }
      )
    )
  }

  /// Pull a larger local window while waiting for live cursors.
  /// Always re-publishes a snapshot so UI cannot stick on "loading next".
  private func expandPreBootstrapFromLocalStore() async {
    guard isActive, !hasKickstarted else { return }
    if preBootstrapExpandInFlight {
      preBootstrapExpandPending = true
      return
    }
    preBootstrapExpandInFlight = true
    defer {
      preBootstrapExpandInFlight = false
      if preBootstrapExpandPending, isActive, !hasKickstarted {
        preBootstrapExpandPending = false
        Task { await self.expandPreBootstrapFromLocalStore() }
      }
    }

    preBootstrapLoadedPages += 1
    let limit = pageSize * preBootstrapLoadedPages
    let expandedPlan = InstantQueryPlan(
      id: "\(plan.id)#prebootstrap-expand-\(preBootstrapLoadedPages)",
      namespace: plan.namespace,
      filters: plan.filters,
      order: plan.order ?? .serverCreatedAt,
      limit: limit,
      selectedFields: plan.selectedFields,
      includes: plan.includes ?? []
    )

    do {
      // Always expand from the local triple store (not a fresh live queryOnce).
      // Live cursors kickstart the real path when the server page info arrives.
      let emission = try await runtime.queryLocally(expandedPlan)
      guard isActive, !hasKickstarted else { return }

      let existing = forwardChunks[.preBootstrap]
      let values: [InstantEntitySnapshot]
      if emission.values.isEmpty, let existing, !existing.data.isEmpty {
        // No growth; republish existing so consumers leave loading state.
        values = existing.data
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages - 1)
      } else if emission.values.count < (existing?.data.count ?? 0) {
        // Don't shrink the window on a partial local read.
        values = existing?.data ?? emission.values
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages - 1)
      } else {
        values = emission.values
      }

      // Pre-kickstart expand is local-only. End when the expanded window is not
      // full — never re-open from remote hasNextPage (not actionable without
      // liveTuple, and it caused infinite loadNextPage thrash on Scribe iPad).
      let closedHasMore = values.count >= limit
      let priorCount = existing?.data.count ?? 0
      let auth = try? await runtime.authSession()
      var expandMeta: [String: String] = [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "expandLimit": limit.description,
        "emissionCount": emission.values.count.description,
        "windowCount": values.count.description,
        "priorWindowCount": priorCount.description,
        "grew": (values.count > priorCount).description,
        "canLoadNextPage": closedHasMore.description,
        "hasMoreSource": closedHasMore ? "localFullness" : "expandShortClosed",
        "remoteHasNextPageRaw": emission.pageInfo.map {
          $0.hasNextPage.description
        } ?? "nil",
        "phase": "preBootstrapExpand",
        "preBootstrapLoadedPages": preBootstrapLoadedPages.description,
      ]
      expandMeta.merge(InstantInfiniteQueryDiagnostics.authMetadata(auth)) { _, new in new }
      expandMeta.merge(InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: values)) {
        _, new in new
      }
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.expand.snapshot",
        message: closedHasMore
          ? "Pre-kickstart local expand filled the window; more may exist locally."
          : "Pre-kickstart local expand did not fill the window; paging closed.",
        metadata: expandMeta,
        correlationID: plan.id
      )

      setForwardChunk(
        key: .preBootstrap,
        chunk: InstantLiveInfiniteChunk(
          data: values,
          sequence: max(
            emission.sequence,
            existing?.sequence ?? 0
          ) + 1,
          pageInfo: InstantQueryPageInfo(
            startCursor: values.first.map {
              InstantQueryCursor(entityID: $0.id, sortValue: nil)
            },
            endCursor: values.last.map {
              InstantQueryCursor(entityID: $0.id, sortValue: nil)
            },
            hasPreviousPage: false,
            hasNextPage: closedHasMore
          ),
          hasMore: closedHasMore,
          endCursor: values.last.map {
            InstantQueryCursor(entityID: $0.id, sortValue: nil)
          }
        )
      )
    } catch {
      // Always republish last good chunk so UI unsticks from loadingNextPage.
      preBootstrapLoadedPages = max(1, preBootstrapLoadedPages - 1)
      InstantInfiniteQueryDiagnostics.record(
        .warning,
        event: "infinite.expand.failed",
        message: "Pre-kickstart local expand failed; closing paging on last good window.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "phase": "preBootstrapExpand",
          "errorType": String(reflecting: type(of: error)),
        ],
        correlationID: plan.id
      )
      if let existing = forwardChunks[.preBootstrap] {
        setForwardChunk(
          key: .preBootstrap,
          chunk: InstantLiveInfiniteChunk(
            data: existing.data,
            sequence: existing.sequence + 1,
            pageInfo: InstantQueryPageInfo(
              startCursor: existing.pageInfo?.startCursor,
              endCursor: existing.pageInfo?.endCursor,
              hasPreviousPage: false,
              hasNextPage: false
            ),
            hasMore: false,
            endCursor: existing.endCursor
          )
        )
      } else {
        pushSnapshot()
      }
    }
  }

  private func receiveForward(
    key: InstantLiveInfiniteForwardChunkKey,
    emission: InstantQueryEmission
  ) {
    guard isActive, let pageInfo = emission.pageInfo else { return }
    setForwardChunk(
      key: key,
      chunk: InstantLiveInfiniteChunk(
        data: emission.values,
        sequence: emission.sequence,
        pageInfo: pageInfo,
        hasMore: pageInfo.hasNextPage,
        endCursor: pageInfo.endCursor
      )
    )
  }

  private func receiveReverse(
    startCursor: InstantQueryCursor,
    emission: InstantQueryEmission
  ) {
    guard isActive, let pageInfo = emission.pageInfo else { return }
    setReverseChunk(
      startCursor: startCursor,
      chunk: InstantLiveInfiniteChunk(
        data: emission.values,
        sequence: emission.sequence,
        pageInfo: pageInfo,
        hasMore: pageInfo.hasNextPage,
        endCursor: pageInfo.endCursor
      )
    )
  }

  private func setForwardChunk(
    key: InstantLiveInfiniteForwardChunkKey,
    chunk: InstantLiveInfiniteChunk
  ) {
    if forwardChunks[key] == nil {
      forwardKeys.append(key)
    }
    forwardChunks[key] = chunk
    pushSnapshot()
  }

  private func setReverseChunk(
    startCursor: InstantQueryCursor,
    chunk: InstantLiveInfiniteChunk
  ) {
    if reverseChunks[startCursor] == nil {
      reverseKeys.append(startCursor)
    }
    reverseChunks[startCursor] = chunk
    maybeAdvanceReverse()
    pushSnapshot()
  }

  private func pushNewForward(
    startCursor: InstantQueryCursor,
    afterInclusive: Bool = false
  ) {
    let key = InstantLiveInfiniteForwardChunkKey.cursor(
      startCursor,
      afterInclusive: afterInclusive
    )
    if forwardChunks[key] == nil {
      forwardKeys.append(key)
      forwardChunks[key] = placeholderChunk()
    }
    let queryPlan = chunkPlan(
      name: "forward",
      order: resolvedOrder,
      limit: pageSize,
      after: cursor(startCursor, inclusive: afterInclusive),
      before: nil
    )
    replaceSubscription(key: .forward(key), plan: queryPlan) { emission in
      await self.receiveForward(key: key, emission: emission)
    }
  }

  private func freezeForward(
    key: InstantLiveInfiniteForwardChunkKey,
    chunk: InstantLiveInfiniteChunk
  ) {
    guard case let .cursor(startCursor, afterInclusive) = key,
      let endCursor = chunk.endCursor
    else {
      return
    }
    forwardChunks[key] = chunk
    let queryPlan = chunkPlan(
      name: "forward-frozen",
      order: resolvedOrder,
      limit: nil,
      after: cursor(startCursor, inclusive: afterInclusive),
      before: cursor(endCursor, inclusive: true)
    )
    replaceSubscription(key: .forward(key), plan: queryPlan) { emission in
      await self.receiveForward(key: key, emission: emission)
    }
  }

  private func pushNewReverse(startCursor: InstantQueryCursor) {
    if reverseChunks[startCursor] == nil {
      reverseKeys.append(startCursor)
      reverseChunks[startCursor] = placeholderChunk()
    }
    let queryPlan = chunkPlan(
      name: "reverse",
      order: reversedOrder,
      limit: pageSize,
      after: cursor(startCursor, inclusive: false),
      before: nil
    )
    replaceSubscription(key: .reverse(startCursor), plan: queryPlan) { emission in
      await self.receiveReverse(
        startCursor: startCursor,
        emission: emission
      )
    }
  }

  private func freezeReverse(
    startCursor: InstantQueryCursor,
    chunk: InstantLiveInfiniteChunk
  ) {
    guard let endCursor = chunk.endCursor else { return }
    reverseChunks[startCursor] = chunk
    let queryPlan = chunkPlan(
      name: "reverse-frozen",
      order: reversedOrder,
      limit: nil,
      after: cursor(startCursor, inclusive: false),
      before: cursor(endCursor, inclusive: true)
    )
    replaceSubscription(key: .reverse(startCursor), plan: queryPlan) { emission in
      await self.receiveReverse(
        startCursor: startCursor,
        emission: emission
      )
    }
  }

  private func maybeAdvanceReverse() {
    guard let startCursor = reverseKeys.last,
      let chunk = reverseChunks[startCursor],
      chunk.hasMore,
      let endCursor = chunk.endCursor,
      advancedReverseChunks.insert(
        InstantLiveInfiniteReverseAdvance(
          startCursor: startCursor,
          endCursor: endCursor
        )
      ).inserted
    else {
      return
    }
    freezeReverse(startCursor: startCursor, chunk: chunk)
    pushNewReverse(startCursor: endCursor)
  }

  private func replaceSubscription(
    key: InstantLiveInfiniteSubscriptionKey,
    plan: InstantQueryPlan,
    receive: @escaping @Sendable (InstantQueryEmission) async -> Void
  ) {
    subscriptions[key]?.cancel()
    subscriptions[key] = Task { [runtime] in
      let observation = await runtime.observeLiveInfiniteQueryChunk(plan)
      for await emission in observation {
        guard !Task.isCancelled else { break }
        await receive(emission)
      }
    }
  }

  private func pushSnapshot() {
    guard isActive else { return }
    let orderedReverseChunks = reverseKeys.reversed().compactMap { reverseChunks[$0] }
    let orderedForwardChunks = forwardKeys.compactMap { forwardChunks[$0] }
    let values = orderedReverseChunks.flatMap { $0.data.reversed() }
      + orderedForwardChunks.flatMap(\.data)
    let canLoadNextPage = orderedForwardChunks.last?.hasMore ?? false
    let startCursor = orderedReverseChunks.first?.pageInfo?.endCursor
      ?? orderedForwardChunks.first?.pageInfo?.startCursor
    let endCursor = orderedForwardChunks.last?.pageInfo?.endCursor
      ?? orderedReverseChunks.last?.pageInfo?.startCursor
    let sequence = (orderedReverseChunks + orderedForwardChunks)
      .map(\.sequence)
      .max()
      ?? 0
    let pageInfo = (orderedReverseChunks + orderedForwardChunks).isEmpty
      ? nil
      : InstantQueryPageInfo(
        startCursor: startCursor,
        endCursor: endCursor,
        hasPreviousPage: false,
        hasNextPage: canLoadNextPage
      )
    continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: plan.id,
        sequence: sequence,
        values: values,
        pageInfo: pageInfo,
        canLoadNextPage: canLoadNextPage
      )
    )
  }

  private func placeholderChunk() -> InstantLiveInfiniteChunk {
    InstantLiveInfiniteChunk(
      data: [],
      sequence: 0,
      pageInfo: nil,
      hasMore: false,
      endCursor: nil
    )
  }

  private func cursor(
    _ cursor: InstantQueryCursor,
    inclusive: Bool
  ) -> InstantQueryCursor {
    var cursor = cursor
    cursor.inclusive = inclusive
    return cursor
  }

  private var resolvedOrder: InstantQueryOrder {
    plan.order ?? .serverCreatedAt
  }

  private var reversedOrder: InstantQueryOrder {
    InstantQueryOrder(
      resolvedOrder.field,
      resolvedOrder.direction == .ascending ? .descending : .ascending
    )
  }

  private func chunkPlan(
    name: String,
    order: InstantQueryOrder,
    limit: Int?,
    after: InstantQueryCursor?,
    before: InstantQueryCursor?
  ) -> InstantQueryPlan {
    defer { nextPlanID += 1 }
    return InstantQueryPlan(
      id: "\(plan.id).infinite.\(name).\(nextPlanID)",
      namespace: plan.namespace,
      filters: plan.filters,
      order: order,
      limit: limit,
      after: after,
      before: before,
      selectedFields: plan.selectedFields,
      includes: plan.includes ?? []
    )
  }
}

private actor InstantInfiniteQueryCoordinator {
  private let plan: InstantQueryPlan
  private let pageSize: Int
  private var anchorID: String?
  private var loadedForwardPageCount = 1
  private var latestCanLoadNextPage = false
  private var latestEmission: InstantQueryEmission?

  init(plan: InstantQueryPlan) {
    self.plan = plan
    self.pageSize = Self.pageSize(for: plan)
  }

  func snapshot(for emission: InstantQueryEmission) -> InstantInfiniteQuerySnapshot {
    latestEmission = emission
    return makeSnapshot(values: emission.values, sequence: emission.sequence)
  }

  func loadNextPage() -> InstantInfiniteQuerySnapshot? {
    guard latestCanLoadNextPage, let latestEmission else { return nil }
    loadedForwardPageCount += 1
    return makeSnapshot(values: latestEmission.values, sequence: latestEmission.sequence)
  }

  private func makeSnapshot(
    values: [InstantEntitySnapshot],
    sequence: Int64
  ) -> InstantInfiniteQuerySnapshot {
    let window = visibleWindow(in: values)
    latestCanLoadNextPage = window.canLoadNextPage
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: sequence,
      values: window.values,
      pageInfo: pageInfo(for: window.values, canLoadNextPage: window.canLoadNextPage),
      canLoadNextPage: window.canLoadNextPage
    )
  }

  private func visibleWindow(
    in values: [InstantEntitySnapshot]
  ) -> (values: [InstantEntitySnapshot], canLoadNextPage: Bool) {
    guard !values.isEmpty else {
      anchorID = nil
      return ([], false)
    }

    if anchorID == nil {
      if values.count < pageSize {
        return (values, false)
      }
      anchorID = values[0].id
    }

    guard let anchorID,
      let anchorIndex = values.firstIndex(where: { $0.id == anchorID })
    else {
      self.anchorID = values[0].id
      let visible = Array(values.prefix(forwardLimit))
      return (visible, values.count > visible.count)
    }

    let leading = values[..<anchorIndex]
    let forwardValues = values[anchorIndex...]
    let visibleForward = forwardValues.prefix(forwardLimit)
    let visible = Array(leading) + Array(visibleForward)
    return (visible, forwardValues.count > visibleForward.count)
  }

  private var forwardLimit: Int {
    pageSize * loadedForwardPageCount
  }

  private func pageInfo(
    for values: [InstantEntitySnapshot],
    canLoadNextPage: Bool
  ) -> InstantQueryPageInfo? {
    guard !values.isEmpty else {
      return InstantQueryPageInfo(
        startCursor: nil,
        endCursor: nil,
        hasPreviousPage: false,
        hasNextPage: canLoadNextPage
      )
    }
    return InstantQueryPageInfo(
      startCursor: values.first.map(cursor(for:)),
      endCursor: values.last.map(cursor(for:)),
      hasPreviousPage: false,
      hasNextPage: canLoadNextPage
    )
  }

  private func cursor(for snapshot: InstantEntitySnapshot) -> InstantQueryCursor {
    InstantQueryCursor(
      entityID: snapshot.id,
      sortValue: plan.order.flatMap { snapshot.values[$0.field]?.first }
    )
  }

  static func pageSize(for plan: InstantQueryPlan) -> Int {
    guard let limit = plan.limit, limit > 0 else { return 10 }
    return limit
  }
}

private extension InstantRuntime {
  func infiniteQueryValidationError(for plan: InstantQueryPlan) async -> InstantError? {
    let attributes: [InstantAttribute]
    if let synchronizedAttributes = try? await attributesForInfiniteQueryValidation() {
      attributes = synchronizedAttributes
    } else {
      attributes = await store.snapshot().attributes
    }
    guard let issue = TripleIndexes.validate(
      plan,
      attributes: AttributeStore(attributes: attributes)
    ) else {
      return nil
    }
    return InstantError(
      code: .validationFailed,
      operation: "validate infinite query",
      namespace: issue.namespace,
      path: issue.path,
      message: issue.message,
      recovery: issue.recovery
    )
  }
}

private extension InstantQueryPlan {
  var infiniteObservationPlan: InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      filters: filters,
      order: order ?? .serverCreatedAt,
      selectedFields: selectedFields,
      includes: includes ?? []
    )
  }

  var infiniteFirstPagePlan: InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      filters: filters,
      order: order ?? .serverCreatedAt,
      limit: InstantInfiniteQueryCoordinator.pageSize(for: self),
      selectedFields: selectedFields,
      includes: includes ?? []
    )
  }
}
