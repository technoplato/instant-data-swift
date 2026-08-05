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
  @State private var dragTranslation: CGSize = .zero
  @State private var origin = CGPoint(x: 16, y: 16)

  private let recipeLabel: String
  private let isLive: Bool
  private let sampleIntervalSeconds: Double = 2

  public init(
    recipeLabel: String,
    isLive: Bool,
    initialPresentation: Presentation = .expanded
  ) {
    self.recipeLabel = recipeLabel
    self.isLive = isLive
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
      logBlock

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
          openLogPaths()
        } label: {
          Label("Reveal logs", systemImage: "folder")
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Spacer(minLength: 0)
      }
    }
    .padding(12)
    .frame(width: 380, alignment: .leading)
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
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension View {
  /// Floats the recipes performance/debug panel above content.
  public func recipesDebugPanel(
    recipeLabel: String,
    isLive: Bool,
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
          initialPresentation: initialPresentation
        )
      }
    #endif
  }
}
