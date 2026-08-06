import Dependencies
import Foundation
import InstantSwiftData

// MARK: - Models (auth-driven sharing demo)

/// Public counter — open read/write (no owner gate). Survives login/logout.
@InstantEntity("recipe_public_counters")
public struct AuthPublicCounter: Hashable, Codable, InstantEntityModel {
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
        operation: "decode AuthPublicCounter",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected value and updatedAt.",
        recovery: "Align the auth/sharing recipe schema."
      )
    }
    self.value = value
    self.updatedAt = updatedAt
  }

  /// Instant requires entity IDs to be UUIDs. Stable UUID so every client shares one row.
  public static let publicEntityID = InstantID<AuthPublicCounter>(
    rawValue: "fdd4f350-833f-5355-bbb9-8bbea92df0ae"
  )
}

/// Account counter — one row per signed-in user id; owner field gates after perms push.
@InstantEntity("recipe_account_counters")
public struct AuthAccountCounter: Hashable, Codable, InstantEntityModel {
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
        operation: "decode AuthAccountCounter",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected ownerUserID, value, and updatedAt.",
        recovery: "Align the auth/sharing recipe schema."
      )
    }
    self.ownerUserID = ownerUserID
    self.value = value
    self.updatedAt = updatedAt
  }
}

public enum AuthV3CounterAttributes {
  public static var all: [InstantAttribute] {
    AuthPublicCounter.instantAttributes + AuthAccountCounter.instantAttributes
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  /// Public + per-account counters for the Auth recipe page.
  ///
  /// Public stays visible for every session (including signed-out). Mine tracks
  /// the current `InstantAuthSession.userID` and disappears on sign-out.
  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct AuthV3CountersCard: View {
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now

    /// Current auth session from `InstantAuthState` so the card re-renders on login/logout.
    public var session: InstantAuthSession?

    @FetchAll(AuthPublicCounter.query.limit(8))
    private var publicCounters: [AuthPublicCounter]

    @FetchAll(AuthAccountCounter.query.limit(32))
    private var accountCounters: [AuthAccountCounter]

    @State private var status = ""
    @State private var isBusy = false

    public init(session: InstantAuthSession?) {
      self.session = session
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        sectionHeader

        HStack(alignment: .top, spacing: 16) {
          publicColumn
          mineColumn
        }

        if !status.isEmpty {
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(22)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
      .task {
        await ensurePublicCounterExists()
      }
      .onChange(of: session?.userID) { _, _ in
        status = session.map { "Session \($0.userID.prefix(8))… — mine counter switches with login." }
          ?? "Signed out — public stays; mine waits for a session."
      }
    }

    private var sectionHeader: some View {
      VStack(alignment: .leading, spacing: 5) {
        Label("Live counters", systemImage: "number.circle.fill")
          .font(.headline)
        Text(
          "Public is shared with everybody (no owner permission). Mine is scoped to the user you just signed in as, and clears when you sign out."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
    }

    private var publicColumn: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text("Public (everyone)")
          .font(.subheadline.weight(.semibold))
        Text("\(Int(publicCounterValue))")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(.snappy, value: publicCounterValue)
        Button {
          Task { await incrementPublic() }
        } label: {
          Text("Increment public").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isBusy)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mineColumn: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text("Mine (this account)")
          .font(.subheadline.weight(.semibold))
        if let mine = myAccountCounter {
          Text("\(Int(mine.value))")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: mine.value)
          Text(mine.ownerUserID)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        } else if session == nil {
          Text("—")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.tertiary)
          Text("Sign in or continue as guest")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("0")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
          Text("No row yet — increment to create")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          Task { await incrementMine() }
        } label: {
          Text("Increment mine").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(isBusy || session == nil)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(session == nil ? 0.85 : 1)
    }

    private var publicCounter: AuthPublicCounter? {
      publicCounters.first { $0.id == AuthPublicCounter.publicEntityID }
        ?? publicCounters.first
    }

    private var publicCounterValue: Double {
      publicCounter?.value ?? 0
    }

    private var myAccountCounter: AuthAccountCounter? {
      guard let userID = session?.userID else { return nil }
      return accountCounters.first { $0.ownerUserID == userID || $0.id.rawValue == userID }
    }

    private func ensurePublicCounterExists() async {
      guard publicCounter == nil else { return }
      let stamp = now
      do {
        try await db.transact {
          AuthPublicCounter.create(
            id: AuthPublicCounter.publicEntityID,
            AuthPublicCounter.value.set(0),
            AuthPublicCounter.updatedAt.set(stamp)
          )
        }
      } catch {
        status = "Public counter bootstrap: \(error)"
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
            AuthPublicCounter.create(
              id: AuthPublicCounter.publicEntityID,
              AuthPublicCounter.value.set(next),
              AuthPublicCounter.updatedAt.set(stamp)
            )
          } else {
            AuthPublicCounter.update(
              id: AuthPublicCounter.publicEntityID,
              AuthPublicCounter.value.set(next),
              AuthPublicCounter.updatedAt.set(stamp)
            )
          }
        }
        status = "Public → \(Int(next))"
      } catch {
        status = String(describing: error)
      }
    }

    private func incrementMine() async {
      guard let userID = session?.userID else {
        status = "Sign in first (guest is fine)."
        return
      }
      isBusy = true
      defer { isBusy = false }
      let id = InstantID<AuthAccountCounter>(rawValue: userID)
      let next = (myAccountCounter?.value ?? 0) + 1
      let stamp = now
      let needsCreate = myAccountCounter == nil
      do {
        try await db.transact {
          if needsCreate {
            AuthAccountCounter.create(
              id: id,
              AuthAccountCounter.ownerUserID.set(userID),
              AuthAccountCounter.value.set(next),
              AuthAccountCounter.updatedAt.set(stamp)
            )
          } else {
            AuthAccountCounter.update(
              id: id,
              AuthAccountCounter.ownerUserID.set(userID),
              AuthAccountCounter.value.set(next),
              AuthAccountCounter.updatedAt.set(stamp)
            )
          }
        }
        status = "Mine → \(Int(next)) for \(userID.prefix(8))…"
      } catch {
        status = String(describing: error)
      }
    }
  }
#endif
