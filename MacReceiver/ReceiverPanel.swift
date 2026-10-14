import SwiftUI

// MARK: - Receiver panel (issues #82/#17)

/// The receiver-mode sections of the panel: live status, the advertised
/// name, and how-to copy. Lives inside the shared grouped Form.
struct ReceiverSections: View {
    @ObservedObject var controller: ReceiverController
    @ObservedObject private var preferences = ReceiverPreferences.shared

    var body: some View {
        // The receiver exists only while receiver mode is on; observed in a
        // subview because nested ObservableObjects don't republish.
        if let receiver = controller.receiver {
            ReceiverStatusSection(receiver: receiver, controller: controller)
        }

        // The header/footer overload is available in SwiftUI 1 (Catalina).
        // https://developer.apple.com/documentation/swiftui/section/init(header:footer:content:)
        Section(header: Text("Name"),
                footer: Text("How this Mac appears in the other Mac's Devices list.")) {
            ReceiverNameField(preferences: preferences) { controller.setAdvertisedName($0) }
        }

        Section(footer: Text("FPS, bitrate, frame timing, and latency graphs at the bottom of the video window while streaming — the same HUD the iPhone app has.")) {
            Toggle("Performance overlay", isOn: $preferences.showAnalytics)
        }

        Section(header: Text("How to connect")) {
            ReceiverLabel("Install and open OpenDisplay on the Mac whose screen you want to extend.",
                          systemImage: "macbook.and.macbook")
            ReceiverLabel("With both Macs on the same network, this Mac appears in its Devices list — click Connect there.",
                          systemImage: "wifi")
            ReceiverLabel("The stream opens in a window here — use the green traffic light for full screen.",
                          systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .font(.subheadline)
    }
}

/// Live state of the running receiver: connection, stream format, and any
/// compatibility signal from the connected Mac.
private struct ReceiverStatusSection: View {
    @ObservedObject var receiver: StreamReceiver
    let controller: ReceiverController

    var body: some View {
        Section(header: Text("This Mac as a display")) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(receiver.connected ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(receiver.connected ? "Connected" : "Waiting for a computer…")
                    // The port matters on a Mac (firewall prompts), so the
                    // idle caption names it instead of repeating the status.
                    Text(receiver.connected || receiver.status != "Ready to connect"
                         ? receiver.status : "Listening on port 9000")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if controller.streaming {
                    Button("Show Window") { controller.showWindow() }
                        .controlSize(.small)
                        .receiverHelp("Bring the video window back if you closed it — the stream keeps running either way.")
                }
            }
            if receiver.videoSize != .zero {
                // Not LabeledContent: that is macOS 13, the app runs on 12.
                HStack {
                    Text("Stream")
                    Spacer()
                    Text("\(Int(receiver.videoSize.width))×\(Int(receiver.videoSize.height)) @ \(receiver.fps) fps")
                        .foregroundColor(.secondary)
                }
            }
            if let message = peerMessage {
                ReceiverLabel(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    /// Compatibility copy from the sender (issue #132) — surfaced inline;
    /// the Mac app has Sparkle, so there is no blocking gate like on iOS.
    private var peerMessage: String? {
        switch receiver.peerSignal {
        case let .updateReceiver(message, _): return message
        case let .updateMac(message): return message
        case nil: return nil
        }
    }
}

/// The advertised-name editor — kept out of any high-frequency observed
/// object so streaming updates can't rebuild it mid-edit (same reasoning as
/// the iOS DeviceNameField).
private struct ReceiverNameField: View {
    @ObservedObject var preferences: ReceiverPreferences
    let onChange: (String) -> Void

    var body: some View {
        // Binding setters work on Catalina and announce each edit immediately.
        // https://developer.apple.com/documentation/swiftui/binding/init(get:set:)
        TextField("Name", text: Binding(get: { preferences.receiverName }, set: onChange))
    }
}

/// SF Symbols and Label start on macOS 11; keep the full instruction on 10.15.
private struct ReceiverLabel: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        if #available(macOS 11, *) {
            Label(text, systemImage: systemImage)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("•").accessibility(hidden: true)
                Text(text)
            }
        }
    }
}
