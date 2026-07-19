import Foundation
import InstantSwiftData

public struct MergeTileGameV3BoardPatch: Codable, Equatable, Sendable {
  public var state: [String: String]

  public init(state: [String: String]) {
    self.state = state
  }
}

public struct MergeTileGameV3Board: Codable, Equatable, Identifiable, Sendable {
  public static let boardID = "83c059e2-ed47-42e5-bdd9-6de88d26c521"
  public static let boardSize = 4
  public static let emptyColor = "#f5f3f0"
  public static let colors = [
    "#e76f51", "#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0",
  ]

  public var id: String
  public var state: [String: String]

  public init(id: String = boardID, state: [String: String]) {
    self.id = id
    self.state = state
  }

  public static var empty: Self {
    Self(
      state: Dictionary(
        uniqueKeysWithValues: (0..<boardSize).flatMap { row in
          (0..<boardSize).map { column in
            ("\(row)-\(column)", emptyColor)
          }
        }
      )
    )
  }

  public static func mergePatch(
    row: Int,
    column: Int,
    color: String
  ) -> MergeTileGameV3BoardPatch {
    MergeTileGameV3BoardPatch(state: ["\(row)-\(column)": color])
  }

  public mutating func merge(_ patch: MergeTileGameV3BoardPatch) {
    state.merge(patch.state) { _, new in new }
  }

  public mutating func reset() {
    self = .empty
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
