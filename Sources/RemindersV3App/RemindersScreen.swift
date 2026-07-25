import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI) && (os(iOS) || os(macOS))
  import SwiftUI

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  public struct RemindersV3Screen: View {
    @InstantAuth(RemindersV3User.self, providers: RemindersV3AuthProviders.self)
    private var auth
    @FetchOne(nil) private var accountUser: RemindersV3User?
    @State private var message = "Sign in to sync and share lists"
    @State private var showsAccount = false
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
        if let userID = injectedUserID ?? auth.user?.id {
          RemindersV3ListsScreen(
            userID: userID,
            onAccount: { showsAccount = true }
          )
          .sheet(isPresented: $showsAccount) {
            accountSheet
          }
        } else {
          VStack(spacing: 16) {
            ContentUnavailableView {
              Label("Reminders", systemImage: "checklist")
            } description: {
              Text(message)
            }

            TextField("Email", text: $auth.email)
              .textContentType(.emailAddress)
              .focused($focusedAuthField, equals: .email)
              .onSubmit(sendMagicCode)

            if showsMagicCode {
              TextField("Code", text: $auth.magicCode)
                .textContentType(.oneTimeCode)
                .focused($focusedAuthField, equals: .magicCode)
                .onSubmit(verifyMagicCode)
              Button("Verify code", action: verifyMagicCode)
              Button("Use a different email") {
                auth.resetMagicCode()
                focusedAuthField = .email
              }
              .buttonStyle(.plain)
            } else {
              Button("Send magic code", action: sendMagicCode)
            }

            Divider()
            Button("Continue as guest", action: signInAsGuest)
          }
          .frame(maxWidth: 420)
          .padding()
        }
      }
      .disabled(auth.isBusy)
      .overlay {
        ProgressView()
          .opacity(auth.isBusy ? 1 : 0)
      }
      .onChange(of: focusedAuthField) { _, field in
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "focus",
          event: "auth-screen.focus-changed",
          message: "Reminders authentication focus changed.",
          metadata: ["field": field.map(String.init(describing:)) ?? "none"]
        )
      }
      .onChange(of: auth.email) { _, email in
        InstantDiagnostics.shared.record(
          .trace,
          subsystem: "reminders-v3",
          category: "input",
          event: "auth-screen.email-changed",
          message: "Reminders email input changed.",
          metadata: ["characterCount": String(email.count)]
        )
      }
      .onChange(of: auth.magicCode) { _, code in
        InstantDiagnostics.shared.record(
          .trace,
          subsystem: "reminders-v3",
          category: "input",
          event: "auth-screen.magic-code-changed",
          message: "Reminders magic-code input changed.",
          metadata: ["characterCount": String(code.count)]
        )
      }
      .task(id: activeUserID) {
        await observeAccountUser()
      }
      .onAppear {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "ui",
          event: "auth-screen.appeared",
          message: "Reminders authentication screen appeared.",
          metadata: [
            "hasInjectedUser": String(injectedUserID != nil),
            "hasAuthenticatedUser": String(auth.user != nil),
          ]
        )
      }
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode:
        true
      default:
        false
      }
    }

    private var activeUserID: InstantID<RemindersV3User>? {
      injectedUserID ?? auth.user?.id
    }

    private var accountSheet: some View {
      NavigationStack {
        Form {
          Section("Account") {
            if let imageURL = accountImageURL {
              AsyncImage(url: imageURL) { image in
                image
                  .resizable()
                  .scaledToFill()
              } placeholder: {
                ProgressView()
              }
              .frame(width: 56, height: 56)
              .clipShape(.circle)
            }
            if let displayName = accountUser?.displayName?.remindersNonempty {
              LabeledContent("Name", value: displayName)
            }
            if let username = accountUser?.username?.remindersNonempty {
              LabeledContent("Username", value: "@\(username)")
            }
            LabeledContent(
              "Email",
              value: accountEmail ?? (auth.session?.isGuest == true ? "Not added" : "Unavailable")
            )
            LabeledContent(
              "Account type",
              value: auth.session?.isGuest == true ? "Guest" : "Member"
            )
          }
          if auth.session?.isGuest == true {
            Section("Protect this guest account") {
              Text("Add your email without losing this guest account or its lists.")
                .foregroundStyle(.secondary)
              TextField("Email", text: $auth.email)
                .textContentType(.emailAddress)
                .focused($focusedAuthField, equals: .email)
                .onSubmit(sendMagicCode)
              if showsMagicCode {
                TextField("Code", text: $auth.magicCode)
                  .textContentType(.oneTimeCode)
                  .focused($focusedAuthField, equals: .magicCode)
                  .onSubmit(verifyMagicCode)
                Button("Verify code", action: verifyMagicCode)
                Button("Use a different email") {
                  auth.resetMagicCode()
                  focusedAuthField = .email
                }
              } else {
                Button("Send magic code", action: sendMagicCode)
              }
              if !message.isEmpty {
                Text(message)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Section {
            Button("Sign out", role: .destructive, action: signOut)
          }
        }
        .navigationTitle("Account")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { showsAccount = false }
          }
        }
      }
      .frame(minWidth: 360, minHeight: 300)
    }

    private var accountEmail: String? {
      accountUser?.email?.remindersNonempty ?? auth.user?.email?.remindersNonempty
    }

    private var accountImageURL: URL? {
      let rawValue = accountUser?.imageURL?.remindersNonempty
        ?? auth.user?.imageURL?.remindersNonempty
      return rawValue.flatMap(URL.init(string:))
    }

    private func observeAccountUser() async {
      do {
        let query = activeUserID.map { RemindersV3User.remindersUser(id: $0) }
        try await $accountUser.task(query)
      } catch is CancellationError {
      } catch {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "reminders-v3",
          category: "query",
          event: "account-user-query.failed",
          message: "Could not resolve the signed-in user record."
        )
      }
    }

    private func sendMagicCode() {
      let targetEmail = auth.email.trimmingCharacters(in: .whitespacesAndNewlines)
      guard targetEmail.contains("@"), targetEmail.contains(".") else {
        message = "Enter a valid email address, such as you@example.com."
        focusedAuthField = .email
        InstantDiagnostics.shared.record(
          .warning,
          subsystem: "reminders-v3",
          category: "auth",
          event: "magic-code-send.rejected",
          message: "Rejected an invalid email before contacting Instant.",
          metadata: ["emailCharacterCount": String(targetEmail.count)]
        )
        return
      }
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "auth",
        event: "magic-code-send.requested",
        message: "User requested an Instant magic code.",
        metadata: ["emailCharacterCount": String(auth.email.count)]
      )
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          message = "Code sent to \(challenge.email)"
          focusedAuthField = .magicCode
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "auth",
            event: "magic-code-send.completed",
            message: "Instant accepted the magic-code request."
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "auth",
            event: "magic-code-send.failed",
            message: "Magic-code request failed."
          )
        }
      )
    }

    private func verifyMagicCode() {
      let code = auth.magicCode.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !code.isEmpty else {
        message = "Enter the code from your email."
        focusedAuthField = .magicCode
        InstantDiagnostics.shared.record(
          .warning,
          subsystem: "reminders-v3",
          category: "auth",
          event: "magic-code-verify.rejected",
          message: "Rejected an empty magic code before contacting Instant."
        )
        return
      }
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "auth",
        event: "magic-code-verify.requested",
        message: "User submitted an Instant magic code.",
        metadata: ["codeCharacterCount": String(auth.magicCode.count)]
      )
      auth.verifyMagicCode(
        onSignedIn: { event in
          message = "Signed in"
          showsAccount = false
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "auth",
            event: "magic-code-verify.completed",
            message: "Magic-code sign-in completed.",
            metadata: ["userID": event.session.userID]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "auth",
            event: "magic-code-verify.failed",
            message: "Magic-code verification failed."
          )
        }
      )
    }

    private func signOut() {
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "auth",
        event: "sign-out.requested",
        message: "User requested sign-out."
      )
      auth.signOut(
        onSignedOut: {
          message = "Signed out"
          showsAccount = false
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "auth",
            event: "sign-out.completed",
            message: "User signed out."
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "auth",
            event: "sign-out.failed",
            message: "Sign-out failed."
          )
        }
      )
    }

    private func signInAsGuest() {
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "auth",
        event: "guest-sign-in.requested",
        message: "User requested guest sign-in."
      )
      auth.signInAsGuest(
        onSignedIn: { user in
          message = "Signed in"
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "auth",
            event: "guest-sign-in.completed",
            message: "Guest sign-in completed.",
            metadata: ["userID": user.session.userID]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "auth",
            event: "guest-sign-in.failed",
            message: "Guest sign-in failed."
          )
        }
      )
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  public struct RemindersV3ListsScreen: View {
    @FetchAll(nil) private var lists: [RemindersV3List]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var newListTitle = ""
    @State private var editedList: RemindersV3List?
    @State private var message = ""
    @State private var searchText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
      case newList
    }

    public let userID: InstantID<RemindersV3User>
    private let onAccount: () -> Void

    public init(
      userID: InstantID<RemindersV3User>,
      onAccount: @escaping () -> Void = {}
    ) {
      self.userID = userID
      self.onAccount = onAccount
      _lists = FetchAll(RemindersV3List.visible(to: userID))
    }

    public var body: some View {
      NavigationStack {
        List {
          Section("New list") {
            TextField("List name", text: $newListTitle)
              .focused($focusedField, equals: .newList)
              .onSubmit(addList)
            Button("Add list", action: addList)
              .buttonStyle(.bordered)
              .accessibilityLabel("Add list")
              .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          smartListsSection
          if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResultsSection
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
              .contextMenu {
                if list.isOwned(by: userID) {
                  Button("Edit List", systemImage: "pencil") { editedList = list }
                }
              }
              .moveDisabled(!list.isOwned(by: userID))
            }
            .onMove(perform: moveLists)
          }
          if !usedTags.isEmpty {
            Section("Tags") {
              ForEach(usedTags) { tag in
                NavigationLink {
                  RemindersV3CollectionScreen(
                    userID: userID,
                    filter: .tag(id: tag.id, title: tag.title)
                  )
                } label: {
                  Label("#\(tag.title)", systemImage: "number")
                }
                .contextMenu {
                  if canDelete(tag) {
                    Button("Delete Tag", systemImage: "trash", role: .destructive) {
                      delete(tag)
                    }
                  }
                }
              }
              .onDelete(perform: deleteTags)
            }
          }
          if !message.isEmpty {
            Text(message)
          }
        }
        .navigationTitle("Reminders")
        .searchable(text: $searchText, prompt: "Search reminders or #tags")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Account", systemImage: "person.crop.circle", action: onAccount)
          }
        }
      }
      .sheet(item: $editedList) { list in
        NavigationStack { RemindersV3ListEditorScreen(list: list) }
      }
      .onAppear {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "ui",
          event: "lists-screen.appeared",
          message: "Reminders lists screen appeared.",
          metadata: ["userID": userID.rawValue]
        )
      }
      .onDisappear {
        recordListsScreenDisappeared()
      }
      .onChange(of: focusedField) { _, field in
        recordListsFocus(field)
      }
      .onChange(of: newListTitle) { oldValue, newValue in
        recordListInput(oldValue: oldValue, newValue: newValue)
      }
      .onChange(of: searchText) { _, newValue in
        InstantDiagnostics.shared.record(
          .trace,
          subsystem: "reminders-v3",
          category: "input",
          event: "reminder-search.input-changed",
          message: "Reminders search input changed.",
          metadata: ["characterCount": String(newValue.count)]
        )
      }
      .onChange(of: lists.map(\.id)) { _, ids in
        recordListEmission(ids)
      }
    }

    private var stats: RemindersStats {
      RemindersV3Presentation.stats(lists: lists, now: now)
    }

    private var usedTags: [RemindersV3Tag] {
      RemindersV3Presentation.usedTags(in: lists)
    }

    private var searchRows: [RemindersV3PresentationRow] {
      RemindersV3Presentation.rows(
        lists: lists,
        filter: .search(searchText),
        showCompleted: false,
        ordering: .dueDate,
        now: now
      )
    }

    private var smartListsSection: some View {
      Section("Smart Lists") {
        smartListLink("Today", count: stats.todayCount, icon: "calendar", filter: .today)
        smartListLink(
          "Scheduled",
          count: stats.scheduledCount,
          icon: "calendar.badge.clock",
          filter: .scheduled
        )
        smartListLink("All", count: stats.allCount, icon: "tray", filter: .all)
        smartListLink("Flagged", count: stats.flaggedCount, icon: "flag", filter: .flagged)
        smartListLink(
          "Completed",
          count: stats.completedCount,
          icon: "checkmark.circle",
          filter: .completed
        )
      }
    }

    private var searchResultsSection: some View {
      Section("Search Results") {
        if searchRows.isEmpty {
          Text("No matching reminders")
            .foregroundStyle(.secondary)
        }
        ForEach(searchRows.prefix(5)) { row in
          NavigationLink {
            RemindersV3ListScreen(listID: row.list.id, userID: userID)
          } label: {
            VStack(alignment: .leading) {
              Text(row.reminder.title)
              Text(row.list.title).font(.caption).foregroundStyle(.secondary)
              if let preview = row.searchSummary
                ?? RemindersV3Presentation.searchPreview(for: row.reminder, text: searchText)
              {
                Text(preview)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
          }
        }
        NavigationLink {
          RemindersV3CollectionScreen(userID: userID, filter: .search(searchText))
        } label: {
          Text("See all results")
        }
      }
    }

    private func smartListLink(
      _ title: String,
      count: Int,
      icon: String,
      filter: RemindersV3CollectionFilter
    ) -> some View {
      NavigationLink {
        RemindersV3CollectionScreen(userID: userID, filter: filter)
      } label: {
        HStack {
          Label(title, systemImage: icon)
          Spacer()
          Text(count, format: .number)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityLabel("\(title), \(count)")
    }

    private func addList() {
      let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        InstantDiagnostics.shared.record(
          .warning,
          subsystem: "reminders-v3",
          category: "mutation",
          event: "list-create.rejected",
          message: "Ignored an empty list title."
        )
        return
      }
      let listID = InstantID<RemindersV3List>(rawValue: uuid().uuidString.lowercased())
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "mutation",
        event: "list-create.requested",
        message: "Creating a reminder list.",
        metadata: [
          "listID": listID.rawValue,
          "ownerID": userID.rawValue,
          "position": String(lists.count),
          "titleLength": String(title.count),
        ],
        correlationID: listID.rawValue
      )
      db.send(
        CreateRemindersV3List(
          listID: listID,
          ownerID: userID,
          title: title,
          position: lists.count,
          createdAt: now
        ),
        onOptimisticCommit: { _ in
          newListTitle = ""
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "mutation",
            event: "list-create.optimistic-commit",
            message: "List was committed to the local cache.",
            metadata: ["listID": listID.rawValue],
            correlationID: listID.rawValue
          )
        },
        onServerAccepted: { _ in
          message = "List synced"
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "mutation",
            event: "list-create.server-accepted",
            message: "Instant accepted the list mutation.",
            metadata: ["listID": listID.rawValue],
            correlationID: listID.rawValue
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "mutation",
            event: "list-create.failed",
            message: "List creation failed.",
            metadata: ["listID": listID.rawValue],
            correlationID: listID.rawValue
          )
        }
      )
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
      var movedLists = lists
      movedLists.move(fromOffsets: source, toOffset: destination)
      db.send(
        ReorderRemindersV3Lists(
          positions: movedLists.filter { $0.isOwned(by: userID) }.enumerated().map {
            position, list in
            .init(listID: list.id, position: position)
          }
        ),
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "mutation",
            event: "list-reorder.failed",
            message: "List reordering failed."
          )
        }
      )
    }

    private func canDelete(_ tag: RemindersV3Tag) -> Bool {
      RemindersV3Presentation.canDeleteTag(tag, in: lists, userID: userID)
    }

    private func deleteTags(at offsets: IndexSet) {
      for offset in offsets {
        delete(usedTags[offset])
      }
    }

    private func delete(_ tag: RemindersV3Tag) {
      guard canDelete(tag) else {
        message = "Only the owner of every tagged list can delete #\(tag.title)."
        return
      }
      db.send(
        DeleteRemindersV3Tag(tagID: tag.id),
        onServerAccepted: { _ in message = "Tag deleted" },
        onFailure: { error in
          message = error.recoveryMessage
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "reminders-v3",
            category: "mutation",
            event: "tag-delete.failed",
            message: "Tag deletion failed.",
            metadata: ["tagID": tag.id.rawValue]
          )
        }
      )
    }

    private func recordListsScreenDisappeared() {
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "reminders-v3",
        category: "ui",
        event: "lists-screen.disappeared",
        message: "Reminders lists screen disappeared.",
        metadata: ["userID": userID.rawValue]
      )
    }

    private func recordListsFocus(_ field: Field?) {
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "reminders-v3",
        category: "focus",
        event: "lists-screen.focus-changed",
        message: "Lists screen field focus changed.",
        metadata: ["field": field == .newList ? "new-list" : "none"]
      )
    }

    private func recordListInput(oldValue: String, newValue: String) {
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "reminders-v3",
        category: "input",
        event: "new-list.input-changed",
        message: "New-list input changed.",
        metadata: [
          "oldLength": String(oldValue.count),
          "newLength": String(newValue.count),
        ]
      )
    }

    private func recordListEmission(_ ids: [InstantID<RemindersV3List>]) {
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "query",
        event: "lists-query.emitted",
        message: "Visible-list observation emitted a snapshot.",
        metadata: [
          "listCount": String(ids.count),
          "listIDs": ids.map(\.rawValue).joined(separator: ","),
        ]
      )
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  public struct RemindersV3ListScreen: View {
    @FetchOne(nil) private var list: RemindersV3List?
    @FetchAll(nil) private var reminders: [RemindersV3Reminder]
    @FetchAll(nil) private var sharingUsers: [RemindersV3User]
    @FetchAll(nil) private var memberSuggestions: [RemindersV3User]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var newReminderTitle = ""
    @State private var coverImageData: Data?
    @State private var form: RemindersV3ReminderFormDestination?
    @State private var editedList: RemindersV3List?
    @State private var memberEmail = ""
    @State private var memberRole = InstantShareRole.reader
    @State private var message = ""
    @State private var ordering = RemindersV3Ordering.manual
    @State private var showCompleted = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
      case newReminder
      case memberEmail
    }

    public let listID: InstantID<RemindersV3List>
    public let userID: InstantID<RemindersV3User>

    public init(
      listID: InstantID<RemindersV3List>,
      userID: InstantID<RemindersV3User>
    ) {
      self.listID = listID
      self.userID = userID
      _list = FetchOne(RemindersV3List.byID(listID, visibleTo: userID))
      _reminders = FetchAll(RemindersV3Reminder.forList(listID, includeCompleted: true))
    }

    public var body: some View {
      List {
        if let list, list.coverFileID != nil {
          coverSection
        }
        remindersSection
        if let list { sharingSection(list) }
        if !message.isEmpty {
          Text(message)
        }
      }
      .navigationTitle(list?.title ?? "Reminders")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("New Reminder", systemImage: "plus", action: newReminderButtonTapped)
            .disabled(!canEditList)
          Menu("View", systemImage: "ellipsis.circle") {
            Picker("Sort By", selection: $ordering) {
              ForEach(RemindersV3Ordering.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
              }
            }
            Button(showCompleted ? "Hide Completed" : "Show Completed") {
              showCompleted.toggle()
            }
            if canClearCompleted {
              Menu("Clear Completed", systemImage: "trash") {
                ForEach(RemindersV3CompletedCleanupScope.menuCases, id: \.self) { scope in
                  Button(scope.title, role: .destructive) {
                    clearCompleted(scope)
                  }
                }
              }
            }
            if let list, list.isOwned(by: userID) {
              Button("Edit List", systemImage: "pencil") { editedList = list }
            }
          }
        }
      }
      .sheet(item: $form) { destination in
        NavigationStack {
          RemindersV3ReminderFormScreen(
            userID: userID,
            initialListID: destination.listID,
            reminder: destination.reminder,
            defaultDueDate: now
          )
        }
      }
      .sheet(item: $editedList) { list in
        NavigationStack { RemindersV3ListEditorScreen(list: list) }
      }
      .onAppear {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "reminders-v3",
          category: "ui",
          event: "list-screen.appeared",
          message: "Reminder-list detail screen appeared.",
          metadata: [
            "listID": listID.rawValue,
            "userID": userID.rawValue,
          ]
        )
      }
      .onChange(of: focusedField) { _, field in
        recordDetailFocus(field)
      }
      .onChange(of: newReminderTitle) { oldValue, newValue in
        recordReminderInput(oldValue: oldValue, newValue: newValue)
      }
      .task(id: list?.coverFileID) {
        await loadCoverImage(fileID: list?.coverFileID)
      }
      .task(id: sharingUserIDs) {
        await observeSharingUsers()
      }
      .task(id: normalizedMemberEmail) {
        await observeMemberSuggestions()
      }
      .onChange(of: reminders.map(\.id)) { _, ids in
        recordReminderEmission(ids)
      }
    }

    private var coverSection: some View {
      Section {
        RemindersV3CoverImageView(data: coverImageData, height: 180)
          .listRowInsets(EdgeInsets())
      }
    }

    private var remindersSection: some View {
      Section("Reminders") {
        TextField("New reminder", text: $newReminderTitle)
          .focused($focusedField, equals: .newReminder)
          .onSubmit(addReminder)
          .disabled(!canEditList)
        Button("Add reminder", action: addReminder)
          .buttonStyle(.bordered)
          .accessibilityLabel("Add reminder")
          .disabled(
            !canEditList
              || newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
        ForEach(displayedReminders) { reminder in
          RemindersV3ReminderRow(
            reminder: reminder,
            listTitle: nil,
            isEditable: canEditList,
            onToggle: { toggle(reminder) },
            onEdit: { edit(reminder) },
            onDelete: { delete(reminder) }
          )
        }
        .onMove(perform: moveReminders)
        .moveDisabled(!canEditList)
      }
    }

    private var canEditList: Bool {
      list?.canWrite(as: userID) == true
    }

    private var displayedReminders: [RemindersV3Reminder] {
      RemindersV3Presentation.sorted(
        reminders: reminders,
        showCompleted: showCompleted,
        ordering: ordering
      )
    }

    private var canClearCompleted: Bool {
      canEditList && reminders.contains { $0.isCompleted }
    }

    private var sharingUserIDs: [InstantID<RemindersV3User>] {
      guard let list else { return [] }
      let membershipIDs = list.share?.memberships
        .filter { $0.revokedAt == nil }
        .map(\.user) ?? []
      return Array(Set([list.owner] + membershipIDs)).sorted { $0.rawValue < $1.rawValue }
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
    private func sharingSection(_ list: RemindersV3List) -> some View {
      if let share = list.share {
        Section("People with Access") {
          ForEach(share.memberships.filter { $0.revokedAt == nil }) { membership in
            sharingMembershipRow(membership, share: share, canManage: list.isOwned(by: userID))
          }
        }
      }

      if list.isOwned(by: userID), let share = list.share {
        Section("Add Person") {
          TextField("Email address", text: $memberEmail)
            .textContentType(.emailAddress)
            .focused($focusedField, equals: .memberEmail)
          if normalizedMemberEmail.count >= 2 {
            ForEach(memberSuggestions.filter { $0.id != userID }.prefix(8)) { candidate in
              Button {
                memberEmail = candidate.email ?? ""
                focusedField = nil
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
          Button(memberTargetIsExisting(in: share) ? "Update access" : "Add person") {
            grantAccess(on: share)
          }
          .buttonStyle(.borderedProminent)
          .disabled(memberTarget == nil || memberTarget?.id == userID)
        }
      } else if list.isOwned(by: userID) {
        Section("Sharing") {
          Button("Set up sharing", action: createShare)
            .buttonStyle(.bordered)
          Text("You can then invite people by email and choose whether they can view or edit.")
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
      HStack {
        if let identity = sharingUsers.first(where: { $0.id == membership.user }) {
          sharingIdentityLabel(identity)
        } else {
          VStack(alignment: .leading) {
            Text(membership.user == userID ? "You" : "Guest account")
            Text("Identity details unavailable")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Text(membership.role.capitalized)
          .foregroundStyle(.secondary)
        if canManage && membership.shareRole != .owner {
          Button("Remove") { revoke(membership, share: share) }
            .buttonStyle(.bordered)
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

    private func observeSharingUsers() async {
      do {
        try await $sharingUsers.task(RemindersV3User.remindersUsers(ids: sharingUserIDs))
      } catch is CancellationError {
      } catch {
        message = "Could not load sharing identities: \(String(describing: error))"
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

    private func loadCoverImage(fileID: String?) async {
      guard let fileID else {
        coverImageData = nil
        return
      }
      do {
        coverImageData = try await db.storedFileContents(id: fileID).data
      } catch {
        recordMutationFailure(
          error,
          event: "cover-load.failed",
          message: "List cover photo failed to load.",
          metadata: [:]
        )
      }
    }

    private func recordDetailFocus(_ field: Field?) {
      let name: String
      switch field {
      case .newReminder: name = "new-reminder"
      case .memberEmail: name = "member-email"
      case nil: name = "none"
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "reminders-v3",
        category: "focus",
        event: "list-screen.focus-changed",
        message: "List-detail field focus changed.",
        metadata: [
          "field": name,
          "listID": listID.rawValue,
        ]
      )
    }

    private func recordReminderInput(oldValue: String, newValue: String) {
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "reminders-v3",
        category: "input",
        event: "new-reminder.input-changed",
        message: "New-reminder input changed.",
        metadata: [
          "oldLength": String(oldValue.count),
          "newLength": String(newValue.count),
          "listID": listID.rawValue,
        ]
      )
    }

    private func recordReminderEmission(_ ids: [InstantID<RemindersV3Reminder>]) {
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "reminders-v3",
        category: "query",
        event: "reminders-query.emitted",
        message: "Reminder observation emitted a snapshot.",
        metadata: [
          "listID": listID.rawValue,
          "reminderCount": String(ids.count),
          "reminderIDs": ids.map(\.rawValue).joined(separator: ","),
        ]
      )
    }

    private func addReminder() {
      let title = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return }
      let reminderID = InstantID<RemindersV3Reminder>(rawValue: uuid().uuidString.lowercased())
      recordMutation(
        event: "reminder-create.requested",
        message: "Creating a reminder.",
        metadata: [
          "reminderID": reminderID.rawValue,
          "titleLength": String(title.count),
          "position": String(reminders.count),
        ]
      )
      db.send(
        CreateRemindersV3Reminder(
          reminderID: reminderID,
          listID: listID,
          title: title,
          position: reminders.count,
          createdAt: now
        ),
        onOptimisticCommit: { _ in
          newReminderTitle = ""
          recordMutation(
            .notice,
            event: "reminder-create.optimistic-commit",
            message: "Reminder committed to the local cache.",
            metadata: ["reminderID": reminderID.rawValue]
          )
        },
        onServerAccepted: { _ in
          message = "Reminder synced"
          recordMutation(
            .notice,
            event: "reminder-create.server-accepted",
            message: "Instant accepted the reminder mutation.",
            metadata: ["reminderID": reminderID.rawValue]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "reminder-create.failed",
            message: "Reminder creation failed.",
            metadata: ["reminderID": reminderID.rawValue]
          )
        }
      )
    }

    private func newReminderButtonTapped() {
      form = RemindersV3ReminderFormDestination(
        id: "new-\(uuid().uuidString.lowercased())",
        listID: listID,
        reminder: nil
      )
    }

    private func edit(_ reminder: RemindersV3Reminder) {
      form = RemindersV3ReminderFormDestination(
        id: reminder.id.rawValue,
        listID: listID,
        reminder: reminder
      )
    }

    private func moveReminders(from source: IndexSet, to destination: Int) {
      var moved = displayedReminders
      moved.move(fromOffsets: source, toOffset: destination)
      ordering = .manual
      db.send(
        ReorderRemindersV3Reminders(
          listID: listID,
          positions: moved.enumerated().map { position, reminder in
            .init(reminderID: reminder.id, position: position)
          }
        ),
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "reminder-reorder.failed",
            message: "Reminder reordering failed.",
            metadata: [:]
          )
        }
      )
    }

    private func toggle(_ reminder: RemindersV3Reminder) {
      let nextCompletion = !reminder.isCompleted
      recordMutation(
        event: "reminder-completion.requested",
        message: "Changing reminder completion.",
        metadata: [
          "reminderID": reminder.id.rawValue,
          "isCompleted": String(nextCompletion),
        ]
      )
      db.send(
        SetRemindersV3Completion(
          reminderID: reminder.id,
          listID: listID,
          isCompleted: nextCompletion
        ),
        onServerAccepted: { _ in
          recordMutation(
            .notice,
            event: "reminder-completion.server-accepted",
            message: "Instant accepted the reminder completion mutation.",
            metadata: ["reminderID": reminder.id.rawValue]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "reminder-completion.failed",
            message: "Reminder completion change failed.",
            metadata: ["reminderID": reminder.id.rawValue]
          )
        }
      )
    }

    private func delete(_ reminder: RemindersV3Reminder) {
      recordMutation(
        event: "reminder-delete.requested",
        message: "Deleting a reminder.",
        metadata: ["reminderID": reminder.id.rawValue]
      )
      db.send(
        DeleteRemindersV3Reminder(reminderID: reminder.id, listID: listID),
        onServerAccepted: { _ in
          recordMutation(
            .notice,
            event: "reminder-delete.server-accepted",
            message: "Instant accepted the reminder deletion.",
            metadata: ["reminderID": reminder.id.rawValue]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "reminder-delete.failed",
            message: "Reminder deletion failed.",
            metadata: ["reminderID": reminder.id.rawValue]
          )
        }
      )
    }

    private func clearCompleted(_ scope: RemindersV3CompletedCleanupScope) {
      guard let list else { return }
      let rows = reminders.map {
        RemindersV3PresentationRow(
          list: list,
          reminder: $0
        )
      }
      let targets = RemindersV3Presentation.completedRowsToDelete(
        rows: rows,
        scope: scope,
        now: now
      )
      .map {
        DeleteRemindersV3CompletedReminders.Target(
          reminderID: $0.reminder.id,
          listID: listID
        )
      }
      guard !targets.isEmpty else {
        message = "No completed reminders matched \(scope.title.lowercased())."
        return
      }
      db.send(
        DeleteRemindersV3CompletedReminders(targets: targets),
        onServerAccepted: { _ in message = "Completed reminders cleared" },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "completed-cleanup.failed",
            message: "Completed reminder cleanup failed.",
            metadata: [:]
          )
        }
      )
    }

    private func createShare() {
      let shareID = InstantID<RemindersV3Share>(rawValue: uuid().uuidString.lowercased())
      recordMutation(
        event: "share-create.requested",
        message: "Creating a share for a reminder list.",
        metadata: ["shareID": shareID.rawValue]
      )
      db.send(
        CreateRemindersV3Share(
          shareID: shareID,
          ownerMembershipID: InstantID(rawValue: uuid().uuidString.lowercased()),
          listID: listID,
          ownerID: userID,
          token: uuid().uuidString.lowercased(),
          createdAt: now
        ),
        onServerAccepted: { _ in
          message = "Share created"
          recordMutation(
            .notice,
            event: "share-create.server-accepted",
            message: "Instant accepted the share creation.",
            metadata: ["shareID": shareID.rawValue]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "share-create.failed",
            message: "Share creation failed.",
            metadata: ["shareID": shareID.rawValue]
          )
        }
      )
    }

    private func grantAccess(on share: RemindersV3Share) {
      guard let targetID = memberTarget?.id, targetID != userID else {
        message = "Choose an account from the email suggestions."
        return
      }
      recordMutation(
        event: "share-access.requested",
        message: "Changing reminder-list share access.",
        metadata: [
          "shareID": share.id.rawValue,
          "targetUserID": targetID.rawValue,
          "role": memberRole.rawValue,
        ]
      )
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
            message = "Role updated"
            memberEmail = ""
            recordMutation(
              .notice,
              event: "share-role.server-accepted",
              message: "Instant accepted the share-role change.",
              metadata: ["shareID": share.id.rawValue]
            )
          },
          onFailure: { error in
            message = error.recoveryMessage
            recordMutationFailure(
              error,
              event: "share-role.failed",
              message: "Share-role change failed.",
              metadata: ["shareID": share.id.rawValue]
            )
          }
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
            recordMutation(
              .notice,
              event: "share-grant.server-accepted",
              message: "Instant accepted the share grant.",
              metadata: ["shareID": share.id.rawValue]
            )
          },
          onFailure: { error in
            message = error.recoveryMessage
            recordMutationFailure(
              error,
              event: "share-grant.failed",
              message: "Share grant failed.",
              metadata: ["shareID": share.id.rawValue]
            )
          }
        )
      }
    }

    private func revoke(
      _ membership: RemindersV3ShareMembership,
      share: RemindersV3Share
    ) {
      guard let role = membership.shareRole else { return }
      recordMutation(
        event: "share-revoke.requested",
        message: "Revoking reminder-list share access.",
        metadata: [
          "shareID": share.id.rawValue,
          "membershipID": membership.id.rawValue,
          "targetUserID": membership.user.rawValue,
          "role": role.rawValue,
        ]
      )
      db.send(
        RevokeRemindersV3Share(
          shareID: share.id,
          membershipID: membership.id,
          listID: listID,
          userID: membership.user,
          role: role,
          revokedAt: now
        ),
        onServerAccepted: { _ in
          message = "Access revoked"
          recordMutation(
            .notice,
            event: "share-revoke.server-accepted",
            message: "Instant accepted the share revocation.",
            metadata: ["shareID": share.id.rawValue]
          )
        },
        onFailure: { error in
          message = error.recoveryMessage
          recordMutationFailure(
            error,
            event: "share-revoke.failed",
            message: "Share revocation failed.",
            metadata: ["shareID": share.id.rawValue]
          )
        }
      )
    }

    private func recordMutation(
      _ level: InstantDiagnosticLevel = .info,
      event: String,
      message: String,
      metadata: [String: String]
    ) {
      var context = metadata
      context["listID"] = listID.rawValue
      InstantDiagnostics.shared.record(
        level,
        subsystem: "reminders-v3",
        category: "mutation",
        event: event,
        message: message,
        metadata: context,
        correlationID: metadata["reminderID"] ?? metadata["shareID"] ?? listID.rawValue
      )
    }

    private func recordMutationFailure(
      _ error: Error,
      event: String,
      message: String,
      metadata: [String: String]
    ) {
      var context = metadata
      context["listID"] = listID.rawValue
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "mutation",
        event: event,
        message: message,
        metadata: context,
        correlationID: metadata["reminderID"] ?? metadata["shareID"] ?? listID.rawValue
      )
    }
  }

  extension Color {
    init(hex: String) {
      let value =
        UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        ?? 0x4a99ef
      self.init(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
      )
    }
  }
#endif
