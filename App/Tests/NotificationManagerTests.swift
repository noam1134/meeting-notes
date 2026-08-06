import XCTest
@testable import MeetingNotes

// Covers the pure parts of NotificationManager (task P3). The
// UNUserNotificationCenter side effects (requestAuthorization/add/remove)
// aren't exercised here — they require a live, permissioned notification
// center and are covered by manual smoke instead.
final class NotificationManagerTests: XCTestCase {
    func testReminderBodySingular() {
        XCTAssertEqual(NotificationManager.reminderBody(pendingCount: 1),
                       "1 meeting session waiting for processing")
    }

    func testReminderBodyPlural() {
        XCTAssertEqual(NotificationManager.reminderBody(pendingCount: 3),
                       "3 meeting sessions waiting for processing")
    }

    func testReminderBodyZero() {
        XCTAssertEqual(NotificationManager.reminderBody(pendingCount: 0),
                       "0 meeting sessions waiting for processing")
    }

    func testMorningTriggerFiresAt9AMDaily() {
        let trigger = NotificationManager.morningTrigger()
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertTrue(trigger.repeats)
    }
}
