# Authentication Screen

URI: `auth.login` (`voicetrail://auth/login`)

ASCII sketch:

```text
+--------------------------------------------------+
|                    VoiceTrail                    |
|        Record the walk. Keep the words.          |
|                                                  |
|  [ Continue with Apple                       ]   |
|  [ Continue with Google                      ]   |
|  [ Continue with GitHub                      ]   |
|  [ Continue with LinkedIn                    ]   |
|  [ Continue with Clerk                       ]   |
|  [ Continue with Firebase                    ]   |
|  [ Continue with Company SSO                 ]   |
|                                                  |
|  ------------------- email -------------------   |
|  Email                                           |
|  [ aisha@example.com                         ]   |
|  [ Send magic code                           ]   |
|                                                  |
|  [ Continue as guest                         ]   |
+--------------------------------------------------+

+--------------------------------------------------+
|                    VoiceTrail                    |
|                                                  |
|  Sent, please check aisha@example.com for the    |
|  code and enter it here.                         |
|                                                  |
|  Code                                            |
|  [ 123456                                    ]   |
|  [ Verify code                              ]    |
|  [ Use a different email                    ]    |
+--------------------------------------------------+
```

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

/// A dumb login screen for every configured VoiceTrail provider.
///
/// The important thing here is what is missing: no copied auth session, no
/// copied magic-code challenge, no copied login phase, and no hand-written
/// navigation. `@InstantAuth` is the view model, and the app shell observes
/// `db.auth.status` above this screen to decide whether to show the signed-in
/// app.
struct AuthLoginScreen: View {
  @InstantAuth(VoiceTrailUser.self) private var auth

  @Dependency(\.analytics) private var analytics
  @Dependency(\.haptics) private var haptics
  @Dependency(\.toast) private var toast

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
    .accessibilityElement(children: .contain)
  }

  /// The provider list is typed app data, not scattered button strings.
  ///
  /// A macOS build could filter providers differently than an iOS build while
  /// keeping the same sign-in surface. The provider value is also the value
  /// passed to `auth.signIn`, so the label and behavior cannot drift.
  private var providerButtons: some View {
    VStack(spacing: 10) {
      ForEach(LoginProvider.allCases) { provider in
        Button {
          Task { await signIn(with: provider) }
        } label: {
          Label(provider.title, systemImage: provider.systemImage)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  /// Email login is a two-mode form driven by `auth.mode`.
  ///
  /// The challenge and code are stored by `@InstantAuth`, so the user can
  /// background the app, return to this screen, and continue without a fragile
  /// view-owned `@State` value.
  @ViewBuilder
  private var magicCodeForm: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Email", text: $auth.email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)

      switch auth.mode {
      case .magicCodeSent(let email), .verifyingMagicCode(let email):
        Text("Sent, please check \(email) for the code and enter it here.")
          .foregroundStyle(.secondary)

        TextField("Code", text: $auth.magicCode)
          .textContentType(.oneTimeCode)
          .keyboardType(.numberPad)

        Button {
          Task {
            await auth.verifyMagicCode { event in
              analytics.track(.signedIn(event.userID, provider: .magicCode))
              haptics.success()
            } onFailure: { error in
              toast.show(error.recoveryMessage)
              haptics.error()
            }
          }
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
          Task {
            await auth.sendMagicCode { challenge in
              analytics.track(.magicCodeSent(challenge.email))
              haptics.success()
            } onFailure: { error in
              toast.show(error.recoveryMessage)
              haptics.error()
            }
          }
        } label: {
          Text("Send magic code")
            .frame(maxWidth: .infinity)
        }
      }
    }
  }

  /// Guest auth and anonymous auth can both exist.
  ///
  /// The app-facing spelling reads like Swift, while the implementation still
  /// maps onto Instant's guest auth behavior and can later upgrade this account
  /// through `auth.linkCurrentUser`.
  private var guestButton: some View {
    Button {
      Task {
        await auth.signInAsGuest { event in
          analytics.track(.signedIn(event.userID, provider: .guest))
        } onFailure: { error in
          toast.show(error.recoveryMessage)
        }
      }
    } label: {
      Text("Continue as guest")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
  }

  private var header: some View {
    VStack(spacing: 6) {
      Text("VoiceTrail")
        .font(.largeTitle.bold())
      Text("Record the walk. Keep the words.")
        .foregroundStyle(.secondary)
    }
  }

  /// A typed menu of configured providers.
  ///
  /// No screen code constructs provider names by string. Adding a future
  /// provider means adding one enum case, one title, and one typed provider
  /// selection.
  private enum LoginProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    case google
    case github
    case linkedIn
    case clerk
    case firebase
    case enterpriseSSO

    var id: Self { self }

    var title: String {
      switch self {
      case .apple: "Continue with Apple"
      case .google: "Continue with Google"
      case .github: "Continue with GitHub"
      case .linkedIn: "Continue with LinkedIn"
      case .clerk: "Continue with Clerk"
      case .firebase: "Continue with Firebase"
      case .enterpriseSSO: "Continue with Company SSO"
      }
    }

    var systemImage: String {
      switch self {
      case .apple: "apple.logo"
      case .google: "g.circle"
      case .github: "chevron.left.forwardslash.chevron.right"
      case .linkedIn: "person.crop.square"
      case .clerk: "key"
      case .firebase: "flame"
      case .enterpriseSSO: "building.2"
      }
    }

    var provider: AuthProviderSelection {
      switch self {
      case .apple:
        .apple(clientName: "apple-ios")
      case .google:
        .google(clientName: "google-ios")
      case .github:
        .github(clientName: "github-web")
      case .linkedIn:
        .linkedIn(clientName: "linkedin-web")
      case .clerk:
        .clerk(clientName: "clerk")
      case .firebase:
        .firebase(clientName: "firebase")
      case .enterpriseSSO:
        .authorizationCode(clientName: "enterprise-oidc")
      }
    }
  }

  /// Provider sign-in exposes trailing closures for one-off side effects.
  ///
  /// The view does not navigate on success. The root app shell reacts to
  /// `db.auth.status`, while this callback records that the user completed an
  /// explicit sign-in gesture.
  private func signIn(with provider: LoginProvider) async {
    await auth.signIn(provider.provider) { event in
      analytics.track(.signedIn(event.userID, provider: provider.rawValue))
      haptics.success()
    } onProviderCompleted: { credential in
      analytics.track(.providerCredentialReceived(provider.rawValue))
    } onFailure: { error in
      toast.show(error.recoveryMessage)
      haptics.error()
    }
  }
}
```
