// Performance overlay (Steam-Deck style, opt-in). Compiled into BOTH
// targets: the iOS receiver shows it over the stream, and the Mac app's
// receiver-mode video window reuses it unchanged. Pure SwiftUI — keep it
// UIKit/AppKit-free. The numbers come from PerfStats (StreamReceiver).

import SwiftUI

// MARK: - Performance overlay (Steam-Deck style, opt-in via Settings)

struct PerfOverlay: View {
    let stats: PerfStats
    let videoSize: CGSize

    var body: some View {
        VStack(spacing: 8) {
            // Metrics wrap onto extra rows when the width doesn't fit —
            // portrait iPhone is ~390pt, far less than one full row.
            MetricsRow {
                // Transport badge — the question "is this cable or WiFi?"
                Text(stats.transport)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(stats.transport == "USB" || stats.transport == "Cable"
                                    ? Color.green.opacity(0.35)
                                : stats.transport == "WiFi" ? Color.blue.opacity(0.4)
                                : Color.gray.opacity(0.3)))
                    .foregroundColor(.white)
                if !stats.codec.isEmpty {
                    Text(stats.codec)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .foregroundColor(.white)
                }
                // Frame rate is the number people know; lead with it.
                VStack(spacing: 1) {
                    Text("\(stats.fps)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(stats.fps >= 50 ? Color.green
                                         : stats.fps >= 28 ? Color.yellow : Color.orange)
                    Text("FPS")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                metric("hitches", "\(stats.hitches)")

                if stats.e2eP50 > 0 {
                    metric("latency", String(format: "%.0f ms", stats.e2eP50))
                    metric("p95", String(format: "%.0f ms", stats.e2eP95))
                    metric("encode", String(format: "%.0f ms", stats.encodeP50))
                }
                if stats.decodeP50 > 0 {
                    metric("decode", String(format: "%.1f ms", stats.decodeP50))
                }
                if stats.photonP50 > 0 {
                    // True capture→glass latency (Metal presented handler) —
                    // the only number that includes display vsync.
                    metric("photon", String(format: "%.0f ms", stats.photonP50))
                }
                if stats.inputP50 > 0 {
                    // touch→CGEvent on the Mac; full touch-to-photon adds
                    // the render+capture wait and one e2e on top.
                    metric("input", String(format: "%.0f ms", stats.inputP50))
                }
                metric("rtt", String(format: "%.0f ms", stats.rttMs))
                if stats.capFps > 0 {
                    metric("Mac cap", "\(stats.capFps)")
                }
                metric("Mbit/s", String(format: "%.1f", stats.mbps))
                metric("stalls", "\(stats.stalls)")
                metric("cursor/s", "\(stats.cursorPerSec)")
                if stats.cursorLost > 0 {
                    metric("cursor lost", "\(stats.cursorLost)")
                }
                metric("enc↓", "\(stats.macEncDrops)")
                metric("net↓", "\(stats.macNetDrops)")
                if stats.macPending > 0 {
                    metric("queue", "\(stats.macPending)")
                }
                if stats.decodeFlushes > 0 {
                    metric("flushes", "\(stats.decodeFlushes)")
                }
                metric("res", "\(Int(videoSize.width))×\(Int(videoSize.height))")
            }
            // Two graphs side by side where they fit (landscape), stacked
            // where they don't (portrait). Without ViewThatFits (iOS 15,
            // macOS 12) always stack: two 220pt graphs never fit a 320pt or
            // 375pt phone, and stacking costs nothing on a Mac window.
            if #available(iOS 16, macOS 13, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { graphs }
                    VStack(spacing: 8) { graphs }
                }
            } else {
                VStack(spacing: 8) { graphs }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var graphs: some View {
        graph("latency ms (cap→display)",
              BarGraph(samples: stats.e2eSamples, ceiling: 80,
                       good: 25, warn: 40, reference: nil))
        graph("frame interval ms (line = 60 fps)",
              BarGraph(samples: stats.samples, ceiling: 60,
                       good: 25, warn: 50, reference: 16.7))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func graph(_ label: String, _ content: BarGraph) -> some View {
        VStack(spacing: 2) {
            content.frame(width: 220, height: 38)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

/// Left-aligned wrapping row: children flow onto as many rows as the
/// proposed width requires. Keeps the perf overlay inside the screen in
/// portrait instead of clipping off both edges. `Layout` needs iOS 16 /
/// macOS 13; an adaptive grid handles 11/12 and measured stack rows handle
/// Catalina. All three layouts receive the same complete metric list.
struct MetricsRow: View {
    private let content: () -> [AnyView]
    @State private var width: CGFloat = 0

    init(@MetricsContentBuilder content: @escaping () -> [AnyView]) {
        self.content = content
    }

    var body: some View {
        let items = content()
        if #available(iOS 16, macOS 13, *) {
            FlowLayout(hSpacing: 14, vSpacing: 8) {
                ForEach(items.indices, id: \.self) { items[$0] }
            }
        } else if #available(iOS 14, macOS 11, *) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 14, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { items[$0] }
            }
        } else {
            stackRows(items)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: MetricsWidth.self, value: geometry.size.width)
                })
                .onPreferenceChange(MetricsWidth.self) { width = $0 }
        }
    }

    private func stackRows(_ items: [AnyView]) -> some View {
        let columns = max(1, Int((width + 14) / 78))
        let cellWidth = max(64, (width - CGFloat(columns - 1) * 14) / CGFloat(columns))
        let rows = (items.count + columns - 1) / columns
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .center, spacing: 14) {
                    ForEach((row * columns)..<min((row + 1) * columns, items.count), id: \.self) {
                        items[$0].frame(width: cellWidth, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct MetricsWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Collect individual metrics so SwiftUI 1 can lay them out without private
/// tuple introspection. The HUD items have no local state to erase.
/// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0289-result-builders.md
@resultBuilder
enum MetricsContentBuilder {
    static func buildExpression<Content: View>(_ view: Content) -> [AnyView] { [AnyView(view)] }
    static func buildBlock(_ items: [AnyView]...) -> [AnyView] { items.flatMap { $0 } }
    static func buildOptional(_ items: [AnyView]?) -> [AnyView] { items ?? [] }
}

@available(iOS 16, macOS 13, *)
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 14
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0
        var rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - hSpacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Bar graph over a rolling sample window with green/yellow/red thresholds
/// and an optional reference line (e.g. 16.7 ms = 60 fps).
struct BarGraph: View {
    let samples: [Double]
    let ceiling: Double
    let good: Double
    let warn: Double
    let reference: Double?

    var body: some View {
        // Path/GeometryReader retain the same thresholds and reference line
        // without Canvas (macOS 12). Three paths keep the view tree small.
        // https://developer.apple.com/documentation/swiftui/path
        GeometryReader { geometry in
            ZStack {
                bars(in: geometry.size, band: 0).fill(Color.green.opacity(0.85))
                bars(in: geometry.size, band: 1).fill(Color.yellow.opacity(0.85))
                bars(in: geometry.size, band: 2).fill(Color.red.opacity(0.85))
                if !samples.isEmpty, let reference {
                    Path { path in
                        let y = geometry.size.height - CGFloat(reference / ceiling) * geometry.size.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                }
            }
        }
    }

    private func bars(in size: CGSize, band: Int) -> Path {
        Path { path in
            let barWidth = size.width / CGFloat(max(samples.count, 1))
            for (index, ms) in samples.enumerated() {
                let sampleBand = ms <= good ? 0 : ms <= warn ? 1 : 2
                guard sampleBand == band else { continue }
                let height = CGFloat(min(ms / ceiling, 1)) * size.height
                path.addRect(CGRect(x: CGFloat(index) * barWidth, y: size.height - height,
                                    width: max(barWidth - 0.5, 0.5), height: height))
            }
        }
    }
}

