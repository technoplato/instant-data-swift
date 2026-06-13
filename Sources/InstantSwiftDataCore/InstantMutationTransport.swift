import Foundation

public struct InstantMutationTransportRequest: Hashable, Encodable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var mutations: [InstantTransportMutation]

  public init(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    mutations: [InstantTransportMutation]
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.mutations = mutations
  }
}

public struct InstantMutationTransportResponse: Hashable, Codable, Sendable {
  public var results: [InstantMutationTransportResult]

  public init(results: [InstantMutationTransportResult]) {
    self.results = results
  }
}

public struct InstantMutationTransportResult: Hashable, Codable, Sendable, Identifiable {
  public enum Outcome: String, Codable, Sendable {
    case confirmed
    case failed
  }

  public var id: String { mutationID }
  public var mutationID: String
  public var outcome: Outcome
  public var message: String?

  public init(mutationID: String, outcome: Outcome, message: String? = nil) {
    self.mutationID = mutationID
    self.outcome = outcome
    self.message = message
  }
}

public struct InstantMutationTransportFlushResult: Hashable, Encodable, Sendable {
  public var request: InstantMutationTransportRequest
  public var results: [InstantMutationTransportResult]
  public var confirmed: [PendingMutation]
  public var failed: [PendingMutation]
  public var pendingMutationCount: Int
  public var mutationCount: Int

  public init(
    request: InstantMutationTransportRequest,
    results: [InstantMutationTransportResult],
    confirmed: [PendingMutation],
    failed: [PendingMutation],
    pendingMutationCount: Int,
    mutationCount: Int
  ) {
    self.request = request
    self.results = results
    self.confirmed = confirmed
    self.failed = failed
    self.pendingMutationCount = pendingMutationCount
    self.mutationCount = mutationCount
  }
}

public struct InstantMutationTransportClient: Sendable {
  public var send:
    @Sendable (InstantMutationTransportRequest) async throws -> InstantMutationTransportResponse

  public init(
    send: @escaping @Sendable (InstantMutationTransportRequest) async throws
      -> InstantMutationTransportResponse
  ) {
    self.send = send
  }
}

extension InstantMutationTransportClient {
  public static let local = Self { request in
    InstantMutationTransportResponse(
      results: request.mutations.map { mutation in
        InstantMutationTransportResult(mutationID: mutation.mutationID, outcome: .confirmed)
      }
    )
  }
}
