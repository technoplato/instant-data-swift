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
    return Self(
      appID: configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "auth-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
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
          AuthV3LoginScreen()
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
    @InstantAuth(AuthV3User.self, providers: AuthV3Providers.self)
    private var auth

    @State private var message = "Signed out"

    public init() {}

    public var body: some View {
      Form {
        Section("Instant Auth") {
          Text(message)
          TextField("Email", text: $auth.email)

          if showsMagicCode {
            TextField("Code", text: $auth.magicCode)
            Button("Verify code", action: verifyMagicCodeButtonTapped)
            Button("Use a different email", action: auth.resetMagicCode)
              .buttonStyle(.plain)
          } else {
            Button("Send magic code", action: sendMagicCodeButtonTapped)
          }

          Button("Continue as guest", action: guestButtonTapped)
        }

        Section("Providers") {
          ForEach(auth.providers) { provider in
            Button(provider.title) { providerButtonTapped(provider) }
          }
        }
      }
      .disabled(auth.isBusy)
      .overlay {
        if auth.isBusy { ProgressView() }
      }
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
        onProviderCompleted: { credential in
          message = "Received \(credential.providerID.rawValue) credential"
        },
        onSignedIn: { event in
          message = "Signed in as \(event.session.userID)"
        },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func sendMagicCodeButtonTapped() {
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          if let code = Self.autofillCode(challenge) {
            auth.magicCode = code
          }
          message = Self.challengeMessage(challenge)
        },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    static func challengeMessage(_ challenge: InstantMagicCodeChallenge) -> String {
      guard let code = autofillCode(challenge) else {
        return "Code sent to \(challenge.email)"
      }
      return "Code sent to \(challenge.email). Local code: \(code)"
    }

    static func autofillCode(_ challenge: InstantMagicCodeChallenge) -> String? {
      let code = challenge.code.trimmingCharacters(in: .whitespacesAndNewlines)
      return code.isEmpty ? nil : code
    }

    private func verifyMagicCodeButtonTapped() {
      auth.verifyMagicCode(
        onSignedIn: { event in message = "Signed in as \(event.session.userID)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func guestButtonTapped() {
      auth.signInAsGuest(
        onSignedIn: { event in message = "Guest \(event.session.userID)" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }
#endif
