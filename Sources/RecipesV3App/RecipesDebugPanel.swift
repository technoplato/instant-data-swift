import Dependencies
import InstantSwiftData
import LinkedInfiniteV3App
import SwiftUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

/// Floating performance/debug panel for recipes-v3 (Scribe build-debug overlay ideas).
///
/// Shows live memory footprint, peak, threads, and a scrollable newest-first log
/// fed by InstantDiagnostics + Linked Infinite durable events. Default expanded
/// so multi‑GB idle footprints are impossible to miss.
@MainActor
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct RecipesDebugPanel: View {
  public enum Presentation: String, CaseIterable, Identifiable {
    case hidden
    case collapsed
    case expanded

    public var id: String { rawValue }
  }

  @ObservedObject private var ring = RecipesDebugLogRing.shared
  @State private var presentation: Presentation
  @State private var didCopy = false
  @State private var wipeMessage = ""
  @State private var isRestarting = false
  @State private var dragTranslation: CGSize = .zero
  @State private var origin = CGPoint(x: 16, y: 16)

  private let recipeLabel: String
  private let isLive: Bool
  private let appID: String
  /// Bootstrapped client — never read `@Dependency(\.defaultInstantSwiftData)` here.
  /// Accessing that key before bootstrap caches the unimplemented live value forever.
  private let client: InstantSwiftDataClient?
  private let sampleIntervalSeconds: Double = 2

  public init(
    recipeLabel: String,
    isLive: Bool,
    appID: String = "",
    client: InstantSwiftDataClient? = nil,
    initialPresentation: Presentation = .expanded
  ) {
    self.recipeLabel = recipeLabel
    self.isLive = isLive
    self.appID = appID
    self.client = client
    _presentation = State(initialValue: initialPresentation)
  }

  public var body: some View {
    #if os(watchOS) || os(tvOS)
      EmptyView()
    #else
      GeometryReader { geometry in
        ZStack(alignment: .topLeading) {
          if presentation != .hidden {
            panel
              .offset(liveOffset(in: geometry.size))
              .gesture(dragGesture(in: geometry.size))
              .animation(.snappy(duration: 0.18), value: presentation)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .allowsHitTesting(presentation != .hidden)
      .task {
        RecipesDebugLogRing.shared.installDiagnosticsBridgeIfNeeded()
        while !Task.isCancelled {
          ring.recordMetricsSample()
          if let client {
            await ring.refreshFailedOutbox(using: client)
          }
          try? await Task.sleep(for: .seconds(sampleIntervalSeconds))
        }
      }
    #endif
  }

  @ViewBuilder
  private var panel: some View {
    switch presentation {
    case .hidden:
      EmptyView()
    case .collapsed:
      collapsedChip
    case .expanded:
      expandedPanel
    }
  }

  private var collapsedChip: some View {
    HStack(spacing: 8) {
      Image(systemName: "line.3.horizontal")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      Text(collapsedLabel)
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .lineLimit(1)
      Button {
        presentation = .expanded
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.plain)
      Button {
        presentation = .hidden
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(panelBackground)
    .clipShape(Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    .padding(12)
  }

  private var expandedPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.secondary)
        Text("Recipes Debug")
          .font(.system(.caption, design: .monospaced, weight: .bold))
        Spacer(minLength: 8)
        Button { presentation = .collapsed } label: {
          Image(systemName: "arrow.down.right.and.arrow.up.left")
        }
        .buttonStyle(.plain)
        Button { presentation = .hidden } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
      }

      metricsBlock
      sparkline
      outboxBlock
      logBlock

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Button {
            copySummary()
          } label: {
            Label(didCopy ? "Copied" : "Copy all", systemImage: didCopy ? "checkmark" : "doc.on.doc")
              .font(.system(.caption2, design: .monospaced, weight: .semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button {
            ring.clearLogs()
          } label: {
            Label("Clear logs", systemImage: "trash")
              .font(.system(.caption2, design: .monospaced, weight: .semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button {
            openLogPaths()
          } label: {
            Label("Reveal logs", systemImage: "folder")
              .font(.system(.caption2, design: .monospaced, weight: .semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        HStack {
          Button(role: .destructive) {
            wipeLocalDatabaseAndRestart()
          } label: {
            Label("Wipe local DB + restart", systemImage: "arrow.clockwise.circle")
              .font(.system(.caption2, design: .monospaced, weight: .semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(appID.isEmpty || isRestarting)

          Button {
            Task {
              guard let client else { return }
              await ring.refreshFailedOutbox(using: client)
            }
          } label: {
            Label("Refresh outbox", systemImage: "arrow.clockwise")
              .font(.system(.caption2, design: .monospaced, weight: .semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(client == nil)
        }

        if !wipeMessage.isEmpty {
          Text(wipeMessage)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(12)
    .frame(width: 400, alignment: .leading)
    .background(panelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(memoryWarningColor.opacity(0.55), lineWidth: 1.5)
    )
    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    .padding(12)
  }

  private var metricsBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      row("Recipe", recipeLabel)
      row("Live", isLive ? "yes" : "local-only")
      row("PID", "\(ProcessInfo.processInfo.processIdentifier)")
      if let m = ring.latestMetrics {
        row("Footprint", RecipesProcessMetricsProbe.formatBytes(m.physicalFootprintBytes))
        row("Resident", RecipesProcessMetricsProbe.formatBytes(m.residentBytes))
        // VSZ is virtual address space (dyld/shared cache/guards), not RAM.
        // Gate memory work on Footprint/Resident — Jetsam uses physical footprint.
        row(
          "VSZ (not RAM)",
          RecipesProcessMetricsProbe.formatBytes(m.virtualBytes)
        )
        row("Threads", "\(m.threadCount)")
      } else {
        row("Footprint", "sampling…")
      }
      row("Peak footprint", RecipesProcessMetricsProbe.formatBytes(ring.peakFootprintBytes))
      Text("VSZ hundreds of GB is normal on Apple Silicon; Jetsam uses Footprint.")
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if isMemoryWarning {
        Text("⚠ Footprint over 1 GB — library materialization / paging suspect")
          .font(.system(.caption2, design: .monospaced, weight: .bold))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var sparkline: some View {
    let history = ring.metricsHistory
    return VStack(alignment: .leading, spacing: 4) {
      Text("Memory (2s samples)")
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(.secondary)
      if history.count >= 2 {
        GeometryReader { geo in
          let maxMB = max(history.map(\.megabytes).max() ?? 1, 1)
          Path { path in
            for (index, sample) in history.enumerated() {
              let x = geo.size.width * CGFloat(index) / CGFloat(max(history.count - 1, 1))
              let y = geo.size.height * (1 - CGFloat(sample.megabytes / maxMB))
              if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
              } else {
                path.addLine(to: CGPoint(x: x, y: y))
              }
            }
          }
          .stroke(memoryWarningColor, lineWidth: 1.5)
        }
        .frame(height: 56)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        Text("Collecting samples…")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
      }
    }
  }

  private var outboxBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Failed outbox (\(ring.failedOutboxRows.count))")
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(
        """
        legacy-unknown-isolated = old failed write without overlay metadata. \
        Isolated so live sync continues; wipe DB for a clean start.
        """
      )
      .font(.system(size: 9, design: .monospaced))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let error = ring.outboxRefreshError {
        Text(error)
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.red)
      } else if ring.failedOutboxRows.isEmpty {
        Text("No failed mutations")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ring.failedOutboxRows.prefix(20)) { row in
              VStack(alignment: .leading, spacing: 2) {
                Text(row.id)
                  .font(.system(.caption2, design: .monospaced, weight: .bold))
                  .textSelection(.enabled)
                  .foregroundStyle(row.isLegacyUnknownOverlay ? .orange : .red)
                Text(row.status + (row.isLegacyUnknownOverlay ? " · legacy-unknown" : ""))
                  .font(.system(size: 9, design: .monospaced))
                  .foregroundStyle(.secondary)
                Text(row.plainEnglish)
                  .font(.system(size: 9, design: .monospaced))
                  .foregroundStyle(.primary)
                  .fixedSize(horizontal: false, vertical: true)
                Text(row.failureMessage)
                  .font(.system(size: 9, design: .monospaced))
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
                  .lineLimit(4)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .frame(height: min(CGFloat(ring.failedOutboxRows.count) * 72, 160))
        .padding(6)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }

  private var logBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Logs (newest first · InstantDiagnostics + Linked Infinite)")
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(ring.entries.prefix(120)) { entry in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(entry.level) · \(entry.category)/\(entry.name)")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(levelColor(entry.level))
              Text(entry.message)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
              if !entry.metadataSummary.isEmpty {
                Text(entry.metadataSummary)
                  .font(.system(size: 9, design: .monospaced))
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
                  .lineLimit(3)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
          }
        }
      }
      .frame(height: 220)
      .padding(6)
      .background(Color.black.opacity(0.22))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(label)
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 72, alignment: .leading)
      Text(value)
        .font(.system(.caption2, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var collapsedLabel: String {
    let footprint =
      ring.latestMetrics.map {
        RecipesProcessMetricsProbe.formatBytes($0.physicalFootprintBytes)
      } ?? "—"
    return "\(recipeLabel) · \(footprint) · peak \(RecipesProcessMetricsProbe.formatBytes(ring.peakFootprintBytes))"
  }

  private var isMemoryWarning: Bool {
    ring.peakFootprintBytes >= 1_073_741_824
      || (ring.latestMetrics?.physicalFootprintBytes ?? 0) >= 1_073_741_824
  }

  private var memoryWarningColor: Color {
    isMemoryWarning ? .red : .cyan
  }

  private func levelColor(_ level: String) -> Color {
    switch level.lowercased() {
    case "error", "critical": return .red
    case "warning": return .orange
    case "notice": return .yellow
    default: return .secondary
    }
  }

  private var panelBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(.ultraThinMaterial)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.black.opacity(0.55))
      }
  }

  private func liveOffset(in container: CGSize) -> CGSize {
    let panelW: CGFloat = presentation == .expanded ? 404 : 280
    let panelH: CGFloat = presentation == .expanded ? 520 : 56
    let x = min(max(8, origin.x + dragTranslation.width), max(8, container.width - panelW))
    let y = min(max(8, origin.y + dragTranslation.height), max(8, container.height - panelH))
    return CGSize(width: x, height: y)
  }

  private func dragGesture(in container: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        dragTranslation = value.translation
      }
      .onEnded { value in
        let panelW: CGFloat = presentation == .expanded ? 404 : 280
        let panelH: CGFloat = presentation == .expanded ? 520 : 56
        let next = CGPoint(
          x: origin.x + value.translation.width,
          y: origin.y + value.translation.height
        )
        origin = CGPoint(
          x: min(max(8, next.x), max(8, container.width - panelW)),
          y: min(max(8, next.y), max(8, container.height - panelH))
        )
        dragTranslation = .zero
      }
  }

  private func copySummary() {
    let text = ring.copyableSummary(recipeLabel: recipeLabel)
    #if os(macOS)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    #elseif os(iOS) || os(visionOS)
      UIPasteboard.general.string = text
    #endif
    didCopy = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      didCopy = false
    }
  }

  private func openLogPaths() {
    #if os(macOS)
      NSWorkspace.shared.activateFileViewerSelecting([
        URL(fileURLWithPath: LinkedInfiniteDurableLog.path),
        FileManager.default.temporaryDirectory
          .appendingPathComponent("recipes-instant-swift-data.jsonl"),
      ])
    #endif
  }

  private func wipeLocalDatabaseAndRestart() {
    guard !appID.isEmpty else {
      wipeMessage = "No app id — cannot wipe."
      return
    }
    guard !isRestarting else { return }
    isRestarting = true
    wipeMessage = "Closing Instant, wiping local store, restarting…"

    Task { @MainActor in
      // Release the live connection so SQLite files unlock before delete.
      if let client {
        do {
          _ = try await client.closeConnection()
        } catch {
          ring.append(
            level: "warning",
            category: "recipes-debug",
            name: "local-cache.close-before-wipe-failed",
            message: String(describing: error),
            metadata: ["appID": appID]
          )
        }
      }

      do {
        let path = try RecipesDebugLogRing.wipeLocalRecipesCache(appID: appID)
        wipeMessage = "Wiped \(path.lastPathComponent). Restarting example…"
        ring.append(
          level: "warning",
          category: "recipes-debug",
          name: "local-cache.wiped",
          message: "Local Instant SQLite removed; restarting the example.",
          metadata: ["appID": appID, "path": path.path]
        )
        // Brief beat so the panel log flushes / user can see the message.
        try? await Task.sleep(for: .milliseconds(400))
        restartExampleProcess()
      } catch {
        isRestarting = false
        wipeMessage = "Wipe failed: \(error)"
      }
    }
  }

  /// Relaunches this recipes host with the same CLI args (e.g. `--recipe auth`), then exits.
  private func restartExampleProcess() {
    #if os(macOS)
      let preservedArgs = Array(ProcessInfo.processInfo.arguments.dropFirst())
      let bundleURL = Bundle.main.bundleURL

      if bundleURL.pathExtension == "app" {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = preservedArgs
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) {
          _,
          error in
          DispatchQueue.main.async {
            if let error {
              self.wipeMessage = "Restart launch failed: \(error.localizedDescription). Quitting."
              self.ring.append(
                level: "error",
                category: "recipes-debug",
                name: "local-cache.restart-failed",
                message: String(describing: error),
                metadata: ["appID": self.appID]
              )
            }
            NSApplication.shared.terminate(nil)
          }
        }
        return
      }

      // SwiftPM `recipes-v3` executable (no .app wrapper).
      do {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = preservedArgs
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        exit(0)
      } catch {
        wipeMessage = "Restart failed: \(error). Quitting."
        ring.append(
          level: "error",
          category: "recipes-debug",
          name: "local-cache.restart-failed",
          message: String(describing: error),
          metadata: ["appID": appID]
        )
        NSApplication.shared.terminate(nil)
      }
    #elseif os(iOS) || os(visionOS)
      // iOS has no public “relaunch self”. Open our URL scheme so SpringBoard can
      // re-activate the app, then exit so the next cold start sees the empty store.
      let restartURL =
        URL(string: "instant-recipes-v3://restart")
        ?? URL(string: "instant-recipes-v3://")
      if let restartURL {
        UIApplication.shared.open(restartURL, options: [:]) { _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(0)
          }
        }
      } else {
        exit(0)
      }
    #else
      exit(0)
    #endif
  }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension View {
  /// Floats the recipes performance/debug panel above content.
  public func recipesDebugPanel(
    recipeLabel: String,
    isLive: Bool,
    appID: String = "",
    client: InstantSwiftDataClient? = nil,
    initialPresentation: RecipesDebugPanel.Presentation = .expanded
  ) -> some View {
    #if os(watchOS) || os(tvOS)
      self
    #else
      ZStack {
        self
        RecipesDebugPanel(
          recipeLabel: recipeLabel,
          isLive: isLive,
          appID: appID,
          client: client,
          initialPresentation: initialPresentation
        )
      }
    #endif
  }
}
