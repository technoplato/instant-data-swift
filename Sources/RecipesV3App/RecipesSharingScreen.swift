import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData
import SwiftUI

// MARK: - Private-note probe (Sharing recipe only)

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

  /// Instant requires entity IDs to be UUIDs.
  public static let otherUserSecretID = InstantID<RecipePrivateNote>(
    rawValue: "f1df43b8-b4a1-58ae-bcc1-6091e7411b79"
  )
  /// Not a real auth user — only used as ownerUserID string for the deny probe.
  public static let otherUserID = "00000000-0000-4000-8000-00000000dead"
}

public enum RecipesSharingAttributes {
  public static var all: [InstantAttribute] {
    AuthV3CounterAttributes.all + RecipePrivateNote.instantAttributes
  }
}

// MARK: - Screen

@MainActor
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct RecipesSharingScreen: View {
  @Dependency(\.defaultInstantSwiftData) private var db
  @Dependency(\.date.now) private var now
  @AuthSession private var auth: InstantAuthSession?

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
          Public + mine counters also live on the Auth recipe (they react to \
          login/logout there). This screen keeps the unauthorized-read probe.
          """
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Counters (same as Auth recipe)") {
        AuthV3CountersCard(session: auth)
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
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
