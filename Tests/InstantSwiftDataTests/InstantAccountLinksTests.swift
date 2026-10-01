import CustomDump
import Foundation
import Testing

@testable import InstantSwiftData

/// Account links join identities that Instant itself never joins: it links only guests (`$users.linkedPrimaryUser`) and
/// joins two OAuth identities only on an email match (`upsert-oauth-link!`, `instant/runtime/routes.clj`). An
/// `accountLinks` row lists one person's identities in `members`, and its permission rules let an identity link only
/// itself: the creator when it creates the row, anyone else while it holds the row's unexpired invite (#361).
///
/// So linking is two writes from two identities: the inviter writes the invite (tx1) through a twin of the primary's
/// session, and the invited identity joins and clears the invite (tx2) through its second sign-in. These tests pin the
/// exact frames, who sends each one, their order, the refusals that send nothing, and the reads in between.
@Suite(.serialized)
struct InstantAccountLinksTests {
  static let now = Date(timeIntervalSince1970: 1_700_000_000)
  static let nowMs = 1_700_000_000_000
  static let expiresMs = 1_700_000_600_000

  @Test(
    "With neither sign-in linked, the primary creates the link and invites, then the second joins",
    arguments: [false, true]
  )
  func neitherLinkedCreatesInvitesAndJoins(primaryIsGuest: Bool) async throws {
    let fixture = try await SecondSignInFixture.make(primary: primaryIsGuest ? .guest : .user)
    defer { fixture.removePrimaryStore() }
    let primaryID = primaryIsGuest ? "guest-a" : "user-a"
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)
    let mintedToken = try #require(try await second.session()?.refreshToken)

    let link = try await InstantAccountLinks.default.link(
      primary: fixture.primary,
      second: second,
      secondProvider: .google,
      deviceName: "Test iPhone",
      now: Self.now
    )

    let primaryLabel =
      primaryIsGuest
      ? #"{"deviceName":"Test iPhone","linkedAtMs":1700000000000,"provider":"guest"}"#
      : #"{"deviceName":"Test iPhone","linkedAtMs":1700000000000}"#
    let secondLabel = #"{"deviceName":"Test iPhone","linkedAtMs":1700000000000,"provider":"google"}"#
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), [primaryID, "user-b"])
    expectNoDifference(
      transacts.first?.steps,
      [
        #"["add-triple","\#(link.id)","accountLinks/id","\#(link.id)",{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/createdByUserID","\#(primaryID)",{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/createdAtMs",1700000000000,{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/updatedAtMs",1700000000000,{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/inviteUserID","user-b",{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/inviteExpiresAtMs",1700000600000,{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/membersJSON",{"\#(primaryID)":\#(primaryLabel),"user-b":\#(secondLabel)},{"mode":"create"}]"#,
        #"["add-triple","\#(link.id)","accountLinks/members","\#(primaryID)",{"mode":"create"}]"#,
      ]
    )
    expectNoDifference(transacts.last?.steps, joinSteps(linkID: link.id, joiner: "user-b"))
    let events = await fixture.server.events
    expectNoDifference(events, acceptedInOrder(transacts))
    expectNoDifference(
      link.members,
      [
        InstantAccountLink.Member(
          userID: primaryID,
          email: primaryIsGuest ? nil : "a@example.com",
          isGuest: primaryIsGuest,
          provider: primaryIsGuest ? .guest : nil,
          linkedAt: Self.now,
          deviceName: "Test iPhone"
        ),
        InstantAccountLink.Member(
          userID: "user-b",
          email: "b@example.com",
          isGuest: false,
          provider: .google,
          linkedAt: Self.now,
          deviceName: "Test iPhone"
        ),
      ]
    )
    let signOutsBeforeClose = await fixture.server.signOutTokens
    expectNoDifference(signOutsBeforeClose, [])
    let secondStore = try #require(second.client.runtime?.configuration.persistenceURL)
    expectNoDifference(secondSignInStores(appID: fixture.appID), [secondStore.lastPathComponent])

    await second.close()
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [mintedToken])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
    let primarySession = try await fixture.primary.authSession()
    expectNoDifference(primarySession?.userID, primaryID)
  }

  @Test("With only the primary linked, the primary invites through its own link, then the second joins")
  func primaryLinkedInvitesTheSecond() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.addUser(FakeInstantUser(id: "user-c", email: "c@example.com"), refreshToken: "token-c")
    await seedLink(fixture.server, id: "link-ac", members: ["user-c", "user-a"])
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let link = try await InstantAccountLinks.default.link(
      primary: fixture.primary,
      second: second,
      secondProvider: .magicCode,
      deviceName: nil,
      now: Self.now
    )
    await second.close()

    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a", "user-b"])
    expectNoDifference(
      transacts.first?.steps,
      inviteSteps(
        linkID: "link-ac",
        invitee: "user-b",
        label: #"{"linkedAtMs":1700000000000,"provider":"magicCode"}"#
      )
    )
    expectNoDifference(transacts.last?.steps, joinSteps(linkID: "link-ac", joiner: "user-b"))
    let events = await fixture.server.events
    expectNoDifference(events, acceptedInOrder(transacts))
    expectNoDifference(link.id, "link-ac")
    expectNoDifference(link.members.map(\.userID), ["user-c", "user-a", "user-b"])
    expectNoDifference(link.members.last?.provider, .magicCode)
  }

  @Test("With only the second linked, the second invites the primary, then the primary joins")
  func secondLinkedInvitesThePrimary() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.addUser(FakeInstantUser(id: "user-d", email: "d@example.com"), refreshToken: "token-d")
    await seedLink(fixture.server, id: "link-bd", members: ["user-d", "user-b"])
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let link = try await InstantAccountLinks.default.link(
      primary: fixture.primary,
      second: second,
      secondProvider: .apple,
      deviceName: "Test Mac",
      now: Self.now
    )
    await second.close()

    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-b", "user-a"])
    expectNoDifference(
      transacts.first?.steps,
      inviteSteps(
        linkID: "link-bd",
        invitee: "user-a",
        label: #"{"deviceName":"Test Mac","linkedAtMs":1700000000000}"#
      )
    )
    expectNoDifference(transacts.last?.steps, joinSteps(linkID: "link-bd", joiner: "user-a"))
    let events = await fixture.server.events
    expectNoDifference(events, acceptedInOrder(transacts))
    expectNoDifference(link.id, "link-bd")
    expectNoDifference(link.members.map(\.userID), ["user-d", "user-b", "user-a"])
  }

  @Test("Two sign-ins already in the same link return it and write nothing")
  func sameLinkWritesNothing() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await seedLink(fixture.server, id: "link-ab", members: ["user-a", "user-b"])
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let link = try await InstantAccountLinks.default.link(
      primary: fixture.primary,
      second: second,
      secondProvider: .google,
      deviceName: nil,
      now: Self.now
    )
    await second.close()

    expectNoDifference(link.id, "link-ab")
    expectNoDifference(link.members.map(\.userID), ["user-a", "user-b"])
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts, [])
  }

  @Test("A second sign-in that belongs to another link is refused before any write")
  func anotherLinkIsRefused() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.addUser(FakeInstantUser(id: "user-c"), refreshToken: "token-c")
    await fixture.server.addUser(FakeInstantUser(id: "user-d"), refreshToken: "token-d")
    await seedLink(fixture.server, id: "link-ac", members: ["user-a", "user-c"])
    await seedLink(fixture.server, id: "link-bd", members: ["user-b", "user-d"])
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let error = await thrownInstantError {
      _ = try await InstantAccountLinks.default.link(
        primary: fixture.primary,
        second: second,
        secondProvider: .google,
        deviceName: nil,
        now: Self.now
      )
    }
    await second.close()

    expectNoDifference(error?.code, .validationFailed)
    #expect(error?.message.contains("already belongs to another account link") == true)
    #expect(error?.recovery.contains("Unlink it there first") == true)
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts, [])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("A second sign-in of the primary's own account is refused before any write")
  func theSameAccountIsRefused() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let second = try await InstantSecondSignIn.open(
      beside: fixture.primary,
      registering: InstantAccountLinks.default.attributes
    )
    _ = try await second.adoptRefreshToken("token-a")

    let error = await thrownInstantError {
      _ = try await InstantAccountLinks.default.link(
        primary: fixture.primary,
        second: second,
        secondProvider: nil,
        deviceName: nil,
        now: Self.now
      )
    }
    await second.close()

    expectNoDifference(error?.code, .validationFailed)
    #expect(error?.message.contains("same account") == true)
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts, [])
  }

  @Test("The join waits for Instant to accept the invite")
  func theJoinWaitsForTheInvite() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.answerTransacts { frame in frame.userID == "user-a" ? .hold : .accept }
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let linking = Task {
      try await InstantAccountLinks.default.link(
        primary: fixture.primary,
        second: second,
        secondProvider: .google,
        deviceName: nil,
        now: Self.now
      )
    }
    try await server.waitUntilTransactCount(1)
    try await Task.sleep(for: .milliseconds(300))
    let whileTheInviteIsUnanswered = await server.transacts.map(\.userID)
    expectNoDifference(whileTheInviteIsUnanswered, ["user-a"])
    await server.releaseHeldTransacts(.accept)
    let link = try await linking.value
    await second.close()

    let transacts = await server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a", "user-b"])
    let events = await server.events
    expectNoDifference(events, acceptedInOrder(transacts))
    expectNoDifference(link.members.map(\.userID), ["user-a", "user-b"])
  }

  @Test("An invite Instant never accepts times out naming the step, sends no join, and closes the twin")
  func anUnansweredInviteSendsNoJoin() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.answerTransacts { _ in .hold }
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)
    let mintedToken = try #require(try await second.session()?.refreshToken)
    var links = InstantAccountLinks.default
    links.serverTimeout = .milliseconds(300)

    let error = await thrownInstantError {
      _ = try await links.link(
        primary: fixture.primary,
        second: second,
        secondProvider: .google,
        deviceName: nil,
        now: Self.now
      )
    }

    expectNoDifference(error?.code, .networkFailed)
    #expect(error?.message.hasPrefix("Account linking stopped while inviting:") == true)
    #expect(error?.message.contains("Waited 300 milliseconds for Instant to accept the invite") == true)
    let transacts = await server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a"])
    let secondStore = try #require(second.client.runtime?.configuration.persistenceURL)
    expectNoDifference(secondSignInStores(appID: fixture.appID), [secondStore.lastPathComponent])
    let closedSockets = await server.closedSocketUserIDs
    #expect(closedSockets.contains("user-a"))

    await second.close()
    let signOuts = await server.signOutTokens
    expectNoDifference(signOuts, [mintedToken])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("A refused join names the joining step")
  func aRefusedJoinNamesTheStep() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.answerTransacts { frame in
      frame.userID == "user-b" ? .refuse("Permission denied: link members") : .accept
    }
    let second = try await fixture.openSignedInSecond(registering: InstantAccountLinks.default.attributes)

    let error = await thrownInstantError {
      _ = try await InstantAccountLinks.default.link(
        primary: fixture.primary,
        second: second,
        secondProvider: .google,
        deviceName: nil,
        now: Self.now
      )
    }
    await second.close()

    expectNoDifference(error?.code, .permissionRejected)
    expectNoDifference(
      error?.message,
      "Account linking stopped while joining: Permission denied: link members"
    )
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("Unlinking one of three members removes that member and its label")
  func unlinkRemovesTheMember() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.addUser(FakeInstantUser(id: "user-c", email: "c@example.com"), refreshToken: "token-c")
    await seedLink(fixture.server, id: "link-abc", members: ["user-a", "user-b", "user-c"])

    let remaining = try await InstantAccountLinks.default.unlink(
      memberUserID: "user-c",
      primary: fixture.primary,
      now: Self.now
    )

    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a"])
    expectNoDifference(
      transacts.first?.steps,
      [
        #"["add-triple","link-abc","accountLinks/id","link-abc"]"#,
        #"["add-triple","link-abc","accountLinks/updatedAtMs",1700000000000]"#,
        #"["deep-merge-triple","link-abc","accountLinks/membersJSON",{"user-c":null}]"#,
        #"["retract-triple","link-abc","accountLinks/members","user-c"]"#,
      ]
    )
    expectNoDifference(remaining?.id, "link-abc")
    expectNoDifference(remaining?.members.map(\.userID), ["user-a", "user-b"])
    let serverMembers = await fixture.server.triples
      .filter { $0.entityID == "link-abc" && $0.attributeID == "accountLinks/members" }
      .compactMap(\.value.stringValue)
    expectNoDifference(serverMembers, ["user-a", "user-b"])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [])
  }

  @Test("Unlinking the last other member deletes the link")
  func unlinkingTheLastOtherMemberDeletesTheLink() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await seedLink(fixture.server, id: "link-ab", members: ["user-a", "user-b"])

    let remaining = try await InstantAccountLinks.default.unlink(
      memberUserID: "user-b",
      primary: fixture.primary,
      now: Self.now
    )

    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a"])
    expectNoDifference(
      transacts.first?.steps,
      [#"["delete-entity","link-ab","accountLinks"]"#]
    )
    expectNoDifference(remaining, nil)
    let linkTriples = await fixture.server.triples.filter { $0.entityID == "link-ab" }
    expectNoDifference(linkTriples, [])
  }

  @Test("Unlinking a sign-in that is not in the link is refused before any write")
  func unlinkingAStrangerIsRefused() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await seedLink(fixture.server, id: "link-ab", members: ["user-a", "user-b"])

    let error = await thrownInstantError {
      _ = try await InstantAccountLinks.default.unlink(
        memberUserID: "user-z",
        primary: fixture.primary,
        now: Self.now
      )
    }

    expectNoDifference(error?.code, .validationFailed)
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts, [])
  }

  @Test("Reading a link returns its members with their labels")
  func readingALinkReturnsLabeledMembers() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await seedLink(
      fixture.server,
      id: "link-ab",
      members: ["user-a", "user-b"],
      labels: [
        "user-a": #"{"provider":"apple","linkedAtMs":1600000000000,"deviceName":"Old iPhone"}"#,
        "user-b": #"{"provider":"refreshToken","linkedAtMs":1600000005000}"#,
      ]
    )
    let twin = try await InstantSecondSignIn.open(
      sharingSessionOf: fixture.primary,
      registering: InstantAccountLinks.default.attributes
    )

    let link = try await InstantAccountLinks.default.accountLink(of: twin)
    await twin.close()

    expectNoDifference(
      link,
      InstantAccountLink(
        id: "link-ab",
        members: [
          InstantAccountLink.Member(
            userID: "user-a",
            email: "a@example.com",
            isGuest: false,
            provider: .apple,
            linkedAt: Date(timeIntervalSince1970: 1_600_000_000),
            deviceName: "Old iPhone"
          ),
          InstantAccountLink.Member(
            userID: "user-b",
            email: "b@example.com",
            isGuest: false,
            provider: .refreshToken,
            linkedAt: Date(timeIntervalSince1970: 1_600_000_005),
            deviceName: nil
          ),
        ]
      )
    )
  }

  @Test("An identity in no link reads no link")
  func anUnlinkedIdentityReadsNoLink() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let twin = try await InstantSecondSignIn.open(
      sharingSessionOf: fixture.primary,
      registering: InstantAccountLinks.default.attributes
    )

    let link = try await InstantAccountLinks.default.accountLink(of: twin)
    await twin.close()

    expectNoDifference(link, nil)
  }

  /// Scribe declares only `$users/id` and `$users/linkedPrimaryUser`, and a store refuses a query on an undeclared
  /// field. A primary that registers the account-link attributes needs nothing more: second sign-ins copy its schema.
  /// The schema repeats `$users/id`, as Scribe's will: duplicate ids merge.
  @Test("A primary that registers the account-link attributes links through a plain second sign-in")
  func aPrimaryThatRegistersTheAttributesLinks() async throws {
    let fixture = try await SecondSignInFixture.make(
      attributes: [fakeNoteTextAttribute, .primaryKey(namespace: "$users")]
        + InstantAccountLinks.default.attributes,
      primary: .user
    )
    defer { fixture.removePrimaryStore() }
    let second = try await fixture.openSignedInSecond()

    let link = try await InstantAccountLinks.default.link(
      primary: fixture.primary,
      second: second,
      secondProvider: .google,
      deviceName: nil,
      now: Self.now
    )
    let read = try await InstantAccountLinks.default.accountLink(sharingSessionOf: fixture.primary)
    await second.close()

    expectNoDifference(link.members.map(\.email), ["a@example.com", "b@example.com"])
    expectNoDifference(read, link)
  }

  @Test("A second sign-in without the account-link schema fails loudly, names the fix, and writes nothing")
  func aMissingSchemaFailsLoudlyAndNamesTheFix() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let second = try await fixture.openSignedInSecond()

    let error = await thrownInstantError {
      _ = try await InstantAccountLinks.default.link(
        primary: fixture.primary,
        second: second,
        secondProvider: .google,
        deviceName: nil,
        now: Self.now
      )
    }
    await second.close()

    expectNoDifference(error?.code, .validationFailed)
    #expect(
      error?.message.hasPrefix(
        "Account linking stopped while reading the account link: This sign-in's store does not declare the account-link schema: accountLinks/id, "
      ) == true
    )
    #expect(error?.message.contains("$users/email, $users/type.") == true)
    #expect(error?.recovery.contains("Register InstantAccountLinks.attributes") == true)
    #expect(error?.recovery.contains("registering: links.attributes") == true)
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts, [])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("The members link is a has-many forward link with a has-one reverse on $users")
  func membersAttributeMatchesTheSchemaLink() throws {
    let attributes = InstantAccountLinks.default.attributes
    let members = try #require(attributes.first { $0.id == "accountLinks/members" })

    expectNoDifference(
      members,
      InstantAttribute(
        id: "accountLinks/members",
        namespace: "accountLinks",
        name: "members",
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "accountLinks/members",
        reverseIdentity: "$users/accountLink",
        linkNamespace: "$users"
      )
    )
    expectNoDifference(
      Set(attributes.map(\.id)),
      [
        "accountLinks/id",
        "accountLinks/createdByUserID",
        "accountLinks/createdAtMs",
        "accountLinks/updatedAtMs",
        "accountLinks/inviteUserID",
        "accountLinks/inviteExpiresAtMs",
        "accountLinks/membersJSON",
        "accountLinks/members",
        "$users/id",
        "$users/email",
        "$users/type",
      ]
    )
    expectNoDifference(InstantAccountLinks.default.inviteLifetime, .seconds(600))
    expectNoDifference(InstantAccountLinks.default.serverTimeout, .seconds(5))
  }

  @Test("The published rules template carries the link rules exactly")
  func theRulesTemplateCarriesTheLinkRules() {
    let template = InstantAccountLinks.permissionRulesTemplate
    let rules = [
      #"      view: "auth.id != null && (auth.id == data.id || (data.linkedPrimaryUser != null && (auth.id == data.linkedPrimaryUser || data.linkedPrimaryUser in auth.ref('$user.accountLink.members.id'))) || data.id in auth.ref('$user.accountLink.members.id'))","#,
      #"      isMember: "auth.id != null && auth.id in data.ref('members.id')","#,
      #"      isInvited: "auth.id != null && data.inviteUserID == auth.id","#,
      #"      inviteIsOpen: "data.inviteExpiresAtMs != null && request.time < timestamp(int(data.inviteExpiresAtMs))","#,
      #"        "auth.id != null && data.createdByUserID == auth.id && size(data.ref('members.id')) == 1 && auth.id in data.ref('members.id')","#,
      #"      keepsCreation: "newData.createdByUserID == data.createdByUserID && newData.createdAtMs == data.createdAtMs","#,
      #"        "newData.inviteUserID == null && newData.inviteExpiresAtMs == null && request.modifiedFields.all(field, field in ['members', 'inviteUserID', 'inviteExpiresAtMs', 'updatedAtMs'])","#,
      #"        "data.createdByUserID == auth.id && double(data.createdAtMs) <= double(data.updatedAtMs)","#,
      #"      view: "isMember || isInvited","#,
      #"      create: "auth.id != null && validCreate","#,
      #"      update: "(isMember && keepsCreation) || (isInvited && inviteIsOpen && clearsOwnInvite)","#,
      #"      delete: "isMember","#,
      #"      link: { members: "auth.id != null && linkedData.id == auth.id && ((isInvited && inviteIsOpen) || joinsAsCreator)" },"#,
      #"      unlink: { members: "isMember" },"#,
    ]
    let lines = Set(template.components(separatedBy: "\n"))

    expectNoDifference(rules.filter { !lines.contains($0) }, [])
    #expect(template.hasPrefix("  $users: {\n"))
    #expect(template.hasSuffix("  },\n"))
  }
}

// MARK: - Helpers

func seedLink(
  _ server: FakeInstantServer,
  id: String,
  members: [String],
  labels: [String: String]? = nil
) async {
  let labels =
    labels
    ?? Dictionary(
      uniqueKeysWithValues: members.enumerated().map { index, member in
        (member, #"{"linkedAtMs":\#(1_600_000_000_000 + index * 1_000)}"#)
      }
    )
  let membersJSON = InstantLiveJSONValue.object(
    labels.mapValues { try! JSONDecoder().decode(InstantLiveJSONValue.self, from: Data($0.utf8)) }
  )
  var triples = [
    FakeTriple(entityID: id, attributeID: "accountLinks/id", value: .string(id)),
    FakeTriple(entityID: id, attributeID: "accountLinks/createdByUserID", value: .string(members[0])),
    FakeTriple(entityID: id, attributeID: "accountLinks/createdAtMs", value: .number(1_600_000_000_000)),
    FakeTriple(entityID: id, attributeID: "accountLinks/updatedAtMs", value: .number(1_600_000_000_000)),
    FakeTriple(entityID: id, attributeID: "accountLinks/membersJSON", value: membersJSON),
  ]
  triples += members.map {
    FakeTriple(entityID: id, attributeID: "accountLinks/members", value: .string($0))
  }
  await server.insert(triples)
}

func inviteSteps(linkID: String, invitee: String, label: String) -> [String] {
  [
    #"["add-triple","\#(linkID)","accountLinks/id","\#(linkID)"]"#,
    #"["add-triple","\#(linkID)","accountLinks/inviteUserID","\#(invitee)"]"#,
    #"["add-triple","\#(linkID)","accountLinks/inviteExpiresAtMs",1700000600000]"#,
    #"["add-triple","\#(linkID)","accountLinks/updatedAtMs",1700000000000]"#,
    #"["deep-merge-triple","\#(linkID)","accountLinks/membersJSON",{"\#(invitee)":\#(label)}]"#,
  ]
}

func joinSteps(linkID: String, joiner: String) -> [String] {
  [
    #"["add-triple","\#(linkID)","accountLinks/id","\#(linkID)"]"#,
    #"["add-triple","\#(linkID)","accountLinks/inviteUserID",null]"#,
    #"["add-triple","\#(linkID)","accountLinks/inviteExpiresAtMs",null]"#,
    #"["add-triple","\#(linkID)","accountLinks/updatedAtMs",1700000000000]"#,
    #"["add-triple","\#(linkID)","accountLinks/members","\#(joiner)"]"#,
  ]
}

/// Each write received and then accepted before the next one arrives.
func acceptedInOrder(_ transacts: [FakeTransactFrame]) -> [FakeServerEvent] {
  transacts.flatMap {
    [
      FakeServerEvent.received(transactionID: $0.transactionID, userID: $0.userID),
      .accepted(transactionID: $0.transactionID),
    ]
  }
}

/// The second sign-in stores of `appID` that are still on disk.
func secondSignInStores(appID: String) -> [String] {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "InstantSecondSignIn",
    isDirectory: true
  )
  let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
  return names.filter { $0.hasPrefix(appID + "-") && $0.hasSuffix(".sqlite") }.sorted()
}

// MARK: - InstantAuthState linking

/// `InstantAuthState`'s linking actions drive ``InstantSecondSignIn`` and ``InstantAccountLinks`` for AuthV3. Through
/// the same fake server: the primary session never changes, the link lands in `accountLink`, and every second sign-in
/// closes (its minted token revoked, its store deleted) on success, on failure, and on cancel.
@Suite(.serialized)
@MainActor
struct InstantAuthStateLinkingTests {
  static let google = AuthProvider.google(
    clientName: "google",
    presentation: .externalBrowser,
    redirectURL: URL(string: "account-linking-test://oauth-callback")
  )

  /// Answers Google with the authorization code `code-b`, as the browser sign-in would.
  static let authorizer = InstantAuthProviderAuthorizer { provider in
    InstantAuthProviderCredential(
      providerID: provider.id,
      payload: .authorizationCode(value: "code-b", codeVerifier: "verifier-b")
    )
  }

  @Test("linkAnotherSignIn keeps the primary session, updates the link, and closes the second sign-in")
  func linkAnotherSignInLinksAndClosesTheSecond() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectOAuthCode("code-b", signsIn: "user-b")
    let state = InstantAuthState<LinkingTestUser>(providers: [Self.google])
    let callbacks = LinkingCallbacks()
    let before = try await fixture.primaryState()

    await state.linkAnotherSignIn(
      Self.google,
      using: fixture.primary,
      authorizer: Self.authorizer,
      deviceName: "Test Mac",
      onLinked: { callbacks.linked.append($0) },
      onFailure: { callbacks.failures.append($0) }
    ).value

    expectNoDifference(state.linking, .idle)
    expectNoDifference(state.accountLink?.members.map(\.userID), ["user-a", "user-b"])
    expectNoDifference(state.accountLink?.members.map(\.provider), [nil, .google])
    expectNoDifference(callbacks.linked, state.accountLink.map { [$0] } ?? [])
    expectNoDifference(callbacks.failures, [])
    let after = try await fixture.primaryState()
    expectNoDifference(after, before)
    let minted = await fixture.server.mintedTokens
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(minted.count, 1)
    expectNoDifference(signOuts, minted)
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("A failed link ends in failed, names the step, and still closes the second sign-in")
  func aFailedLinkStillClosesTheSecond() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectOAuthCode("code-b", signsIn: "user-b")
    await fixture.server.answerTransacts { frame in
      frame.userID == "user-b" ? .refuse("Permission denied: link members") : .accept
    }
    let state = InstantAuthState<LinkingTestUser>(providers: [Self.google])
    let callbacks = LinkingCallbacks()
    let before = try await fixture.primaryState()

    await state.linkAnotherSignIn(
      Self.google,
      using: fixture.primary,
      authorizer: Self.authorizer,
      onLinked: { callbacks.linked.append($0) },
      onFailure: { callbacks.failures.append($0) }
    ).value

    guard case .failed(let error) = state.linking else {
      Issue.record("Expected a failed link, got \(state.linking).")
      return
    }
    expectNoDifference(
      error.message,
      "Account linking stopped while joining: Permission denied: link members"
    )
    expectNoDifference(callbacks.failures, [error])
    expectNoDifference(callbacks.linked, [])
    expectNoDifference(state.accountLink, nil)
    let after = try await fixture.primaryState()
    expectNoDifference(after, before)
    let minted = await fixture.server.mintedTokens
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, minted)
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }

  @Test("The email code path holds the second sign-in until the code links it, then closes it")
  func theEmailCodePathHoldsThenCloses() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let state = InstantAuthState<LinkingTestUser>(providers: [Self.google])

    await state.sendLinkMagicCode(email: " b@example.com ", using: fixture.primary).value
    expectNoDifference(state.linking, .codeSent(email: "b@example.com"))
    expectNoDifference(state.linkCodeEmail, "b@example.com")
    expectNoDifference(secondSignInStores(appID: fixture.appID).count, 1)

    await state.verifyLinkMagicCode(email: "b@example.com", code: "000000", using: fixture.primary).value
    guard case .failed = state.linking else {
      Issue.record("Expected a wrong code to fail, got \(state.linking).")
      return
    }
    expectNoDifference(state.linkCodeEmail, "b@example.com")
    expectNoDifference(secondSignInStores(appID: fixture.appID).count, 1)

    await state.verifyLinkMagicCode(
      email: "b@example.com",
      code: "123456",
      using: fixture.primary,
      deviceName: "Test Mac"
    ).value
    expectNoDifference(state.linking, .idle)
    expectNoDifference(state.linkCodeEmail, nil)
    expectNoDifference(state.accountLink?.members.map(\.userID), ["user-a", "user-b"])
    expectNoDifference(state.accountLink?.members.map(\.provider), [nil, .magicCode])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
    let minted = await fixture.server.mintedTokens
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, minted)
  }

  @Test("Cancelling a pending code closes the held second sign-in")
  func cancellingAPendingCodeClosesTheHeldSecond() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let state = InstantAuthState<LinkingTestUser>(providers: [Self.google])
    await state.sendLinkMagicCode(email: "b@example.com", using: fixture.primary).value
    expectNoDifference(secondSignInStores(appID: fixture.appID).count, 1)

    await state.cancelLinking().value

    expectNoDifference(state.linking, .idle)
    expectNoDifference(state.linkCodeEmail, nil)
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [])
  }

  @Test("refreshAccountLink reads the link, and unlink updates it")
  func refreshAndUnlinkUpdateTheAccountLink() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await seedLink(fixture.server, id: "link-ab", members: ["user-a", "user-b"])
    let state = InstantAuthState<LinkingTestUser>(providers: [Self.google])
    let callbacks = LinkingCallbacks()

    await state.refreshAccountLink(using: fixture.primary).value
    expectNoDifference(state.accountLink?.id, "link-ab")
    expectNoDifference(state.accountLink?.members.map(\.userID), ["user-a", "user-b"])

    await state.unlink(
      memberUserID: "user-b",
      using: fixture.primary,
      onUnlinked: { callbacks.unlinked.append($0) },
      onFailure: { callbacks.failures.append($0) }
    ).value

    expectNoDifference(state.linking, .idle)
    expectNoDifference(state.accountLink, nil)
    expectNoDifference(callbacks.unlinked, [nil])
    expectNoDifference(callbacks.failures, [])
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-a"])
    expectNoDifference(secondSignInStores(appID: fixture.appID), [])
  }
}

/// The smallest `$users` model `InstantAuthState` needs.
struct LinkingTestUser: InstantEntityModel {
  static let instantNamespace = "$users"
  static let instantAttributes: [InstantAttribute] = []

  var id: InstantID<Self>

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }
}

@MainActor
final class LinkingCallbacks {
  var linked: [InstantAccountLink] = []
  var unlinked: [InstantAccountLink?] = []
  var failures: [InstantError] = []
}
