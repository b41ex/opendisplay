import XCTest
import Combine

final class ReceiverPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "ReceiverPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testMissingNameUsesComputerNameWithoutWritingDefaults() {
        let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        XCTAssertEqual(preferences.receiverName, "Test Mac")
        XCTAssertEqual(preferences.serviceName, "Test Mac")
        XCTAssertFalse(preferences.showAnalytics)
        XCTAssertNil(defaults.object(forKey: "receiverName"))
    }

    func testExistingPreferencesKeepTheirKeysAndValues() {
        defaults.set("Studio", forKey: "receiverName")
        defaults.set(true, forKey: "showAnalytics")
        let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        XCTAssertEqual(preferences.receiverName, "Studio")
        XCTAssertEqual(preferences.serviceName, "Studio")
        XCTAssertTrue(preferences.showAnalytics)
    }

    func testEmptyNameSurvivesRelaunchAndUsesFallbackForService() {
        let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        preferences.receiverName = ""
        let relaunched = ReceiverPreferences(defaults: defaults, fallbackName: "Renamed Mac")
        XCTAssertEqual(defaults.string(forKey: "receiverName"), "")
        XCTAssertEqual(relaunched.receiverName, "")
        XCTAssertEqual(relaunched.serviceName, "Renamed Mac")
    }

    func testNameAndOverlayChoiceSurviveRelaunchWithoutTrimmingName() {
        let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        preferences.receiverName = "  Studio  "
        preferences.showAnalytics = true
        let relaunched = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        XCTAssertEqual(relaunched.serviceName, "  Studio  ")
        XCTAssertTrue(relaunched.showAnalytics)
        preferences.showAnalytics = false
        XCTAssertFalse(ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac").showAnalytics)
    }

    func testBothPreferencesPublishChanges() {
        let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
        var names: [String] = []
        var overlays: [Bool] = []
        let nameSubscription = preferences.$receiverName.sink { names.append($0) }
        let overlaySubscription = preferences.$showAnalytics.sink { overlays.append($0) }
        preferences.receiverName = "Studio"
        preferences.showAnalytics = true
        XCTAssertEqual(names, ["Test Mac", "Studio"])
        XCTAssertEqual(overlays, [false, true])
        withExtendedLifetime((nameSubscription, overlaySubscription)) {}
    }

    func testPreferencesDoNotRetainThemselves() {
        weak var reference: ReceiverPreferences?
        autoreleasepool {
            let preferences = ReceiverPreferences(defaults: defaults, fallbackName: "Test Mac")
            reference = preferences
            preferences.receiverName = "Studio"
            preferences.showAnalytics = true
        }
        XCTAssertNil(reference)
    }
}
