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
    if let state = try? await persistence.loadState() {
      attributes = state.snapshot.store.attributes
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
