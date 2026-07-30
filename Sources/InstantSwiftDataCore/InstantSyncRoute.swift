public enum InstantSyncRoutePolicy: String, Hashable, Codable, Sendable {
  case current
  case desertRequired = "desert-required"
}

public enum InstantSelectedSyncRoute: String, Hashable, Codable, Sendable {
  case localCache = "local-cache"
  case cloud
  case desert
}

public struct InstantSyncRouteDescriptor: Hashable, Codable, Sendable {
  public var route: InstantSelectedSyncRoute
  public var adapter: String
  public var transport: InstantRuntimeTransportKind

  public init(
    route: InstantSelectedSyncRoute,
    adapter: String,
    transport: InstantRuntimeTransportKind
  ) {
    self.route = route
    self.adapter = adapter
    self.transport = transport
  }

  public static let localCache = Self(
    route: .localCache,
    adapter: "local-cache",
    transport: .localCacheOnly
  )

  public static let cloudWebSocket = Self(
    route: .cloud,
    adapter: "instant-websocket",
    transport: .webSocket
  )
}

public struct InstantSyncTransportFactory: Sendable {
  public var adapter: String
  public var transport: InstantRuntimeTransportKind
  public var makeTransport: @Sendable () async throws -> InstantLiveTransportClient

  public init(
    adapter: String,
    transport: InstantRuntimeTransportKind,
    makeTransport: @escaping @Sendable () async throws -> InstantLiveTransportClient
  ) {
    self.adapter = adapter
    self.transport = transport
    self.makeTransport = makeTransport
  }

  public func routeDescriptor(for route: InstantSelectedSyncRoute) -> InstantSyncRouteDescriptor {
    InstantSyncRouteDescriptor(route: route, adapter: adapter, transport: transport)
  }
}
