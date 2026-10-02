import Foundation

/// How a member of an account link signed in, as its label in the link records it.
///
/// The label is for people reading the list of linked sign-ins. It grants nothing: the link's `members` decide access.
public enum InstantAccountLinkProvider: String, Codable, Sendable, CaseIterable {
  case apple
  case google
  case magicCode
  case guest
  case refreshToken
}

extension InstantAccountLinkProvider {
  /// The label for a sign-in through `providerID`: `apple`, `google`, the magic-code provider, or the guest provider.
  /// Other providers have no label.
  public init?(providerID: InstantAuthProviderID) {
    switch providerID {
    case InstantAuthProviderID(rawValue: "apple"): self = .apple
    case InstantAuthProviderID(rawValue: "google"): self = .google
    case .magicCode: self = .magicCode
    case .guest: self = .guest
    default: return nil
    }
  }
}

/// One person's linked identities, as an account link on the Instant server lists them.
public struct InstantAccountLink: Hashable, Sendable {
  /// One identity in the link.
  public struct Member: Hashable, Sendable {
    /// The identity's `$users` id.
    public var userID: String
    /// The identity's email address, when it has one. Guests have none.
    public var email: String?
    /// Whether the identity is an Instant guest.
    public var isGuest: Bool
    /// How the identity signed in when it was linked, when the link recorded it.
    public var provider: InstantAccountLinkProvider?
    /// When the identity was linked, when the link recorded it.
    public var linkedAt: Date?
    /// The device that linked the identity, when the link recorded it.
    public var deviceName: String?

    public init(
      userID: String,
      email: String? = nil,
      isGuest: Bool = false,
      provider: InstantAccountLinkProvider? = nil,
      linkedAt: Date? = nil,
      deviceName: String? = nil
    ) {
      self.userID = userID
      self.email = email
      self.isGuest = isGuest
      self.provider = provider
      self.linkedAt = linkedAt
      self.deviceName = deviceName
    }
  }

  /// The link row's id.
  public var id: String
  /// The linked identities, in the order they were linked.
  public var members: [Member]

  public init(id: String, members: [Member]) {
    self.id = id
    self.members = members
  }
}

/// Links one person's Instant identities, such as their Apple and Google sign-ins, so the app can treat them as one
/// account.
///
/// Instant itself links only guests (`$users.linkedPrimaryUser`), and it joins two provider sign-ins only when their
/// email addresses match. An account link is an app-level row that lists one person's identities in its `members`.
/// The app's permission rules (``permissionRulesTemplate``) then let every member read what the other members own.
///
/// The rules let an identity link only itself, so a link takes two writes from two identities. The identity already in
/// a link invites the other one (or creates the link and invites it), and the invited identity joins and clears the
/// invite. The primary identity writes through a twin of its own session (``InstantSecondSignIn/open(sharingSessionOf:registering:)``),
/// so a long outbox on the primary client never delays a link. The other identity writes through its own second
/// sign-in. Each write waits for Instant to accept it before the next one starts.
///
/// ```swift
/// let links = InstantAccountLinks.default
/// let second = try await InstantSecondSignIn.open(beside: client, registering: links.attributes)
/// _ = try await second.signIn(with: credential, provider: google)
/// let link = try await links.link(primary: client, second: second, secondProvider: .google, deviceName: "iPhone")
/// await second.close()
/// ```
///
/// The app declares the link in its Instant schema: an `accountLinks` entity with the fields below, and a link whose
/// forward side is `accountLinks.members` (has many `$users`) and whose reverse side is `$users.accountLink` (has
/// one). It pastes ``permissionRulesTemplate`` into its permissions.
public struct InstantAccountLinks: Hashable, Sendable {
  /// The namespace of the link rows.
  public var namespace: String
  /// The forward label of the link from a link row to its member `$users`.
  public var membersLabel: String
  /// The reverse label of that link on `$users`.
  public var userLinkLabel: String
  /// How long an invite stays open.
  ///
  /// The server compares the invite's expiry with its own clock, so this must outlast the skew between a device's clock
  /// and the server's. It is not a wait: the invited identity joins as soon as Instant accepts the invite.
  public var inviteLifetime: Duration
  /// How long each read and write waits for Instant's answer. Five seconds is the codebase-wide bound for a server
  /// wait.
  public var serverTimeout: Duration

  public init(
    namespace: String = "accountLinks",
    membersLabel: String = "members",
    userLinkLabel: String = "accountLink",
    inviteLifetime: Duration = .seconds(600),
    serverTimeout: Duration = .seconds(5)
  ) {
    self.namespace = namespace
    self.membersLabel = membersLabel
    self.userLinkLabel = userLinkLabel
    self.inviteLifetime = inviteLifetime
    self.serverTimeout = serverTimeout
  }

  /// The `accountLinks` namespace, its `members` link, and the reverse `$users.accountLink`.
  public static let `default` = Self()

  /// The local schema for account links: the link rows, the `members` link, and the `$users` fields a link read
  /// returns (`email` and `type`).
  ///
  /// Register these in the app's schema, next to its own attributes:
  ///
  /// ```swift
  /// initialAttributes: MyApp.instantAttributes + InstantAccountLinks.default.attributes
  /// ```
  ///
  /// A store validates every read and write against its declared attributes, so a store without these refuses
  /// account-link reads and writes. Second sign-ins copy the primary's schema. The twins that
  /// ``link(primary:second:secondProvider:deviceName:now:)`` and ``unlink(memberUserID:primary:now:)`` open register
  /// these too, and so can a second sign-in: ``InstantSecondSignIn/open(beside:registering:)``. Reading through a
  /// store that lacks them throws an error that names the missing attributes and this fix, before anything is
  /// written.
  public var attributes: [InstantAttribute] {
    [
      .primaryKey(namespace: namespace),
      InstantAttribute(
        id: attributeID("createdByUserID"),
        namespace: namespace,
        name: "createdByUserID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: attributeID("createdAtMs"),
        namespace: namespace,
        name: "createdAtMs",
        valueType: .number
      ),
      InstantAttribute(
        id: attributeID("updatedAtMs"),
        namespace: namespace,
        name: "updatedAtMs",
        valueType: .number
      ),
      InstantAttribute(
        id: attributeID("inviteUserID"),
        namespace: namespace,
        name: "inviteUserID",
        valueType: .string,
        isRequired: false,
        isIndexed: true
      ),
      InstantAttribute(
        id: attributeID("inviteExpiresAtMs"),
        namespace: namespace,
        name: "inviteExpiresAtMs",
        valueType: .number,
        isRequired: false
      ),
      InstantAttribute(
        id: attributeID("membersJSON"),
        namespace: namespace,
        name: "membersJSON",
        valueType: .json,
        isRequired: false
      ),
      // Has-many forward, has-one reverse: Instant's `many-one` link is cardinality many and unique, so an identity
      // can be a member of only one link (`relationships.ts`).
      InstantAttribute(
        id: attributeID(membersLabel),
        namespace: namespace,
        name: membersLabel,
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: attributeID(membersLabel),
        reverseIdentity: "\(Self.usersNamespace)/\(userLinkLabel)",
        linkNamespace: Self.usersNamespace
      ),
      .primaryKey(namespace: Self.usersNamespace),
      InstantAttribute(
        id: "\(Self.usersNamespace)/email",
        namespace: Self.usersNamespace,
        name: "email",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "\(Self.usersNamespace)/type",
        namespace: Self.usersNamespace,
        name: "type",
        valueType: .string,
        isRequired: false
      ),
    ]
  }

  /// The permission rules for the default names, to paste into the app's `instant.perms.ts` rules object.
  ///
  /// An identity can link only itself: as the creator, in the transaction that creates the row (it is then the only
  /// member), or as the row's invited identity before the invite expires. The invited identity clears its own invite
  /// in the transaction that joins. Any member can unlink any member, and the server keeps each identity in one link.
  /// `$users.view` lets the members of a link read each other's `$users` rows, and those of their linked guests.
  ///
  /// Each app also lets members read what the other members own, in its own entities' `view` rules. Scribe's
  /// recordings, for example, add:
  ///
  /// ```
  /// data.ownerUserID in auth.ref('$user.accountLink.members.id')
  ///   || data.ownerUserID in auth.ref('$user.accountLink.members.linkedGuestUsers.id')
  /// ```
  public static let permissionRulesTemplate = """
      $users: {
        allow: {
          view: "auth.id != null && (auth.id == data.id || (data.linkedPrimaryUser != null && (auth.id == data.linkedPrimaryUser || data.linkedPrimaryUser in auth.ref('$user.accountLink.members.id'))) || data.id in auth.ref('$user.accountLink.members.id'))",
        },
      },
      accountLinks: {
        bind: {
          isMember: "auth.id != null && auth.id in data.ref('members.id')",
          isInvited: "auth.id != null && data.inviteUserID == auth.id",
          inviteIsOpen: "data.inviteExpiresAtMs != null && request.time < timestamp(int(data.inviteExpiresAtMs))",
          joinsAsCreator:
            "auth.id != null && data.createdByUserID == auth.id && size(data.ref('members.id')) == 1 && auth.id in data.ref('members.id')",
          keepsCreation: "newData.createdByUserID == data.createdByUserID && newData.createdAtMs == data.createdAtMs",
          clearsOwnInvite:
            "newData.inviteUserID == null && newData.inviteExpiresAtMs == null && request.modifiedFields.all(field, field in ['members', 'inviteUserID', 'inviteExpiresAtMs', 'updatedAtMs'])",
          validCreate:
            "data.createdByUserID == auth.id && double(data.createdAtMs) <= double(data.updatedAtMs)",
        },
        allow: {
          view: "isMember || isInvited",
          create: "auth.id != null && validCreate",
          update: "(isMember && keepsCreation) || (isInvited && inviteIsOpen && clearsOwnInvite)",
          delete: "isMember",
          link: { members: "auth.id != null && linkedData.id == auth.id && ((isInvited && inviteIsOpen) || joinsAsCreator)" },
          unlink: { members: "isMember" },
        },
      },

    """

  // MARK: Reading

  /// The account link of `signIn`'s identity, read from Instant, or `nil` when the identity is in no link.
  public func accountLink(of signIn: InstantSecondSignIn) async throws -> InstantAccountLink? {
    try await row(of: signIn, operation: "read the account link")?.link
  }

  /// The account link of `primary`'s identity, read from Instant through a temporary twin of its session, or `nil`
  /// when the identity is in no link.
  public func accountLink(sharingSessionOf primary: InstantSwiftDataClient) async throws -> InstantAccountLink? {
    let twin = try await InstantSecondSignIn.open(sharingSessionOf: primary, registering: attributes)
    do {
      let link = try await accountLink(of: twin)
      await twin.close()
      return link
    } catch {
      await twin.close()
      throw error
    }
  }

  // MARK: Linking

  /// Links `second`'s identity with `primary`'s, and returns the link as Instant has it afterward.
  ///
  /// The two identities are read first, from Instant:
  ///
  /// - In the same link already: the link comes back and nothing is written.
  /// - In different links: linking is refused. An identity can be in only one link; unlink it from the other first.
  /// - One of them in a link: that identity invites the other through its link, then the other joins.
  /// - Neither: the primary identity creates a link and invites the other, then the other joins.
  ///
  /// The invite and the join each wait up to ``serverTimeout`` for Instant to accept them, and the join starts only
  /// after Instant accepts the invite. `primary`'s session never changes. A failure throws an error that names the step
  /// that failed. This method never closes `second`; close it yourself on every path.
  ///
  /// - Parameters:
  ///   - primary: The app's client, signed in.
  ///   - second: A second sign-in of another identity, opened with ``attributes`` registered.
  ///   - secondProvider: How `second` signed in, for its label.
  ///   - deviceName: The device doing the linking, for the labels it writes.
  ///   - now: When the link happens. Labels and the invite's expiry derive from it.
  @discardableResult
  public func link(
    primary: InstantSwiftDataClient,
    second: InstantSecondSignIn,
    secondProvider: InstantAccountLinkProvider?,
    deviceName: String?,
    now: Date = Date()
  ) async throws -> InstantAccountLink {
    let twin = try await Step.connecting.run {
      try await InstantSecondSignIn.open(sharingSessionOf: primary, registering: attributes)
    }
    do {
      let linked = try await link(
        twin: twin,
        second: second,
        secondProvider: secondProvider,
        deviceName: deviceName,
        nowMs: Self.milliseconds(now)
      )
      await twin.close()
      return linked
    } catch {
      await twin.close()
      throw error
    }
  }

  private func link(
    twin: InstantSecondSignIn,
    second: InstantSecondSignIn,
    secondProvider: InstantAccountLinkProvider?,
    deviceName: String?,
    nowMs: Int64
  ) async throws -> InstantAccountLink {
    guard let primarySession = try await twin.session() else {
      throw Self.refusal("The primary client is not signed in.", recovery: "Sign in on the primary client first.")
    }
    guard let secondSession = try await second.session() else {
      throw Self.refusal(
        "The second sign-in is not signed in.",
        recovery: "Sign the other identity in on the second sign-in before linking it."
      )
    }
    let primaryID = primarySession.userID
    let secondID = secondSession.userID
    guard primaryID != secondID else {
      throw Self.refusal(
        "The other sign-in is the same account as this one, so there is nothing to link.",
        recovery: "Sign in with a different Apple, Google, or email account."
      )
    }

    let primaryRow = try await Step.reading.run { try await row(of: twin, operation: "read the account link") }
    let secondRow = try await Step.reading.run {
      try await row(of: second, operation: "read the other sign-in's account link")
    }
    let primaryLabel = Self.label(
      provider: primarySession.isGuest ? .guest : nil,
      linkedAtMs: nowMs,
      deviceName: deviceName
    )
    let secondLabel = Self.label(provider: secondProvider, linkedAtMs: nowMs, deviceName: deviceName)
    let expiresAtMs = nowMs + Self.milliseconds(inviteLifetime)

    switch (primaryRow, secondRow) {
    case let (primaryRow?, secondRow?):
      guard primaryRow.id == secondRow.id else {
        throw InstantError(
          code: .validationFailed,
          operation: "link another sign-in",
          message: "The other sign-in already belongs to another account link.",
          recovery:
            "Unlink it there first: sign in with it on its own, open its linked sign-ins, and unlink it. Then link it here."
        )
      }
      return primaryRow.link

    case let (primaryRow?, nil):
      try await Step.inviting.run {
        try await twin.transactAwaitingServer(
          inviteTransaction(
            id: twin.makeID(),
            linkID: primaryRow.id,
            invitee: secondID,
            label: secondLabel,
            nowMs: nowMs,
            expiresAtMs: expiresAtMs
          ),
          operation: "the invite",
          timeout: serverTimeout
        )
      }
      try await join(primaryRow.id, as: secondID, through: second, nowMs: nowMs)

    case let (nil, secondRow?):
      try await Step.inviting.run {
        try await second.transactAwaitingServer(
          inviteTransaction(
            id: second.makeID(),
            linkID: secondRow.id,
            invitee: primaryID,
            label: primaryLabel,
            nowMs: nowMs,
            expiresAtMs: expiresAtMs
          ),
          operation: "the invite",
          timeout: serverTimeout
        )
      }
      try await join(secondRow.id, as: primaryID, through: twin, nowMs: nowMs)

    case (nil, nil):
      let linkID = twin.makeID()
      try await Step.inviting.run {
        try await twin.transactAwaitingServer(
          createTransaction(
            id: twin.makeID(),
            linkID: linkID,
            creator: primaryID,
            invitee: secondID,
            labels: [primaryID: primaryLabel, secondID: secondLabel],
            nowMs: nowMs,
            expiresAtMs: expiresAtMs
          ),
          operation: "the invite",
          timeout: serverTimeout
        )
      }
      try await join(linkID, as: secondID, through: second, nowMs: nowMs)
    }

    guard
      let linked = try await Step.reading.run({
        try await row(of: twin, operation: "read the account link")
      })
    else {
      throw Step.reading.error(
        wrapping: InstantError(
          code: .implementationFailed,
          operation: "read the account link",
          message: "Instant accepted the invite and the join, but this account's link did not come back.",
          recovery: "Read the linked sign-ins again. If the link is still missing, link again."
        )
      )
    }
    return linked.link
  }

  private func join(
    _ linkID: String,
    as joiner: String,
    through signIn: InstantSecondSignIn,
    nowMs: Int64
  ) async throws {
    try await Step.joining.run {
      try await signIn.transactAwaitingServer(
        joinTransaction(id: signIn.makeID(), linkID: linkID, joiner: joiner, nowMs: nowMs),
        operation: "the join",
        timeout: serverTimeout
      )
    }
  }

  // MARK: Unlinking

  /// Removes `memberUserID` from `primary`'s account link, and returns the link as it is afterward, or `nil` when the
  /// link is gone.
  ///
  /// Any member may unlink any member. When fewer than two members would remain, the link row is deleted instead,
  /// because a link of one identity links nothing. The write goes through a twin of `primary`'s session and waits up to
  /// ``serverTimeout`` for Instant to accept it.
  @discardableResult
  public func unlink(
    memberUserID: String,
    primary: InstantSwiftDataClient,
    now: Date = Date()
  ) async throws -> InstantAccountLink? {
    let twin = try await Step.connecting.run {
      try await InstantSecondSignIn.open(sharingSessionOf: primary, registering: attributes)
    }
    do {
      let remaining = try await unlink(memberUserID: memberUserID, twin: twin, nowMs: Self.milliseconds(now))
      await twin.close()
      return remaining
    } catch {
      await twin.close()
      throw error
    }
  }

  private func unlink(
    memberUserID: String,
    twin: InstantSecondSignIn,
    nowMs: Int64
  ) async throws -> InstantAccountLink? {
    let current = try await Step.reading.run {
      try await self.row(of: twin, operation: "read the account link")
    }
    guard let current, current.memberIDs.contains(memberUserID) else {
      throw Self.refusal(
        "That sign-in is not in this account's link.",
        recovery: "Read the linked sign-ins again, then unlink one of its members."
      )
    }
    let remainingIDs = current.memberIDs.filter { $0 != memberUserID }
    let deletesLink = remainingIDs.count < 2
    try await Step.unlinking.run {
      try await twin.transactAwaitingServer(
        deletesLink
          ? deleteTransaction(id: twin.makeID(), linkID: current.id)
          : unlinkTransaction(id: twin.makeID(), linkID: current.id, member: memberUserID, nowMs: nowMs),
        operation: deletesLink ? "the deletion of the link" : "the unlink",
        timeout: serverTimeout
      )
    }
    guard !deletesLink else { return nil }
    var link = current.link
    link.members.removeAll { $0.userID == memberUserID }
    return link
  }

  // MARK: Transactions

  private func createTransaction(
    id: String,
    linkID: String,
    creator: String,
    invitee: String,
    labels: [String: JSONValue],
    nowMs: Int64,
    expiresAtMs: Int64
  ) -> InstantStoreTransaction {
    let txTime = InstantTimestamp(milliseconds: nowMs)
    return InstantStoreTransaction(
      id: id,
      operations: [
        .requireEntityMissing(entityID: linkID, namespace: namespace),
        insert(linkID, "id", .string(linkID), id, txTime),
        insert(linkID, "createdByUserID", .string(creator), id, txTime),
        insert(linkID, "createdAtMs", .number(Double(nowMs)), id, txTime),
        insert(linkID, "updatedAtMs", .number(Double(nowMs)), id, txTime),
        insert(linkID, "inviteUserID", .string(invitee), id, txTime),
        insert(linkID, "inviteExpiresAtMs", .number(Double(expiresAtMs)), id, txTime),
        insert(linkID, "membersJSON", .json(.object(labels)), id, txTime),
        insert(linkID, membersLabel, .ref(creator), id, txTime),
      ]
    )
  }

  /// A member's invite for `invitee`, with the invitee's label merged into `membersJSON` so the join need not touch it.
  private func inviteTransaction(
    id: String,
    linkID: String,
    invitee: String,
    label: JSONValue,
    nowMs: Int64,
    expiresAtMs: Int64
  ) -> InstantStoreTransaction {
    let txTime = InstantTimestamp(milliseconds: nowMs)
    return InstantStoreTransaction(
      id: id,
      operations: [
        insert(linkID, "id", .string(linkID), id, txTime),
        insert(linkID, "inviteUserID", .string(invitee), id, txTime),
        insert(linkID, "inviteExpiresAtMs", .number(Double(expiresAtMs)), id, txTime),
        insert(linkID, "updatedAtMs", .number(Double(nowMs)), id, txTime),
        merge(linkID, "membersJSON", .json(.object([invitee: label])), id, txTime),
      ]
    )
  }

  /// The invited identity links itself and clears its own invite. The rules let it change nothing else.
  private func joinTransaction(
    id: String,
    linkID: String,
    joiner: String,
    nowMs: Int64
  ) -> InstantStoreTransaction {
    let txTime = InstantTimestamp(milliseconds: nowMs)
    return InstantStoreTransaction(
      id: id,
      operations: [
        insert(linkID, "id", .string(linkID), id, txTime),
        insert(linkID, "inviteUserID", .null, id, txTime),
        insert(linkID, "inviteExpiresAtMs", .null, id, txTime),
        insert(linkID, "updatedAtMs", .number(Double(nowMs)), id, txTime),
        insert(linkID, membersLabel, .ref(joiner), id, txTime),
      ]
    )
  }

  private func unlinkTransaction(
    id: String,
    linkID: String,
    member: String,
    nowMs: Int64
  ) -> InstantStoreTransaction {
    let txTime = InstantTimestamp(milliseconds: nowMs)
    return InstantStoreTransaction(
      id: id,
      operations: [
        insert(linkID, "id", .string(linkID), id, txTime),
        insert(linkID, "updatedAtMs", .number(Double(nowMs)), id, txTime),
        merge(linkID, "membersJSON", .json(.object([member: .null])), id, txTime),
        .retract(
          InstantTriple(
            entityID: linkID,
            attributeID: attributeID(membersLabel),
            value: .ref(member),
            txID: id,
            txTime: txTime
          )
        ),
      ]
    )
  }

  private func deleteTransaction(id: String, linkID: String) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: id,
      operations: [.deleteEntityInNamespace(entityID: linkID, namespace: namespace)]
    )
  }

  private func insert(
    _ entityID: String,
    _ field: String,
    _ value: InstantValue,
    _ transactionID: String,
    _ txTime: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID(field),
        value: value,
        txID: transactionID,
        txTime: txTime
      )
    )
  }

  private func merge(
    _ entityID: String,
    _ field: String,
    _ value: InstantValue,
    _ transactionID: String,
    _ txTime: InstantTimestamp
  ) -> InstantTripleOperation {
    .merge(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID(field),
        value: value,
        txID: transactionID,
        txTime: txTime
      )
    )
  }

  private func attributeID(_ field: String) -> String {
    "\(namespace)/\(field)"
  }

  // MARK: Reading rows

  /// A link row as Instant answers it: its members and their labels.
  private struct Row {
    var id: String
    var memberIDs: [String]
    var link: InstantAccountLink
  }

  private func row(of signIn: InstantSecondSignIn, operation: String) async throws -> Row? {
    guard let session = try await signIn.session() else {
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message: "The sign-in is not signed in, so it has no account link to read.",
        recovery: "Sign in before reading the account link."
      )
    }
    try await requireSchema(on: signIn, operation: operation)
    let users = try await signIn.queryServer(query(userID: session.userID), timeout: serverTimeout)
    guard
      let user = users.first(where: { $0.id == session.userID }),
      let row = user.links?[userLinkLabel]?.first
    else { return nil }
    let members = row.links?[membersLabel] ?? []
    let labels = Self.labels(row.values["membersJSON"])
    let linkMembers = members.map { member -> InstantAccountLink.Member in
      let label = labels[member.id] ?? [:]
      return InstantAccountLink.Member(
        userID: member.id,
        email: Self.string(member.values["email"]),
        isGuest: Self.string(member.values["type"]) == InstantAuthUserType.guest.rawValue,
        provider: Self.jsonString(label["provider"]).flatMap(InstantAccountLinkProvider.init(rawValue:)),
        linkedAt: Self.jsonNumber(label["linkedAtMs"]).map { Date(timeIntervalSince1970: $0 / 1_000) },
        deviceName: Self.jsonString(label["deviceName"])
      )
    }
    .sorted { lhs, rhs in
      let lhsTime = lhs.linkedAt ?? .distantFuture
      let rhsTime = rhs.linkedAt ?? .distantFuture
      return lhsTime == rhsTime ? lhs.userID < rhs.userID : lhsTime < rhsTime
    }
    return Row(
      id: row.id,
      memberIDs: linkMembers.map(\.userID),
      link: InstantAccountLink(id: row.id, members: linkMembers)
    )
  }

  /// Throws, naming the fix, when `signIn`'s store lacks any of ``attributes``. The store would otherwise refuse the read
  /// with a message about one undeclared field, or refuse the join after the invite was already written.
  private func requireSchema(on signIn: InstantSecondSignIn, operation: String) async throws {
    guard let runtime = signIn.client.runtime else { return }
    let declared = try await runtime.persistedStoreAttributes().reduce(into: Set<String>()) {
      identities, attribute in
      identities.insert(attribute.id)
      identities.insert("\(attribute.namespace)/\(attribute.name)")
      if let forwardIdentity = attribute.forwardIdentity {
        identities.insert(forwardIdentity)
      }
    }
    let missing = attributes.map(\.id).filter { !declared.contains($0) }
    guard missing.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        namespace: namespace,
        message:
          "This sign-in's store does not declare the account-link schema: \(missing.joined(separator: ", ")).",
        recovery:
          "Register InstantAccountLinks.attributes: add them to the app's initialAttributes, or open the second sign-in with InstantSecondSignIn.open(beside:registering: links.attributes)."
      )
    }
  }

  /// `$users` by id, its reverse `accountLink`, and that link's `members`.
  private func query(userID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "instant-account-link:\(userID)",
      namespace: Self.usersNamespace,
      filters: [.equals(field: "id", value: .string(userID))],
      includes: [
        InstantQueryInclude(
          userLinkLabel,
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "instant-account-link:\(userID):\(userLinkLabel)",
            namespace: namespace,
            includes: [
              InstantQueryInclude(
                membersLabel,
                direction: .forward,
                query: InstantQueryIncludePlan(
                  id: "instant-account-link:\(userID):\(membersLabel)",
                  namespace: Self.usersNamespace,
                  includes: []
                )
              )
            ]
          )
        )
      ]
    )
  }

  private static let usersNamespace = "$users"

  private static func label(
    provider: InstantAccountLinkProvider?,
    linkedAtMs: Int64,
    deviceName: String?
  ) -> JSONValue {
    var fields: [String: JSONValue] = ["linkedAtMs": .number(Double(linkedAtMs))]
    fields["provider"] = provider.map { .string($0.rawValue) }
    fields["deviceName"] = deviceName.map(JSONValue.string)
    return .object(fields)
  }

  private static func labels(_ value: InstantMaterializedValue?) -> [String: [String: JSONValue]] {
    guard case .json(.object(let members))? = value?.first else { return [:] }
    return members.compactMapValues { label in
      guard case .object(let fields) = label else { return nil }
      return fields
    }
  }

  private static func string(_ value: InstantMaterializedValue?) -> String? {
    guard case .string(let string)? = value?.first else { return nil }
    return string
  }

  private static func jsonString(_ value: JSONValue?) -> String? {
    guard case .string(let string)? = value else { return nil }
    return string
  }

  private static func jsonNumber(_ value: JSONValue?) -> Double? {
    guard case .number(let number)? = value else { return nil }
    return number
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func milliseconds(_ duration: Duration) -> Int64 {
    let (seconds, attoseconds) = duration.components
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }

  private static func refusal(_ message: String, recovery: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "link another sign-in",
      message: message,
      recovery: recovery
    )
  }

  /// A step of linking or unlinking. A failure names its step.
  private enum Step: String {
    case connecting = "connecting as this account"
    case reading = "reading the account link"
    case inviting
    case joining
    case unlinking

    func run<Value>(_ body: () async throws -> Value) async throws -> Value {
      do {
        return try await body()
      } catch let error as CancellationError {
        throw error
      } catch {
        throw self.error(wrapping: error)
      }
    }

    func error(wrapping error: Error) -> InstantError {
      var wrapped =
        (error as? InstantError)
        ?? InstantError(
          code: .implementationFailed,
          operation: "link another sign-in",
          message: String(describing: error),
          recovery: "Try again. If it keeps failing, report it with this message."
        )
      wrapped.message = "Account linking stopped while \(rawValue): \(wrapped.message)"
      return wrapped
    }
  }
}
