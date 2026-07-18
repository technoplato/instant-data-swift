# Authentication Screen, V3

URI: `auth.login` (`voicetrail://auth/login`)

This version keeps auth state in `@InstantAuth`, but keeps callbacks at
the call site. That makes each button show the side effects caused by
that particular user action without making callbacks another source of
state.

Implementation status (2026-07-18): the reusable `@InstantAuth` state owner
and provider contract are implemented in
`Sources/InstantSwiftData/InstantAuth.swift` and
`Sources/InstantSwiftData/InstantAuthProvider.swift`. The public syntax below
is compiled by `Tests/InstantSwiftDataTests/V3AuthLoginFixtureTests.swift`,
which also proves magic-code success, invalid-code retry, stale-action
cancellation, typed provider exchange, callback cardinality, and durable
session restoration after relaunch. Platform-native/browser credential UI is
intentionally supplied by the injected `InstantAuthProviderAuthorizer`.

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

struct VoiceTrailAuthLoginScreen: View {
  /// `@InstantAuth` owns the authentication state machine.
  ///
  /// The screen binds directly to `email`, `magicCode`, `mode`, and
  /// `status`. It does not copy those values into local `@State`, and it
  /// does not navigate when sign-in succeeds. The app shell can react to
  /// `auth.status`.
  @InstantAuth(
    VoiceTrailUser.self,
    providers: VoiceTrailAuthProviders.self
  )
  private var auth

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  var body: some View {
    VStack(spacing: 18) {
      header
      providerButtons
      Divider()
      magicCodeForm
      guestButton
    }
    .padding(24)
    .disabled(auth.isBusy)
    .overlay {
      if auth.isBusy {
        ProgressView()
      }
    }
  }

  private var header: some View {
    VStack(spacing: 6) {
      Text("VoiceTrail")
        .font(.largeTitle.bold())

      Text("Record the walk. Keep the words.")
        .foregroundStyle(.secondary)
    }
  }

  private var providerButtons: some View {
    VStack(spacing: 10) {
      ForEach(auth.providers) { provider in
        Button {
          providerButtonTapped(provider)
        } label: {
          Label(
            provider.title,
            systemImage: provider.systemImage
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  @ViewBuilder
  private var magicCodeForm: some View {
    VStack(
      alignment: .leading,
      spacing: 10
    ) {
      TextField(
        "Email",
        text: $auth.email
      )
      .textContentType(.emailAddress)
      .keyboardType(.emailAddress)
      .textInputAutocapitalization(.never)

      switch auth.mode {
      case .magicCodeSent(let email),
        .verifyingMagicCode(let email):
        Text(
          "Sent, please check "
            + email
            + " for the code."
        )
        .foregroundStyle(.secondary)

        TextField(
          "Code",
          text: $auth.magicCode
        )
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)

        Button {
          verifyMagicCodeButtonTapped()
        } label: {
          Text("Verify code")
            .frame(maxWidth: .infinity)
        }

        Button("Use a different email") {
          auth.resetMagicCode()
        }
        .buttonStyle(.plain)

      default:
        Button {
          sendMagicCodeButtonTapped()
        } label: {
          Text("Send magic code")
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  private var guestButton: some View {
    Button {
      guestButtonTapped()
    } label: {
      Text("Continue as guest")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
  }

  /// Provider sign-in remains a message to `auth`.
  ///
  /// The wrapper owns the async work and updates `auth.status`; these
  /// closures only run side effects for this button tap. Passive session
  /// restoration should not call these closures.
  private func providerButtonTapped(
    _ provider: AuthProviderSelection
  ) {
    auth.signIn(
      provider,
      onProviderCompleted: { credential in
        analytics.track(
          .providerCredentialReceived(
            credential.providerID.rawValue
          )
        )
      },
      onSignedIn: { event in
        analytics.track(
          .signedIn(
            event.session.userID,
            provider: event.providerID.rawValue
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  /// Sending a magic code changes the form mode in `@InstantAuth`.
  ///
  /// The callback is useful for haptics and analytics, not for storing
  /// the challenge in the view.
  private func sendMagicCodeButtonTapped() {
    auth.sendMagicCode(
      onChallengeSent: { challenge in
        analytics.track(
          .magicCodeSent(challenge.email)
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  /// Verifying the code produces an Instant session.
  ///
  /// The session itself still belongs to `@InstantAuth`; this callback is
  /// only the explicit user-action hook.
  private func verifyMagicCodeButtonTapped() {
    auth.verifyMagicCode(
      onSignedIn: { event in
        analytics.track(
          .signedIn(
            event.session.userID,
            provider: .magicCode
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func guestButtonTapped() {
    auth.signInAsGuest(
      onSignedIn: { event in
        analytics.track(
          .signedIn(
            event.session.userID,
            provider: .guest
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }
}

enum VoiceTrailAuthProviders:
  InstantAuthProviderCatalog {
  static let magicCode =
    AuthProvider.magicCode(
      email: .instant,
      extraFields: VoiceTrailUser.Signup.self
    )

  static let apple =
    AuthProvider.apple(
      clientName: "apple-ios",
      presentation: .native
    )

  static let google =
    AuthProvider.google(
      clientName: "google-ios",
      presentation: .native
    )

  static let github =
    AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser
    )

  static let enterprise =
    AuthProvider.authorizationCode(
      id: "enterprise-oidc",
      clientName: "enterprise-oidc"
    )

  static let all = [
    magicCode,
    apple,
    google,
    github,
    enterprise
  ]
}
```
