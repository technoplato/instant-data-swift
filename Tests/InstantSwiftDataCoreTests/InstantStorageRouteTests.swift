import CustomDump
import Foundation
import Network
import Testing
@testable import InstantSwiftDataCore

/// The live storage client asks for a route that is not expensive while the path has one, and says which route each
/// transfer used (#1231).
///
/// On one device Wi-Fi Assist moved the storage connection to cellular (an HTTP/3 connection migrated "because PTO count
/// is > 3") and 618 later uploads, about 341 MB, reused it for 57 minutes while Wi-Fi was the path again. URLSession keeps
/// the connections of requests that refuse expensive networks apart from those of requests that allow them (measured on
/// a Mac, loopback), so a request that asks for a route that is not expensive never rides such a connection.
@Suite(.serialized)
struct InstantStorageRouteTests {
  @Test
  func aRequestOnAPathThatIsNotExpensiveAsksForSuchARoute() async throws {
    let fixture = StorageRouteFixture(path: .wifi)
    let response = try await fixture.client.send(fixture.request())
    expectNoDifference(response.statusCode, 200)
    let sent = await fixture.transfers.sent
    expectNoDifference(sent.map(\.allowsExpensiveNetworkAccess), [false])
    expectNoDifference(sent.map(\.timeoutInterval), [60], "Only a small upload's first attempt waits less.")
  }

  @Test
  func aRequestThatFailsOnSuchARouteGoesAgainAsItsCallerAskedAtOnce() async throws {
    let fixture = StorageRouteFixture(path: .wifi, failure: storageRouteRefusal)
    let response = try await fixture.client.send(fixture.request())
    expectNoDifference(response.statusCode, 200)
    _ = try await fixture.client.send(fixture.request())
    let sent = await fixture.transfers.sent
    expectNoDifference(
      sent.map(\.allowsExpensiveNetworkAccess),
      [false, true, true],
      "After the failure, requests go as their callers asked until the backoff ends."
    )
    expectNoDifference(sent.map(\.timeoutInterval), [60, 60, 60])
    #expect(!fixture.path.asksForNonexpensiveRoute())
  }

  @Test
  func aCallersRefusalOfExpensiveNetworksIsNeverWidened() async throws {
    let fixture = StorageRouteFixture(path: .wifi, failure: storageRouteRefusal)
    var request = fixture.request()
    request.allowsExpensiveNetworkAccess = false
    await #expect(throws: URLError.self) {
      _ = try await fixture.client.send(request)
    }
    let sent = await fixture.transfers.sent
    expectNoDifference(sent.map(\.allowsExpensiveNetworkAccess), [false])
    expectNoDifference(sent.map(\.timeoutInterval), [60], "The caller's request goes as it is.")
  }

  @Test
  func onCellularARequestGoesAsItsCallerAsked() async throws {
    let fixture = StorageRouteFixture(path: .cellular)
    _ = try await fixture.client.send(fixture.request())
    let sent = await fixture.transfers.sent
    expectNoDifference(sent.map(\.allowsExpensiveNetworkAccess), [true])
  }

  @Test
  func anUploadThatFailsOnSuchARouteIsSentAgainAsItsCallerAsked() async throws {
    let fixture = StorageRouteFixture(path: .wifi, failure: storageRouteRefusal)
    let small = try fixture.file(byteCount: 24_000)
    let large = try fixture.file(byteCount: 2 * 1_024 * 1_024)
    let response = try await fixture.client.uploadFile(fixture.request(method: "PUT"), small)
    expectNoDifference(response.statusCode, 200)
    fixture.path.recordNonexpensiveRouteSucceeded()  // the backoff ends
    _ = try await fixture.client.uploadFile(fixture.request(method: "PUT"), large)
    let uploads = await fixture.transfers.uploaded
    expectNoDifference(uploads.map(\.request.allowsExpensiveNetworkAccess), [false, true, false, true])
    expectNoDifference(
      uploads.map(\.request.timeoutInterval),
      [5, 60, 60, 60],
      "A small upload's first attempt waits five seconds at most; a large one keeps its caller's timeout."
    )
  }

  /// A timeout on Wi-Fi may be a slow server, such as a storage stall (#1233): a large upload is not sent twice for it,
  /// and the preference stands.
  @Test
  func aLargeUploadThatTimesOutOnSuchARouteIsNotSentTwice() async throws {
    let fixture = StorageRouteFixture(path: .wifi, failure: URLError(.timedOut))
    let large = try fixture.file(byteCount: 2 * 1_024 * 1_024)
    await #expect(throws: URLError.self) {
      _ = try await fixture.client.uploadFile(fixture.request(method: "PUT"), large)
    }
    let uploads = await fixture.transfers.uploaded
    expectNoDifference(uploads.map(\.request.allowsExpensiveNetworkAccess), [false])
    #expect(fixture.path.asksForNonexpensiveRoute())
  }

  /// A small upload's first attempt that times out goes again at once on any network, as Wi-Fi Assist would have sent
  /// it: the compressed copy keeps flowing while the Wi-Fi's internet link is down (FEATURES item 24).
  @Test
  func aSmallUploadThatTimesOutOnSuchARouteGoesAgainOnAnyNetwork() async throws {
    let fixture = StorageRouteFixture(path: .wifi, failure: URLError(.timedOut))
    let small = try fixture.file(byteCount: 24_000)
    let response = try await fixture.client.uploadFile(fixture.request(method: "PUT"), small)
    expectNoDifference(response.statusCode, 200)
    let uploads = await fixture.transfers.uploaded
    expectNoDifference(uploads.map(\.request.allowsExpensiveNetworkAccess), [false, true])
    expectNoDifference(uploads.map(\.request.timeoutInterval), [5, 60])
    #expect(!fixture.path.asksForNonexpensiveRoute())
  }

  @Test
  func aRequestThatGoesThroughAfterAFailureIsARecovery() async throws {
    let fixture = StorageRouteFixture(path: .wifi)
    fixture.path.recordNonexpensiveRouteRefused(now: .now - .seconds(120))
    #expect(fixture.path.asksForNonexpensiveRoute(), "The backoff ended.")
    _ = try await fixture.client.send(fixture.request())
    expectNoDifference(fixture.path.routeMark.recoveries, 1, "A socket that fell back may move now.")
  }

  @Test
  func aLiveUploadSaysWhichRouteItsTransferUsed() async throws {
    let server = try await StorageRouteLoopbackServer.start()
    defer { server.stop() }
    let fixture = StorageRouteFixture(path: .wifi)
    let file = try fixture.file(byteCount: 100_000)
    var request = URLRequest(url: server.url.appendingPathComponent("storage/upload"))
    request.httpMethod = "PUT"
    let response = try await InstantStorageHTTPClient.live(networkPath: .alwaysSatisfied).uploadFile(request, file)
    expectNoDifference(response.statusCode, 200)
    expectNoDifference(response.route, InstantNetworkRoute(isCellular: false, isExpensive: false, isConstrained: false))
  }
}

// MARK: - Fixtures

/// The live client over a scripted path and scripted transfers: each request's network access and timeout recorded.
private struct StorageRouteFixture {
  let path: InstantNetworkPathMonitor
  let transfers: StorageRouteTransfers
  let client: InstantStorageHTTPClient
  let directory: URL

  init(path state: InstantNetworkPathState, failure: URLError? = nil) {
    path = InstantNetworkPathMonitor(path: state)
    transfers = StorageRouteTransfers(failure: failure)
    client = .live(networkPath: InstantNetworkPath(monitor: path), transfers: transfers.client)
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantStorageRouteTests-\(UUID().uuidString)", isDirectory: true)
  }

  func request(method: String = "GET") -> URLRequest {
    var request = URLRequest(url: URL(string: "https://api.instantdb.com/storage/files")!)
    request.httpMethod = method
    return request
  }

  func file(byteCount: Int) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(byteCount).bin")
    try Data(repeating: 7, count: byteCount).write(to: url)
    return url
  }
}

/// The system's answer to a request that refuses expensive networks when the only network it has is cellular.
private let storageRouteRefusal = URLError(
  .notConnectedToInternet,
  userInfo: [NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.expensive.rawValue]
)

/// Scripted transfers: a request that refuses expensive networks fails with `failure`, when one is given; every other
/// request answers 200.
private actor StorageRouteTransfers {
  struct Upload: Sendable {
    var request: URLRequest
    var file: URL
  }

  private let failure: URLError?
  private(set) var sent: [URLRequest] = []
  private(set) var uploaded: [Upload] = []

  init(failure: URLError?) {
    self.failure = failure
  }

  nonisolated var client: InstantStorageHTTPTransfers {
    InstantStorageHTTPTransfers(
      send: { request in try await self.send(request) },
      downloadToFile: { _ in throw URLError(.unsupportedURL) },
      upload: { request, file in
        InstantStorageTransportOperation(run: { try await self.upload(request, file: file) }, abort: {})
      }
    )
  }

  private func answer(_ request: URLRequest) throws -> InstantStorageHTTPResponse {
    if let failure, !request.allowsExpensiveNetworkAccess {
      throw failure
    }
    return InstantStorageHTTPResponse(statusCode: 200, data: Data(#"{"data":{"id":"stored"}}"#.utf8))
  }

  private func send(_ request: URLRequest) throws -> InstantStorageHTTPResponse {
    sent.append(request)
    return try answer(request)
  }

  private func upload(_ request: URLRequest, file: URL) throws -> InstantStorageHTTPResponse {
    uploaded.append(Upload(request: request, file: file))
    return try answer(request)
  }
}

/// A loopback HTTP server that reads one request's headers and body and answers 200 with a stored file's id.
private final class StorageRouteLoopbackServer: @unchecked Sendable {
  // SAFETY: `connections` is touched only on `queue`; `port` is set once, before `start` returns the server.
  private let listener: NWListener
  private let queue = DispatchQueue(label: "instant-storage-route-tests.server")
  private var connections: [NWConnection] = []
  private var port: UInt16 = 0

  var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

  private init(listener: NWListener) {
    self.listener = listener
  }

  static func start() async throws -> StorageRouteLoopbackServer {
    let parameters = NWParameters.tcp
    parameters.acceptLocalOnly = true
    parameters.requiredInterfaceType = .loopback
    let listener = try NWListener(using: parameters)
    let server = StorageRouteLoopbackServer(listener: listener)
    listener.newConnectionHandler = { [server] connection in server.accept(connection) }
    server.port = try await withCheckedThrowingContinuation { continuation in
      let once = StorageRouteResumeOnce()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
        case .failed(let error):
          if once.claim() { continuation.resume(throwing: error) }
        default:
          break
        }
      }
      listener.start(queue: server.queue)
    }
    return server
  }

  private func accept(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: queue)
    read(connection, buffer: Data())
  }

  private func read(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
      guard let self else { return }
      var buffer = buffer
      if let data { buffer.append(data) }
      if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
        let headers = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self).lowercased()
        let length =
          headers.components(separatedBy: "\r\n")
          .first { $0.hasPrefix("content-length:") }
          .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        if buffer.count - headerEnd.upperBound >= length {
          self.answer(connection)
          return
        }
      }
      guard error == nil, !isComplete else {
        connection.cancel()
        return
      }
      self.read(connection, buffer: buffer)
    }
  }

  private func answer(_ connection: NWConnection) {
    let body = #"{"data":{"id":"stored"}}"#
    let response =
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
      + "Connection: close\r\n\r\n\(body)"
    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
  }

  func stop() {
    queue.async {
      for connection in self.connections { connection.cancel() }
      self.connections = []
    }
    listener.cancel()
  }
}

/// Lets a callback that may run more than once resume its continuation once.
private final class StorageRouteResumeOnce: @unchecked Sendable {
  // SAFETY: `lock` guards `claimed`.
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}
