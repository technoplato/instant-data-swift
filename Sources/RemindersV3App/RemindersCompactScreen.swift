import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI) && (os(watchOS) || os(tvOS))
  import SwiftUI

  @MainActor
  @available(tvOS 17.0, watchOS 10.0, *)
  public struct RemindersV3Screen: View {
    @InstantAuth(RemindersV3User.self, providers: RemindersV3AuthProviders.self)
    private var auth
    @State private var message = "Sign in to sync and share lists"
    @FocusState private var focusedAuthField: AuthField?

    private enum AuthField: Hashable {
      case email
      case magicCode
    }

    private let injectedUserID: InstantID<RemindersV3User>?

    public init() {
      injectedUserID = nil
    }

    public init(userID: InstantID<RemindersV3User>) {
      injectedUserID = userID
    }

    public var body: some View {
      Group {
        if let userID = activeUserID {
          RemindersV3CompactListsScreen(
            userID: userID,
            accountTitle: accountTitle,
            canSignOut: injectedUserID == nil,
            onSignOut: signOutButtonTapped
          )
        } else {
          signInScreen
        }
      }
      .disabled(auth.isBusy)
      .overlay {
        if auth.isBusy {
          ProgressView()
        }
      }
    }

    private var activeUserID: InstantID<RemindersV3User>? {
      injectedUserID ?? auth.user?.id
    }

    private var accountTitle: String {
      auth.user?.email?.remindersNonempty
        ?? (auth.session?.isGuest == true ? "Guest account" : "Signed in")
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode:
        true
      default:
        false
      }
    }

    private var signInScreen: some View {
      NavigationStack {
        List {
          Section {
            Label("Reminders", systemImage: "checklist")
              .font(.headline)
            Text(message)
              .foregroundStyle(.secondary)
          }

          Section("Sign in") {
            TextField("Email", text: $auth.email)
              .textContentType(.emailAddress)
              .focused($focusedAuthField, equals: .email)
              .onSubmit(sendMagicCodeButtonTapped)

            if showsMagicCode {
              TextField("Code", text: $auth.magicCode)
                .textContentType(.oneTimeCode)
                .focused($focusedAuthField, equals: .magicCode)
                .onSubmit(verifyCodeButtonTapped)
              Button("Verify code", action: verifyCodeButtonTapped)
              Button("Use a different email", action: differentEmailButtonTapped)
            } else {
              Button("Send magic code", action: sendMagicCodeButtonTapped)
            }
          }

          Section {
            Button("Continue as guest", action: continueAsGuestButtonTapped)
          } footer: {
            Text("Use the same email on every device to see the same owned and shared lists.")
          }
        }
        .navigationTitle("Sign In")
        .defaultFocus($focusedAuthField, .email)
      }
    }

    private func sendMagicCodeButtonTapped() {
      let targetEmail = auth.email.trimmingCharacters(in: .whitespacesAndNewlines)
      guard targetEmail.contains("@"), targetEmail.contains(".") else {
        message = "Enter a valid email address."
        focusedAuthField = .email
        return
      }
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          message = "Code sent to \(challenge.email)"
          focusedAuthField = .magicCode
          record(.notice, event: "compact-magic-code.sent")
        },
        onFailure: handleAuthFailure
      )
    }

    private func verifyCodeButtonTapped() {
      guard !auth.magicCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        message = "Enter the code from your email."
        focusedAuthField = .magicCode
        return
      }
      auth.verifyMagicCode(
        onSignedIn: { event in
          message = "Signed in"
          record(
            .notice,
            event: "compact-magic-code.verified",
            metadata: ["userID": event.session.userID]
          )
        },
        onFailure: handleAuthFailure
      )
    }

    private func differentEmailButtonTapped() {
      auth.resetMagicCode()
      focusedAuthField = .email
    }

    private func continueAsGuestButtonTapped() {
      auth.signInAsGuest(
        onSignedIn: { event in
          message = "Signed in as guest"
          record(
            .notice,
            event: "compact-guest-sign-in.completed",
            metadata: ["userID": event.session.userID]
          )
        },
        onFailure: handleAuthFailure
      )
    }

    private func signOutButtonTapped() {
      auth.signOut(
        onSignedOut: {
          message = "Signed out"
          record(.notice, event: "compact-sign-out.completed")
        },
        onFailure: handleAuthFailure
      )
    }

    private func handleAuthFailure(_ error: InstantError) {
      message = error.recoveryMessage
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "auth",
        event: "compact-auth.failed",
        message: "A compact Reminders authentication operation failed."
      )
    }

    private func record(
      _ level: InstantDiagnosticLevel,
      event: String,
      metadata: [String: String] = [:]
    ) {
      InstantDiagnostics.shared.record(
        level,
        subsystem: "reminders-v3",
        category: "auth",
        event: event,
        message: "The compact Reminders authentication state changed.",
        metadata: metadata
      )
    }
  }

  @MainActor
  @available(tvOS 17.0, watchOS 10.0, *)
  private struct RemindersV3CompactListsScreen: View {
    @FetchAll private var lists: [RemindersV3List]
    @ConnectionStatus private var connectionStatus
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var message = ""

    let userID: InstantID<RemindersV3User>
    let accountTitle: String
    let canSignOut: Bool
    let onSignOut: () -> Void

    var body: some View {
      NavigationStack {
        List {
          Section {
            Label(connectionLabel, systemImage: connectionIcon)
              .accessibilityIdentifier("reminders-sync-status")
          }

          if let list = lists.first {
            Section(list.title) {
              if list.reminders.isEmpty {
                Text("No reminders yet")
                  .foregroundStyle(.secondary)
              }
              ForEach(list.reminders) { reminder in
                Button {
                  reminderButtonTapped(reminder, in: list)
                } label: {
                  Label(
                    reminder.title,
                    systemImage: reminder.isCompleted ? "checkmark.circle.fill" : "circle"
                  )
                }
                .accessibilityIdentifier("reminder-\(reminder.id.rawValue)")
              }
              Button("Add example reminder", systemImage: "plus", action: addReminderButtonTapped)
                .accessibilityIdentifier("add-example-reminder")
              NavigationLink {
                RemindersV3CompactSharingScreen(listID: list.id, userID: userID)
              } label: {
                Label("Sharing", systemImage: "person.2")
              }
            }
          } else {
            Section {
              Text("No lists yet")
                .foregroundStyle(.secondary)
              Button("Create example list", systemImage: "plus", action: createListButtonTapped)
                .accessibilityIdentifier("create-example-list")
            }
          }

          Section("Account") {
            Text(accountTitle)
            if canSignOut {
              Button("Sign out", role: .destructive, action: onSignOut)
            }
          }

          if !message.isEmpty {
            Text(message)
              .foregroundStyle(.secondary)
          }
        }
        .navigationTitle("Reminders")
        .task(id: userID) { await observeLists() }
        .task { await observeConnection() }
      }
    }

    private var connectionLabel: String {
      switch connectionStatus.state {
      case .authenticated: "Synced"
      case .opened: "Connected"
      case .connecting: "Connecting"
      case .closed: "Offline"
      case .errored: "Sync error"
      }
    }

    private var connectionIcon: String {
      switch connectionStatus.state {
      case .authenticated, .opened: "checkmark.icloud"
      case .connecting: "arrow.triangle.2.circlepath.icloud"
      case .closed: "icloud.slash"
      case .errored: "exclamationmark.icloud"
      }
    }

    private func observeLists() async {
      do {
        try await $lists.task(RemindersV3List.visible(to: userID))
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
        record(error: error, event: "compact-lists-query.failed")
      }
    }

    private func observeConnection() async {
      do {
        try await $connectionStatus.task()
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
        record(error: error, event: "compact-connection-query.failed")
      }
    }

    private func createListButtonTapped() {
      let id = InstantID<RemindersV3List>(rawValue: uuid().uuidString.lowercased())
      db.send(
        CreateRemindersV3List(
          listID: id,
          ownerID: userID,
          title: "Shared reminders",
          position: lists.count,
          createdAt: now
        ),
        onServerAccepted: { _ in message = "List synced" },
        onFailure: handleFailure
      )
    }

    private func addReminderButtonTapped() {
      guard let list = lists.first else { return }
      let id = InstantID<RemindersV3Reminder>(rawValue: uuid().uuidString.lowercased())
      db.send(
        CreateRemindersV3Reminder(
          reminderID: id,
          listID: list.id,
          title: "Example reminder \(list.reminders.count + 1)",
          position: list.reminders.count,
          createdAt: now
        ),
        onServerAccepted: { _ in message = "Reminder synced" },
        onFailure: handleFailure
      )
    }

    private func reminderButtonTapped(
      _ reminder: RemindersV3Reminder,
      in list: RemindersV3List
    ) {
      db.send(
        SetRemindersV3Completion(
          reminderID: reminder.id,
          listID: list.id,
          isCompleted: !reminder.isCompleted
        ),
        onServerAccepted: { _ in message = "Completion synced" },
        onFailure: handleFailure
      )
    }

    private func handleFailure(_ error: InstantError) {
      message = error.recoveryMessage
      record(error: error, event: "compact-mutation.failed")
    }

    private func record(error: Error, event: String) {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "compact-ui",
        event: event,
        message: "A compact Reminders operation failed."
      )
    }
  }

  @MainActor
  @available(tvOS 17.0, watchOS 10.0, *)
  private struct RemindersV3CompactSharingScreen: View {
    @FetchOne private var list: RemindersV3List?
    @FetchAll private var sharingUsers: [RemindersV3User]
    @FetchAll private var memberSuggestions: [RemindersV3User]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var memberEmail = ""
    @State private var memberRole = InstantShareRole.reader
    @State private var message = ""

    let listID: InstantID<RemindersV3List>
    let userID: InstantID<RemindersV3User>

    var body: some View {
      List {
        if let list {
          sharingSections(list)
        } else {
          ProgressView("Loading sharing")
        }

        if !message.isEmpty {
          Text(message)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Sharing")
      .task(id: listID) { await observeList() }
      .task(id: sharingUserIDs) { await observeSharingUsers() }
      .task(id: normalizedMemberEmail) { await observeMemberSuggestions() }
    }

    private var sharingUserIDs: [InstantID<RemindersV3User>] {
      guard let list else { return [] }
      let memberIDs = list.share?.memberships
        .filter { $0.revokedAt == nil }
        .map(\.user) ?? []
      return Array(Set([list.owner] + memberIDs)).sorted { $0.rawValue < $1.rawValue }
    }

    private var normalizedMemberEmail: String {
      memberEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var memberTarget: RemindersV3User? {
      (memberSuggestions + sharingUsers).first {
        $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          == normalizedMemberEmail
      }
    }

    @ViewBuilder
    private func sharingSections(_ list: RemindersV3List) -> some View {
      if let share = list.share {
        Section("People with Access") {
          ForEach(share.memberships.filter { $0.revokedAt == nil }) { membership in
            sharingMembershipRow(
              membership,
              share: share,
              canManage: list.isOwned(by: userID)
            )
          }
        }
      }

      if list.isOwned(by: userID), let share = list.share {
        Section("Add Person") {
          TextField("Email address", text: $memberEmail)
            .textContentType(.emailAddress)
          if normalizedMemberEmail.count >= 2 {
            ForEach(memberSuggestions.filter { $0.id != userID }.prefix(4)) { candidate in
              Button {
                suggestionButtonTapped(candidate)
              } label: {
                sharingIdentityLabel(candidate)
              }
              .buttonStyle(.plain)
            }
            if memberSuggestions.isEmpty && !$memberSuggestions.isLoading {
              Text("No account matches that email.")
                .foregroundStyle(.secondary)
            }
          }
          Picker("Access", selection: $memberRole) {
            Text("Can view").tag(InstantShareRole.reader)
            Text("Can edit").tag(InstantShareRole.writer)
          }
          Button(
            memberTargetIsExisting(in: share) ? "Update access" : "Add person",
            action: grantAccessButtonTapped
          )
          .disabled(memberTarget == nil || memberTarget?.id == userID)
        }
      } else if list.isOwned(by: userID) {
        Section("Sharing") {
          Button("Set up sharing", action: setUpSharingButtonTapped)
          Text("Invite another signed-in account by email, then choose view or edit access.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section("Your Access") {
          Label(
            list.writers.contains(userID) ? "Can edit" : "Can view",
            systemImage: list.writers.contains(userID) ? "pencil" : "eye"
          )
          Text("The list owner manages sharing access.")
            .foregroundStyle(.secondary)
        }
      }
    }

    private func sharingMembershipRow(
      _ membership: RemindersV3ShareMembership,
      share: RemindersV3Share,
      canManage: Bool
    ) -> some View {
      VStack(alignment: .leading) {
        if let identity = sharingUsers.first(where: { $0.id == membership.user }) {
          sharingIdentityLabel(identity)
        } else {
          Text(membership.user == userID ? "You" : "Account")
        }
        Text(membership.role.capitalized)
          .font(.caption)
          .foregroundStyle(.secondary)
        if canManage && membership.shareRole != .owner {
          Button("Remove", role: .destructive) {
            removeButtonTapped(membership, from: share)
          }
        }
      }
    }

    private func sharingIdentityLabel(_ identity: RemindersV3User) -> some View {
      VStack(alignment: .leading) {
        Text(identity.id == userID ? "You" : identity.remindersIdentityTitle)
        if let subtitle = identity.remindersIdentitySubtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }

    private func memberTargetIsExisting(in share: RemindersV3Share) -> Bool {
      guard let memberTarget else { return false }
      return share.memberships.contains {
        $0.user == memberTarget.id && $0.revokedAt == nil
      }
    }

    private func observeList() async {
      do {
        try await $list.task(RemindersV3List.byID(listID, visibleTo: userID))
      } catch is CancellationError {
      } catch {
        message = "Could not load sharing: \(String(describing: error))"
      }
    }

    private func observeSharingUsers() async {
      do {
        try await $sharingUsers.task(RemindersV3User.remindersUsers(ids: sharingUserIDs))
      } catch is CancellationError {
      } catch {
        message = "Could not load people: \(String(describing: error))"
      }
    }

    private func observeMemberSuggestions() async {
      do {
        try await Task.sleep(for: .milliseconds(180))
        try await $memberSuggestions.task(
          RemindersV3User.remindersUsers(matchingEmail: normalizedMemberEmail)
        )
      } catch is CancellationError {
      } catch {
        message = "Could not search people: \(String(describing: error))"
      }
    }

    private func suggestionButtonTapped(_ candidate: RemindersV3User) {
      memberEmail = candidate.email ?? ""
    }

    private func setUpSharingButtonTapped() {
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
        onServerAccepted: { _ in message = "Sharing is ready" },
        onFailure: handleFailure
      )
    }

    private func grantAccessButtonTapped() {
      guard let share = list?.share,
        let targetID = memberTarget?.id,
        targetID != userID
      else {
        message = "Choose an account from the email suggestions."
        return
      }

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
          onServerAccepted: { _ in
            message = "Access updated"
            memberEmail = ""
          },
          onFailure: handleFailure
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
          onServerAccepted: { _ in
            message = "Access granted"
            memberEmail = ""
          },
          onFailure: handleFailure
        )
      }
    }

    private func removeButtonTapped(
      _ membership: RemindersV3ShareMembership,
      from share: RemindersV3Share
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
        onServerAccepted: { _ in message = "Access removed" },
        onFailure: handleFailure
      )
    }

    private func handleFailure(_ error: InstantError) {
      message = error.recoveryMessage
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "sharing",
        event: "compact-sharing.failed",
        message: "A compact Reminders sharing operation failed.",
        metadata: ["listID": listID.rawValue]
      )
    }
  }
#endif
