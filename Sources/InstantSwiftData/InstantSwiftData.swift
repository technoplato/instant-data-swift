@_exported public import InstantSwiftDataCore

@attached(member, names: named(instantNamespace))
public macro InstantEntity(_ namespace: String? = nil) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantEntityMacro")

public struct InstantSwiftDataClient: Sendable {
  public var runtime: InstantRuntime

  public init(runtime: InstantRuntime) {
    self.runtime = runtime
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration
  ) async throws -> Self {
    try await Self(runtime: InstantRuntime.bootstrap(configuration: configuration))
  }

  @discardableResult
  public func transact(
    _ transaction: InstantStoreTransaction
  ) async throws -> InstantStoreMutationResult {
    try await runtime.transact(transaction)
  }

  public func query(_ plan: InstantQueryPlan) async -> [InstantEntitySnapshot] {
    await runtime.query(plan)
  }

  public func observe(_ plan: InstantQueryPlan) async -> AsyncStream<InstantQueryEmission> {
    await runtime.observe(plan)
  }
}

@propertyWrapper
public struct FetchAll<Element: Sendable>: Sendable {
  public var wrappedValue: [Element]
  public var loadError: InstantError?
  public var isLoading: Bool

  public init(wrappedValue: [Element] = []) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }
}
