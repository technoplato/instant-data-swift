import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct StroopwafelV3Screen: View {
    @InstantAuth(StroopwafelV3User.self, providers: StroopwafelV3AuthProviders.self)
    private var auth
    @FetchOne private var profile: StroopwafelV3User?
    @Dependency(\.defaultInstantSwiftData) private var db

    @State private var handle = ""
    @State private var message = "Continue as a guest to play"

    private let injectedUserID: InstantID<StroopwafelV3User>?
    private let initialRoomCode: String?

    public init() {
      injectedUserID = nil
      initialRoomCode = nil
    }

    public init(
      userID: InstantID<StroopwafelV3User>,
      roomCode: String? = nil
    ) {
      injectedUserID = userID
      initialRoomCode = roomCode
    }

    public var body: some View {
      Group {
        if let injectedUserID {
          StroopwafelV3InjectedScreen(
            userID: injectedUserID,
            roomCode: initialRoomCode
          )
        } else if auth.user != nil, let profile, profile.handle?.isEmpty == false {
          StroopwafelV3LobbyScreen(user: profile)
        } else {
          Form {
            Section("Stroopwafel") {
              Text(message)
              if let user = auth.user {
                TextField("Handle", text: $handle)
                Button("Create profile") { createProfile(user) }
                  .disabled(handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              } else {
                Button("Continue as guest", action: signInAsGuest)
              }
            }
          }
        }
      }
      .disabled(auth.isBusy)
      .overlay { if auth.isBusy { ProgressView() } }
      .task(id: auth.user?.id) {
        do {
          try await $profile.task(profileQuery)
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private var profileQuery: InstantQuery<StroopwafelV3User>? {
      auth.user.map {
        InstantQuery(filters: [.equals(field: "id", value: .string($0.id.rawValue))])
      }
    }

    private func signInAsGuest() {
      auth.signInAsGuest(
        onSignedIn: { _ in message = "Choose your handle" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func createProfile(_ user: InstantAuthUser<StroopwafelV3User>) {
      let value = handle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      db.send(
        SetupStroopwafelV3Profile(
          userID: user.id,
          handle: value,
          email: nil,
          createdAt: Self.timestamp(Date())
        ),
        onOptimisticCommit: { _ in message = "Profile created" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    fileprivate static func timestamp(_ date: Date) -> String {
      ISO8601DateFormatter().string(from: date)
    }
  }

  @MainActor
  private struct StroopwafelV3InjectedScreen: View {
    @FetchOne private var user: StroopwafelV3User?

    let userID: InstantID<StroopwafelV3User>
    let roomCode: String?

    var body: some View {
      Group {
        if let user {
          StroopwafelV3LobbyScreen(user: user, initialRoomCode: roomCode)
        } else {
          ProgressView("Loading player")
        }
      }
      .task(id: userID) {
        do {
          try await $user.task(
            InstantQuery(filters: [.equals(field: "id", value: .string(userID.rawValue))])
          )
        } catch {
          // FetchOne exposes the renderable error through loadError.
        }
      }
    }
  }

  @MainActor
  public struct StroopwafelV3LobbyScreen: View {
    @FetchOne private var room: StroopwafelV3Room?
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var joinCode = ""
    @State private var activeCode: String?
    @State private var message = "Create a room or enter a code"

    public let user: StroopwafelV3User

    public init(user: StroopwafelV3User, initialRoomCode: String? = nil) {
      self.user = user
      _joinCode = State(initialValue: initialRoomCode ?? "")
      _activeCode = State(initialValue: initialRoomCode)
    }

    public var body: some View {
      NavigationStack {
        Group {
          if let room {
            if let gameID = room.currentGameID {
              StroopwafelV3GameScreen(
                gameID: InstantID(rawValue: gameID),
                user: user,
                onLeave: leaveRoom
              )
            } else {
              waitingRoom(room)
            }
          } else {
            lobby
          }
        }
        .navigationTitle("Stroopwafel")
      }
      .task(id: activeCode) {
        do {
          try await $room.task(activeCode.map(StroopwafelV3Room.forCode))
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private var lobby: some View {
      Form {
        Section("Welcome, \(user.handle ?? "Guest")") {
          Button("Create room", action: createRoom)
          TextField("Room code", text: $joinCode)
          Button("Join room", action: joinRoom)
            .disabled(normalizedJoinCode.isEmpty)
        }
        Text(message)
      }
    }

    private func waitingRoom(_ room: StroopwafelV3Room) -> some View {
      List {
        Section("Room \(room.code ?? "closed")") {
          ForEach(room.users) { player in
            HStack {
              Text(player.handle ?? player.id.rawValue)
              Spacer()
              if player.id.rawValue == room.hostID {
                Text("Host")
              } else if room.readyIDs.values.contains(player.id.rawValue) {
                Text("Ready")
              }
              if isHost, player.id != user.id {
                Button("Kick") { kick(player, from: room) }
              }
            }
          }
        }
        Section {
          if isHost {
            Button("Start game") { startGame(in: room) }
              .disabled(room.users.count < 2 || room.readyIDs.values.isEmpty)
          } else {
            Button(isReady(in: room) ? "Not ready" : "Ready") {
              setReady(!isReady(in: room), in: room)
            }
          }
          Button("Leave room", role: .destructive) { leaveRoom(room) }
        }
        Text(message)
      }
    }

    private var normalizedJoinCode: String {
      joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var isHost: Bool {
      room?.hostID == user.id.rawValue
    }

    private func isReady(in room: StroopwafelV3Room) -> Bool {
      room.readyIDs.values.contains(user.id.rawValue)
    }

    private func createRoom() {
      let roomID = InstantID<StroopwafelV3Room>(rawValue: uuid().uuidString.lowercased())
      let code = String(uuid().uuidString.prefix(4)).uppercased()
      db.send(
        CreateStroopwafelV3Room(
          roomID: roomID,
          code: code,
          hostID: user.id,
          createdAt: StroopwafelV3Screen.timestamp(Date())
        ),
        onOptimisticCommit: { _ in activeCode = code },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func joinRoom() {
      let code = normalizedJoinCode
      Task {
        do {
          guard let room = try await db.query(StroopwafelV3Room.forCode(code)).first else {
            message = "Room not found"
            return
          }
          let prepared = try await JoinStroopwafelV3Room(room: room, userID: user.id)
            .prepare(using: db)
          _ = try await db.transact {
            for mutation in prepared.mutations { mutation }
          }
          activeCode = code
          message = "Joined room"
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func setReady(_ value: Bool, in room: StroopwafelV3Room) {
      db.send(
        SetStroopwafelV3Ready(room: room, userID: user.id, isReady: value),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func kick(_ player: StroopwafelV3User, from room: StroopwafelV3Room) {
      db.send(
        KickStroopwafelV3Player(room: room, userID: player.id),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func startGame(in room: StroopwafelV3Room) {
      let gameID = InstantID<StroopwafelV3Game>(rawValue: uuid().uuidString.lowercased())
      let playerIDs = room.users.map(\.id.rawValue).filter {
        $0 == room.hostID || room.readyIDs.values.contains($0)
      }
      let pointIDs = Dictionary(uniqueKeysWithValues: playerIDs.map {
        ($0, InstantID<StroopwafelV3Point>(rawValue: uuid().uuidString.lowercased()))
      })
      let colors = StroopwafelV3ColorSequence(
        StroopwafelExample.generateGameColors(seed: gameID.rawValue).map {
          .init(color: $0.color, label: $0.label)
        }
      )
      db.send(
        StartStroopwafelV3Game(
          room: room,
          gameID: gameID,
          pointIDsByPlayerID: pointIDs,
          colors: colors,
          createdAt: StroopwafelV3Screen.timestamp(Date())
        ),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func leaveRoom(_ room: StroopwafelV3Room) {
      db.send(
        LeaveStroopwafelV3Room(
          room: room,
          userID: user.id,
          deletedAt: StroopwafelV3Screen.timestamp(Date())
        ),
        onOptimisticCommit: { _ in activeCode = nil },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct StroopwafelV3GameScreen: View {
    @FetchOne private var game: StroopwafelV3Game?
    @Dependency(\.defaultInstantSwiftData) private var db

    public let gameID: InstantID<StroopwafelV3Game>
    public let user: StroopwafelV3User
    public let onLeave: (StroopwafelV3Room) -> Void

    @State private var message = "Match the label, not the ink"

    public init(
      gameID: InstantID<StroopwafelV3Game>,
      user: StroopwafelV3User,
      onLeave: @escaping (StroopwafelV3Room) -> Void
    ) {
      self.gameID = gameID
      self.user = user
      self.onLeave = onLeave
    }

    public var body: some View {
      Group {
        if let game {
          List {
            Section("Scores") {
              ForEach(game.points) { point in
                Text("\(playerName(point.userID, in: game)): \(point.value)")
              }
            }
            if game.status == StroopwafelExample.gameCompleted {
              Section("Game over") {
                if let room = game.rooms.first {
                  Button("Play again") { playAgain(room) }
                  Button("Leave room", role: .destructive) { onLeave(room) }
                }
              }
            } else if let prompt = currentPrompt(in: game) {
              Section {
                Text(prompt.label.capitalized)
                  .foregroundStyle(Color(stroopwafelName: prompt.color))
                  .font(.largeTitle.bold())
                ForEach(StroopwafelExample.colorChoices, id: \.self) { color in
                  Button(color.capitalized) { tap(color, in: game) }
                }
              }
            }
            Text(message)
          }
        } else {
          ProgressView("Loading game")
        }
      }
      .task(id: gameID) {
        do {
          try await $game.task(StroopwafelV3Game.byID(gameID))
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func currentPrompt(in game: StroopwafelV3Game) -> StroopwafelV3ColorPrompt? {
      guard let score = game.points.first(where: { $0.userID == user.id.rawValue })?.value,
        game.colors.values.indices.contains(score)
      else { return nil }
      return game.colors.values[score]
    }

    private func playerName(_ userID: String, in game: StroopwafelV3Game) -> String {
      game.users.first { $0.id.rawValue == userID }?.handle ?? userID
    }

    private func tap(_ color: String, in game: StroopwafelV3Game) {
      db.send(
        TapStroopwafelV3Color(game: game, userID: user.id, selectedColor: color),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func playAgain(_ room: StroopwafelV3Room) {
      db.send(
        PlayAgainStroopwafelV3(room: room),
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  private extension Color {
    init(stroopwafelName name: String) {
      switch name {
      case "red": self = .red
      case "green": self = .green
      case "blue": self = .blue
      case "yellow": self = .yellow
      default: self = .primary
      }
    }
  }
#endif
