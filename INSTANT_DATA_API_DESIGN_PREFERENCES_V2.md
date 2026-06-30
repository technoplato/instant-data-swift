# Instant Data API Design Preferences, Version 2

This is the second working draft of the public API design preferences for
Instant Swift Data. It is a sibling of `INSTANT_DATA_API_DESIGN_PREFERENCES.md`
so the earlier draft stays intact while the design gets sharper.

Status:

- Working draft.
- The API is hypothetical unless explicitly called out as already present.
- The examples are intentionally "kitchen sink" examples so we can react to the
  feel of the API before implementation hardens around the wrong shape.
- Screen-level sketches now live in `screens/`. Each screen names a typed URI,
  includes an ASCII sketch, and shows a full SwiftUI example using this V2 API
  direction.
- Official Instant auth docs checked on 2026-06-30:
  - `https://www.instantdb.com/docs/auth`
  - `https://www.instantdb.com/docs/auth/magic-codes`
  - `https://www.instantdb.com/docs/auth/guest-auth`
  - `https://www.instantdb.com/docs/auth/google-oauth`
  - `https://www.instantdb.com/docs/auth/apple`
  - `https://www.instantdb.com/docs/auth/github-oauth`
  - `https://www.instantdb.com/docs/auth/linkedin-oauth`
  - `https://www.instantdb.com/docs/auth/clerk`
  - `https://www.instantdb.com/docs/auth/firebase`
- Official Instant streams docs checked on 2026-06-30:
  - `https://www.instantdb.com/docs/streams`

## V2 Direction

Instant Swift Data should feel like a Point-Free Swift library that happens to
be backed by InstantDB.

That means:

- The app author writes Swift types, generated symbols, property wrappers,
  dependency bootstrap, drafts, and observable models.
- The data model is still InstantDB-native: graph links, realtime observation,
  auth, permissions, storage, rooms, presence, topics, streams, optimistic
  writes, offline cache, and a durable outbox are first-class.
- The API should avoid magic strings for namespaces, attributes, relation names,
  permission paths, room topics, storage paths, and stream names.
- Runtime validation remains important because server data, permissions, auth,
  and transport can fail. But obvious type mismatches should fail at compile
  time or macro expansion time.

## Screen Sketches

The current screen sketches are:

- `screens/auth-login.md` for `auth.login`.
- `screens/recordings-list.md` for `recordings.index`.
- `screens/recording.md` for `recordings.capture`.
- `screens/playback.md` for `recordings.playback`.
- `screens/preferences.md` for `settings.preferences`.

These files are not implementation requirements yet. They are syntax probes for
the end-state app code we want to make possible.

## Bootstrap

Recommended shape:

```swift
import Dependencies
import InstantSwiftData

@main
struct VoiceTrailApp: App {
  init() {
    prepareDependencies {
      $0.defaultInstantSwiftData = try .live(
        appID: Secrets.instantAppID,
        schema: VoiceTrailSchema.self,
        auth: .providers(VoiceTrailAuth.self),
        permissions: VoiceTrailPermissions.self,
        persistence: .sqlite(.applicationSupport("VoiceTrail.sqlite")),
        sharing: .enabled(VoiceTrailSharing.self),
        sync: .automatic
      )
    }
  }
}
```

Notes:

- `auth` answers "which sign-in methods exist, how are they configured, and how
  does a provider result become an Instant auth session?"
- `permissions` answers "what is allowed?"
- `persistence` answers "where is the local cache, auth session, query cache,
  outbox, stream cache, and sharing metadata stored?"
- `sharing` answers "what roots can be shared, what roles/scopes exist, and how
  share links map back to permissions?"
- `sync` answers "when does this client connect to Instant and flush or receive
  remote data?"

## Authentication

Instant currently documents Magic Codes, Guest Auth, Google OAuth, Sign In with
Apple, GitHub OAuth, LinkedIn OAuth, Clerk, and Firebase Auth. Instant's general
auth overview currently lists Magic Codes, Guest Auth, Google OAuth, Sign In
with Apple, GitHub OAuth, LinkedIn OAuth, and Clerk as built-in methods, and the
Firebase Auth page documents delegating auth to Firebase by handing Instant a
Firebase ID token. The Swift API should expose all of these as typed provider
cases rather than scattered one-off methods.

Recommended bootstrap shape:

```swift
struct VoiceTrailAuth: InstantAuthConfiguration {
  /// Email magic codes are the softest default: no password storage, works on
  /// every platform, and maps directly to Instant's built-in magic-code flow.
  static let magicCode = AuthProvider.magicCode(
    email: .instant,
    extraFields: VoiceTrailUser.Signup.self
  )

  /// Guest auth should also be spelled "anonymous" at the Swift layer because
  /// native app developers expect both terms.
  ///
  /// The underlying Instant concept is guest auth: the user gets an id without
  /// an email, can create local/remote data, and later upgrades to a full
  /// account without losing that data.
  static let anonymous = AuthProvider.guest(alias: .anonymous)

  /// Apple native sign-in should use the platform credential, nonce, and
  /// identity token, then exchange it for an Instant session through
  /// `signInWithIdToken`.
  static let apple = AuthProvider.apple(
    clientName: "apple-ios",
    presentation: .native,
    requestedScopes: [.fullName, .email]
  )

  /// Google native sign-in should be first-class on Apple platforms too, even
  /// though the JavaScript docs split examples by Web and React Native.
  static let google = AuthProvider.google(
    clientName: "google-ios",
    presentation: .native
  )

  /// GitHub and LinkedIn are useful for a transcription product that may be used
  /// by developers, researchers, recruiters, journalists, and enterprise teams.
  /// They can use redirect or external browser sessions on Apple platforms.
  static let github = AuthProvider.github(
    clientName: "github-web",
    presentation: .authorizationCode(redirectURI: VoiceTrailAuth.githubRedirect)
  )

  static let linkedIn = AuthProvider.linkedIn(
    clientName: "linkedin-web",
    presentation: .authorizationCode(redirectURI: VoiceTrailAuth.linkedInRedirect)
  )

  /// Clerk remains a delegated provider. The app gets a Clerk JWT, then asks
  /// Instant to verify it and create the long-lived Instant session.
  static let clerk = AuthProvider.clerk(
    clientName: "clerk",
    tokenProvider: ClerkTokenProvider.self
  )

  /// Firebase is the same general shape as Clerk: let Firebase do the primary
  /// sign-in, then exchange the Firebase ID token for an Instant session.
  static let firebase = AuthProvider.firebase(
    clientName: "firebase",
    tokenProvider: FirebaseIDTokenProvider.self
  )

  /// Custom lets the app keep an auth system Instant does not know about yet,
  /// while still centralizing the conversion into an Instant session.
  static let customEnterpriseSSO = AuthProvider.idToken(
    clientName: "enterprise-oidc",
    issuer: URL(string: "https://login.company.example")!,
    tokenProvider: EnterpriseIDTokenProvider.self
  )
}
```

Recommended provider model:

```swift
public enum AuthProvider: Sendable {
  /// Passwordless email login. This maps to Instant magic codes.
  case magicCode(email: MagicCodeEmailProvider, extraFields: (any InstantUserExtraFields.Type)?)

  /// Temporary or anonymous access. This maps to Instant guest auth.
  case guest(alias: GuestAlias = .guest)

  /// Native or web Sign In with Apple.
  case apple(
    clientName: String,
    presentation: OAuthPresentation,
    requestedScopes: Set<AppleScope> = [.fullName, .email]
  )

  /// Native or web Google OAuth.
  case google(clientName: String, presentation: OAuthPresentation)

  /// Redirect-style GitHub OAuth.
  case github(clientName: String, presentation: OAuthPresentation)

  /// Redirect-style LinkedIn OAuth.
  case linkedIn(clientName: String, presentation: OAuthPresentation)

  /// Delegated auth through Clerk's session token.
  case clerk(clientName: String, tokenProvider: any IDTokenProvider.Type)

  /// Delegated auth through Firebase's ID token.
  case firebase(clientName: String, tokenProvider: any IDTokenProvider.Type)

  /// Generic ID-token exchange for custom OIDC, enterprise SSO, future providers,
  /// or provider support Instant adds after this API ships.
  case idToken(
    clientName: String,
    issuer: URL?,
    tokenProvider: any IDTokenProvider.Type
  )

  /// Generic authorization-code exchange for providers that hand the app a code
  /// rather than an ID token.
  case authorizationCode(
    clientName: String,
    authorizationURL: AuthorizationURLProvider,
    redirectURI: URL
  )
}
```

Recommended high-level auth service:

```swift
@Dependency(\.defaultInstantSwiftData) var db

/// Auth hangs off `db.auth` so app code has one obvious place for sign-in,
/// linking, session refresh, and sign-out.
try await db.auth.signIn(.anonymous)

try await db.auth.sendMagicCode(
  email: "aisha@example.com"
)

try await db.auth.verifyMagicCode(
  code: code,
  extraFields: VoiceTrailUser.Signup(
    displayName: "Aisha",
    createdAt: .now,
    preferredAuthProvider: .magicCode
  )
)

try await db.auth.signIn(
  .apple(
    clientName: "apple-ios",
    credential: appleCredential,
    nonce: nonce
  )
)

try await db.auth.signIn(
  .google(
    clientName: "google-ios",
    idToken: googleIDToken,
    nonce: nonce
  )
)

try await db.auth.signOut()

/// These methods can return typed events for tests or instrumentation, but the
/// canonical app state remains `db.auth.session`, `db.auth.status`, and
/// `@InstantAuth`.
```

Recommended account-linking shape:

```swift
/// Anonymous/guest users should be able to upgrade without losing data.
///
/// This is not just "sign out and sign back in." It should preserve the local
/// auth session, queued offline writes, ownership links, and share memberships.
try await db.auth.linkCurrentUser(
  with: .apple(
    clientName: "apple-ios",
    credential: appleCredential,
    nonce: nonce
  )
)

/// Users should also be able to add a second login provider to the same Instant
/// user when Instant and the provider support stable email or subject matching.
try await db.auth.linkCurrentUser(
  with: .google(clientName: "google-ios", idToken: googleIDToken)
)
```

Recommended library-owned auth state:

```swift
@InstantAuth(VoiceTrailUser.self)
var auth

/// `db.auth.session` is the source of truth for the current session.
///
/// Views should not hold their own copy of this value. Authentication is too
/// easy to get subtly wrong if every screen has to remember to persist, refresh,
/// clear, and reconcile the same session.
db.auth.session

/// `InstantAuth` is an observable facade over `db.auth`.
///
/// It owns the email text, magic-code challenge, one-time code, in-flight
/// provider work, last error, and session. The projected value exposes SwiftUI
/// bindings so login views can stay almost entirely declarative.
public struct InstantAuth<User: InstantEntityModel>: Sendable {
  public var session: InstantAuthSession?
  public var user: User?
  public var status: InstantAuthStatus<User>
  public var mode: InstantAuthMode
  public var email: String
  public var magicCode: String
  public var error: InstantAuthError?
  public var isBusy: Bool

  public mutating func resetMagicCode()
  public func sendMagicCode(callbacks: AuthChallengeCallbacks = .init()) async
  public func verifyMagicCode(callbacks: AuthSignInCallbacks<User> = .init()) async
  public func signIn(_ provider: AuthProviderSelection, callbacks: AuthSignInCallbacks<User> = .init()) async
  public func signInAsGuest(callbacks: AuthSignInCallbacks<User> = .init()) async
  public func linkCurrentUser(with provider: AuthProviderSelection, callbacks: AuthLinkCallbacks<User> = .init()) async
  public func signOut(callbacks: AuthSignOutCallbacks = .init()) async
}

/// `InstantAuthStatus` drives app shells. A root observer can switch from the
/// login stack to the authenticated app by watching this enum, without the
/// login screen manually navigating on success.
public enum InstantAuthStatus<User: InstantEntityModel>: Sendable {
  case restoring(cached: InstantAuthSession?)
  case signedOut
  case signingIn(AuthProviderID, cached: InstantAuthSession?)
  case guest(InstantAuthSession, user: User?)
  case signedIn(InstantAuthSession, user: User?)
  case failed(InstantAuthError, cached: InstantAuthSession?)
}

/// `InstantAuthMode` drives the provider/email form itself.
///
/// This is deliberately more specific than `status`. A user can be signed out
/// while the magic-code form is in the "code sent" mode, and the view should not
/// need a private `@State var sentChallenge`.
public enum InstantAuthMode: Sendable, Equatable {
  case providerPicker
  case enteringEmail
  case sendingMagicCode(email: String)
  case magicCodeSent(email: String)
  case verifyingMagicCode(email: String)
  case contactingProvider(AuthProviderID)
  case linkingProvider(AuthProviderID)
}
```

Recommended Swift-call-site overloads:

```swift
extension InstantAuth {
  /// The struct-based callback form is useful for passing reusable callback
  /// bundles around.
  func signIn(
    _ provider: AuthProviderSelection,
    callbacks: AuthSignInCallbacks<User> = .init()
  ) async

  /// The trailing-closure form is what app screens should usually reach for.
  ///
  /// It keeps one-off side effects at the call site without asking the screen
  /// to observe a separate phase variable just to run analytics or haptics.
  func signIn(
    _ provider: AuthProviderSelection,
    onSignIn: @escaping @Sendable (AuthSignInEvent<User>) async -> Void = { _ in },
    onProviderCompleted: @escaping @Sendable (ProviderCredential) async -> Void = { _ in },
    onFailure: @escaping @Sendable (InstantAuthError) async -> Void = { _ in }
  ) async

  func sendMagicCode(
    onChallengeSent: @escaping @Sendable (MagicCodeChallenge) async -> Void = { _ in },
    onFailure: @escaping @Sendable (InstantAuthError) async -> Void = { _ in }
  ) async

  func verifyMagicCode(
    onSignIn: @escaping @Sendable (AuthSignInEvent<User>) async -> Void = { _ in },
    onFailure: @escaping @Sendable (InstantAuthError) async -> Void = { _ in }
  ) async

  func linkCurrentUser(
    with provider: AuthProviderSelection,
    onAccountLinked: @escaping @Sendable (AuthLinkEvent<User>) async -> Void = { _ in },
    onProviderCompleted: @escaping @Sendable (ProviderCredential) async -> Void = { _ in },
    onFailure: @escaping @Sendable (InstantAuthError) async -> Void = { _ in }
  ) async

  func signOut(
    onSignOut: @escaping @Sendable (InstantAuthSession.ID) async -> Void = { _ in },
    onFailure: @escaping @Sendable (InstantAuthError) async -> Void = { _ in }
  ) async
}
```

Recommended login screen route:

```swift
/// Route: `auth.login`
///
/// This screen is intentionally dumb. It renders `auth.mode`, binds directly to
/// library-owned fields, and sends user intents back into `auth`.
struct LoginScreen: View {
  @InstantAuth(VoiceTrailUser.self) var auth

  var body: some View {
    VStack(spacing: 16) {
      Text("VoiceTrail")
        .font(.largeTitle.bold())

      Text("Record a walk, capture the words, keep the route.")
        .foregroundStyle(.secondary)

      Button("Continue with Apple") {
        Task {
          await auth.signIn(
            .apple(clientName: "apple-ios"),
            callbacks: .init(
              onProviderCompleted: { credential in
                analytics.track(.providerCredentialReceived(.apple))
              },
              onSignIn: { event in
                analytics.track(.signedIn(event.userID, provider: .apple))
              },
              onFailure: { error in
                haptics.error()
                toast.show(error.recoveryMessage)
              }
            )
          )
        }
      }

      Button("Continue with Google") {
        Task { await auth.signIn(.google(clientName: "google-ios")) }
      }

      Button("Continue with GitHub") {
        Task { await auth.signIn(.github(clientName: "github-web")) }
      }

      Button("Continue with LinkedIn") {
        Task { await auth.signIn(.linkedIn(clientName: "linkedin-web")) }
      }

      Button("Continue with Clerk") {
        Task { await auth.signIn(.clerk(clientName: "clerk")) }
      }

      Button("Continue with Firebase") {
        Task { await auth.signIn(.firebase(clientName: "firebase")) }
      }

      Divider()

      TextField("Email", text: $auth.email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)

      switch auth.mode {
      case .magicCodeSent(let email), .verifyingMagicCode(let email):
        Text("Sent, please check \(email) for the code and enter it here.")

        TextField("Code", text: $auth.magicCode)
          .textContentType(.oneTimeCode)

        Button("Verify code") {
          Task {
            await auth.verifyMagicCode(
              callbacks: .init(
                onSignIn: { event in
                  analytics.track(.signedIn(event.userID, provider: .magicCode))
                },
                onFailure: { error in
                  toast.show(error.recoveryMessage)
                }
              )
            )
          }
        }

      default:
        Button("Send magic code") {
          Task {
            await auth.sendMagicCode(
              callbacks: .init(
                onChallengeSent: { challenge in
                  analytics.track(.magicCodeSent(challenge.email))
                },
                onFailure: { error in
                  toast.show(error.recoveryMessage)
                }
              )
            )
          }
        }
      }

      Button("Try anonymously") {
        Task { await auth.signInAsGuest() }
      }
    }
    .padding()
    .disabled(auth.isBusy)
  }
}
```

Login screen sketch:

```text
┌────────────────────────────────────────────┐
│                VoiceTrail                  │
│ Record a walk, capture the words, keep...  │
│                                            │
│  [ Continue with Apple        ]            │
│  [ Continue with Google       ]            │
│  [ Continue with GitHub       ]            │
│  [ Continue with LinkedIn     ]            │
│  [ Continue with Clerk        ]            │
│  [ Continue with Firebase     ]            │
│                                            │
│  ───────────── or email ─────────────      │
│  Email                                     │
│  [ aisha@example.com                  ]    │
│  [ Send magic code                    ]    │
│                                            │
│  [ Try anonymously                    ]    │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│                VoiceTrail                  │
│                                            │
│  Sent, please check aisha@example.com      │
│  for the code and enter it here.           │
│                                            │
│  Code                                      │
│  [ 123456                             ]    │
│  [ Verify code                       ]     │
│                                            │
│  [ Use a different email             ]     │
└────────────────────────────────────────────┘
```

Auth design decisions:

- `db.auth` is the public namespace.
- `signIn(.anonymous)` and `signInAsGuest()` can both exist. The first reads
  well in app code; the second mirrors Instant's docs.
- Native Apple and Google should be modeled as ID-token sign-in because Apple's
  documented Instant flow takes an identity token plus nonce, and Instant's
  delegated Clerk/Firebase flows also converge on `signInWithIdToken`.
- GitHub and LinkedIn should support authorization-code/redirect flow.
- Clerk and Firebase are delegated providers, not built-in Swift UI. The app
  gets a provider token, then Instant verifies it and creates the Instant
  session.
- Every provider should support optional lifecycle hooks for UI and analytics:

```swift
await auth.signIn(
  .apple(clientName: "apple-ios", credential: credential, nonce: nonce),
  callbacks: .init(
    onProviderCompleted: { credential in
      /// Called when the native/web provider finishes and the app has the
      /// provider credential. This is useful for analytics and diagnostics, not
      /// for storing session state.
    },
    onSignIn: { event in
      /// Called exactly when auth transitions into a signed-in Instant user as
      /// the result of this explicit user action.
      ///
      /// A root app-shell observer still reacts to `db.auth.status`. This hook
      /// is for one-off side effects such as haptics, analytics, or a welcome
      /// toast.
    },
    onFailure: { error in
      /// Called for provider, exchange, permission, persistence, or transport
      /// failures. `auth.error` is also updated by the library, so views do not
      /// have to copy this into their own state.
    }
  )
)
```

Callback rule:

- Auth callbacks must never be the only way to know auth state.
- `db.auth.session`, `db.auth.status`, and `@InstantAuth` are the state.
- `onChallengeSent`, `onProviderCompleted`, `onSignIn`, `onAccountLinked`,
  `onSignOut`, `onFailure`, and `onComplete` are optional side-effect hooks.
- `onSignIn` should not fire for passive session restoration on launch. Passive
  restoration is observed through `db.auth.status`, while `onSignIn` means "the
  user just completed a sign-in action."

## Operation Lifecycle Callbacks

The public API should let app code hook into meaningful lifecycle moments
without making callbacks responsible for state the library can own.

The rule:

- Observable state belongs to `@InstantAuth`, `@FetchAll`, `@FetchOne`,
  `@InstantStream`, `@InstantStorage`, `db.sync`, and `db.auth`.
- Callbacks are for one-off side effects: analytics, haptics, toasts,
  instrumentation, scroll-to-new-item, capture-before-change, and debugging.
- A callback should never be required to keep the app correct.

Recommended initiated-operation vocabulary:

```swift
public struct InstantOperationCallbacks<OptimisticValue: Sendable, ServerValue: Sendable>: Sendable {
  /// Called when the operation starts, before local persistence, optimistic
  /// application, or network work.
  ///
  /// Use this for analytics, haptics, disabling a one-shot button, or capturing
  /// a value for a custom undo affordance. Do not use it to mirror library
  /// state into view state.
  public var onStart: (@Sendable () async -> Void)?

  /// Called after the local store has accepted the optimistic change.
  ///
  /// All subscribed queries have either already updated or are about to update
  /// from the same local transaction. This callback is for side effects that
  /// should happen because the local-first write was accepted.
  public var onOptimisticCommit: (@Sendable (OptimisticValue) async -> Void)?

  /// Called when Instant accepts the outbox item, upload, auth exchange, share
  /// invite, or stream metadata associated with this operation.
  ///
  /// The name is intentionally not `onSynced`. Sync is a continuous connection
  /// concern; this callback is the acknowledgement for one operation.
  public var onServerAccepted: (@Sendable (ServerValue) async -> Void)?

  /// Called for validation, permission, persistence, provider, transport,
  /// server rejection, or cancellation failures.
  ///
  /// The library still updates its own observable error state where appropriate.
  /// This hook exists for side effects.
  public var onFailure: (@Sendable (InstantError) async -> Void)?

  /// Called at the end of the operation whether it succeeded, failed, or was
  /// canceled.
  public var onComplete: (@Sendable (Result<ServerValue, InstantError>) async -> Void)?
}
```

Recommended received-data vocabulary:

```swift
public struct InstantSubscriptionCallbacks<Value: Sendable>: Sendable {
  /// Called when a subscription hydrates from local cache.
  ///
  /// Most views do not need this because the wrapped value already changes. It
  /// is useful for instrumentation and first-load scroll positioning.
  public var onInitialLocalLoad: (@Sendable ([Value]) async -> Void)?

  /// Called when this subscription receives a committed remote change that did
  /// not originate from this device's current client id.
  ///
  /// This is the hook for "someone else edited the title" banners, merge
  /// education, timeline nudges, and collaborative UI.
  public var onRemoteChange: (@Sendable (InstantRemoteChange<Value>) async -> Void)?

  /// Called when multiple remote changes are coalesced into one delivery.
  public var onRemoteBatch: (@Sendable ([InstantRemoteChange<Value>]) async -> Void)?

  /// Called when the live transport reconnects and the subscription has caught
  /// up to the server cursor.
  public var onCaughtUp: (@Sendable (InstantSubscriptionCursor) async -> Void)?
}
```

Specialized APIs can add domain-specific callbacks while preserving the same
intent:

```swift
public struct AuthChallengeCallbacks: Sendable {
  public var onChallengeSent: (@Sendable (MagicCodeChallenge) async -> Void)?
  public var onFailure: (@Sendable (InstantAuthError) async -> Void)?
  public var onComplete: (@Sendable (Result<MagicCodeChallenge, InstantAuthError>) async -> Void)?
}

public struct AuthSignInCallbacks<User: InstantEntityModel>: Sendable {
  public var onProviderCompleted: (@Sendable (ProviderCredential) async -> Void)?
  public var onSignIn: (@Sendable (AuthSignInEvent<User>) async -> Void)?
  public var onFailure: (@Sendable (InstantAuthError) async -> Void)?
  public var onComplete: (@Sendable (Result<AuthSignInEvent<User>, InstantAuthError>) async -> Void)?
}

public struct AuthLinkCallbacks<User: InstantEntityModel>: Sendable {
  public var onProviderCompleted: (@Sendable (ProviderCredential) async -> Void)?
  public var onAccountLinked: (@Sendable (AuthLinkEvent<User>) async -> Void)?
  public var onFailure: (@Sendable (InstantAuthError) async -> Void)?
  public var onComplete: (@Sendable (Result<AuthLinkEvent<User>, InstantAuthError>) async -> Void)?
}

public struct AuthSignOutCallbacks: Sendable {
  public var onSignOut: (@Sendable (InstantAuthSession.ID) async -> Void)?
  public var onFailure: (@Sendable (InstantAuthError) async -> Void)?
  public var onComplete: (@Sendable (Result<InstantAuthSession.ID, InstantAuthError>) async -> Void)?
}

public struct InstantStorageCallbacks<OptimisticFile: Sendable, StoredFile: Sendable>: Sendable {
  public var lifecycle: InstantOperationCallbacks<OptimisticFile, StoredFile> = .init()
  public var onProgress: (@Sendable (FileUploadProgress) async -> Void)?
}

public struct InstantStreamCallbacks<Stream: Sendable, Metadata: Sendable>: Sendable {
  public var lifecycle: InstantOperationCallbacks<Stream, Metadata> = .init()
  public var onChunk: (@Sendable (StreamChunk) async -> Void)?
  public var onByteOffset: (@Sendable (Int64) async -> Void)?
  public var onClosed: (@Sendable (Metadata) async -> Void)?
}
```

Create/update/delete:

```swift
try await db.create(
  Recording.Draft(
    owner: currentUserID,
    audioFile: audio.fileID,
    startedAt: startedAt,
    title: "Morning walk",
    titleSource: .user,
    duration: .zero,
    sourceDeviceID: deviceID
  ),
  callbacks: .init(
    onStart: {
      recorderHUD.phase = .savingLocalRecording
    },
    onOptimisticCommit: { recording in
      /// Navigate immediately because local persistence has succeeded. If the
      /// phone is offline, the recording still exists locally and will sync
      /// later.
      router.go(.recordingPlayback(recording.id))
    },
    onServerAccepted: { recording in
      toast.show("Recording saved")
    },
    onFailure: { error in
      alert = .saveFailed(error)
    }
  )
)

try await db.update(
  Recording.self,
  id: recordingID,
  set: {
    $0.title = "Edited walk title"
  },
  callbacks: .init(
    onOptimisticCommit: { recording in
      titleField.flashSavedLocally()
    },
    onServerAccepted: { recording in
      titleField.flashSynced()
    }
  )
)

try await db.delete(
  Recording.self,
  id: recordingID,
  callbacks: .init(
    onOptimisticCommit: { _ in router.go(.recordingsList) },
    onFailure: { error in alert = .deleteFailed(error) }
  )
)
```

Auth:

```swift
await auth.signIn(
  .apple(clientName: "apple-ios", credential: credential, nonce: nonce),
  callbacks: .init(
    onProviderCompleted: { credential in
      analytics.track(.providerCredentialReceived(.apple))
    },
    onSignIn: { event in
      /// The app shell changes because `db.auth.status` changes. This callback
      /// only records the explicit sign-in event.
      analytics.track(.signedIn(event.userID, provider: .apple))
      haptics.success()
    },
    onFailure: { error in
      toast.show(error.recoveryMessage)
    }
  )
)
```

Storage:

```swift
let upload = try await db.storage.upload(
  screenshotURL,
  path: .recordingAttachment(recordingID, "whiteboard.png"),
  callbacks: .init(
    lifecycle: .init(
      onOptimisticCommit: { pendingFile in
        /// The attachment can render immediately from the local file URL, even
        /// before the upload has a remote URL.
        attachmentPreview = .local(pendingFile.localURL)
      },
      onServerAccepted: { file in
        attachmentPreview = .remote(file.url)
      },
      onFailure: { error in
        attachmentPreview = .failed(error)
      }
    ),
    onProgress: { progress in
      attachmentPreview = .uploading(progress.fractionCompleted)
    }
  )
)
```

Streams:

```swift
let stream = try await db.streams.createWriteStream(
  TranscriptionStream.self,
  clientID: streamClientID,
  callbacks: .init(
    lifecycle: .init(
      onOptimisticCommit: { stream in
        liveTranscript.phase = .streaming(stream.clientID)
      },
      onServerAccepted: { metadata in
        liveTranscript.phase = metadata.done ? .finished : .synced
      },
      onFailure: { error in
        liveTranscript.phase = .failed(error)
      }
    ),
    onChunk: { chunk in
      liveTranscript.append(chunk.text)
    }
  )
)
```

Sharing:

```swift
let share = try await db.shares.create(
  Recording.self,
  id: recordingID,
  role: .listener,
  scopes: [.viewTranscript, .listenAudio],
  callbacks: .init(
    onStart: {
      shareSheet.phase = .creatingLink
    },
    onOptimisticCommit: { share in
      /// The invite can appear in UI as soon as local metadata exists. If the
      /// app is offline, it can show a pending badge instead of blocking.
      shareSheet.pendingInvite = share
    },
    onServerAccepted: { share in
      shareSheet.readyInviteURL = share.url
    },
    onFailure: { error in
      shareSheet.phase = .failed(error)
    }
  )
)
```

Sync:

```swift
try await db.sync.flush(
  callbacks: .init(
    onStart: {
      syncBadge = .flushing
    },
    onOptimisticCommit: { pending in
      /// Local state is already ahead of the server. This callback describes
      /// what the client is about to send, not new user-visible data.
      syncInspector.pendingMutationCount = pending.count
    },
    onServerAccepted: { result in
      syncBadge = .connected
      syncInspector.lastFlush = result
    },
    onFailure: { error in
      syncBadge = .blocked(error)
    }
  )
)
```

Remote changes received from other clients:

```swift
@FetchAll(
  Recording.query
    .where(Recording.owner == currentUserID)
    .order(Recording.startedAt, .descending),
  callbacks: .init(
    onRemoteChange: { change in
      /// `recordings` already changed because `@FetchAll` owns the data.
      ///
      /// This hook is for product behavior that cares that a different device
      /// caused the change: a banner, a collaboration pulse, analytics, or a
      /// conflict explanation.
      guard change.origin != .currentClient else { return }
      toast.show("\(change.authorDisplayName) updated \(change.entity.title)")
    }
  )
)
var recordings: [Recording]
```

## Sync Policy

The name `sync: .automatic` should be a convenience, not the whole design.

Recommended API:

```swift
public enum InstantSyncPolicy: Sendable {
  /// Connect when the app becomes active, authenticate when a session exists,
  /// subscribe to active queries, receive remote changes, and flush the local
  /// outbox whenever connectivity allows.
  case automatic

  /// Keep the local store, observers, and outbox active, but wait for explicit
  /// calls such as `db.sync.connect()` and `db.sync.flush()`.
  case manual

  /// Never open the network transport. Reads come from the local cache and
  /// writes either queue locally or fail according to the `writeBehavior`.
  case offlineOnly(writeBehavior: OfflineWriteBehavior = .queue)

  /// Allow network reads and live subscriptions, but reject local writes before
  /// they enter the outbox.
  case readOnly

  /// Connect and flush only when a user is signed in. Signed-out users can still
  /// read whatever cached public data the app has already stored locally.
  case whenAuthenticated

  /// Ask an app-defined gate whether the client is allowed to connect, subscribe,
  /// and flush. This is the shape I would use for premium-only sync.
  case gated(
    any InstantSyncGate.Type,
    denied: SyncDeniedBehavior = .cacheOnly(allowOptimisticWrites: false)
  )

  /// Escape hatch for advanced apps that want separate policies for connection,
  /// subscriptions, query-once, outbox flush, retries, metered networks, and
  /// background refresh.
  case custom(InstantSyncConfiguration)
}

public enum OfflineWriteBehavior: Sendable {
  /// Apply optimistic writes locally and persist them to the outbox.
  case queue

  /// Reject writes while the client is offline or intentionally disconnected.
  case reject
}

public enum SyncDeniedBehavior: Sendable {
  /// Keep cached reads working. Local writes are accepted or rejected based on
  /// the associated flag.
  case cacheOnly(allowOptimisticWrites: Bool)

  /// Make reads that require fresh network data fail with a typed sync error.
  case rejectNetworkedReads

  /// Disconnect and fail all writes that would produce outbox work.
  case rejectWrites
}
```

Premium-only sync should use a gate:

```swift
struct PremiumSyncGate: InstantSyncGate {
  /// Keep the gate dependency-driven so previews, tests, and local terminal
  /// demos can exercise premium and non-premium behavior without real billing.
  @Dependency(\.entitlements) var entitlements

  /// The gate is a client-side resource policy. It can save bandwidth, battery,
  /// and server work, but it is not security. Server permissions still decide
  /// what data a user may read or write.
  func decision(for context: InstantSyncContext) async -> InstantSyncDecision {
    guard context.authSession?.userID != nil else {
      return .pause(reason: .signedOut)
    }

    return await entitlements.isPremium
      ? .resume
      : .pause(reason: .requiresEntitlement("premium-sync"))
  }
}

extension InstantSyncPolicy {
  /// A convenient app-specific spelling for the product's premium sync rule.
  static var premiumOnly: Self {
    .gated(
      PremiumSyncGate.self,
      denied: .cacheOnly(allowOptimisticWrites: false)
    )
  }
}
```

Then bootstrap becomes:

```swift
$0.defaultInstantSwiftData = try .live(
  appID: Secrets.instantAppID,
  schema: VoiceTrailSchema.self,
  permissions: VoiceTrailPermissions.self,
  persistence: .sqlite(.applicationSupport("VoiceTrail.sqlite")),
  sharing: .enabled(VoiceTrailSharing.self),
  sync: .premiumOnly
)
```

Important decision:

- Sync policy is not where security lives.
- Premium-only data access must also be enforced in `permissions`.
- Sync policy is where product behavior lives: whether to connect, whether to
  flush, whether to keep local-only drafts, and how to surface denied sync.

## Streams

Instant streams are durable, resumable, real-time byte/text flows. They are not
the same thing as ordinary entity rows, and they are not the same thing as room
topics.

What Instant streams are useful for:

- Long-running AI output where the UI wants to render chunks immediately.
- Resumable generation after a page reload, app relaunch, or dropped connection.
- Output that starts before the final shape is known, such as LLM responses,
  background summaries, transcript cleanup, translation, redaction, or chapter
  generation.
- A backend or serverless worker that wants to write progressive output while a
  client reads directly from Instant.
- A durable log-like result where a reader can resume from a byte offset.

What streams are not the right tool for:

- Ordinary durable records that need query filters, graph links, permissions by
  field, or edits. Use entities and transactions.
- Ephemeral "who is typing" or "cursor moved" events. Use rooms/presence/topics.
- Final transcription rows if the app already wrote every segment and word while
  recording. In that case the final operation should mark the existing recording
  or transcription as no longer active, not rewrite the whole transcript.

The Instant docs describe streams as using the standard Web Streams API. A write
stream is buffered on Instant's servers, periodically flushed to Storage, fully
flushed when finished, and because streams are storage-backed they do not expire.
Readers can pick up from a stream id or client id and optionally resume from a
byte offset. Instant also exposes `$streams` metadata such as `id`, `clientId`,
`done`, `size`, and `abortReason`.

Recommended Swift surface:

```swift
@InstantStream
struct TranscriptionCleanupStream: Sendable {
  /// A stable client id lets the app resume the same stream after relaunch. The
  /// server still assigns a persistent stream id once the stream exists.
  static func clientID(transcriptionID: Transcription.ID) -> String {
    "transcription-cleanup-\(transcriptionID.rawValue)"
  }
}

@InstantEntity("$streams")
struct InstantStream: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// Unique, app-provided stream identity. This is how clients resume without
  /// needing to know the server-generated stream id yet.
  @InstantUnique
  var clientID: String

  /// `done` is system-owned metadata. App code can read it but should not
  /// mutate it through normal transactions.
  @InstantSystemField
  var done: Bool?

  @InstantSystemField
  var size: Int?

  @InstantSystemField
  var abortReason: String?
}
```

Creating and reading a stream:

```swift
let stream = try await db.streams.createWriteStream(
  TranscriptionCleanupStream.self,
  clientID: TranscriptionCleanupStream.clientID(transcriptionID: transcriptionID),
  callbacks: .init(
    lifecycle: .init(
      onOptimisticCommit: { stream in
        cleanupUI.phase = .streaming(stream.clientID)
      },
      onServerAccepted: { metadata in
        cleanupUI.phase = metadata.done == true ? .finished : .synced
      }
    ),
    onChunk: { chunk in
      cleanupUI.append(chunk.text)
    },
    onByteOffset: { offset in
      cleanupUI.resumeOffset = offset
    }
  )
)

for try await chunk in cleanupModel.cleanedTranscriptChunks {
  try await stream.write(chunk.text)
}

try await stream.close()
```

Resuming after relaunch:

```swift
let stream = try await db.streams.readStream(
  TranscriptionCleanupStream.self,
  clientID: TranscriptionCleanupStream.clientID(transcriptionID: transcriptionID),
  fromByteOffset: cleanupUI.resumeOffset
)

for try await chunk in stream {
  cleanupUI.append(chunk.text)
}
```

Linking a stream to a domain entity:

```swift
try await db.transact {
  /// Link streams to app entities when the stream is part of the user's durable
  /// workflow. This lets permissions say "you can read this stream if you can
  /// view the recording/transcription it belongs to."
  Transcription.updateExisting(
    id: transcriptionID,
    Transcription.activeCleanupStream.set(stream.id)
  )
}
```

Stream permissions:

```swift
@InstantPermissions
struct VoiceTrailStreamPermissions {
  static let streams = Rules<InstantStream> {
    /// Instant stream permissions live under `$streams`. Non-admin users should
    /// not be able to read or create streams unless the app says exactly why.
    Allow.create {
      SignedIn()
    }

    Allow.view {
      Parent(\.transcription) {
        Parent(\.recording) {
          Owner()
          Member(.viewTranscript)
          PublicLink(.viewTranscript)
        }
      }
    }
  }
}
```

How this applies to live transcription:

- The speech recognizer should write `Transcription`, `TranscriptionSegment`,
  and word JSON as ordinary entities while recording.
- The player observes those entities in realtime.
- When recording stops, update `Recording.endedAt`, `Recording.duration`,
  `Transcription.status`, and any active processor state.
- Use streams only for optional progressive processors whose output is not
  already represented as normal rows: cleanup, summary, translation, redaction,
  title generation, chapters, or "AI notes."

## Sharing Configuration

Sharing should be configured in three layers:

```swift
$0.defaultInstantSwiftData = try .live(
  appID: Secrets.instantAppID,
  schema: VoiceTrailSchema.self,
  permissions: VoiceTrailPermissions.self,
  persistence: .sqlite(.applicationSupport("VoiceTrail.sqlite")),
  sharing: .enabled(VoiceTrailSharing.self),
  sync: .automatic
)
```

Layer 1: schema marks share roots and share membership entities.

```swift
@InstantEntity
@InstantShareRoot
struct Recording: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "ownedRecordings")
  var owner: InstantID<InstantUser>

  var title: String
}
```

Layer 2: permissions enforce server-side access.

```swift
@InstantPermissions
struct VoiceTrailPermissions {
  static let recordings = Rules<Recording> {
    /// Owners can always see their recordings. Shared users can see a recording
    /// when an accepted membership grants the requested capability.
    Allow.view {
      Owner()
      Member(.viewTranscript)
      PublicLink(.viewTranscript)
    }

    /// The result builder compiles to Instant permissions. Swift gives us a
    /// nicer authoring surface, but the emitted `instant.perms.ts` still uses
    /// Instant's CEL/data.ref/auth.ref rules.
    Allow.update {
      Owner()
      Member(.edit)
    }
  }
}
```

Layer 3: `sharing` provides app-level roles, scopes, invite links, and visible
share metadata.

```swift
struct VoiceTrailSharing: InstantSharingConfiguration {
  /// Recordings are the root object users understand. Child transcriptions,
  /// segments, attachments, route samples, and audio files inherit from this
  /// root unless a narrower rule says otherwise.
  static let recording = ShareRoot(Recording.self) {
    Role.owner
      .allows(.viewTranscript, .listenAudio, .downloadAudio, .comment, .edit, .share)

    Role.editor
      .allows(.viewTranscript, .listenAudio, .comment, .edit)

    Role.listener
      .allows(.viewTranscript, .listenAudio)

    Role.reader
      .allows(.viewTranscript)
  }
}
```

App code then stays small:

```swift
let share = try await db.shares.create(
  Recording.self,
  id: recordingID,
  role: .listener,
  scopes: [.viewTranscript, .listenAudio],
  expiresAt: .now.addingTimeInterval(7 * 24 * 60 * 60)
)

try await db.shares.accept(share.inviteToken)

@Shares(Recording.self, id: recordingID)
var recordingShares: [Share<Recording>]
```

## Client Naming

The current code has `InstantSwiftDataClient`. I do not think app code needs
both `InstantSwiftDataClient` and `InstantDatabase` as separate concepts.

Recommended naming:

```swift
@Dependency(\.defaultInstantSwiftData) var db
```

Where the dependency value is backed by one public client type:

```swift
public struct InstantSwiftDataClient: Sendable {
  public static func live(...) throws -> Self
  public static func preview(...) -> Self
  public static func test(...) -> Self
  public static func offline(...) throws -> Self
}
```

Optional polish:

```swift
public typealias InstantDatabase = InstantSwiftDataClient
```

Why:

- `InstantSwiftDataClient` matches the package and current code.
- The local variable can still be `db`, which is what developers want to write.
- A typealias gives docs a friendlier term without splitting the mental model.

## Schema Annotation Kitchen Sink

This section describes the target source-level annotations. Some exist already
in the package, and some are proposed.

```swift
/// Declares a Swift type as an Instant namespace.
///
/// The macro infers the namespace by pluralizing the type name, generates typed
/// attribute paths, generates reverse relation tokens, generates a writable
/// `Draft`, and emits schema metadata for TypeScript generation.
@InstantEntity
struct ExampleEntity: Codable, Sendable, Identifiable {
  let id: InstantID<Self>
}

/// Overrides the inferred namespace when an app has an existing schema or needs
/// a special Instant namespace such as `$users` or `$files`.
@InstantEntity("legacy_transcripts")
struct LegacyTranscript: Codable, Sendable, Identifiable {
  let id: InstantID<Self>
}

/// Marks a field as indexed so Instant can filter or order by it.
///
/// The macro should warn when a query filters or orders by a field that is not
/// indexed, because Instant requires filter/order fields to be schema-supported.
@InstantIndexed
var createdAt: Date

/// Marks a field as unique and therefore usable as a lookup ref.
///
/// Uniqueness should imply indexing. The generated attribute path gets a
/// `.lookup(...)` helper that can be used in updates, links, and deletes.
@InstantUnique
var externalJobID: String

/// Gives a field a custom Instant attribute name while keeping the Swift member
/// idiomatic.
///
/// This should be rare in new apps, but it matters for migrations and existing
/// TypeScript schemas.
@InstantField("speaker_label")
var speakerLabel: String

/// Declares a typed graph edge.
///
/// The forward field stores an `InstantID<Target>`. The reverse name generates a
/// type-safe include token so callers write `Recording.transcriptions`, not
/// `"transcriptions"`.
@InstantRelation(reverse: "transcriptions", cardinality: .one, onDelete: .cascade)
var recording: InstantID<Recording>

/// Declares a many-valued graph edge.
///
/// Instant supports one/many cardinality. The Swift model should support
/// `[InstantID<Target>]` for many edges once the decoder/query layer can make
/// that shape pleasant.
@InstantRelation(reverse: "labels", cardinality: .many)
var tags: [InstantID<Tag>]

/// Forces the Instant wire type for wrapper types, enums, and semantic values.
///
/// Most scalar fields should infer their wire type from Swift, but explicit wire
/// annotations are useful for wrappers such as `Milliseconds`, `LanguageCode`,
/// or enums that encode as strings.
@InstantWire(.number)
var duration: Seconds

/// Stores a Codable value as an Instant `json` attribute.
///
/// This is useful for data that is naturally embedded, usually read as a whole,
/// and not individually filtered by Instant. Word-level timestamps are a good
/// fit. Searchable segment text is not, so it stays a scalar string too.
@InstantJSON
var words: [TranscriptWord]

/// Supplies a client-side default for generated drafts.
///
/// This should not pretend Instant has server defaults. It only makes
/// `Entity.Draft()` ergonomic.
@InstantDefault(.now)
var capturedAt: Date

/// Excludes a stored Swift property from the Instant schema.
///
/// This is mostly for derived UI state, memoized formatting, and migration
/// shims. It should not be used for important domain data.
@InstantIgnored
var formattedDuration: String = ""

/// Documents a sensitive field and lets the permission generator require a
/// field-level rule before schema emission succeeds.
///
/// This is a design guardrail for fields such as emails, raw transcript text,
/// audio file links, and billing state.
@InstantSensitive
var email: String
```

Recommended rules:

- Requiredness should be inferred from Swift optionality:
  - `String` is required.
  - `String?` is optional.
- `@InstantRequired` should not exist unless Swift optionality proves
  insufficient.
- `@InstantIndexed` and `@InstantUnique` should be schema annotations, not
  runtime hints.
- `@InstantSensitive` should not enforce access by itself. It should force the
  app to declare permissions.
- `@InstantJSON` values should be easy to decode but not pretend nested JSON
  fields are indexable Instant attributes.

## Inspection Domain, Kept From V1 And Expanded

This smaller domain stays in the document because it is easy to scan while we
judge the syntax.

```swift
@InstantEntity
struct Inspection: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// Indexed because the schedule screen filters by time ranges and orders by
  /// the next due inspection. Without this annotation the query builder should
  /// warn before a bad Instant query reaches the server.
  @InstantIndexed
  var scheduledAt: Date

  /// Indexed because the operations board groups and filters by status all day.
  /// The enum encodes as a string, so typos such as `"needs_part"` never enter
  /// app code.
  @InstantIndexed
  var status: Status

  /// Searchable with `$ilike` for simple operator workflows.
  ///
  /// For large full-text search we would add a search service, but this keeps
  /// the common "find the warehouse inspection" case local to Instant.
  @InstantIndexed
  var siteName: String

  var notes: String?

  /// A typed forward relation to the technician.
  ///
  /// The reverse token generated from this field lets the technician detail
  /// screen include `Technician.inspections` without writing a string path.
  @InstantRelation(reverse: "inspections", cardinality: .one)
  var assignedTechnician: InstantID<Technician>

  enum Status: String, Codable, Sendable, InstantStringEnum {
    case scheduled
    case inProgress
    case needsParts
    case complete
  }
}

@InstantEntity
struct Technician: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// Unique fields generate lookup refs. This supports writes like
  /// `Technician.email.lookup("mira@example.com")` and lets link operations
  /// avoid a separate read when the app already knows a unique value.
  @InstantUnique
  var email: String

  @InstantIndexed
  var region: String

  var displayName: String
}
```

Query documentation:

```swift
@FetchAll(
  /// `@FetchAll` subscribes to the query and keeps the Swift value current.
  ///
  /// Cached local results can appear immediately on launch, optimistic writes
  /// update this value before the server round trip, and remote changes from
  /// other clients flow through the same subscription.
  Inspection.query
    /// Type-safe enum equality. There is no stringly typed status value here.
    .where(Inspection.status == .needsParts)

    /// Comparison only compiles for Instant comparable values.
    .where(Inspection.scheduledAt <= Date())

    /// `$ilike` is represented as a Swift method on string attribute paths.
    .where(Inspection.siteName.iLike("%warehouse%"))

    /// Includes use generated relation tokens. This is a graph include, not a
    /// SQL join, and the nested query can select only the fields the UI needs.
    .include(
      Inspection.assignedTechnician,
      Technician.query.select(Technician.displayName, Technician.region)
    )

    /// Ordering by a declared indexed Date field should be validated before the
    /// query is sent to Instant.
    .order(Inspection.scheduledAt, .ascending)

    /// Pagination belongs at the top level in Instant. Nested pagination should
    /// be rejected by the builder or by validation.
    .first(50)
)
var overdueInspections: [Inspection]
```

## Voice Transcription Domain

The transcription app is the richer domain that should guide v2. It exercises
storage, streams, sharing, permissions, nested queries, JSON fields, duplicated
convenience data, geolocation, public URLs, and multiple processors per
recording.

### Core Entities

```swift
@InstantEntity
@InstantShareRoot
struct Recording: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// The owner is the root permission anchor.
  ///
  /// All child objects should be reachable from this recording so permissions
  /// can answer questions such as "may this user listen to the audio?" without
  /// every child needing its own separate ACL model.
  @InstantRelation(reverse: "recordings", cardinality: .one)
  var owner: InstantID<InstantUser>

  /// The original audio lives in Instant Storage, not as a URL string.
  ///
  /// File permissions can be generated from the typed storage path and the
  /// recording's share policy. The app links the file entity here so queries can
  /// display upload status, byte size, content type, and signed URLs.
  @InstantRelation(reverse: "sourceRecordings", cardinality: .one)
  var audioFile: InstantID<InstantFile>

  /// Indexed for the recents list and for time-window search.
  @InstantIndexed
  var startedAt: Date

  @InstantIndexed
  var endedAt: Date?

  /// Recording state is explicit so the UI can answer "am I still actively
  /// recording?" without inferring too much from timestamps.
  @InstantIndexed
  var state: State

  /// A human title can be edited after recording. If the title was inferred from
  /// transcript content, `titleSource` says so.
  @InstantIndexed
  var title: String

  var titleSource: TitleSource

  /// Denormalized duration for lists. Segment and word timings still keep their
  /// own precise offsets.
  @InstantIndexed
  var duration: Seconds

  /// Convenient preview data for map thumbnails.
  ///
  /// The full route is stored as `RecordingLocationSample` rows so the app can
  /// stream and paginate long walks without rewriting one huge JSON blob.
  @InstantJSON
  var routeSummary: RouteSummary?

  /// The app may record a local device identity for debugging sync problems and
  /// grouping offline recordings. It is indexed because support tooling filters
  /// by device.
  @InstantIndexed
  var sourceDeviceID: String

  /// Public URLs are represented by share link entities, not by making the
  /// recording itself globally public. This boolean only helps the library keep
  /// list UIs cheap.
  @InstantIndexed
  var hasPublicLinks: Bool

  enum TitleSource: String, Codable, Sendable, InstantStringEnum {
    case user
    case firstSegment
    case generatedSummary
  }

  enum State: String, Codable, Sendable, InstantStringEnum {
    case recording
    case processing
    case ready
    case failed
  }
}

extension Recording {
  /// Computed properties are ordinary Swift, not persisted Instant attributes.
  ///
  /// This keeps convenience close to the model without duplicating state in the
  /// database. If the app needs to filter by this value in Instant, use the
  /// indexed `state` field instead.
  @InstantIgnored
  var isActivelyRecording: Bool {
    state == .recording
  }
}

@InstantEntity
struct Transcription: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// A recording can have many transcriptions: local model, cloud model,
  /// re-run with diarization, re-run in another language, and so on.
  @InstantRelation(reverse: "transcriptions", cardinality: .one, onDelete: .cascade)
  var recording: InstantID<Recording>

  /// Each transcription records the processor that produced it.
  ///
  /// This makes output auditable. When the same recording has two transcripts,
  /// users can see whether Whisper, Deepgram, Apple Speech, or a custom model
  /// produced each one.
  @InstantRelation(reverse: "transcriptions", cardinality: .one)
  var processor: InstantID<TranscriptionProcessor>

  @InstantIndexed
  var createdAt: Date

  @InstantIndexed
  var status: Status

  @InstantIndexed
  var languageCode: LanguageCode

  /// The entire transcript is duplicated here for quick copy, search, export,
  /// and preview. Segment rows remain the source for timeline rendering.
  @InstantIndexed
  var text: String

  /// The full word array is duplicated here for convenient export.
  ///
  /// Segment rows also store their own word arrays so the player can render
  /// active captions without loading the whole transcript.
  @InstantJSON
  var words: [TranscriptWord]

  /// Aggregate confidence helps sort candidate transcriptions and flag rough
  /// output. Word and segment confidence remain available for fine-grained UI.
  @InstantIndexed
  var confidence: Double

  /// Exactly one transcript can be primary for a recording in normal UI. The
  /// library should support a uniqueness constraint over `(recording, isPrimary)`
  /// eventually, but a simple indexed boolean is still useful.
  @InstantIndexed
  var isPrimary: Bool

  enum Status: String, Codable, Sendable, InstantStringEnum {
    case queued
    case processing
    case ready
    case failed
  }
}

@InstantEntity
struct TranscriptionProcessor: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  /// Unique so jobs can reference a stable processor configuration by lookup.
  @InstantUnique
  var slug: String

  @InstantIndexed
  var provider: Provider

  @InstantIndexed
  var model: String

  var modelVersion: String?
  var appBuild: String?
  var supportsWordTimestamps: Bool
  var supportsDiarization: Bool
  var supportsConfidence: Bool

  /// Provider-specific configuration is typed, but still encodes as JSON.
  ///
  /// This keeps Swift strict while allowing each engine to carry the knobs it
  /// actually supports. The generated TypeScript schema sees one JSON field,
  /// while Swift gets exhaustive cases and provider-specific associated values.
  @InstantJSON
  var configuration: Configuration

  enum Provider: String, Codable, Sendable, InstantStringEnum {
    case appleSpeech
    case whisperLocal
    case whisperRemote
    case deepgram
    case assemblyAI
    case custom
  }

  enum Configuration: Codable, Sendable, InstantJSONCodable {
    case appleSpeech(locale: LanguageCode, requiresOnDeviceRecognition: Bool)
    case whisperLocal(modelURLBookmark: String, computeUnits: ComputeUnits)
    case whisperRemote(endpoint: URL, model: String, temperature: Double?)
    case deepgram(model: String, smartFormat: Bool, diarize: Bool)
    case assemblyAI(speakerLabels: Bool, autoChapters: Bool)
    case custom(JSONValue)
  }
}
```

### Timeline Entities

```swift
@InstantEntity
struct TranscriptionSegment: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "segments", cardinality: .one, onDelete: .cascade)
  var transcription: InstantID<Transcription>

  /// Segment ordering is time-based, so both endpoints are indexed.
  @InstantIndexed
  var startTime: Seconds

  @InstantIndexed
  var endTime: Seconds

  /// Duplicated plain text keeps segment lists, search, and export simple.
  @InstantIndexed
  var text: String

  /// Duplicated word-level timing keeps the player simple.
  ///
  /// This is JSON because the app almost always reads a segment's words as a
  /// single value. If we later need cross-recording word analytics, words can
  /// become their own namespace.
  @InstantJSON
  var words: [TranscriptWord]

  /// Speaker labels are indexed because review screens often filter by speaker.
  @InstantIndexed
  var speakerLabel: String?

  @InstantRelation(reverse: "segments", cardinality: .one)
  var speaker: InstantID<TranscriptSpeaker>?

  @InstantIndexed
  var confidence: Double
}

@InstantEntity
struct TranscriptSpeaker: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "speakers", cardinality: .one, onDelete: .cascade)
  var transcription: InstantID<Transcription>

  /// Stable within a transcription, for example `speaker-1`.
  @InstantIndexed
  var label: String

  /// User-editable display name, for example `Aisha`.
  @InstantIndexed
  var displayName: String?

  /// Optional voiceprint metadata should stay private and permission-gated.
  @InstantSensitive
  @InstantJSON
  var voiceprint: VoiceprintSummary?
}

struct TranscriptWord: Codable, Sendable, InstantJSONCodable {
  /// The normalized word shown in captions and export.
  var text: String

  /// The raw token from the engine, when preserving punctuation or casing helps
  /// with debugging.
  var rawText: String?

  /// Offsets are relative to the recording start. Relative time survives edits
  /// and avoids mixing local clock time with media time.
  var startTime: Seconds
  var endTime: Seconds

  /// Confidence belongs on every word so the UI can underline uncertain spans.
  var confidence: Double?

  /// Alternative estimates let a correction UI show "did you mean..." without
  /// reprocessing the recording.
  var estimates: [WordEstimate]

  /// Repeats the segment speaker label for export convenience.
  var speakerLabel: String?
}

struct WordEstimate: Codable, Sendable {
  var text: String
  var confidence: Double
}
```

### Inline Attachments

```swift
@InstantEntity
struct RecordingAttachment: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "attachments", cardinality: .one, onDelete: .cascade)
  var recording: InstantID<Recording>

  /// Optional because attachments are captured during recording before a
  /// transcription segment exists. Once transcription finishes, the app may link
  /// the attachment to the segment that covers the capture time.
  @InstantRelation(reverse: "attachments", cardinality: .one)
  var segment: InstantID<TranscriptionSegment>?

  @InstantIndexed
  var kind: Kind

  /// Timeline position where the user copied text, added a link, or captured a
  /// screenshot. This is what lets the UI display attachments inline.
  @InstantIndexed
  var capturedAtOffset: Seconds

  @InstantIndexed
  var capturedAt: Date

  /// Screenshots and copied binary blobs use Storage.
  @InstantRelation(reverse: "attachments", cardinality: .one)
  var file: InstantID<InstantFile>?

  /// Links stay as strings because they are user-authored content, not storage
  /// file URLs. Storage URLs should come from `$files`.
  var url: String?

  /// Copied text is duplicated inline because users expect it to render even if
  /// the original source disappears.
  @InstantSensitive
  var copiedText: String?

  var title: String?
  var note: String?

  enum Kind: String, Codable, Sendable, InstantStringEnum {
    case screenshot
    case link
    case copiedText
    case file
    case bookmark
  }
}
```

### Route And Geolocation

```swift
@InstantEntity
struct RecordingLocationSample: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "locationSamples", cardinality: .one, onDelete: .cascade)
  var recording: InstantID<Recording>

  /// Absolute clock time helps reconcile samples produced by different devices.
  @InstantIndexed
  var capturedAt: Date

  /// Media-relative time is what the transcript UI uses to sync the route with
  /// the words.
  @InstantIndexed
  var offset: Seconds

  var latitude: Double
  var longitude: Double
  var altitude: Double?
  var horizontalAccuracy: Double?
  var verticalAccuracy: Double?
  var speed: Double?
  var course: Double?

  /// Samples can come from CoreLocation, a GPX import, or another device.
  @InstantIndexed
  var source: Source

  enum Source: String, Codable, Sendable, InstantStringEnum {
    case coreLocation
    case importedRoute
    case companionDevice
  }
}

struct RouteSummary: Codable, Sendable, InstantJSONCodable {
  var sampleCount: Int
  var distanceMeters: Double?
  var bounds: GeoBounds?
  var previewPolyline: String?
}

struct GeoBounds: Codable, Sendable {
  var minLatitude: Double
  var minLongitude: Double
  var maxLatitude: Double
  var maxLongitude: Double
}
```

### Access, Listening, And Public URLs

```swift
@InstantEntity
struct RecordingMember: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "members", cardinality: .one, onDelete: .cascade)
  var recording: InstantID<Recording>

  @InstantRelation(reverse: "recordingMemberships", cardinality: .one)
  var user: InstantID<InstantUser>

  /// Roles are product concepts. Permissions expand these into CEL rules.
  @InstantIndexed
  var role: Role

  /// Per-member overrides are rare, but useful for temporary restrictions.
  ///
  /// The common path is still role-derived. The app should not persist a pile of
  /// duplicated `canViewTranscript` booleans that can drift from the role.
  @InstantJSON
  var overrides: PermissionOverrides?

  var acceptedAt: Date?
  var expiresAt: Date?

  enum Role: String, Codable, Sendable, InstantStringEnum {
    case owner
    case editor
    case listener
    case reader
  }
}

extension RecordingMember.Role {
  /// Roles derive capabilities in Swift, in generated TypeScript permissions,
  /// and in local optimistic permission checks.
  ///
  /// This keeps the persisted data small and prevents impossible states such as
  /// `role == .reader` with `canDownloadAudio == true`.
  var capabilities: Set<RecordingCapability> {
    switch self {
    case .owner:
      return [.viewTranscript, .listenAudio, .downloadAudio, .comment, .edit, .share]
    case .editor:
      return [.viewTranscript, .listenAudio, .comment, .edit]
    case .listener:
      return [.viewTranscript, .listenAudio]
    case .reader:
      return [.viewTranscript]
    }
  }
}

extension RecordingMember {
  /// Computed properties are not Instant attributes.
  ///
  /// They are pure Swift conveniences over persisted fields and generated role
  /// policy. If a computed value needs to participate in an Instant query, it
  /// should become a real indexed field instead.
  @InstantIgnored
  var permissions: RecordingPermissions {
    RecordingPermissions(role: role, overrides: overrides)
  }
}

struct RecordingPermissions: Sendable {
  var role: RecordingMember.Role
  var overrides: PermissionOverrides?

  func allows(_ capability: RecordingCapability) -> Bool {
    let base = role.capabilities.contains(capability)
    return overrides?.decision(for: capability, default: base) ?? base
  }
}

enum RecordingCapability: String, Codable, Sendable, CaseIterable, InstantStringEnum {
  case viewTranscript
  case listenAudio
  case downloadAudio
  case viewAttachments
  case viewRoute
  case comment
  case edit
  case share
}

struct PermissionOverrides: Codable, Sendable, InstantJSONCodable {
  var grants: Set<RecordingCapability> = []
  var revocations: Set<RecordingCapability> = []

  func decision(for capability: RecordingCapability, default defaultValue: Bool) -> Bool {
    if grants.contains(capability) { return true }
    if revocations.contains(capability) { return false }
    return defaultValue
  }
}

@InstantEntity
struct PublicRecordingLink: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantRelation(reverse: "publicLinks", cardinality: .one, onDelete: .cascade)
  var recording: InstantID<Recording>

  /// Unique slug used in public URLs. The app can build URLs from a route such
  /// as `/r/<slug>` without storing full absolute URLs in the database.
  @InstantUnique
  var slug: String

  @InstantIndexed
  var createdAt: Date

  var expiresAt: Date?

  /// Public links can expose transcript-only views without exposing audio.
  var allowTranscript: Bool
  var allowAudioPlayback: Bool
  var allowAudioDownload: Bool
  var allowAttachments: Bool
  var allowRoute: Bool

  /// A passcode hash belongs in a sensitive field and should have a field-level
  /// permission rule. Plain passcodes should never be stored.
  @InstantSensitive
  var passcodeHash: String?
}
```

### Permissions Sketch

```swift
@InstantPermissions
struct VoiceTrailPermissions {
  static let recordings = Rules<Recording> {
    /// Owners, members with transcript access, and public transcript links can
    /// view the recording shell.
    Allow.view {
      Owner()
      Member(.viewTranscript)
      PublicLink(.viewTranscript)
    }

    /// Only owners and editors can mutate recording metadata.
    Allow.update {
      Owner()
      Member(.edit)
    }
  }

  static let transcriptions = Rules<Transcription> {
    /// Transcripts inherit view access from the parent recording.
    Allow.view {
      Parent(\.recording) {
        Owner()
        Member(.viewTranscript)
        PublicLink(.viewTranscript)
      }
    }
  }

  static let files = FileRules {
    /// File permissions are path-aware because Instant `$files` permissions do
    /// not use `data.ref`. The typed storage path builder should make this
    /// safer than raw string prefixes.
    Allow.view {
      FilePath(RecordingAudioPath.self) {
        Parent(\.recording) {
          Owner()
          Member(.listenAudio)
          PublicLink(.listenAudio)
        }
      }
    }
  }
}
```

Security note:

- The permissions DSL above is aspirational Swift syntax for generating
  `instant.perms.ts`.
- The builder is stricter than TypeScript authoring. Capabilities must come from
  `RecordingCapability`, reverse paths must be generated relation tokens, and
  file paths must be typed path builders.
- Client-side `sync: .premiumOnly` is not enough for premium-only data. The
  permission rules must also check entitlement or membership on the server.

## Transcription Query Examples

Recording list:

```swift
@FetchAll(
  /// A recording list should load from cache immediately, then reconcile with
  /// realtime updates when sync is allowed.
  Recording.query
    .where(Recording.owner == currentUserID)
    .include(
      Recording.transcriptions,
      Transcription.query
        .where(Transcription.isPrimary == true)
        .select(
          Transcription.status,
          Transcription.text,
          Transcription.confidence
        )
    )
    .include(Recording.audioFile)
    .order(Recording.startedAt, .descending)
    .first(100)
)
var recordings: [Recording]
```

Timeline playback:

```swift
@FetchAll(
  /// Segments are queried by media time so playback can keep captions and
  /// speaker labels in sync with the audio.
  TranscriptionSegment.query
    .where(TranscriptionSegment.transcription == selectedTranscriptionID)
    .where(TranscriptionSegment.endTime >= playbackWindow.start)
    .where(TranscriptionSegment.startTime <= playbackWindow.end)
    .include(TranscriptionSegment.speaker)
    .order(TranscriptionSegment.startTime, .ascending)
)
var visibleSegments: [TranscriptionSegment]
```

Inline attachments:

```swift
@FetchAll(
  /// Attachments are sorted by the offset at which they were captured so the UI
  /// can interleave screenshots, copied text, links, and files with transcript
  /// segments.
  RecordingAttachment.query
    .where(RecordingAttachment.recording == recordingID)
    .where(RecordingAttachment.capturedAtOffset >= playbackWindow.start)
    .where(RecordingAttachment.capturedAtOffset <= playbackWindow.end)
    .include(RecordingAttachment.file)
    .order(RecordingAttachment.capturedAtOffset, .ascending)
)
var inlineAttachments: [RecordingAttachment]
```

Route samples:

```swift
@FetchAll(
  /// Route samples are separate entities, not one giant JSON field, because a
  /// long walk can produce thousands of points and the map should page or stream
  /// them without rewriting the recording row.
  RecordingLocationSample.query
    .where(RecordingLocationSample.recording == recordingID)
    .where(RecordingLocationSample.offset >= visibleTimeRange.start)
    .where(RecordingLocationSample.offset <= visibleTimeRange.end)
    .order(RecordingLocationSample.offset, .ascending)
    .limit(500)
)
var routeSamples: [RecordingLocationSample]
```

Search:

```swift
@FetchAll(
  /// Search uses duplicated scalar text on transcription and segment rows.
  ///
  /// Word arrays stay JSON because they are for rendering and export. If we
  /// need word-level search, words should graduate to their own namespace.
  TranscriptionSegment.query
    .where(TranscriptionSegment.text.iLike("%pricing%"))
    .where(TranscriptionSegment.speakerLabel != "background")
    .include(
      TranscriptionSegment.transcription,
      Transcription.query.include(Transcription.recording)
    )
    .order(TranscriptionSegment.startTime, .ascending)
)
var searchHits: [TranscriptionSegment]
```

Shared with me:

```swift
@FetchAll(
  /// This screen shows recordings the current user can listen to, even when
  /// they are not the owner.
  ///
  /// The persisted membership row stores a role. The capability check is
  /// generated from `RecordingCapability` and the role policy, not from
  /// duplicated booleans on the membership row.
  Recording.query
    .where(Recording.members.user == currentUserID)
    .where(Recording.members.role.allows(.listenAudio))
    .include(
      Recording.members,
      RecordingMember.query.where(RecordingMember.user == currentUserID)
    )
    .include(
      Recording.transcriptions,
      Transcription.query
        .where(Transcription.isPrimary == true)
        .select(Transcription.status, Transcription.text)
    )
    .order(Recording.startedAt, .descending)
)
var listenableRecordingsSharedWithMe: [Recording]
```

## Transcription Mutation Examples

Create an offline recording shell:

```swift
let recordingID = InstantID<Recording>()
let audioPath = RecordingAudioPath(recordingID: recordingID, filename: "walk.m4a")

/// Upload can happen before or after the recording row is created. If offline,
/// the local file reference and pending upload live beside the outbox until
/// sync is allowed.
let audio = try await db.storage.prepareUpload(localAudioURL, path: audioPath)

try await db.transact {
  /// `create` should be strict. Accidentally creating the same recording twice
  /// should fail before the outbox stores a duplicate transaction.
  Recording.create(
    id: recordingID,
    Recording.owner.set(currentUserID),
    Recording.audioFile.set(audio.fileID),
    Recording.startedAt.set(startedAt),
    Recording.endedAt.set(nil),
    Recording.state.set(.recording),
    Recording.title.set("Morning walk"),
    Recording.titleSource.set(.user),
    Recording.duration.set(.zero),
    Recording.routeSummary.set(nil),
    Recording.sourceDeviceID.set(deviceID),
    Recording.hasPublicLinks.set(false)
  )

  /// Membership is created in the same transaction so local permission checks
  /// and UI share state are coherent even while offline.
  RecordingMember.create(
    id: .init(),
    RecordingMember.recording.set(recordingID),
    RecordingMember.user.set(currentUserID),
    RecordingMember.role.set(.owner),
    RecordingMember.overrides.set(nil),
    RecordingMember.acceptedAt.set(.now),
    RecordingMember.expiresAt.set(nil)
  )
}
```

Write transcription data while recording:

```swift
let transcriptionID = try await db.create(
  Transcription.Draft(
    recording: recordingID,
    processor: processorID,
    createdAt: .now,
    status: .processing,
    languageCode: "en-US",
    text: "",
    words: [],
    confidence: 0,
    isPrimary: true
  )
)

for try await partial in speechRecognizer.segments {
  /// Stable partials are ordinary entity writes, not stream chunks.
  ///
  /// The player, transcript screen, route overlay, and remote collaborators all
  /// observe the same durable rows as they are created or merged. When the
  /// recording finishes, there is no need to "persist the final transcript"
  /// again because the transcript already exists locally and remotely.
  try await db.mutate(
    callbacks: .init(
      onOptimisticCommit: { _ in liveCaptions.show(partial.text) },
      onFailure: { error in recorderHUD.warning = .segmentSaveFailed(error) }
    )
  ) {
    TranscriptionSegment.upsert(
      id: partial.segmentID,
      TranscriptionSegment.transcription.set(transcriptionID),
      TranscriptionSegment.startTime.set(partial.startTime),
      TranscriptionSegment.endTime.set(partial.endTime),
      TranscriptionSegment.text.set(partial.text),
      TranscriptionSegment.words.set(partial.words),
      TranscriptionSegment.speakerLabel.set(partial.speakerLabel),
      TranscriptionSegment.speaker.set(partial.speakerID),
      TranscriptionSegment.confidence.set(partial.confidence)
    )

    Transcription.merge(
      id: transcriptionID,
      Transcription.text.set(partial.fullTranscriptSoFar),
      Transcription.words.set(partial.allWordsSoFar),
      Transcription.confidence.set(partial.runningConfidence)
    )
  }
}
```

Finish recording:

```swift
try await db.mutate(
  callbacks: .init(
    onOptimisticCommit: { _ in recorderHUD.phase = .savedLocally },
    onServerAccepted: { _ in recorderHUD.phase = .savedRemotely },
    onFailure: { error in recorderHUD.phase = .failed(error) }
  )
) {
  /// Finalization is a status transition over rows that already exist.
  ///
  /// We do not loop over every segment again. Rewriting the whole transcript at
  /// stop time would create unnecessary conflict surface and waste the exact
  /// local-first behavior Instant gives us.
  Recording.updateExisting(
    id: recordingID,
    Recording.endedAt.set(.now),
    Recording.state.set(.ready),
    Recording.duration.set(finalDuration),
    Recording.routeSummary.set(finalRouteSummary)
  )

  Transcription.updateExisting(
    id: transcriptionID,
    Transcription.status.set(.ready),
    Transcription.confidence.set(finalConfidence)
  )
}
```

Use streams for optional progressive processors:

```swift
let cleanupStream = try await db.streams.createWriteStream(
  TranscriptionCleanupStream.self,
  clientID: TranscriptionCleanupStream.clientID(transcriptionID: transcriptionID)
)

for try await chunk in cleanupModel.cleanedTranscriptChunks(transcriptionID) {
  /// This is the kind of work streams are good at: progressive derived output
  /// that can be resumed by another client. The canonical transcript rows stay
  /// in `Transcription` and `TranscriptionSegment`.
  try await cleanupStream.write(chunk.text)
}

try await cleanupStream.close()
```

Create a public transcript-only URL:

```swift
try await db.transact {
  PublicRecordingLink.create(
    id: .init(),
    PublicRecordingLink.recording.set(recordingID),
    PublicRecordingLink.slug.set(Slug.random()),
    PublicRecordingLink.createdAt.set(.now),
    PublicRecordingLink.expiresAt.set(.now.addingTimeInterval(24 * 60 * 60)),
    PublicRecordingLink.allowTranscript.set(true),
    PublicRecordingLink.allowAudioPlayback.set(false),
    PublicRecordingLink.allowAudioDownload.set(false),
    PublicRecordingLink.allowAttachments.set(false),
    PublicRecordingLink.allowRoute.set(false),
    PublicRecordingLink.passcodeHash.set(nil)
  )

  Recording.updateExisting(
    id: recordingID,
    Recording.hasPublicLinks.set(true)
  )
}
```

## Swift Schema To TypeScript Codegen

The source of truth should be Swift, because Swift can be stricter than
Instant's TypeScript schema surface:

- Swift optionality expresses requiredness.
- Swift enums remove string typos.
- Swift associated-value enums can encode to JSON while staying exhaustive in
  app code.
- Typed IDs prevent linking a `Recording` where a `Transcription` is expected.
- Generated relation tokens prevent reverse-name drift.
- Indexed/unique annotations can be enforced by macros before an invalid query
  ships.
- Permission builders can use typed capabilities and generated relation paths,
  then emit Instant-compatible `data.ref` and `auth.ref` expressions.

Recommended pipeline:

```text
Swift source
  @InstantEntity
  @InstantRelation
  @InstantIndexed
  @InstantPermissions
  @InstantShareRoot
        │
        ▼
Swift macro expansion and diagnostics
  - generated attribute paths
  - generated reverse relation tokens
  - generated Drafts
  - compile-time query/index validation where possible
        │
        ▼
Schema IR
  - entities
  - attrs
  - links
  - rooms/topics/presence
  - storage paths
  - stream metadata
  - permissions
  - sharing roles/capabilities
        │
        ▼
Generated artifacts
  - instant.schema.ts
  - instant.perms.ts
  - Swift validation fixtures
  - TypeScript parity fixtures
```

Example of strict Swift becoming plain Instant schema:

```swift
@InstantEntity
struct TranscriptionProcessor: Codable, Sendable, Identifiable {
  let id: InstantID<Self>

  @InstantUnique
  var slug: String

  @InstantIndexed
  var provider: Provider

  @InstantJSON
  var configuration: Configuration

  enum Provider: String, Codable, Sendable, InstantStringEnum {
    case appleSpeech
    case whisperLocal
    case whisperRemote
    case deepgram
    case assemblyAI
    case custom
  }

  enum Configuration: Codable, Sendable, InstantJSONCodable {
    case appleSpeech(locale: LanguageCode, requiresOnDeviceRecognition: Bool)
    case whisperLocal(modelURLBookmark: String, computeUnits: ComputeUnits)
    case whisperRemote(endpoint: URL, model: String, temperature: Double?)
    case deepgram(model: String, smartFormat: Bool, diarize: Bool)
    case assemblyAI(speakerLabels: Bool, autoChapters: Bool)
    case custom(JSONValue)
  }
}
```

Generated TypeScript schema shape:

```ts
// Generated. Do not edit by hand.
const _schema = i.schema({
  entities: {
    transcriptionProcessors: i.entity({
      slug: i.string().unique().indexed(),
      provider: i.string().indexed(),
      configuration: i.json(),
    }),
  },
});
```

Swift remains stricter than the TypeScript artifact:

```swift
/// Swift rejects unknown providers while decoding.
let provider: TranscriptionProcessor.Provider = .whisperRemote

/// Swift validates the JSON payload according to the selected enum case.
let configuration: TranscriptionProcessor.Configuration = .deepgram(
  model: "nova-3",
  smartFormat: true,
  diarize: true
)
```

The TypeScript schema only needs to know "this is an indexed string" and "this
is JSON." Swift owns the richer domain guarantees.

## Open Decisions Updated By V2

### API Identity

Recommendation:

- Keep the north star as "InstantDB-native with SQLiteData ergonomics."

User signal:

- Positive toward the bootstrap shape and the explicit `permissions`,
  `persistence`, SQLite, and `sync` slots.

### Sync

Recommendation:

- Keep `sync: .automatic` as the default.
- Add `manual`, `offlineOnly`, `readOnly`, `whenAuthenticated`, `gated`, and
  `custom`.
- Use `gated` for premium-only sync behavior.
- Do not use sync policy as security. Permissions remain the source of truth.

### Streams

Recommendation:

- Treat Instant streams as durable, resumable, progressive-output flows backed
  by Storage and `$streams` metadata.
- Use streams for LLM-style output, cleanup, translation, summaries, redaction,
  chapter generation, logs, and other derived work that benefits from chunked
  resumption.
- Do not use streams as the canonical store for ordinary queryable records.
- Do not re-persist the final transcription if the app already wrote segments
  and word arrays while recording.

### Authentication

Recommendation:

- Add a top-level `auth:` bootstrap slot.
- Hang sign-in, sign-out, account linking, session refresh, and auth-state
  observation from `db.auth`.
- Treat magic code/email, guest/anonymous, Apple, Google, GitHub, LinkedIn,
  Clerk, Firebase, custom ID-token, and custom authorization-code flows as typed
  provider cases.
- Keep `signIn(.anonymous)` and `signInAsGuest()` as aliases so Swift app code
  reads naturally while the Instant naming remains recognizable.
- Model Apple, Google, Clerk, Firebase, and custom OIDC-like providers through a
  shared ID-token exchange shape where possible.
- Model GitHub and LinkedIn through authorization-code/redirect flows.
- Make account linking and guest upgrade first-class so anonymous recording
  data, queued outbox writes, and share memberships survive conversion to a
  full account.
- Use library-owned observable auth state instead of plain optional sessions or
  screen-owned `@State`. `@InstantAuth` and `db.auth` own session restoration,
  magic-code challenge state, provider progress, account linking, errors, and
  sign-out.
- Support optional side-effect callbacks such as `onChallengeSent`,
  `onProviderCompleted`, `onSignIn`, `onAccountLinked`, `onSignOut`,
  `onFailure`, and `onComplete`. These callbacks must not be required for state
  the library can expose directly.

### Operation Callbacks

Recommendation:

- Every operation category should support lifecycle callbacks:
  - auth
  - create/update/delete/mutate
  - storage upload/delete
  - stream create/write/read/close
  - sync connect/flush/retry
  - sharing create/accept/update/revoke
- Use a shared initiated-operation vocabulary: `onStart`,
  `onOptimisticCommit`, `onServerAccepted`, `onFailure`, and `onComplete`.
- Use a separate received-data vocabulary: `onInitialLocalLoad`,
  `onRemoteChange`, `onRemoteBatch`, and `onCaughtUp`.
- Add specialized callbacks where the domain needs them, such as upload
  progress and stream chunks/byte offsets.

### Sharing

Recommendation:

- Add a top-level `sharing:` bootstrap slot.
- Treat sharing as schema plus permissions plus typed app roles/scopes.
- Let share links and public URLs be app-visible entities so product behavior is
  inspectable and testable.

### Schema Annotations

Recommendation:

- Support property annotations for index, uniqueness, field naming, relation
  metadata, wire type, JSON encoding, draft defaults, ignored fields, and
  sensitive fields.
- Infer requiredness from Swift optionality.
- Generate diagnostics when queries filter/order by non-indexed fields.
- Prefer compile failures or macro diagnostics over warnings when the invalid
  query can be known statically.
- Use Swift as the source of truth and generate `instant.schema.ts` and
  `instant.perms.ts` from stricter Swift schema/permission declarations.

### Domain Model

Recommendation:

- Use the transcription domain as the primary realism test.
- Keep words as duplicated JSON arrays on `Transcription` and
  `TranscriptionSegment`.
- Keep segment text duplicated as scalar strings for query/search.
- Create recording/transcription shells up front and update them as recording
  progresses.
- Finish recording by updating state/timestamps/status, not by rewriting the
  whole final transcription.
- Model route points as separate linked entities, with a small JSON route
  summary on `Recording`.
- Model public URLs with `PublicRecordingLink`, not raw public flags alone.
- Model audio as `InstantFile` links and typed storage paths, not URL strings.
- Derive member capabilities from `RecordingMember.Role` and optional overrides
  instead of persisting duplicate permission booleans.

### Screen Sketches

Recommendation:

- Keep `screens/` as the place for concrete UI syntax probes.
- Each screen should name its URI, show an ASCII sketch, and provide one full
  Swift block.
- Login/authentication screens should bind to `@InstantAuth` fields such as
  `email`, `magicCode`, `mode`, `status`, and `session`.
- Recording and playback screens should make entity persistence feel natural:
  stable transcription data is written as rows while recording, while streams
  are reserved for optional progressive derived output.
- Preferences should expose account linking, session refresh, sign-out, sync
  policy, manual flush, storage cleanup, and schema export through typed library
  state/actions.

## Next Question

Question 2 should resolve schema declaration style:

- Entity macros only.
- Central schema builder only.
- Entity macros plus generated central schema.

Recommended answer:

Use entity macros as the authoring surface and generate a central schema from
them. Add an optional central schema file only for cross-cutting declarations
such as permissions, sharing roots, room types, storage path types, and global
validation.
