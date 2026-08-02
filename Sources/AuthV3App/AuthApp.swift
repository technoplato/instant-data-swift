import Dependencies
import Foundation
import InstantSwiftData

public struct AuthV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public init(appID: String, persistenceURL: URL? = nil, enablesLiveSync: Bool) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configuredAppID = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let isValidUUID = configuredAppID.flatMap(UUID.init(uuidString:)) != nil
    return Self(
      appID: isValidUUID ? configuredAppID ?? "auth-v3-local" : "auth-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: isValidUUID
    )
  }
}

public typealias AuthAppConfiguration = AuthV3AppConfiguration

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class AuthV3BootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: AuthV3AppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: AuthV3AppConfiguration) {
      self.configuration = configuration
    }

    public func startIfNeeded() {
      guard client == nil, task == nil else { return }
      task = Task { @MainActor [weak self, configuration] in
        do {
          var dependencies = DependencyValues()
          if configuration.enablesLiveSync {
            dependencies.instantLiveTransport = .live
          } else {
            dependencies.instantMagicCodeExchange = .local
            dependencies.instantRefreshTokenVerifier = .local
            dependencies.instantGuestAuthenticator = .local
            dependencies.instantIDTokenExchange = .local
            dependencies.instantOAuthExchange = .local
            dependencies.instantAuthTokenInvalidator = .local
            dependencies.instantStorageTransport = nil
          }
          try await dependencies.bootstrapInstantSwiftData(
            appID: configuration.appID,
            persistenceURL: configuration.persistenceURL,
            initialAttributes: AuthV3User.instantAttributes
          )
          let client = dependencies.defaultInstantSwiftData
          prepareDependencies { $0.defaultInstantSwiftData = client }
          self?.client = client
          self?.task = nil
        } catch {
          self?.errorMessage = String(describing: error)
          self?.task = nil
        }
      }
    }
  }

  @MainActor
  public struct AuthV3BootstrapScreen: View {
    @StateObject private var model: AuthV3BootstrapModel

    public init(model: AuthV3BootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if model.client != nil {
          AuthV3LoginScreen(allowsProviderSignIn: model.configuration.enablesLiveSync)
        } else if let errorMessage = model.errorMessage {
          Text(errorMessage)
        } else {
          ProgressView("Opening Auth")
        }
      }
      .task { model.startIfNeeded() }
    }
  }

  @MainActor
  public struct AuthV3LoginScreen: View {
    @StateObject private var auth: InstantAuthState<AuthV3User>

    @State private var message: String?
    private let allowsProviderSignIn: Bool

    public init(
      allowsProviderSignIn: Bool = true,
      providerConfiguration: AuthV3ProviderConfiguration = .environment()
    ) {
      self.allowsProviderSignIn = allowsProviderSignIn
      _auth = StateObject(
        wrappedValue: InstantAuthState(
          providers: AuthV3Providers.providers(configuration: providerConfiguration)
        )
      )
    }

    public var body: some View {
      ZStack {
        LinearGradient(
          colors: [Color.accentColor.opacity(0.16), Color.clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 20) {
            header
            if let message {
              statusCard(message)
            }
            if let session = auth.session {
              if session.isGuest {
                guestAccountCard(session)
                providerCard(
                  title: "Keep your guest work",
                  detail: "Connect Apple or Google without signing out first."
                )
              } else {
                signedInCard(session)
              }
            } else {
              emailCard
              providerCard(
                title: "Or use an account",
                detail: "Your provider credential is exchanged directly with Instant."
              )
              guestCard
            }
          }
          .frame(maxWidth: 520)
          .padding(.horizontal, 24)
          .padding(.vertical, 40)
        }
        .disabled(auth.isBusy)

        if auth.isBusy {
          ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            ProgressView("Working…")
              .padding(.horizontal, 24)
              .padding(.vertical, 18)
              .background(.regularMaterial, in: Capsule())
          }
        }
      }
      .task { auth.startObservationIfNeeded() }
    }

    private var header: some View {
      VStack(spacing: 10) {
        Image(systemName: "person.crop.circle.badge.checkmark")
          .font(.system(size: 46, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        Text("Welcome")
          .font(.largeTitle.bold())
        Text("A secure, durable Instant account starts here.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }

    private var emailCard: some View {
      authCard {
        VStack(alignment: .leading, spacing: 16) {
          sectionHeader(
            title: showsMagicCode ? "Enter your code" : "Sign in with email",
            detail: showsMagicCode
              ? "Use the one-time code sent to \(auth.email)."
              : "We’ll send a one-time code. No password required."
          )

          if showsMagicCode {
            TextField("One-time code", text: $auth.magicCode)
              .textFieldStyle(.roundedBorder)
              .textContentType(.oneTimeCode)
              .onSubmit(verifyMagicCodeButtonTapped)
            Button(action: verifyMagicCodeButtonTapped) {
              Text("Verify and continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Use a different email") {
              message = nil
              auth.resetMagicCode()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
          } else {
            TextField("Email address", text: $auth.email)
              .textFieldStyle(.roundedBorder)
              .textContentType(.emailAddress)
              .onSubmit(sendMagicCodeButtonTapped)
            Button(action: sendMagicCodeButtonTapped) {
              Label("Send one-time code", systemImage: "envelope")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
          }
        }
      }
    }

    private var guestCard: some View {
      authCard {
        VStack(alignment: .leading, spacing: 14) {
          sectionHeader(
            title: "Not ready to choose?",
            detail: "Start as a guest, then connect an account later from this screen."
          )
          Button(action: guestButtonTapped) {
            Label("Continue as guest", systemImage: "person.crop.circle.dashed")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
        }
      }
    }

    private func providerCard(title: String, detail: String) -> some View {
      authCard {
        VStack(alignment: .leading, spacing: 14) {
          sectionHeader(title: title, detail: detail)
          if allowsProviderSignIn {
            ForEach(auth.credentialProviders) { provider in
              Button {
                providerButtonTapped(provider)
              } label: {
                Label(provider.title, systemImage: provider.systemImage)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
          } else {
            Label(
              "Add a valid INSTANT_APP_ID to enable Apple and Google sign-in.",
              systemImage: "wrench.and.screwdriver"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        }
      }
    }

    private func guestAccountCard(_ session: InstantAuthSession) -> some View {
      authCard {
        VStack(alignment: .leading, spacing: 12) {
          Label("Guest session", systemImage: "person.crop.circle.dashed")
            .font(.headline)
          Text(
            "This device has a guest identity. Connect a provider below while this session is active so Instant can upgrade or link it."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          Text(session.userID)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Button("Discard guest session", role: .destructive, action: signOutButtonTapped)
            .buttonStyle(.bordered)
        }
      }
    }

    private func signedInCard(_ session: InstantAuthSession) -> some View {
      authCard {
        VStack(alignment: .leading, spacing: 14) {
          Label("Account connected", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
          if let email = auth.user?.email {
            Text(email).font(.title3.weight(.semibold))
          }
          Text(session.userID)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Button("Sign out", role: .destructive, action: signOutButtonTapped)
            .buttonStyle(.bordered)
        }
      }
    }

    private func statusCard(_ text: String) -> some View {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(Color.accentColor)
        Text(text)
          .font(.subheadline)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
      .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
      .accessibilityElement(children: .combine)
    }

    private func sectionHeader(title: String, detail: String) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }

    private func authCard<Content: View>(
      @ViewBuilder content: () -> Content
    ) -> some View {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode: true
      default: false
      }
    }

    private func providerButtonTapped(_ provider: AuthProviderSelection) {
      auth.signIn(
        provider,
        onSignedIn: { event in
          message = signedInMessage(event)
        },
        onFailure: { error in
          message = error.description
        }
      )
    }

    private func sendMagicCodeButtonTapped() {
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          message = "Code sent to \(challenge.email)"
        },
        onFailure: { error in
          message = error.description
        }
      )
    }

    private func verifyMagicCodeButtonTapped() {
      auth.verifyMagicCode(
        onSignedIn: { event in
          message = signedInMessage(event)
        },
        onFailure: { error in
          message = error.description
        }
      )
    }

    private func guestButtonTapped() {
      auth.signInAsGuest(
        onSignedIn: { _ in
          message = "Guest session created. Connect Apple or Google below whenever you’re ready."
        },
        onFailure: { error in
          message = error.description
        }
      )
    }

    private func signOutButtonTapped() {
      auth.signOut(
        onSignedOut: { message = "Signed out." },
        onFailure: { error in message = error.description }
      )
    }

    private func signedInMessage(_ event: InstantAuthSignedInEvent) -> String {
      switch event.identityTransition {
      case .signedIn:
        return "Account connected successfully."
      case .guestPromoted(let result):
        switch result.disposition {
        case .upgradedInPlace:
          return "Account connected. Your guest identity was upgraded in place."
        case .linkedToExistingUser:
          return
            "Account connected to an existing user. The guest identity remains linked; guest-owned records require linked-guest permissions and were not automatically transferred."
        case .identityChangedWithoutVerifiedLink:
          return
            "Account connected as a different user, but this auth exchange could not verify a guest link. Guest-owned records may remain inaccessible until linkage is confirmed."
        }
      }
    }
  }
#endif
