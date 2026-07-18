import CustomDump
import Darwin
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct BootstrapTests {
  @Test
  func defaultClientReportsMissingBootstrap() async {
    @Dependency(\.defaultInstantSwiftData) var client

    do {
      _ = try await client.transact(InstantStoreTransaction(id: "tx", operations: []))
      #expect(Bool(false), "Expected the default client to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.query(TodoExample.query)
      #expect(Bool(false), "Expected the default client query to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.authSession()
      #expect(Bool(false), "Expected the default client auth session to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.observeAuthSession()
      #expect(Bool(false), "Expected the default client auth observer to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.signInWithIDToken(clientName: "google-ios", idToken: "token")
      #expect(Bool(false), "Expected the default client ID token auth to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.signInWithOAuth(code: "oauth-code")
      #expect(Bool(false), "Expected the default client OAuth auth to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.joinRoom(.default)
      #expect(Bool(false), "Expected the default client room join to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.leaveRoom(.default)
      #expect(Bool(false), "Expected the default client room leave to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func bootstrapInstallsRuntimeBackedClient() async throws {
    let appID = "bootstrap-test-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      guard let runtime = client.runtime else {
        #expect(Bool(false), "Expected a runtime-backed client.")
        return
      }
      #expect(runtime.configuration.persistenceURL.path.contains(fixedUUID.uuidString.lowercased()))
      expectNoDifference(runtime.configuration.apiURI.absoluteString, "https://api.example.test/custom")
      expectNoDifference(
        runtime.configuration.websocketURI.absoluteString,
        "wss://ws.example.test/runtime/session"
      )

      let authorizationURL = try client.oauthAuthorizationURL(
        clientName: "google-ios",
        redirectURL: try #require(URL(string: "myapp://oauth/callback"))
      )
      let authorizationComponents = try #require(
        URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
      )
      expectNoDifference(authorizationComponents.host, "api.example.test")
      let issuerURI = try client.issuerURI()
      expectNoDifference(issuerURI.absoluteString, "https://api.example.test/custom/runtime/\(appID)")

      let localID = try await client.localID(named: "todos.bootstrap")
      expectNoDifference(localID, fixedUUID.uuidString.lowercased())

      let transaction = InstantStoreTransaction(
        id: "tx-bootstrap",
        operations: TodoExample.createOperations(
          id: "todo-bootstrap",
          text: "Use dependencies",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
          transactionID: "tx-bootstrap"
        )
      )
      try await client.transact(transaction)

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(
        todos,
        [
          TodoRecord(
            id: "todo-bootstrap",
            text: "Use dependencies",
            isCompleted: false,
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
          )
        ]
      )

      let emission = try await client.queryOnce(
        InstantQueryPlan(
          id: "bootstrap-test.first",
          namespace: TodoExample.namespace,
          first: 1
        )
      )
      expectNoDifference(emission.queryID, "bootstrap-test.first")
      expectNoDifference(emission.values.map(\.id), ["todo-bootstrap"])
      expectNoDifference(emission.pageInfo?.hasNextPage, false)

      let status = try await client.connectionStatus()
      expectNoDifference(status.appID, appID)
      expectNoDifference(status.apiURI.absoluteString, "https://api.example.test/custom")
      expectNoDifference(
        status.websocketURI.absoluteString,
        "wss://ws.example.test/runtime/session"
      )
      expectNoDifference(status.transport, .localCacheOnly)
      expectNoDifference(status.state, .opened)
      expectNoDifference(status.pendingMutationCount, 1)

      let closedStatus = try await client.closeConnection()
      expectNoDifference(closedStatus.state, .closed)
      expectNoDifference(closedStatus.pendingMutationCount, 1)

      let reconnectedStatus = try await client.connect()
      expectNoDifference(reconnectedStatus.state, .opened)
      expectNoDifference(reconnectedStatus.pendingMutationCount, 1)
    }
  }

  @Test
  func bootstrapUsesLocalMagicCodeExchangeByDefault() async throws {
    let appID = "local-magic-code-default-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fixedTimestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let fixedUUID = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataLocalMagicCode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let challenge = try await client.sendMagicCode(email: " User@Example.COM ")
      expectNoDifference(
        challenge,
        InstantMagicCodeChallenge(
          appID: appID,
          email: "user@example.com",
          code: "123456",
          createdAt: fixedTimestamp,
          expiresAt: InstantTimestamp(milliseconds: fixedTimestamp.milliseconds + 600_000)
        )
      )

      let session = try await client.signInWithMagicCode(
        email: "user@example.com",
        code: " 123456 "
      )
      expectNoDifference(
        session,
        InstantAuthSession(
          appID: appID,
          userID: "email:user@example.com",
          refreshToken: "local-magic:\(appID):user@example.com",
          isGuest: false,
          createdAt: fixedTimestamp,
          updatedAt: fixedTimestamp
        )
      )
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
    }
  }

  @Test
  func bootstrapMagicCodeSignInResultPersistsExtraFields() async throws {
    let appID = "local-magic-code-result-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_009)
    let fixedTimestamp = InstantTimestamp(milliseconds: 1_700_000_009_000)
    let fixedUUID = UUID(uuidString: "98765432-0000-0000-0000-000000000000")!
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "InstantSwiftDataLocalMagicCodeResult-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: [
          InstantAttribute(
            id: "$users/email",
            namespace: "$users",
            name: "email",
            valueType: .string,
            isRequired: false,
            isIndexed: true,
            isUnique: true
          ),
          InstantAttribute(
            id: "$users/username",
            namespace: "$users",
            name: "username",
            valueType: .string,
            isRequired: false,
            isIndexed: true,
            isUnique: true
          ),
        ]
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let challenge = try await client.sendMagicCode(email: " New@Example.COM ")
      expectNoDifference(challenge.code, "987654")

      let result = try await client.signInWithMagicCodeResult(
        email: "new@example.com",
        code: " 987654 ",
        extraFields: [
          "username": .string("cool_user")
        ]
      )
      expectNoDifference(
        result,
        InstantMagicCodeSignInResult(
          session: InstantAuthSession(
            appID: appID,
            userID: "email:new@example.com",
            refreshToken: "local-magic:\(appID):new@example.com",
            isGuest: false,
            createdAt: fixedTimestamp,
            updatedAt: fixedTimestamp
          ),
          created: true
        )
      )

      let user = try #require(
        try await client.query(
          InstantQueryPlan(id: "bootstrap.auth-extra-fields.users", namespace: "$users")
        )
        .first { $0.id == "email:new@example.com" }
      )
      expectNoDifference(
        user.values,
        [
          "id": .one(.string("email:new@example.com")),
          "email": .one(.string("new@example.com")),
          "username": .one(.string("cool_user")),
        ]
      )
      let pendingMutations = await client.pendingMutations()
      expectNoDifference(pendingMutations, [])
    }
  }

  @Test
  func runtimeBackedClientForwardsShareOperations() async throws {
    let appID = "share-forwarding-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataShareForwarding-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      guard client.runtime != nil else {
        Issue.record("Expected a runtime-backed client.")
        return
      }

      _ = try await client.signInWithRefreshToken("owner-refresh", userID: "user-1")
      var ownerIterator = try await client.observeShares().makeAsyncIterator()
      let ownerInitialShares = await ownerIterator.next()
      expectNoDifference(ownerInitialShares, [])

      let created = try await client.createShare(
        rootNamespace: TodoExample.namespace,
        rootID: "todo-public-client"
      )
      let listedShares = try await client.shares()
      expectNoDifference(listedShares, [created])
      let ownerCreatedEmission = await ownerIterator.next()
      expectNoDifference(ownerCreatedEmission, [created])

      _ = try await client.signInWithRefreshToken("invitee-refresh", userID: "user-2")
      let accepted = try await client.acceptShare(token: created.share.token)
      var inviteeIterator = try await client.observeShares().makeAsyncIterator()
      let inviteeInitialShares = await inviteeIterator.next()
      expectNoDifference(inviteeInitialShares, [accepted])
      let ownerAcceptedEmission = await ownerIterator.next()
      expectNoDifference(ownerAcceptedEmission, [accepted])

      _ = try await client.signInWithRefreshToken("owner-refresh", userID: "user-1")
      let promoted = try await client.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "user-2",
        role: .writer
      )
      let ownerPromotedEmission = await ownerIterator.next()
      expectNoDifference(ownerPromotedEmission, [promoted])
      let inviteePromotedEmission = await inviteeIterator.next()
      expectNoDifference(inviteePromotedEmission, [promoted])

      _ = try await client.revokeShare(id: created.share.id)
      let ownerRevokedEmission = await ownerIterator.next()
      expectNoDifference(ownerRevokedEmission, [])
      let inviteeRevokedEmission = await inviteeIterator.next()
      expectNoDifference(inviteeRevokedEmission, [])
    }
  }

  @Test
  func draftValidationProvesGeneratedCreateEditAndRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataDraftValidation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let idGenerator = DraftValidationIDGenerator([
      "draft-validation-created",
      "draft-validation-author",
      "draft-validation-post",
    ])

    let result = try await InstantSwiftDataDraftValidation.run(
      appID: "draft-validation-test",
      cacheURL: directory.appendingPathComponent("state.sqlite"),
      timestamp: { InstantTimestamp(milliseconds: 1_700_001_000_000) },
      makeID: { idGenerator.next() }
    )

    expectNoDifference(result.appID, "draft-validation-test")
    expectNoDifference(result.evidence.map(\.event), ["create", "edit", "relation", "relaunch"])
    expectNoDifference(result.evidence.map(\.ok), [true, true, true, true])
    expectNoDifference(result.evidence.first?.details.createdID, "draft-validation-created")
    expectNoDifference(result.evidence.first?.details.newDraftIDWasNil, true)
    expectNoDifference(
      result.evidence.first?.details.newDraftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(
      result.evidence.first?.details.newDraftIncludedPrimaryKeyAssignment,
      false
    )
    let relationDetails = try #require(result.evidence.first { $0.event == "relation" }?.details)
    expectNoDifference(relationDetails.draftAuthorIDs, ["draft-validation-author"])
    expectNoDifference(relationDetails.draftAuthorNames, ["Draft relation author"])
    expectNoDifference(relationDetails.draftPostIDs, ["draft-validation-post"])
    expectNoDifference(relationDetails.draftPostTitles, ["Post from relation draft"])
    expectNoDifference(relationDetails.draftPostAuthorIDs, ["draft-validation-author"])
    expectNoDifference(relationDetails.draftPostAuthorAttributeValueType, "ref")
    expectNoDifference(relationDetails.draftPostAuthorLinkNamespace, "draftValidationAuthors")
    expectNoDifference(
      relationDetails.draftPostAuthorForwardIdentity,
      "draftValidationPosts/author"
    )
    expectNoDifference(
      relationDetails.draftPostAuthorReverseIdentity,
      "draftValidationAuthors/posts"
    )
    expectNoDifference(relationDetails.relationAuthorID, "draft-validation-author")
    expectNoDifference(relationDetails.relationPostID, "draft-validation-post")
    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(
      finalDetails.draftTodoAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(finalDetails.draftTodoIDs, ["draft-validation-created"])
    expectNoDifference(finalDetails.draftTodoTitles, ["Edit from generated draft"])
    expectNoDifference(finalDetails.draftTodoCompletionStates, [true])
    expectNoDifference(finalDetails.draftTodoNotes, ["Edited through Draft(existing)"])
    expectNoDifference(finalDetails.draftAuthorIDs, ["draft-validation-author"])
    expectNoDifference(finalDetails.draftPostIDs, ["draft-validation-post"])
    expectNoDifference(finalDetails.draftPostAuthorIDs, ["draft-validation-author"])
    expectNoDifference(
      finalDetails.pendingMutationIDs.sorted(),
      [
        "validation.typed-drafts.author",
        "validation.typed-drafts.create",
        "validation.typed-drafts.edit",
        "validation.typed-drafts.post",
      ]
    )
    expectNoDifference(
      finalDetails.draftMutationSummaries.map(\.mutationID).sorted(),
      [
        "validation.typed-drafts.author",
        "validation.typed-drafts.create",
        "validation.typed-drafts.edit",
        "validation.typed-drafts.post",
      ]
    )
    expectNoDifference(finalDetails.newDraftIDWasNil, true)
    expectNoDifference(
      finalDetails.newDraftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(finalDetails.newDraftIncludedPrimaryKeyAssignment, false)
    let createMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.create"
      }
    )
    expectNoDifference(createMutation.status, "pending")
    expectNoDifference(createMutation.transactionID, "validation.typed-drafts.create")
    expectNoDifference(
      createMutation.operationKinds,
      ["requireEntityMissing", "insert", "insert", "insert", "insert", "insert"]
    )
    expectNoDifference(createMutation.preconditionKinds, ["entity-missing"])
    expectNoDifference(createMutation.preconditionNamespaces, ["draftValidationTodos"])
    expectNoDifference(createMutation.txStepKinds, Array(repeating: "add-triple", count: 5))
    expectNoDifference(
      createMutation.txStepAttributeIDs,
      [
        "draftValidationTodos/id",
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    expectNoDifference(
      createMutation.operationValueSummaries,
      [
        "string:draft-validation-created",
        "string:Create from generated draft",
        "boolean:false",
        "date:1700001000000",
        "null",
      ]
    )
    expectNoDifference(createMutation.operationValueTypes, ["string", "string", "boolean", "date", "null"])
    expectNoDifference(createMutation.txStepOptionModes, Array(repeating: "create", count: 5))
    expectNoDifference(createMutation.primaryKeyStepCount, 1)
    expectNoDifference(
      createMutation.draftAssignmentAttributeIDs,
      [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ]
    )
    let editMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.edit"
      }
    )
    expectNoDifference(editMutation.preconditionKinds, [])
    expectNoDifference(editMutation.transactionID, "validation.typed-drafts.edit")
    expectNoDifference(editMutation.txStepKinds, Array(repeating: "add-triple", count: 5))
    expectNoDifference(editMutation.txStepEntityIDs, Array(repeating: "draft-validation-created", count: 5))
    expectNoDifference(editMutation.txStepOptionModes, Array(repeating: "none", count: 5))
    expectNoDifference(
      editMutation.operationValueSummaries,
      [
        "string:draft-validation-created",
        "string:Edit from generated draft",
        "boolean:true",
        "date:1700001000000",
        "string:Edited through Draft(existing)",
      ]
    )
    let postMutation = try #require(
      finalDetails.draftMutationSummaries.first {
        $0.mutationID == "validation.typed-drafts.post"
      }
    )
    expectNoDifference(postMutation.transactionID, "validation.typed-drafts.post")
    expectNoDifference(postMutation.txStepKinds, Array(repeating: "add-triple", count: 3))
    expectNoDifference(postMutation.txStepEntityIDs, Array(repeating: "draft-validation-post", count: 3))
    expectNoDifference(
      postMutation.txStepAttributeIDs,
      [
        "draftValidationPosts/id",
        "draftValidationPosts/title",
        "draftValidationPosts/author",
      ]
    )
    expectNoDifference(postMutation.txStepValueTypes, ["string", "string", "string"])
    expectNoDifference(postMutation.operationValueTypes, ["string", "string", "ref"])
    expectNoDifference(
      postMutation.operationValueSummaries,
      [
        "string:draft-validation-post",
        "string:Post from relation draft",
        "ref:draft-validation-author",
      ]
    )
    expectNoDifference(postMutation.refAttributeIDs, ["draftValidationPosts/author"])
    expectNoDifference(finalDetails.createdID, "draft-validation-created")
    expectNoDifference(finalDetails.editedID, "draft-validation-created")
    expectNoDifference(finalDetails.relationAuthorID, "draft-validation-author")
    expectNoDifference(finalDetails.relationPostID, "draft-validation-post")
  }

  @Test
  func draftValidationDetailsDecodesLegacyEvidence() throws {
    let details = try JSONDecoder().decode(
      DraftValidationDetails.self,
      from: Data(
        """
        {
          "cachePath": "/tmp/state.sqlite",
          "draftTodoAttributeIDs": [
            "draftValidationTodos/title",
            "draftValidationTodos/isCompleted",
            "draftValidationTodos/createdAt",
            "draftValidationTodos/notes"
          ],
          "draftTodoIDs": ["draft-validation-created"],
          "draftTodoTitles": ["Edit from generated draft"],
          "draftTodoCompletionStates": [true],
          "draftTodoNotes": ["Edited through Draft(existing)"],
          "pendingMutationIDs": [
            "validation.typed-drafts.create",
            "validation.typed-drafts.edit"
          ],
          "createdID": "draft-validation-created",
          "editedID": "draft-validation-created"
        }
        """.utf8
      )
    )

    expectNoDifference(details.draftAuthorIDs, [])
    expectNoDifference(details.draftAuthorNames, [])
    expectNoDifference(details.draftPostIDs, [])
    expectNoDifference(details.draftPostAuthorIDs, [])
    expectNoDifference(details.draftPostAuthorAttributeValueType, nil)
    expectNoDifference(details.draftPostAuthorLinkNamespace, nil)
    expectNoDifference(details.draftMutationSummaries, [])
    expectNoDifference(details.newDraftIDWasNil, false)
    expectNoDifference(details.newDraftAssignmentAttributeIDs, [])
    expectNoDifference(details.newDraftIncludedPrimaryKeyAssignment, false)
    expectNoDifference(details.createdID, "draft-validation-created")
    expectNoDifference(details.editedID, "draft-validation-created")
  }

  @Test
  func platformAdapterValidationDetailsDecodeOlderEvidenceWithoutBindingAdapters() throws {
    let details = try JSONDecoder().decode(
      PlatformAdapterValidationDetails.self,
      from: Data(
        """
        {
          "adapter": "@FetchAll",
          "cachePath": "/tmp/state.sqlite",
          "todoCount": 1,
          "todoIDs": ["todo-1"],
          "todoTitles": ["Older evidence"]
        }
        """.utf8
      )
    )

    expectNoDifference(details.adapter, "@FetchAll")
    expectNoDifference(details.bindingAdapters, [])
    expectNoDifference(details.todoIDs, ["todo-1"])
    expectNoDifference(details.todoTitles, ["Older evidence"])
    expectNoDifference(details.previousTodoTitles, [])
    expectNoDifference(details.roomMemberIDs, [])
  }

  @Test
  func platformAdapterValidationProvesWrappersBindLocalRuntime() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "InstantSwiftDataPlatformAdapterValidation-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let result = try await InstantSwiftDataPlatformAdapterValidation.run(
      appID: "platform-adapter-validation-test",
      cacheURL: directory.appendingPathComponent("state.sqlite"),
      timestamp: { InstantTimestamp(milliseconds: 1_700_002_000_000) },
      makeID: { "platform-adapter-validation-id" }
    )

    expectNoDifference(result.appID, "platform-adapter-validation-test")
    expectNoDifference(result.evidence.map(\.event), [
      "fetch-all",
      "fetch-one",
      "fetch",
      "local-id",
      "auth-session",
      "room-presence",
      "room-topic-messages",
      "stored-files",
      "stream-chunks",
      "shares",
      "projected-bindings",
      "fetch-all-filtered-reload",
      "fetch-all-dynamic-query",
      "fetch-one-dynamic-query",
      "fetch-request-dynamic-query",
      "fetch-all-nil-query",
      "fetch-one-nil-query",
      "fetch-request-nil-request",
      "fetch-all-cached-prior-error",
      "fetch-all-cancellation",
      "fetch-request-cancellation",
      "infinite-query-dynamic-cancellation",
      "infinite-query-dynamic-load",
      "live-wrapper-dynamic-cancellation",
      "live-wrapper-topic-messages-cancellation",
      "live-wrapper-stored-files-cancellation",
      "live-wrapper-stream-chunks-cancellation",
      "live-wrapper-shares-cancellation",
      "connection-status",
    ])
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 29))
    expectNoDifference(result.evidence.map(\.appID), Array(repeating: result.appID, count: 29))
    expectNoDifference(result.evidence.map(\.details.adapter), [
      "@FetchAll",
      "@FetchOne",
      "@Fetch",
      "@LocalID",
      "@AuthSession",
      "@RoomPresence",
      "@RoomTopicMessages",
      "@StoredFiles",
      "@StreamChunks",
      "@Shares",
      "Projected bindings",
      "@FetchAll/@Fetch(filtered)",
      "@FetchAll(dynamic)",
      "@FetchOne(dynamic)",
      "@Fetch(request dynamic)",
      "@FetchAll(nil)",
      "@FetchOne(nil)",
      "@Fetch(request nil)",
      "@FetchAll(error)",
      "@FetchAll(cancellation)",
      "@Fetch(request cancellation)",
      "@InfiniteQuery(dynamic cancellation)",
      "@InfiniteQuery(dynamic load)",
      "@RoomPresence(dynamic cancellation)",
      "@RoomTopicMessages(cancellation)",
      "@StoredFiles(cancellation)",
      "@StreamChunks(cancellation)",
      "@Shares(cancellation)",
      "@ConnectionStatus",
    ])

    let fetchAll = try #require(result.evidence.first?.details)
    expectNoDifference(fetchAll.todoTitles, ["Bind public adapter wrappers"])
    expectNoDifference(fetchAll.todoCount, 1)

    let fetchOne = try #require(result.evidence.first { $0.event == "fetch-one" }?.details)
    expectNoDifference(fetchOne.selectedTodoID, "platform-adapter-validation-id")
    expectNoDifference(fetchOne.selectedTodoTitle, "Bind public adapter wrappers")

    let localID = try #require(result.evidence.first { $0.event == "local-id" }?.details)
    expectNoDifference(localID.localID, "platform-adapter-validation-id")

    let authSession = try #require(result.evidence.first { $0.event == "auth-session" }?.details)
    expectNoDifference(authSession.authUserID, "adapter-user")

    let presence = try #require(result.evidence.first { $0.event == "room-presence" }?.details)
    expectNoDifference(presence.roomMemberIDs, ["adapter-user"])

    let topic = try #require(result.evidence.first { $0.event == "room-topic-messages" }?.details)
    expectNoDifference(topic.topicMessageIDs, ["platform-adapter-validation-id"])

    let file = try #require(result.evidence.first { $0.event == "stored-files" }?.details)
    expectNoDifference(file.fileIDs, ["platform-adapter-validation-id"])

    let filteredReload = try #require(
      result.evidence.first { $0.event == "fetch-all-filtered-reload" }?.details
    )
    expectNoDifference(
      filteredReload.fetchAllTitleBatches,
      [[], ["Engineering"], [], ["Engineering"]]
    )
    expectNoDifference(
      filteredReload.fetchTitleBatches,
      [[], ["Engineering"], [], ["Engineering"]]
    )
    expectNoDifference(filteredReload.queryCount, 6)

    let dynamic = try #require(
      result.evidence.first { $0.event == "fetch-all-dynamic-query" }?.details
    )
    expectNoDifference(dynamic.previousTodoTitles, ["Open dynamic"])
    expectNoDifference(dynamic.todoTitles, ["Done dynamic"])
    expectNoDifference(dynamic.queryCount, 2)

    let fetchOneDynamic = try #require(
      result.evidence.first { $0.event == "fetch-one-dynamic-query" }?.details
    )
    expectNoDifference(fetchOneDynamic.previousTodoTitles, ["Open single"])
    expectNoDifference(fetchOneDynamic.todoTitles, ["Done single"])
    expectNoDifference(fetchOneDynamic.selectedTodoTitle, "Done single")
    expectNoDifference(fetchOneDynamic.queryCount, 2)

    let fetchRequestDynamic = try #require(
      result.evidence.first { $0.event == "fetch-request-dynamic-query" }?.details
    )
    expectNoDifference(fetchRequestDynamic.previousTodoTitles, ["Open request"])
    expectNoDifference(fetchRequestDynamic.todoTitles, ["Done request"])
    expectNoDifference(fetchRequestDynamic.todoCount, 2)
    expectNoDifference(fetchRequestDynamic.queryCount, 4)
    expectNoDifference(fetchRequestDynamic.observationCount, 0)

    let nilQuery = try #require(
      result.evidence.first { $0.event == "fetch-all-nil-query" }?.details
    )
    expectNoDifference(nilQuery.previousTodoTitles, ["Cached nil query"])
    expectNoDifference(nilQuery.todoTitles, [])
    expectNoDifference(nilQuery.queryCount, 0)
    expectNoDifference(nilQuery.nilQueryCleared, true)

    let fetchOneNilQuery = try #require(
      result.evidence.first { $0.event == "fetch-one-nil-query" }?.details
    )
    expectNoDifference(fetchOneNilQuery.previousTodoTitles, ["Cached optional nil query"])
    expectNoDifference(fetchOneNilQuery.todoTitles, [])
    expectNoDifference(fetchOneNilQuery.selectedTodoTitle, nil)
    expectNoDifference(fetchOneNilQuery.queryCount, 0)
    expectNoDifference(fetchOneNilQuery.nilQueryCleared, true)

    let fetchRequestNil = try #require(
      result.evidence.first { $0.event == "fetch-request-nil-request" }?.details
    )
    expectNoDifference(fetchRequestNil.previousTodoTitles, ["Cached request nil"])
    expectNoDifference(fetchRequestNil.todoTitles, [])
    expectNoDifference(fetchRequestNil.todoCount, 0)
    expectNoDifference(fetchRequestNil.queryCount, 0)
    expectNoDifference(fetchRequestNil.nilQueryCleared, nil)
    expectNoDifference(fetchRequestNil.nilRequestCleared, true)

    let cachedPrior = try #require(
      result.evidence.first { $0.event == "fetch-all-cached-prior-error" }?.details
    )
    expectNoDifference(cachedPrior.todoTitles, ["Cached before error"])
    expectNoDifference(cachedPrior.loadErrorOperation, "query dynamic FetchAll")

    let cancellation = try #require(
      result.evidence.first { $0.event == "fetch-all-cancellation" }?.details
    )
    expectNoDifference(cancellation.observationCount, 1)
    expectNoDifference(cancellation.cancellationTerminated, true)

    let requestCancellation = try #require(
      result.evidence.first { $0.event == "fetch-request-cancellation" }?.details
    )
    expectNoDifference(requestCancellation.queryCount, 0)
    expectNoDifference(requestCancellation.observationCount, 1)
    expectNoDifference(requestCancellation.cancellationTerminated, true)

    let infiniteCancellation = try #require(
      result.evidence.first { $0.event == "infinite-query-dynamic-cancellation" }?.details
    )
    expectNoDifference(infiniteCancellation.todoTitles, ["Second infinite subscription"])
    expectNoDifference(infiniteCancellation.previousTodoTitles, ["First infinite subscription"])
    expectNoDifference(infiniteCancellation.observationCount, 2)
    expectNoDifference(infiniteCancellation.cancellationTerminated, true)
    expectNoDifference(infiniteCancellation.isLoading, false)

    let infiniteLoad = try #require(
      result.evidence.first { $0.event == "infinite-query-dynamic-load" }?.details
    )
    expectNoDifference(infiniteLoad.previousTodoTitles, ["Fresh infinite load"])
    expectNoDifference(infiniteLoad.fetchAllTitleBatches, [["Fresh infinite load"], []])
    expectNoDifference(infiniteLoad.todoTitles, [])
    expectNoDifference(infiniteLoad.queryCount, 3)
    expectNoDifference(infiniteLoad.nilQueryCleared, true)
    expectNoDifference(infiniteLoad.isLoading, false)
    expectNoDifference(infiniteLoad.loadErrorOperation, nil)

    let liveWrapperCancellation = try #require(
      result.evidence.first { $0.event == "live-wrapper-dynamic-cancellation" }?.details
    )
    expectNoDifference(liveWrapperCancellation.roomMemberIDs, ["presence-second-live-room"])
    expectNoDifference(liveWrapperCancellation.observationCount, 2)
    expectNoDifference(liveWrapperCancellation.cancellationTerminated, true)
    expectNoDifference(liveWrapperCancellation.isLoading, false)

    let stream = try #require(result.evidence.first { $0.event == "stream-chunks" }?.details)
    expectNoDifference(stream.streamChunkIDs, ["platform-adapter-validation-id"])

    let shares = try #require(result.evidence.first { $0.event == "shares" }?.details)
    expectNoDifference(shares.shareIDs, ["platform-adapter-validation-id"])

    let projectedBindings = try #require(
      result.evidence.first { $0.event == "projected-bindings" }?.details
    )
    expectNoDifference(projectedBindings.adapter, "Projected bindings")
    expectNoDifference(projectedBindings.bindingAdapters, [
      "@FetchAll",
      "@InfiniteQuery",
      "@FetchOne",
      "@Fetch",
      "@LocalID",
      "@AuthSession",
      "@ConnectionStatus",
      "@RoomPresence",
      "@RoomTopicMessages",
      "@StoredFiles",
      "@StreamChunks",
      "@Shares",
    ])
    expectNoDifference(projectedBindings.todoTitles, ["Bind public adapter wrappers"])
    expectNoDifference(projectedBindings.todoCount, 1)
    expectNoDifference(projectedBindings.selectedTodoID, "platform-adapter-validation-id")
    expectNoDifference(projectedBindings.localID, "platform-adapter-validation-id")
    expectNoDifference(projectedBindings.authUserID, "adapter-user")
    expectNoDifference(projectedBindings.connectionStates, [.authenticated])

    let connectionStatus = try #require(
      result.evidence.first { $0.event == "connection-status" }?.details
    )
    expectNoDifference(
      connectionStatus.connectionStates,
      [.connecting, .authenticated, .closed]
    )
    expectNoDifference(connectionStatus.isLoading, false)
    expectNoDifference(projectedBindings.roomMemberIDs, ["adapter-user"])
    expectNoDifference(projectedBindings.topicMessageIDs, ["platform-adapter-validation-id"])
    expectNoDifference(projectedBindings.fileIDs, ["platform-adapter-validation-id"])
    expectNoDifference(projectedBindings.streamChunkIDs, ["platform-adapter-validation-id"])
    expectNoDifference(projectedBindings.shareIDs, ["platform-adapter-validation-id"])
  }

  @Test
  func bootstrapUsesMagicCodeExchangeDependency() async throws {
    let appID = "magic-code-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataMagicCode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantMagicCodeExchange(
      send: { request in
        InstantMagicCodeChallenge(
          appID: request.appID,
          email: request.email,
          code: "246810",
          createdAt: request.sentAt,
          expiresAt: InstantTimestamp(milliseconds: request.sentAt.milliseconds + 60_000)
        )
      },
      verify: { request in
        InstantMagicCodeVerification(
          userID: "dependency:\(request.appID):\(request.email):\(request.code)",
          refreshToken: "challenge:\(request.challenge.code)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantMagicCodeExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let emptySession = try await client.authSession()
      expectNoDifference(emptySession, nil)
      let authStream = try await client.observeAuthSession()
      var authIterator = authStream.makeAsyncIterator()
      let observedEmptySession = try #require(await authIterator.next())
      expectNoDifference(observedEmptySession, nil)

      let guestSession = try await client.signInAsGuest()
      expectNoDifference(guestSession.appID, appID)
      expectNoDifference(guestSession.isGuest, true)
      let persistedGuestSession = try await client.authSession()
      expectNoDifference(persistedGuestSession, guestSession)
      let observedGuestSession = try #require(await authIterator.next())
      expectNoDifference(observedGuestSession, guestSession)

      try await client.signOut()
      let signedOutGuestSession = try await client.authSession()
      expectNoDifference(signedOutGuestSession, nil)
      let observedSignedOutGuestSession = try #require(await authIterator.next())
      expectNoDifference(observedSignedOutGuestSession, nil)

      let challenge = try await client.sendMagicCode(email: " User@Example.COM ")
      expectNoDifference(challenge.code, "246810")

      let session = try await client.signInWithMagicCode(
        email: "user@example.com",
        code: "246810"
      )
      expectNoDifference(session.userID, "dependency:\(appID):user@example.com:246810")
      expectNoDifference(session.refreshToken, "challenge:246810")
      let persistedMagicSession = try await client.authSession()
      expectNoDifference(persistedMagicSession, session)
      let observedMagicSession = try #require(await authIterator.next())
      expectNoDifference(observedMagicSession, session)

      try await client.signOut()
      let signedOutMagicSession = try await client.authSession()
      expectNoDifference(signedOutMagicSession, nil)
      let observedSignedOutMagicSession = try #require(await authIterator.next())
      expectNoDifference(observedSignedOutMagicSession, nil)

      let tokenSession = try await client.signInWithRefreshToken(
        " refresh-token ",
        userID: " token-user "
      )
      expectNoDifference(tokenSession.userID, "token-user")
      expectNoDifference(tokenSession.refreshToken, "refresh-token")
      expectNoDifference(tokenSession.isGuest, false)
      let persistedTokenSession = try await client.authSession()
      expectNoDifference(persistedTokenSession, tokenSession)
      let observedTokenSession = try #require(await authIterator.next())
      expectNoDifference(observedTokenSession, tokenSession)
    }
  }

  @Test
  func bootstrapUsesRefreshTokenVerifierDependency() async throws {
    let appID = "refresh-token-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataRefreshToken-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let verifier = InstantRefreshTokenVerifier(
      verify: { request in
        InstantRefreshTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.refreshToken):\(request.userID ?? "nil"):\(request.signedInAt.milliseconds)",
          refreshToken: "dependency-refresh:\(request.refreshToken)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantRefreshTokenVerifier = verifier
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let session = try await client.signInWithRefreshToken(
        " refresh-token ",
        userID: " token-user "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):refresh-token:token-user:1700000000000"
      )
      expectNoDifference(session.refreshToken, "dependency-refresh:refresh-token")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
    }
  }

  @Test
  func bootstrapUsesIDTokenExchangeDependency() async throws {
    let appID = "id-token-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataIDToken-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantIDTokenExchange(
      signIn: { request in
        InstantIDTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.clientName):\(request.idToken):\(request.nonce ?? "nil")",
          refreshToken: "dependency-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantIDTokenExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let authStream = try await client.observeAuthSession()
      var authIterator = authStream.makeAsyncIterator()
      let observedEmptySession = try #require(await authIterator.next())
      expectNoDifference(observedEmptySession, nil)

      let session = try await client.signInWithIDToken(
        clientName: " google-ios ",
        idToken: " jwt-token ",
        nonce: " nonce-1 "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):google-ios:jwt-token: nonce-1 "
      )
      expectNoDifference(session.refreshToken, "dependency-refresh:1700000000000")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
      let observedSession = try #require(await authIterator.next())
      expectNoDifference(observedSession, session)
    }
  }

  @Test
  func bootstrapUsesOAuthExchangeDependency() async throws {
    let appID = "oauth-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataOAuth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantOAuthExchange(
      signIn: { request in
        InstantOAuthVerification(
          userID:
            "dependency:\(request.appID):\(request.code):\(request.codeVerifier ?? "nil"):\(request.refreshToken ?? "nil")",
          refreshToken: "dependency-oauth-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantOAuthExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      _ = try await client.signInWithRefreshToken("existing-refresh", userID: "existing-user")
      let session = try await client.signInWithOAuth(
        code: " oauth-code ",
        codeVerifier: " verifier with spaces "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):oauth-code: verifier with spaces :existing-refresh"
      )
      expectNoDifference(session.refreshToken, "dependency-oauth-refresh:1700000000000")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
    }
  }

  @Test
  func bootstrapUsesAuthTokenInvalidatorDependency() async throws {
    let appID = "sign-out-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataSignOut-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let recorder = AuthTokenInvalidationRecorder()
    let invalidator = InstantAuthTokenInvalidator(
      invalidate: { request in
        await recorder.record(request)
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantAuthTokenInvalidator = invalidator
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      _ = try await client.signInWithRefreshToken("refresh-token", userID: "token-user")
      let signOut: () async throws -> Void = client.signOut
      try await signOut()
      let signedOutSession = try await client.authSession()
      expectNoDifference(signedOutSession, nil)
      let defaultRequests = await recorder.requests()
      expectNoDifference(defaultRequests.count, 1)
      expectNoDifference(defaultRequests.first?.appID, appID)
      expectNoDifference(defaultRequests.first?.refreshToken, "refresh-token")
      expectNoDifference(defaultRequests.first?.signedOutAt.milliseconds, 1_700_000_000_000)

      _ = try await client.signInWithRefreshToken("second-refresh-token", userID: "token-user")
      try await client.signOut(invalidateToken: false)
      let skippedInvalidationSession = try await client.authSession()
      expectNoDifference(skippedInvalidationSession, nil)
      let skippedRequests = await recorder.requests()
      expectNoDifference(skippedRequests.count, 1)
    }
  }

  @Test
  func bootstrapUsesMutationTransportDependency() async throws {
    let appID = "mutation-transport-dependency-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataMutationTransport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let recorder = BootstrapMutationTransportRecorder()
    let transport = InstantMutationTransportClient { request in
      await recorder.record(request)
      return InstantMutationTransportResponse(
        results: request.mutations.map { mutation in
          InstantMutationTransportResult(mutationID: mutation.mutationID, outcome: .confirmed)
        }
      )
    }

    try await withDependencies {
      $0.instantMutationTransport = transport
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

      try await client.transact(
        InstantStoreTransaction(
          id: "tx-dependency-flush",
          operations: TodoExample.createOperations(
            id: "todo-dependency-flush",
            text: "dependency transport",
            createdAt: createdAt,
            transactionID: "tx-dependency-flush"
          )
        )
      )

      let result = try await client.flushPendingMutations()
      expectNoDifference(result.request.appID, appID)
      expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-dependency-flush"])
      expectNoDifference(result.confirmed.map(\.id), ["tx-dependency-flush"])
      expectNoDifference(result.pendingMutationCount, 0)

      let requests = await recorder.requests()
      expectNoDifference(requests.map { $0.appID }, [appID])
      expectNoDifference(requests.first?.mutations.map(\.mutationID), ["tx-dependency-flush"])
      let pendingMutations = await client.pendingMutations()
      expectNoDifference(pendingMutations, [])
    }
  }

  @Test
  func bootstrapUsesLiveTransportDependency() async throws {
    let appID = "live-transport-dependency-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataLiveTransport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try await withDependencies {
      $0.instantLiveTransport = .local
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let status = try await client.connectionStatus()
      expectNoDifference(status.transport, .webSocket)
      expectNoDifference(status.state, .closed)
      expectNoDifference(
        status.websocketURI.absoluteString,
        "wss://ws.example.test/runtime/session"
      )

      let connectedStatus = try await client.connect()
      expectNoDifference(connectedStatus.transport, .webSocket)
      expectNoDifference(connectedStatus.state, .opened)
      expectNoDifference(connectedStatus.pendingMutationCount, 0)

      let closedStatus = try await client.closeConnection()
      expectNoDifference(closedStatus.transport, .webSocket)
      expectNoDifference(closedStatus.state, .closed)
    }
  }

  @Test
  func bootstrapUsesAppBuilderPlatformAndGeneratorDependencies() async throws {
    let appID = "app-builder-dependency-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataAppBuilder-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let platform = InstantPlatformAppClient { request in
      InstantPlatformApp(
        id: "override-platform-\(request.makeID())",
        title: request.title,
        orgID: request.orgID,
        createdAt: request.createdAt
      )
    }
    let generator = AppBuilderCodeGeneratorClient { request in
      AsyncThrowingStream { continuation in
        continuation.yield(
          AppBuilderGenerationChunk(
            kind: .reasoning,
            text: "Override reasoning for \(request.prompt)."
          )
        )
        continuation.yield(
          AppBuilderGenerationChunk(
            kind: .code,
            text: "override code for \(request.instantAppID)"
          )
        )
        continuation.finish()
      }
    }

    try await withDependencies {
      $0.instantPlatformAppClient = platform
      $0.appBuilderCodeGenerator = generator
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: AppBuilderExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      let runtime = try #require(client.runtime)
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

      let platformApp = try await runtime.configuration.platformAppClient.createApp(
        InstantPlatformAppCreateRequest(
          title: "Dependency app",
          orgID: "org-dependency",
          createdAt: createdAt,
          makeID: { "build-dependency" }
        )
      )
      expectNoDifference(platformApp.id, "override-platform-build-dependency")
      expectNoDifference(platformApp.orgID, "org-dependency")

      let stream = try await runtime.configuration.appBuilderCodeGenerator.generate(
        AppBuilderGenerationRequest(
          prompt: "Build a dependency demo",
          buildID: "build-dependency",
          instantAppID: platformApp.id
        )
      )
      var iterator = stream.makeAsyncIterator()
      let reasoning = try #require(try await iterator.next())
      let code = try #require(try await iterator.next())
      let finished = try await iterator.next()
      expectNoDifference(reasoning.kind, .reasoning)
      expectNoDifference(reasoning.text, "Override reasoning for Build a dependency demo.")
      expectNoDifference(code.kind, .code)
      expectNoDifference(code.text, "override code for override-platform-build-dependency")
      expectNoDifference(finished, nil)
    }
  }

  @Test
  func syncUpRecordingDependenciesCanBeOverridden() async throws {
    let soundEffects = BootstrapSyncUpSoundEffectRecorder()
    let settings = BootstrapSyncUpOpenSettingsRecorder()

    try await withDependencies {
      $0.syncUpSpeechClient = .scripted(
        authorizationStatus: .notDetermined,
        requestedAuthorization: .authorized,
        results: [
          SyncUpSpeechRecognitionResult(formattedString: "Dependency transcript", isFinal: true)
        ]
      )
      $0.syncUpSoundEffectClient = SyncUpSoundEffectClient(
        load: { await soundEffects.load($0) },
        play: { await soundEffects.play() }
      )
      $0.syncUpOpenSettingsClient = SyncUpOpenSettingsClient {
        await settings.open()
      }
    } operation: {
      @Dependency(\.syncUpSpeechClient) var speechClient
      @Dependency(\.syncUpSoundEffectClient) var soundEffectClient
      @Dependency(\.syncUpOpenSettingsClient) var openSettingsClient

      let status = speechClient.authorizationStatus()
      let requestedStatus = await speechClient.requestAuthorization()
      let stream = await speechClient.startTask()
      var transcripts: [String] = []
      for try await result in stream {
        transcripts.append(result.formattedString)
      }
      await soundEffectClient.load("ding.wav")
      await soundEffectClient.play()
      await openSettingsClient.open()
      let loadedFileNames = await soundEffects.loadedFileNames()
      let playCount = await soundEffects.playCount()
      let openCount = await settings.openCount()

      expectNoDifference(status, .notDetermined)
      expectNoDifference(requestedStatus, .authorized)
      expectNoDifference(transcripts, ["Dependency transcript"])
      expectNoDifference(loadedFileNames, ["ding.wav"])
      expectNoDifference(playCount, 1)
      expectNoDifference(openCount, 1)
    }
  }

  @Test
  func dependencyOverrideCanInstallMockClient() async throws {
    let signOutOptions = SignOutOptionsRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: 0,
          emissions: []
        )
      },
      query: { _ in
        [
          InstantEntitySnapshot(
            id: "mock-todo",
            namespace: TodoExample.namespace,
            values: [
              "text": .one(.string("Mocked")),
              "isCompleted": .one(.bool(true)),
              "createdAt": .one(.date(Date(timeIntervalSince1970: 1_700_000_001))),
            ]
          )
        ]
      },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" },
      authSession: {
        InstantAuthSession(
          appID: "mock-app",
          userID: "mock-user",
          refreshToken: "mock-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 1),
          updatedAt: InstantTimestamp(milliseconds: 2)
        )
      },
      observeAuthSession: {
        AsyncStream { continuation in
          continuation.yield(
            InstantAuthSession(
              appID: "mock-app",
              userID: "mock-observed-user",
              refreshToken: "mock-observed-refresh",
              isGuest: false,
              createdAt: InstantTimestamp(milliseconds: 8),
              updatedAt: InstantTimestamp(milliseconds: 9)
            )
          )
          continuation.finish()
        }
      },
      signInAsGuest: {
        InstantAuthSession(
          appID: "mock-app",
          userID: "mock-guest",
          isGuest: true,
          createdAt: InstantTimestamp(milliseconds: 3),
          updatedAt: InstantTimestamp(milliseconds: 3)
        )
      },
      sendMagicCode: { email in
        InstantMagicCodeChallenge(
          appID: "mock-app",
          email: email,
          code: "135790",
          createdAt: InstantTimestamp(milliseconds: 4),
          expiresAt: InstantTimestamp(milliseconds: 5)
        )
      },
      signInWithMagicCode: { email, code in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(email):\(code)",
          refreshToken: "mock-magic-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 6),
          updatedAt: InstantTimestamp(milliseconds: 6)
        )
      },
      signInWithRefreshToken: { refreshToken, userID in
        InstantAuthSession(
          appID: "mock-app",
          userID: userID ?? "mock-token-user",
          refreshToken: refreshToken,
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 7),
          updatedAt: InstantTimestamp(milliseconds: 7)
        )
      },
      oauthAuthorizationURL: { clientName, redirectURL in
        var components = URLComponents(string: "https://mock.example/runtime/oauth/start")!
        components.queryItems = [
          URLQueryItem(name: "client", value: clientName),
          URLQueryItem(name: "redirect", value: redirectURL.absoluteString),
        ]
        return components.url!
      },
      issuerURI: {
        URL(string: "https://mock.example/runtime/mock-app")!
      },
      signOut: {},
      signInWithIDToken: { clientName, idToken, nonce in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(clientName):\(idToken):\(nonce ?? "nil")",
          refreshToken: "mock-id-token-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 10),
          updatedAt: InstantTimestamp(milliseconds: 10)
        )
      },
      signInWithOAuth: { code, codeVerifier in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(code):\(codeVerifier ?? "nil")",
          refreshToken: "mock-oauth-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 11),
          updatedAt: InstantTimestamp(milliseconds: 11)
        )
      },
      signOutWithOptions: { invalidateToken in
        await signOutOptions.record(invalidateToken)
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let localID = try await client.localID(named: "todo")
      expectNoDifference(localID, "mock-todo")

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(todos.map(\.text), ["Mocked"])
      expectNoDifference(todos.map(\.isCompleted), [true])

      let mockSession = try await client.authSession()
      expectNoDifference(mockSession?.userID, "mock-user")
      let mockAuthStream = try await client.observeAuthSession()
      var mockAuthIterator = mockAuthStream.makeAsyncIterator()
      let mockObservedSession = try #require(await mockAuthIterator.next())
      expectNoDifference(mockObservedSession?.userID, "mock-observed-user")
      let mockAuthSubscription = try await client.subscribeAuthSession()
      var mockAuthSubscriptionIterator = mockAuthSubscription.makeAsyncIterator()
      let mockSubscribedSession = try #require(try await mockAuthSubscriptionIterator.next())
      expectNoDifference(mockSubscribedSession?.userID, "mock-observed-user")
      mockAuthSubscription.cancel()
      let mockGuest = try await client.signInAsGuest()
      expectNoDifference(mockGuest.userID, "mock-guest")
      let mockChallenge = try await client.sendMagicCode(email: "mock@example.com")
      expectNoDifference(mockChallenge.code, "135790")
      let mockMagicSession = try await client.signInWithMagicCode(
        email: "mock@example.com",
        code: "135790"
      )
      expectNoDifference(mockMagicSession.userID, "mock@example.com:135790")
      let mockMagicResult = try await client.signInWithMagicCodeResult(
        email: "mock@example.com",
        code: "135790"
      )
      expectNoDifference(mockMagicResult.session.userID, "mock@example.com:135790")
      expectNoDifference(mockMagicResult.created, false)
      do {
        _ = try await client.signInWithMagicCodeResult(
          email: "mock@example.com",
          code: "135790",
          extraFields: ["username": .string("cool_user")]
        )
        Issue.record("Expected old magic-code overrides to reject extra fields.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .implementationFailed)
        expectNoDifference(error.operation, "sign in with magic code")
      }
      let mockTokenSession = try await client.signInWithRefreshToken("mock-token", userID: nil)
      expectNoDifference(mockTokenSession.userID, "mock-token-user")
      let mockAuthorizationURL = try client.oauthAuthorizationURL(
        clientName: "mock-client",
        redirectURL: try #require(URL(string: "myapp://oauth"))
      )
      let mockAuthorizationComponents = try #require(
        URLComponents(url: mockAuthorizationURL, resolvingAgainstBaseURL: false)
      )
      expectNoDifference(mockAuthorizationComponents.host, "mock.example")
      let mockIssuerURI = try client.issuerURI()
      expectNoDifference(mockIssuerURI.absoluteString, "https://mock.example/runtime/mock-app")
      let mockIDTokenSession = try await client.signInWithIDToken(
        clientName: "mock-client",
        idToken: "mock-id-token",
        nonce: nil
      )
      expectNoDifference(mockIDTokenSession.userID, "mock-client:mock-id-token:nil")
      let mockOAuthSession = try await client.signInWithOAuth(
        code: "mock-code",
        codeVerifier: nil
      )
      expectNoDifference(mockOAuthSession.userID, "mock-code:nil")
      try await client.signOut(invalidateToken: false)
      let recordedSignOutOptions = await signOutOptions.values()
      expectNoDifference(recordedSignOutOptions, [false])
    }
  }

  @Test
  func nonReactiveAdapterMethodsDelegateToInjectedOperations() async throws {
    let recorder = NonReactiveClientOperationRecorder()
    let session = mockAuthSession(userID: "adapter-user")
    let transaction = InstantStoreTransaction(id: "tx-adapter-forwarding", operations: [])
    let plan = InstantQueryPlan(id: "adapter.once", namespace: TodoExample.namespace)
    let client = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record("transact:\(transaction.id)")
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      queryOnce: { plan in
        await recorder.record("queryOnce:\(plan.id):\(plan.namespace)")
        return InstantQueryEmission(
          queryID: plan.id,
          sequence: 1,
          values: [],
          pageInfo: InstantQueryPageInfo(
            startCursor: nil,
            endCursor: nil,
            hasPreviousPage: false,
            hasNextPage: false
          )
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in
        await recorder.record("localID:\(name)")
        return "local-id-\(name)"
      },
      authSession: {
        await recorder.record("authSession")
        return session
      }
    )

    let result = try await client.transact(transaction)
    expectNoDifference(result.transactionID, "tx-adapter-forwarding")

    let auth = try await client.authSession()
    expectNoDifference(auth, session)

    let emission = try await client.queryOnce(plan)
    expectNoDifference(emission.queryID, "adapter.once")
    expectNoDifference(emission.pageInfo?.hasNextPage, false)

    let localID = try await client.localID(named: "device")
    expectNoDifference(localID, "local-id-device")

    let events = await recorder.events()
    expectNoDifference(
      events,
      [
        "transact:tx-adapter-forwarding",
        "authSession",
        "queryOnce:adapter.once:todos",
        "localID:device",
      ]
    )
  }

  @Test
  func connectionStatusPropertyWrapperStartsConnecting() {
    @ConnectionStatus var status: InstantConnectionStatus

    expectNoDifference(status.state, .connecting)
    expectNoDifference($status.loadError, nil)
    expectNoDifference($status.isLoading, false)
  }

  @Test
  func connectionStatusPropertyWrapperLoadsUsingDependencyClient() async throws {
    let loaded = mockConnectionStatus(state: .authenticated, userID: "cached-user")
    let client = connectionStatusClient(
      load: { loaded },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @ConnectionStatus var status: InstantConnectionStatus

      try await $status.load()

      expectNoDifference(status, loaded)
      expectNoDifference($status.loadError, nil)
      expectNoDifference($status.isLoading, false)
    }
  }

  @Test
  func connectionStatusPropertyWrapperTaskBindsObservedStatuses() async throws {
    let client = connectionStatusClient(
      load: { mockConnectionStatus(state: .opened) },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(mockConnectionStatus(state: .opened))
          continuation.yield(mockConnectionStatus(state: .authenticated, userID: "observed-user"))
          continuation.finish()
        }
      }
    )

    @ConnectionStatus var status: InstantConnectionStatus

    try await $status.task(using: client)

    expectNoDifference(status.state, .authenticated)
    expectNoDifference(status.userID, "observed-user")
    expectNoDifference($status.loadError, nil)
    expectNoDifference($status.isLoading, false)
  }

  @Test
  func connectionStatusPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = AuthSessionTermination()
    let client = connectionStatusClient(
      load: { mockConnectionStatus(state: .opened) },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(mockConnectionStatus(state: .opened))
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let status = ConnectionStatus()
    let subscription = try await status.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initial = try #require(try await iterator.next())
    expectNoDifference(initial.state, .opened)

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func authSessionPropertyWrapperStartsNil() {
    @AuthSession var session: InstantAuthSession?

    expectNoDifference(session, nil)
    expectNoDifference($session.loadError, nil)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperLoadsUsingDependencyClient() async throws {
    let loaded = mockAuthSession(userID: "cached-user")
    let client = authSessionClient(
      load: { loaded },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @AuthSession var session: InstantAuthSession?

      try await $session.load()

      expectNoDifference(session, loaded)
      expectNoDifference($session.loadError, nil)
      expectNoDifference($session.isLoading, false)
    }
  }

  @Test
  func authSessionPropertyWrapperLoadCancellationDoesNotOverwriteCachedValue() async throws {
    let gate = AuthSessionLoadGate()
    let cached = mockAuthSession(userID: "cached-user")
    let loaded = mockAuthSession(userID: "late-user")
    let client = authSessionClient(
      load: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return loaded
      },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )
    let auth = AuthSession(wrappedValue: cached)

    let task = Task {
      let auth = auth
      try await auth.load(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @AuthSession load cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }

    expectNoDifference(auth.wrappedValue, cached)
    expectNoDifference(auth.loadError, nil)
    expectNoDifference(auth.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperTaskUsesCachedRuntimeSession() async throws {
    let appID = "auth-session-cached-runtime-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_004)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000704")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      let guest = try await client.signInAsGuest()
      let auth = AuthSession()
      let task = Task {
        let auth = auth
        try await auth.task(using: client)
      }
      defer {
        task.cancel()
      }

      try await waitForBootstrapCondition(operation: "wait for cached AuthSession task value") {
        auth.wrappedValue == guest
      }
      expectNoDifference(auth.loadError, nil)
      expectNoDifference(auth.isLoading, false)

      task.cancel()
      do {
        try await task.value
        Issue.record("Expected @AuthSession cached runtime task cancellation to throw.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }
    }
  }

  @Test
  func authSessionPropertyWrapperTaskBindsObservedSessions() async throws {
    let signedIn = mockAuthSession(userID: "observed-user")
    let client = authSessionClient(
      load: { nil },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.yield(signedIn)
          continuation.finish()
        }
      }
    )

    @AuthSession var session: InstantAuthSession?

    try await $session.task(using: client)

    expectNoDifference(session, signedIn)
    expectNoDifference($session.loadError, nil)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionRequiredUserThrowsUntilObserved() async throws {
    let signedIn = mockAuthSession(userID: "u1")
    let client = authSessionClient(
      load: { nil },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.yield(signedIn)
          continuation.finish()
        }
      }
    )

    @AuthSession var session: InstantAuthSession?

    do {
      _ = try $session.requireUser()
      #expect(Bool(false), "Expected @AuthSession required user to throw while signed out.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "access AuthSession user")
      expectNoDifference(
        error.message,
        "useUser must be used within an auth-protected route"
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    try await $session.task(using: client)

    let user = try $session.requireUser()
    expectNoDifference(user, signedIn)
    expectNoDifference(session?.userID, "u1")
    expectNoDifference($session.loadError, nil)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperTaskStartsLoadingUntilObservationBegins() async throws {
    let gate = AuthSessionLoadGate()
    let signedIn = mockAuthSession(userID: "pending-observed-user")
    let client = authSessionClient(
      load: { nil },
      observe: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(signedIn)
          continuation.finish()
        }
      }
    )

    let auth = AuthSession()
    let task = Task {
      let auth = auth
      try await auth.task(using: client)
    }

    await gate.waitUntilStarted()
    expectNoDifference(auth.wrappedValue, nil)
    expectNoDifference(auth.loadError, nil)
    expectNoDifference(auth.isLoading, true)

    await gate.release()
    try await task.value

    expectNoDifference(auth.wrappedValue, signedIn)
    expectNoDifference(auth.loadError, nil)
    expectNoDifference(auth.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperTaskPreservesCachedValueAndRecordsObservationError()
    async throws
  {
    let cached = mockAuthSession(userID: "cached-user")
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "observe test AuthSession",
      message: "auth observation failed",
      recovery: "Retry with a working auth observer."
    )
    let client = authSessionClient(
      load: { nil },
      observe: { throw expectedError }
    )

    @AuthSession var session: InstantAuthSession? = cached

    do {
      try await $session.task(using: client)
      #expect(Bool(false), "Expected @AuthSession task to surface observer failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "observe test AuthSession")
      expectNoDifference($session.loadError?.operation, "observe test AuthSession")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    expectNoDifference(session, cached)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = AuthSessionTermination()
    let client = authSessionClient(
      load: { nil },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let auth = AuthSession()
    let subscription = try await auth.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initial = try await iterator.next()
    if case .some(nil) = initial {
    } else {
      #expect(Bool(false), "Expected initial auth session emission to be nil.")
    }

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func authSessionPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = mockAuthSession(userID: "cached-user")
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test AuthSession",
      message: "auth failed",
      recovery: "Retry with a working auth client."
    )
    let client = authSessionClient(
      load: { throw expectedError },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )

    @AuthSession var session: InstantAuthSession? = cached

    do {
      try await $session.load(using: client)
      #expect(Bool(false), "Expected @AuthSession to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test AuthSession")
      expectNoDifference($session.loadError?.operation, "load test AuthSession")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    expectNoDifference(session, cached)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func roomClientOperationsUseInjectedClosures() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let client = roomClient(
      joinRoom: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return room
      },
      leaveRoom: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return room
      },
      setPresence: { room, userID, values in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(userID, "user-1")
        expectNoDifference(values, ["status": .string("online")])
        return member
      },
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      },
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream { continuation in
          continuation.yield([member])
          continuation.finish()
        }
      },
      leavePresence: { room, userID in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(userID, "user-1")
        return "user-1"
      },
      publishTopicMessage: { room, topic, userID, payload in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(userID, "user-1")
        expectNoDifference(payload, .object(["emoji": .string("wave")]))
        return message
      },
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [message]
      },
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream { continuation in
          continuation.yield([message])
          continuation.finish()
        }
      }
    )

    let joinedRoom = try await client.joinRoom(room)
    expectNoDifference(joinedRoom, room)
    let setMember = try await client.setRoomPresence(
      room: room,
      userID: "user-1",
      values: ["status": .string("online")]
    )
    expectNoDifference(setMember, member)
    let listedMembers = try await client.roomPresence(room: room)
    expectNoDifference(listedMembers, [member])

    var presenceIterator = try await client.observeRoomPresence(room: room).makeAsyncIterator()
    let observedMembers = await presenceIterator.next()
    expectNoDifference(observedMembers, [member])

    let leftUserID = try await client.leaveRoomPresence(room: room, userID: "user-1")
    expectNoDifference(leftUserID, "user-1")
    let publishedMessage = try await client.publishRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      userID: "user-1",
      payload: .object(["emoji": .string("wave")])
    )
    expectNoDifference(publishedMessage, message)
    let listedMessages = try await client.roomTopicMessages(
      room: room,
      topic: "sendEmoji",
      limit: 1
    )
    expectNoDifference(listedMessages, [message])

    var topicIterator = try await client.observeRoomTopicMessages(
      room: room,
      topic: "sendEmoji"
    ).makeAsyncIterator()
    let observedMessages = await topicIterator.next()
    expectNoDifference(observedMessages, [message])
    let leftRoom = try await client.leaveRoom(room)
    expectNoDifference(leftRoom, room)
  }

  @Test
  func roomPublishTopicAdapterJoinsBeforePublishing() async throws {
    let room = InstantRoomHandle(type: "chat", id: "r1")
    let recorder = RoomLifecycleRecorder()
    let client = roomClient(
      joinRoom: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "r1"))
        await recorder.record("join:\(room.type):\(room.id)")
        return room
      },
      publishTopicMessage: { room, topic, userID, payload in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "r1"))
        expectNoDifference(topic, "emoji")
        expectNoDifference(userID, nil)
        expectNoDifference(payload, .object(["value": .string("fire")]))
        await recorder.record("publish:\(topic)")
        return mockRoomTopicMessage(room: room, topic: topic, payload: payload)
      }
    )

    let joinedRoom = try await client.joinRoom(room)
    let message = try await client.publishRoomTopicMessage(
      room: joinedRoom,
      topic: "emoji",
      payload: .object(["value": .string("fire")])
    )

    expectNoDifference(joinedRoom, room)
    expectNoDifference(message.room, room)
    expectNoDifference(message.topic, "emoji")
    expectNoDifference(message.payload, .object(["value": .string("fire")]))
    let events = await recorder.events()
    expectNoDifference(events, ["join:chat:r1", "publish:emoji"])
  }

  @Test
  func roomHandleSupportsVueStyleDefaults() async throws {
    let defaultRoom = InstantRoomHandle()
    let explicitDefaultRoom = InstantRoomHandle(
      type: InstantRoomHandle.defaultType,
      id: InstantRoomHandle.defaultID
    )

    expectNoDifference(defaultRoom, explicitDefaultRoom)
    expectNoDifference(InstantRoomHandle.default, explicitDefaultRoom)
    expectNoDifference(defaultRoom.type, "_defaultRoomType")
    expectNoDifference(defaultRoom.id, "_defaultRoomId")

    let member = mockRoomPresenceMember(room: defaultRoom, userID: "default-user")
    let client = roomClient(
      roomPresence: { room in
        expectNoDifference(room, defaultRoom)
        return [member]
      }
    )
    let presence = RoomPresence(room: defaultRoom)

    try await presence.load(using: client)

    expectNoDifference(presence.wrappedValue, [member])
    expectNoDifference(presence.loadError, nil)
    expectNoDifference(presence.isLoading, false)
  }

  @Test
  func roomPresencePropertyWrapperLoadsUsingDependencyClient() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let client = roomClient(
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @RoomPresence("chat", "lobby") var members: [InstantRoomPresenceMember]

      try await $members.load()

      expectNoDifference(members, [member])
      expectNoDifference($members.loadError, nil)
      expectNoDifference($members.isLoading, false)
    }
  }

  @Test
  func roomPresencePropertyWrapperTaskBindsObservedMembers() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let client = roomClient(
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([member])
          continuation.finish()
        }
      }
    )

    @RoomPresence var members: [InstantRoomPresenceMember]

    try await $members.task("chat", "lobby", using: client)

    expectNoDifference(members, [member])
    expectNoDifference($members.loadError, nil)
    expectNoDifference($members.isLoading, false)
  }

  @Test
  func roomPresencePropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = roomClient(
      observeRoomPresence: { _ in
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let presence = RoomPresence("chat", "lobby")
    let subscription = try await presence.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialMembers = try await iterator.next()
    expectNoDifference(initialMembers, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func roomPresencePropertyWrapperRecordsMissingRoomError() async throws {
    let presence = RoomPresence()

    do {
      _ = try await presence.subscribe(using: roomClient())
      Issue.record("Expected @RoomPresence without a room to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "subscribe RoomPresence")
      expectNoDifference(presence.loadError?.operation, "subscribe RoomPresence")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(presence.wrappedValue, [])
    expectNoDifference(presence.isLoading, false)
  }

  @Test
  func roomPresencePropertyWrapperSubscribeCancellationAfterObserveDoesNotSucceed() async throws {
    let gate = AuthSessionLoadGate()
    let client = roomClient(
      observeRoomPresence: { _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )
    let presence = RoomPresence("chat", "lobby")

    let task = Task {
      let presence = presence
      _ = try await presence.subscribe(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @RoomPresence subscribe cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func roomPresencePropertyWrapperTaskCancellationAfterObserveCancelsReturnedSubscription()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let termination = RoomObservationTermination()
    let client = roomClient(
      observeRoomPresence: { room in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([mockRoomPresenceMember(room: room, userID: "user-1")])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )
    let presence = RoomPresence("chat", "lobby")

    let task = Task {
      let presence = presence
      try await presence.task(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @RoomPresence task cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }

    await termination.wait()
    expectNoDifference(presence.wrappedValue, [])
    expectNoDifference(presence.loadError, nil)
    expectNoDifference(presence.isLoading, false)
  }

  @Test
  func roomTopicMessagesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let client = roomClient(
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [message]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @RoomTopicMessages("chat", "lobby", "sendEmoji", limit: 1)
      var messages: [InstantRoomTopicMessage]

      try await $messages.load()

      expectNoDifference(messages, [message])
      expectNoDifference($messages.loadError, nil)
      expectNoDifference($messages.isLoading, false)
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperRecordsNegativeLimitErrors() async throws {
    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji", limit: -1)

    do {
      try await messages.load(using: roomClient())
      Issue.record("Expected @RoomTopicMessages negative load limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "load RoomTopicMessages")
      expectNoDifference(messages.loadError?.operation, "load RoomTopicMessages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(messages.wrappedValue, [])
    expectNoDifference(messages.isLoading, false)

    do {
      _ = try await messages.subscribe(
        "chat",
        "lobby",
        "sendEmoji",
        limit: -1,
        using: roomClient()
      )
      Issue.record("Expected @RoomTopicMessages negative subscribe limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe RoomTopicMessages")
      expectNoDifference(messages.loadError?.operation, "subscribe RoomTopicMessages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperTaskBindsObservedMessages() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let laterMessage = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([message, laterMessage])
          continuation.finish()
        }
      }
    )

    @RoomTopicMessages var messages: [InstantRoomTopicMessage]

    try await $messages.task("chat", "lobby", "sendEmoji", limit: 1, using: client)

    expectNoDifference(messages, [message])
    expectNoDifference($messages.loadError, nil)
    expectNoDifference($messages.isLoading, false)
  }

  @Test
  func roomTopicMessagesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji")
    let subscription = try await messages.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialMessages = try await iterator.next()
    expectNoDifference(initialMessages, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func roomTopicClientSubscriptionAdapterAppliesLimitAndValidatesInput() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let first = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let second = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([first, second])
          continuation.finish()
        }
      }
    )

    let subscription = try await client.subscribeRoomTopicMessages(
      room: room,
      topic: "sendEmoji",
      limit: 1
    )
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [first])

    do {
      _ = try await client.subscribeRoomTopicMessages(
        room: room,
        topic: "sendEmoji",
        limit: -1
      )
      Issue.record("Expected negative room topic subscription limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe room topic messages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperSubscribeCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = roomClient(
      observeRoomTopicMessages: { _, _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )
    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji")

    let task = Task {
      let messages = messages
      _ = try await messages.subscribe(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @RoomTopicMessages subscribe cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func projectedAdapterLifecycleAPIsWorkFromImmutableModels() async throws {
    let session = mockAuthSession(userID: "immutable-user")
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let firstMessage = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let laterMessage = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let authClient = authSessionClient(
      load: { session },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.yield(session)
          continuation.finish()
        }
      }
    )
    let roomsClient = roomClient(
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      },
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([member])
          continuation.finish()
        }
      },
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [firstMessage, laterMessage]
      },
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([firstMessage, laterMessage])
          continuation.finish()
        }
      }
    )
    let localIDRecorder = LocalIDRecorder()
    let localIDClient = localIDClient(localIDRecorder)
    let model = ImmutableProjectedAdapterLifecycleModel()

    try await model.exerciseAuth(using: authClient)
    try await model.exerciseRoom(room: room, topic: "sendEmoji", using: roomsClient)
    try await model.exerciseLocalID(using: localIDClient)

    expectNoDifference(model.session, session)
    expectNoDifference(model.members, [member])
    expectNoDifference(model.messages, [firstMessage])
    expectNoDifference(model.localID, "local-id-session")
    expectNoDifference(model.$session.loadError, nil)
    expectNoDifference(model.$members.loadError, nil)
    expectNoDifference(model.$messages.loadError, nil)
    expectNoDifference(model.$localID.loadError, nil)
    let resolvedNames = await localIDRecorder.recordedNames()
    expectNoDifference(resolvedNames, ["device", "session"])
  }

  @Test
  func fileAndStreamClientOperationsUseInjectedClosures() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/mock-file.txt")
    let file = mockStoredFile(id: "file-1", name: "mock-file.txt")
    let contents = InstantStoredFileContents(file: file, data: Data("hello".utf8))
    let progress = mockFileUploadProgress(file: file, state: .success)
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let client = integrationClient(
      uploadFile: { url, name, contentType in
        expectNoDifference(url, sourceURL)
        expectNoDifference(name, "renamed.txt")
        expectNoDifference(contentType, "text/plain")
        return file
      },
      uploadFileProgress: { url, name, contentType in
        expectNoDifference(url, sourceURL)
        expectNoDifference(name, "renamed.txt")
        expectNoDifference(contentType, "text/plain")
        return AsyncThrowingStream { continuation in
          continuation.yield(progress)
          continuation.finish()
        }
      },
      storedFiles: { [file] },
      observeStoredFiles: {
        AsyncStream { continuation in
          continuation.yield([file])
          continuation.finish()
        }
      },
      storedFileContents: { id in
        expectNoDifference(id, "file-1")
        return contents
      },
      deleteStoredFile: { id in
        expectNoDifference(id, "file-1")
        return file
      },
      appendStreamChunk: { streamID, payload in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(payload, .object(["text": .string("hello")]))
        return chunk
      },
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [chunk]
      },
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream { continuation in
          continuation.yield([chunk])
          continuation.finish()
        }
      }
    )

    let uploadedFile = try await client.uploadFile(
      from: sourceURL,
      name: "renamed.txt",
      contentType: "text/plain"
    )
    expectNoDifference(uploadedFile, file)
    var progressIterator = try await client.uploadFileProgress(
      from: sourceURL,
      name: "renamed.txt",
      contentType: "text/plain"
    )
    .makeAsyncIterator()
    let observedProgress = try await progressIterator.next()
    expectNoDifference(observedProgress, progress)
    let listedFiles = try await client.storedFiles()
    expectNoDifference(listedFiles, [file])
    var filesIterator = try await client.observeStoredFiles().makeAsyncIterator()
    let observedFiles = await filesIterator.next()
    expectNoDifference(observedFiles, [file])
    let storedContents = try await client.storedFileContents(id: "file-1")
    expectNoDifference(storedContents, contents)
    let deletedFile = try await client.deleteStoredFile(id: "file-1")
    expectNoDifference(deletedFile, file)
    let appendedChunk = try await client.appendStreamChunk(
      streamID: "chat/lobby",
      payload: .object(["text": .string("hello")])
    )
    expectNoDifference(appendedChunk, chunk)
    let listedChunks = try await client.streamChunks(streamID: "chat/lobby", limit: 1)
    expectNoDifference(listedChunks, [chunk])
    var chunksIterator = try await client.observeStreamChunks(streamID: "chat/lobby")
      .makeAsyncIterator()
    let observedChunks = await chunksIterator.next()
    expectNoDifference(observedChunks, [chunk])
  }

  @Test
  func streamClientCursorAwareInjectedClosuresReceiveAfterIndex() async throws {
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      streamChunksAfterIndex: { streamID, limit, afterIndex in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        expectNoDifference(afterIndex, 0)
        return [laterChunk]
      },
      observeStreamChunksAfterIndex: { streamID, afterIndex in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(afterIndex, 0)
        return AsyncStream { continuation in
          continuation.yield([laterChunk])
          continuation.finish()
        }
      }
    )

    let listedChunks = try await client.streamChunks(
      streamID: "chat/lobby",
      limit: 1,
      afterIndex: 0
    )
    expectNoDifference(listedChunks, [laterChunk])

    var iterator = try await client.observeStreamChunks(streamID: "chat/lobby", afterIndex: 0)
      .makeAsyncIterator()
    let observedChunks = await iterator.next()
    expectNoDifference(observedChunks, [laterChunk])
  }

  @Test
  func streamClientByteStreamInjectedClosuresReceiveOffsets() async throws {
    let metadata = mockStreamMetadata(id: "stream-1", clientID: "client-1")
    let chunk = mockStreamContentChunk(streamID: "stream-1", offset: 3, content: "🍕")
    let append = InstantStreamContentAppend(metadata: metadata, chunk: chunk, offset: chunk.offset)
    let read = mockStreamContentRead(metadata: metadata, byteOffset: 3, content: "🍕")
    let closed = mockStreamMetadata(
      id: "stream-1",
      clientID: "client-1",
      done: true,
      size: 7,
      abortReason: "done"
    )
    let client = integrationClient(
      createStream: { clientID in
        expectNoDifference(clientID, "client-1")
        return metadata
      },
      streamMetadataByStreamID: { streamID in
        expectNoDifference(streamID, "stream-1")
        return metadata
      },
      streamMetadataByClientID: { clientID in
        expectNoDifference(clientID, "client-1")
        return metadata
      },
      appendStreamContent: { streamID, content, expectedOffset in
        expectNoDifference(streamID, "stream-1")
        expectNoDifference(content, "🍕")
        expectNoDifference(expectedOffset, 3)
        return append
      },
      closeStream: { streamID, abortReason in
        expectNoDifference(streamID, "stream-1")
        expectNoDifference(abortReason, "done")
        return closed
      },
      streamContentByStreamID: { streamID, byteOffset in
        expectNoDifference(streamID, "stream-1")
        expectNoDifference(byteOffset, 3)
        return read
      },
      streamContentByClientID: { clientID, byteOffset in
        expectNoDifference(clientID, "client-1")
        expectNoDifference(byteOffset, 3)
        return read
      },
      observeStreamContentByStreamID: { streamID, byteOffset in
        expectNoDifference(streamID, "stream-1")
        expectNoDifference(byteOffset, 3)
        return AsyncStream { continuation in
          continuation.yield(read)
          continuation.finish()
        }
      },
      observeStreamContentByClientID: { clientID, byteOffset in
        expectNoDifference(clientID, "client-1")
        expectNoDifference(byteOffset, 3)
        return AsyncStream { continuation in
          continuation.yield(read)
          continuation.finish()
        }
      }
    )

    let created = try await client.createStream(clientID: "client-1")
    let streamMetadata = try await client.streamMetadata(streamID: "stream-1")
    let clientMetadata = try await client.streamMetadata(clientID: "client-1")
    let appended = try await client.appendStreamContent(
      streamID: "stream-1",
      content: "🍕",
      expectedOffset: 3
    )
    let closedStream = try await client.closeStream(streamID: "stream-1", abortReason: "done")
    let streamRead = try await client.streamContent(streamID: "stream-1", byteOffset: 3)
    let clientRead = try await client.streamContent(clientID: "client-1", byteOffset: 3)
    expectNoDifference(created, metadata)
    expectNoDifference(streamMetadata, metadata)
    expectNoDifference(clientMetadata, metadata)
    expectNoDifference(appended, append)
    expectNoDifference(closedStream, closed)
    expectNoDifference(streamRead, read)
    expectNoDifference(clientRead, read)

    var streamIDIterator = try await client.observeStreamContent(
      streamID: "stream-1",
      byteOffset: 3
    )
    .makeAsyncIterator()
    let observedByStreamID = await streamIDIterator.next()
    expectNoDifference(observedByStreamID, read)

    var clientIDIterator = try await client.observeStreamContent(
      clientID: "client-1",
      byteOffset: 3
    )
    .makeAsyncIterator()
    let observedByClientID = await clientIDIterator.next()
    expectNoDifference(observedByClientID, read)

    do {
      _ = try await client.streamContent(streamID: "stream-1", byteOffset: -1)
      Issue.record("Expected negative byte offset to fail before injected stream read closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "read stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try await client.appendStreamContent(
        streamID: "stream-1",
        content: "blocked",
        expectedOffset: -1
      )
      Issue.record("Expected negative expected offset to fail before injected stream append closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "append stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func storedFilesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let file = mockStoredFile(id: "file-1")
    let client = integrationClient(
      storedFiles: { [file] }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @StoredFiles var files: [InstantStoredFile]

      try await $files.load()

      expectNoDifference(files, [file])
      expectNoDifference($files.loadError, nil)
      expectNoDifference($files.isLoading, false)
    }
  }

  @Test
  func storedFilesPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = [mockStoredFile(id: "cached-file")]
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test StoredFiles",
      message: "files failed",
      recovery: "Retry with a working files client."
    )
    let client = integrationClient(
      storedFiles: { throw expectedError }
    )

    @StoredFiles var files: [InstantStoredFile] = cached

    do {
      try await $files.load(using: client)
      Issue.record("Expected @StoredFiles to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test StoredFiles")
      expectNoDifference($files.loadError?.operation, "load test StoredFiles")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(files, cached)
    expectNoDifference($files.isLoading, false)
  }

  @Test
  func storedFilesPropertyWrapperTaskBindsObservedFiles() async throws {
    let file = mockStoredFile(id: "file-1")
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([file])
          continuation.finish()
        }
      }
    )

    @StoredFiles var files: [InstantStoredFile]

    try await $files.task(using: client)

    expectNoDifference(files, [file])
    expectNoDifference($files.loadError, nil)
    expectNoDifference($files.isLoading, false)
  }

  @Test
  func storedFilesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let files = StoredFiles()
    let subscription = try await files.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialFiles = try await iterator.next()
    expectNoDifference(initialFiles, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func storedFilesClientSubscriptionAdapterCancelsUnderlyingObservation() async throws {
    let file = mockStoredFile(id: "file-1")
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([file])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let subscription = try await client.subscribeStoredFiles()
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [file])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func storedFilesClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeStoredFiles: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeStoredFiles()
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected stored files subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func streamChunksPropertyWrapperLoadsUsingDependencyClient() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [chunk]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @StreamChunks("chat/lobby", limit: 1) var chunks: [InstantStreamChunk]

      try await $chunks.load()

      expectNoDifference(chunks, [chunk])
      expectNoDifference($chunks.loadError, nil)
      expectNoDifference($chunks.isLoading, false)
    }

    let resumedClient = integrationClient(
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, nil)
        return [chunk, laterChunk]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = resumedClient
    } operation: {
      @StreamChunks("chat/lobby", limit: 1, afterIndex: chunk.index)
      var chunks: [InstantStreamChunk]

      try await $chunks.load()

      expectNoDifference(chunks, [laterChunk])
      expectNoDifference($chunks.loadError, nil)
      expectNoDifference($chunks.isLoading, false)
    }
  }

  @Test
  func streamChunksPropertyWrapperRecordsNegativeLimitErrors() async throws {
    let chunks = StreamChunks("chat/lobby", limit: -1)

    do {
      try await chunks.load(using: integrationClient())
      Issue.record("Expected @StreamChunks negative load limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "load StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "load StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(chunks.wrappedValue, [])
    expectNoDifference(chunks.isLoading, false)

    do {
      _ = try await chunks.subscribe("chat/lobby", limit: -1, using: integrationClient())
      Issue.record("Expected @StreamChunks negative subscribe limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "subscribe StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      try await chunks.load("chat/lobby", afterIndex: -1, using: integrationClient())
      Issue.record("Expected @StreamChunks negative load afterIndex to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "load StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "load StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try await chunks.subscribe("chat/lobby", afterIndex: -1, using: integrationClient())
      Issue.record("Expected @StreamChunks negative subscribe afterIndex to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "subscribe StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func streamChunksPropertyWrapperTaskBindsObservedChunks() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([chunk, laterChunk])
          continuation.finish()
        }
      }
    )

    @StreamChunks var chunks: [InstantStreamChunk]

    try await $chunks.task("chat/lobby", limit: 1, afterIndex: chunk.index, using: client)

    expectNoDifference(chunks, [laterChunk])
    expectNoDifference($chunks.loadError, nil)
    expectNoDifference($chunks.isLoading, false)
  }

  @Test
  func streamChunksPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([chunk, laterChunk])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let chunks = StreamChunks("chat/lobby", limit: 1)
    let subscription = try await chunks.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialChunks = try await iterator.next()
    expectNoDifference(initialChunks, [chunk])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func streamClientSubscriptionAdapterAppliesLimitAndValidatesInput() async throws {
    let first = mockStreamChunk(streamID: "chat/lobby")
    let second = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([first, second])
          continuation.finish()
        }
      }
    )

    let subscription = try await client.subscribeStreamChunks(
      streamID: "chat/lobby",
      limit: 1
    )
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [first])

    let resumedSubscription = try await client.subscribeStreamChunks(
      streamID: "chat/lobby",
      limit: 1,
      afterIndex: first.index
    )
    var resumedIterator = resumedSubscription.makeAsyncIterator()
    let resumedEmission = try await resumedIterator.next()
    expectNoDifference(resumedEmission, [second])

    do {
      _ = try await client.subscribeStreamChunks(streamID: "chat/lobby", limit: -1)
      Issue.record("Expected negative stream chunk subscription limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe stream chunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try await client.subscribeStreamChunks(streamID: "chat/lobby", afterIndex: -1)
      Issue.record("Expected negative stream chunk subscription cursor to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe stream chunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func streamClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeStreamChunks: { _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeStreamChunks(streamID: "chat/lobby")
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected stream chunk subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func shareClientOperationsUseInjectedClosures() async throws {
    let snapshot = mockShareSnapshot()
    let accepted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let promoted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .writer)]
    )
    let client = integrationClient(
      createShare: { namespace, id in
        expectNoDifference(namespace, "todos")
        expectNoDifference(id, "todo-1")
        return snapshot
      },
      acceptShare: { token in
        expectNoDifference(token, snapshot.share.token)
        return accepted
      },
      shares: { [accepted] },
      observeShares: {
        AsyncStream { continuation in
          continuation.yield([accepted])
          continuation.finish()
        }
      },
      updateShareMembershipRole: { shareID, userID, role in
        expectNoDifference(shareID, snapshot.share.id)
        expectNoDifference(userID, "user-2")
        expectNoDifference(role, .writer)
        return promoted
      },
      revokeShare: { id in
        expectNoDifference(id, snapshot.share.id)
        return snapshot
      }
    )

    let createdShare = try await client.createShare(rootNamespace: "todos", rootID: "todo-1")
    expectNoDifference(createdShare, snapshot)
    let acceptedShare = try await client.acceptShare(token: snapshot.share.token)
    expectNoDifference(acceptedShare, accepted)
    let listedShares = try await client.shares()
    expectNoDifference(listedShares, [accepted])
    var shareIterator = try await client.observeShares().makeAsyncIterator()
    let observedShares = await shareIterator.next()
    expectNoDifference(observedShares, [accepted])
    let promotedShare = try await client.updateShareMembershipRole(
      shareID: snapshot.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promotedShare, promoted)
    let revokedShare = try await client.revokeShare(id: snapshot.share.id)
    expectNoDifference(revokedShare, snapshot)
  }

  @Test
  func shareClientSubscriptionAdapterCancelsUnderlyingObservation() async throws {
    let snapshot = mockShareSnapshot()
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let subscription = try await client.subscribeShares()
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [snapshot])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func shareClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed() async throws {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeShares: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeShares()
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected share subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func sharesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let snapshot = mockShareSnapshot()
    let client = integrationClient(
      shares: { [snapshot] }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @Shares var shares: [InstantShareSnapshot]

      try await $shares.load()

      expectNoDifference(shares, [snapshot])
      expectNoDifference($shares.loadError, nil)
      expectNoDifference($shares.isLoading, false)
    }
  }

  @Test
  func sharesPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = [mockShareSnapshot(id: "cached-share")]
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test Shares",
      message: "shares failed",
      recovery: "Retry with a working shares client."
    )
    let client = integrationClient(
      shares: { throw expectedError }
    )

    @Shares var shares: [InstantShareSnapshot] = cached

    do {
      try await $shares.load(using: client)
      Issue.record("Expected @Shares to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test Shares")
      expectNoDifference($shares.loadError?.operation, "load test Shares")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(shares, cached)
    expectNoDifference($shares.isLoading, false)
  }

  @Test
  func sharesPropertyWrapperTaskBindsObservedShares() async throws {
    let snapshot = mockShareSnapshot()
    let accepted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.yield([accepted])
          continuation.finish()
        }
      }
    )

    @Shares var shares: [InstantShareSnapshot]

    try await $shares.task(using: client)

    expectNoDifference(shares, [accepted])
    expectNoDifference($shares.loadError, nil)
    expectNoDifference($shares.isLoading, false)
  }

  @Test
  func sharesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let snapshot = mockShareSnapshot()
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let shares = Shares()
    let subscription = try await shares.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialShares = try await iterator.next()
    expectNoDifference(initialShares, [snapshot])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func projectedStorageStreamShareLifecycleAPIsWorkFromImmutableModels() async throws {
    let file = mockStoredFile(id: "immutable-file")
    let firstChunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let share = mockShareSnapshot(id: "immutable-share")
    let acceptedShare = mockShareSnapshot(
      id: "immutable-share",
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let client = integrationClient(
      storedFiles: { [file] },
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([file])
          continuation.finish()
        }
      },
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [firstChunk]
      },
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([firstChunk, laterChunk])
          continuation.finish()
        }
      },
      shares: { [share] },
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([share])
          continuation.yield([acceptedShare])
          continuation.finish()
        }
      }
    )
    let model = ImmutableProjectedStorageStreamShareLifecycleModel()

    try await model.exercise(streamID: "chat/lobby", using: client)

    expectNoDifference(model.files, [file])
    expectNoDifference(model.chunks, [firstChunk])
    expectNoDifference(model.shares, [acceptedShare])
    expectNoDifference(model.$files.loadError, nil)
    expectNoDifference(model.$chunks.loadError, nil)
    expectNoDifference(model.$shares.loadError, nil)
  }

  #if canImport(SwiftUI)
    @Test
    func authRoomAndLocalIDWrappersExposeSwiftUIBindings() {
      let session = mockAuthSession(userID: "binding-user")
      let room = InstantRoomHandle(type: "chat", id: "bindings")
      let member = mockRoomPresenceMember(room: room, userID: "binding-member")
      let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")

      let auth = AuthSession()
      auth.binding.wrappedValue = session
      expectNoDifference(auth.wrappedValue, session)

      let status = ConnectionStatus()
      status.binding.wrappedValue = mockConnectionStatus(state: .authenticated, userID: "binding-user")
      expectNoDifference(status.wrappedValue.state, .authenticated)
      expectNoDifference(status.wrappedValue.userID, "binding-user")

      let presence = RoomPresence(room: room)
      presence.binding.wrappedValue = [member]
      expectNoDifference(presence.wrappedValue, [member])

      let messages = RoomTopicMessages(room: room, topic: "sendEmoji")
      messages.binding.wrappedValue = [message]
      expectNoDifference(messages.wrappedValue, [message])

      let localID = LocalID("device")
      localID.binding.wrappedValue = "local-id-device"
      expectNoDifference(localID.wrappedValue, "local-id-device")
    }

    @Test
    func storageStreamShareWrappersExposeSwiftUIBindings() {
      let file = mockStoredFile(id: "binding-file")
      let chunk = mockStreamChunk(streamID: "chat/bindings")
      let share = mockShareSnapshot(id: "binding-share")

      let files = StoredFiles()
      files.binding.wrappedValue = [file]
      expectNoDifference(files.wrappedValue, [file])

      let chunks = StreamChunks("chat/bindings")
      chunks.binding.wrappedValue = [chunk]
      expectNoDifference(chunks.wrappedValue, [chunk])

      let shares = Shares()
      shares.binding.wrappedValue = [share]
      expectNoDifference(shares.wrappedValue, [share])
    }
  #endif

  @Test
  func cliDefaultPersistenceURLHonorsHomeEnvironment() {
    let key = "INSTANT_SWIFT_DATA_HOME"
    let previous = getenv(key).map { String(cString: $0) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLIHome-\(UUID().uuidString)", isDirectory: true)

    #expect(setenv(key, directory.path, 1) == 0)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
    }

    let url = DependencyValues.defaultInstantSwiftDataPersistenceURL(
      appID: "ignored-for-cli",
      context: .cli
    )

    expectNoDifference(url.path, directory.appendingPathComponent("state.sqlite").path)
  }

  @Test
  func mockClientQueryOnceFallsBackToSnapshots() async throws {
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { plan in
        [
          InstantEntitySnapshot(
            id: "mock-todo",
            namespace: plan.namespace,
            values: [
              "text": .one(.string("Mock once"))
            ]
          )
        ]
      },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    let plan = InstantQueryPlan(id: "mock.once", namespace: TodoExample.namespace)
    let emission = try await mock.queryOnce(plan)
    expectNoDifference(emission.queryID, "mock.once")
    expectNoDifference(emission.sequence, 0)
    expectNoDifference(emission.values.map(\.id), ["mock-todo"])
    expectNoDifference(emission.pageInfo, nil)

    do {
      _ = try await mock.authSession()
      #expect(Bool(false), "Expected old-shape mock client auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.observeAuthSession()
      #expect(Bool(false), "Expected old-shape mock client auth observer to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.connectionStatus()
      #expect(Bool(false), "Expected old-shape mock client status to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.observeConnectionStatus()
      #expect(Bool(false), "Expected old-shape mock client status observer to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.connect()
      #expect(Bool(false), "Expected old-shape mock client connect to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.closeConnection()
      #expect(Bool(false), "Expected old-shape mock client close to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.signInWithIDToken(clientName: "google-ios", idToken: "token")
      #expect(Bool(false), "Expected old-shape mock client ID token auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.signInWithOAuth(code: "oauth-code")
      #expect(Bool(false), "Expected old-shape mock client OAuth auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.roomPresence(room: InstantRoomHandle(type: "chat", id: "lobby"))
      #expect(Bool(false), "Expected old-shape mock client rooms to fail without room closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData rooms")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.observeRoomPresence(room: InstantRoomHandle(type: "chat", id: "lobby"))
      #expect(Bool(false), "Expected old-shape mock client room observers to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData rooms")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.storedFiles()
      #expect(Bool(false), "Expected old-shape mock client files to fail without file closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData files")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.streamChunks(streamID: "chat/lobby")
      #expect(Bool(false), "Expected old-shape mock client streams to fail without stream closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData streams")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.shares()
      #expect(Bool(false), "Expected old-shape mock client shares to fail without share closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData shares")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }
}

private actor AuthTokenInvalidationRecorder {
  private var values: [InstantAuthTokenInvalidationRequest] = []

  func record(_ request: InstantAuthTokenInvalidationRequest) {
    values.append(request)
  }

  func requests() -> [InstantAuthTokenInvalidationRequest] {
    values
  }
}

private actor BootstrapMutationTransportRecorder {
  private var recordedRequests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    recordedRequests.append(request)
  }

  func requests() -> [InstantMutationTransportRequest] {
    recordedRequests
  }
}

private actor SignOutOptionsRecorder {
  private var recordedValues: [Bool] = []

  func record(_ invalidateToken: Bool) {
    recordedValues.append(invalidateToken)
  }

  func values() -> [Bool] {
    recordedValues
  }
}

private actor NonReactiveClientOperationRecorder {
  private var recordedEvents: [String] = []

  func record(_ event: String) {
    recordedEvents.append(event)
  }

  func events() -> [String] {
    recordedEvents
  }
}

private actor AuthSessionTermination {
  private var didTerminate = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func record() {
    didTerminate = true
    for continuation in continuations {
      continuation.resume()
    }
    continuations.removeAll()
  }

  func wait() async {
    if didTerminate { return }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

private actor AuthSessionLoadGate {
  private var didStart = false
  private var didRelease = false
  private var startContinuations: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

  func recordStarted() {
    didStart = true
    for continuation in startContinuations {
      continuation.resume()
    }
    startContinuations.removeAll()
  }

  func waitUntilStarted() async {
    if didStart { return }
    await withCheckedContinuation { continuation in
      startContinuations.append(continuation)
    }
  }

  func release() {
    didRelease = true
    for continuation in releaseContinuations {
      continuation.resume()
    }
    releaseContinuations.removeAll()
  }

  func waitUntilReleased() async {
    if didRelease { return }
    await withCheckedContinuation { continuation in
      releaseContinuations.append(continuation)
    }
  }
}

private actor RoomObservationTermination {
  private var didTerminate = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func record() {
    didTerminate = true
    for continuation in continuations {
      continuation.resume()
    }
    continuations.removeAll()
  }

  func wait() async {
    if didTerminate { return }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

private actor RoomLifecycleRecorder {
  private var recordedEvents: [String] = []

  func record(_ event: String) {
    recordedEvents.append(event)
  }

  func events() -> [String] {
    recordedEvents
  }
}

private actor LocalIDRecorder {
  private var names: [String] = []

  func resolve(_ name: String) -> String {
    names.append(name)
    return "local-id-\(name)"
  }

  func recordedNames() -> [String] {
    names
  }
}

private struct ImmutableProjectedAdapterLifecycleModel {
  @AuthSession var session: InstantAuthSession?
  @RoomPresence var members: [InstantRoomPresenceMember]
  @RoomTopicMessages var messages: [InstantRoomTopicMessage]
  @LocalID var localID: String?

  func exerciseAuth(using client: InstantSwiftDataClient) async throws {
    try await $session.load(using: client)
    let subscription = try await $session.subscribe(using: client)
    subscription.cancel()
    try await $session.task(using: client)
  }

  func exerciseRoom(
    room: InstantRoomHandle,
    topic: String,
    using client: InstantSwiftDataClient
  ) async throws {
    try await $members.load(room: room, using: client)
    let membersSubscription = try await $members.subscribe(room: room, using: client)
    membersSubscription.cancel()
    try await $members.task(room: room, using: client)

    try await $messages.load(room: room, topic: topic, limit: 1, using: client)
    let messagesSubscription = try await $messages.subscribe(
      room: room,
      topic: topic,
      limit: 1,
      using: client
    )
    messagesSubscription.cancel()
    try await $messages.task(room: room, topic: topic, limit: 1, using: client)
  }

  func exerciseLocalID(using client: InstantSwiftDataClient) async throws {
    try await $localID.load("device", using: client)
    try await $localID.task("session", using: client)
  }
}

private struct ImmutableProjectedStorageStreamShareLifecycleModel {
  @StoredFiles var files: [InstantStoredFile]
  @StreamChunks var chunks: [InstantStreamChunk]
  @Shares var shares: [InstantShareSnapshot]

  func exercise(streamID: String, using client: InstantSwiftDataClient) async throws {
    try await $files.load(using: client)
    let filesSubscription = try await $files.subscribe(using: client)
    filesSubscription.cancel()
    try await $files.task(using: client)

    try await $chunks.load(streamID, limit: 1, using: client)
    let chunksSubscription = try await $chunks.subscribe(streamID, limit: 1, using: client)
    chunksSubscription.cancel()
    try await $chunks.task(streamID, limit: 1, using: client)

    try await $shares.load(using: client)
    let sharesSubscription = try await $shares.subscribe(using: client)
    sharesSubscription.cancel()
    try await $shares.task(using: client)
  }
}

private func mockAuthSession(userID: String, isGuest: Bool = false) -> InstantAuthSession {
  InstantAuthSession(
    appID: "mock-app",
    userID: userID,
    refreshToken: isGuest ? nil : "mock-refresh-\(userID)",
    isGuest: isGuest,
    createdAt: InstantTimestamp(milliseconds: 1),
    updatedAt: InstantTimestamp(milliseconds: 2)
  )
}

private func mockConnectionStatus(
  state: InstantConnectionState,
  userID: String? = nil
) -> InstantConnectionStatus {
  InstantConnectionStatus(
    appID: "mock-app",
    apiURI: InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
    transport: .localCacheOnly,
    state: state,
    isAuthenticated: userID != nil,
    userID: userID,
    pendingMutationCount: 0,
    processedTransactionID: nil
  )
}

private func mockRoomPresenceMember(
  room: InstantRoomHandle,
  userID: String,
  values: [String: JSONValue] = ["status": .string("online")]
) -> InstantRoomPresenceMember {
  InstantRoomPresenceMember(
    appID: "mock-app",
    room: room,
    userID: userID,
    values: values,
    updatedAt: InstantTimestamp(milliseconds: 3)
  )
}

private func mockRoomTopicMessage(
  room: InstantRoomHandle,
  topic: String,
  id: String = "message-1",
  payload: JSONValue = .object(["emoji": .string("wave")])
) -> InstantRoomTopicMessage {
  InstantRoomTopicMessage(
    id: id,
    appID: "mock-app",
    room: room,
    topic: topic,
    userID: "user-1",
    payload: payload,
    createdAt: InstantTimestamp(milliseconds: 4)
  )
}

private func mockStoredFile(
  id: String,
  name: String = "mock-file.txt",
  contentType: String? = "text/plain"
) -> InstantStoredFile {
  InstantStoredFile(
    id: id,
    appID: "mock-app",
    name: name,
    contentType: contentType,
    byteCount: 5,
    localPath: "/tmp/\(name)",
    ownerUserID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 5),
    updatedAt: InstantTimestamp(milliseconds: 6)
  )
}

private func mockFileUploadProgress(
  file: InstantStoredFile,
  state: InstantStorageOperationState
) -> InstantFileUploadProgress {
  InstantFileUploadProgress(
    operationID: file.id,
    appID: file.appID,
    fileID: file.id,
    fileName: file.name,
    contentType: file.contentType,
    state: state,
    completedByteCount: file.byteCount,
    totalByteCount: file.byteCount,
    progress: state == .success ? 1 : 0,
    file: state == .success ? file : nil,
    updatedAt: InstantTimestamp(milliseconds: 7)
  )
}

private func mockStreamChunk(
  id: String = "chunk-1",
  streamID: String,
  index: Int64 = 0,
  payload: JSONValue = .object(["text": .string("hello")])
) -> InstantStreamChunk {
  InstantStreamChunk(
    id: id,
    appID: "mock-app",
    streamID: streamID,
    index: index,
    payload: payload,
    userID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 8 + index)
  )
}

private func mockStreamMetadata(
  id: String = "stream-1",
  clientID: String = "client-1",
  done: Bool = false,
  size: Int64? = nil,
  abortReason: String? = nil
) -> InstantStreamMetadata {
  InstantStreamMetadata(
    id: id,
    appID: "mock-app",
    clientID: clientID,
    done: done,
    size: size,
    abortReason: abortReason,
    userID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 9),
    updatedAt: InstantTimestamp(milliseconds: 10)
  )
}

private func mockStreamContentChunk(
  id: String = "content-chunk-1",
  streamID: String = "stream-1",
  offset: Int64 = 0,
  content: String = "hello"
) -> InstantStreamContentChunk {
  InstantStreamContentChunk(
    id: id,
    appID: "mock-app",
    streamID: streamID,
    offset: offset,
    byteCount: Int64(content.utf8.count),
    content: content,
    userID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 11)
  )
}

private func mockStreamContentRead(
  metadata: InstantStreamMetadata = mockStreamMetadata(),
  byteOffset: Int64 = 0,
  content: String = "hello"
) -> InstantStreamContentRead {
  InstantStreamContentRead(
    metadata: metadata,
    byteOffset: byteOffset,
    byteCount: Int64(content.utf8.count),
    content: content,
    done: metadata.done,
    abortReason: metadata.abortReason
  )
}

private func mockShareSnapshot(
  id: String = "share-1",
  rootNamespace: String = "todos",
  rootID: String = "todo-1",
  ownerUserID: String = "user-1",
  memberships: [(userID: String, role: InstantShareRole)] = [("user-1", .owner)]
) -> InstantShareSnapshot {
  InstantShareSnapshot(
    share: InstantShare(
      id: id,
      appID: "mock-app",
      rootNamespace: rootNamespace,
      rootID: rootID,
      ownerUserID: ownerUserID,
      token: "token-\(id)",
      createdAt: InstantTimestamp(milliseconds: 9),
      updatedAt: InstantTimestamp(milliseconds: 10)
    ),
    memberships: memberships.map { membership in
      InstantShareMembership(
        appID: "mock-app",
        shareID: id,
        userID: membership.userID,
        role: membership.role,
        acceptedAt: InstantTimestamp(milliseconds: 11)
      )
    }
  )
}

private func authSessionClient(
  load: @escaping @Sendable () async throws -> InstantAuthSession?,
  observe: @escaping @Sendable () async throws -> AsyncStream<InstantAuthSession?>
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: transaction.operations.count,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    authSession: load,
    observeAuthSession: observe
  )
}

private func connectionStatusClient(
  load: @escaping @Sendable () async throws -> InstantConnectionStatus,
  observe: @escaping @Sendable () async throws -> AsyncStream<InstantConnectionStatus>
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: transaction.operations.count,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    connectionStatus: load,
    observeConnectionStatus: observe,
    localID: { name in "mock-\(name)" }
  )
}

private func localIDClient(_ recorder: LocalIDRecorder) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: transaction.operations.count,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in
      await recorder.resolve(name)
    }
  )
}

private func roomClient(
  joinRoom: @escaping @Sendable (InstantRoomHandle) async throws -> InstantRoomHandle = { $0 },
  leaveRoom: @escaping @Sendable (InstantRoomHandle) async throws -> InstantRoomHandle = { $0 },
  setPresence: @escaping @Sendable (
    InstantRoomHandle,
    String?,
    [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember = { room, userID, values in
    mockRoomPresenceMember(room: room, userID: userID ?? "mock-user", values: values)
  },
  roomPresence: @escaping @Sendable (InstantRoomHandle) async throws
    -> [InstantRoomPresenceMember] = { _ in [] },
  observeRoomPresence: @escaping @Sendable (InstantRoomHandle) async throws
    -> AsyncStream<[InstantRoomPresenceMember]> = { _ in
      AsyncStream { continuation in continuation.finish() }
    },
  leavePresence: @escaping @Sendable (InstantRoomHandle, String?) async throws
    -> String = { _, userID in userID ?? "mock-user" },
  publishTopicMessage: @escaping @Sendable (
    InstantRoomHandle,
    String,
    String?,
    JSONValue
  ) async throws -> InstantRoomTopicMessage = { room, topic, _, payload in
    mockRoomTopicMessage(room: room, topic: topic, payload: payload)
  },
  roomTopicMessages: @escaping @Sendable (InstantRoomHandle, String, Int?) async throws
    -> [InstantRoomTopicMessage] = { _, _, _ in [] },
  observeRoomTopicMessages: @escaping @Sendable (InstantRoomHandle, String) async throws
    -> AsyncStream<[InstantRoomTopicMessage]> = { _, _ in
      AsyncStream { continuation in continuation.finish() }
    }
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: transaction.operations.count,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    joinRoom: joinRoom,
    leaveRoom: leaveRoom,
    setRoomPresence: setPresence,
    roomPresence: roomPresence,
    observeRoomPresence: observeRoomPresence,
    leaveRoomPresence: leavePresence,
    publishRoomTopicMessage: publishTopicMessage,
    roomTopicMessages: roomTopicMessages,
    observeRoomTopicMessages: observeRoomTopicMessages
  )
}

private func integrationClient(
  uploadFile: @escaping @Sendable (URL, String?, String?) async throws
    -> InstantStoredFile = { _, name, contentType in
      mockStoredFile(id: "mock-file", name: name ?? "mock-file.txt", contentType: contentType)
    },
  uploadFileProgress: @escaping @Sendable (URL, String?, String?) async throws
    -> AsyncThrowingStream<InstantFileUploadProgress, Error> = { _, name, contentType in
      let file = mockStoredFile(
        id: "mock-file",
        name: name ?? "mock-file.txt",
        contentType: contentType
      )
      return AsyncThrowingStream { continuation in
        continuation.yield(mockFileUploadProgress(file: file, state: .success))
        continuation.finish()
      }
    },
  storedFiles: @escaping @Sendable () async throws -> [InstantStoredFile] = { [] },
  observeStoredFiles: @escaping @Sendable () async throws
    -> AsyncStream<[InstantStoredFile]> = {
      AsyncStream { continuation in continuation.finish() }
    },
  storedFileContents: @escaping @Sendable (String) async throws
    -> InstantStoredFileContents = { id in
      let file = mockStoredFile(id: id)
      return InstantStoredFileContents(file: file, data: Data())
    },
  deleteStoredFile: @escaping @Sendable (String) async throws -> InstantStoredFile = { id in
    mockStoredFile(id: id)
  },
  appendStreamChunk: @escaping @Sendable (String, JSONValue) async throws
    -> InstantStreamChunk = { streamID, payload in
      mockStreamChunk(streamID: streamID, payload: payload)
    },
  streamChunks: @escaping @Sendable (String, Int?) async throws
    -> [InstantStreamChunk] = { _, _ in [] },
  observeStreamChunks: @escaping @Sendable (String) async throws
    -> AsyncStream<[InstantStreamChunk]> = { _ in
      AsyncStream { continuation in continuation.finish() }
    },
  streamChunksAfterIndex:
    (@Sendable (String, Int?, Int64?) async throws -> [InstantStreamChunk])? = nil,
  observeStreamChunksAfterIndex:
    (@Sendable (String, Int64?) async throws -> AsyncStream<[InstantStreamChunk]>)? = nil,
  createStream: @escaping @Sendable (String) async throws -> InstantStreamMetadata = { clientID in
    mockStreamMetadata(clientID: clientID)
  },
  streamMetadataByStreamID: @escaping @Sendable (String) async throws
    -> InstantStreamMetadata = { streamID in
      mockStreamMetadata(id: streamID)
    },
  streamMetadataByClientID: @escaping @Sendable (String) async throws
    -> InstantStreamMetadata = { clientID in
      mockStreamMetadata(clientID: clientID)
    },
  appendStreamContent: @escaping @Sendable (String, String, Int64?) async throws
    -> InstantStreamContentAppend = { streamID, content, expectedOffset in
      let chunk = mockStreamContentChunk(
        streamID: streamID,
        offset: expectedOffset ?? 0,
        content: content
      )
      return InstantStreamContentAppend(
        metadata: mockStreamMetadata(id: streamID),
        chunk: chunk,
        offset: chunk.offset
      )
    },
  closeStream: @escaping @Sendable (String, String?) async throws
    -> InstantStreamMetadata = { streamID, abortReason in
      mockStreamMetadata(id: streamID, done: true, size: 0, abortReason: abortReason)
    },
  streamContentByStreamID: @escaping @Sendable (String, Int64) async throws
    -> InstantStreamContentRead = { streamID, byteOffset in
      mockStreamContentRead(metadata: mockStreamMetadata(id: streamID), byteOffset: byteOffset)
    },
  streamContentByClientID: @escaping @Sendable (String, Int64) async throws
    -> InstantStreamContentRead = { clientID, byteOffset in
      mockStreamContentRead(metadata: mockStreamMetadata(clientID: clientID), byteOffset: byteOffset)
    },
  observeStreamContentByStreamID: @escaping @Sendable (String, Int64) async throws
    -> AsyncStream<InstantStreamContentRead> = { streamID, byteOffset in
      AsyncStream { continuation in
        continuation.yield(
          mockStreamContentRead(metadata: mockStreamMetadata(id: streamID), byteOffset: byteOffset)
        )
        continuation.finish()
      }
    },
  observeStreamContentByClientID: @escaping @Sendable (String, Int64) async throws
    -> AsyncStream<InstantStreamContentRead> = { clientID, byteOffset in
      AsyncStream { continuation in
        continuation.yield(
          mockStreamContentRead(metadata: mockStreamMetadata(clientID: clientID), byteOffset: byteOffset)
        )
        continuation.finish()
      }
    },
  createShare: @escaping @Sendable (String, String) async throws
    -> InstantShareSnapshot = { namespace, id in
      mockShareSnapshot(rootNamespace: namespace, rootID: id)
    },
  acceptShare: @escaping @Sendable (String) async throws -> InstantShareSnapshot = { token in
    mockShareSnapshot(id: token)
  },
  shares: @escaping @Sendable () async throws -> [InstantShareSnapshot] = { [] },
  observeShares: @escaping @Sendable () async throws
    -> AsyncStream<[InstantShareSnapshot]> = {
      AsyncStream { continuation in continuation.finish() }
    },
  updateShareMembershipRole: @escaping @Sendable (
    String,
    String,
    InstantShareRole
  ) async throws -> InstantShareSnapshot = { shareID, userID, role in
    mockShareSnapshot(
      id: shareID,
      memberships: [("user-1", .owner), (userID, role)]
    )
  },
  revokeShare: @escaping @Sendable (String) async throws -> InstantShareSnapshot = { id in
    mockShareSnapshot(id: id)
  }
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: transaction.operations.count,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    uploadFile: uploadFile,
    uploadFileProgress: uploadFileProgress,
    storedFiles: storedFiles,
    observeStoredFiles: observeStoredFiles,
    storedFileContents: storedFileContents,
    deleteStoredFile: deleteStoredFile,
    appendStreamChunk: appendStreamChunk,
    streamChunks: streamChunks,
    observeStreamChunks: observeStreamChunks,
    streamChunksAfterIndex: streamChunksAfterIndex,
    observeStreamChunksAfterIndex: observeStreamChunksAfterIndex,
    createStream: createStream,
    streamMetadataByStreamID: streamMetadataByStreamID,
    streamMetadataByClientID: streamMetadataByClientID,
    appendStreamContent: appendStreamContent,
    closeStream: closeStream,
    streamContentByStreamID: streamContentByStreamID,
    streamContentByClientID: streamContentByClientID,
    observeStreamContentByStreamID: observeStreamContentByStreamID,
    observeStreamContentByClientID: observeStreamContentByClientID,
    createShare: createShare,
    acceptShare: acceptShare,
    shares: shares,
    observeShares: observeShares,
    updateShareMembershipRole: updateShareMembershipRole,
    revokeShare: revokeShare
  )
}

private func waitForBootstrapCondition(
  operation: String,
  until condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<100 {
    if await condition() {
      return
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  throw InstantError(
    code: .validationFailed,
    operation: operation,
    message: "Timed out waiting for bootstrap test condition.",
    recovery: "Inspect the controlled test client, subscription lifecycle, and wrapper state."
  )
}

private actor BootstrapSyncUpSoundEffectRecorder {
  private var loaded: [String] = []
  private var plays = 0

  func load(_ fileName: String) {
    loaded.append(fileName)
  }

  func play() {
    plays += 1
  }

  func loadedFileNames() -> [String] {
    loaded
  }

  func playCount() -> Int {
    plays
  }
}

private actor BootstrapSyncUpOpenSettingsRecorder {
  private var count = 0

  func open() {
    count += 1
  }

  func openCount() -> Int {
    count
  }
}

private final class DraftValidationIDGenerator: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: [String]

  init(_ ids: [String]) {
    self.ids = ids
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    return ids.isEmpty ? UUID().uuidString.lowercased() : ids.removeFirst()
  }
}
