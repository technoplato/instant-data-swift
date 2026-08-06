import Foundation
import LinkedInfiniteV3App
import RecipesV3App
import SwiftUI

/// Loads KEY=VALUE pairs from dotenv-style files into the process environment
/// without overwriting keys already set by the shell or Xcode.
///
/// Source of truth for live Instant: `Examples/RecipesV3/.env` (gitignored).
/// On device/Xcode hosts, the same app id is also embedded as `InstantAppID`
/// in Info.plist (from `RecipesV3.local.xcconfig`, written by provision/sync).
enum RecipesV3DotEnv {
  /// Keys that may ship inside the app bundle resource. Admin tokens never do.
  private static let bundleSafeKeys: Set<String> = [
    "INSTANT_APP_ID",
    "INSTANT_RECIPE",
    "INSTANT_APPLE_AUTH_CLIENT_NAME",
    "INSTANT_GOOGLE_AUTH_CLIENT_NAME",
    "INSTANT_OAUTH_REDIRECT_URL",
  ]

  static func load() {
    let fm = FileManager.default
    var candidates: [URL] = []

    if let custom = ProcessInfo.processInfo.environment["RECIPES_V3_ENV_PATH"],
      !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      candidates.append(URL(fileURLWithPath: custom))
    }

    // Bundled copy (APP_ID only) so physical devices get live Instant without
    // a filesystem path to the repo .env.
    if let bundled = Bundle.main.url(forResource: "RecipesV3", withExtension: "env") {
      candidates.append(bundled)
    }
    if let bundled = Bundle.main.url(forResource: "RecipesV3", withExtension: "env", subdirectory: nil) {
      candidates.append(bundled)
    }

    // Package-relative locations when launched via `swift run` from repo root.
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
    candidates.append(cwd.appendingPathComponent("Examples/RecipesV3/.env"))
    candidates.append(cwd.appendingPathComponent(".env"))

    // Absolute private credentials (shared Instant app for recipes).
    candidates.append(
      URL(
        fileURLWithPath:
          "/Users/laptop/Sync/private/credentials/swift-instant-data/recipes-v3.env"
      )
    )

    // Walk up from executable for SPM build trees.
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for _ in 0..<8 {
      candidates.append(dir.appendingPathComponent("Examples/RecipesV3/.env"))
      candidates.append(dir.appendingPathComponent(".env"))
      let parent = dir.deletingLastPathComponent()
      if parent.path == dir.path { break }
      dir = parent
    }

    var loadedFrom: String?
    for url in candidates {
      guard fm.isReadableFile(atPath: url.path) else { continue }
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let fromBundle = url.path.contains(".app/") || url.path.contains("Bundle")
      apply(text, allowOnly: fromBundle ? Self.bundleSafeKeys : nil)
      loadedFrom = url.path
      break
    }

    LinkedInfiniteDurableLog.log(
      "dotenv.load",
      [
        "loadedFrom": loadedFrom ?? "none",
        "hasInstantAppID": !(ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "").isEmpty,
        "appIDPrefix": String(
          (ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "").prefix(8)
        ),
      ]
    )
  }

  private static func apply(_ text: String, allowOnly: Set<String>? = nil) {
    for rawLine in text.split(whereSeparator: \.isNewline) {
      var line = String(rawLine).trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }
      if line.hasPrefix("export ") {
        line = String(line.dropFirst("export ".count))
          .trimmingCharacters(in: .whitespaces)
      }
      guard let eq = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
      var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
      if (value.hasPrefix("\"") && value.hasSuffix("\""))
        || (value.hasPrefix("'") && value.hasSuffix("'"))
      {
        value = String(value.dropFirst().dropLast())
      }
      guard !key.isEmpty else { continue }
      if let allowOnly, !allowOnly.contains(key) { continue }
      // Shell / Xcode wins over file.
      if ProcessInfo.processInfo.environment[key] == nil {
        setenv(key, value, 0)
      }
    }
  }
}

#if os(macOS)
  import AppKit

  /// Makes the SwiftPM `recipes-v3` binary behave like a normal Mac app so
  /// Mission Control / Exposé click-to-focus works.
  @MainActor
  private final class RecipesV3ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
      NSApplication.shared.setActivationPolicy(.regular)
      LinkedInfiniteDurableLog.log(
        "app.finished-launching",
        [
          "activationPolicy": "regular",
          "windowCount": NSApplication.shared.windows.count,
          "processID": ProcessInfo.processInfo.processIdentifier,
          "hasInstantAppID": !(ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "")
            .isEmpty,
          "enablesLiveSyncExpected": !(ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "")
            .isEmpty,
        ]
      )
      DispatchQueue.main.async {
        Self.bringWindowsForward(reason: "did-finish-launching")
      }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
      LinkedInfiniteDurableLog.log(
        "app.became-active",
        [
          "windowCount": NSApplication.shared.windows.count,
          "keyWindow": NSApplication.shared.keyWindow.map { String($0.windowNumber) } ?? "none",
        ]
      )
      Self.bringWindowsForward(reason: "did-become-active")
    }

    func applicationShouldHandleReopen(
      _ sender: NSApplication,
      hasVisibleWindows flag: Bool
    ) -> Bool {
      LinkedInfiniteDurableLog.log(
        "app.should-handle-reopen",
        [
          "hasVisibleWindows": flag,
          "windowCount": NSApplication.shared.windows.count,
        ]
      )
      Self.bringWindowsForward(reason: "should-handle-reopen")
      return true
    }

    static func bringWindowsForward(reason: String) {
      NSApplication.shared.setActivationPolicy(.regular)
      NSApplication.shared.activate(ignoringOtherApps: true)
      var ordered = 0
      for window in NSApplication.shared.windows {
        if window.canBecomeKey || window.canBecomeMain {
          window.makeKeyAndOrderFront(nil)
          ordered += 1
        } else {
          window.orderFrontRegardless()
          ordered += 1
        }
      }
      LinkedInfiniteDurableLog.log(
        "app.bring-windows-forward",
        [
          "reason": reason,
          "orderedCount": ordered,
          "windowCount": NSApplication.shared.windows.count,
          "isActive": NSApplication.shared.isActive,
          "keyWindow": NSApplication.shared.keyWindow.map { String($0.windowNumber) } ?? "none",
        ]
      )
    }
  }
#endif

@main
struct RecipesV3Executable: App {
  @StateObject private var bootstrap: RecipesV3BootstrapModel

  #if os(macOS)
    @NSApplicationDelegateAdaptor(RecipesV3ApplicationDelegate.self)
    private var applicationDelegate
  #endif

  init() {
    RecipesV3DotEnv.load()
    LinkedInfiniteDurableLog.resetSession(reason: "recipes-v3-main-init")
    _bootstrap = StateObject(
      wrappedValue: RecipesV3BootstrapModel(configuration: .environment())
    )
    LinkedInfiniteDurableLog.log(
      "app.configuration",
      [
        "appID": ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "recipes-v3-local",
        "hasAppID": !(ProcessInfo.processInfo.environment["INSTANT_APP_ID"] ?? "").isEmpty,
        "recipe": ProcessInfo.processInfo.environment["INSTANT_RECIPE"] ?? "",
        "persistencePath": ProcessInfo.processInfo.environment["INSTANT_PERSISTENCE_PATH"] ?? "",
      ]
    )
  }

  var body: some Scene {
    WindowGroup {
      RecipesV3BootstrapScreen(model: bootstrap)
        #if os(macOS)
          .onAppear {
            RecipesV3ApplicationDelegate.bringWindowsForward(reason: "root-onAppear")
          }
        #endif
    }
  }
}
