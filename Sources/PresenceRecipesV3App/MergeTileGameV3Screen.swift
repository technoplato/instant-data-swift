import Foundation
import InstantSwiftData

public struct MergeTileGameV3BoardPatch: Codable, Equatable, Sendable {
  public var state: [String: String]

  public init(state: [String: String]) {
    self.state = state
  }
}

public struct MergeTileGameV3BoardState:
  Codable,
  Equatable,
  ExpressibleByDictionaryLiteral,
  Hashable,
  InstantJSONWireValue,
  InstantValueDecodable,
  Sendable
{
  public private(set) var values: [String: String]

  public init(_ values: [String: String]) {
    self.values = values
  }

  public init(dictionaryLiteral elements: (String, String)...) {
    self.init(Dictionary(uniqueKeysWithValues: elements))
  }

  public subscript(key: String) -> String? {
    get { values[key] }
    set { values[key] = newValue }
  }

  public var count: Int { values.count }

  public var instantValue: InstantValue {
    .json(.object(values.mapValues(JSONValue.string)))
  }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .json(.object(object)) = value else {
      throw decodeError(
        value: value,
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation,
        expected: "a JSON object"
      )
    }

    var values: [String: String] = [:]
    for (key, value) in object {
      guard case let .string(color) = value else {
        throw decodeError(
          value: .json(.object(object)),
          namespace: namespace,
          path: "\(path).\(key)",
          localID: localID,
          operation: operation,
          expected: "a string color"
        )
      }
      values[key] = color
    }
    return Self(values)
  }

  private static func decodeError(
    value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID,
      message: "Expected \(expected), received \(String(describing: value)).",
      recovery: "Keep the Merge Tile Game board state aligned with the canonical string map."
    )
  }
}

@InstantEntity("boards")
public struct MergeTileGameV3Board: Codable, Equatable, Hashable, InstantEntityModel {
  public static let boardID = "83c059e2-ed47-42e5-bdd9-6de88d26c521"
  public static let fixedID = InstantID<Self>(rawValue: boardID)
  public static let boardSize = 4
  public static let emptyColor = "#f5f3f0"
  public static let colors = [
    "#e76f51", "#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0",
  ]

  public var id: InstantID<Self>

  @InstantWire(.json)
  public var state: MergeTileGameV3BoardState

  public init(id: String = boardID, state: [String: String]) {
    self.id = InstantID(rawValue: id)
    self.state = MergeTileGameV3BoardState(state)
  }

  public init(id: InstantID<Self> = fixedID, state: MergeTileGameV3BoardState) {
    self.id = id
    self.state = state
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    state = try MergeTileGameV3BoardState.decodeInstantValue(
      snapshot.values["state"]?.first,
      namespace: Self.instantNamespace,
      path: "state",
      localID: snapshot.id,
      operation: "decode Merge Tile Game V3 board"
    )
  }

  public static var emptyState: [String: String] {
    Dictionary(
      uniqueKeysWithValues: (0..<boardSize).flatMap { row in
        (0..<boardSize).map { column in
          ("\(row)-\(column)", emptyColor)
        }
      }
    )
  }

  public static var empty: Self {
    Self(state: MergeTileGameV3BoardState(emptyState))
  }

  public var stateObject: [String: String] { state.values }

  public func color(row: Int, column: Int) -> String? {
    state["\(row)-\(column)"]
  }

  public static func mergePatch(
    row: Int,
    column: Int,
    color: String
  ) -> MergeTileGameV3BoardPatch {
    MergeTileGameV3BoardPatch(state: ["\(row)-\(column)": color])
  }

  public mutating func merge(_ patch: MergeTileGameV3BoardPatch) {
    for (key, color) in patch.state {
      state[key] = color
    }
  }

  public mutating func reset() {
    self = .empty
  }
}

public struct MergeTileGameV3BoardInitialized: Equatable, Sendable {
  public var id: InstantID<MergeTileGameV3Board>

  public init(id: InstantID<MergeTileGameV3Board>) {
    self.id = id
  }
}

public struct InitializeMergeTileGameV3Board: InstantMessage {
  public init() {}

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MergeTileGameV3BoardInitialized>
  {
    _ = client
    return InstantPreparedMessage(
      change: MergeTileGameV3BoardInitialized(id: MergeTileGameV3Board.fixedID)
    ) {
      MergeTileGameV3Board.create(
        id: MergeTileGameV3Board.fixedID,
        MergeTileGameV3Board.state.set(MergeTileGameV3Board.empty.state)
      )
    }
  }
}

public struct MergeTileGameV3CellPainted: Equatable, Sendable {
  public var row: Int
  public var column: Int
  public var color: String

  public init(row: Int, column: Int, color: String) {
    self.row = row
    self.column = column
    self.color = color
  }
}

public struct PaintMergeTileGameV3Cell: InstantMessage {
  public var row: Int
  public var column: Int
  public var color: String

  public init(row: Int, column: Int, color: String) {
    self.row = row
    self.column = column
    self.color = color
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MergeTileGameV3CellPainted>
  {
    _ = client
    let patch = MergeTileGameV3Board.mergePatch(row: row, column: column, color: color)
    return InstantPreparedMessage(
      change: MergeTileGameV3CellPainted(row: row, column: column, color: color)
    ) {
      MergeTileGameV3Board.merge(
        id: MergeTileGameV3Board.fixedID,
        MergeTileGameV3Board.state.set(MergeTileGameV3BoardState(patch.state))
      )
    }
  }
}

public struct MergeTileGameV3BoardReset: Equatable, Sendable {
  public var id: InstantID<MergeTileGameV3Board>

  public init(id: InstantID<MergeTileGameV3Board>) {
    self.id = id
  }
}

public struct ResetMergeTileGameV3Board: InstantMessage {
  public init() {}

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MergeTileGameV3BoardReset>
  {
    _ = client
    return InstantPreparedMessage(
      change: MergeTileGameV3BoardReset(id: MergeTileGameV3Board.fixedID)
    ) {
      MergeTileGameV3Board.update(
        id: MergeTileGameV3Board.fixedID,
        MergeTileGameV3Board.state.set(MergeTileGameV3Board.empty.state)
      )
    }
  }
}

public struct MergeTileGameV3Presence: Codable, Equatable, Identifiable, Sendable {
  public var id: String { userID }
  public var userID: String
  public var color: String

  public init(userID: String, color: String) {
    self.userID = userID
    self.color = color
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: MergeTileGameV3CodingKey.self)
    userID = try container.decodeIfPresent(
      String.self,
      forKey: MergeTileGameV3CodingKey("userID")
    ) ?? ""
    color = try container.decode(
      String.self,
      forKey: MergeTileGameV3CodingKey("color")
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: MergeTileGameV3CodingKey.self)
    try container.encode(color, forKey: MergeTileGameV3CodingKey("color"))
  }
}

private struct MergeTileGameV3CodingKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}

public struct MergeTileGameV3Room: InstantRoomSchema {
  public typealias Presence = MergeTileGameV3Presence
  public static let roomType = "tile-game-example"
  public static let defaultRoomID = "_defaultRoomId"

  public enum Topic: String, InstantRoomTopic {
    public typealias RoomSchema = MergeTileGameV3Room
    case changed
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class MergeTileGameV3Model: ObservableObject {
    @Published public private(set) var presence: MergeTileGameV3Presence
    @Published public private(set) var peers: [MergeTileGameV3Presence] = []
    @Published public private(set) var players: [MergeTileGameV3Presence] = []

    public let profileID: String
    private let requestedColor: String?

    public init(profileID: String, color: String? = nil) {
      self.profileID = profileID
      requestedColor = color
      presence = MergeTileGameV3Presence(
        userID: profileID,
        color: color ?? MergeTileGameV3Board.colors[0]
      )
    }

    public var availableColors: [String] {
      let taken = Set(players.map(\.color))
      return MergeTileGameV3Board.colors.filter { !taken.contains($0) }
    }

    public var selectedColor: String {
      requestedColor ?? availableColors.first ?? MergeTileGameV3Board.colors[0]
    }

    public func updatePresence(_ values: [MergeTileGameV3Presence]) {
      players = values
      peers = values.filter { $0.userID != profileID }
      presence = MergeTileGameV3Presence(userID: profileID, color: selectedColor)
    }
  }

  @MainActor
  public struct MergeTileGameV3Screen: View {
    @Room private var room: InstantRoom<MergeTileGameV3Room>
    @Presence private var presence: [MergeTileGameV3Presence]
    @StateObject private var model: MergeTileGameV3Model
    @State private var board = MergeTileGameV3Board.empty

    public init(
      profileID: String = UUID().uuidString,
      color: String? = nil
    ) {
      _model = StateObject(
        wrappedValue: MergeTileGameV3Model(profileID: profileID, color: color)
      )
    }

    public var body: some View {
      VStack(spacing: 16) {
        HStack {
          Circle()
            .fill(tileColor(model.selectedColor))
            .frame(width: 12, height: 12)
          Text("Your color")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Reset") { board.reset() }
            .font(.caption)
        }
        .frame(maxWidth: 200)

        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 4), count: 4), spacing: 4) {
          ForEach(0..<MergeTileGameV3Board.boardSize, id: \.self) { row in
            ForEach(0..<MergeTileGameV3Board.boardSize, id: \.self) { column in
              let key = "\(row)-\(column)"
              Button {
                board.merge(.init(state: [key: model.selectedColor]))
              } label: {
                RoundedRectangle(cornerRadius: 8)
                  .fill(tileColor(board.state[key] ?? MergeTileGameV3Board.emptyColor))
                  .frame(width: 44, height: 44)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
      }
      .padding()
      .instantRoom(
        $room,
        InstantRoom<MergeTileGameV3Room>(
          type: MergeTileGameV3Room.roomType,
          id: MergeTileGameV3Room.defaultRoomID
        )
      )
      .presence($presence, in: room, publishing: model.presence)
      .onChange(of: presence) { _, values in model.updatePresence(values) }
      .navigationTitle("Merge Tile Game")
    }

    private func tileColor(_ hex: String) -> Color {
      let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
      return Color(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
      )
    }
  }
#endif
