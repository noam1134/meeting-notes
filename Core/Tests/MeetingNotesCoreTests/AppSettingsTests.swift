import XCTest
@testable import MeetingNotesCore

final class AppSettingsTests: XCTestCase {
    var defaults: UserDefaults!
    let suite = "mn-settings-tests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLoadReturnsDefaultsWhenUnset() {
        XCTAssertEqual(AppSettings.load(from: defaults).categories,
                       ["Trello task", "Decision", "Question", "FYI"])
    }

    func testSaveThenLoadRoundTrips() {
        AppSettings(categories: ["A", "B"]).save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults).categories, ["A", "B"])
    }

    func testEmptySavedListFallsBackToDefaults() {
        AppSettings(categories: []).save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults).categories,
                       AppSettings.defaultCategories)
    }

    func testMorningReminderDefaultsToEnabledWhenUnset() {
        XCTAssertEqual(AppSettings.load(from: defaults).morningReminderEnabled, true)
    }

    func testMorningReminderSaveThenLoadRoundTrips() {
        AppSettings(categories: ["A"], morningReminderEnabled: false).save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults).morningReminderEnabled, false)
    }
}
