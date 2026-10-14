import Foundation
import Combine

/// One model shared by the panel and HUD; keeps the existing defaults keys.
/// ObservableObject/Published are available on Catalina:
/// https://developer.apple.com/documentation/combine/observableobject
final class ReceiverPreferences: ObservableObject {
    static let shared = ReceiverPreferences()

    private let defaults: UserDefaults
    private let fallbackName: String

    @Published var receiverName: String {
        didSet { defaults.set(receiverName, forKey: "receiverName") }
    }
    @Published var showAnalytics: Bool {
        didSet { defaults.set(showAnalytics, forKey: "showAnalytics") }
    }

    init(defaults: UserDefaults = .standard,
         fallbackName: String = Host.current().localizedName ?? "Mac") {
        self.defaults = defaults
        self.fallbackName = fallbackName
        receiverName = defaults.string(forKey: "receiverName") ?? fallbackName
        showAnalytics = defaults.bool(forKey: "showAnalytics")
    }

    /// Keep an empty editor value while advertising the computer's name.
    var serviceName: String { receiverName.isEmpty ? fallbackName : receiverName }
}
