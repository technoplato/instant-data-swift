import Foundation

/// Whether a write that failed can succeed if it is tried again (#482 part C).
///
/// Scribe's save lane retries the write at its head until it succeeds, and it cannot tell "this will never succeed"
/// from "try again later" without asking. `transact`, `save` and `delete` commit locally first and return; a server
/// refusal arrives later as a failed mutation (``PendingMutation/failureKind``). So what they throw is a local failure,
/// and its kind says whether trying the same write again can help.
public enum InstantWriteFailureKind: Hashable, Codable, Sendable {
  /// The write can never succeed as written. The rejection says why.
  case rejected(InstantWriteRejection)
  /// The write may succeed later: offline or a failed connection, a cancelled call, a busy or failing local disk, or
  /// a local store that changed under the write until it gave up.
  case transient
  /// The library cannot tell.
  case unknown

  /// Classifies any error a write throws.
  ///
  /// An ``InstantWriteFailureClassifying`` error, such as every ``InstantError``, classifies itself. A
  /// `CancellationError` is transient. An `EncodingError` is a value that cannot be encoded, so it is rejected as an
  /// invalid value. A `URLError` that says the network is unreachable is transient. Anything else is unknown.
  public init(classifying error: any Error) {
    switch error {
    case let classifying as any InstantWriteFailureClassifying:
      self = classifying.writeFailureKind
    case is CancellationError:
      self = .transient
    case is EncodingError:
      self = .rejected(.invalidValue)
    case let urlError as URLError:
      self = Self.kind(of: urlError)
    default:
      self = .unknown
    }
  }

  private static func kind(of error: URLError) -> Self {
    switch error.code {
    case .cancelled, .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
      .cannotFindHost, .dnsLookupFailed:
      .transient
    default:
      .unknown
    }
  }

  /// The kind of a failure the server reported, or nil when the failure carries nothing from the server.
  ///
  /// A failure the library retries by itself (`InstantAutomaticFailedMutationRetryPolicy`), a request timeout, a rate
  /// limit or a server error (5xx) is transient. Any other 4xx is a refusal that repeats. A type without a status is
  /// unknown.
  static func serverFailureKind(status: Int?, type: String?, message: String) -> Self? {
    if InstantAutomaticFailedMutationRetryPolicy.isRetryableFailureMessage(message) {
      return .transient
    }
    if let status {
      if [408, 425, 429].contains(status) || (500...599).contains(status) {
        return .transient
      }
      if (400...499).contains(status) {
        return .rejected(.refusedByServer)
      }
      return .unknown
    }
    return type == nil ? nil : .unknown
  }
}

/// Why a write can never succeed as written.
public enum InstantWriteRejection: String, Hashable, Codable, Sendable, CaseIterable {
  /// The write names a namespace, attribute, link or lookup attribute the schema does not declare.
  case unknownAttribute
  /// A value does not fit its attribute: the wrong type, null for a required attribute, or a non-finite number.
  case invalidValue
  /// The write breaks another rule: a merge on a link, a lookup by an attribute that is not unique, a strict create of
  /// an entity that exists, a transaction id another confirmed or failed write already uses, or a write larger than
  /// the delivery limits.
  case invalidWrite
  /// A permission rule refused the write, on this device or on the server.
  case permissionDenied
  /// The server refused the write for another reason.
  case refusedByServer
}

/// An error that says whether the write that threw it can succeed if it is tried again.
public protocol InstantWriteFailureClassifying: Error {
  var writeFailureKind: InstantWriteFailureKind { get }
}

extension InstantError: InstantWriteFailureClassifying {
  /// Whether the write that threw this error can succeed if it is tried again (#482).
  ///
  /// Derived from the error's code, operation and message, which the library sets at each throw site; the mapping is
  /// pinned by `InstantWriteFailureKindTests`, so a renamed operation or reworded message fails a test instead of
  /// changing a classification.
  public var writeFailureKind: InstantWriteFailureKind {
    switch code {
    case .permissionRejected:
      return .rejected(.permissionDenied)
    case .networkFailed:
      return .transient
    case .validationFailed:
      return validationFailureKind
    case .persistenceFailed:
      return persistenceFailureKind
    case .authFailed, .decodeFailed, .implementationFailed:
      return .unknown
    }
  }

  private var validationFailureKind: InstantWriteFailureKind {
    let text = self.message.lowercased()
    // The row or fact may still arrive by sync from another device, so these are not permanent.
    if operation == "strict update entity" || operation == "require triple" {
      return .unknown
    }
    if text.contains("matched more than one local entity") {
      return .unknown
    }
    if let serverKind = InstantWriteFailureKind.serverFailureKind(
      status: serverStatus,
      type: serverType,
      message: self.message
    ) {
      return serverKind
    }
    if text.contains("does not exist in the local schema")
      || text.contains("no attribute named")
      || text.contains("no ref attribute named")
      || text.contains("require a declared destination attribute")
    {
      return .rejected(.unknownAttribute)
    }
    if text.contains("invalid value for attribute")
      || text.contains("non-finite number")
      || text.contains("does not match the declared type")
      || text.contains("cannot be set to null")
      || text.contains("requires a reference value")
    {
      return .rejected(.invalidValue)
    }
    return .rejected(.invalidWrite)
  }

  private var persistenceFailureKind: InstantWriteFailureKind {
    let text = self.message.lowercased()
    // SQLite's own messages for a busy or failing disk (`sqlite3ErrStr`): SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR,
    // SQLITE_FULL and SQLITE_NOMEM. A write that kept losing revision races to other writers gave up after five tries.
    if text.contains("database is locked")
      || text.contains("database table is locked")
      || text.contains("disk i/o error")
      || text.contains("database or disk is full")
      || text.contains("out of memory")
      || text.contains("changed repeatedly")
    {
      return .transient
    }
    return .unknown
  }
}

extension PendingMutation {
  /// For a failed mutation, whether trying it again can succeed; nil unless ``status`` is `.failed` (#482).
  ///
  /// A permission refusal is rejected as `permissionDenied`. A failure the library retries by itself, such as a server
  /// timeout or an attribute it could not resolve yet, is transient. Any other refusal with a 4xx status is rejected as
  /// `refusedByServer`. A write the library set aside for exceeding the delivery limits is rejected as `invalidWrite`.
  /// Anything else is unknown.
  public var failureKind: InstantWriteFailureKind? {
    guard status == .failed else { return nil }
    let message = failure?.message ?? failureMessage ?? ""
    if (failure?.code ?? Self.failureCode(message: failureMessage)) == .permissionRejected {
      return .rejected(.permissionDenied)
    }
    if let serverKind = InstantWriteFailureKind.serverFailureKind(
      status: failure?.status,
      type: failure?.type,
      message: message
    ) {
      return serverKind
    }
    if message.contains("automatic-delivery limit") {
      return .rejected(.invalidWrite)
    }
    return .unknown
  }
}
