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

  #if canImport(UIKit)
    import UIKit
  #endif

  private struct AuthV3AllowsDiscardingGuestSessionKey: EnvironmentKey {
    static let defaultValue = true
  }

  private struct AuthV3ShowsDemoCountersKey: EnvironmentKey {
    static let defaultValue = true
  }

  private struct AuthV3ShowsLinkedSignInsKey: EnvironmentKey {
    static let defaultValue = false
  }

  extension EnvironmentValues {
    /// Whether ``AuthV3LoginScreen``'s guest card offers "Discard guest session".
    ///
    /// Discarding signs the guest out. The next launch creates a new guest, and nothing on this
    /// device can read the old guest's data again. Apps whose guest owns user data turn this off,
    /// so the only way off a guest session is a provider sign-in, which upgrades the guest in place
    /// or links it to an existing account:
    ///
    /// ```swift
    /// AuthV3LoginScreen()
    ///   .environment(\.authV3AllowsDiscardingGuestSession, false)
    /// ```
    public var authV3AllowsDiscardingGuestSession: Bool {
      get { self[AuthV3AllowsDiscardingGuestSessionKey.self] }
      set { self[AuthV3AllowsDiscardingGuestSessionKey.self] = newValue }
    }

    /// Whether ``AuthV3LoginScreen`` shows the Auth recipe's demo counters ("Increment public" and
    /// "Increment mine").
    ///
    /// The counters demonstrate a public row and a per-account row in the recipe's own
    /// `recipe_public_counters` and `recipe_account_counters` entities. While the card is on screen it
    /// observes both entities, and it creates the public row as soon as it appears. Apps whose schema
    /// does not declare those entities turn the card off, or every one of those reads and writes fails:
    ///
    /// ```swift
    /// AuthV3LoginScreen()
    ///   .environment(\.authV3ShowsDemoCounters, false)
    /// ```
    public var authV3ShowsDemoCounters: Bool {
      get { self[AuthV3ShowsDemoCountersKey.self] }
      set { self[AuthV3ShowsDemoCountersKey.self] = newValue }
    }

    /// Whether ``AuthV3LoginScreen`` shows "Linked sign-ins" while an account is signed in.
    ///
    /// The card lists the sign-ins linked to this account in its `accountLinks` row, unlinks them, and links
    /// another sign-in with Apple, Google, or an email code. Linking signs the other identity in on a temporary
    /// second sign-in (``InstantSecondSignIn``), so this device's session never changes. Only apps whose Instant
    /// schema and permissions declare account links (``InstantAccountLinks``) turn it on; every other app leaves it
    /// off, or the card's reads and writes fail:
    ///
    /// ```swift
    /// AuthV3LoginScreen()
    ///   .environment(\.authV3ShowsLinkedSignIns, true)
    /// ```
    public var authV3ShowsLinkedSignIns: Bool {
      get { self[AuthV3ShowsLinkedSignInsKey.self] }
      set { self[AuthV3ShowsLinkedSignInsKey.self] = newValue }
    }
  }

  extension Optional {
    /// Whether a presentation driven by this optional is showing. Setting `false` clears it.
    fileprivate var isPresented: Bool {
      get { self != nil }
      set {
        guard !newValue else { return }
        self = nil
      }
    }
  }

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
            initialAttributes: AuthV3User.instantAttributes + AuthV3CounterAttributes.all
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
    @State private var linkEmail = ""
    @State private var linkCode = ""
    @State private var memberPendingUnlink: InstantAccountLink.Member?
    @Environment(\.authV3AllowsDiscardingGuestSession) private var allowsDiscardingGuestSession
    @Environment(\.authV3ShowsDemoCounters) private var showsDemoCounters
    @Environment(\.authV3ShowsLinkedSignIns) private var showsLinkedSignIns
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
            if showsDemoCounters {
              // Public counter (no perms) + mine counter that switches with login/logout.
              if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
                AuthV3CountersCard(session: auth.session)
              }
            }
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
              if showsLinkedSignIns {
                linkedSignInsCard(session)
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
          if allowsDiscardingGuestSession {
            Button("Discard guest session", role: .destructive, action: signOutButtonTapped)
              .buttonStyle(.bordered)
          } else {
            Text("Sign in below to keep this device's data in your account.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
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

    private func linkedSignInsCard(_ session: InstantAuthSession) -> some View {
      authCard {
        VStack(alignment: .leading, spacing: 14) {
          sectionHeader(
            title: "Linked sign-ins",
            detail: "Sign-ins linked here belong to one account. Linking never signs this device out."
          )
          if let link = auth.accountLink, !link.members.isEmpty {
            ForEach(link.members, id: \.userID) { member in
              linkedMemberRow(member, session: session)
            }
          } else {
            Text("No other sign-in is linked to this account.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          linkingStatusRow
          Divider()
          Text("Link another sign-in")
            .font(.subheadline.weight(.semibold))
          if allowsProviderSignIn {
            ForEach(auth.credentialProviders) { provider in
              Button {
                linkProviderButtonTapped(provider)
              } label: {
                Label(linkTitle(provider), systemImage: provider.systemImage)
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
          }
          linkEmailCodeControls
        }
      }
      .disabled(isLinkingInProgress)
      .confirmationDialog(
        "Unlink this sign-in?",
        isPresented: $memberPendingUnlink.isPresented,
        titleVisibility: .visible,
        presenting: memberPendingUnlink
      ) { member in
        Button("Unlink", role: .destructive) {
          unlinkButtonConfirmed(member)
        }
      } message: { member in
        Text(
          "\(linkedMemberTitle(member)) stops sharing this account. You can link it again later."
        )
      }
      .task(id: session.userID) {
        await auth.refreshAccountLink().value
      }
    }

    private func linkedMemberRow(
      _ member: InstantAccountLink.Member,
      session: InstantAuthSession
    ) -> some View {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: member.isGuest ? "person.crop.circle.dashed" : "person.crop.circle")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(linkedMemberTitle(member))
            .font(.subheadline.weight(.medium))
          let details = linkedMemberDetails(member, session: session)
          if !details.isEmpty {
            Text(details)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        if member.userID != session.userID {
          Button("Unlink", role: .destructive) {
            memberPendingUnlink = member
          }
          .buttonStyle(.borderless)
        }
      }
      .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var linkingStatusRow: some View {
      switch auth.linking {
      case .idle:
        EmptyView()
      case .signingInSecond(let providerID):
        linkingProgress("Signing in with \(providerName(providerID))…")
      case .sendingCode:
        linkingProgress("Sending a code…")
      case .codeSent(let email):
        Label("Code sent to \(email).", systemImage: "envelope")
          .font(.footnote)
          .foregroundStyle(.secondary)
      case .linking:
        linkingProgress("Linking…")
      case .unlinking:
        linkingProgress("Unlinking…")
      case .failed(let error):
        VStack(alignment: .leading, spacing: 4) {
          Label(error.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
          Text(error.recovery)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
      }
    }

    private func linkingProgress(_ text: String) -> some View {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(text)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var linkEmailCodeControls: some View {
      if let email = auth.linkCodeEmail {
        TextField("Code sent to \(email)", text: $linkCode)
          .textFieldStyle(.roundedBorder)
          .textContentType(.oneTimeCode)
          .onSubmit(linkCodeSubmitted)
        HStack {
          Button("Link", action: linkCodeSubmitted)
            .buttonStyle(.borderedProminent)
          Button("Use a different email") {
            linkCode = ""
            auth.cancelLinking()
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
        }
      } else {
        TextField("Email address", text: $linkEmail)
          .textFieldStyle(.roundedBorder)
          .textContentType(.emailAddress)
          .onSubmit(sendLinkCodeButtonTapped)
        Button(action: sendLinkCodeButtonTapped) {
          Label("Send code", systemImage: "envelope")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
    }

    private var isLinkingInProgress: Bool {
      switch auth.linking {
      case .signingInSecond, .sendingCode, .linking, .unlinking: true
      case .idle, .codeSent, .failed: false
      }
    }

    private func linkTitle(_ provider: AuthProvider) -> String {
      "Link \(providerName(provider.id))"
    }

    private func providerName(_ providerID: InstantAuthProviderID) -> String {
      switch InstantAccountLinkProvider(providerID: providerID) {
      case .apple: "Apple"
      case .google: "Google"
      case .magicCode: "an email code"
      case .guest: "a guest session"
      case .refreshToken: "a stored sign-in"
      case nil: providerID.rawValue
      }
    }

    private func linkedMemberTitle(_ member: InstantAccountLink.Member) -> String {
      member.email ?? "Guest \(member.userID.prefix(8))"
    }

    private func linkedMemberDetails(
      _ member: InstantAccountLink.Member,
      session: InstantAuthSession
    ) -> String {
      var details: [String] = []
      switch member.provider {
      case .apple: details.append("Apple")
      case .google: details.append("Google")
      case .magicCode: details.append("Email code")
      case .guest: details.append("Guest")
      case .refreshToken: details.append("Stored sign-in")
      case nil: break
      }
      if member.userID == session.userID {
        details.append("This device")
      }
      return details.joined(separator: " · ")
    }

    private func linkProviderButtonTapped(_ provider: AuthProvider) {
      auth.linkAnotherSignIn(
        provider,
        deviceName: Self.linkingDeviceName,
        onLinked: { link in
          message = "\(providerName(provider.id)) is linked to this account."
          postLinked(link, providerID: provider.id)
        },
        onFailure: { error in
          postLinkFailed(error, providerID: provider.id)
        }
      )
    }

    private func sendLinkCodeButtonTapped() {
      linkCode = ""
      auth.sendLinkMagicCode(
        email: linkEmail,
        onFailure: { error in
          postLinkFailed(error, providerID: .magicCode)
        }
      )
    }

    private func linkCodeSubmitted() {
      guard let email = auth.linkCodeEmail else { return }
      auth.verifyLinkMagicCode(
        email: email,
        code: linkCode,
        deviceName: Self.linkingDeviceName,
        onLinked: { link in
          linkCode = ""
          linkEmail = ""
          message = "The email sign-in is linked to this account."
          postLinked(link, providerID: .magicCode)
        },
        onFailure: { error in
          postLinkFailed(error, providerID: .magicCode)
        }
      )
    }

    private func unlinkButtonConfirmed(_ member: InstantAccountLink.Member) {
      let linkID = auth.accountLink?.id ?? ""
      auth.unlink(
        memberUserID: member.userID,
        onUnlinked: { _ in
          message = "\(linkedMemberTitle(member)) is no longer linked."
          // Hosts log these; never put tokens or email addresses in them.
          NotificationCenter.default.post(
            name: Notification.Name("recipes.auth.link.unlinked"),
            object: nil,
            userInfo: [
              "linkID": linkID,
              "userID": auth.session?.userID ?? "",
              "memberUserID": member.userID,
            ]
          )
        },
        onFailure: { error in
          postLinkFailed(error, providerID: nil)
        }
      )
    }

    private func postLinked(_ link: InstantAccountLink, providerID: InstantAuthProviderID) {
      // Hosts log these; never put tokens or email addresses in them.
      NotificationCenter.default.post(
        name: Notification.Name("recipes.auth.link.linked"),
        object: nil,
        userInfo: [
          "linkID": link.id,
          "userID": auth.session?.userID ?? "",
          "memberUserIDs": link.members.map(\.userID).joined(separator: ","),
          "providerID": providerID.rawValue,
        ]
      )
    }

    private func postLinkFailed(_ error: InstantError, providerID: InstantAuthProviderID?) {
      NotificationCenter.default.post(
        name: Notification.Name("recipes.auth.link.failed"),
        object: nil,
        userInfo: [
          "providerID": providerID?.rawValue ?? "",
          "userID": auth.session?.userID ?? "",
          "linkID": auth.accountLink?.id ?? "",
          "code": error.code.rawValue,
          "operation": error.operation,
          // An auth message can name the email address a sign-in used.
          "error": Self.redactingEmailAddresses(error.message),
        ]
      )
    }

    /// `text` with every email address replaced by `<email>`, for notifications hosts log.
    static func redactingEmailAddresses(_ text: String) -> String {
      text.replacingOccurrences(
        of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        with: "<email>",
        options: .regularExpression
      )
    }

    /// The device kind written into the labels of the identities this device links.
    private static var linkingDeviceName: String? {
      #if os(macOS) || targetEnvironment(macCatalyst)
        return "Mac"
      #elseif canImport(UIKit) && !os(watchOS)
        return UIDevice.current.model
      #else
        return nil
      #endif
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

    private func providerButtonTapped(_ provider: AuthProvider) {
      // Hosts (Recipes Tailnet logger) observe these for automatic diagnosis.
      NotificationCenter.default.post(
        name: Notification.Name("recipes.auth.provider.tapped"),
        object: nil,
        userInfo: [
          "providerID": provider.id.rawValue,
          "clientName": provider.clientName ?? "",
        ]
      )
      auth.signIn(
        provider,
        onSignedIn: { event in
          message = signedInMessage(event)
          NotificationCenter.default.post(
            name: Notification.Name("recipes.auth.provider.signedIn"),
            object: nil,
            userInfo: [
              "providerID": provider.id.rawValue,
              "userID": event.session.userID,
              "transition": String(describing: event.identityTransition),
            ]
          )
        },
        onFailure: { error in
          message = error.description
          NotificationCenter.default.post(
            name: Notification.Name("recipes.auth.provider.failed"),
            object: nil,
            userInfo: [
              "providerID": provider.id.rawValue,
              "clientName": provider.clientName ?? "",
              "error": error.description,
              "code": error.code.rawValue,
              "operation": error.operation,
            ]
          )
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
