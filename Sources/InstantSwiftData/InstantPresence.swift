#if canImport(SwiftUI)
  import Combine
  import Dependencies
  import Foundation
  import SwiftUI

  @MainActor
  private final class InstantPresenceState<Value: Codable & Sendable>: ObservableObject {
    @Published var values: [Value]
    @Published var error: InstantError?
    @Published var isLoading = false

    private var observationGeneration = 0

    init(values: [Value]) {
      self.values = values
    }

    func observe(
      room: InstantRoomHandle,
      using client: InstantSwiftDataClient
    ) async throws {
      observationGeneration += 1
      let generation = observationGeneration
      values = []
      error = nil
      isLoading = true

      do {
        let subscription = try await client.subscribeRoomPresence(room: room)
        defer { subscription.cancel() }
        try Task.checkCancellation()

        for try await members in subscription {
          try Task.checkCancellation()
          guard observationGeneration == generation else {
            throw CancellationError()
          }
          values = try members.map { member in
            var object = member.values
            if object["userID"] == nil {
              object["userID"] = .string(member.userID)
            }
            return try InstantRoomCodableJSON.decode(Value.self, from: object)
          }
          error = nil
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
        error = nil
        isLoading = false
        throw CancellationError()
      } catch let instantError as InstantError {
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        error = instantError
        isLoading = false
        throw instantError
      } catch {
        guard observationGeneration == generation else {
          throw CancellationError()
        }
        let instantError = InstantError(
          code: .decodeFailed,
          operation: "observe typed room presence",
          message: String(describing: error),
          recovery: "Keep the room presence schema aligned with the published JSON object."
        )
        self.error = instantError
        isLoading = false
        throw instantError
      }
    }

    func publish(
      _ value: Value?,
      room: InstantRoomHandle,
      using client: InstantSwiftDataClient
    ) async throws {
      do {
        if let value {
          let object = try InstantRoomCodableJSON.encodeObject(value)
          _ = try await client.setRoomPresence(room: room, values: object)
        } else {
          _ = try await client.leaveRoomPresence(room: room)
        }
        error = nil
      } catch is CancellationError {
        throw CancellationError()
      } catch let instantError as InstantError {
        error = instantError
        throw instantError
      } catch {
        let instantError = InstantError(
          code: .implementationFailed,
          operation: "publish typed room presence",
          message: String(describing: error),
          recovery: "Inspect the presence value and configured room client."
        )
        self.error = instantError
        throw instantError
      }
    }
  }

  @MainActor
  private final class InstantPresenceStateReference<Value: Codable & Sendable> {
    var value: InstantPresenceState<Value>

    init(_ value: InstantPresenceState<Value>) {
      self.value = value
    }
  }

  @MainActor
  @propertyWrapper
  public struct Presence<Value: Codable & Sendable>: DynamicProperty {
    private let stateReference: InstantPresenceStateReference<Value>
    @StateObject private var stateObserver: InstantPresenceState<Value>

    private var state: InstantPresenceState<Value> {
      stateReference.value
    }

    public init(wrappedValue: [Value] = []) {
      let state = InstantPresenceState(values: wrappedValue)
      stateReference = InstantPresenceStateReference(state)
      _stateObserver = StateObject(wrappedValue: state)
    }

    public var wrappedValue: [Value] {
      state.values
    }

    public var projectedValue: Self {
      self
    }

    public var loadError: InstantError? {
      state.error
    }

    public var isLoading: Bool {
      state.isLoading
    }

    public mutating func update() {
      stateReference.value = stateObserver
    }

    public func task<Schema: InstantRoomSchema>(
      in room: InstantRoom<Schema>,
      using client: InstantSwiftDataClient
    ) async throws where Schema.Presence == Value {
      guard let handle = room.handle else {
        state.values = []
        state.isLoading = false
        return
      }
      try await state.observe(room: handle, using: client)
    }

    public func publish<Schema: InstantRoomSchema>(
      _ value: Value?,
      in room: InstantRoom<Schema>,
      using client: InstantSwiftDataClient
    ) async throws where Schema.Presence == Value {
      guard let handle = room.handle else { return }
      try await state.publish(value, room: handle, using: client)
    }
  }

  private struct InstantPresencePublicationID: Hashable {
    var room: InstantRoomHandle?
    var value: JSONValue?
  }

  extension View {
    public func presence<Schema: InstantRoomSchema>(
      _ presence: Presence<Schema.Presence>,
      in room: InstantRoom<Schema>,
      publishing currentValue: Schema.Presence?
    ) -> some View {
      @Dependency(\.defaultInstantSwiftData) var client
      return self.presence(
        presence,
        in: room,
        publishing: currentValue,
        using: client
      )
    }

    public func presence<Schema: InstantRoomSchema>(
      _ presence: Presence<Schema.Presence>,
      in room: InstantRoom<Schema>,
      publishing currentValue: Schema.Presence?,
      using client: InstantSwiftDataClient
    ) -> some View {
      let publicationID = InstantPresencePublicationID(
        room: room.handle,
        value: currentValue.flatMap { try? InstantRoomCodableJSON.encode($0) }
      )
      return task(id: room.handle) {
        do {
          try await presence.task(in: room, using: client)
        } catch is CancellationError {
        } catch {
          // Presence records its renderable observation failure.
        }
      }
      .task(id: publicationID) {
        do {
          try await presence.publish(currentValue, in: room, using: client)
        } catch is CancellationError {
        } catch {
          // Presence records its renderable publication failure.
        }
      }
    }
  }

  enum InstantRoomCodableJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> JSONValue {
      let data = try JSONEncoder().encode(value)
      let object = try JSONSerialization.jsonObject(
        with: data,
        options: [.fragmentsAllowed]
      )
      return try jsonValue(from: object)
    }

    static func encodeObject<Value: Encodable>(
      _ value: Value
    ) throws -> [String: JSONValue] {
      guard case let .object(object) = try encode(value) else {
        throw InstantError(
          code: .validationFailed,
          operation: "encode typed room value",
          message: "Room presence must encode as a JSON object.",
          recovery: "Use a Codable struct for the room presence schema."
        )
      }
      return object
    }

    static func decode<Value: Decodable>(
      _ type: Value.Type,
      from object: [String: JSONValue]
    ) throws -> Value {
      try decode(type, from: .object(object))
    }

    static func decode<Value: Decodable>(
      _ type: Value.Type,
      from value: JSONValue
    ) throws -> Value {
      let foundationObject = foundationValue(from: value)
      let data = try JSONSerialization.data(
        withJSONObject: foundationObject,
        options: [.fragmentsAllowed, .sortedKeys]
      )
      return try JSONDecoder().decode(type, from: data)
    }

    private static func jsonValue(from value: Any) throws -> JSONValue {
      switch value {
      case is NSNull:
        return .null
      case let value as Bool:
        return .bool(value)
      case let value as NSNumber:
        return .number(value.doubleValue)
      case let value as String:
        return .string(value)
      case let value as [Any]:
        return .array(try value.map(jsonValue(from:)))
      case let value as [String: Any]:
        return .object(try value.mapValues(jsonValue(from:)))
      default:
        throw InstantError(
          code: .validationFailed,
          operation: "encode typed room value",
          message: "Unsupported JSON value \(String(describing: value)).",
          recovery: "Use Codable values supported by JSONEncoder."
        )
      }
    }

    private static func foundationValue(from value: JSONValue) -> Any {
      switch value {
      case .null:
        return NSNull()
      case let .bool(value):
        return value
      case let .number(value):
        return value
      case let .string(value):
        return value
      case let .array(values):
        return values.map(foundationValue(from:))
      case let .object(values):
        return values.mapValues(foundationValue(from:))
      }
    }
  }
#endif
