import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct CloudKitDemoV3Screen: View {
    @InstantAuth(CloudKitDemoV3User.self, providers: CloudKitDemoV3AuthProviders.self)
    private var auth
    @State private var message = "Sign in to sync shared counters"

    private let injectedUserID: InstantID<CloudKitDemoV3User>?

    public init() {
      injectedUserID = nil
    }

    public init(userID: InstantID<CloudKitDemoV3User>) {
      injectedUserID = userID
    }

    public var body: some View {
      Group {
        if let userID = injectedUserID ?? auth.user?.id {
          CloudKitDemoV3CountersScreen(userID: userID)
        } else {
          ContentUnavailableView {
            Label("Shared Counters", systemImage: "person.2.badge.gearshape")
          } description: {
            Text(message)
          } actions: {
            Button("Continue as guest", action: signInAsGuest)
          }
        }
      }
      .disabled(auth.isBusy)
      .overlay { if auth.isBusy { ProgressView() } }
    }

    private func signInAsGuest() {
      auth.signInAsGuest(
        onSignedIn: { _ in message = "Signed in" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct CloudKitDemoV3CountersScreen: View {
    @FetchAll private var counters: [CloudKitDemoV3Counter]
    @Shares private var shares: [InstantShareSnapshot]
    @Dependency(\.date.now) private var now
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var newCounterTitle = ""
    @State private var message = ""

    public let userID: InstantID<CloudKitDemoV3User>

    public init(userID: InstantID<CloudKitDemoV3User>) {
      self.userID = userID
    }

    public var body: some View {
      NavigationStack {
        List {
          Section("New shared counter") {
            TextField("Counter name", text: $newCounterTitle)
            Button("Create", action: createCounter)
              .disabled(newCounterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          Section("Counters") {
            ForEach(counters) { counter in
              NavigationLink {
                CloudKitDemoV3CounterScreen(counter: counter, userID: userID)
              } label: {
                HStack {
                  Text(counter.title)
                  Spacer()
                  Text(counter.value, format: .number)
                  Image(systemName: "person.2")
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          Section("Visible share state") {
            Text("\(shares.count) active share\(shares.count == 1 ? "" : "s")")
          }
          if !message.isEmpty { Text(message) }
        }
        .navigationTitle("Shared Counters")
      }
      .task(id: userID) {
        do {
          async let loadCounters: Void = $counters.task(
            CloudKitDemoV3Counter.visible(to: userID)
          )
          async let loadShares: Void = $shares.task(using: db)
          _ = try await (loadCounters, loadShares)
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func createCounter() {
      let title = newCounterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return }
      db.send(
        CreateCloudKitDemoV3SharedCounter(
          counterID: InstantID(rawValue: uuid().uuidString.lowercased()),
          shareID: InstantID(rawValue: uuid().uuidString.lowercased()),
          ownerMembershipID: InstantID(rawValue: uuid().uuidString.lowercased()),
          ownerID: userID,
          title: title,
          token: uuid().uuidString.lowercased(),
          createdAt: now
        ),
        onOptimisticCommit: { _ in newCounterTitle = "" },
        onServerAccepted: { _ in message = "Counter shared" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct CloudKitDemoV3CounterScreen: View {
    @Dependency(\.date.now) private var now
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var memberID = ""
    @State private var memberRole = InstantShareRole.reader
    @State private var message = ""

    @State public var counter: CloudKitDemoV3Counter
    public let userID: InstantID<CloudKitDemoV3User>

    public init(
      counter: CloudKitDemoV3Counter,
      userID: InstantID<CloudKitDemoV3User>
    ) {
      _counter = State(initialValue: counter)
      self.userID = userID
    }

    public var body: some View {
      List {
        Section("Value") {
          HStack {
            Button("−") { increment(by: -1) }
            Spacer()
            Text(counter.value, format: .number)
              .font(.largeTitle.monospacedDigit())
            Spacer()
            Button("+") { increment(by: 1) }
          }
        }
        if let share = counter.share {
          Section("Share link") {
            Text(share.token).textSelection(.enabled)
          }
          Section("Participants") {
            ForEach(share.memberships) { membership in
              HStack {
                Text(membership.user.rawValue)
                Spacer()
                if membership.shareRole == .owner {
                  Text("Owner").foregroundStyle(.secondary)
                } else if let role = membership.shareRole {
                  Picker("Role", selection: roleBinding(membership, share: share, role: role)) {
                    Text("Read only").tag(InstantShareRole.reader)
                    Text("Read and write").tag(InstantShareRole.writer)
                  }
                  Button("Revoke", role: .destructive) {
                    revoke(membership, share: share, role: role)
                  }
                }
              }
            }
            TextField("Participant user ID", text: $memberID)
            Picker("Access", selection: $memberRole) {
              Text("Read only").tag(InstantShareRole.reader)
              Text("Read and write").tag(InstantShareRole.writer)
            }
            Button("Grant access") { grantAccess(share: share) }
              .disabled(memberID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        if !message.isEmpty { Text(message) }
      }
      .navigationTitle(counter.title)
    }

    private func increment(by delta: Int) {
      db.send(
        IncrementCloudKitDemoV3Counter(counterID: counter.id, delta: delta),
        onOptimisticCommit: { change in counter.value = change.value },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func grantAccess(share: CloudKitDemoV3Share) {
      let rawUserID = memberID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !rawUserID.isEmpty else { return }
      let targetID = InstantID<CloudKitDemoV3User>(rawValue: rawUserID)
      db.send(
        AcceptCloudKitDemoV3Share(
          token: share.token,
          membershipID: InstantID(rawValue: uuid().uuidString.lowercased()),
          userID: targetID,
          acceptedAt: now
        ),
        onServerAccepted: { _ in memberID = ""
          message = "Access granted"
        },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func roleBinding(
      _ membership: CloudKitDemoV3ShareMembership,
      share: CloudKitDemoV3Share,
      role: InstantShareRole
    ) -> Binding<InstantShareRole> {
      Binding(
        get: { role },
        set: { newRole in
          guard newRole != role else { return }
          db.send(
            ChangeCloudKitDemoV3ShareRole(
              shareID: share.id,
              membershipID: membership.id,
              counterID: counter.id,
              userID: membership.user,
              previousRole: role,
              role: newRole,
              updatedAt: now
            ),
            onFailure: { error in message = error.recoveryMessage }
          )
        }
      )
    }

    private func revoke(
      _ membership: CloudKitDemoV3ShareMembership,
      share: CloudKitDemoV3Share,
      role: InstantShareRole
    ) {
      db.send(
        RevokeCloudKitDemoV3Participant(
          shareID: share.id,
          membershipID: membership.id,
          counterID: counter.id,
          userID: membership.user,
          role: role,
          revokedAt: now
        ),
        onServerAccepted: { _ in message = "Access revoked" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }
#endif
