import Foundation
import LinkedInfiniteV3App
import RecipesV3App
import SwiftUI

#if os(macOS)
  import AppKit

  /// Makes the SwiftPM `recipes-v3` binary behave like a normal Mac app so
  /// Mission Control / Exposé click-to-focus works (not a LSUIElement-style
  /// accessory process with orphan windows).
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
  @StateObject private var bootstrap = RecipesV3BootstrapModel(
    configuration: .environment()
  )

  #if os(macOS)
    @NSApplicationDelegateAdaptor(RecipesV3ApplicationDelegate.self)
    private var applicationDelegate
  #endif

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
