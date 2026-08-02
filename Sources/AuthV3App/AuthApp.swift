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
    @State private var logText = "--- Debug Console Started ---\n"

    public init() {}

    public var body: some View {
      HSplitView {
        Form {
          if let session = auth.session {
            Section("Signed In") {
              Text("User ID: \(session.userID)")
              if let email = auth.user?.email {
                Text("Email: \(email)")
              }
              Button("Log out") {
                log("Action: Log out initiated")
                auth.signOut(
                  onSignedOut: {
                    message = "Signed out"
                    log("Event: Signed out successfully")
                  },
                  onFailure: { error in
                    message = error.recoveryMessage
                    log("Error on signOut: \(error.message) | Recovery: \(error.recovery)")
                  }
                )
              }
            }
          } else {
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
        }
        .disabled(auth.isBusy)
        .overlay {
          if auth.isBusy { ProgressView() }
        }
        .frame(minWidth: 300)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Debug Logs (/tmp/instant-auth-debug.log)")
              .font(.caption)
              .bold()
            Spacer()
            Button("Clear") {
              logText = ""
            }
            .font(.caption)
          }

          TextEditor(text: .constant(logText))
            .font(.system(.body, design: .monospaced))
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)
        }
        .padding(8)
        .frame(minWidth: 320)
      }
    }

    private var showsMagicCode: Bool {
      switch auth.mode {
      case .magicCodeSent, .verifyingMagicCode: true
      default: false
      }
    }

    private func log(_ entry: String) {
      let formatted = "[\(ISO8601DateFormatter().string(from: Date()))] \(entry)\n"
      logText += formatted
      appendToFile(formatted)
    }

    private func appendToFile(_ text: String) {
      let logURL = URL(fileURLWithPath: "/tmp/instant-auth-debug.log")
      if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
          handle.write(data)
        }
        try? handle.close()
      } else {
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
      }
    }

    private func providerButtonTapped(_ provider: AuthProviderSelection) {
      log("Action: providerButtonTapped -> \(provider.title) (\(provider.id.rawValue))")
      auth.signIn(
        provider,
        onProviderCompleted: { credential in
          message = "Received \(credential.providerID.rawValue) credential"
          log("Event: onProviderCompleted for \(credential.providerID.rawValue)")
        },
        onSignedIn: { event in
          message = "Signed in as \(event.session.userID)"
          log("Event: onSignedIn -> User ID: \(event.session.userID)")
        },
        onFailure: { error in
          message = error.recoveryMessage
          log("Error on signIn (\(provider.id.rawValue)): message='\(error.message)' recovery='\(error.recovery)' operation='\(error.operation)'")
        }
      )
    }

    private func sendMagicCodeButtonTapped() {
      log("Action: sendMagicCode to \(auth.email)")
      auth.sendMagicCode(
        onChallengeSent: { challenge in
          message = "Code sent to \(challenge.email)"
          log("Event: onChallengeSent to \(challenge.email)")
        },
        onFailure: { error in
          message = error.recoveryMessage
          log("Error on sendMagicCode: '\(error.message)' recovery='\(error.recovery)'")
        }
      )
    }

    private func verifyMagicCodeButtonTapped() {
      log("Action: verifyMagicCode with \(auth.magicCode)")
      auth.verifyMagicCode(
        onSignedIn: { event in
          message = "Signed in as \(event.session.userID)"
          log("Event: onSignedIn -> User ID: \(event.session.userID)")
        },
        onFailure: { error in
          message = error.recoveryMessage
          log("Error on verifyMagicCode: '\(error.message)' recovery='\(error.recovery)'")
        }
      )
    }

    private func guestButtonTapped() {
      log("Action: guestButtonTapped")
      auth.signInAsGuest(
        onSignedIn: { event in
          message = "Guest \(event.session.userID)"
          log("Event: onSignedIn as Guest -> User ID: \(event.session.userID)")
        },
        onFailure: { error in
          message = error.recoveryMessage
          log("Error on signInAsGuest: '\(error.message)' recovery='\(error.recovery)'")
        }
      )
    }
  }
#endif

