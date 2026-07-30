import Foundation

#if canImport(Network)
  import Network

  public actor InstantNetworkDesertHost {
    public nonisolated let coordinator: InstantDesertCoordinator
    public nonisolated let port: UInt16

    public nonisolated var transport: InstantLiveTransportClient {
      coordinator.transport
    }

    private let listener: NWListener
    private let acceptor: InstantNetworkDesertAcceptor

    private init(
      coordinator: InstantDesertCoordinator,
      listener: NWListener,
      acceptor: InstantNetworkDesertAcceptor,
      port: UInt16
    ) {
      self.coordinator = coordinator
      self.listener = listener
      self.acceptor = acceptor
      self.port = port
    }

    public static func start(
      appID: String,
      initialAttributes: [InstantAttribute] = [],
      host: String = "127.0.0.1",
      port: UInt16
    ) async throws -> Self {
      guard host == "127.0.0.1" || host == "::1" else {
        throw InstantError(
          code: .validationFailed,
          operation: "start Instant Network.framework desert host",
          path: "host",
          message:
            "The unauthenticated desert prototype can bind only to 127.0.0.1 or ::1, not '\(host)'.",
          recovery: "Use 127.0.0.1 for Mac and iOS Simulator smoke testing."
        )
      }
      guard let networkPort = NWEndpoint.Port(rawValue: port) else {
        throw InstantError(
          code: .validationFailed,
          operation: "start Instant Network.framework desert host",
          path: "port",
          message: "The requested TCP port '\(port)' is invalid.",
          recovery: "Choose a TCP port from 0 through 65535."
        )
      }
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      parameters.requiredLocalEndpoint = .hostPort(
        host: NWEndpoint.Host(host),
        port: networkPort
      )
      let listener: NWListener
      do {
        listener = try NWListener(using: parameters)
      } catch {
        throw InstantNetworkDesertError.wrap(
          error,
          operation: "create Instant Network.framework desert listener",
          recovery: "Choose an available port and confirm Local Network access is allowed."
        )
      }
      let coordinator = InstantDesertCoordinator(
        appID: appID,
        initialAttributes: initialAttributes
      )
      let acceptor = InstantNetworkDesertAcceptor(coordinator: coordinator, appID: appID)
      listener.newConnectionHandler = { connection in
        Task { await acceptor.accept(connection) }
      }
      try await InstantNetworkDesertStart.waitUntilReady(listener)
      guard let boundPort = listener.port?.rawValue else {
        listener.cancel()
        throw InstantError(
          code: .networkFailed,
          operation: "start Instant Network.framework desert host",
          path: "port",
          message: "The listener became ready without a bound TCP port.",
          recovery: "Restart the desert host on an explicit available port."
        )
      }
      return Self(
        coordinator: coordinator,
        listener: listener,
        acceptor: acceptor,
        port: boundPort
      )
    }

    public func stop() async {
      listener.cancel()
      await acceptor.stop()
    }
  }

  extension InstantLiveTransportClient {
    public static func networkFramework(host: String, port: UInt16) -> Self {
      Self { _ in
        guard !host.isEmpty else {
          throw InstantError(
            code: .validationFailed,
            operation: "connect Instant Network.framework desert peer",
            path: "host",
            message: "The desert peer host is empty.",
            recovery: "Pass the Mac host name, IP address, or localhost for Simulator testing."
          )
        }
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
          throw InstantError(
            code: .validationFailed,
            operation: "connect Instant Network.framework desert peer",
            path: "port",
            message: "The desert peer TCP port '\(port)' is invalid.",
            recovery: "Use the port reported by InstantNetworkDesertHost."
          )
        }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(
          host: NWEndpoint.Host(host),
          port: networkPort,
          using: parameters
        )
        let framed = InstantNetworkDesertFramedConnection(connection: connection)
        try await framed.start()
        return InstantLiveWebSocketSession(
          send: { message in
            try await framed.send(message)
          },
          receive: {
            try await framed.receive()
          },
          close: {
            await framed.cancel()
          }
        )
      }
    }
  }

  private actor InstantNetworkDesertAcceptor {
    private let coordinator: InstantDesertCoordinator
    private let appID: String
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var connections: [UUID: NWConnection] = [:]

    init(coordinator: InstantDesertCoordinator, appID: String) {
      self.coordinator = coordinator
      self.appID = appID
    }

    func accept(_ connection: NWConnection) {
      let id = UUID()
      let coordinator = coordinator
      let appID = appID
      connections[id] = connection
      tasks[id] = Task { [weak self] in
        await InstantNetworkDesertHostPeer.run(
          connection: connection,
          coordinator: coordinator,
          appID: appID
        )
        await self?.finished(id)
      }
    }

    func stop() async {
      let activeTasks = Array(tasks.values)
      let activeConnections = Array(connections.values)
      tasks.removeAll()
      connections.removeAll()
      for connection in activeConnections { connection.cancel() }
      for task in activeTasks { task.cancel() }
      for task in activeTasks { await task.value }
    }

    private func finished(_ id: UUID) {
      tasks[id] = nil
      connections[id] = nil
    }
  }

  private enum InstantNetworkDesertHostPeer {
    static func run(
      connection: NWConnection,
      coordinator: InstantDesertCoordinator,
      appID: String
    ) async {
      let framed = InstantNetworkDesertFramedConnection(connection: connection)
      var session: InstantLiveWebSocketSession?
      do {
        try await framed.start()
        let openedSession = try await coordinator.openSession(appID: appID)
        session = openedSession
        try await withThrowingTaskGroup(of: Void.self) { group in
          group.addTask {
            while !Task.isCancelled {
              let message = try await framed.receive()
              try await openedSession.send(message)
            }
          }
          group.addTask {
            while !Task.isCancelled {
              let message = try await openedSession.receive()
              try await framed.send(message)
            }
          }
          do {
            _ = try await group.next()
          } catch {
            await framed.cancel()
            await openedSession.close()
            group.cancelAll()
            throw error
          }
          await framed.cancel()
          await openedSession.close()
          group.cancelAll()
        }
      } catch {
        await framed.cancel()
        await session?.close()
      }
    }
  }

  private actor InstantNetworkDesertFramedConnection {
    private static let maximumFrameSize = 16 * 1_024 * 1_024

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "instant-swift-data.desert-network")
    private var didStart = false

    init(connection: NWConnection) {
      self.connection = connection
    }

    func start() async throws {
      guard !didStart else { return }
      didStart = true
      try await InstantNetworkDesertStart.waitUntilReady(connection, queue: queue)
    }

    func send(_ message: InstantLiveMessage) async throws {
      let payload: Data
      do {
        payload = try JSONEncoder().encode(message)
      } catch {
        throw InstantNetworkDesertError.wrap(
          error,
          operation: "encode Instant Network.framework desert message",
          recovery: "Inspect the Instant live message before sending it."
        )
      }
      guard payload.count <= Self.maximumFrameSize else {
        throw InstantError(
          code: .validationFailed,
          operation: "send Instant Network.framework desert message",
          message: "The encoded desert frame exceeds \(Self.maximumFrameSize) bytes.",
          recovery: "Split the operation into smaller entity transactions."
        )
      }
      var bigEndianLength = UInt32(payload.count).bigEndian
      var frame = withUnsafeBytes(of: &bigEndianLength) { Data($0) }
      frame.append(payload)
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(
          content: frame,
          completion: .contentProcessed { error in
            if let error {
              continuation.resume(
                throwing: InstantNetworkDesertError.wrap(
                  error,
                  operation: "send Instant Network.framework desert frame",
                  recovery: "Confirm the host is running and the peer can reach its TCP port."
                )
              )
            } else {
              continuation.resume()
            }
          })
      }
    }

    func receive() async throws -> InstantLiveMessage {
      let header = try await readExactly(4)
      let length = header.reduce(UInt32(0)) { partial, byte in
        (partial << 8) | UInt32(byte)
      }
      guard length > 0, length <= Self.maximumFrameSize else {
        throw InstantError(
          code: .decodeFailed,
          operation: "receive Instant Network.framework desert frame",
          message: "The peer announced an invalid \(length)-byte desert frame.",
          recovery: "Use matching length-prefixed Instant desert transports on both peers."
        )
      }
      let payload = try await readExactly(Int(length))
      do {
        return try JSONDecoder().decode(InstantLiveMessage.self, from: payload)
      } catch {
        throw InstantNetworkDesertError.wrap(
          error,
          operation: "decode Instant Network.framework desert message",
          recovery: "Use matching InstantLiveMessage encoders on the host and peer."
        )
      }
    }

    func cancel() {
      connection.cancel()
    }

    private func readExactly(_ byteCount: Int) async throws -> Data {
      var result = Data()
      result.reserveCapacity(byteCount)
      while result.count < byteCount {
        if Task.isCancelled { throw CancellationError() }
        let chunk = try await receiveChunk(maximumLength: byteCount - result.count)
        result.append(chunk)
      }
      return result
    }

    private func receiveChunk(maximumLength: Int) async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        connection.receive(
          minimumIncompleteLength: 1,
          maximumLength: maximumLength
        ) { data, _, isComplete, error in
          if let error {
            continuation.resume(
              throwing: InstantNetworkDesertError.wrap(
                error,
                operation: "receive Instant Network.framework desert frame",
                recovery: "Confirm the desert host is running and reachable."
              )
            )
          } else if let data, !data.isEmpty {
            continuation.resume(returning: data)
          } else if isComplete {
            continuation.resume(
              throwing: InstantError(
                code: .networkFailed,
                operation: "receive Instant Network.framework desert frame",
                message: "The peer closed the TCP connection.",
                recovery: "Reconnect to the desert host and resume pending mutations."
              )
            )
          } else {
            continuation.resume(
              throwing: InstantError(
                code: .networkFailed,
                operation: "receive Instant Network.framework desert frame",
                message: "Network.framework returned no frame bytes.",
                recovery: "Reconnect to the desert host and retry."
              )
            )
          }
        }
      }
    }
  }

  private enum InstantNetworkDesertStart {
    static func waitUntilReady(_ listener: NWListener) async throws {
      let gate = InstantNetworkDesertOneShot()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          gate.resume(with: .success(()))
        case .failed(let error):
          gate.resume(
            with: .failure(
              InstantNetworkDesertError.wrap(
                error,
                operation: "start Instant Network.framework desert host",
                recovery: "Choose an available port and confirm Local Network access is allowed."
              )
            )
          )
        case .cancelled:
          gate.resume(
            with: .failure(
              InstantError(
                code: .networkFailed,
                operation: "start Instant Network.framework desert host",
                message: "The desert listener was cancelled before it became ready.",
                recovery: "Create and retain a new InstantNetworkDesertHost."
              )
            )
          )
        case .setup, .waiting:
          break
        @unknown default:
          break
        }
      }
      listener.start(queue: DispatchQueue(label: "instant-swift-data.desert-listener"))
      try await wait(
        on: gate,
        operation: "start Instant Network.framework desert host",
        timeoutRecovery: "Choose an available port and confirm Local Network access is allowed.",
        cancel: { listener.cancel() }
      )
    }

    static func waitUntilReady(
      _ connection: NWConnection,
      queue: DispatchQueue
    ) async throws {
      let gate = InstantNetworkDesertOneShot()
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          gate.resume(with: .success(()))
        case .failed(let error):
          gate.resume(
            with: .failure(
              InstantNetworkDesertError.wrap(
                error,
                operation: "connect Instant Network.framework desert peer",
                recovery: "Confirm the host address, TCP port, and Local Network permission."
              )
            )
          )
        case .cancelled:
          gate.resume(
            with: .failure(
              InstantError(
                code: .networkFailed,
                operation: "connect Instant Network.framework desert peer",
                message: "The desert connection was cancelled before it became ready.",
                recovery: "Open a new desert peer connection and retry."
              )
            )
          )
        case .setup, .preparing, .waiting:
          break
        @unknown default:
          break
        }
      }
      connection.start(queue: queue)
      try await wait(
        on: gate,
        operation: "connect Instant Network.framework desert peer",
        timeoutRecovery: "Confirm the host address, TCP port, and Local Network permission.",
        cancel: { connection.cancel() }
      )
    }

    private static func wait(
      on gate: InstantNetworkDesertOneShot,
      operation: String,
      timeoutRecovery: String,
      cancel: @escaping @Sendable () -> Void
    ) async throws {
      let timeout = Task<Void, Never> {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        let timedOut = gate.resume(
          with: .failure(
            InstantError(
              code: .networkFailed,
              operation: operation,
              message: "Network.framework did not become ready within one second.",
              recovery: timeoutRecovery
            )
          )
        )
        if timedOut { cancel() }
      }
      defer { timeout.cancel() }

      do {
        try await withTaskCancellationHandler {
          try await gate.wait()
        } onCancel: {
          let cancelled = gate.resume(with: .failure(CancellationError()))
          if cancelled { cancel() }
        }
      } catch {
        cancel()
        throw error
      }
    }
  }

  // SAFETY: the lock protects the callback's one-resume continuation invariant
  // across Network.framework queues.
  private final class InstantNetworkDesertOneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?

    @discardableResult
    func resume(
      with result: Result<Void, any Error>
    ) -> Bool {
      lock.lock()
      guard self.result == nil else {
        lock.unlock()
        return false
      }
      self.result = result
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume(with: result)
      return true
    }

    func wait() async throws {
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        if let result {
          lock.unlock()
          continuation.resume(with: result)
        } else {
          self.continuation = continuation
          lock.unlock()
        }
      }
    }
  }

  private enum InstantNetworkDesertError {
    static func wrap(
      _ error: any Error,
      operation: String,
      recovery: String
    ) -> InstantError {
      if let error = error as? InstantError { return error }
      return InstantError(
        code: .networkFailed,
        operation: operation,
        message: String(describing: error),
        recovery: recovery
      )
    }
  }
#else
  public actor InstantNetworkDesertHost {
    public nonisolated let coordinator: InstantDesertCoordinator
    public nonisolated let port: UInt16

    public nonisolated var transport: InstantLiveTransportClient {
      coordinator.transport
    }

    private init(coordinator: InstantDesertCoordinator, port: UInt16) {
      self.coordinator = coordinator
      self.port = port
    }

    public static func start(
      appID: String,
      initialAttributes: [InstantAttribute] = [],
      host: String = "127.0.0.1",
      port: UInt16
    ) async throws -> Self {
      throw InstantError(
        code: .implementationFailed,
        operation: "start Instant Network.framework desert host",
        message: "Network.framework is unavailable on this platform.",
        recovery: "Run the desert host on an Apple platform with Network.framework."
      )
    }

    public func stop() {}
  }

  extension InstantLiveTransportClient {
    public static func networkFramework(host: String, port: UInt16) -> Self {
      Self { _ in
        throw InstantError(
          code: .implementationFailed,
          operation: "connect Instant Network.framework desert peer",
          message: "Network.framework is unavailable on this platform.",
          recovery: "Run the desert peer on an Apple platform with Network.framework."
        )
      }
    }
  }
#endif
