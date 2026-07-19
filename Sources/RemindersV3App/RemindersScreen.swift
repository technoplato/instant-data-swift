import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct RemindersV3Screen: View {
    @InstantAuth(RemindersV3User.self, providers: RemindersV3AuthProviders.self)
    private var auth
    @State private var message = "Sign in to sync and share lists"

    private let injectedUserID: InstantID<RemindersV3User>?

    public init() {
      injectedUserID = nil
    }

    public init(userID: InstantID<RemindersV3User>) {
      injectedUserID = userID
    }

    public var body: some View {
      Group {
        if let userID = injectedUserID ?? auth.user?.id {
          RemindersV3ListsScreen(userID: userID)
        } else {
          ContentUnavailableView {
            Label("Reminders", systemImage: "checklist")
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
  public struct RemindersV3ListsScreen: View {
    @FetchAll private var lists: [RemindersV3List]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var newListTitle = ""
    @State private var message = ""

    public let userID: InstantID<RemindersV3User>

    public init(userID: InstantID<RemindersV3User>) {
      self.userID = userID
    }

    public var body: some View {
      NavigationStack {
        List {
          Section("New list") {
            TextField("List name", text: $newListTitle)
            Button("Add list", action: addList)
              .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          Section("My lists") {
            ForEach(lists) { list in
              NavigationLink {
                RemindersV3ListScreen(listID: list.id, userID: userID)
              } label: {
                HStack {
                  Circle()
                    .fill(Color(hex: list.color))
                    .frame(width: 12, height: 12)
                  Text(list.title)
                  Spacer()
                  Text(list.reminders.filter { !$0.isCompleted }.count, format: .number)
                    .foregroundStyle(.secondary)
                  if list.share != nil {
                    Image(systemName: "person.2")
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }
          if !message.isEmpty {
            Text(message)
          }
        }
        .navigationTitle("Reminders")
      }
      .task(id: userID) {
        do {
          try await $lists.task(RemindersV3List.visible(to: userID))
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func addList() {
      let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return }
      db.send(
        CreateRemindersV3List(
          listID: InstantID(rawValue: uuid().uuidString.lowercased()),
          ownerID: userID,
          title: title,
          position: lists.count,
          createdAt: now
        ),
        onOptimisticCommit: { _ in newListTitle = "" },
        onServerAccepted: { _ in message = "List synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct RemindersV3ListScreen: View {
    @FetchOne private var list: RemindersV3List?
    @FetchAll private var reminders: [RemindersV3Reminder]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var newReminderTitle = ""
    @State private var memberID = ""
    @State private var memberRole = InstantShareRole.reader
    @State private var message = ""

    public let listID: InstantID<RemindersV3List>
    public let userID: InstantID<RemindersV3User>

    public init(
      listID: InstantID<RemindersV3List>,
      userID: InstantID<RemindersV3User>
    ) {
      self.listID = listID
      self.userID = userID
    }

    public var body: some View {
      List {
        Section("Reminders") {
          TextField("New reminder", text: $newReminderTitle)
          Button("Add reminder", action: addReminder)
            .disabled(newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          ForEach(reminders) { reminder in
            HStack {
              Button(action: { toggle(reminder) }) {
                Image(
                  systemName: reminder.isCompleted
                    ? "checkmark.circle.fill"
                    : "circle"
                )
              }
              .buttonStyle(.plain)
              Text(reminder.title)
              Spacer()
              Button(role: .destructive, action: { delete(reminder) }) {
                Image(systemName: "trash")
              }
              .buttonStyle(.plain)
            }
          }
        }
        if let list {
          Section("Sharing") {
            if let share = list.share {
              Text("Token: \(share.token)")
                .textSelection(.enabled)
              ForEach(share.memberships) { membership in
                HStack {
                  Text(membership.user.rawValue)
                  Spacer()
                  Text(membership.role)
                    .foregroundStyle(.secondary)
                  if membership.shareRole != .owner {
                    Button("Revoke") { revoke(membership, share: share) }
                  }
                }
              }
              TextField("Member user ID", text: $memberID)
              Picker("Role", selection: $memberRole) {
                Text("Reader").tag(InstantShareRole.reader)
                Text("Writer").tag(InstantShareRole.writer)
              }
              Button("Grant access") { grantAccess(on: share) }
                .disabled(memberID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
              Button("Create share link", action: createShare)
            }
          }
        }
        if !message.isEmpty {
          Text(message)
        }
      }
      .navigationTitle(list?.title ?? "Reminders")
      .task(id: listID) {
        do {
          async let loadList: Void = $list.task(
            RemindersV3List.byID(listID, visibleTo: userID)
          )
          async let loadReminders: Void = $reminders.task(
            RemindersV3Reminder.forList(listID, includeCompleted: true)
          )
          _ = try await (loadList, loadReminders)
        } catch is CancellationError {
        } catch {
          message = String(describing: error)
        }
      }
    }

    private func addReminder() {
      let title = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return }
      db.send(
        CreateRemindersV3Reminder(
          reminderID: InstantID(rawValue: uuid().uuidString.lowercased()),
          listID: listID,
          title: title,
          position: reminders.count,
          createdAt: now
        ),
        onOptimisticCommit: { _ in newReminderTitle = "" },
        onServerAccepted: { _ in message = "Reminder synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func toggle(_ reminder: RemindersV3Reminder) {
      db.send(
        SetRemindersV3Completion(
          reminderID: reminder.id,
          listID: listID,
          isCompleted: !reminder.isCompleted
        ),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func delete(_ reminder: RemindersV3Reminder) {
      db.send(
        DeleteRemindersV3Reminder(reminderID: reminder.id, listID: listID),
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func createShare() {
      let shareID = InstantID<RemindersV3Share>(rawValue: uuid().uuidString.lowercased())
      db.send(
        CreateRemindersV3Share(
          shareID: shareID,
          ownerMembershipID: InstantID(rawValue: uuid().uuidString.lowercased()),
          listID: listID,
          ownerID: userID,
          token: uuid().uuidString.lowercased(),
          createdAt: now
        ),
        onServerAccepted: { _ in message = "Share created" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func grantAccess(on share: RemindersV3Share) {
      let rawMemberID = memberID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !rawMemberID.isEmpty else { return }
      let targetID = InstantID<RemindersV3User>(rawValue: rawMemberID)
      if let membership = share.memberships.first(where: { $0.user == targetID }),
        let previousRole = membership.shareRole
      {
        db.send(
          ChangeRemindersV3ShareRole(
            shareID: share.id,
            membershipID: membership.id,
            listID: listID,
            userID: targetID,
            previousRole: previousRole,
            role: memberRole,
            updatedAt: now
          ),
          onServerAccepted: { _ in message = "Role updated" },
          onFailure: { error in message = error.recoveryMessage }
        )
      } else {
        db.send(
          AcceptRemindersV3Share(
            shareID: share.id,
            membershipID: InstantID(rawValue: uuid().uuidString.lowercased()),
            listID: listID,
            userID: targetID,
            role: memberRole,
            acceptedAt: now
          ),
          onServerAccepted: { _ in message = "Access granted" },
          onFailure: { error in message = error.recoveryMessage }
        )
      }
    }

    private func revoke(
      _ membership: RemindersV3ShareMembership,
      share: RemindersV3Share
    ) {
      guard let role = membership.shareRole else { return }
      db.send(
        RevokeRemindersV3Share(
          shareID: share.id,
          membershipID: membership.id,
          listID: listID,
          userID: membership.user,
          role: role,
          revokedAt: now
        ),
        onServerAccepted: { _ in message = "Access revoked" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  private extension Color {
    init(hex: String) {
      let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        ?? 0x4a99ef
      self.init(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
      )
    }
  }
#endif
