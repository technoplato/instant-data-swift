@_exported public import InstantSwiftDataCore
import Dependencies
import Foundation
import IssueReporting

#if canImport(SwiftUI)
  public import SwiftUI
#endif

@attached(member, names: named(instantNamespace), named(instantAttributes), named(Draft), arbitrary)
public macro InstantEntity(_ namespace: String? = nil) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantEntityMacro")

@attached(peer)
public macro InstantRelation(reverse: String) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantRelationMacro")

public struct InstantSwiftDataClient: Sendable {
  public let runtime: InstantRuntime?

  private var transactOperation:
    @Sendable (InstantStoreTransaction) async throws -> InstantStoreMutationResult
  private var queryOnceOperation:
    @Sendable (InstantQueryPlan) async throws -> InstantQueryEmission
  private var queryOperation: @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot]
  private var observeOperation: @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>
  private var pendingMutationsOperation: @Sendable () async -> [PendingMutation]
  private var flushPendingMutationsOperation:
    @Sendable (Int?) async throws -> InstantMutationTransportFlushResult
  private var connectionStatusOperation: @Sendable () async throws -> InstantConnectionStatus
  private var connectOperation: @Sendable () async throws -> InstantConnectionStatus
  private var closeConnectionOperation: @Sendable () async throws -> InstantConnectionStatus
  private var localIDOperation: @Sendable (String) async throws -> String
  private var authSessionOperation: @Sendable () async throws -> InstantAuthSession?
  private var observeAuthSessionOperation:
    @Sendable () async throws -> AsyncStream<InstantAuthSession?>
  private var signInAsGuestOperation: @Sendable () async throws -> InstantAuthSession
  private var sendMagicCodeOperation: @Sendable (String) async throws -> InstantMagicCodeChallenge
  private var signInWithMagicCodeOperation:
    @Sendable (String, String) async throws -> InstantAuthSession
  private var signInWithRefreshTokenOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var signInWithIDTokenOperation:
    @Sendable (String, String, String?) async throws -> InstantAuthSession
  private var signInWithOAuthOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var oauthAuthorizationURLOperation: @Sendable (String, URL) throws -> URL
  private var issuerURIOperation: @Sendable () throws -> URL
  private var signOutOperation: @Sendable (Bool) async throws -> Void
  private var setRoomPresenceOperation:
    @Sendable (InstantRoomHandle, String?, [String: JSONValue]) async throws
      -> InstantRoomPresenceMember
  private var roomPresenceOperation:
    @Sendable (InstantRoomHandle) async throws -> [InstantRoomPresenceMember]
  private var observeRoomPresenceOperation:
    @Sendable (InstantRoomHandle) async throws -> AsyncStream<[InstantRoomPresenceMember]>
  private var leaveRoomPresenceOperation:
    @Sendable (InstantRoomHandle, String?) async throws -> String
  private var publishRoomTopicMessageOperation:
    @Sendable (InstantRoomHandle, String, String?, JSONValue) async throws
      -> InstantRoomTopicMessage
  private var roomTopicMessagesOperation:
    @Sendable (InstantRoomHandle, String, Int?) async throws -> [InstantRoomTopicMessage]
  private var observeRoomTopicMessagesOperation:
    @Sendable (InstantRoomHandle, String) async throws -> AsyncStream<[InstantRoomTopicMessage]>
  private var uploadFileOperation:
    @Sendable (URL, String?, String?) async throws -> InstantStoredFile
  private var uploadFileProgressOperation:
    @Sendable (URL, String?, String?) async throws
      -> AsyncThrowingStream<InstantFileUploadProgress, Error>
  private var storedFilesOperation: @Sendable () async throws -> [InstantStoredFile]
  private var observeStoredFilesOperation:
    @Sendable () async throws -> AsyncStream<[InstantStoredFile]>
  private var storedFileContentsOperation:
    @Sendable (String) async throws -> InstantStoredFileContents
  private var deleteStoredFileOperation:
    @Sendable (String) async throws -> InstantStoredFile
  private var appendStreamChunkOperation:
    @Sendable (String, JSONValue) async throws -> InstantStreamChunk
  private var streamChunksOperation:
    @Sendable (String, Int?) async throws -> [InstantStreamChunk]
  private var observeStreamChunksOperation:
    @Sendable (String) async throws -> AsyncStream<[InstantStreamChunk]>
  private var createShareOperation:
    @Sendable (String, String) async throws -> InstantShareSnapshot
  private var acceptShareOperation: @Sendable (String) async throws -> InstantShareSnapshot
  private var sharesOperation: @Sendable () async throws -> [InstantShareSnapshot]
  private var observeSharesOperation:
    @Sendable () async throws -> AsyncStream<[InstantShareSnapshot]>
  private var updateShareMembershipRoleOperation:
    @Sendable (String, String, InstantShareRole) async throws -> InstantShareSnapshot
  private var revokeShareOperation: @Sendable (String) async throws -> InstantShareSnapshot

  public init(runtime: InstantRuntime) {
    self.runtime = runtime
    self.transactOperation = { transaction in
      try await runtime.transact(transaction)
    }
    self.queryOnceOperation = { plan in
      try await runtime.queryOnce(plan)
    }
    self.queryOperation = { plan in
      try await runtime.query(plan)
    }
    self.observeOperation = { plan in
      await runtime.observe(plan)
    }
    self.pendingMutationsOperation = {
      await runtime.pendingMutations()
    }
    self.flushPendingMutationsOperation = { limit in
      try await runtime.flushPendingMutations(limit: limit)
    }
    self.connectionStatusOperation = {
      try await runtime.connectionStatus()
    }
    self.connectOperation = {
      try await runtime.connect()
    }
    self.closeConnectionOperation = {
      try await runtime.closeConnection()
    }
    self.localIDOperation = { name in
      try await runtime.localID(named: name)
    }
    self.authSessionOperation = {
      try await runtime.authSession()
    }
    self.observeAuthSessionOperation = {
      try await runtime.observeAuthSession()
    }
    self.signInAsGuestOperation = {
      try await runtime.signInAsGuest()
    }
    self.sendMagicCodeOperation = { email in
      try await runtime.sendMagicCode(email: email)
    }
    self.signInWithMagicCodeOperation = { email, code in
      try await runtime.signInWithMagicCode(email: email, code: code)
    }
    self.signInWithRefreshTokenOperation = { refreshToken, userID in
      try await runtime.signInWithRefreshToken(refreshToken, userID: userID)
    }
    self.signInWithIDTokenOperation = { clientName, idToken, nonce in
      try await runtime.signInWithIDToken(
        clientName: clientName,
        idToken: idToken,
        nonce: nonce
      )
    }
    self.signInWithOAuthOperation = { code, codeVerifier in
      try await runtime.signInWithOAuth(code: code, codeVerifier: codeVerifier)
    }
    self.oauthAuthorizationURLOperation = { clientName, redirectURL in
      try runtime.oauthAuthorizationURL(clientName: clientName, redirectURL: redirectURL)
    }
    self.issuerURIOperation = {
      try runtime.issuerURI()
    }
    self.signOutOperation = { invalidateToken in
      try await runtime.signOut(invalidateToken: invalidateToken)
    }
    self.setRoomPresenceOperation = { room, userID, values in
      try await runtime.setPresence(room: room, userID: userID, values: values)
    }
    self.roomPresenceOperation = { room in
      try await runtime.roomPresence(room: room)
    }
    self.observeRoomPresenceOperation = { room in
      try await runtime.observeRoomPresence(room: room)
    }
    self.leaveRoomPresenceOperation = { room, userID in
      try await runtime.leavePresence(room: room, userID: userID)
    }
    self.publishRoomTopicMessageOperation = { room, topic, userID, payload in
      try await runtime.publishTopicMessage(
        room: room,
        topic: topic,
        userID: userID,
        payload: payload
      )
    }
    self.roomTopicMessagesOperation = { room, topic, limit in
      try await runtime.roomTopicMessages(room: room, topic: topic, limit: limit)
    }
    self.observeRoomTopicMessagesOperation = { room, topic in
      try await runtime.observeRoomTopicMessages(room: room, topic: topic)
    }
    self.uploadFileOperation = { sourceURL, name, contentType in
      try await runtime.uploadFile(from: sourceURL, name: name, contentType: contentType)
    }
    self.uploadFileProgressOperation = { sourceURL, name, contentType in
      try await runtime.uploadFileProgress(from: sourceURL, name: name, contentType: contentType)
    }
    self.storedFilesOperation = {
      try await runtime.storedFiles()
    }
    self.observeStoredFilesOperation = {
      try await runtime.observeStoredFiles()
    }
    self.storedFileContentsOperation = { id in
      try await runtime.storedFileContents(id: id)
    }
    self.deleteStoredFileOperation = { id in
      try await runtime.deleteStoredFile(id: id)
    }
    self.appendStreamChunkOperation = { streamID, payload in
      try await runtime.appendStreamChunk(streamID: streamID, payload: payload)
    }
    self.streamChunksOperation = { streamID, limit in
      try await runtime.streamChunks(streamID: streamID, limit: limit)
    }
    self.observeStreamChunksOperation = { streamID in
      try await runtime.observeStreamChunks(streamID: streamID)
    }
    self.createShareOperation = { rootNamespace, rootID in
      try await runtime.createShare(rootNamespace: rootNamespace, rootID: rootID)
    }
    self.acceptShareOperation = { token in
      try await runtime.acceptShare(token: token)
    }
    self.sharesOperation = {
      try await runtime.shares()
    }
    self.observeSharesOperation = {
      try await runtime.observeShares()
    }
    self.updateShareMembershipRoleOperation = { shareID, userID, role in
      try await runtime.updateShareMembershipRole(shareID: shareID, userID: userID, role: role)
    }
    self.revokeShareOperation = { id in
      try await runtime.revokeShare(id: id)
    }
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil,
    setRoomPresence:
      (@Sendable (InstantRoomHandle, String?, [String: JSONValue]) async throws
        -> InstantRoomPresenceMember)? = nil,
    roomPresence:
      (@Sendable (InstantRoomHandle) async throws -> [InstantRoomPresenceMember])? = nil,
    observeRoomPresence:
      (@Sendable (InstantRoomHandle) async throws -> AsyncStream<[InstantRoomPresenceMember]>)? =
        nil,
    leaveRoomPresence: (@Sendable (InstantRoomHandle, String?) async throws -> String)? = nil,
    publishRoomTopicMessage:
      (@Sendable (InstantRoomHandle, String, String?, JSONValue) async throws
        -> InstantRoomTopicMessage)? = nil,
    roomTopicMessages:
      (@Sendable (InstantRoomHandle, String, Int?) async throws
        -> [InstantRoomTopicMessage])? = nil,
    observeRoomTopicMessages:
      (@Sendable (InstantRoomHandle, String) async throws
        -> AsyncStream<[InstantRoomTopicMessage]>)? = nil,
    uploadFile:
      (@Sendable (URL, String?, String?) async throws -> InstantStoredFile)? = nil,
    uploadFileProgress:
      (@Sendable (URL, String?, String?) async throws
        -> AsyncThrowingStream<InstantFileUploadProgress, Error>)? = nil,
    storedFiles: (@Sendable () async throws -> [InstantStoredFile])? = nil,
    observeStoredFiles:
      (@Sendable () async throws -> AsyncStream<[InstantStoredFile]>)? = nil,
    storedFileContents:
      (@Sendable (String) async throws -> InstantStoredFileContents)? = nil,
    deleteStoredFile:
      (@Sendable (String) async throws -> InstantStoredFile)? = nil,
    appendStreamChunk:
      (@Sendable (String, JSONValue) async throws -> InstantStreamChunk)? = nil,
    streamChunks:
      (@Sendable (String, Int?) async throws -> [InstantStreamChunk])? = nil,
    observeStreamChunks:
      (@Sendable (String) async throws -> AsyncStream<[InstantStreamChunk]>)? = nil,
    createShare:
      (@Sendable (String, String) async throws -> InstantShareSnapshot)? = nil,
    acceptShare:
      (@Sendable (String) async throws -> InstantShareSnapshot)? = nil,
    shares:
      (@Sendable () async throws -> [InstantShareSnapshot])? = nil,
    observeShares:
      (@Sendable () async throws -> AsyncStream<[InstantShareSnapshot]>)? = nil,
    updateShareMembershipRole:
      (@Sendable (String, String, InstantShareRole) async throws -> InstantShareSnapshot)? = nil,
    revokeShare:
      (@Sendable (String) async throws -> InstantShareSnapshot)? = nil
  ) {
    self.init(
      transact: transact,
      queryOnce: queryOnce,
      query: query,
      observe: observe,
      pendingMutations: pendingMutations,
      flushPendingMutations: flushPendingMutations,
      connectionStatus: connectionStatus,
      connect: connect,
      closeConnection: closeConnection,
      localID: localID,
      authSession: authSession,
      observeAuthSession: observeAuthSession,
      signInAsGuest: signInAsGuest,
      sendMagicCode: sendMagicCode,
      signInWithMagicCode: signInWithMagicCode,
      signInWithRefreshToken: signInWithRefreshToken,
      oauthAuthorizationURL: nil,
      issuerURI: nil,
      signOut: signOut,
      signInWithIDToken: signInWithIDToken,
      signInWithOAuth: signInWithOAuth,
      signOutWithOptions: signOutWithOptions,
      setRoomPresence: setRoomPresence,
      roomPresence: roomPresence,
      observeRoomPresence: observeRoomPresence,
      leaveRoomPresence: leaveRoomPresence,
      publishRoomTopicMessage: publishRoomTopicMessage,
      roomTopicMessages: roomTopicMessages,
      observeRoomTopicMessages: observeRoomTopicMessages,
      uploadFile: uploadFile,
      uploadFileProgress: uploadFileProgress,
      storedFiles: storedFiles,
      observeStoredFiles: observeStoredFiles,
      storedFileContents: storedFileContents,
      deleteStoredFile: deleteStoredFile,
      appendStreamChunk: appendStreamChunk,
      streamChunks: streamChunks,
      observeStreamChunks: observeStreamChunks,
      createShare: createShare,
      acceptShare: acceptShare,
      shares: shares,
      observeShares: observeShares,
      updateShareMembershipRole: updateShareMembershipRole,
      revokeShare: revokeShare
    )
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    oauthAuthorizationURL: (@Sendable (String, URL) throws -> URL)? = nil,
    issuerURI: (@Sendable () throws -> URL)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil,
    setRoomPresence:
      (@Sendable (InstantRoomHandle, String?, [String: JSONValue]) async throws
        -> InstantRoomPresenceMember)? = nil,
    roomPresence:
      (@Sendable (InstantRoomHandle) async throws -> [InstantRoomPresenceMember])? = nil,
    observeRoomPresence:
      (@Sendable (InstantRoomHandle) async throws -> AsyncStream<[InstantRoomPresenceMember]>)? =
        nil,
    leaveRoomPresence: (@Sendable (InstantRoomHandle, String?) async throws -> String)? = nil,
    publishRoomTopicMessage:
      (@Sendable (InstantRoomHandle, String, String?, JSONValue) async throws
        -> InstantRoomTopicMessage)? = nil,
    roomTopicMessages:
      (@Sendable (InstantRoomHandle, String, Int?) async throws
        -> [InstantRoomTopicMessage])? = nil,
    observeRoomTopicMessages:
      (@Sendable (InstantRoomHandle, String) async throws
        -> AsyncStream<[InstantRoomTopicMessage]>)? = nil,
    uploadFile:
      (@Sendable (URL, String?, String?) async throws -> InstantStoredFile)? = nil,
    uploadFileProgress:
      (@Sendable (URL, String?, String?) async throws
        -> AsyncThrowingStream<InstantFileUploadProgress, Error>)? = nil,
    storedFiles: (@Sendable () async throws -> [InstantStoredFile])? = nil,
    observeStoredFiles:
      (@Sendable () async throws -> AsyncStream<[InstantStoredFile]>)? = nil,
    storedFileContents:
      (@Sendable (String) async throws -> InstantStoredFileContents)? = nil,
    deleteStoredFile:
      (@Sendable (String) async throws -> InstantStoredFile)? = nil,
    appendStreamChunk:
      (@Sendable (String, JSONValue) async throws -> InstantStreamChunk)? = nil,
    streamChunks:
      (@Sendable (String, Int?) async throws -> [InstantStreamChunk])? = nil,
    observeStreamChunks:
      (@Sendable (String) async throws -> AsyncStream<[InstantStreamChunk]>)? = nil,
    createShare:
      (@Sendable (String, String) async throws -> InstantShareSnapshot)? = nil,
    acceptShare:
      (@Sendable (String) async throws -> InstantShareSnapshot)? = nil,
    shares:
      (@Sendable () async throws -> [InstantShareSnapshot])? = nil,
    observeShares:
      (@Sendable () async throws -> AsyncStream<[InstantShareSnapshot]>)? = nil,
    updateShareMembershipRole:
      (@Sendable (String, String, InstantShareRole) async throws -> InstantShareSnapshot)? = nil,
    revokeShare:
      (@Sendable (String) async throws -> InstantShareSnapshot)? = nil
  ) {
    let authError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData auth",
      message: "No auth client has been configured.",
      recovery: "Bootstrap Instant Swift Data before using auth, or override auth closures in tests."
    )
    let transportError = InstantError(
      code: .implementationFailed,
      operation: "flush InstantSwiftData mutations",
      message: "No mutation transport client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before flushing mutations, or override the flush closure in tests."
    )
    let runtimeStatusError = InstantError(
      code: .implementationFailed,
      operation: "inspect InstantSwiftData connection",
      message: "No runtime connection status client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before inspecting connection status, or override the status closure in tests."
    )
    let roomsError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData rooms",
      message: "No room client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before using rooms, or override room closures in tests."
    )
    let filesError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData files",
      message: "No file client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before using files, or override file closures in tests."
    )
    let streamsError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData streams",
      message: "No stream client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before using streams, or override stream closures in tests."
    )
    let sharesError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData shares",
      message: "No share client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before using shares, or override share closures in tests."
    )

    self.runtime = nil
    self.transactOperation = transact
    self.queryOnceOperation =
      queryOnce
      ?? { plan in
        InstantQueryEmission(queryID: plan.id, sequence: 0, values: try await query(plan))
      }
    self.queryOperation = query
    self.observeOperation = observe
    self.pendingMutationsOperation = pendingMutations
    self.flushPendingMutationsOperation = flushPendingMutations ?? { _ in throw transportError }
    self.connectionStatusOperation = connectionStatus ?? { throw runtimeStatusError }
    self.connectOperation = connect ?? { throw runtimeStatusError }
    self.closeConnectionOperation = closeConnection ?? { throw runtimeStatusError }
    self.localIDOperation = localID
    self.authSessionOperation = authSession ?? { throw authError }
    self.observeAuthSessionOperation = observeAuthSession ?? { throw authError }
    self.signInAsGuestOperation = signInAsGuest ?? { throw authError }
    self.sendMagicCodeOperation = sendMagicCode ?? { _ in throw authError }
    self.signInWithMagicCodeOperation = signInWithMagicCode ?? { _, _ in throw authError }
    self.signInWithRefreshTokenOperation = signInWithRefreshToken ?? { _, _ in throw authError }
    self.signInWithIDTokenOperation = signInWithIDToken ?? { _, _, _ in throw authError }
    self.signInWithOAuthOperation = signInWithOAuth ?? { _, _ in throw authError }
    self.oauthAuthorizationURLOperation = oauthAuthorizationURL ?? { _, _ in throw authError }
    self.issuerURIOperation = issuerURI ?? { throw authError }
    self.signOutOperation =
      signOutWithOptions ?? { _ in
        if let signOut {
          try await signOut()
        } else {
          throw authError
        }
      }
    self.setRoomPresenceOperation = setRoomPresence ?? { _, _, _ in throw roomsError }
    self.roomPresenceOperation = roomPresence ?? { _ in throw roomsError }
    self.observeRoomPresenceOperation = observeRoomPresence ?? { _ in throw roomsError }
    self.leaveRoomPresenceOperation = leaveRoomPresence ?? { _, _ in throw roomsError }
    self.publishRoomTopicMessageOperation =
      publishRoomTopicMessage ?? { _, _, _, _ in throw roomsError }
    self.roomTopicMessagesOperation = roomTopicMessages ?? { _, _, _ in throw roomsError }
    self.observeRoomTopicMessagesOperation =
      observeRoomTopicMessages ?? { _, _ in throw roomsError }
    self.uploadFileOperation = uploadFile ?? { _, _, _ in throw filesError }
    self.uploadFileProgressOperation = uploadFileProgress ?? { _, _, _ in throw filesError }
    self.storedFilesOperation = storedFiles ?? { throw filesError }
    self.observeStoredFilesOperation = observeStoredFiles ?? { throw filesError }
    self.storedFileContentsOperation = storedFileContents ?? { _ in throw filesError }
    self.deleteStoredFileOperation = deleteStoredFile ?? { _ in throw filesError }
    self.appendStreamChunkOperation = appendStreamChunk ?? { _, _ in throw streamsError }
    self.streamChunksOperation = streamChunks ?? { _, _ in throw streamsError }
    self.observeStreamChunksOperation = observeStreamChunks ?? { _ in throw streamsError }
    self.createShareOperation = createShare ?? { _, _ in throw sharesError }
    self.acceptShareOperation = acceptShare ?? { _ in throw sharesError }
    self.sharesOperation = shares ?? { throw sharesError }
    self.observeSharesOperation = observeShares ?? { throw sharesError }
    self.updateShareMembershipRoleOperation =
      updateShareMembershipRole ?? { _, _, _ in throw sharesError }
    self.revokeShareOperation = revokeShare ?? { _ in throw sharesError }
  }

  public static func unimplemented(_ message: String) -> Self {
    let error = InstantError(
      code: .implementationFailed,
      operation: "access default InstantSwiftData client",
      message: message,
      recovery: "Bootstrap Instant Swift Data before reading the dependency, or override it in tests."
    )

    return Self(
      transact: { _ in
        throw error
      },
      query: { _ in
        throw error
      },
      observe: { _ in
        AsyncStream { continuation in
          reportIssue(error)
          continuation.finish()
        }
      },
      pendingMutations: {
        reportIssue(error)
        return []
      },
      flushPendingMutations: { _ in
        throw error
      },
      connectionStatus: {
        throw error
      },
      connect: {
        throw error
      },
      closeConnection: {
        throw error
      },
      localID: { _ in
        throw error
      },
      authSession: {
        throw error
      },
      observeAuthSession: {
        throw error
      },
      signInAsGuest: {
        throw error
      },
      sendMagicCode: { _ in
        throw error
      },
      signInWithMagicCode: { _, _ in
        throw error
      },
      signInWithRefreshToken: { _, _ in
        throw error
      },
      oauthAuthorizationURL: { _, _ in
        throw error
      },
      issuerURI: {
        throw error
      },
      signOut: {
        throw error
      },
      signInWithIDToken: { _, _, _ in
        throw error
      },
      signInWithOAuth: { _, _ in
        throw error
      },
      signOutWithOptions: { _ in
        throw error
      },
      setRoomPresence: { _, _, _ in
        throw error
      },
      roomPresence: { _ in
        throw error
      },
      observeRoomPresence: { _ in
        throw error
      },
      leaveRoomPresence: { _, _ in
        throw error
      },
      publishRoomTopicMessage: { _, _, _, _ in
        throw error
      },
      roomTopicMessages: { _, _, _ in
        throw error
      },
      observeRoomTopicMessages: { _, _ in
        throw error
      },
      uploadFile: { _, _, _ in
        throw error
      },
      uploadFileProgress: { _, _, _ in
        throw error
      },
      storedFiles: {
        throw error
      },
      observeStoredFiles: {
        throw error
      },
      storedFileContents: { _ in
        throw error
      },
      deleteStoredFile: { _ in
        throw error
      },
      appendStreamChunk: { _, _ in
        throw error
      },
      streamChunks: { _, _ in
        throw error
      },
      observeStreamChunks: { _ in
        throw error
      },
      createShare: { _, _ in
        throw error
      },
      acceptShare: { _ in
        throw error
      },
      shares: {
        throw error
      },
      observeShares: {
        throw error
      },
      updateShareMembershipRole: { _, _, _ in
        throw error
      },
      revokeShare: { _ in
        throw error
      }
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration
  ) async throws -> Self {
    try await Self(runtime: InstantRuntime.bootstrap(configuration: configuration))
  }

  @discardableResult
  public func transact(
    _ transaction: InstantStoreTransaction
  ) async throws -> InstantStoreMutationResult {
    try await transactOperation(transaction)
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOperation(plan)
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    try await queryOnceOperation(plan)
  }

  public func observe(_ plan: InstantQueryPlan) async -> AsyncStream<InstantQueryEmission> {
    await observeOperation(plan)
  }

  public func pendingMutations() async -> [PendingMutation] {
    await pendingMutationsOperation()
  }

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    try await flushPendingMutationsOperation(limit)
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    try await connectionStatusOperation()
  }

  @discardableResult
  public func connect() async throws -> InstantConnectionStatus {
    try await connectOperation()
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    try await closeConnectionOperation()
  }

  public func localID(named name: String) async throws -> String {
    try await localIDOperation(name)
  }

  public func authSession() async throws -> InstantAuthSession? {
    try await authSessionOperation()
  }

  public func observeAuthSession() async throws -> AsyncStream<InstantAuthSession?> {
    try await observeAuthSessionOperation()
  }

  public func subscribeAuthSession() async throws -> FetchSubscription<InstantAuthSession?> {
    let sessions = try await observeAuthSession()
    try Task.checkCancellation()
    return fetchSubscription(from: sessions)
  }

  public func signInAsGuest() async throws -> InstantAuthSession {
    try await signInAsGuestOperation()
  }

  public func sendMagicCode(email: String) async throws -> InstantMagicCodeChallenge {
    try await sendMagicCodeOperation(email)
  }

  public func signInWithMagicCode(email: String, code: String) async throws -> InstantAuthSession {
    try await signInWithMagicCodeOperation(email, code)
  }

  public func signInWithRefreshToken(
    _ refreshToken: String,
    userID: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithRefreshTokenOperation(refreshToken, userID)
  }

  public func signInWithIDToken(
    clientName: String,
    idToken: String,
    nonce: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithIDTokenOperation(clientName, idToken, nonce)
  }

  public func signInWithOAuth(
    code: String,
    codeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithOAuthOperation(code, codeVerifier)
  }

  public func oauthAuthorizationURL(
    clientName: String,
    redirectURL: URL
  ) throws -> URL {
    try oauthAuthorizationURLOperation(clientName, redirectURL)
  }

  public func issuerURI() throws -> URL {
    try issuerURIOperation()
  }

  public func signOut() async throws {
    try await signOut(invalidateToken: true)
  }

  public func signOut(invalidateToken: Bool = true) async throws {
    try await signOutOperation(invalidateToken)
  }

  @discardableResult
  public func setRoomPresence(
    room: InstantRoomHandle,
    userID: String? = nil,
    values: [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember {
    try await setRoomPresenceOperation(room, userID, values)
  }

  public func roomPresence(
    room: InstantRoomHandle
  ) async throws -> [InstantRoomPresenceMember] {
    try await roomPresenceOperation(room)
  }

  public func observeRoomPresence(
    room: InstantRoomHandle
  ) async throws -> AsyncStream<[InstantRoomPresenceMember]> {
    try await observeRoomPresenceOperation(room)
  }

  public func subscribeRoomPresence(
    room: InstantRoomHandle
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    let members = try await observeRoomPresence(room: room)
    try Task.checkCancellation()
    return fetchSubscription(from: members)
  }

  @discardableResult
  public func leaveRoomPresence(
    room: InstantRoomHandle,
    userID: String? = nil
  ) async throws -> String {
    try await leaveRoomPresenceOperation(room, userID)
  }

  @discardableResult
  public func publishRoomTopicMessage(
    room: InstantRoomHandle,
    topic: String,
    userID: String? = nil,
    payload: JSONValue
  ) async throws -> InstantRoomTopicMessage {
    try await publishRoomTopicMessageOperation(room, topic, userID, payload)
  }

  public func roomTopicMessages(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) async throws -> [InstantRoomTopicMessage] {
    try await roomTopicMessagesOperation(room, topic, limit)
  }

  public func observeRoomTopicMessages(
    room: InstantRoomHandle,
    topic: String
  ) async throws -> AsyncStream<[InstantRoomTopicMessage]> {
    try await observeRoomTopicMessagesOperation(room, topic)
  }

  public func subscribeRoomTopicMessages(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    try validateNonNegativeLimit(
      limit,
      operation: "subscribe room topic messages",
      subject: "Room topic message"
    )
    let messages = try await observeRoomTopicMessages(room: room, topic: topic)
    try Task.checkCancellation()
    let subscription = fetchSubscription(from: messages)
    if let limit {
      return subscription.map { Array($0.prefix(limit)) }
    }
    return subscription
  }

  @discardableResult
  public func uploadFile(
    from sourceURL: URL,
    name: String? = nil,
    contentType: String? = nil
  ) async throws -> InstantStoredFile {
    try await uploadFileOperation(sourceURL, name, contentType)
  }

  public func uploadFileProgress(
    from sourceURL: URL,
    name: String? = nil,
    contentType: String? = nil
  ) async throws -> AsyncThrowingStream<InstantFileUploadProgress, Error> {
    try await uploadFileProgressOperation(sourceURL, name, contentType)
  }

  public func storedFiles() async throws -> [InstantStoredFile] {
    try await storedFilesOperation()
  }

  public func observeStoredFiles() async throws -> AsyncStream<[InstantStoredFile]> {
    try await observeStoredFilesOperation()
  }

  public func subscribeStoredFiles() async throws -> FetchSubscription<[InstantStoredFile]> {
    let files = try await observeStoredFiles()
    try Task.checkCancellation()
    return fetchSubscription(from: files)
  }

  public func storedFileContents(id: String) async throws -> InstantStoredFileContents {
    try await storedFileContentsOperation(id)
  }

  @discardableResult
  public func deleteStoredFile(id: String) async throws -> InstantStoredFile {
    try await deleteStoredFileOperation(id)
  }

  @discardableResult
  public func appendStreamChunk(
    streamID: String,
    payload: JSONValue
  ) async throws -> InstantStreamChunk {
    try await appendStreamChunkOperation(streamID, payload)
  }

  public func streamChunks(
    streamID: String,
    limit: Int? = nil
  ) async throws -> [InstantStreamChunk] {
    try await streamChunksOperation(streamID, limit)
  }

  public func observeStreamChunks(
    streamID: String
  ) async throws -> AsyncStream<[InstantStreamChunk]> {
    try await observeStreamChunksOperation(streamID)
  }

  public func subscribeStreamChunks(
    streamID: String,
    limit: Int? = nil
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    try validateNonNegativeLimit(
      limit,
      operation: "subscribe stream chunks",
      subject: "Stream chunk"
    )
    let chunks = try await observeStreamChunks(streamID: streamID)
    try Task.checkCancellation()
    let subscription = fetchSubscription(from: chunks)
    if let limit {
      return subscription.map { Array($0.prefix(limit)) }
    }
    return subscription
  }

  @discardableResult
  public func createShare(
    rootNamespace: String,
    rootID: String
  ) async throws -> InstantShareSnapshot {
    try await createShareOperation(rootNamespace, rootID)
  }

  @discardableResult
  public func acceptShare(token: String) async throws -> InstantShareSnapshot {
    try await acceptShareOperation(token)
  }

  public func shares() async throws -> [InstantShareSnapshot] {
    try await sharesOperation()
  }

  public func observeShares() async throws -> AsyncStream<[InstantShareSnapshot]> {
    try await observeSharesOperation()
  }

  public func subscribeShares() async throws -> FetchSubscription<[InstantShareSnapshot]> {
    let shares = try await observeShares()
    try Task.checkCancellation()
    return fetchSubscription(from: shares)
  }

  @discardableResult
  public func updateShareMembershipRole(
    shareID: String,
    userID: String,
    role: InstantShareRole
  ) async throws -> InstantShareSnapshot {
    try await updateShareMembershipRoleOperation(shareID, userID, role)
  }

  @discardableResult
  public func revokeShare(id: String) async throws -> InstantShareSnapshot {
    try await revokeShareOperation(id)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async -> FetchSubscription<[Entity]> {
    let emissions = await observe(query.plan)
    let stream = AsyncThrowingStream<[Entity], Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(try Entity.decode(emission.values))
        } catch {
          stream.continuation.finish(throwing: error)
          return
        }
      }
      stream.continuation.finish()
    }
    stream.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return FetchSubscription(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }
}

public enum InstantSwiftDataBootstrapContext: String, Sendable {
  case live
  case preview
  case test
  case cli
}

public struct FetchSubscription<Element: Sendable>: AsyncSequence, Sendable {
  public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.Iterator

  private let stream: AsyncThrowingStream<Element, Error>
  private let cancellation: FetchSubscriptionCancellation

  public init(
    stream: AsyncThrowingStream<Element, Error>,
    cancel: @escaping @Sendable () -> Void
  ) {
    self.stream = stream
    self.cancellation = FetchSubscriptionCancellation(cancel)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }

  public func cancel() {
    cancellation.cancel()
  }

  public var task: Void {
    get async throws {
      try await withTaskCancellationHandler {
        await cancellation.wait()
        try Task.checkCancellation()
      } onCancel: {
        self.cancel()
      }
    }
  }

  fileprivate static func finished() -> Self {
    let finished = AsyncThrowingStream<Element, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    finished.continuation.finish()
    let subscription = Self(stream: finished.stream) {}
    subscription.cancel()
    return subscription
  }

  public func map<Mapped: Sendable>(
    _ transform: @escaping @Sendable (Element) throws -> Mapped
  ) -> FetchSubscription<Mapped> {
    let mapped = AsyncThrowingStream<Mapped, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      do {
        for try await value in self {
          try Task.checkCancellation()
          mapped.continuation.yield(try transform(value))
        }
        mapped.continuation.finish()
      } catch {
        mapped.continuation.finish(throwing: error)
      }
    }
    mapped.continuation.onTermination = { @Sendable _ in
      task.cancel()
      self.cancel()
    }
    return FetchSubscription<Mapped>(stream: mapped.stream) {
      task.cancel()
      mapped.continuation.finish()
      self.cancel()
    }
  }
}

private func fetchSubscription<Element: Sendable>(
  from values: AsyncStream<Element>
) -> FetchSubscription<Element> {
  let stream = AsyncThrowingStream<Element, Error>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
  )
  let task = Task {
    for await value in values {
      do {
        try Task.checkCancellation()
        stream.continuation.yield(value)
      } catch {
        stream.continuation.finish(throwing: error)
        return
      }
    }
    stream.continuation.finish()
  }
  stream.continuation.onTermination = { @Sendable _ in
    task.cancel()
  }
  return FetchSubscription(stream: stream.stream) {
    task.cancel()
    stream.continuation.finish()
  }
}

private func validateNonNegativeLimit(
  _ limit: Int?,
  operation: String,
  subject: String
) throws {
  guard let limit, limit < 0 else { return }
  throw InstantError(
    code: .validationFailed,
    operation: operation,
    message: "\(subject) limit must be greater than or equal to 0.",
    recovery: "Pass a non-negative limit, or omit limit to observe every local value."
  )
}

// SAFETY: all mutable fetch state is protected by `lock`.
private final class FetchStorage<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _wrappedValue: Value
  private var _loadError: InstantError?
  private var _isLoading: Bool

  init(value: Value) {
    self._wrappedValue = value
    self._loadError = nil
    self._isLoading = false
  }

  var wrappedValue: Value {
    get {
      withLock { _wrappedValue }
    }
    set {
      withLock {
        _wrappedValue = newValue
      }
    }
  }

  var loadError: InstantError? {
    get {
      withLock { _loadError }
    }
    set {
      withLock {
        _loadError = newValue
      }
    }
  }

  var isLoading: Bool {
    get {
      withLock { _isLoading }
    }
    set {
      withLock {
        _isLoading = newValue
      }
    }
  }

  private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

private struct FetchOperations<Value: Sendable>: Sendable {
  var load: (@Sendable (InstantSwiftDataClient) async throws -> Value)?
  var subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)?
}

// SAFETY: all mutable operation configuration is protected by `lock`.
private final class FetchOperationStorage<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var operations: FetchOperations<Value>

  init(_ operations: FetchOperations<Value> = FetchOperations()) {
    self.operations = operations
  }

  var value: FetchOperations<Value> {
    get {
      lock.lock()
      defer { lock.unlock() }
      return operations
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      operations = newValue
    }
  }
}

// SAFETY: all mutable configuration is protected by `lock`.
private final class LockedValueStorage<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Value

  init(_ value: Value) {
    self._value = value
  }

  var value: Value {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }
}

// SAFETY: the only mutable state is `isCancelled`, which is protected by `lock`.
private final class FetchSubscriptionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: @Sendable () -> Void
  private var isCancelled = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  init(_ operation: @escaping @Sendable () -> Void) {
    self.operation = operation
  }

  deinit {
    cancel()
  }

  func cancel() {
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    isCancelled = true
    let continuations = self.continuations
    self.continuations.removeAll()
    lock.unlock()

    operation()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if isCancelled {
        lock.unlock()
        continuation.resume()
      } else {
        continuations.append(continuation)
        lock.unlock()
      }
    }
  }
}

private enum DefaultInstantSwiftDataKey: TestDependencyKey {
  static var testValue: InstantSwiftDataClient {
    .unimplemented("No test InstantSwiftData client has been configured.")
  }

  static var previewValue: InstantSwiftDataClient {
    .unimplemented("No preview InstantSwiftData client has been configured.")
  }
}

extension DefaultInstantSwiftDataKey: DependencyKey {
  static var liveValue: InstantSwiftDataClient {
    .unimplemented("No live InstantSwiftData client has been configured.")
  }
}

private enum InstantMagicCodeExchangeKey: TestDependencyKey {
  static var testValue: InstantMagicCodeExchange {
    .local
  }

  static var previewValue: InstantMagicCodeExchange {
    .local
  }
}

extension InstantMagicCodeExchangeKey: DependencyKey {
  static var liveValue: InstantMagicCodeExchange {
    .local
  }
}

private enum InstantRefreshTokenVerifierKey: TestDependencyKey {
  static var testValue: InstantRefreshTokenVerifier {
    .local
  }

  static var previewValue: InstantRefreshTokenVerifier {
    .local
  }
}

extension InstantRefreshTokenVerifierKey: DependencyKey {
  static var liveValue: InstantRefreshTokenVerifier {
    .local
  }
}

private enum InstantIDTokenExchangeKey: TestDependencyKey {
  static var testValue: InstantIDTokenExchange {
    .local
  }

  static var previewValue: InstantIDTokenExchange {
    .local
  }
}

extension InstantIDTokenExchangeKey: DependencyKey {
  static var liveValue: InstantIDTokenExchange {
    .local
  }
}

private enum InstantOAuthExchangeKey: TestDependencyKey {
  static var testValue: InstantOAuthExchange {
    .local
  }

  static var previewValue: InstantOAuthExchange {
    .local
  }
}

extension InstantOAuthExchangeKey: DependencyKey {
  static var liveValue: InstantOAuthExchange {
    .local
  }
}

private enum InstantAuthTokenInvalidatorKey: TestDependencyKey {
  static var testValue: InstantAuthTokenInvalidator {
    .local
  }

  static var previewValue: InstantAuthTokenInvalidator {
    .local
  }
}

extension InstantAuthTokenInvalidatorKey: DependencyKey {
  static var liveValue: InstantAuthTokenInvalidator {
    .local
  }
}

private enum InstantMutationTransportKey: TestDependencyKey {
  static var testValue: InstantMutationTransportClient {
    .local
  }

  static var previewValue: InstantMutationTransportClient {
    .local
  }
}

extension InstantMutationTransportKey: DependencyKey {
  static var liveValue: InstantMutationTransportClient {
    .local
  }
}

private enum SyncUpSpeechClientKey: TestDependencyKey {
  static var testValue: SyncUpSpeechClient {
    .local
  }

  static var previewValue: SyncUpSpeechClient {
    .local
  }
}

extension SyncUpSpeechClientKey: DependencyKey {
  static var liveValue: SyncUpSpeechClient {
    .local
  }
}

private enum SyncUpSoundEffectClientKey: TestDependencyKey {
  static var testValue: SyncUpSoundEffectClient {
    .local
  }

  static var previewValue: SyncUpSoundEffectClient {
    .local
  }
}

extension SyncUpSoundEffectClientKey: DependencyKey {
  static var liveValue: SyncUpSoundEffectClient {
    .local
  }
}

private enum SyncUpOpenSettingsClientKey: TestDependencyKey {
  static var testValue: SyncUpOpenSettingsClient {
    .local
  }

  static var previewValue: SyncUpOpenSettingsClient {
    .local
  }
}

extension SyncUpOpenSettingsClientKey: DependencyKey {
  static var liveValue: SyncUpOpenSettingsClient {
    .local
  }
}

extension DependencyValues {
  public var defaultInstantSwiftData: InstantSwiftDataClient {
    get { self[DefaultInstantSwiftDataKey.self] }
    set { self[DefaultInstantSwiftDataKey.self] = newValue }
  }

  public var instantMagicCodeExchange: InstantMagicCodeExchange {
    get { self[InstantMagicCodeExchangeKey.self] }
    set { self[InstantMagicCodeExchangeKey.self] = newValue }
  }

  public var instantRefreshTokenVerifier: InstantRefreshTokenVerifier {
    get { self[InstantRefreshTokenVerifierKey.self] }
    set { self[InstantRefreshTokenVerifierKey.self] = newValue }
  }

  public var instantIDTokenExchange: InstantIDTokenExchange {
    get { self[InstantIDTokenExchangeKey.self] }
    set { self[InstantIDTokenExchangeKey.self] = newValue }
  }

  public var instantOAuthExchange: InstantOAuthExchange {
    get { self[InstantOAuthExchangeKey.self] }
    set { self[InstantOAuthExchangeKey.self] = newValue }
  }

  public var instantAuthTokenInvalidator: InstantAuthTokenInvalidator {
    get { self[InstantAuthTokenInvalidatorKey.self] }
    set { self[InstantAuthTokenInvalidatorKey.self] = newValue }
  }

  public var instantMutationTransport: InstantMutationTransportClient {
    get { self[InstantMutationTransportKey.self] }
    set { self[InstantMutationTransportKey.self] = newValue }
  }

  public var syncUpSpeechClient: SyncUpSpeechClient {
    get { self[SyncUpSpeechClientKey.self] }
    set { self[SyncUpSpeechClientKey.self] = newValue }
  }

  public var syncUpSoundEffectClient: SyncUpSoundEffectClient {
    get { self[SyncUpSoundEffectClientKey.self] }
    set { self[SyncUpSoundEffectClientKey.self] = newValue }
  }

  public var syncUpOpenSettingsClient: SyncUpOpenSettingsClient {
    get { self[SyncUpOpenSettingsClientKey.self] }
    set { self[SyncUpOpenSettingsClientKey.self] = newValue }
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    try await self.bootstrapInstantSwiftData(
      appID: appID,
      apiURI: InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      context: context,
      initialAttributes: initialAttributes
    )
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    let date = self.date
    let uuid = self.uuid
    let magicCodeExchange = self.instantMagicCodeExchange
    let refreshTokenVerifier = self.instantRefreshTokenVerifier
    let idTokenExchange = self.instantIDTokenExchange
    let oauthExchange = self.instantOAuthExchange
    let authTokenInvalidator = self.instantAuthTokenInvalidator
    let mutationTransport = self.instantMutationTransport
    let url =
      persistenceURL
      ?? Self.defaultInstantSwiftDataPersistenceURL(
        appID: appID,
        context: context,
        uniqueID: context == .test ? uuid().uuidString.lowercased() : nil
      )

    self.defaultInstantSwiftData = try await InstantSwiftDataClient.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: url,
        initialAttributes: initialAttributes,
        now: {
          InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1000).rounded()))
        },
        makeID: {
          uuid().uuidString.lowercased()
        },
        refreshTokenVerifier: refreshTokenVerifier,
        magicCodeExchange: magicCodeExchange,
        idTokenExchange: idTokenExchange,
        oauthExchange: oauthExchange,
        authTokenInvalidator: authTokenInvalidator,
        mutationTransport: mutationTransport
      )
    )
  }

  public static func defaultInstantSwiftDataPersistenceURL(
    appID: String,
    context: InstantSwiftDataBootstrapContext,
    uniqueID: String? = nil
  ) -> URL {
    let fileName = sanitizedPersistenceName(appID) + ".sqlite"

    switch context {
    case .live:
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".instant-swift-data", isDirectory: true)
        .appendingPathComponent("apps", isDirectory: true)
        .appendingPathComponent(fileName)

    case .cli:
      return defaultCLIHomeURL()
        .appendingPathComponent("state.sqlite")

    case .preview:
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataPreviews", isDirectory: true)
        .appendingPathComponent(fileName)

    case .test:
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataTests", isDirectory: true)
        .appendingPathComponent((uniqueID ?? UUID().uuidString.lowercased()) + "-" + fileName)
    }
  }

  private static func sanitizedPersistenceName(_ appID: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = appID.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return name.isEmpty ? "default" : name
  }

  private static func defaultCLIHomeURL() -> URL {
    if let path = ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_HOME"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".instant-swift-data", isDirectory: true)
  }
}

@dynamicMemberLookup
@propertyWrapper
public struct FetchAll<Element: Sendable>: Sendable {
  private let storage: FetchStorage<[Element]>
  private let operations: FetchOperationStorage<[Element]>

  public var wrappedValue: [Element] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  public subscript<Member>(dynamicMember keyPath: KeyPath<[Element], Member>) -> Member {
    wrappedValue[keyPath: keyPath]
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[Element]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }

    public subscript<Member>(
      dynamicMember keyPath: WritableKeyPath<[Element], Member>
    ) -> Binding<Member> {
      binding[dynamicMember: keyPath]
    }
  #endif

  @_disfavoredOverload
  public init(wrappedValue: [Element] = []) {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage()
  }

  public init(wrappedValue: [Element] = []) where Element: InstantEntityModel {
    self.init(wrappedValue: wrappedValue, Element.query)
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage(Self.operations(for: query))
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      operations.value = newValue.operations.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation = operations.value.load else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchAll with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchAll",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func load(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    operations.value = Self.operations(for: query)
    try await load(using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>?
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    guard let query else {
      clearQuery()
      return
    }
    try await load(query, using: client)
  }

  public func subscribe() async throws -> FetchSubscription<[Element]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> {
    guard let subscribeOperation = operations.value.subscribe else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchAll with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }

    loadError = nil
    return try await subscribeOperation(client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    operations.value = Self.operations(for: query)
    return try await subscribe(using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>?
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    guard let query else {
      clearQuery()
      return .finished()
    }
    return try await subscribe(query, using: client)
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe FetchAll",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func task(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    operations.value = Self.operations(for: query)
    try await task(using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>?
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    guard let query else {
      clearQuery()
      return
    }
    try await task(query, using: client)
  }

  private func clearQuery() {
    operations.value = FetchOperations()
    wrappedValue = []
    loadError = nil
    isLoading = false
  }

  private static func operations(
    for query: InstantEntityQuery<Element>
  ) -> FetchOperations<[Element]> where Element: InstantEntityModel {
    FetchOperations(
      load: { client in
        try await client.query(query)
      },
      subscribe: { client in
        await client.subscribe(query)
      }
    )
  }
}

@dynamicMemberLookup
@propertyWrapper
public struct FetchOne<Value: Sendable>: Sendable {
  private let storage: FetchStorage<Value>
  private let operations: FetchOperationStorage<Value>

  public var wrappedValue: Value {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
    wrappedValue[keyPath: keyPath]
  }

  #if canImport(SwiftUI)
    public var binding: Binding<Value> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }

    public subscript<Member>(
      dynamicMember keyPath: WritableKeyPath<Value, Member>
    ) -> Binding<Member> {
      binding[dynamicMember: keyPath]
    }
  #endif

  @_disfavoredOverload
  public init(wrappedValue: Value) {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage()
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      operations.value = newValue.operations.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation = operations.value.load else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchOne with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchOne",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe() async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    guard let subscribeOperation = operations.value.subscribe else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchOne with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }

    loadError = nil
    return try await subscribeOperation(client)
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe FetchOne",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  fileprivate static func limitOne<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) -> InstantEntityQuery<Entity> {
    if query.plan.limit == nil {
      return query.limit(1)
    }
    return query
  }

  fileprivate static func notFoundError<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    operation: String
  ) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      namespace: Entity.instantNamespace,
      path: query.plan.id,
      message: "No '\(Entity.instantNamespace)' entity matched this FetchOne query.",
      recovery: "Use an optional @FetchOne value if an empty result set is expected."
    )
  }
}

extension FetchOne where Value: InstantEntityModel {
  public init(wrappedValue: Value) {
    self.init(wrappedValue: wrappedValue, Value.query)
  }

  public init(
    wrappedValue: Value,
    _ query: InstantEntityQuery<Value>
  ) {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage(Self.requiredOperations(for: query))
  }

  public func load(
    _ query: InstantEntityQuery<Value>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Value>,
    using client: InstantSwiftDataClient
  ) async throws {
    configureRequiredQuery(query)
    try await load(using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Value>
  ) async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Value>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    configureRequiredQuery(query)
    return try await subscribe(using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Value>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Value>,
    using client: InstantSwiftDataClient
  ) async throws {
    configureRequiredQuery(query)
    try await task(using: client)
  }

  private func configureRequiredQuery(_ query: InstantEntityQuery<Value>) {
    operations.value = Self.requiredOperations(for: query)
  }

  private static func requiredOperations(
    for query: InstantEntityQuery<Value>
  ) -> FetchOperations<Value> {
    FetchOperations(
      load: { client in
        let values = try await client.query(Self.limitOne(query))
        guard let value = values.first else {
          throw Self.notFoundError(query, operation: "load FetchOne")
        }
        return value
      },
      subscribe: { client in
        await client.subscribe(Self.limitOne(query)).map { values in
          guard let value = values.first else {
            throw Self.notFoundError(query, operation: "subscribe FetchOne")
          }
          return value
        }
      }
    )
  }
}

extension FetchOne {
  public init<Entity: InstantEntityModel>(
    wrappedValue: Entity? = nil
  ) where Value == Entity? {
    self.init(wrappedValue: wrappedValue, Entity.query)
  }

  public init<Entity: InstantEntityModel>(
    wrappedValue: Entity? = nil,
    _ query: InstantEntityQuery<Entity>
  ) where Value == Entity? {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage(Self.optionalOperations(for: query))
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    using client: InstantSwiftDataClient
  ) async throws where Value == Entity? {
    configureOptionalQuery(query)
    try await load(using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?
  ) async throws where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?,
    using client: InstantSwiftDataClient
  ) async throws where Value == Entity? {
    guard let query else {
      clearOptionalQuery()
      return
    }
    try await load(query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws -> FetchSubscription<Value> where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> where Value == Entity? {
    configureOptionalQuery(query)
    return try await subscribe(using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?
  ) async throws -> FetchSubscription<Value> where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> where Value == Entity? {
    guard let query else {
      clearOptionalQuery()
      return .finished()
    }
    return try await subscribe(query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    using client: InstantSwiftDataClient
  ) async throws where Value == Entity? {
    configureOptionalQuery(query)
    try await task(using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?
  ) async throws where Value == Entity? {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>?,
    using client: InstantSwiftDataClient
  ) async throws where Value == Entity? {
    guard let query else {
      clearOptionalQuery()
      return
    }
    try await task(query, using: client)
  }

  private func configureOptionalQuery<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) where Value == Entity? {
    operations.value = Self.optionalOperations(for: query)
  }

  private func clearOptionalQuery<Entity: InstantEntityModel>() where Value == Entity? {
    operations.value = FetchOperations()
    wrappedValue = nil
    loadError = nil
    isLoading = false
  }

  private static func optionalOperations<Entity: InstantEntityModel>(
    for query: InstantEntityQuery<Entity>
  ) -> FetchOperations<Value> where Value == Entity? {
    FetchOperations(
      load: { client in
        try await client.query(Self.limitOne(query)).first
      },
      subscribe: { client in
        await client.subscribe(Self.limitOne(query)).map(\.first)
      }
    )
  }
}

@dynamicMemberLookup
@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  private let storage: FetchStorage<Value>
  private let operations: FetchOperationStorage<Value>

  public var wrappedValue: Value {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  public subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
    wrappedValue[keyPath: keyPath]
  }

  #if canImport(SwiftUI)
    public var binding: Binding<Value> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }

    public subscript<Member>(
      dynamicMember keyPath: WritableKeyPath<Value, Member>
    ) -> Binding<Member> {
      binding[dynamicMember: keyPath]
    }
  #endif

  public init(wrappedValue: Value) {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage()
  }

  public init(
    wrappedValue: Value,
    load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)? = nil
  ) {
    self.storage = FetchStorage(value: wrappedValue)
    self.operations = FetchOperationStorage(FetchOperations(load: load, subscribe: subscribe))
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      operations.value = newValue.operations.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation = operations.value.load else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load Fetch",
        message: "No Instant load operation has been configured for this fetch wrapper.",
        recovery: "Initialize @Fetch with a load operation, or pass an operation to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load Fetch",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and fetch load operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func load(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(operation, using: client)
  }

  public func load(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)? = nil
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(operation, subscribe: subscribe, using: client)
  }

  public func load(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    operations.value = FetchOperations(load: operation, subscribe: subscribe)
    try await load(using: client)
  }

  public func subscribe() async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    guard let subscribeOperation = operations.value.subscribe else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe Fetch",
        message: "No Instant subscription operation has been configured for this fetch wrapper.",
        recovery:
          "Initialize @Fetch with a subscribe operation, or pass an operation to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }

    do {
      let subscription = try await subscribeOperation(client)
      loadError = nil
      return subscription
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe Fetch",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and fetch subscription operation."
      )
      loadError = error
      throw error
    }
  }

  public func subscribe(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws
      -> FetchSubscription<Value>
  ) async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(operation, using: client)
  }

  public func subscribe(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws
      -> FetchSubscription<Value>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    var operations = operations.value
    operations.subscribe = operation
    self.operations.value = operations
    return try await subscribe(using: client)
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe Fetch",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and fetch subscription operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func task(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws
      -> FetchSubscription<Value>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(operation, using: client)
  }

  public func task(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws
      -> FetchSubscription<Value>,
    using client: InstantSwiftDataClient
  ) async throws {
    var operations = operations.value
    operations.subscribe = operation
    self.operations.value = operations
    try await task(using: client)
  }
}

@propertyWrapper
public struct AuthSession: Sendable {
  private let storage: FetchStorage<InstantAuthSession?>

  public var wrappedValue: InstantAuthSession? {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<InstantAuthSession?> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: InstantAuthSession? = nil) {
    self.storage = FetchStorage(value: wrappedValue)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let session = try await client.authSession()
      try Task.checkCancellation()
      wrappedValue = session
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load AuthSession",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient auth operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe() async throws -> FetchSubscription<InstantAuthSession?> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<InstantAuthSession?> {
    do {
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeAuthSession()
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe AuthSession",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient auth observation operation."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe AuthSession",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient auth observation operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }
}

@propertyWrapper
public struct RoomPresence: Sendable {
  private let storage: FetchStorage<[InstantRoomPresenceMember]>
  private let room: LockedValueStorage<InstantRoomHandle?>

  public var wrappedValue: [InstantRoomPresenceMember] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[InstantRoomPresenceMember]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [InstantRoomPresenceMember] = []) {
    self.storage = FetchStorage(value: wrappedValue)
    self.room = LockedValueStorage(nil)
  }

  public init(_ type: String, _ id: String) {
    self.storage = FetchStorage(value: [])
    self.room = LockedValueStorage(InstantRoomHandle(type: type, id: id))
  }

  public init(room: InstantRoomHandle) {
    self.storage = FetchStorage(value: [])
    self.room = LockedValueStorage(room)
  }

  public init(wrappedValue: [InstantRoomPresenceMember], _ type: String, _ id: String) {
    self.storage = FetchStorage(value: wrappedValue)
    self.room = LockedValueStorage(InstantRoomHandle(type: type, id: id))
  }

  public init(wrappedValue: [InstantRoomPresenceMember], room: InstantRoomHandle) {
    self.storage = FetchStorage(value: wrappedValue)
    self.room = LockedValueStorage(room)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      room.value = newValue.room.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let room = room.value else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load RoomPresence",
        message: "No Instant room has been configured for this wrapper.",
        recovery: "Initialize @RoomPresence with a room, or pass a room to load(_:_:using:)."
      )
      loadError = error
      throw error
    }
    try await load(room: room, using: client)
  }

  public func load(_ type: String, _ id: String) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(type, id, using: client)
  }

  public func load(
    _ type: String,
    _ id: String,
    using client: InstantSwiftDataClient
  ) async throws {
    try await load(room: InstantRoomHandle(type: type, id: id), using: client)
  }

  public func load(room: InstantRoomHandle) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(room: room, using: client)
  }

  public func load(
    room: InstantRoomHandle,
    using client: InstantSwiftDataClient
  ) async throws {
    self.room.value = room
    isLoading = true
    do {
      let members = try await client.roomPresence(room: room)
      try Task.checkCancellation()
      wrappedValue = members
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load RoomPresence",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room presence operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe()
    async throws -> FetchSubscription<[InstantRoomPresenceMember]>
  {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    guard let room = room.value else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomPresence",
        message: "No Instant room has been configured for this wrapper.",
        recovery: "Initialize @RoomPresence with a room, or pass a room to subscribe(_:_:using:)."
      )
      loadError = error
      throw error
    }
    return try await subscribe(room: room, using: client)
  }

  public func subscribe(
    _ type: String,
    _ id: String
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(type, id, using: client)
  }

  public func subscribe(
    _ type: String,
    _ id: String,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    try await subscribe(room: InstantRoomHandle(type: type, id: id), using: client)
  }

  public func subscribe(
    room: InstantRoomHandle
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(room: room, using: client)
  }

  public func subscribe(
    room: InstantRoomHandle,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    self.room.value = room
    do {
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeRoomPresence(room: room)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomPresence",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room presence observer."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(_ type: String, _ id: String) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(type, id, using: client)
  }

  public func task(
    _ type: String,
    _ id: String,
    using client: InstantSwiftDataClient
  ) async throws {
    self.room.value = InstantRoomHandle(type: type, id: id)
    try await task(using: client)
  }

  public func task(room: InstantRoomHandle) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(room: room, using: client)
  }

  public func task(
    room: InstantRoomHandle,
    using client: InstantSwiftDataClient
  ) async throws {
    self.room.value = room
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe RoomPresence",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room presence observer."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }
}

private struct RoomTopicMessagesConfiguration: Sendable {
  var room: InstantRoomHandle?
  var topic: String?
  var limit: Int?
}

@propertyWrapper
public struct RoomTopicMessages: Sendable {
  private let storage: FetchStorage<[InstantRoomTopicMessage]>
  private let configuration: LockedValueStorage<RoomTopicMessagesConfiguration>

  public var wrappedValue: [InstantRoomTopicMessage] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[InstantRoomTopicMessage]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [InstantRoomTopicMessage] = []) {
    self.storage = FetchStorage(value: wrappedValue)
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(room: nil, topic: nil, limit: nil)
    )
  }

  public init(_ type: String, _ id: String, _ topic: String, limit: Int? = nil) {
    self.storage = FetchStorage(value: [])
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(
        room: InstantRoomHandle(type: type, id: id),
        topic: topic,
        limit: limit
      )
    )
  }

  public init(room: InstantRoomHandle, topic: String, limit: Int? = nil) {
    self.storage = FetchStorage(value: [])
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(room: room, topic: topic, limit: limit)
    )
  }

  public init(
    wrappedValue: [InstantRoomTopicMessage],
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil
  ) {
    self.storage = FetchStorage(value: wrappedValue)
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(
        room: InstantRoomHandle(type: type, id: id),
        topic: topic,
        limit: limit
      )
    )
  }

  public init(
    wrappedValue: [InstantRoomTopicMessage],
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) {
    self.storage = FetchStorage(value: wrappedValue)
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(room: room, topic: topic, limit: limit)
    )
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      configuration.value = newValue.configuration.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    let configuration = configuration.value
    guard let room = configuration.room, let topic = configuration.topic else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load RoomTopicMessages",
        message: "No Instant room topic has been configured for this wrapper.",
        recovery:
          "Initialize @RoomTopicMessages with a room and topic, or pass them to load(_:_:_:using:)."
      )
      loadError = error
      throw error
    }
    try await load(room: room, topic: topic, limit: configuration.limit, using: client)
  }

  public func load(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(type, id, topic, limit: limit, using: client)
  }

  public func load(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    try await load(
      room: InstantRoomHandle(type: type, id: id),
      topic: topic,
      limit: limit,
      using: client
    )
  }

  public func load(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(room: room, topic: topic, limit: limit, using: client)
  }

  public func load(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    self.configuration.value = RoomTopicMessagesConfiguration(
      room: room,
      topic: topic,
      limit: limit
    )
    isLoading = true
    do {
      try Self.validateLimit(limit, operation: "load RoomTopicMessages")
      let messages = try await client.roomTopicMessages(
        room: room,
        topic: topic,
        limit: limit
      )
      try Task.checkCancellation()
      wrappedValue = messages
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load RoomTopicMessages",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room topic operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe()
    async throws -> FetchSubscription<[InstantRoomTopicMessage]>
  {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    let configuration = configuration.value
    guard let room = configuration.room, let topic = configuration.topic else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomTopicMessages",
        message: "No Instant room topic has been configured for this wrapper.",
        recovery:
          "Initialize @RoomTopicMessages with a room and topic, or pass them to subscribe(_:_:_:using:)."
      )
      loadError = error
      throw error
    }
    return try await subscribe(room: room, topic: topic, limit: configuration.limit, using: client)
  }

  public func subscribe(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(type, id, topic, limit: limit, using: client)
  }

  public func subscribe(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    try await subscribe(
      room: InstantRoomHandle(type: type, id: id),
      topic: topic,
      limit: limit,
      using: client
    )
  }

  public func subscribe(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(room: room, topic: topic, limit: limit, using: client)
  }

  public func subscribe(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    self.configuration.value = RoomTopicMessagesConfiguration(
      room: room,
      topic: topic,
      limit: limit
    )
    do {
      try Self.validateLimit(limit, operation: "subscribe RoomTopicMessages")
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeRoomTopicMessages(
        room: room,
        topic: topic,
        limit: limit
      )
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomTopicMessages",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room topic observer."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(type, id, topic, limit: limit, using: client)
  }

  public func task(
    _ type: String,
    _ id: String,
    _ topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    self.configuration.value = RoomTopicMessagesConfiguration(
      room: InstantRoomHandle(type: type, id: id),
      topic: topic,
      limit: limit
    )
    try await task(using: client)
  }

  public func task(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(room: room, topic: topic, limit: limit, using: client)
  }

  public func task(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    self.configuration.value = RoomTopicMessagesConfiguration(
      room: room,
      topic: topic,
      limit: limit
    )
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe RoomTopicMessages",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room topic observer."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  private static func validateLimit(_ limit: Int?, operation: String) throws {
    guard let limit, limit < 0 else { return }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Topic message limit must be greater than or equal to 0.",
      recovery: "Pass a non-negative limit, or omit limit to observe every local message."
    )
  }
}

@propertyWrapper
public struct StoredFiles: Sendable {
  private let storage: FetchStorage<[InstantStoredFile]>

  public var wrappedValue: [InstantStoredFile] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[InstantStoredFile]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [InstantStoredFile] = []) {
    self.storage = FetchStorage(value: wrappedValue)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let files = try await client.storedFiles()
      try Task.checkCancellation()
      wrappedValue = files
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load StoredFiles",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stored files operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe()
    async throws -> FetchSubscription<[InstantStoredFile]>
  {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStoredFile]> {
    do {
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeStoredFiles()
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe StoredFiles",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stored files observer."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe StoredFiles",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stored files observer."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }
}

private struct StreamChunksConfiguration: Sendable {
  var streamID: String?
  var limit: Int?
}

// SAFETY: stream chunk configuration is protected by `lock`.
private final class StreamChunksConfigurationStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var configuration: StreamChunksConfiguration

  init(streamID: String?, limit: Int?) {
    self.configuration = StreamChunksConfiguration(streamID: streamID, limit: limit)
  }

  var value: StreamChunksConfiguration {
    lock.lock()
    defer { lock.unlock() }
    return configuration
  }

  func set(_ configuration: StreamChunksConfiguration) {
    lock.lock()
    defer { lock.unlock() }
    self.configuration = configuration
  }

  func set(streamID: String, limit: Int?) {
    set(StreamChunksConfiguration(streamID: streamID, limit: limit))
  }
}

@propertyWrapper
public struct StreamChunks: Sendable {
  private let storage: FetchStorage<[InstantStreamChunk]>
  private let configuration: StreamChunksConfigurationStorage

  public var wrappedValue: [InstantStreamChunk] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[InstantStreamChunk]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [InstantStreamChunk] = []) {
    self.storage = FetchStorage(value: wrappedValue)
    self.configuration = StreamChunksConfigurationStorage(streamID: nil, limit: nil)
  }

  public init(_ streamID: String, limit: Int? = nil) {
    self.storage = FetchStorage(value: [])
    self.configuration = StreamChunksConfigurationStorage(streamID: streamID, limit: limit)
  }

  public init(wrappedValue: [InstantStreamChunk], _ streamID: String, limit: Int? = nil) {
    self.storage = FetchStorage(value: wrappedValue)
    self.configuration = StreamChunksConfigurationStorage(streamID: streamID, limit: limit)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      configuration.set(newValue.configuration.value)
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    let configuration = configuration.value
    guard let streamID = configuration.streamID else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load StreamChunks",
        message: "No Instant stream id has been configured for this wrapper.",
        recovery: "Initialize @StreamChunks with a stream id, or pass one to load(_:using:)."
      )
      loadError = error
      throw error
    }
    try await load(streamID, limit: configuration.limit, using: client)
  }

  public func load(_ streamID: String, limit: Int? = nil) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(streamID, limit: limit, using: client)
  }

  public func load(
    _ streamID: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    configuration.set(streamID: streamID, limit: limit)
    isLoading = true
    do {
      try Self.validateLimit(limit, operation: "load StreamChunks")
      let chunks = try await client.streamChunks(streamID: streamID, limit: limit)
      try Task.checkCancellation()
      wrappedValue = chunks
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load StreamChunks",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stream chunks operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe()
    async throws -> FetchSubscription<[InstantStreamChunk]>
  {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    let configuration = configuration.value
    guard let streamID = configuration.streamID else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe StreamChunks",
        message: "No Instant stream id has been configured for this wrapper.",
        recovery: "Initialize @StreamChunks with a stream id, or pass one to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }
    return try await subscribe(streamID, limit: configuration.limit, using: client)
  }

  public func subscribe(
    _ streamID: String,
    limit: Int? = nil
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(streamID, limit: limit, using: client)
  }

  public func subscribe(
    _ streamID: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    configuration.set(streamID: streamID, limit: limit)
    do {
      try Self.validateLimit(limit, operation: "subscribe StreamChunks")
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeStreamChunks(streamID: streamID, limit: limit)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe StreamChunks",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stream chunks observer."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(_ streamID: String, limit: Int? = nil) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(streamID, limit: limit, using: client)
  }

  public func task(
    _ streamID: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    configuration.set(streamID: streamID, limit: limit)
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe StreamChunks",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stream chunks observer."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  private static func validateLimit(_ limit: Int?, operation: String) throws {
    guard let limit, limit < 0 else { return }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Stream chunk limit must be greater than or equal to 0.",
      recovery: "Pass a non-negative limit, or omit limit to observe every local chunk."
    )
  }
}

@propertyWrapper
public struct Shares: Sendable {
  private let storage: FetchStorage<[InstantShareSnapshot]>

  public var wrappedValue: [InstantShareSnapshot] {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[InstantShareSnapshot]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [InstantShareSnapshot] = []) {
    self.storage = FetchStorage(value: wrappedValue)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let shares = try await client.shares()
      try Task.checkCancellation()
      wrappedValue = shares
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load Shares",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient shares operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe()
    async throws -> FetchSubscription<[InstantShareSnapshot]>
  {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantShareSnapshot]> {
    do {
      try Task.checkCancellation()
      loadError = nil
      return try await client.subscribeShares()
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe Shares",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient shares observer."
      )
      loadError = error
      throw error
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe Shares",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient shares observer."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }
}

@propertyWrapper
public struct LocalID: Sendable {
  private let storage: FetchStorage<String?>
  private let name: LockedValueStorage<String?>

  public var wrappedValue: String? {
    get { storage.wrappedValue }
    nonmutating set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    nonmutating set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    nonmutating set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<String?> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: String? = nil) {
    self.storage = FetchStorage(value: wrappedValue)
    self.name = LockedValueStorage(nil)
  }

  public init(_ name: String) {
    self.storage = FetchStorage(value: nil)
    self.name = LockedValueStorage(name)
  }

  public init(wrappedValue: String?, _ name: String) {
    self.storage = FetchStorage(value: wrappedValue)
    self.name = LockedValueStorage(name)
  }

  public init(wrappedValue: String? = nil, name: String) {
    self.storage = FetchStorage(value: wrappedValue)
    self.name = LockedValueStorage(name)
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      name.value = newValue.name.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let name = name.value else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load LocalID",
        message: "No Instant local ID name has been configured for this wrapper.",
        recovery: "Initialize @LocalID with a name, or pass a name to load(_:using:)."
      )
      loadError = error
      throw error
    }
    try await load(name, using: client)
  }

  public func load(_ name: String) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(name, using: client)
  }

  public func load(_ name: String, using client: InstantSwiftDataClient) async throws {
    self.name.value = name
    isLoading = true
    do {
      let value = try await client.localID(named: name)
      try Task.checkCancellation()
      wrappedValue = value
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load LocalID",
        path: name,
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient local ID operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func task() async throws {
    try await load()
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await load(using: client)
  }

  public func task(_ name: String) async throws {
    try await load(name)
  }

  public func task(_ name: String, using client: InstantSwiftDataClient) async throws {
    try await load(name, using: client)
  }
}
