#if canImport(SwiftUI)
  import Combine
  import Dependencies
  import Foundation
  import SwiftUI

  public struct InstantTopicPublishedEvent<Message: Codable & Sendable>: Sendable {
    public var topicID: String
    public var message: Message

    public init(topicID: String, message: Message) {
      self.topicID = topicID
      self.message = message
    }
  }

  @MainActor
  public final class InstantTopic<Message: Codable & Sendable>: ObservableObject {
    @Published public private(set) var messages: [Message] = []
    @Published public private(set) var loadError: InstantError?
    @Published public private(set) var isLoading = false

    public let name: String

    private var room: InstantRoomHandle?
    private var observationGeneration = 0
    private let localUserID = UUID().uuidString.lowercased()

    fileprivate init(name: String) {
      self.name = name
    }

    fileprivate func observe(
      room: InstantRoomHandle,
      using client: InstantSwiftDataClient
    ) async throws {
      observationGeneration += 1
      let generation = observationGeneration
      self.room = room
      messages = []
      loadError = nil
      isLoading = true

      do {
        let subscription = try await client.subscribeRoomTopicMessages(
          room: room,
          topic: name
        )
        defer { subscription.cancel() }
        try Task.checkCancellation()

        for try await rawMessages in subscription {
          try Task.checkCancellation()
          guard observationGeneration == generation else {
            throw CancellationError()
          }
          messages = try rawMessages.map {
            try InstantRoomCodableJSON.decode(Message.self, from: $0.payload)
          }
          loadError = nil
          isLoading = false
        }

        try Task.checkCancellation()
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        isLoading = false
      } catch is CancellationError {
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        loadError = nil
        isLoading = false
        throw CancellationError()
      } catch let instantError as InstantError {
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        loadError = instantError
        isLoading = false
        throw instantError
      } catch {
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        let instantError = InstantError(
          code: .decodeFailed,
          operation: "observe typed room topic",
          message: String(describing: error),
          recovery: "Keep the room topic message type aligned with the published JSON payload."
        )
        loadError = instantError
        isLoading = false
        throw instantError
      }
    }

    @discardableResult
    public func publish(
      _ message: Message,
      onPublished: @escaping @MainActor @Sendable
        (InstantTopicPublishedEvent<Message>) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return publish(
        message,
        using: client,
        onPublished: onPublished,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func publish(
      _ message: Message,
      using client: InstantSwiftDataClient,
      onPublished: @escaping @MainActor @Sendable
        (InstantTopicPublishedEvent<Message>) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let room = self.room
      let name = self.name
      return Task { @MainActor in
        do {
          guard let room else {
            throw InstantError(
              code: .validationFailed,
              operation: "publish typed room topic",
              message: "The topic is not attached to an Instant room.",
              recovery: "Attach @Topic with .instantTopic(_:in:) before publishing."
            )
          }
          let payload = try InstantRoomCodableJSON.encode(message)
          let published = try await client.publishRoomTopicMessage(
            room: room,
            topic: name,
            userID: localUserID,
            payload: payload
          )
          try Task.checkCancellation()
          let event = InstantTopicPublishedEvent(
            topicID: published.id,
            message: message
          )
          loadError = nil
          onPublished(event)
        } catch is CancellationError {
        } catch let instantError as InstantError {
          loadError = instantError
          onFailure(instantError)
        } catch {
          let instantError = InstantError(
            code: .implementationFailed,
            operation: "publish typed room topic",
            message: String(describing: error),
            recovery: "Inspect the topic message and configured room client."
          )
          loadError = instantError
          onFailure(instantError)
        }
      }
    }
  }

  @MainActor
  private final class InstantTopicReference<Message: Codable & Sendable> {
    var value: InstantTopic<Message>

    init(_ value: InstantTopic<Message>) {
      self.value = value
    }
  }

  @MainActor
  @propertyWrapper
  public struct Topic<
    Message: Codable & Sendable,
    Name: InstantRoomTopic
  >: DynamicProperty {
    private let topicReference: InstantTopicReference<Message>
    @StateObject private var topicObserver: InstantTopic<Message>

    private var topic: InstantTopic<Message> {
      topicReference.value
    }

    public init(_ name: Name) {
      let topic = InstantTopic<Message>(name: name.rawValue)
      topicReference = InstantTopicReference(topic)
      _topicObserver = StateObject(wrappedValue: topic)
    }

    public var wrappedValue: InstantTopic<Message> {
      topic
    }

    public var projectedValue: Self {
      self
    }

    public mutating func update() {
      topicReference.value = topicObserver
    }

    public func task(
      in room: InstantRoom<Name.RoomSchema>,
      using client: InstantSwiftDataClient
    ) async throws {
      let handle = try await waitForInstantTopicRoomHandle(room)
      try await topic.observe(room: handle, using: client)
    }
  }

  private func waitForInstantTopicRoomHandle<Schema: InstantRoomSchema>(
    _ room: InstantRoom<Schema>
  ) async throws -> InstantRoomHandle {
    while true {
      try Task.checkCancellation()
      if let handle = room.handle { return handle }
      await Task.yield()
    }
  }

  extension View {
    public func instantTopic<
      Message: Codable & Sendable,
      Name: InstantRoomTopic
    >(
      _ topic: Topic<Message, Name>,
      in room: InstantRoom<Name.RoomSchema>
    ) -> some View {
      @Dependency(\.defaultInstantSwiftData) var client
      return instantTopic(topic, in: room, using: client)
    }

    public func instantTopic<
      Message: Codable & Sendable,
      Name: InstantRoomTopic
    >(
      _ topic: Topic<Message, Name>,
      in room: InstantRoom<Name.RoomSchema>,
      using client: InstantSwiftDataClient
    ) -> some View {
      task {
        do {
          try await topic.task(in: room, using: client)
        } catch is CancellationError {
        } catch {
          // Topic records its renderable observation failure.
        }
      }
    }
  }
#endif
