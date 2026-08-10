@_exported public import InstantSwiftDataCore
import Dependencies
import Foundation
import IssueReporting

#if canImport(Observation)
  import Observation
#endif

#if canImport(SwiftUI)
  import Combine
  public import SwiftUI
#endif

@attached(member, names: named(instantNamespace), named(instantAttributes), named(Draft), arbitrary)
public macro InstantEntity(_ namespace: String? = nil) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantEntityMacro")

@attached(peer)
public macro InstantRelation(reverse: String, reverseMember: String? = nil) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantRelationMacro")

@attached(peer)
public macro InstantWire(_ valueType: InstantValueType) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantWireMacro")

public struct InstantSwiftDataClient: Sendable {
  public let runtime: InstantRuntime?
  fileprivate var supportsAutomaticFetchObservation = true

  private var transactOperation:
    @Sendable (InstantStoreTransaction) async throws -> InstantStoreMutationResult
  private var queryOnceOperation: @Sendable (InstantQueryPlan) async throws -> InstantQueryEmission
  private var queryOperation: @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot]
  private var observeOperation:
    @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>
  private var subscribeInfiniteQueryOperation:
    @Sendable (InstantQueryPlan) async -> InstantInfiniteQuerySubscription
  private var infiniteQueryInitialSnapshotOperation:
    @Sendable (InstantQueryPlan) async throws -> InstantInfiniteQuerySnapshot
  private var pendingMutationsOperation: @Sendable () async -> [PendingMutation]
  private var flushPendingMutationsOperation:
    @Sendable (Int?) async throws -> InstantMutationTransportFlushResult
  private var connectionStatusOperation: @Sendable () async throws -> InstantConnectionStatus
  private var observeConnectionStatusOperation:
    @Sendable () async throws -> AsyncStream<InstantConnectionStatus>
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
  private var signInWithMagicCodeResultOperation:
    @Sendable (String, String, [String: InstantValue]) async throws -> InstantMagicCodeSignInResult
  private var signInWithRefreshTokenOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var signInWithIDTokenOperation:
    @Sendable (String, String, String?) async throws -> InstantAuthSession
  private var signInWithOAuthOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var promoteGuestWithIDTokenOperation:
    @Sendable (String, String, String?) async throws -> InstantGuestPromotionResult
  private var promoteGuestWithOAuthOperation:
    @Sendable (String, String?) async throws -> InstantGuestPromotionResult
  private var oauthAuthorizationURLOperation: @Sendable (String, URL) throws -> URL
  private var issuerURIOperation: @Sendable () throws -> URL
  private var signOutOperation: @Sendable (Bool) async throws -> Void
  private var joinRoomOperation: @Sendable (InstantRoomHandle) async throws -> InstantRoomHandle
  private var leaveRoomOperation: @Sendable (InstantRoomHandle) async throws -> InstantRoomHandle
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
  private var storageSnapshotOperation: @Sendable () async throws -> InstantStorageSnapshot
  private var observeStoredFilesOperation:
    @Sendable () async throws -> AsyncStream<[InstantStoredFile]>
  private var storedFileContentsOperation:
    @Sendable (String, String?) async throws -> InstantStoredFileContents
  private var deleteStoredFileOperation: @Sendable (String) async throws -> InstantStoredFile
  private var appendStreamChunkOperation:
    @Sendable (String, JSONValue) async throws -> InstantStreamChunk
  private var streamChunksOperation:
    @Sendable (String, Int?, Int64?) async throws -> [InstantStreamChunk]
  private var observeStreamChunksOperation:
    @Sendable (String, Int64?) async throws -> AsyncStream<[InstantStreamChunk]>
  private var createStreamOperation: @Sendable (String) async throws -> InstantStreamMetadata
  private var streamMetadataByStreamIDOperation:
    @Sendable (String) async throws -> InstantStreamMetadata
  private var streamMetadataByClientIDOperation:
    @Sendable (String) async throws -> InstantStreamMetadata
  private var appendStreamContentOperation:
    @Sendable (String, String, Int64?) async throws -> InstantStreamContentAppend
  private var closeStreamOperation:
    @Sendable (String, String?) async throws -> InstantStreamMetadata
  private var streamContentByStreamIDOperation:
    @Sendable (String, Int64) async throws -> InstantStreamContentRead
  private var streamContentByClientIDOperation:
    @Sendable (String, Int64) async throws -> InstantStreamContentRead
  private var observeStreamContentByStreamIDOperation:
    @Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>
  private var observeStreamContentByClientIDOperation:
    @Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>
  private var createShareOperation: @Sendable (String, String) async throws -> InstantShareSnapshot
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
    self.subscribeInfiniteQueryOperation = { plan in
      await runtime.subscribeInfiniteQuery(plan)
    }
    self.infiniteQueryInitialSnapshotOperation = { plan in
      try await runtime.infiniteQueryInitialSnapshot(plan)
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
    self.observeConnectionStatusOperation = {
      try await runtime.observeConnectionStatus()
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
    self.signInWithMagicCodeResultOperation = { email, code, extraFields in
      try await runtime.signInWithMagicCodeResult(
        email: email,
        code: code,
        extraFields: extraFields
      )
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
    self.promoteGuestWithIDTokenOperation = { clientName, idToken, nonce in
      InstantGuestPromotionResult(
        try await runtime.promoteGuestWithIDToken(
          clientName: clientName,
          idToken: idToken,
          nonce: nonce
        )
      )
    }
    self.promoteGuestWithOAuthOperation = { code, codeVerifier in
      InstantGuestPromotionResult(
        try await runtime.promoteGuestWithOAuth(
          code: code,
          codeVerifier: codeVerifier
        )
      )
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
    self.joinRoomOperation = { room in
      try await runtime.joinRoom(room)
    }
    self.leaveRoomOperation = { room in
      try await runtime.leaveRoom(room)
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
    self.storageSnapshotOperation = {
      try await runtime.storageSnapshot()
    }
    self.observeStoredFilesOperation = {
      try await runtime.observeStoredFiles()
    }
    self.storedFileContentsOperation = { id, name in
      try await runtime.storedFileContents(id: id, name: name)
    }
    self.deleteStoredFileOperation = { id in
      try await runtime.deleteStoredFile(id: id)
    }
    self.appendStreamChunkOperation = { streamID, payload in
      try await runtime.appendStreamChunk(streamID: streamID, payload: payload)
    }
    self.streamChunksOperation = { streamID, limit, afterIndex in
      try await runtime.streamChunks(streamID: streamID, limit: limit, afterIndex: afterIndex)
    }
    self.observeStreamChunksOperation = { streamID, afterIndex in
      try await runtime.observeStreamChunks(streamID: streamID, afterIndex: afterIndex)
    }
    self.createStreamOperation = { clientID in
      try await runtime.createStream(clientID: clientID)
    }
    self.streamMetadataByStreamIDOperation = { streamID in
      try await runtime.streamMetadata(streamID: streamID)
    }
    self.streamMetadataByClientIDOperation = { clientID in
      try await runtime.streamMetadata(clientID: clientID)
    }
    self.appendStreamContentOperation = { streamID, content, expectedOffset in
      try await runtime.appendStreamContent(
        streamID: streamID,
        content: content,
        expectedOffset: expectedOffset
      )
    }
    self.closeStreamOperation = { streamID, abortReason in
      try await runtime.closeStream(streamID: streamID, abortReason: abortReason)
    }
    self.streamContentByStreamIDOperation = { streamID, byteOffset in
      try await runtime.streamContent(streamID: streamID, byteOffset: byteOffset)
    }
    self.streamContentByClientIDOperation = { clientID, byteOffset in
      try await runtime.streamContent(clientID: clientID, byteOffset: byteOffset)
    }
    self.observeStreamContentByStreamIDOperation = { streamID, byteOffset in
      try await runtime.observeStreamContent(streamID: streamID, byteOffset: byteOffset)
    }
    self.observeStreamContentByClientIDOperation = { clientID, byteOffset in
      try await runtime.observeStreamContent(clientID: clientID, byteOffset: byteOffset)
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

  /// Returns a read-only client facet that serves ordinary queries and observations from the
  /// already-bootstrapped local runtime without requiring a live server acknowledgement.
  ///
  /// Inject this facet at a composition boundary for startup, preview, or diagnostic reads that
  /// explicitly accept last-known local state. Mutations and remote capabilities are unavailable.
  public func localReader() throws -> Self {
    guard let runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "create local InstantSwiftData reader",
        message: "A local reader requires a bootstrapped Instant runtime.",
        recovery: "Bootstrap InstantSwiftDataClient before deriving its local reader facet."
      )
    }
    let readOnlyError = InstantError(
      code: .implementationFailed,
      operation: "mutate through local InstantSwiftData reader",
      message: "The local reader facet does not support mutations.",
      recovery: "Use the ordinary injected client for mutations and remote capabilities."
    )
    return Self(
      transact: { _ in throw readOnlyError },
      queryOnce: { plan in
        try await runtime.queryLocally(plan)
      },
      query: { plan in
        try await runtime.queryLocally(plan).values
      },
      observe: { plan in
        await runtime.observeLocally(plan)
      },
      pendingMutations: {
        await runtime.pendingMutations()
      },
      localID: { name in
        try await runtime.localID(named: name)
      }
    )
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    subscribeInfiniteQuery:
      (@Sendable (InstantQueryPlan) async -> InstantInfiniteQuerySubscription)? = nil,
    infiniteQueryInitialSnapshot:
      (@Sendable (InstantQueryPlan) async throws -> InstantInfiniteQuerySnapshot)? = nil,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    observeConnectionStatus:
      (@Sendable () async throws -> AsyncStream<InstantConnectionStatus>)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithMagicCodeResult:
      (
        @Sendable (String, String, [String: InstantValue]) async throws
          -> InstantMagicCodeSignInResult
      )? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    promoteGuestWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantGuestPromotionResult)? = nil,
    promoteGuestWithOAuth:
      (@Sendable (String, String?) async throws -> InstantGuestPromotionResult)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil,
    joinRoom: (@Sendable (InstantRoomHandle) async throws -> InstantRoomHandle)? = nil,
    leaveRoom: (@Sendable (InstantRoomHandle) async throws -> InstantRoomHandle)? = nil,
    setRoomPresence:
      (
        @Sendable (InstantRoomHandle, String?, [String: JSONValue]) async throws
          -> InstantRoomPresenceMember
      )? = nil,
    roomPresence:
      (@Sendable (InstantRoomHandle) async throws -> [InstantRoomPresenceMember])? = nil,
    observeRoomPresence:
      (@Sendable (InstantRoomHandle) async throws -> AsyncStream<[InstantRoomPresenceMember]>)? =
      nil,
    leaveRoomPresence: (@Sendable (InstantRoomHandle, String?) async throws -> String)? = nil,
    publishRoomTopicMessage:
      (
        @Sendable (InstantRoomHandle, String, String?, JSONValue) async throws
          -> InstantRoomTopicMessage
      )? = nil,
    roomTopicMessages:
      (
        @Sendable (InstantRoomHandle, String, Int?) async throws
          -> [InstantRoomTopicMessage]
      )? = nil,
    observeRoomTopicMessages:
      (
        @Sendable (InstantRoomHandle, String) async throws
          -> AsyncStream<[InstantRoomTopicMessage]>
      )? = nil,
    uploadFile:
      (@Sendable (URL, String?, String?) async throws -> InstantStoredFile)? = nil,
    uploadFileProgress:
      (
        @Sendable (URL, String?, String?) async throws
          -> AsyncThrowingStream<InstantFileUploadProgress, Error>
      )? = nil,
    storedFiles: (@Sendable () async throws -> [InstantStoredFile])? = nil,
    storageSnapshot: (@Sendable () async throws -> InstantStorageSnapshot)? = nil,
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
    streamChunksAfterIndex:
      (@Sendable (String, Int?, Int64?) async throws -> [InstantStreamChunk])? = nil,
    observeStreamChunksAfterIndex:
      (@Sendable (String, Int64?) async throws -> AsyncStream<[InstantStreamChunk]>)? = nil,
    createStream:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    streamMetadataByStreamID:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    streamMetadataByClientID:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    appendStreamContent:
      (@Sendable (String, String, Int64?) async throws -> InstantStreamContentAppend)? = nil,
    closeStream:
      (@Sendable (String, String?) async throws -> InstantStreamMetadata)? = nil,
    streamContentByStreamID:
      (@Sendable (String, Int64) async throws -> InstantStreamContentRead)? = nil,
    streamContentByClientID:
      (@Sendable (String, Int64) async throws -> InstantStreamContentRead)? = nil,
    observeStreamContentByStreamID:
      (@Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>)? = nil,
    observeStreamContentByClientID:
      (@Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>)? = nil,
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
      subscribeInfiniteQuery: subscribeInfiniteQuery,
      infiniteQueryInitialSnapshot: infiniteQueryInitialSnapshot,
      pendingMutations: pendingMutations,
      flushPendingMutations: flushPendingMutations,
      connectionStatus: connectionStatus,
      observeConnectionStatus: observeConnectionStatus,
      connect: connect,
      closeConnection: closeConnection,
      localID: localID,
      authSession: authSession,
      observeAuthSession: observeAuthSession,
      signInAsGuest: signInAsGuest,
      sendMagicCode: sendMagicCode,
      signInWithMagicCode: signInWithMagicCode,
      signInWithMagicCodeResult: signInWithMagicCodeResult,
      signInWithRefreshToken: signInWithRefreshToken,
      oauthAuthorizationURL: nil,
      issuerURI: nil,
      signOut: signOut,
      signInWithIDToken: signInWithIDToken,
      signInWithOAuth: signInWithOAuth,
      promoteGuestWithIDToken: promoteGuestWithIDToken,
      promoteGuestWithOAuth: promoteGuestWithOAuth,
      signOutWithOptions: signOutWithOptions,
      joinRoom: joinRoom,
      leaveRoom: leaveRoom,
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
      storageSnapshot: storageSnapshot,
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

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    subscribeInfiniteQuery:
      (@Sendable (InstantQueryPlan) async -> InstantInfiniteQuerySubscription)? = nil,
    infiniteQueryInitialSnapshot:
      (@Sendable (InstantQueryPlan) async throws -> InstantInfiniteQuerySnapshot)? = nil,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    observeConnectionStatus:
      (@Sendable () async throws -> AsyncStream<InstantConnectionStatus>)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithMagicCodeResult:
      (
        @Sendable (String, String, [String: InstantValue]) async throws
          -> InstantMagicCodeSignInResult
      )? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    oauthAuthorizationURL: (@Sendable (String, URL) throws -> URL)? = nil,
    issuerURI: (@Sendable () throws -> URL)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    promoteGuestWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantGuestPromotionResult)? = nil,
    promoteGuestWithOAuth:
      (@Sendable (String, String?) async throws -> InstantGuestPromotionResult)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil,
    joinRoom: (@Sendable (InstantRoomHandle) async throws -> InstantRoomHandle)? = nil,
    leaveRoom: (@Sendable (InstantRoomHandle) async throws -> InstantRoomHandle)? = nil,
    setRoomPresence:
      (
        @Sendable (InstantRoomHandle, String?, [String: JSONValue]) async throws
          -> InstantRoomPresenceMember
      )? = nil,
    roomPresence:
      (@Sendable (InstantRoomHandle) async throws -> [InstantRoomPresenceMember])? = nil,
    observeRoomPresence:
      (@Sendable (InstantRoomHandle) async throws -> AsyncStream<[InstantRoomPresenceMember]>)? =
      nil,
    leaveRoomPresence: (@Sendable (InstantRoomHandle, String?) async throws -> String)? = nil,
    publishRoomTopicMessage:
      (
        @Sendable (InstantRoomHandle, String, String?, JSONValue) async throws
          -> InstantRoomTopicMessage
      )? = nil,
    roomTopicMessages:
      (
        @Sendable (InstantRoomHandle, String, Int?) async throws
          -> [InstantRoomTopicMessage]
      )? = nil,
    observeRoomTopicMessages:
      (
        @Sendable (InstantRoomHandle, String) async throws
          -> AsyncStream<[InstantRoomTopicMessage]>
      )? = nil,
    uploadFile:
      (@Sendable (URL, String?, String?) async throws -> InstantStoredFile)? = nil,
    uploadFileProgress:
      (
        @Sendable (URL, String?, String?) async throws
          -> AsyncThrowingStream<InstantFileUploadProgress, Error>
      )? = nil,
    storedFiles: (@Sendable () async throws -> [InstantStoredFile])? = nil,
    storageSnapshot: (@Sendable () async throws -> InstantStorageSnapshot)? = nil,
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
    streamChunksAfterIndex:
      (@Sendable (String, Int?, Int64?) async throws -> [InstantStreamChunk])? = nil,
    observeStreamChunksAfterIndex:
      (@Sendable (String, Int64?) async throws -> AsyncStream<[InstantStreamChunk]>)? = nil,
    createStream:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    streamMetadataByStreamID:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    streamMetadataByClientID:
      (@Sendable (String) async throws -> InstantStreamMetadata)? = nil,
    appendStreamContent:
      (@Sendable (String, String, Int64?) async throws -> InstantStreamContentAppend)? = nil,
    closeStream:
      (@Sendable (String, String?) async throws -> InstantStreamMetadata)? = nil,
    streamContentByStreamID:
      (@Sendable (String, Int64) async throws -> InstantStreamContentRead)? = nil,
    streamContentByClientID:
      (@Sendable (String, Int64) async throws -> InstantStreamContentRead)? = nil,
    observeStreamContentByStreamID:
      (@Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>)? = nil,
    observeStreamContentByClientID:
      (@Sendable (String, Int64) async throws -> AsyncStream<InstantStreamContentRead>)? = nil,
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
      recovery:
        "Bootstrap Instant Swift Data before using auth, or override auth closures in tests."
    )
    let guestPromotionError = InstantError(
      code: .implementationFailed,
      operation: "promote guest account",
      message: "No atomic guest-promotion client has been configured.",
      recovery:
        "Bootstrap a runtime-backed InstantSwiftDataClient or inject the guest-promotion operations in tests and previews."
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
    let infiniteQueryError = InstantError(
      code: .implementationFailed,
      operation: "subscribe InfiniteQuery",
      message: "No infinite query client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before subscribing to infinite queries, or override the infinite query closures in tests."
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
    self.subscribeInfiniteQueryOperation =
      subscribeInfiniteQuery
      ?? { plan in Self.failedInfiniteQuerySubscription(error: infiniteQueryError, queryID: plan.id)
      }
    self.infiniteQueryInitialSnapshotOperation =
      infiniteQueryInitialSnapshot ?? { _ in throw infiniteQueryError }
    self.pendingMutationsOperation = pendingMutations
    self.flushPendingMutationsOperation = flushPendingMutations ?? { _ in throw transportError }
    self.connectionStatusOperation = connectionStatus ?? { throw runtimeStatusError }
    self.observeConnectionStatusOperation = observeConnectionStatus ?? { throw runtimeStatusError }
    self.connectOperation = connect ?? { throw runtimeStatusError }
    self.closeConnectionOperation = closeConnection ?? { throw runtimeStatusError }
    self.localIDOperation = localID
    self.authSessionOperation = authSession ?? { throw authError }
    self.observeAuthSessionOperation = observeAuthSession ?? { throw authError }
    self.signInAsGuestOperation = signInAsGuest ?? { throw authError }
    self.sendMagicCodeOperation = sendMagicCode ?? { _ in throw authError }
    if let signInWithMagicCode {
      self.signInWithMagicCodeOperation = signInWithMagicCode
    } else if let signInWithMagicCodeResult {
      self.signInWithMagicCodeOperation = { email, code in
        try await signInWithMagicCodeResult(email, code, [:]).session
      }
    } else {
      self.signInWithMagicCodeOperation = { _, _ in throw authError }
    }
    if let signInWithMagicCodeResult {
      self.signInWithMagicCodeResultOperation = signInWithMagicCodeResult
    } else if let signInWithMagicCode {
      self.signInWithMagicCodeResultOperation = { email, code, extraFields in
        guard extraFields.isEmpty else {
          throw InstantError(
            code: .implementationFailed,
            operation: "sign in with magic code",
            message:
              "The configured InstantSwiftData client does not support magic-code extra fields.",
            recovery:
              "Override signInWithMagicCodeResult in tests or bootstrap a runtime-backed client before passing extra fields."
          )
        }
        return InstantMagicCodeSignInResult(
          session: try await signInWithMagicCode(email, code),
          created: false
        )
      }
    } else {
      self.signInWithMagicCodeResultOperation = { _, _, _ in throw authError }
    }
    self.signInWithRefreshTokenOperation = signInWithRefreshToken ?? { _, _ in throw authError }
    self.signInWithIDTokenOperation = signInWithIDToken ?? { _, _, _ in throw authError }
    self.signInWithOAuthOperation = signInWithOAuth ?? { _, _ in throw authError }
    self.promoteGuestWithIDTokenOperation =
      promoteGuestWithIDToken ?? { _, _, _ in throw guestPromotionError }
    self.promoteGuestWithOAuthOperation =
      promoteGuestWithOAuth ?? { _, _ in throw guestPromotionError }
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
    self.joinRoomOperation = joinRoom ?? { _ in throw roomsError }
    self.leaveRoomOperation = leaveRoom ?? { _ in throw roomsError }
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
    self.storageSnapshotOperation = storageSnapshot ?? { throw filesError }
    self.observeStoredFilesOperation = observeStoredFiles ?? { throw filesError }
    self.storedFileContentsOperation = { id, _ in
      guard let storedFileContents else { throw filesError }
      return try await storedFileContents(id)
    }
    self.deleteStoredFileOperation = deleteStoredFile ?? { _ in throw filesError }
    self.appendStreamChunkOperation = appendStreamChunk ?? { _, _ in throw streamsError }
    if let streamChunksAfterIndex {
      self.streamChunksOperation = streamChunksAfterIndex
    } else if let streamChunks {
      self.streamChunksOperation = { streamID, limit, afterIndex in
        let chunks = try await streamChunks(streamID, afterIndex == nil ? limit : nil)
        return Self.streamChunks(chunks, limit: limit, afterIndex: afterIndex)
      }
    } else {
      self.streamChunksOperation = { _, _, _ in throw streamsError }
    }
    if let observeStreamChunksAfterIndex {
      self.observeStreamChunksOperation = observeStreamChunksAfterIndex
    } else if let observeStreamChunks {
      self.observeStreamChunksOperation = { streamID, afterIndex in
        let stream = try await observeStreamChunks(streamID)
        guard let afterIndex else { return stream }
        return Self.streamChunks(after: afterIndex, from: stream)
      }
    } else {
      self.observeStreamChunksOperation = { _, _ in throw streamsError }
    }
    self.createStreamOperation = createStream ?? { _ in throw streamsError }
    self.streamMetadataByStreamIDOperation = streamMetadataByStreamID ?? { _ in throw streamsError }
    self.streamMetadataByClientIDOperation = streamMetadataByClientID ?? { _ in throw streamsError }
    self.appendStreamContentOperation = appendStreamContent ?? { _, _, _ in throw streamsError }
    self.closeStreamOperation = closeStream ?? { _, _ in throw streamsError }
    self.streamContentByStreamIDOperation =
      streamContentByStreamID ?? { _, _ in throw streamsError }
    self.streamContentByClientIDOperation =
      streamContentByClientID ?? { _, _ in throw streamsError }
    self.observeStreamContentByStreamIDOperation =
      observeStreamContentByStreamID ?? { _, _ in throw streamsError }
    self.observeStreamContentByClientIDOperation =
      observeStreamContentByClientID ?? { _, _ in throw streamsError }
    self.createShareOperation = createShare ?? { _, _ in throw sharesError }
    self.acceptShareOperation = acceptShare ?? { _ in throw sharesError }
    self.sharesOperation = shares ?? { throw sharesError }
    self.observeSharesOperation = observeShares ?? { throw sharesError }
    self.updateShareMembershipRoleOperation =
      updateShareMembershipRole ?? { _, _, _ in throw sharesError }
    self.revokeShareOperation = revokeShare ?? { _ in throw sharesError }
  }

  private static func streamChunks(
    _ chunks: [InstantStreamChunk],
    limit: Int?,
    afterIndex: Int64?
  ) -> [InstantStreamChunk] {
    let resumed =
      afterIndex.map { index in
        chunks.filter { $0.index > index }
      } ?? chunks
    if let limit {
      return Array(resumed.prefix(limit))
    }
    return resumed
  }

  private static func streamChunks(
    after afterIndex: Int64,
    from stream: AsyncStream<[InstantStreamChunk]>
  ) -> AsyncStream<[InstantStreamChunk]> {
    let mapped = AsyncStream<[InstantStreamChunk]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let task = Task {
      for await chunks in stream {
        mapped.continuation.yield(streamChunks(chunks, limit: nil, afterIndex: afterIndex))
      }
      mapped.continuation.finish()
    }
    mapped.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return mapped.stream
  }

  public static func unimplemented(_ message: String) -> Self {
    let error = InstantError(
      code: .implementationFailed,
      operation: "access default InstantSwiftData client",
      message: message,
      recovery:
        "Bootstrap Instant Swift Data before reading the dependency, or override it in tests."
    )

    var client = Self(
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
      observeConnectionStatus: {
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
      promoteGuestWithIDToken: { _, _, _ in
        throw error
      },
      promoteGuestWithOAuth: { _, _ in
        throw error
      },
      signOutWithOptions: { _ in
        throw error
      },
      joinRoom: { _ in
        throw error
      },
      leaveRoom: { _ in
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
      streamChunksAfterIndex: { _, _, _ in
        throw error
      },
      observeStreamChunksAfterIndex: { _, _ in
        throw error
      },
      createStream: { _ in
        throw error
      },
      streamMetadataByStreamID: { _ in
        throw error
      },
      streamMetadataByClientID: { _ in
        throw error
      },
      appendStreamContent: { _, _, _ in
        throw error
      },
      closeStream: { _, _ in
        throw error
      },
      streamContentByStreamID: { _, _ in
        throw error
      },
      streamContentByClientID: { _, _ in
        throw error
      },
      observeStreamContentByStreamID: { _, _ in
        throw error
      },
      observeStreamContentByClientID: { _, _ in
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
    client.supportsAutomaticFetchObservation = false
    return client
  }

  private static func failedInfiniteQuerySubscription(
    error: InstantError,
    queryID: String
  ) -> InstantInfiniteQuerySubscription {
    let stream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    stream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: queryID,
        sequence: 0,
        values: [],
        canLoadNextPage: false,
        error: error
      )
    )
    stream.continuation.finish()
    return InstantInfiniteQuerySubscription(
      snapshots: stream.stream,
      loadNextPage: {},
      unsubscribe: {}
    )
  }

  public static func bootstrap(configuration: InstantRuntimeConfiguration) async throws -> Self {
    try await bootstrap(configuration: configuration, storageTransport: nil)
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration,
    storageTransport: InstantStorageTransportClient?
  ) async throws -> Self {
    try await Self(
      runtime: InstantRuntime.bootstrap(
        configuration: configuration,
        storageTransport: storageTransport
      )
    )
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

  public func subscribeInfiniteQuery(
    _ plan: InstantQueryPlan
  ) async -> InstantInfiniteQuerySubscription {
    await subscribeInfiniteQueryOperation(plan)
  }

  public func infiniteQueryInitialSnapshot(
    _ plan: InstantQueryPlan
  ) async throws -> InstantInfiniteQuerySnapshot {
    try await infiniteQueryInitialSnapshotOperation(plan)
  }

  public func pendingMutations() async -> [PendingMutation] {
    await pendingMutationsOperation()
  }

  /// Returns the number of durable pending mutations without decoding their
  /// transaction and rollback operation graphs on runtime-backed clients.
  public func pendingMutationCount() async -> Int {
    if let runtime {
      return await runtime.pendingMutationCount()
    }
    return await pendingMutationsOperation().count
  }

  public func failedMutations() async throws -> [PendingMutation] {
    guard let runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "list failed Instant mutations",
        message: "This Instant Swift Data client has no runtime outbox lifecycle.",
        recovery: "Use a runtime-backed client to inspect retained failed mutations."
      )
    }
    return await runtime.failedMutations()
  }

  @discardableResult
  public func retryFailedMutation(id: String) async throws -> InstantFailedMutationResolution {
    guard let runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "retry failed Instant mutation",
        localID: id,
        message: "This Instant Swift Data client has no runtime outbox lifecycle.",
        recovery: "Use a runtime-backed client to retry retained failed mutations."
      )
    }
    let mutation = try await runtime.retryFailedMutation(id: id)
    return InstantFailedMutationResolution(
      mutation: mutation,
      localStateDisposition: .retainedForRetry
    )
  }

  @discardableResult
  public func discardFailedMutation(id: String) async throws -> InstantFailedMutationResolution {
    guard let runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "discard failed Instant mutation",
        localID: id,
        message: "This Instant Swift Data client has no runtime outbox lifecycle.",
        recovery: "Use a runtime-backed client to discard retained failed mutations."
      )
    }
    do {
      let mutation = try await runtime.discardFailedMutation(id: id)
      return InstantFailedMutationResolution(
        mutation: mutation,
        localStateDisposition: .discarded
      )
    } catch var error as InstantError {
      if error.localMutationDisposition == nil {
        error.localMutationDisposition = .retainedUnknown
      }
      throw error
    }
  }

  /// Waits until every locally persisted mutation has been acknowledged by the live server.
  ///
  /// Transactions remain local-first: this method does not block `transact`. It is intended for
  /// short-lived tools and explicit durability boundaries that must remain alive until another
  /// client can observe the final mutation. Unlike `flushPendingMutations`, this does not invoke a
  /// separately configured mutation transport or locally confirm the outbox.
  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  public func waitForAllPendingMutations(
    timeout: Duration = .seconds(10),
    pollInterval: Duration = .milliseconds(50)
  ) async throws {
    guard timeout >= .zero else {
      throw InstantError(
        code: .validationFailed,
        operation: "wait for pending mutations",
        message: "The delivery timeout must be greater than or equal to zero.",
        recovery: "Pass a non-negative timeout."
      )
    }
    guard pollInterval >= .zero else {
      throw InstantError(
        code: .validationFailed,
        operation: "wait for pending mutations",
        message: "The delivery poll interval must be greater than or equal to zero.",
        recovery: "Pass a non-negative poll interval."
      )
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data",
      category: "outbox",
      event: "outbox.wait-all.started",
      message: "Waiting for every pending Instant outbox mutation to be server-accepted.",
      metadata: [
        "timeout": String(describing: timeout),
        "pollInterval": String(describing: pollInterval),
      ]
    )
    while true {
      try Task.checkCancellation()
      let barrier: InstantMutationDeliveryBarrierSummary
      if let runtime {
        barrier = try await runtime.mutationDeliveryBarrierSummary()
      } else {
        let mutations = await pendingMutations()
        let outstanding = mutations.filter { mutation in
          mutation.status == .pending
            || (mutation.status == .confirmed && !mutation.provesServerAcceptance)
        }
        barrier = InstantMutationDeliveryBarrierSummary(
          outstandingMutationCount: outstanding.count,
          firstOutstandingMutationID: outstanding.first?.id,
          firstOutstandingIsLocalOnlyConfirmation: outstanding.first?.status == .confirmed,
          sampleOutstandingMutationIDs: outstanding.prefix(8).map(\.id),
          firstFailedMutation: mutations.first(where: { $0.status == .failed })
        )
      }
      if let failed = barrier.firstFailedMutation {
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data",
          category: "outbox",
          event: "outbox.wait-all.failed-mutation",
          message: "waitForAllPendingMutations hit a failed outbox mutation.",
          metadata: [
            "mutationID": failed.id,
            "failureMessage": failed.failureMessage ?? "",
            "pendingCount": String(barrier.outstandingMutationCount),
          ],
          correlationID: failed.id
        )
        throw failed.rejectionError(
          operation: "wait for pending mutations",
          recovery: "Inspect the failed outbox mutation before retrying or discarding it."
        )
      }
      guard barrier.outstandingMutationCount > 0 else {
        InstantDiagnostics.shared.record(
          .info,
          subsystem: "instant-swift-data",
          category: "outbox",
          event: "outbox.wait-all.completed",
          message: "All pending Instant outbox mutations are server-accepted.",
          metadata: [:]
        )
        return
      }

      let status = try await connectionStatus()
      switch status.state {
      case .closed:
        _ = try await connect()
      case .errored:
        throw InstantError(
          code: .networkFailed,
          operation: "wait for pending mutations",
          message:
            status.lastErrorMessage
            ?? "The live Instant connection failed with \(barrier.outstandingMutationCount) unacknowledged mutation(s).",
          recovery: "Reconnect and retry after inspecting the live transport error."
        )
      case .connecting:
        break
      case .opened, .authenticated:
        runtime?.requestLiveMutationDelivery()
      }

      guard clock.now < deadline else {
        let message: String
        if barrier.firstOutstandingIsLocalOnlyConfirmation,
          let mutationID = barrier.firstOutstandingMutationID
        {
          message =
            "Mutation '\(mutationID)' was confirmed only by a local source, "
            + "not by the Instant server before the delivery timeout."
        } else {
          message =
            "Timed out waiting for \(barrier.outstandingMutationCount) mutation(s) to be acknowledged by Instant."
        }
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data",
          category: "outbox",
          event: "outbox.wait-all.timeout",
          message: message,
          metadata: [
            "outstandingCount": String(barrier.outstandingMutationCount),
            "connectionState": status.state.rawValue,
            "pendingMutationCount": String(status.pendingMutationCount),
            "sampleMutationIDs": barrier.sampleOutstandingMutationIDs.joined(separator: ","),
            "timeout": String(describing: timeout),
          ]
        )
        throw InstantError(
          code: .networkFailed,
          operation: "wait for pending mutations",
          localID: barrier.firstOutstandingIsLocalOnlyConfirmation
            ? barrier.firstOutstandingMutationID
            : nil,
          message: message,
          recovery: "Keep the process alive longer or inspect the live Instant connection."
        )
      }
      try await clock.sleep(for: pollInterval)
    }
  }

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    try await flushPendingMutationsOperation(limit)
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    try await connectionStatusOperation()
  }

  public func observeConnectionStatus() async throws -> AsyncStream<InstantConnectionStatus> {
    try await observeConnectionStatusOperation()
  }

  public func subscribeConnectionStatus() async throws -> FetchSubscription<InstantConnectionStatus>
  {
    let statuses = try await observeConnectionStatus()
    try Task.checkCancellation()
    return fetchSubscription(from: statuses)
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

  /// Stable Instant client id for this device + app install (ADR 0015 Q23).
  ///
  /// Resolves Instant TS `getLocalId` for ``InstantClientID/name`` (local SQLite
  /// actor hop — not network). Caches into ``InstantClientID/current`` so
  /// product code can read **synchronously** afterward:
  /// ```swift
  /// // Once at bootstrap / after auth:
  /// _ = try await client.clientID()
  ///
  /// // Anywhere later (views, reducers) — no await:
  /// let local = InstantClientID.requireCurrent()
  /// InstantClientID.isThisClient(activityClientID: activity.clientId)
  /// ```
  public func clientID() async throws -> String {
    if let runtime {
      return try await runtime.clientID()
    }
    let id = try await localID(named: InstantClientID.name)
    InstantClientID.prepareCurrent(id)
    return id
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

  public func signInWithMagicCodeResult(
    email: String,
    code: String,
    extraFields: [String: InstantValue] = [:]
  ) async throws -> InstantMagicCodeSignInResult {
    try await signInWithMagicCodeResultOperation(email, code, extraFields)
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

  func performGuestPromotionWithIDToken(
    clientName: String,
    idToken: String,
    nonce: String?
  ) async throws -> InstantGuestPromotionResult {
    try await promoteGuestWithIDTokenOperation(clientName, idToken, nonce)
  }

  func performGuestPromotionWithOAuth(
    code: String,
    codeVerifier: String?
  ) async throws -> InstantGuestPromotionResult {
    try await promoteGuestWithOAuthOperation(code, codeVerifier)
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
  public func joinRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    try await joinRoomOperation(room)
  }

  @discardableResult
  public func leaveRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    try await leaveRoomOperation(room)
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

  public func storageSnapshot() async throws -> InstantStorageSnapshot {
    try await storageSnapshotOperation()
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
    try await storedFileContentsOperation(id, nil)
  }

  public func storedFileContents(
    id: String,
    name: String
  ) async throws -> InstantStoredFileContents {
    try await storedFileContentsOperation(id, name)
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
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) async throws -> [InstantStreamChunk] {
    try validateNonNegativeIndex(
      afterIndex,
      operation: "read stream chunks",
      subject: "Stream chunk"
    )
    return try await streamChunksOperation(streamID, limit, afterIndex)
  }

  public func observeStreamChunks(
    streamID: String,
    afterIndex: Int64? = nil
  ) async throws -> AsyncStream<[InstantStreamChunk]> {
    try validateNonNegativeIndex(
      afterIndex,
      operation: "observe stream chunks",
      subject: "Stream chunk"
    )
    return try await observeStreamChunksOperation(streamID, afterIndex)
  }

  public func subscribeStreamChunks(
    streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    try validateNonNegativeLimit(
      limit,
      operation: "subscribe stream chunks",
      subject: "Stream chunk"
    )
    try validateNonNegativeIndex(
      afterIndex,
      operation: "subscribe stream chunks",
      subject: "Stream chunk"
    )
    let chunks = try await observeStreamChunks(streamID: streamID, afterIndex: afterIndex)
    try Task.checkCancellation()
    let subscription = fetchSubscription(from: chunks)
    if let limit {
      return subscription.map { Array($0.prefix(limit)) }
    }
    return subscription
  }

  @discardableResult
  public func createStream(clientID: String) async throws -> InstantStreamMetadata {
    try await createStreamOperation(clientID)
  }

  public func streamMetadata(streamID: String) async throws -> InstantStreamMetadata {
    try await streamMetadataByStreamIDOperation(streamID)
  }

  public func streamMetadata(clientID: String) async throws -> InstantStreamMetadata {
    try await streamMetadataByClientIDOperation(clientID)
  }

  @discardableResult
  public func appendStreamContent(
    streamID: String,
    content: String,
    expectedOffset: Int64? = nil
  ) async throws -> InstantStreamContentAppend {
    try validateNonNegativeByteOffset(
      expectedOffset,
      operation: "append stream content"
    )
    return try await appendStreamContentOperation(streamID, content, expectedOffset)
  }

  @discardableResult
  public func closeStream(
    streamID: String,
    abortReason: String? = nil
  ) async throws -> InstantStreamMetadata {
    try await closeStreamOperation(streamID, abortReason)
  }

  public func streamContent(
    streamID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    try validateNonNegativeByteOffset(byteOffset, operation: "read stream content")
    return try await streamContentByStreamIDOperation(streamID, byteOffset)
  }

  public func streamContent(
    clientID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    try validateNonNegativeByteOffset(byteOffset, operation: "read stream content")
    return try await streamContentByClientIDOperation(clientID, byteOffset)
  }

  public func observeStreamContent(
    streamID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    try validateNonNegativeByteOffset(byteOffset, operation: "observe stream content")
    return try await observeStreamContentByStreamIDOperation(streamID, byteOffset)
  }

  public func observeStreamContent(
    clientID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    try validateNonNegativeByteOffset(byteOffset, operation: "observe stream content")
    return try await observeStreamContentByClientIDOperation(clientID, byteOffset)
  }

  public func subscribeStreamContent(
    streamID: String,
    byteOffset: Int64 = 0
  ) async throws -> FetchSubscription<InstantStreamContentRead> {
    try validateNonNegativeByteOffset(byteOffset, operation: "subscribe stream content")
    let content = try await observeStreamContent(streamID: streamID, byteOffset: byteOffset)
    try Task.checkCancellation()
    return fetchSubscription(from: content)
  }

  public func subscribeStreamContent(
    clientID: String,
    byteOffset: Int64 = 0
  ) async throws -> FetchSubscription<InstantStreamContentRead> {
    try validateNonNegativeByteOffset(byteOffset, operation: "subscribe stream content")
    let content = try await observeStreamContent(clientID: clientID, byteOffset: byteOffset)
    try Task.checkCancellation()
    return fetchSubscription(from: content)
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

/// Algebraic load surface for infinite queries (TanStack-shaped).
///
/// Prefer this over parallel bool soup (`isLoading` + `canLoadNextPage` + empty
/// rows). Impossible combos such as "loading next page with no first page and
/// no failure" are unrepresentable.
public enum InfiniteQueryPhase: Equatable, Sendable {
  case idleEmpty
  case loadingFirstPage
  case loaded(canLoadNextPage: Bool)
  case loadingNextPage(canLoadNextPage: Bool)
  case failed(InstantError, hadRows: Bool)
}

public struct InfiniteQuerySnapshot<Element: Sendable>: Sendable {
  public var queryID: String
  public var sequence: Int64
  public var values: [Element]
  public var pageInfo: InstantQueryPageInfo?
  public var canLoadNextPage: Bool
  public var error: InstantError?

  public init(
    queryID: String,
    sequence: Int64,
    values: [Element],
    pageInfo: InstantQueryPageInfo? = nil,
    canLoadNextPage: Bool,
    error: InstantError? = nil
  ) {
    self.queryID = queryID
    self.sequence = sequence
    self.values = values
    self.pageInfo = pageInfo
    self.canLoadNextPage = canLoadNextPage
    self.error = error
  }

  /// Snapshot phase without an in-flight loading bit (subscriptions emit settled
  /// pages). Use `InfiniteQuery.phase` on the property wrapper for live loading.
  public var phase: InfiniteQueryPhase {
    if let error {
      return .failed(error, hadRows: !values.isEmpty)
    }
    if values.isEmpty {
      return canLoadNextPage ? .loaded(canLoadNextPage: true) : .idleEmpty
    }
    return .loaded(canLoadNextPage: canLoadNextPage)
  }
}

extension InfiniteQuerySnapshot: Equatable where Element: Equatable {}
extension InfiniteQuerySnapshot: Hashable where Element: Hashable {}

public struct InfiniteQuerySubscription<Element: Sendable>: AsyncSequence, Sendable {
  public typealias AsyncIterator = AsyncThrowingStream<InfiniteQuerySnapshot<Element>, Error>
    .Iterator

  private let stream: AsyncThrowingStream<InfiniteQuerySnapshot<Element>, Error>
  private let loadNextPageOperation: @Sendable () -> Void
  private let cancellation: FetchSubscriptionCancellation

  public init(
    stream: AsyncThrowingStream<InfiniteQuerySnapshot<Element>, Error>,
    loadNextPage: @escaping @Sendable () -> Void,
    cancel: @escaping @Sendable () -> Void
  ) {
    self.stream = stream
    self.loadNextPageOperation = loadNextPage
    self.cancellation = FetchSubscriptionCancellation(cancel)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }

  public func loadNextPage() {
    cancellation.unlessCancelled {
      loadNextPageOperation()
    }
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
    let finished = AsyncThrowingStream<InfiniteQuerySnapshot<Element>, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    finished.continuation.finish()
    let subscription = Self(stream: finished.stream, loadNextPage: {}) {}
    subscription.cancel()
    return subscription
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

private func validateNonNegativeIndex(
  _ index: Int64?,
  operation: String,
  subject: String
) throws {
  guard let index, index < 0 else { return }
  throw InstantError(
    code: .validationFailed,
    operation: operation,
    message: "\(subject) index must be greater than or equal to 0.",
    recovery: "Pass a previously emitted index, or omit the cursor to observe every local value."
  )
}

private func validateNonNegativeByteOffset(
  _ byteOffset: Int64?,
  operation: String
) throws {
  guard let byteOffset, byteOffset < 0 else { return }
  throw InstantError(
    code: .validationFailed,
    operation: operation,
    message: "Stream byte offset must be greater than or equal to 0.",
    recovery: "Pass a non-negative byte offset, or omit it to start at the beginning."
  )
}

// SAFETY: all mutable fetch state is protected by `lock`.
private final class FetchStorage<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _initialValue: Value
  private var _wrappedValue: Value
  private var _loadError: InstantError?
  private var _isLoading: Bool
  private var _activeSubscriptionID = 0
  private var _activeSubscription: (id: Int, subscription: FetchSubscription<Value>)?
  private var _automaticObservationTask: Task<Void, Never>?
  private var _isAutomaticObservationTaskReserved = false
  private var _allowsAutomaticObservation = true
  private let observationRegistrar: Any?

  #if canImport(SwiftUI)
    let objectWillChange = ObservableObjectPublisher()
  #endif

  init(value: Value) {
    self._initialValue = value
    self._wrappedValue = value
    self._loadError = nil
    self._isLoading = false
    #if canImport(Observation)
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
        self.observationRegistrar = FetchObservationRegistrar<Value>()
      } else {
        self.observationRegistrar = nil
      }
    #else
      self.observationRegistrar = nil
    #endif
  }

  deinit {
    _automaticObservationTask?.cancel()
    _activeSubscription?.subscription.cancel()
  }

  var initialValue: Value {
    get {
      access(keyPath: \.initialValue)
      return withLock { _initialValue }
    }
    set {
      withLock {
        _initialValue = newValue
      }
      publishChange()
    }
  }

  var wrappedValue: Value {
    get {
      access(keyPath: \.wrappedValue)
      return withLock { _wrappedValue }
    }
    set {
      withLock {
        _wrappedValue = newValue
      }
      publishChange()
    }
  }

  var loadError: InstantError? {
    get {
      access(keyPath: \.loadError)
      return withLock { _loadError }
    }
    set {
      withLock {
        _loadError = newValue
      }
      publishChange()
    }
  }

  var isLoading: Bool {
    get {
      access(keyPath: \.isLoading)
      return withLock { _isLoading }
    }
    set {
      withLock {
        _isLoading = newValue
      }
      publishChange()
    }
  }

  func resetToInitialValue() {
    withLock {
      _wrappedValue = _initialValue
    }
    publishChange()
  }

  func cancelActiveSubscription() {
    let cancellation = withLock {
      _activeSubscriptionID += 1
      let subscription = _activeSubscription?.subscription
      _activeSubscription = nil
      let automaticObservationTask = _automaticObservationTask
      _automaticObservationTask = nil
      _isAutomaticObservationTaskReserved = false
      _allowsAutomaticObservation = false
      return (subscription, automaticObservationTask)
    }
    cancellation.0?.cancel()
    cancellation.1?.cancel()
  }

  func beginActiveSubscription(_ subscription: FetchSubscription<Value>) -> Int {
    var id = 0
    let previousSubscription = withLock {
      _activeSubscriptionID += 1
      id = _activeSubscriptionID
      let previousSubscription = _activeSubscription?.subscription
      _activeSubscription = (id, subscription)
      return previousSubscription
    }
    previousSubscription?.cancel()
    return id
  }

  func prepareActiveSubscriptionTask() -> Int {
    let result = withLock {
      _activeSubscriptionID += 1
      let subscription = _activeSubscription?.subscription
      _activeSubscription = nil
      let automaticObservationTask = _automaticObservationTask
      _automaticObservationTask = nil
      _isAutomaticObservationTaskReserved = false
      _allowsAutomaticObservation = false
      _isLoading = true
      return (
        generation: _activeSubscriptionID,
        subscription: subscription,
        automaticObservationTask: automaticObservationTask
      )
    }
    result.subscription?.cancel()
    result.automaticObservationTask?.cancel()
    publishChange()
    return result.generation
  }

  func beginActiveSubscription(
    _ subscription: FetchSubscription<Value>,
    after generation: Int
  ) -> Int? {
    let result: (id: Int, previousSubscription: FetchSubscription<Value>?)? = withLock {
      guard _activeSubscriptionID == generation else { return nil }
      _activeSubscriptionID += 1
      let id = _activeSubscriptionID
      let previousSubscription = _activeSubscription?.subscription
      _activeSubscription = (id, subscription)
      return (id, previousSubscription)
    }
    result?.previousSubscription?.cancel()
    return result?.id
  }

  func isActiveSubscription(_ id: Int) -> Bool {
    withLock {
      _activeSubscription?.id == id
    }
  }

  func endActiveSubscription(_ id: Int) {
    withLock {
      if _activeSubscription?.id == id {
        _activeSubscription = nil
      }
    }
  }

  func finishActiveSubscription(_ id: Int, loadError: InstantError?) {
    withLock {
      guard _activeSubscription?.id == id else { return }
      _activeSubscription = nil
      _loadError = loadError
      _isLoading = false
    }
    publishChange()
  }

  func reserveAutomaticObservationTask() -> Int? {
    withLock {
      guard
        _allowsAutomaticObservation,
        _automaticObservationTask == nil,
        !_isAutomaticObservationTaskReserved
      else {
        return nil
      }
      _activeSubscriptionID += 1
      _isAutomaticObservationTaskReserved = true
      return _activeSubscriptionID
    }
  }

  func installReservedAutomaticObservationTask(_ task: Task<Void, Never>) {
    let shouldCancel = withLock {
      guard _automaticObservationTask == nil, _isAutomaticObservationTaskReserved else {
        return true
      }
      _automaticObservationTask = task
      _isAutomaticObservationTaskReserved = false
      return false
    }
    if shouldCancel { task.cancel() }
  }

  func enableAutomaticObservation() {
    withLock {
      _allowsAutomaticObservation = true
    }
  }

  func updateActiveSubscriptionValue(_ value: Value, id: Int) -> Bool {
    let didUpdate = withLock {
      guard _activeSubscription?.id == id else { return false }
      _wrappedValue = value
      _loadError = nil
      _isLoading = false
      return true
    }
    if didUpdate { publishChange() }
    return didUpdate
  }

  func finishActiveOrPendingSubscriptionTask(
    id: Int?,
    generation: Int,
    loadError: InstantError?
  ) -> Bool {
    let didFinish = withLock {
      if let id {
        guard _activeSubscription?.id == id else { return false }
        _activeSubscription = nil
      } else {
        guard _activeSubscriptionID == generation else { return false }
      }
      _loadError = loadError
      _isLoading = false
      return true
    }
    if didFinish { publishChange() }
    return didFinish
  }

  private func publishChange() {
    #if canImport(Observation)
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *),
        let observationRegistrar =
          observationRegistrar as? FetchObservationRegistrar<Value>
      {
        observationRegistrar.publishChange(of: self)
      }
    #endif
    #if canImport(SwiftUI)
      if Thread.isMainThread {
        objectWillChange.send()
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.objectWillChange.send()
        }
      }
    #endif
  }

  private func access<Member>(keyPath: KeyPath<FetchStorage, Member>) {
    #if canImport(Observation)
      if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *),
        let observationRegistrar =
          observationRegistrar as? FetchObservationRegistrar<Value>
      {
        observationRegistrar.access(self, keyPath: keyPath)
      }
    #endif
  }

  private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

#if canImport(Observation)
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  // SAFETY: ObservationRegistrar provides the synchronization boundary for cross-actor access.
  private final class FetchObservationRegistrar<Value: Sendable>: @unchecked Sendable {
    private let registrar = ObservationRegistrar()

    func access<Member>(
      _ storage: FetchStorage<Value>,
      keyPath: KeyPath<FetchStorage<Value>, Member>
    ) {
      registrar.access(storage, keyPath: keyPath)
    }

    func publishChange(of storage: FetchStorage<Value>) {
      registrar.withMutation(of: storage, keyPath: \.initialValue) {}
      registrar.withMutation(of: storage, keyPath: \.wrappedValue) {}
      registrar.withMutation(of: storage, keyPath: \.loadError) {}
      registrar.withMutation(of: storage, keyPath: \.isLoading) {}
    }
  }
#endif

#if canImport(SwiftUI)
  extension FetchStorage: ObservableObject {}
#endif

#if canImport(Observation)
  extension FetchStorage: Observable {}
#endif

private func runFetchStorageSubscriptionTask<Value: Sendable>(
  storage: FetchStorage<Value>,
  subscribe: @escaping @Sendable () async throws -> FetchSubscription<Value>,
  operation: String,
  recovery: String
) async throws {
  let generation = storage.prepareActiveSubscriptionTask()
  var activeSubscriptionID: Int?
  var emissionCount = 0
  InstantDiagnostics.shared.record(
    .debug,
    subsystem: "instant-swift-data",
    category: "fetch-wrapper",
    event: "fetch-task.started",
    message: "Started a property-wrapper subscription task.",
    metadata: [
      "operation": operation,
      "generation": String(generation),
      "valueType": String(reflecting: Value.self),
    ]
  )
  do {
    let subscription = try await subscribe()
    defer {
      subscription.cancel()
    }
    try Task.checkCancellation()
    guard let subscriptionID = storage.beginActiveSubscription(subscription, after: generation)
    else {
      throw CancellationError()
    }
    activeSubscriptionID = subscriptionID
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "fetch-task.subscribed",
      message: "Property wrapper established its subscription.",
      metadata: [
        "operation": operation,
        "generation": String(generation),
        "subscriptionID": String(subscriptionID),
      ]
    )
    for try await value in subscription {
      try Task.checkCancellation()
      guard storage.updateActiveSubscriptionValue(value, id: subscriptionID) else {
        throw CancellationError()
      }
      emissionCount += 1
      var emissionMetadata = [
        "operation": operation,
        "emissionCount": String(emissionCount),
        "subscriptionID": String(subscriptionID),
      ]
      let mirror = Mirror(reflecting: value)
      if mirror.displayStyle == .collection || mirror.displayStyle == .set
        || mirror.displayStyle == .dictionary
      {
        emissionMetadata["resultCount"] = String(mirror.children.count)
      }
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data",
        category: "fetch-wrapper",
        event: "fetch-task.emitted",
        message: "Property wrapper applied a subscription emission.",
        metadata: emissionMetadata
      )
    }
    try Task.checkCancellation()
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: subscriptionID,
        generation: generation,
        loadError: nil
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "fetch-task.finished",
      message: "Property-wrapper subscription task finished.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
  } catch let error as CancellationError {
    _ = storage.finishActiveOrPendingSubscriptionTask(
      id: activeSubscriptionID,
      generation: generation,
      loadError: nil
    )
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "fetch-task.cancelled",
      message: "Property-wrapper subscription task was cancelled.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
  } catch let error as InstantError {
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: activeSubscriptionID,
        generation: generation,
        loadError: error
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "fetch-task.failed",
      message: "Property-wrapper subscription task failed.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
  } catch {
    let error = InstantError(
      code: .implementationFailed,
      operation: operation,
      message: String(describing: error),
      recovery: recovery
    )
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: activeSubscriptionID,
        generation: generation,
        loadError: error
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "fetch-task.failed",
      message: "Property-wrapper subscription task failed.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
  }
}

// SAFETY: all mutable infinite-query state is protected by `lock`.
private final class InfiniteQueryStorage<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _initialValue: [Element]
  private var _wrappedValue: [Element]
  private var _loadError: InstantError?
  private var _isLoading: Bool
  private var _pageInfo: InstantQueryPageInfo?
  private var _canLoadNextPage: Bool
  private var _activeSubscriptionID = 0
  private var _activeSubscription: (id: Int, subscription: InfiniteQuerySubscription<Element>)?

  #if canImport(SwiftUI)
    let objectWillChange = ObservableObjectPublisher()
  #endif

  init(value: [Element]) {
    self._initialValue = value
    self._wrappedValue = value
    self._loadError = nil
    self._isLoading = false
    self._pageInfo = nil
    self._canLoadNextPage = false
  }

  var initialValue: [Element] {
    get {
      withLock { _initialValue }
    }
    set {
      publishChange()
      withLock {
        _initialValue = newValue
      }
    }
  }

  var wrappedValue: [Element] {
    get {
      withLock { _wrappedValue }
    }
    set {
      publishChange()
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
      publishChange()
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
      publishChange()
      withLock {
        _isLoading = newValue
      }
    }
  }

  var pageInfo: InstantQueryPageInfo? {
    get {
      withLock { _pageInfo }
    }
    set {
      publishChange()
      withLock {
        _pageInfo = newValue
      }
    }
  }

  var canLoadNextPage: Bool {
    get {
      withLock { _canLoadNextPage }
    }
    set {
      publishChange()
      withLock {
        _canLoadNextPage = newValue
      }
    }
  }

  func resetToInitialValue() {
    publishChange()
    withLock {
      _wrappedValue = _initialValue
      _loadError = nil
      _isLoading = false
      _pageInfo = nil
      _canLoadNextPage = false
    }
  }

  func apply(_ snapshot: InfiniteQuerySnapshot<Element>) {
    publishChange()
    withLock {
      _wrappedValue = snapshot.values
      _loadError = snapshot.error
      _isLoading = false
      _pageInfo = snapshot.pageInfo
      _canLoadNextPage = snapshot.canLoadNextPage
    }
  }

  func cancelActiveSubscription() {
    let subscription = withLock {
      _activeSubscriptionID += 1
      let subscription = _activeSubscription?.subscription
      _activeSubscription = nil
      return subscription
    }
    subscription?.cancel()
  }

  func beginActiveSubscription(_ subscription: InfiniteQuerySubscription<Element>) -> Int {
    var id = 0
    let previousSubscription = withLock {
      _activeSubscriptionID += 1
      id = _activeSubscriptionID
      let previousSubscription = _activeSubscription?.subscription
      _activeSubscription = (id, subscription)
      return previousSubscription
    }
    previousSubscription?.cancel()
    return id
  }

  func prepareActiveSubscriptionTask() -> Int {
    publishChange()
    let result = withLock {
      _activeSubscriptionID += 1
      let subscription = _activeSubscription?.subscription
      _activeSubscription = nil
      _isLoading = true
      return (generation: _activeSubscriptionID, subscription: subscription)
    }
    result.subscription?.cancel()
    return result.generation
  }

  func preparePendingLoad() -> Int {
    publishChange()
    let result = withLock {
      _activeSubscriptionID += 1
      let subscription = _activeSubscription?.subscription
      _activeSubscription = nil
      _isLoading = true
      return (generation: _activeSubscriptionID, subscription: subscription)
    }
    result.subscription?.cancel()
    return result.generation
  }

  func beginActiveSubscription(
    _ subscription: InfiniteQuerySubscription<Element>,
    after generation: Int
  ) -> Int? {
    let result: (id: Int, previousSubscription: InfiniteQuerySubscription<Element>?)? =
      withLock {
        guard _activeSubscriptionID == generation else { return nil }
        _activeSubscriptionID += 1
        let id = _activeSubscriptionID
        let previousSubscription = _activeSubscription?.subscription
        _activeSubscription = (id, subscription)
        return (id, previousSubscription)
      }
    result?.previousSubscription?.cancel()
    return result?.id
  }

  func isActiveSubscription(_ id: Int) -> Bool {
    withLock {
      _activeSubscription?.id == id
    }
  }

  func endActiveSubscription(_ id: Int) {
    withLock {
      if _activeSubscription?.id == id {
        _activeSubscription = nil
      }
    }
  }

  func applyActiveSubscriptionSnapshot(
    _ snapshot: InfiniteQuerySnapshot<Element>,
    id: Int
  ) -> Bool {
    publishChange()
    return withLock {
      guard _activeSubscription?.id == id else { return false }
      _wrappedValue = snapshot.values
      _loadError = snapshot.error
      _isLoading = false
      _pageInfo = snapshot.pageInfo
      _canLoadNextPage = snapshot.canLoadNextPage
      return true
    }
  }

  func applyPendingLoadSnapshot(
    _ snapshot: InfiniteQuerySnapshot<Element>,
    generation: Int
  ) -> Bool {
    publishChange()
    return withLock {
      guard _activeSubscriptionID == generation else { return false }
      _wrappedValue = snapshot.values
      _loadError = snapshot.error
      _isLoading = false
      _pageInfo = snapshot.pageInfo
      _canLoadNextPage = snapshot.canLoadNextPage
      return true
    }
  }

  func finishPendingLoad(
    generation: Int,
    loadError: InstantError?
  ) -> Bool {
    publishChange()
    return withLock {
      guard _activeSubscriptionID == generation else { return false }
      _loadError = loadError
      _isLoading = false
      return true
    }
  }

  func finishActiveOrPendingSubscriptionTask(
    id: Int?,
    generation: Int,
    loadError: InstantError?
  ) -> Bool {
    publishChange()
    return withLock {
      if let id {
        guard _activeSubscription?.id == id else { return false }
        _activeSubscription = nil
      } else {
        guard _activeSubscriptionID == generation else { return false }
      }
      _loadError = loadError
      _isLoading = false
      return true
    }
  }

  func loadNextPage() {
    let subscription = withLock {
      _activeSubscription?.subscription
    }
    subscription?.loadNextPage()
  }

  private func publishChange() {
    #if canImport(SwiftUI)
      if Thread.isMainThread {
        objectWillChange.send()
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.objectWillChange.send()
        }
      }
    #endif
  }

  private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

#if canImport(SwiftUI)
  extension InfiniteQueryStorage: ObservableObject {}
#endif

private func runInfiniteQueryStorageSubscriptionTask<Element: Sendable>(
  storage: InfiniteQueryStorage<Element>,
  subscribe: @escaping @Sendable () async throws -> InfiniteQuerySubscription<Element>,
  operation: String,
  recovery: String
) async throws {
  let generation = storage.prepareActiveSubscriptionTask()
  var activeSubscriptionID: Int?
  var emissionCount = 0
  InstantDiagnostics.shared.record(
    .debug,
    subsystem: "instant-swift-data",
    category: "fetch-wrapper",
    event: "infinite-query-task.started",
    message: "Started an infinite-query property-wrapper subscription task.",
    metadata: [
      "operation": operation,
      "generation": String(generation),
      "elementType": String(reflecting: Element.self),
    ]
  )
  do {
    let subscription = try await subscribe()
    defer {
      subscription.cancel()
    }
    try Task.checkCancellation()
    guard let subscriptionID = storage.beginActiveSubscription(subscription, after: generation)
    else {
      throw CancellationError()
    }
    activeSubscriptionID = subscriptionID
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "infinite-query-task.subscribed",
      message: "Infinite-query wrapper established its subscription.",
      metadata: [
        "operation": operation,
        "generation": String(generation),
        "subscriptionID": String(subscriptionID),
      ]
    )
    for try await snapshot in subscription {
      try Task.checkCancellation()
      guard storage.applyActiveSubscriptionSnapshot(snapshot, id: subscriptionID) else {
        throw CancellationError()
      }
      emissionCount += 1
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data",
        category: "fetch-wrapper",
        event: "infinite-query-task.emitted",
        message: "Infinite-query wrapper applied a subscription snapshot.",
        metadata: [
          "operation": operation,
          "emissionCount": String(emissionCount),
          "subscriptionID": String(subscriptionID),
          "resultCount": String(snapshot.values.count),
          "canLoadNextPage": String(snapshot.canLoadNextPage),
          "hasError": String(snapshot.error != nil),
        ]
      )
    }
    try Task.checkCancellation()
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: subscriptionID,
        generation: generation,
        loadError: nil
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "infinite-query-task.finished",
      message: "Infinite-query wrapper subscription finished.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
  } catch let error as CancellationError {
    _ = storage.finishActiveOrPendingSubscriptionTask(
      id: activeSubscriptionID,
      generation: generation,
      loadError: nil
    )
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "infinite-query-task.cancelled",
      message: "Infinite-query wrapper subscription was cancelled.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
  } catch let error as InstantError {
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: activeSubscriptionID,
        generation: generation,
        loadError: error
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "infinite-query-task.failed",
      message: "Infinite-query wrapper subscription failed.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
  } catch {
    let error = InstantError(
      code: .implementationFailed,
      operation: operation,
      message: String(describing: error),
      recovery: recovery
    )
    guard
      storage.finishActiveOrPendingSubscriptionTask(
        id: activeSubscriptionID,
        generation: generation,
        loadError: error
      )
    else {
      throw CancellationError()
    }
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data",
      category: "fetch-wrapper",
      event: "infinite-query-task.failed",
      message: "Infinite-query wrapper subscription failed.",
      metadata: [
        "operation": operation,
        "emissionCount": String(emissionCount),
      ]
    )
    throw error
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

  init(
    _ operations: FetchOperations<Value> = FetchOperations(),
    storage: FetchStorage<Value>? = nil
  ) {
    self.operations = operations
    // Construction must stay inert. SwiftUI freely creates disposable DynamicProperty
    // values while diffing views; observation begins from a retained wrapper's first
    // read, publisher access, or DynamicProperty update instead.
    _ = storage
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

  func startAutomaticObservationIfNeeded(storage: FetchStorage<Value>) {
    let subscribe = value.subscribe
    if let subscribe {
      startAutomaticFetchObservation(storage: storage, subscribe: subscribe)
    }
  }
}

// SAFETY: Swift's runtime weak-reference lock protects reads and deallocation zeroing.
private final class WeakFetchStorage<Value: Sendable>: @unchecked Sendable {
  weak var value: FetchStorage<Value>?

  init(_ value: FetchStorage<Value>) {
    self.value = value
  }
}

private func startAutomaticFetchObservation<Value: Sendable>(
  storage: FetchStorage<Value>,
  subscribe: @escaping @Sendable (InstantSwiftDataClient) async throws
    -> FetchSubscription<Value>
) {
  @Dependency(\.defaultInstantSwiftData) var client
  guard client.supportsAutomaticFetchObservation else { return }
  startAutomaticFetchObservation(storage: storage, using: client, subscribe: subscribe)
}

private func startAutomaticFetchObservation<Value: Sendable>(
  storage: FetchStorage<Value>,
  using client: InstantSwiftDataClient,
  subscribe: @escaping @Sendable (InstantSwiftDataClient) async throws
    -> FetchSubscription<Value>
) {
  guard let generation = storage.reserveAutomaticObservationTask() else { return }
  let storageReference = WeakFetchStorage(storage)
  let startupTrace = client.runtime?.configuration.startupTrace ?? .disabled
  let startupStopwatch = startupTrace.started(
    "fetch.automatic",
    metadata: ["valueType": String(reflecting: Value.self)]
  )
  InstantDiagnostics.shared.record(
    .debug,
    subsystem: "instant-swift-data",
    category: "fetch-wrapper",
    event: "fetch-automatic.started",
    message: "Started automatic observation for a static fetch declaration.",
    metadata: ["valueType": String(reflecting: Value.self)]
  )
  let task = Task {
    var subscriptionID: Int?
    var emissionCount = 0
    do {
      let subscription = try await subscribe(client)
      startupTrace.completed(
        "fetch.subscription-established",
        since: startupStopwatch,
        metadata: ["valueType": String(reflecting: Value.self)]
      )
      defer { subscription.cancel() }
      try Task.checkCancellation()
      guard
        let id = storageReference.value?.beginActiveSubscription(
          subscription,
          after: generation
        )
      else { return }
      subscriptionID = id
      for try await value in subscription {
        try Task.checkCancellation()
        guard storageReference.value?.updateActiveSubscriptionValue(value, id: id) == true else {
          throw CancellationError()
        }
        emissionCount += 1
        let mirror = Mirror(reflecting: value)
        if emissionCount == 1 {
          startupTrace.completed(
            "fetch.first-emission",
            since: startupStopwatch,
            metadata: [
              "resultCount": String(mirror.children.count),
              "valueType": String(reflecting: Value.self),
            ]
          )
        }
        InstantDiagnostics.shared.record(
          .trace,
          subsystem: "instant-swift-data",
          category: "fetch-wrapper",
          event: "fetch-automatic.emitted",
          message: "Applied an automatic fetch observation emission.",
          metadata: [
            "emissionCount": String(emissionCount),
            "resultCount": String(mirror.children.count),
            "valueType": String(reflecting: Value.self),
          ]
        )
      }
      storageReference.value?.finishActiveSubscription(id, loadError: nil)
    } catch is CancellationError {
      if let subscriptionID {
        storageReference.value?.finishActiveSubscription(subscriptionID, loadError: nil)
      }
    } catch let error as InstantError {
      if let subscriptionID {
        storageReference.value?.finishActiveSubscription(subscriptionID, loadError: error)
      } else {
        storageReference.value?.loadError = error
        storageReference.value?.isLoading = false
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data",
        category: "fetch-wrapper",
        event: "fetch-automatic.failed",
        message: "Automatic fetch observation failed.",
        metadata: ["valueType": String(reflecting: Value.self)]
      )
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "observe fetch declaration",
        message: String(describing: error),
        recovery: "Inspect the declared Instant query and configured InstantSwiftData client."
      )
      if let subscriptionID {
        storageReference.value?.finishActiveSubscription(subscriptionID, loadError: error)
      } else {
        storageReference.value?.loadError = error
        storageReference.value?.isLoading = false
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data",
        category: "fetch-wrapper",
        event: "fetch-automatic.failed",
        message: "Automatic fetch observation failed.",
        metadata: ["valueType": String(reflecting: Value.self)]
      )
    }
  }
  storage.installReservedAutomaticObservationTask(task)
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

// SAFETY: all mutable state is protected by `lock`.
final class FetchSubscriptionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: @Sendable () -> Void
  private var isCancelled = false
  private var activeOperationCount = 0
  private var didRunCancellation = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  init(_ operation: @escaping @Sendable () -> Void) {
    self.operation = operation
  }

  deinit {
    cancel()
  }

  func cancel() {
    let continuations: [CheckedContinuation<Void, Never>]
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    isCancelled = true
    guard activeOperationCount == 0, !didRunCancellation else {
      lock.unlock()
      return
    }
    didRunCancellation = true
    continuations = self.continuations
    self.continuations.removeAll()
    lock.unlock()

    operation()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func unlessCancelled(_ action: @Sendable () -> Void) {
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    activeOperationCount += 1
    lock.unlock()

    action()

    finishOperation()
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if didRunCancellation {
        lock.unlock()
        continuation.resume()
      } else {
        continuations.append(continuation)
        lock.unlock()
      }
    }
  }

  private func finishOperation() {
    let continuations: [CheckedContinuation<Void, Never>]
    lock.lock()
    activeOperationCount -= 1
    guard isCancelled, activeOperationCount == 0, !didRunCancellation else {
      lock.unlock()
      return
    }
    didRunCancellation = true
    continuations = self.continuations
    self.continuations.removeAll()
    lock.unlock()

    operation()
    for continuation in continuations {
      continuation.resume()
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

private enum LocalInstantSwiftDataKey: TestDependencyKey {
  static var testValue: InstantSwiftDataClient {
    .unimplemented("No test local-only InstantSwiftData client has been configured.")
  }

  static var previewValue: InstantSwiftDataClient {
    .unimplemented("No preview local-only InstantSwiftData client has been configured.")
  }
}

extension LocalInstantSwiftDataKey: DependencyKey {
  static var liveValue: InstantSwiftDataClient {
    .unimplemented("No live local-only InstantSwiftData client has been configured.")
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
    .live
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
    .live
  }
}

private enum InstantGuestAuthenticatorKey: TestDependencyKey {
  static var testValue: InstantGuestAuthenticator {
    .local
  }

  static var previewValue: InstantGuestAuthenticator {
    .local
  }
}

extension InstantGuestAuthenticatorKey: DependencyKey {
  static var liveValue: InstantGuestAuthenticator {
    .live
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
    .live
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
    .live
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
    .live
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

private enum InstantStorageTransportKey: TestDependencyKey {
  static var testValue: InstantStorageTransportClient? {
    nil
  }

  static var previewValue: InstantStorageTransportClient? {
    nil
  }
}

extension InstantStorageTransportKey: DependencyKey {
  static var liveValue: InstantStorageTransportClient? {
    .live()
  }
}

private enum InstantLiveTransportKey: TestDependencyKey {
  static var testValue: InstantLiveTransportClient? {
    nil
  }

  static var previewValue: InstantLiveTransportClient? {
    nil
  }
}

extension InstantLiveTransportKey: DependencyKey {
  static var liveValue: InstantLiveTransportClient? {
    nil
  }
}

private enum InstantUserCookieSyncClientKey: TestDependencyKey {
  static var testValue: InstantUserCookieSyncClient {
    .local
  }

  static var previewValue: InstantUserCookieSyncClient {
    .local
  }
}

extension InstantUserCookieSyncClientKey: DependencyKey {
  static var liveValue: InstantUserCookieSyncClient {
    .live
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

private enum InstantPlatformAppClientKey: TestDependencyKey {
  static var testValue: InstantPlatformAppClient {
    .local
  }

  static var previewValue: InstantPlatformAppClient {
    .local
  }
}

extension InstantPlatformAppClientKey: DependencyKey {
  static var liveValue: InstantPlatformAppClient {
    .local
  }
}

private enum AppBuilderCodeGeneratorClientKey: TestDependencyKey {
  static var testValue: AppBuilderCodeGeneratorClient {
    .local
  }

  static var previewValue: AppBuilderCodeGeneratorClient {
    .local
  }
}

extension AppBuilderCodeGeneratorClientKey: DependencyKey {
  static var liveValue: AppBuilderCodeGeneratorClient {
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

  public var localInstantSwiftData: InstantSwiftDataClient {
    get { self[LocalInstantSwiftDataKey.self] }
    set { self[LocalInstantSwiftDataKey.self] = newValue }
  }

  public var instantMagicCodeExchange: InstantMagicCodeExchange {
    get { self[InstantMagicCodeExchangeKey.self] }
    set { self[InstantMagicCodeExchangeKey.self] = newValue }
  }

  public var instantRefreshTokenVerifier: InstantRefreshTokenVerifier {
    get { self[InstantRefreshTokenVerifierKey.self] }
    set { self[InstantRefreshTokenVerifierKey.self] = newValue }
  }

  public var instantGuestAuthenticator: InstantGuestAuthenticator {
    get { self[InstantGuestAuthenticatorKey.self] }
    set { self[InstantGuestAuthenticatorKey.self] = newValue }
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

  public var instantStorageTransport: InstantStorageTransportClient? {
    get { self[InstantStorageTransportKey.self] }
    set { self[InstantStorageTransportKey.self] = newValue }
  }

  public var instantLiveTransport: InstantLiveTransportClient? {
    get { self[InstantLiveTransportKey.self] }
    set { self[InstantLiveTransportKey.self] = newValue }
  }

  public var instantUserCookieSyncClient: InstantUserCookieSyncClient {
    get { self[InstantUserCookieSyncClientKey.self] }
    set { self[InstantUserCookieSyncClientKey.self] = newValue }
  }

  public var instantPlatformAppClient: InstantPlatformAppClient {
    get { self[InstantPlatformAppClientKey.self] }
    set { self[InstantPlatformAppClientKey.self] = newValue }
  }

  public var appBuilderCodeGenerator: AppBuilderCodeGeneratorClient {
    get { self[AppBuilderCodeGeneratorClientKey.self] }
    set { self[AppBuilderCodeGeneratorClientKey.self] = newValue }
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
    firstPartyURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = [],
    liveShareContract: InstantLiveShareContract? = nil,
    startupTrace: InstantStartupTrace = .live()
  ) async throws {
    try await self.bootstrapInstantSwiftData(
      appID: appID,
      apiURI: InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      firstPartyURL: firstPartyURL,
      context: context,
      initialAttributes: initialAttributes,
      liveShareContract: liveShareContract,
      startupTrace: startupTrace
    )
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    persistenceURL: URL? = nil,
    firstPartyURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = [],
    liveShareContract: InstantLiveShareContract? = nil,
    startupTrace: InstantStartupTrace = .live()
  ) async throws {
    let bootstrapStopwatch = startupTrace.started(
      "dependencies.bootstrap",
      metadata: [
        "appID": appID,
        "context": context.rawValue,
      ]
    )
    let date = self.date
    let uuid = self.uuid
    let magicCodeExchange = self.instantMagicCodeExchange
    let refreshTokenVerifier = self.instantRefreshTokenVerifier
    let guestAuthenticator = self.instantGuestAuthenticator
    let idTokenExchange = self.instantIDTokenExchange
    let oauthExchange = self.instantOAuthExchange
    let authTokenInvalidator = self.instantAuthTokenInvalidator
    let mutationTransport = self.instantMutationTransport
    let storageTransport = self.instantStorageTransport
    let liveTransport = self.instantLiveTransport
    let userCookieSyncClient = self.instantUserCookieSyncClient
    let platformAppClient = self.instantPlatformAppClient
    let appBuilderCodeGenerator = self.appBuilderCodeGenerator
    let url =
      persistenceURL
      ?? Self.defaultInstantSwiftDataPersistenceURL(
        appID: appID,
        context: context,
        uniqueID: context == .test ? uuid().uuidString.lowercased() : nil
      )

    var runtimeConfiguration = InstantRuntimeConfiguration(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        firstPartyURL: firstPartyURL,
        persistenceURL: url,
        initialAttributes: initialAttributes,
        now: {
          InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1000).rounded()))
        },
        makeID: {
          uuid().uuidString.lowercased()
        },
        refreshTokenVerifier: refreshTokenVerifier,
        guestAuthenticator: guestAuthenticator,
        magicCodeExchange: magicCodeExchange,
        idTokenExchange: idTokenExchange,
        oauthExchange: oauthExchange,
        authTokenInvalidator: authTokenInvalidator,
        mutationTransport: mutationTransport,
        liveTransport: liveTransport,
        liveShareContract: liveShareContract,
        userCookieSyncClient: userCookieSyncClient,
        platformAppClient: platformAppClient,
        appBuilderCodeGenerator: appBuilderCodeGenerator
      )
    runtimeConfiguration.startupTrace = startupTrace
    runtimeConfiguration.autoConnectLiveTransport = liveTransport != nil
    startupTrace.completed(
      "dependencies.configuration",
      durationMilliseconds: 0,
      metadata: [
        "autoConnect": String(runtimeConfiguration.autoConnectLiveTransport),
        "persistenceFile": url.lastPathComponent,
      ]
    )

    do {
      let client = try await InstantSwiftDataClient.bootstrap(
        configuration: runtimeConfiguration,
        storageTransport: storageTransport
      )
      // Synchronous product reads (SwiftUI / TCA) use InstantClientID.current.
      _ = try await client.clientID()
      self.defaultInstantSwiftData = client
      startupTrace.completed(
        "dependencies.bootstrap",
        since: bootstrapStopwatch,
        metadata: ["defaultClientInstalled": "true"]
      )
    } catch {
      startupTrace.failed("dependencies.bootstrap", error: error, since: bootstrapStopwatch)
      throw error
    }
  }

  public mutating func bootstrapLocalInstantSwiftData(
    appID: String,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    let date = self.date
    let uuid = self.uuid
    let url =
      persistenceURL
      ?? Self.defaultInstantSwiftDataPersistenceURL(
        appID: appID,
        context: context,
        uniqueID: context == .test ? uuid().uuidString.lowercased() : nil
      )
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: initialAttributes,
      now: {
        InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1_000).rounded()))
      },
      makeID: {
        uuid().uuidString.lowercased()
      }
    )
    configuration.isLocalOnly = true
    self.localInstantSwiftData = try await InstantSwiftDataClient.bootstrap(
      configuration: configuration,
      storageTransport: nil
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
      return defaultApplicationDataURL()
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

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
      return defaultApplicationDataURL()
    #else
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".instant-swift-data", isDirectory: true)
    #endif
  }

  private static func defaultApplicationDataURL() -> URL {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
      return (
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
          ?? FileManager.default.temporaryDirectory
      )
      .appendingPathComponent("InstantSwiftData", isDirectory: true)
    #else
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".instant-swift-data", isDirectory: true)
    #endif
  }
}

@dynamicMemberLookup
@propertyWrapper
// SAFETY: mutable query state is owned by lock-protected storage references;
// SwiftUI observes the same reference through its main-actor DynamicProperty hook.
public struct InfiniteQuery<Element: InstantEntityModel>: @unchecked Sendable {
  private let storageReference: LockedValueStorage<InfiniteQueryStorage<Element>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: InfiniteQueryStorage<Element>
  #endif
  private let query: LockedValueStorage<InstantEntityQuery<Element>?>

  private var storage: InfiniteQueryStorage<Element> { storageReference.value }

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

  public var pageInfo: InstantQueryPageInfo? {
    get { storage.pageInfo }
    nonmutating set { storage.pageInfo = newValue }
  }

  public var canLoadNextPage: Bool {
    get { storage.canLoadNextPage }
    nonmutating set { storage.canLoadNextPage = newValue }
  }

  /// TanStack-shaped phase ADT derived from loading, rows, page-end, and error.
  public var phase: InfiniteQueryPhase {
    if let loadError {
      return .failed(loadError, hadRows: !wrappedValue.isEmpty)
    }
    if isLoading {
      return wrappedValue.isEmpty
        ? .loadingFirstPage
        : .loadingNextPage(canLoadNextPage: canLoadNextPage)
    }
    if wrappedValue.isEmpty {
      return .idleEmpty
    }
    return .loaded(canLoadNextPage: canLoadNextPage)
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

  public init(wrappedValue: [Element] = []) {
    self.init(wrappedValue: wrappedValue, Element.query)
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>
  ) {
    let storage = InfiniteQueryStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.query = LockedValueStorage(query)
  }

  /// Page size is infinite-query config: each `loadNextPage()` expands by this
  /// many **root** rows. It is not "only ever N rows forever."
  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>,
    pageSize: Int
  ) {
    precondition(pageSize > 0, "InfiniteQuery pageSize must be greater than zero.")
    self.init(wrappedValue: wrappedValue, query.limit(UInt(pageSize)))
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>?
  ) {
    let storage = InfiniteQueryStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.query = LockedValueStorage(query)
  }

  #if canImport(SwiftUI)
    public init(
      wrappedValue: [Element] = [],
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, Element.query)
    }

    public init(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Element>,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query)
    }

    public init(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Element>,
      pageSize: Int,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query, pageSize: pageSize)
    }

    public init(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Element>?,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query)
    }
  #endif

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      storage.initialValue = newValue.storage.initialValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      pageInfo = newValue.pageInfo
      canLoadNextPage = newValue.canLoadNextPage
      query.value = newValue.query.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let query = query.value else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load InfiniteQuery",
        message: "No Instant query has been configured for this infinite query wrapper.",
        recovery:
          "Initialize @InfiniteQuery with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    let generation = storage.preparePendingLoad()
    do {
      let snapshot = try await client.infiniteQueryInitialSnapshot(query)
      try Task.checkCancellation()
      guard storage.applyPendingLoadSnapshot(snapshot, generation: generation) else {
        throw CancellationError()
      }
    } catch let error as CancellationError {
      _ = storage.finishPendingLoad(generation: generation, loadError: nil)
      throw error
    } catch let error as InstantError {
      guard storage.finishPendingLoad(generation: generation, loadError: error) else {
        throw CancellationError()
      }
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load InfiniteQuery",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and infinite query decoder."
      )
      guard storage.finishPendingLoad(generation: generation, loadError: error) else {
        throw CancellationError()
      }
      throw error
    }
  }

  public func load(
    _ query: InstantEntityQuery<Element>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws {
    self.query.value = query
    try await load(using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>?
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public func load(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws {
    guard let query else {
      clearQuery()
      return
    }
    try await load(query, using: client)
  }

  public func subscribe() async throws -> InfiniteQuerySubscription<Element> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> InfiniteQuerySubscription<Element> {
    do {
      let subscription = try await makeSubscription(using: client)
      loadError = nil
      return subscription
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> InfiniteQuerySubscription<Element> {
    guard let query = query.value else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe InfiniteQuery",
        message: "No Instant query has been configured for this infinite query wrapper.",
        recovery:
          "Initialize @InfiniteQuery with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
      throw error
    }

    return await client.subscribeInfiniteQuery(query)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>
  ) async throws -> InfiniteQuerySubscription<Element> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws -> InfiniteQuerySubscription<Element> {
    self.query.value = query
    return try await subscribe(using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>?
  ) async throws -> InfiniteQuerySubscription<Element> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public func subscribe(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws -> InfiniteQuerySubscription<Element> {
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
    try await runInfiniteQueryStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe InfiniteQuery",
      recovery:
        "Inspect the configured InstantSwiftDataClient and infinite query subscription operation."
    )
  }

  public func task(
    _ query: InstantEntityQuery<Element>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws {
    self.query.value = query
    try await task(using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>?
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public func task(
    _ query: InstantEntityQuery<Element>?,
    using client: InstantSwiftDataClient
  ) async throws {
    guard let query else {
      clearQuery()
      return
    }
    try await task(query, using: client)
  }

  public func loadNextPage() {
    storage.loadNextPage()
  }

  public func cancel() {
    storage.cancelActiveSubscription()
    isLoading = false
  }

  private func clearQuery() {
    query.value = nil
    storage.cancelActiveSubscription()
    wrappedValue = []
    loadError = nil
    isLoading = false
    pageInfo = nil
    canLoadNextPage = false
  }
}

@dynamicMemberLookup
@propertyWrapper
// SAFETY: mutable fetch state is owned by lock-protected storage references;
// SwiftUI observes the same reference through its main-actor DynamicProperty hook.
public struct FetchAll<Element: Sendable>: @unchecked Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<[Element]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[Element]>
  #endif
  private let operations: FetchOperationStorage<[Element]>

  private var storage: FetchStorage<[Element]> { storageReference.value }

  public var wrappedValue: [Element] {
    get {
      operations.startAutomaticObservationIfNeeded(storage: storage)
      return storage.wrappedValue
    }
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
    public var publisher: some Publisher<[Element], Never> {
      Just<Void>(()).flatMap { _ in
        operations.startAutomaticObservationIfNeeded(storage: storage)
        return storage.objectWillChange
          .map { storage.wrappedValue }
          .prepend(storage.wrappedValue)
      }
    }
  #endif

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage()
  }

  #if canImport(SwiftUI)
    @_disfavoredOverload
    public init(
      wrappedValue: [Element] = [],
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue)
    }
  #endif

  public init(wrappedValue: [Element] = []) where Element: InstantEntityModel {
    self.init(wrappedValue: wrappedValue, Element.query)
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.init(wrappedValue: wrappedValue, Optional(query))
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>?
  ) where Element: InstantEntityModel {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      query.map(Self.operations(for:)) ?? FetchOperations(),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init(
      wrappedValue: [Element] = [],
      animation: Animation?
    ) where Element: InstantEntityModel {
      self.init(wrappedValue: wrappedValue, Element.query)
    }

    public init(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Element>,
      animation: Animation?
    ) where Element: InstantEntityModel {
      self.init(wrappedValue: wrappedValue, query)
    }

    public init(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Element>?,
      animation: Animation?
    ) where Element: InstantEntityModel {
      self.init(wrappedValue: wrappedValue, query)
    }
  #endif

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      storage.initialValue = newValue.storage.initialValue
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
    storage.cancelActiveSubscription()
    guard let loadOperation = operations.value.load else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery:
          "Initialize @FetchAll with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
      if let subscribe = operations.value.subscribe {
        storage.enableAutomaticObservation()
        startAutomaticFetchObservation(storage: storage, using: client, subscribe: subscribe)
      }
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      loadError = nil
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> {
    guard let subscribeOperation = operations.value.subscribe else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery:
          "Initialize @FetchAll with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
    }

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
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe FetchAll",
      recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
    )
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
    storage.cancelActiveSubscription()
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

#if canImport(SwiftUI)
  extension View {
    public func instantFetch<Element>(
      _ fetch: FetchAll<Element>,
      _ query: InstantQuery<Element>
    ) -> some View where Element: InstantEntityModel {
      task(id: query) {
        do {
          try await fetch.task(query)
        } catch is CancellationError {
        } catch {
          // FetchAll records renderable failures in loadError.
        }
      }
    }
  }
#endif

extension FetchAll where Element: InstantValueDecodable & InstantValueRepresentable {
  public init<Entity: InstantEntityModel>(
    wrappedValue: [Element] = [],
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      Self.scalarOperations(for: query, selecting: field),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: [Element] = [],
      _ field: InstantAttributePath<Entity, Element>,
      from query: InstantEntityQuery<Entity> = Entity.query,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, field, from: query)
    }
  #endif

  public init<Entity: InstantEntityModel>(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) {
    self.init(wrappedValue: wrappedValue, field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: [Element] = [],
      _ query: InstantEntityQuery<Entity>,
      selecting field: InstantAttributePath<Entity, Element>,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query, selecting: field)
    }
  #endif

  public func load<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(field, from: query, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws {
    configureScalarQuery(query, selecting: field)
    try await load(using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, selecting: field, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>,
    using client: InstantSwiftDataClient
  ) async throws {
    try await load(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws -> FetchSubscription<[Element]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> {
    configureScalarQuery(query, selecting: field)
    return try await subscribe(using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) async throws -> FetchSubscription<[Element]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, selecting: field, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> {
    try await subscribe(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Element>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws {
    configureScalarQuery(query, selecting: field)
    try await task(using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, selecting: field, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>,
    using client: InstantSwiftDataClient
  ) async throws {
    try await task(field, from: query, using: client)
  }

  private func configureScalarQuery<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) {
    operations.value = Self.scalarOperations(for: query, selecting: field)
  }

  private static func scalarOperations<Entity: InstantEntityModel>(
    for query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Element>
  ) -> FetchOperations<[Element]> {
    let selectedQuery = query.select(field)
    return FetchOperations(
      load: { client in
        try await scalarValues(
          from: client.query(selectedQuery.plan),
          field: field,
          operation: "load FetchAll"
        )
      },
      subscribe: { client in
        await scalarSubscription(client: client, selectedQuery: selectedQuery, field: field)
      }
    )
  }

  private static func scalarSubscription<Entity: InstantEntityModel>(
    client: InstantSwiftDataClient,
    selectedQuery: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, Element>
  ) async -> FetchSubscription<[Element]> {
    let emissions = await client.observe(selectedQuery.plan)
    let stream = AsyncThrowingStream<[Element], Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(
            try scalarValues(
              from: emission.values,
              field: field,
              operation: "subscribe FetchAll"
            )
          )
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
    return FetchSubscription<[Element]>(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }

  private static func scalarValues<Entity: InstantEntityModel>(
    from snapshots: [InstantEntitySnapshot],
    field: InstantAttributePath<Entity, Element>,
    operation: String
  ) throws -> [Element] {
    try snapshots.map { snapshot in
      try Element.decodeInstantValue(
        snapshot.values[field.name]?.first,
        namespace: Entity.instantNamespace,
        path: field.name,
        localID: snapshot.id,
        operation: operation
      )
    }
  }
}

extension FetchAll {
  public init<Entity: InstantEntityModel, FieldValue>(
    wrappedValue: [FieldValue?] = [],
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      Self.optionalScalarOperations(for: query, selecting: field),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel, FieldValue>(
      wrappedValue: [FieldValue?] = [],
      _ field: InstantAttributePath<Entity, FieldValue>,
      from query: InstantEntityQuery<Entity> = Entity.query,
      animation: Animation?
    ) where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
      self.init(wrappedValue: wrappedValue, field, from: query)
    }
  #endif

  public init<Entity: InstantEntityModel, FieldValue>(
    wrappedValue: [FieldValue?] = [],
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    self.init(wrappedValue: wrappedValue, field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel, FieldValue>(
      wrappedValue: [FieldValue?] = [],
      _ query: InstantEntityQuery<Entity>,
      selecting field: InstantAttributePath<Entity, FieldValue>,
      animation: Animation?
    ) where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
      self.init(wrappedValue: wrappedValue, query, selecting: field)
    }
  #endif

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(field, from: query, using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    try await load(using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, selecting: field, using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await load(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws -> FetchSubscription<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    return try await subscribe(using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws -> FetchSubscription<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, selecting: field, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await subscribe(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    try await task(using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, selecting: field, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await task(field, from: query, using: client)
  }

  private func configureOptionalScalarQuery<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    operations.value = Self.optionalScalarOperations(for: query, selecting: field)
  }

  private static func optionalScalarOperations<Entity: InstantEntityModel, FieldValue>(
    for query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) -> FetchOperations<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let selectedQuery = query.select(field)
    return FetchOperations(
      load: { client in
        try await optionalScalarValues(
          from: client.query(selectedQuery.plan),
          field: field,
          operation: "load FetchAll"
        )
      },
      subscribe: { client in
        await optionalScalarSubscription(client: client, selectedQuery: selectedQuery, field: field)
      }
    )
  }

  private static func optionalScalarSubscription<Entity: InstantEntityModel, FieldValue>(
    client: InstantSwiftDataClient,
    selectedQuery: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, FieldValue>
  ) async -> FetchSubscription<[Element]>
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let emissions = await client.observe(selectedQuery.plan)
    let stream = AsyncThrowingStream<[Element], Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(
            try optionalScalarValues(
              from: emission.values,
              field: field,
              operation: "subscribe FetchAll"
            )
          )
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
    return FetchSubscription<[Element]>(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }

  private static func optionalScalarValues<Entity: InstantEntityModel, FieldValue>(
    from snapshots: [InstantEntitySnapshot],
    field: InstantAttributePath<Entity, FieldValue>,
    operation: String
  ) throws -> [Element]
  where Element == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try snapshots.map { snapshot in
      guard let value = snapshot.values[field.name]?.first, value != .null else {
        return nil
      }
      return try FieldValue.decodeInstantValue(
        value,
        namespace: Entity.instantNamespace,
        path: field.name,
        localID: snapshot.id,
        operation: operation
      )
    }
  }
}

@dynamicMemberLookup
@propertyWrapper
public struct FetchOne<Value: Sendable>: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<Value>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<Value>
  #endif
  private let operations: FetchOperationStorage<Value>

  private var storage: FetchStorage<Value> { storageReference.value }

  public var wrappedValue: Value {
    get {
      operations.startAutomaticObservationIfNeeded(storage: storage)
      return storage.wrappedValue
    }
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
    public var publisher: some Publisher<Value, Never> {
      Just<Void>(()).flatMap { _ in
        operations.startAutomaticObservationIfNeeded(storage: storage)
        return storage.objectWillChange
          .map { storage.wrappedValue }
          .prepend(storage.wrappedValue)
      }
    }
  #endif

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage()
  }

  #if canImport(SwiftUI)
    @_disfavoredOverload
    public init(
      wrappedValue: Value,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue)
    }
  #endif

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      storage.initialValue = newValue.storage.initialValue
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
    storage.cancelActiveSubscription()
    guard let loadOperation = operations.value.load else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery:
          "Initialize @FetchOne with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
      if let subscribe = operations.value.subscribe {
        storage.enableAutomaticObservation()
        startAutomaticFetchObservation(storage: storage, using: client, subscribe: subscribe)
      }
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    } catch {
      loadError = nil
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    guard let subscribeOperation = operations.value.subscribe else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery:
          "Initialize @FetchOne with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
    }

    return try await subscribeOperation(client)
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe FetchOne",
      recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
    )
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

  #if canImport(SwiftUI)
    public init(
      wrappedValue: Value,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, Value.query)
    }
  #endif

  public init(
    wrappedValue: Value,
    _ query: InstantEntityQuery<Value>
  ) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(Self.requiredOperations(for: query), storage: storage)
  }

  #if canImport(SwiftUI)
    public init(
      wrappedValue: Value,
      _ query: InstantEntityQuery<Value>,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query)
    }
  #endif

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

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: Entity? = nil,
      animation: Animation?
    ) where Value == Entity? {
      self.init(wrappedValue: wrappedValue, Entity.query)
    }
  #endif

  public init<Entity: InstantEntityModel>(
    wrappedValue: Entity? = nil,
    _ query: InstantEntityQuery<Entity>
  ) where Value == Entity? {
    self.init(wrappedValue: wrappedValue, Optional(query))
  }

  public init<Entity: InstantEntityModel>(
    wrappedValue: Entity? = nil,
    _ query: InstantEntityQuery<Entity>?
  ) where Value == Entity? {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      query.map(Self.optionalOperations(for:)) ?? FetchOperations(),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: Entity? = nil,
      _ query: InstantEntityQuery<Entity>,
      animation: Animation?
    ) where Value == Entity? {
      self.init(wrappedValue: wrappedValue, query)
    }

    public init<Entity: InstantEntityModel>(
      wrappedValue: Entity? = nil,
      _ query: InstantEntityQuery<Entity>?,
      animation: Animation?
    ) where Value == Entity? {
      self.init(wrappedValue: wrappedValue, query)
    }
  #endif

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
    storage.cancelActiveSubscription()
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

extension FetchOne where Value: InstantValueDecodable & InstantValueRepresentable {
  public init<Entity: InstantEntityModel>(
    wrappedValue: Value,
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      Self.scalarOperations(for: query, selecting: field),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: Value,
      _ field: InstantAttributePath<Entity, Value>,
      from query: InstantEntityQuery<Entity> = Entity.query,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, field, from: query)
    }
  #endif

  public init<Entity: InstantEntityModel>(
    wrappedValue: Value,
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) {
    self.init(wrappedValue: wrappedValue, field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      wrappedValue: Value,
      _ query: InstantEntityQuery<Entity>,
      selecting field: InstantAttributePath<Entity, Value>,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, query, selecting: field)
    }
  #endif

  public func load<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(field, from: query, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws {
    configureScalarQuery(query, selecting: field)
    try await load(using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, selecting: field, using: client)
  }

  public func load<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>,
    using client: InstantSwiftDataClient
  ) async throws {
    try await load(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    configureScalarQuery(query, selecting: field)
    return try await subscribe(using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, selecting: field, using: client)
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    try await subscribe(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws {
    configureScalarQuery(query, selecting: field)
    try await task(using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, selecting: field, using: client)
  }

  public func task<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>,
    using client: InstantSwiftDataClient
  ) async throws {
    try await task(field, from: query, using: client)
  }

  private func configureScalarQuery<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) {
    operations.value = Self.scalarOperations(for: query, selecting: field)
  }

  private static func scalarOperations<Entity: InstantEntityModel>(
    for query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) -> FetchOperations<Value> {
    let selectedQuery = Self.limitOne(query.select(field))
    return FetchOperations(
      load: { client in
        try await scalarValue(
          from: client.query(selectedQuery.plan),
          query: query,
          field: field,
          operation: "load FetchOne"
        )
      },
      subscribe: { client in
        await scalarSubscription(
          client: client, query: query, selectedQuery: selectedQuery, field: field)
      }
    )
  }

  private static func scalarSubscription<Entity: InstantEntityModel>(
    client: InstantSwiftDataClient,
    query: InstantEntityQuery<Entity>,
    selectedQuery: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, Value>
  ) async -> FetchSubscription<Value> {
    let emissions = await client.observe(selectedQuery.plan)
    let stream = AsyncThrowingStream<Value, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(
            try scalarValue(
              from: emission.values,
              query: query,
              field: field,
              operation: "subscribe FetchOne"
            )
          )
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
    return FetchSubscription<Value>(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }

  private static func scalarValue<Entity: InstantEntityModel>(
    from snapshots: [InstantEntitySnapshot],
    query: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, Value>,
    operation: String
  ) throws -> Value {
    guard let snapshot = snapshots.first else {
      if Value.acceptsMissingInstantValue {
        return try Value.decodeInstantValue(
          nil,
          namespace: Entity.instantNamespace,
          path: field.name,
          localID: nil,
          operation: operation
        )
      }
      throw Self.notFoundError(query, operation: operation)
    }
    return try Value.decodeInstantValue(
      snapshot.values[field.name]?.first,
      namespace: Entity.instantNamespace,
      path: field.name,
      localID: snapshot.id,
      operation: operation
    )
  }
}

extension FetchOne
where
  Value: ExpressibleByNilLiteral & InstantValueDecodable & InstantValueRepresentable
{
  public init<Entity: InstantEntityModel>(
    _ field: InstantAttributePath<Entity, Value>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) {
    self.init(wrappedValue: Value(nilLiteral: ()), field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      _ field: InstantAttributePath<Entity, Value>,
      from query: InstantEntityQuery<Entity> = Entity.query,
      animation: Animation?
    ) {
      self.init(wrappedValue: Value(nilLiteral: ()), field, from: query)
    }
  #endif

  public init<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, Value>
  ) {
    self.init(wrappedValue: Value(nilLiteral: ()), field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel>(
      _ query: InstantEntityQuery<Entity>,
      selecting field: InstantAttributePath<Entity, Value>,
      animation: Animation?
    ) {
      self.init(wrappedValue: Value(nilLiteral: ()), field, from: query)
    }
  #endif
}

extension FetchOne {
  public init<Entity: InstantEntityModel, FieldValue>(
    wrappedValue: FieldValue? = nil,
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      Self.optionalScalarOperations(for: query, selecting: field),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel, FieldValue>(
      wrappedValue: FieldValue? = nil,
      _ field: InstantAttributePath<Entity, FieldValue>,
      from query: InstantEntityQuery<Entity> = Entity.query,
      animation: Animation?
    ) where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
      self.init(wrappedValue: wrappedValue, field, from: query)
    }
  #endif

  public init<Entity: InstantEntityModel, FieldValue>(
    wrappedValue: FieldValue? = nil,
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    self.init(wrappedValue: wrappedValue, field, from: query)
  }

  #if canImport(SwiftUI)
    public init<Entity: InstantEntityModel, FieldValue>(
      wrappedValue: FieldValue? = nil,
      _ query: InstantEntityQuery<Entity>,
      selecting field: InstantAttributePath<Entity, FieldValue>,
      animation: Animation?
    ) where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
      self.init(wrappedValue: wrappedValue, query, selecting: field)
    }
  #endif

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(field, from: query, using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    try await load(using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, selecting: field, using: client)
  }

  public func load<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await load(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws -> FetchSubscription<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(field, from: query, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    return try await subscribe(using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws -> FetchSubscription<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, selecting: field, using: client)
  }

  public func subscribe<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await subscribe(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(field, from: query, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ field: InstantAttributePath<Entity, FieldValue>,
    from query: InstantEntityQuery<Entity> = Entity.query,
    using client: InstantSwiftDataClient
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    configureOptionalScalarQuery(query, selecting: field)
    try await task(using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, selecting: field, using: client)
  }

  public func task<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>,
    using client: InstantSwiftDataClient
  ) async throws
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    try await task(field, from: query, using: client)
  }

  private func configureOptionalScalarQuery<Entity: InstantEntityModel, FieldValue>(
    _ query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    operations.value = Self.optionalScalarOperations(for: query, selecting: field)
  }

  private static func optionalScalarOperations<Entity: InstantEntityModel, FieldValue>(
    for query: InstantEntityQuery<Entity>,
    selecting field: InstantAttributePath<Entity, FieldValue>
  ) -> FetchOperations<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let selectedQuery = Self.limitOne(query.select(field))
    return FetchOperations(
      load: { client in
        try await optionalScalarValue(
          from: client.query(selectedQuery.plan),
          query: query,
          field: field,
          operation: "load FetchOne"
        )
      },
      subscribe: { client in
        await optionalScalarSubscription(
          client: client,
          query: query,
          selectedQuery: selectedQuery,
          field: field
        )
      }
    )
  }

  private static func optionalScalarSubscription<Entity: InstantEntityModel, FieldValue>(
    client: InstantSwiftDataClient,
    query: InstantEntityQuery<Entity>,
    selectedQuery: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, FieldValue>
  ) async -> FetchSubscription<Value>
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    let emissions = await client.observe(selectedQuery.plan)
    let stream = AsyncThrowingStream<Value, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(
            try optionalScalarValue(
              from: emission.values,
              query: query,
              field: field,
              operation: "subscribe FetchOne"
            )
          )
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
    return FetchSubscription<Value>(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }

  private static func optionalScalarValue<Entity: InstantEntityModel, FieldValue>(
    from snapshots: [InstantEntitySnapshot],
    query: InstantEntityQuery<Entity>,
    field: InstantAttributePath<Entity, FieldValue>,
    operation: String
  ) throws -> Value
  where Value == FieldValue?, FieldValue: InstantValueDecodable & InstantValueRepresentable {
    guard let snapshot = snapshots.first,
      let value = snapshot.values[field.name]?.first,
      value != .null
    else {
      return nil
    }
    return try FieldValue.decodeInstantValue(
      value,
      namespace: Entity.instantNamespace,
      path: field.name,
      localID: snapshot.id,
      operation: operation
    )
  }
}

public protocol InstantFetchKeyRequest: Sendable {
  associatedtype Value: Sendable

  var fetchRequest: InstantFetchRequest<Value> { get }
}

public struct InstantFetchRequest<Value: Sendable>: Sendable {
  fileprivate var loadOperation: @Sendable (InstantSwiftDataClient) async throws -> Value
  fileprivate var subscribeOperation:
    @Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>

  public func load() async throws -> Value {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws -> Value {
    try await loadOperation(client)
  }

  public func subscribe() async throws -> FetchSubscription<Value> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    try await subscribeOperation(client)
  }

  public init<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>,
    transform: @escaping @Sendable ([Entity]) throws -> Value
  ) {
    self.init(source: InstantFetchSource(query).map(transform))
  }

  public init<A: InstantEntityModel, B: InstantEntityModel>(
    _ a: InstantEntityQuery<A>,
    _ b: InstantEntityQuery<B>,
    transform: @escaping @Sendable ([A], [B]) throws -> Value
  ) {
    self.init(
      source: InstantFetchSource.zip(InstantFetchSource(a), InstantFetchSource(b))
        .map { try transform($0.0, $0.1) }
    )
  }

  public init<A: InstantEntityModel, B: InstantEntityModel, C: InstantEntityModel>(
    _ a: InstantEntityQuery<A>,
    _ b: InstantEntityQuery<B>,
    _ c: InstantEntityQuery<C>,
    transform: @escaping @Sendable ([A], [B], [C]) throws -> Value
  ) {
    self.init(
      source: InstantFetchSource.zip(
        InstantFetchSource.zip(InstantFetchSource(a), InstantFetchSource(b)),
        InstantFetchSource(c)
      )
      .map { try transform($0.0.0, $0.0.1, $0.1) }
    )
  }

  public init<
    A: InstantEntityModel, B: InstantEntityModel, C: InstantEntityModel,
    D: InstantEntityModel
  >(
    _ a: InstantEntityQuery<A>,
    _ b: InstantEntityQuery<B>,
    _ c: InstantEntityQuery<C>,
    _ d: InstantEntityQuery<D>,
    transform: @escaping @Sendable ([A], [B], [C], [D]) throws -> Value
  ) {
    self.init(
      source: InstantFetchSource.zip(
        InstantFetchSource.zip(
          InstantFetchSource.zip(InstantFetchSource(a), InstantFetchSource(b)),
          InstantFetchSource(c)
        ),
        InstantFetchSource(d)
      )
      .map { try transform($0.0.0.0, $0.0.0.1, $0.0.1, $0.1) }
    )
  }

  public init<
    A: InstantEntityModel, B: InstantEntityModel, C: InstantEntityModel,
    D: InstantEntityModel, E: InstantEntityModel
  >(
    _ a: InstantEntityQuery<A>,
    _ b: InstantEntityQuery<B>,
    _ c: InstantEntityQuery<C>,
    _ d: InstantEntityQuery<D>,
    _ e: InstantEntityQuery<E>,
    transform: @escaping @Sendable ([A], [B], [C], [D], [E]) throws -> Value
  ) {
    self.init(
      source: InstantFetchSource.zip(
        InstantFetchSource.zip(
          InstantFetchSource.zip(
            InstantFetchSource.zip(InstantFetchSource(a), InstantFetchSource(b)),
            InstantFetchSource(c)
          ),
          InstantFetchSource(d)
        ),
        InstantFetchSource(e)
      )
      .map { try transform($0.0.0.0.0, $0.0.0.0.1, $0.0.0.1, $0.0.1, $0.1) }
    )
  }

  public init<
    A: InstantEntityModel, B: InstantEntityModel, C: InstantEntityModel,
    D: InstantEntityModel, E: InstantEntityModel, F: InstantEntityModel
  >(
    _ a: InstantEntityQuery<A>,
    _ b: InstantEntityQuery<B>,
    _ c: InstantEntityQuery<C>,
    _ d: InstantEntityQuery<D>,
    _ e: InstantEntityQuery<E>,
    _ f: InstantEntityQuery<F>,
    transform: @escaping @Sendable ([A], [B], [C], [D], [E], [F]) throws -> Value
  ) {
    self.init(
      source: InstantFetchSource.zip(
        InstantFetchSource.zip(
          InstantFetchSource.zip(
            InstantFetchSource.zip(
              InstantFetchSource.zip(InstantFetchSource(a), InstantFetchSource(b)),
              InstantFetchSource(c)
            ),
            InstantFetchSource(d)
          ),
          InstantFetchSource(e)
        ),
        InstantFetchSource(f)
      )
      .map {
        try transform(
          $0.0.0.0.0.0,
          $0.0.0.0.0.1,
          $0.0.0.0.1,
          $0.0.0.1,
          $0.0.1,
          $0.1
        )
      }
    )
  }

  /// ADR 0015 — map root **snapshots** (include `links` preserved) into one value.
  ///
  /// Use when the request needs multi-bag children plus a single aggregate value
  /// (for example a list query value with attachments beside projected rows), not
  /// only a flat `[Row]` array.
  ///
  /// ```swift
  /// InstantFetchRequest(listQuery) { snapshots in
  ///   let decoded = try decodeMultiBag(snapshots)
  ///   return QueryValue(recordings: decoded.recordings, attachments: decoded.attachments)
  /// }
  /// ```
  public init<Root: InstantEntityModel>(
    snapshotsOf query: InstantEntityQuery<Root>,
    map: @escaping @Sendable (_ roots: [InstantEntitySnapshot]) throws -> Value
  ) {
    self.init(source: InstantFetchSource.entitySnapshots(query).map(map))
  }

  /// ADR 0015 L2 — request-time **map** of root + included reverse children.
  ///
  /// Loads `query` as snapshots (so include links are preserved), decodes each
  /// root and its named included children, then builds rows. The view only sees
  /// `[Row]` — it does not dig nested graphs.
  ///
  /// Prefer pairing with nested `.limit` on the include (L1):
  ///
  /// ```swift
  /// InstantFetchRequest(
  ///   Recording.query.include(Recording.segments, Segment.query.order(...).limit(2)),
  ///   children: Recording.segments,
  ///   map: { recording, segments in
  ///     ListRow(id: recording.id, preview: makeTwoLines(segments.map(\.text)))
  ///   }
  /// )
  /// ```
  public init<Root: InstantEntityModel, Child: InstantEntityModel, Row: Sendable>(
    _ query: InstantEntityQuery<Root>,
    children relation: InstantReverseRelation<Root, Child>,
    map: @escaping @Sendable (_ root: Root, _ children: [Child]) throws -> Row
  ) where Value == [Row] {
    let linkName = relation.name
    self.init(
      source: InstantFetchSource.entitySnapshots(query).map { snapshots in
        try snapshots.map { snapshot in
          let root = try Root(snapshot: snapshot)
          let children = try snapshot.decodeIncludedChildren(linkName, as: Child.self)
          return try map(root, children)
        }
      }
    )
  }

  /// ADR 0015 — multi-bag map: two reverse includes (e.g. segments + attachments).
  ///
  /// Both relations must be present on `query` via `.include`. Each bag is the
  /// typed array for that link name (empty if missing). Order of parameters
  /// matches the `children` arguments, not include declaration order.
  ///
  /// ```swift
  /// InstantFetchRequest(
  ///   Recording.query
  ///     .include(Recording.segments, Segment.query.limit(2))
  ///     .include(Recording.attachments, Attachment.query.limit(24)),
  ///   children: Recording.segments, Recording.attachments,
  ///   map: { recording, segments, attachments in ListRow(...) }
  /// )
  /// ```
  public init<
    Root: InstantEntityModel,
    ChildA: InstantEntityModel,
    ChildB: InstantEntityModel,
    Row: Sendable
  >(
    _ query: InstantEntityQuery<Root>,
    children relationA: InstantReverseRelation<Root, ChildA>,
    _ relationB: InstantReverseRelation<Root, ChildB>,
    map: @escaping @Sendable (
      _ root: Root,
      _ childrenA: [ChildA],
      _ childrenB: [ChildB]
    ) throws -> Row
  ) where Value == [Row] {
    let nameA = relationA.name
    let nameB = relationB.name
    self.init(
      source: InstantFetchSource.entitySnapshots(query).map { snapshots in
        try snapshots.map { snapshot in
          let root = try Root(snapshot: snapshot)
          let a = try snapshot.decodeIncludedChildren(nameA, as: ChildA.self)
          let b = try snapshot.decodeIncludedChildren(nameB, as: ChildB.self)
          return try map(root, a, b)
        }
      }
    )
  }

  private init(source: InstantFetchSource<Value>) {
    self.loadOperation = source.load
    self.subscribeOperation = source.subscribe
  }
}

private struct InstantFetchSource<Value: Sendable>: Sendable {
  var load: @Sendable (InstantSwiftDataClient) async throws -> Value
  var subscribe: @Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>

  init<Entity: InstantEntityModel>(_ query: InstantEntityQuery<Entity>)
  where Value == [Entity] {
    self.load = { try await $0.query(query) }
    self.subscribe = { await $0.subscribe(query) }
  }

  /// Snapshot stream — keeps include `links` for request-time map (ADR 0015 L2).
  static func entitySnapshots<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) -> InstantFetchSource<[InstantEntitySnapshot]> where Value == [InstantEntitySnapshot] {
    let plan = query.plan
    return InstantFetchSource<[InstantEntitySnapshot]>(
      load: { try await $0.query(plan) },
      subscribe: { client in
        let emissions = await client.observe(plan)
        let stream = AsyncThrowingStream<[InstantEntitySnapshot], Error>.makeStream(
          bufferingPolicy: .bufferingNewest(1)
        )
        let task = Task {
          for await emission in emissions {
            do {
              try Task.checkCancellation()
              stream.continuation.yield(emission.values)
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
    )
  }

  private init(
    load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    subscribe: @escaping @Sendable (InstantSwiftDataClient) async throws
      -> FetchSubscription<Value>
  ) {
    self.load = load
    self.subscribe = subscribe
  }

  func map<Mapped: Sendable>(
    _ transform: @escaping @Sendable (Value) throws -> Mapped
  ) -> InstantFetchSource<Mapped> {
    InstantFetchSource<Mapped>(
      load: { try transform(try await load($0)) },
      subscribe: { try await subscribe($0).map(transform) }
    )
  }

  static func zip<A: Sendable, B: Sendable>(
    _ a: InstantFetchSource<A>,
    _ b: InstantFetchSource<B>
  ) -> InstantFetchSource<(A, B)> where Value == (A, B) {
    InstantFetchSource<(A, B)>(
      load: { client in
        async let aValue = a.load(client)
        async let bValue = b.load(client)
        return try await (aValue, bValue)
      },
      subscribe: { client in
        async let aSubscription = a.subscribe(client)
        async let bSubscription = b.subscribe(client)
        return try await combineLatest(aSubscription, bSubscription)
      }
    )
  }
}

private actor InstantFetchLatestPair<A: Sendable, B: Sendable> {
  private var a: A?
  private var b: B?

  func updateA(_ value: A) -> (A, B)? {
    a = value
    return latest
  }

  func updateB(_ value: B) -> (A, B)? {
    b = value
    return latest
  }

  private var latest: (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
  }
}

private func combineLatest<A: Sendable, B: Sendable>(
  _ a: FetchSubscription<A>,
  _ b: FetchSubscription<B>
) -> FetchSubscription<(A, B)> {
  let stream = AsyncThrowingStream<(A, B), Error>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
  )
  let latest = InstantFetchLatestPair<A, B>()
  let task = Task {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          for try await value in a {
            try Task.checkCancellation()
            if let pair = await latest.updateA(value) {
              stream.continuation.yield(pair)
            }
          }
        }
        group.addTask {
          for try await value in b {
            try Task.checkCancellation()
            if let pair = await latest.updateB(value) {
              stream.continuation.yield(pair)
            }
          }
        }
        try await group.waitForAll()
      }
      stream.continuation.finish()
    } catch {
      stream.continuation.finish(throwing: error)
    }
    a.cancel()
    b.cancel()
  }
  stream.continuation.onTermination = { @Sendable _ in
    task.cancel()
    a.cancel()
    b.cancel()
  }
  return FetchSubscription<(A, B)>(stream: stream.stream) {
    task.cancel()
    a.cancel()
    b.cancel()
    stream.continuation.finish()
  }
}

@dynamicMemberLookup
@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<Value>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<Value>
  #endif
  private let operations: FetchOperationStorage<Value>

  private var storage: FetchStorage<Value> { storageReference.value }

  public var wrappedValue: Value {
    get {
      operations.startAutomaticObservationIfNeeded(storage: storage)
      return storage.wrappedValue
    }
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
    public var publisher: some Publisher<Value, Never> {
      Just<Void>(()).flatMap { _ in
        operations.startAutomaticObservationIfNeeded(storage: storage)
        return storage.objectWillChange
          .map { storage.wrappedValue }
          .prepend(storage.wrappedValue)
      }
    }
  #endif

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage()
  }

  #if canImport(SwiftUI)
    public init(
      wrappedValue: Value,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue)
    }
  #endif

  public init(
    wrappedValue: Value,
    load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)? = nil
  ) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(
      FetchOperations(load: load, subscribe: subscribe),
      storage: storage
    )
  }

  #if canImport(SwiftUI)
    public init(
      wrappedValue: Value,
      load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
      subscribe: (@Sendable (InstantSwiftDataClient) async throws -> FetchSubscription<Value>)? =
        nil,
      animation: Animation?
    ) {
      self.init(wrappedValue: wrappedValue, load: load, subscribe: subscribe)
    }
  #endif

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      storage.initialValue = newValue.storage.initialValue
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
    storage.cancelActiveSubscription()
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
      if let subscribe = operations.value.subscribe {
        storage.enableAutomaticObservation()
        startAutomaticFetchObservation(storage: storage, using: client, subscribe: subscribe)
      }
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> {
    guard let subscribeOperation = operations.value.subscribe else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe Fetch",
        message: "No Instant subscription operation has been configured for this fetch wrapper.",
        recovery:
          "Initialize @Fetch with a subscribe operation, or pass an operation to subscribe(_:using:)."
      )
    }

    do {
      return try await subscribeOperation(client)
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe Fetch",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and fetch subscription operation."
      )
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
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe Fetch",
      recovery: "Inspect the configured InstantSwiftDataClient and fetch subscription operation."
    )
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

extension Fetch {
  public init<Request: InstantFetchKeyRequest>(
    wrappedValue: Value,
    _ request: Request
  ) where Request.Value == Value {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.operations = FetchOperationStorage(Self.operations(for: request), storage: storage)
  }

  #if canImport(SwiftUI)
    public init<Request: InstantFetchKeyRequest>(
      wrappedValue: Value,
      _ request: Request,
      animation: Animation?
    ) where Request.Value == Value {
      self.init(wrappedValue: wrappedValue, request)
    }
  #endif

  public func load<Request: InstantFetchKeyRequest>(
    _ request: Request
  ) async throws where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(request, using: client)
  }

  public func load<Request: InstantFetchKeyRequest>(
    _ request: Request,
    using client: InstantSwiftDataClient
  ) async throws where Request.Value == Value {
    storage.cancelActiveSubscription()
    operations.value = Self.operations(for: request)
    try await load(using: client)
  }

  public func load<Request: InstantFetchKeyRequest>(
    _ request: Request?
  ) async throws where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(request, using: client)
  }

  public func load<Request: InstantFetchKeyRequest>(
    _ request: Request?,
    using client: InstantSwiftDataClient
  ) async throws where Request.Value == Value {
    guard let request else {
      clearRequest()
      return
    }
    try await load(request, using: client)
  }

  public func subscribe<Request: InstantFetchKeyRequest>(
    _ request: Request
  ) async throws -> FetchSubscription<Value> where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(request, using: client)
  }

  public func subscribe<Request: InstantFetchKeyRequest>(
    _ request: Request,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> where Request.Value == Value {
    storage.cancelActiveSubscription()
    operations.value = Self.operations(for: request)
    return try await subscribe(using: client)
  }

  public func subscribe<Request: InstantFetchKeyRequest>(
    _ request: Request?
  ) async throws -> FetchSubscription<Value> where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(request, using: client)
  }

  public func subscribe<Request: InstantFetchKeyRequest>(
    _ request: Request?,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Value> where Request.Value == Value {
    guard let request else {
      clearRequest()
      return .finished()
    }
    return try await subscribe(request, using: client)
  }

  public func task<Request: InstantFetchKeyRequest>(
    _ request: Request
  ) async throws where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(request, using: client)
  }

  public func task<Request: InstantFetchKeyRequest>(
    _ request: Request,
    using client: InstantSwiftDataClient
  ) async throws where Request.Value == Value {
    operations.value = Self.operations(for: request)
    try await task(using: client)
  }

  public func task<Request: InstantFetchKeyRequest>(
    _ request: Request?
  ) async throws where Request.Value == Value {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(request, using: client)
  }

  public func task<Request: InstantFetchKeyRequest>(
    _ request: Request?,
    using client: InstantSwiftDataClient
  ) async throws where Request.Value == Value {
    guard let request else {
      clearRequest()
      return
    }
    try await task(request, using: client)
  }

  private func clearRequest() {
    storage.cancelActiveSubscription()
    operations.value = FetchOperations()
    storage.resetToInitialValue()
    loadError = nil
    isLoading = false
  }

  private static func operations<Request: InstantFetchKeyRequest>(
    for request: Request
  ) -> FetchOperations<Value> where Request.Value == Value {
    FetchOperations(
      load: { client in
        try await request.fetchRequest.loadOperation(client)
      },
      subscribe: { client in
        try await request.fetchRequest.subscribeOperation(client)
      }
    )
  }
}

@propertyWrapper
public struct ConnectionStatus: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<InstantConnectionStatus>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<InstantConnectionStatus>
  #endif

  private var storage: FetchStorage<InstantConnectionStatus> { storageReference.value }

  public var wrappedValue: InstantConnectionStatus {
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
    public var binding: Binding<InstantConnectionStatus> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init() {
    let storage = FetchStorage(value: Self.defaultConnectingStatus)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
  }

  public init(wrappedValue: InstantConnectionStatus) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
      let status = try await client.connectionStatus()
      try Task.checkCancellation()
      wrappedValue = status
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
        operation: "load ConnectionStatus",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient connection status operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public func subscribe() async throws -> FetchSubscription<InstantConnectionStatus> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<InstantConnectionStatus> {
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<InstantConnectionStatus> {
    do {
      try Task.checkCancellation()
      return try await client.subscribeConnectionStatus()
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe ConnectionStatus",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient connection status observer."
      )
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "task ConnectionStatus",
      recovery: "Inspect the configured InstantSwiftDataClient connection status observer."
    )
  }

  private static var defaultConnectingStatus: InstantConnectionStatus {
    InstantConnectionStatus(
      appID: "",
      apiURI: InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
      transport: .localCacheOnly,
      state: .connecting,
      isAuthenticated: false,
      userID: nil,
      pendingMutationCount: 0,
      processedTransactionID: nil
    )
  }
}

@propertyWrapper
public struct AuthSession: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<InstantAuthSession?>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<InstantAuthSession?>
  #endif

  private var storage: FetchStorage<InstantAuthSession?> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
    }
  }

  public func requireUser() throws -> InstantAuthSession {
    guard let session = wrappedValue else {
      throw InstantError(
        code: .authFailed,
        operation: "access AuthSession user",
        message: "useUser must be used within an auth-protected route",
        recovery:
          "Load or subscribe to @AuthSession in an auth-protected flow before requiring a user."
      )
    }
    return session
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<InstantAuthSession?> {
    do {
      try Task.checkCancellation()
      return try await client.subscribeAuthSession()
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe AuthSession",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient auth observation operation."
      )
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe AuthSession",
      recovery: "Inspect the configured InstantSwiftDataClient auth observation operation."
    )
  }
}

@propertyWrapper
public struct RoomPresence: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<[InstantRoomPresenceMember]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[InstantRoomPresenceMember]>
  #endif
  private let room: LockedValueStorage<InstantRoomHandle?>

  private var storage: FetchStorage<[InstantRoomPresenceMember]> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.room = LockedValueStorage(nil)
  }

  public init(_ type: String, _ id: String) {
    let storage = FetchStorage<[InstantRoomPresenceMember]>(value: [])
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.room = LockedValueStorage(InstantRoomHandle(type: type, id: id))
  }

  public init(room: InstantRoomHandle) {
    let storage = FetchStorage<[InstantRoomPresenceMember]>(value: [])
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.room = LockedValueStorage(room)
  }

  public init(wrappedValue: [InstantRoomPresenceMember], _ type: String, _ id: String) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.room = LockedValueStorage(InstantRoomHandle(type: type, id: id))
  }

  public init(wrappedValue: [InstantRoomPresenceMember], room: InstantRoomHandle) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    guard let room = room.value else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomPresence",
        message: "No Instant room has been configured for this wrapper.",
        recovery: "Initialize @RoomPresence with a room, or pass a room to subscribe(_:_:using:)."
      )
    }
    return try await makeSubscription(room: room, using: client)
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
    loadError = nil
    do {
      return try await makeSubscription(room: room, using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    room: InstantRoomHandle,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomPresenceMember]> {
    do {
      try Task.checkCancellation()
      return try await client.subscribeRoomPresence(room: room)
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomPresence",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room presence observer."
      )
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
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe RoomPresence",
      recovery: "Inspect the configured InstantSwiftDataClient room presence observer."
    )
  }
}

private struct RoomTopicMessagesConfiguration: Sendable {
  var room: InstantRoomHandle?
  var topic: String?
  var limit: Int?
}

@propertyWrapper
public struct RoomTopicMessages: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<[InstantRoomTopicMessage]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[InstantRoomTopicMessage]>
  #endif
  private let configuration: LockedValueStorage<RoomTopicMessagesConfiguration>

  private var storage: FetchStorage<[InstantRoomTopicMessage]> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(room: nil, topic: nil, limit: nil)
    )
  }

  public init(_ type: String, _ id: String, _ topic: String, limit: Int? = nil) {
    let storage = FetchStorage<[InstantRoomTopicMessage]>(value: [])
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.configuration = LockedValueStorage(
      RoomTopicMessagesConfiguration(
        room: InstantRoomHandle(type: type, id: id),
        topic: topic,
        limit: limit
      )
    )
  }

  public init(room: InstantRoomHandle, topic: String, limit: Int? = nil) {
    let storage = FetchStorage<[InstantRoomTopicMessage]>(value: [])
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    let configuration = configuration.value
    guard let room = configuration.room, let topic = configuration.topic else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomTopicMessages",
        message: "No Instant room topic has been configured for this wrapper.",
        recovery:
          "Initialize @RoomTopicMessages with a room and topic, or pass them to subscribe(_:_:_:using:)."
      )
    }
    return try await makeSubscription(
      room: room,
      topic: topic,
      limit: configuration.limit,
      using: client
    )
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
    loadError = nil
    do {
      return try await makeSubscription(room: room, topic: topic, limit: limit, using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantRoomTopicMessage]> {
    do {
      try Self.validateLimit(limit, operation: "subscribe RoomTopicMessages")
      try Task.checkCancellation()
      return try await client.subscribeRoomTopicMessages(
        room: room,
        topic: topic,
        limit: limit
      )
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe RoomTopicMessages",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room topic observer."
      )
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
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe RoomTopicMessages",
      recovery: "Inspect the configured InstantSwiftDataClient room topic observer."
    )
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
  private let storageReference: LockedValueStorage<FetchStorage<[InstantStoredFile]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[InstantStoredFile]>
  #endif

  private var storage: FetchStorage<[InstantStoredFile]> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStoredFile]> {
    do {
      try Task.checkCancellation()
      return try await client.subscribeStoredFiles()
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe StoredFiles",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stored files observer."
      )
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe StoredFiles",
      recovery: "Inspect the configured InstantSwiftDataClient stored files observer."
    )
  }
}

private struct StreamChunksConfiguration: Sendable {
  var streamID: String?
  var limit: Int?
  var afterIndex: Int64?
}

// SAFETY: stream chunk configuration is protected by `lock`.
private final class StreamChunksConfigurationStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var configuration: StreamChunksConfiguration

  init(streamID: String?, limit: Int?, afterIndex: Int64?) {
    self.configuration = StreamChunksConfiguration(
      streamID: streamID,
      limit: limit,
      afterIndex: afterIndex
    )
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

  func set(streamID: String, limit: Int?, afterIndex: Int64?) {
    set(StreamChunksConfiguration(streamID: streamID, limit: limit, afterIndex: afterIndex))
  }
}

@propertyWrapper
public struct StreamChunks: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<[InstantStreamChunk]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[InstantStreamChunk]>
  #endif
  private let configuration: StreamChunksConfigurationStorage

  private var storage: FetchStorage<[InstantStreamChunk]> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.configuration = StreamChunksConfigurationStorage(
      streamID: nil,
      limit: nil,
      afterIndex: nil
    )
  }

  public init(_ streamID: String, limit: Int? = nil, afterIndex: Int64? = nil) {
    let storage = FetchStorage<[InstantStreamChunk]>(value: [])
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.configuration = StreamChunksConfigurationStorage(
      streamID: streamID,
      limit: limit,
      afterIndex: afterIndex
    )
  }

  public init(
    wrappedValue: [InstantStreamChunk],
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) {
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
    self.configuration = StreamChunksConfigurationStorage(
      streamID: streamID,
      limit: limit,
      afterIndex: afterIndex
    )
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
    try await load(
      streamID,
      limit: configuration.limit,
      afterIndex: configuration.afterIndex,
      using: client
    )
  }

  public func load(_ streamID: String, limit: Int? = nil, afterIndex: Int64? = nil) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(streamID, limit: limit, afterIndex: afterIndex, using: client)
  }

  public func load(
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    configuration.set(streamID: streamID, limit: limit, afterIndex: afterIndex)
    isLoading = true
    do {
      try Self.validateLimit(limit, operation: "load StreamChunks")
      try Self.validateAfterIndex(afterIndex, operation: "load StreamChunks")
      let chunks = try await client.streamChunks(
        streamID: streamID,
        limit: limit,
        afterIndex: afterIndex
      )
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    let configuration = configuration.value
    guard let streamID = configuration.streamID else {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe StreamChunks",
        message: "No Instant stream id has been configured for this wrapper.",
        recovery: "Initialize @StreamChunks with a stream id, or pass one to subscribe(_:using:)."
      )
    }
    return try await makeSubscription(
      streamID,
      limit: configuration.limit,
      afterIndex: configuration.afterIndex,
      using: client
    )
  }

  public func subscribe(
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(streamID, limit: limit, afterIndex: afterIndex, using: client)
  }

  public func subscribe(
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    configuration.set(streamID: streamID, limit: limit, afterIndex: afterIndex)
    loadError = nil
    do {
      return try await makeSubscription(
        streamID,
        limit: limit,
        afterIndex: afterIndex,
        using: client
      )
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantStreamChunk]> {
    do {
      try Self.validateLimit(limit, operation: "subscribe StreamChunks")
      try Self.validateAfterIndex(afterIndex, operation: "subscribe StreamChunks")
      try Task.checkCancellation()
      return try await client.subscribeStreamChunks(
        streamID: streamID,
        limit: limit,
        afterIndex: afterIndex
      )
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe StreamChunks",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient stream chunks observer."
      )
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(_ streamID: String, limit: Int? = nil, afterIndex: Int64? = nil) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(streamID, limit: limit, afterIndex: afterIndex, using: client)
  }

  public func task(
    _ streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil,
    using client: InstantSwiftDataClient
  ) async throws {
    configuration.set(streamID: streamID, limit: limit, afterIndex: afterIndex)
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe StreamChunks",
      recovery: "Inspect the configured InstantSwiftDataClient stream chunks observer."
    )
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

  private static func validateAfterIndex(_ afterIndex: Int64?, operation: String) throws {
    guard let afterIndex, afterIndex < 0 else { return }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Stream chunk after-index must be greater than or equal to 0.",
      recovery:
        "Pass a previously emitted chunk index, or omit afterIndex to observe every local chunk."
    )
  }
}

@propertyWrapper
public struct Shares: Sendable {
  private let storageReference: LockedValueStorage<FetchStorage<[InstantShareSnapshot]>>
  #if canImport(SwiftUI)
    @StateObject private var storageObserver: FetchStorage<[InstantShareSnapshot]>
  #endif

  private var storage: FetchStorage<[InstantShareSnapshot]> { storageReference.value }

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
    let storage = FetchStorage(value: wrappedValue)
    self.storageReference = LockedValueStorage(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
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
    loadError = nil
    do {
      return try await makeSubscription(using: client)
    } catch let error as CancellationError {
      loadError = nil
      throw error
    } catch let error as InstantError {
      loadError = error
      throw error
    }
  }

  private func makeSubscription(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[InstantShareSnapshot]> {
    do {
      try Task.checkCancellation()
      return try await client.subscribeShares()
    } catch let error as CancellationError {
      throw error
    } catch let error as InstantError {
      throw error
    } catch {
      throw InstantError(
        code: .implementationFailed,
        operation: "subscribe Shares",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient shares observer."
      )
    }
  }

  public func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public func task(using client: InstantSwiftDataClient) async throws {
    try await runFetchStorageSubscriptionTask(
      storage: storage,
      subscribe: { try await makeSubscription(using: client) },
      operation: "observe Shares",
      recovery: "Inspect the configured InstantSwiftDataClient shares observer."
    )
  }
}

#if canImport(SwiftUI)
  @MainActor
  extension InfiniteQuery: DynamicProperty {
    public mutating func update() {
      storageReference.value = storageObserver
    }
  }
  @MainActor
  extension FetchAll: DynamicProperty {
    public mutating func update() {
      storageReference.value = storageObserver
      operations.startAutomaticObservationIfNeeded(storage: storageObserver)
    }
  }
  @MainActor extension FetchOne: DynamicProperty {
    public mutating func update() {
      storageReference.value = storageObserver
      operations.startAutomaticObservationIfNeeded(storage: storageObserver)
    }
  }
  @MainActor extension Fetch: DynamicProperty {
    public mutating func update() {
      storageReference.value = storageObserver
      operations.startAutomaticObservationIfNeeded(storage: storageObserver)
    }
  }
  @MainActor extension ConnectionStatus: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension AuthSession: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension RoomPresence: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension RoomTopicMessages: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension StoredFiles: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension StreamChunks: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
  @MainActor extension Shares: DynamicProperty {
    public mutating func update() { storageReference.value = storageObserver }
  }
#endif

// SAFETY: lifecycle task access is serialized by `lock`; value access delegates
// to the wrapper's already thread-safe fetch storage.
private final class LocalIDLifecycleStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var didStart = false
  private var task: Task<Void, Never>?
  fileprivate let storage: FetchStorage<String?>
  fileprivate let name: LockedValueStorage<String?>

  #if canImport(SwiftUI)
    let objectWillChange = ObservableObjectPublisher()
  #endif

  init(value: String?, name: String?) {
    self.storage = FetchStorage(value: value)
    self.name = LockedValueStorage(name)
  }

  func start(_ operation: @escaping @Sendable () async -> Void) {
    let shouldStart = withLock {
      guard !didStart else { return false }
      didStart = true
      return true
    }
    guard shouldStart else { return }

    let task = Task {
      await operation()
    }
    withLock {
      self.task = task
    }
  }

  func publishChange() {
    #if canImport(SwiftUI)
      if Thread.isMainThread {
        objectWillChange.send()
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.objectWillChange.send()
        }
      }
    #endif
  }

  deinit {
    task?.cancel()
  }

  private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

#if canImport(SwiftUI)
  extension LocalIDLifecycleStorage: ObservableObject {}
#endif

@propertyWrapper
// SAFETY: cross-actor value access is routed through lock-protected storage;
// SwiftUI's lifecycle observer is accessed only by the main-actor update hook.
public struct LocalID: @unchecked Sendable {
  private let lifecycleReference: LockedValueStorage<LocalIDLifecycleStorage>

  #if canImport(SwiftUI)
    @StateObject private var lifecycleObserver: LocalIDLifecycleStorage
  #endif

  private var lifecycle: LocalIDLifecycleStorage {
    lifecycleReference.value
  }

  public var wrappedValue: String? {
    get { lifecycle.storage.wrappedValue }
    nonmutating set {
      lifecycle.publishChange()
      lifecycle.storage.wrappedValue = newValue
    }
  }

  public var loadError: InstantError? {
    get { lifecycle.storage.loadError }
    nonmutating set {
      lifecycle.publishChange()
      lifecycle.storage.loadError = newValue
    }
  }

  public var isLoading: Bool {
    get { lifecycle.storage.isLoading }
    nonmutating set {
      lifecycle.publishChange()
      lifecycle.storage.isLoading = newValue
    }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<String?> {
      Binding(
        get: { lifecycle.storage.wrappedValue },
        set: {
          lifecycle.publishChange()
          lifecycle.storage.wrappedValue = $0
        }
      )
    }
  #endif

  public init(wrappedValue: String? = nil) {
    self.init(initialValue: wrappedValue, name: nil)
  }

  public init(_ name: String) {
    self.init(initialValue: nil, name: name)
  }

  public init(wrappedValue: String?, _ name: String) {
    self.init(initialValue: wrappedValue, name: name)
  }

  public init(wrappedValue: String? = nil, name: String) {
    self.init(initialValue: wrappedValue, name: name)
  }

  private init(initialValue: String?, name: String?) {
    let lifecycle = LocalIDLifecycleStorage(value: initialValue, name: name)
    self.lifecycleReference = LockedValueStorage(lifecycle)
    #if canImport(SwiftUI)
      self._lifecycleObserver = StateObject(wrappedValue: lifecycle)
    #endif
  }

  public var projectedValue: Self {
    get { self }
    nonmutating set {
      wrappedValue = newValue.wrappedValue
      loadError = newValue.loadError
      isLoading = newValue.isLoading
      lifecycle.name.value = newValue.lifecycle.name.value
    }
  }

  public func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public func load(using client: InstantSwiftDataClient) async throws {
    guard let name = lifecycle.name.value else {
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
    lifecycle.name.value = name
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

#if canImport(SwiftUI)
  @MainActor
  extension LocalID: DynamicProperty {
    public mutating func update() {
      lifecycleReference.value = lifecycleObserver
      guard wrappedValue == nil, loadError == nil else { return }
      let localID = self
      lifecycle.start {
        do {
          try await localID.load()
        } catch is CancellationError {
        } catch {
          // LocalID records renderable failures in loadError.
        }
      }
    }
  }
#endif
