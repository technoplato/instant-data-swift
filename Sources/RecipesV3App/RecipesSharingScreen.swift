import Dependencies
import Foundation
import InstantSwiftData
import SwiftUI

// MARK: - Models (plain sharing demo)

/// Public counter — anyone authenticated or guest can read/write (allow-all).
@InstantEntity("recipe_public_counters")
public struct RecipePublicCounter: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var value: Double
  public var updatedAt: Date

  public init(id: InstantID<Self>, value: Double, updatedAt: Date) {
    self.id = id
    self.value = value
    self.updatedAt = updatedAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .number(value) = snapshot.values["value"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode RecipePublicCounter",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected value and updatedAt.",
        recovery: "Align the sharing recipe schema."
      )
    }
    self.value = value
    self.updatedAt = updatedAt
  }

  public static let publicEntityID = InstantID<RecipePublicCounter>(rawValue: "public-counter")
}

/// Account counter — one row per user id; owner field gates writes after perms push.
@InstantEntity("recipe_account_counters")
public struct RecipeAccountCounter: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var ownerUserID: String
  public var value: Double
  public var updatedAt: Date

  public init(id: InstantID<Self>, ownerUserID: String, value: Double, updatedAt: Date) {
    self.id = id
    self.ownerUserID = ownerUserID
    self.value = value
    self.updatedAt = updatedAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(ownerUserID) = snapshot.values["ownerUserID"]?.first,
      case let .number(value) = snapshot.values["value"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode RecipeAccountCounter",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected ownerUserID, value, and updatedAt.",
        recovery: "Align the sharing recipe schema."
      )
    }
    self.ownerUserID = ownerUserID
    self.value = value
    self.updatedAt = updatedAt
  }
}

/// Private note owned by a fixed "other" user — used to probe unauthorized reads.
@InstantEntity("recipe_private_notes")
public struct RecipePrivateNote: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var ownerUserID: String
  public var body: String
  public var updatedAt: Date

  public init(id: InstantID<Self>, ownerUserID: String, body: String, updatedAt: Date) {
    self.id = id
    self.ownerUserID = ownerUserID
    self.body = body
    self.updatedAt = updatedAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(ownerUserID) = snapshot.values["ownerUserID"]?.first,
      case let .string(body) = snapshot.values["body"]?.first,
      case let .date(updatedAt) = snapshot.values["updatedAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode RecipePrivateNote",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected ownerUserID, body, and updatedAt.",
        recovery: "Align the sharing recipe schema."
      )
    }
    self.ownerUserID = ownerUserID
    self.body = body
    self.updatedAt = updatedAt
  }

  public static let otherUserSecretID = InstantID<RecipePrivateNote>(
    rawValue: "other-user-secret-note"
  )
  public static let otherUserID = "demo-other-user-not-you"
}

public enum RecipesSharingAttributes {
  public static var all: [InstantAttribute] {
    RecipePublicCounter.instantAttributes
      + RecipeAccountCounter.instantAttributes
      + RecipePrivateNote.instantAttributes
  }
}

// MARK: - Screen

@MainActor
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct RecipesSharingScreen: View {
  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.date.now) private var now
  @AuthSession private var auth: InstantAuthSession?

  @FetchAll(RecipePublicCounter.query.limit(8))
  private var publicCounters: [RecipePublicCounter]

  @FetchAll(RecipeAccountCounter.query.limit(32))
  private var accountCounters: [RecipeAccountCounter]

  @State private var message = ""
  @State private var unauthorizedResult = "Not tried yet"
  @State private var isBusy = false

  private let wrapsInNavigationStack: Bool

  public init(wrapsInNavigationStack: Bool = true) {
    self.wrapsInNavigationStack = wrapsInNavigationStack
  }

  public var body: some View {
    Group {
      if wrapsInNavigationStack {
        NavigationStack { content }
      } else {
        content
      }
    }
  }

  private var content: some View {
    List {
      Section("Session") {
        if let auth {
          LabeledContent("User", value: auth.userID)
          LabeledContent("Guest", value: auth.isGuest ? "yes" : "no")
        } else {
          Text("Not signed in")
            .foregroundStyle(.secondary)
          Button("Sign in as guest") {
            Task { await signInAsGuest() }
          }
        }
      }

      Section {
        Text(
          """
          Public = anyone on this app can increment. \
          Mine = only your user id’s counter. \
          Unauthorized = try to read a note owned by demo-other-user-not-you.
          """
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Public counter (shared with everyone)") {
        LabeledContent("Value", value: "\(Int(publicCounterValue))")
        Button("Increment public") {
          Task { await incrementPublic() }
        }
        .disabled(isBusy)
      }

      Section("My account counter (only me)") {
        if let mine = myAccountCounter {
          LabeledContent("Value", value: "\(Int(mine.value))")
          LabeledContent("Owner", value: mine.ownerUserID)
        } else {
          Text("No account counter yet")
            .foregroundStyle(.secondary)
        }
        Button("Increment mine") {
          Task { await incrementMine() }
        }
        .disabled(isBusy || auth == nil)
      }

      Section("Unauthorized read probe") {
        Text(unauthorizedResult)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
        Button("Seed other-user secret (local write)") {
          Task { await seedOtherUserSecret() }
        }
        .disabled(isBusy)
        Button("Try to read other-user secret") {
          Task { await tryUnauthorizedRead() }
        }
        .disabled(isBusy)
        Text(
          """
          After permissions are pushed, only ownerUserID may view recipe_private_notes. \
          Until then this app may still see local cache rows — the probe still records \
          the attempt outcome so auth gaps stay visible.
          """
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      if !message.isEmpty {
        Section("Status") {
          Text(message)
            .font(.caption)
        }
      }
    }
    .navigationTitle("Sharing")
    .task {
      await ensurePublicCounterExists()
    }
  }

  private var publicCounter: RecipePublicCounter? {
    publicCounters.first { $0.id == RecipePublicCounter.publicEntityID }
      ?? publicCounters.first
  }

  private var publicCounterValue: Double {
    publicCounter?.value ?? 0
  }

  private var myAccountCounter: RecipeAccountCounter? {
    guard let userID = auth?.userID else { return nil }
    return accountCounters.first { $0.ownerUserID == userID || $0.id.rawValue == userID }
  }

  private func signInAsGuest() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let session = try await db.signInAsGuest()
      message = "Signed in as guest \(session.userID)"
    } catch {
      message = String(describing: error)
    }
  }

  private func ensurePublicCounterExists() async {
    guard publicCounter == nil else { return }
    let stamp = now
    do {
      try await db.transact {
        RecipePublicCounter.create(
          id: RecipePublicCounter.publicEntityID,
          RecipePublicCounter.value.set(0),
          RecipePublicCounter.updatedAt.set(stamp)
        )
      }
    } catch {
      // May already exist remotely.
      message = "Public counter bootstrap: \(error)"
    }
  }

  private func incrementPublic() async {
    isBusy = true
    defer { isBusy = false }
    let next = publicCounterValue + 1
    let stamp = now
    let needsCreate = publicCounter == nil
    do {
      try await db.transact {
        if needsCreate {
          RecipePublicCounter.create(
            id: RecipePublicCounter.publicEntityID,
            RecipePublicCounter.value.set(next),
            RecipePublicCounter.updatedAt.set(stamp)
          )
        } else {
          RecipePublicCounter.update(
            id: RecipePublicCounter.publicEntityID,
            RecipePublicCounter.value.set(next),
            RecipePublicCounter.updatedAt.set(stamp)
          )
        }
      }
      message = "Public counter → \(Int(next))"
    } catch {
      message = String(describing: error)
    }
  }

  private func incrementMine() async {
    guard let userID = auth?.userID else {
      message = "Sign in first (guest is fine)."
      return
    }
    isBusy = true
    defer { isBusy = false }
    let id = InstantID<RecipeAccountCounter>(rawValue: userID)
    let next = (myAccountCounter?.value ?? 0) + 1
    let stamp = now
    let needsCreate = myAccountCounter == nil
    do {
      try await db.transact {
        if needsCreate {
          RecipeAccountCounter.create(
            id: id,
            RecipeAccountCounter.ownerUserID.set(userID),
            RecipeAccountCounter.value.set(next),
            RecipeAccountCounter.updatedAt.set(stamp)
          )
        } else {
          RecipeAccountCounter.update(
            id: id,
            RecipeAccountCounter.ownerUserID.set(userID),
            RecipeAccountCounter.value.set(next),
            RecipeAccountCounter.updatedAt.set(stamp)
          )
        }
      }
      message = "My counter → \(Int(next))"
    } catch {
      message = String(describing: error)
    }
  }

  private func seedOtherUserSecret() async {
    isBusy = true
    defer { isBusy = false }
    let stamp = now
    do {
      try await db.transact {
        RecipePrivateNote.create(
          id: RecipePrivateNote.otherUserSecretID,
          RecipePrivateNote.ownerUserID.set(RecipePrivateNote.otherUserID),
          RecipePrivateNote.body.set("secret-for-demo-other-user"),
          RecipePrivateNote.updatedAt.set(stamp)
        )
      }
      message = "Seeded other-user secret note locally (and outbox if live)."
    } catch {
      // Update if exists
      do {
        try await db.transact {
          RecipePrivateNote.update(
            id: RecipePrivateNote.otherUserSecretID,
            RecipePrivateNote.ownerUserID.set(RecipePrivateNote.otherUserID),
            RecipePrivateNote.body.set("secret-for-demo-other-user"),
            RecipePrivateNote.updatedAt.set(stamp)
          )
        }
        message = "Updated other-user secret note."
      } catch {
        message = String(describing: error)
      }
    }
  }

  private func tryUnauthorizedRead() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let rows = try await db.query(RecipePrivateNote.query.limit(20))
      let note = rows.first { $0.id == RecipePrivateNote.otherUserSecretID }
      if let note {
        unauthorizedResult =
          """
          SAW note id=\(note.id.rawValue) owner=\(note.ownerUserID) body=\(note.body). \
          If you are not that owner, permissions are too open (or this is local cache).
          """
      } else {
        unauthorizedResult =
          "Empty result (denied or missing). auth=\(auth?.userID ?? "nil")"
      }
    } catch {
      unauthorizedResult = "Read failed (expected under tight perms): \(error)"
    }
  }
}
