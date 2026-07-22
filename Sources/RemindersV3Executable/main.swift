import Foundation
import InstantSwiftData
import RemindersV3App
import SwiftUI

#if os(macOS)
  import AppKit

  @MainActor
  private final class RemindersV3ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var firstResponderTypes: [Int: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
      NSApplication.shared.setActivationPolicy(.regular)
      recordApplicationState(event: "application.finished-launching")
      let center = NotificationCenter.default
      center.addObserver(
        self,
        selector: #selector(windowDidBecomeKey(_:)),
        name: NSWindow.didBecomeKeyNotification,
        object: nil
      )
      center.addObserver(
        self,
        selector: #selector(windowDidResignKey(_:)),
        name: NSWindow.didResignKeyNotification,
        object: nil
      )
      center.addObserver(
        self,
        selector: #selector(windowFirstResponderChanged(_:)),
        name: NSWindow.didUpdateNotification,
        object: nil
      )
      DispatchQueue.main.async {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.canBecomeKey {
          window.makeKeyAndOrderFront(nil)
        }
        self.recordApplicationState(event: "application.activation-requested")
      }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
      recordApplicationState(event: "application.became-active")
    }

    func applicationDidResignActive(_ notification: Notification) {
      recordApplicationState(event: "application.resigned-active")
    }

    func applicationWillTerminate(_ notification: Notification) {
      recordApplicationState(event: "application.will-terminate")
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
      recordWindow(notification.object as? NSWindow, event: "window.became-key")
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
      recordWindow(notification.object as? NSWindow, event: "window.resigned-key")
    }

    @objc private func windowFirstResponderChanged(_ notification: Notification) {
      guard let window = notification.object as? NSWindow, window.isKeyWindow else { return }
      let responderType = window.firstResponder.map { String(reflecting: type(of: $0)) } ?? "none"
      guard firstResponderTypes[window.windowNumber] != responderType else { return }
      firstResponderTypes[window.windowNumber] = responderType
      recordWindow(window, event: "window.updated")
    }

    private func recordApplicationState(event: String) {
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "reminders-v3",
        category: "focus",
        event: event,
        message: "Reminders application activation changed.",
        metadata: [
          "isActive": String(NSApplication.shared.isActive),
          "keyWindowNumber": NSApplication.shared.keyWindow.map { String($0.windowNumber) }
            ?? "none",
          "mainWindowNumber": NSApplication.shared.mainWindow.map { String($0.windowNumber) }
            ?? "none",
          "windowCount": String(NSApplication.shared.windows.count),
        ]
      )
    }

    private func recordWindow(_ window: NSWindow?, event: String) {
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "reminders-v3",
        category: "focus",
        event: event,
        message: "Reminders window focus changed.",
        metadata: [
          "windowNumber": window.map { String($0.windowNumber) } ?? "none",
          "isKeyWindow": String(window?.isKeyWindow == true),
          "isMainWindow": String(window?.isMainWindow == true),
          "isApplicationActive": String(NSApplication.shared.isActive),
          "firstResponderType": window?.firstResponder.map { String(reflecting: type(of: $0)) }
            ?? "none",
        ]
      )
    }
  }
#endif

@main
struct RemindersV3Executable: App {
  @StateObject private var bootstrap: RemindersV3BootstrapModel
  @Environment(\.scenePhase) private var scenePhase

  #if os(macOS)
    @NSApplicationDelegateAdaptor(RemindersV3ApplicationDelegate.self)
    private var applicationDelegate
  #endif

  init() {
    let environment = ProcessInfo.processInfo.environment
    let configuredDiagnostics = InstantDiagnosticsConfiguration.environment(environment)
    let logURL =
      environment["REMINDERS_V3_LOG_PATH"]
      .flatMap { path in
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
      }
      ?? configuredDiagnostics.fileURL
      ?? InstantDiagnostics.defaultLogFileURL(processName: "reminders-v3")
    InstantDiagnostics.shared.configure(
      InstantDiagnosticsConfiguration(
        fileURL: logURL,
        minimumLevel: environment["INSTANT_SWIFT_DATA_LOG_LEVEL"] == nil
          ? .trace
          : configuredDiagnostics.minimumLevel
      )
    )
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "reminders-v3",
      category: "lifecycle",
      event: "process.started",
      message: "Reminders process started.",
      metadata: [
        "logPath": logURL.path,
        "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
      ]
    )
    _bootstrap = StateObject(
      wrappedValue: RemindersV3BootstrapModel(configuration: .environment(environment))
    )
  }

  var body: some Scene {
    WindowGroup {
      RemindersV3BootstrapScreen(model: bootstrap)
        .onChange(of: scenePhase, initial: true) { _, phase in
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "reminders-v3",
            category: "lifecycle",
            event: "scene.phase-changed",
            message: "Reminders scene phase changed.",
            metadata: ["phase": String(describing: phase)]
          )
        }
    }
  }
}
