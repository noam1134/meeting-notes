import XCTest
@testable import MeetingNotes
import MeetingNotesCore

// Covers AppState.pendingSessionCount: sessions with status .pending that
// are NOT the active session (task P3 menu bar badge + morning reminder).
final class AppStatePendingCountTests: XCTestCase {
    var root: URL!
    var store: SessionStore!
    var state: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mn-app-tests-\(UUID().uuidString)")
        store = SessionStore(rootURL: root)
        state = AppState(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testZeroWhenNoSessions() {
        XCTAssertEqual(state.pendingSessionCount, 0)
    }

    func testActiveSessionDoesNotCountEvenThoughStatusIsPending() {
        state.startMeeting(named: "Standup")
        XCTAssertEqual(state.pendingSessionCount, 0)
    }

    func testEndedPendingSessionCounts() {
        state.startMeeting(named: "Standup")
        state.endMeeting()
        XCTAssertEqual(state.pendingSessionCount, 1)
    }

    func testProcessedSessionDoesNotCount() throws {
        state.startMeeting(named: "Standup")
        state.endMeeting()
        let folder = try XCTUnwrap(store.listSessions().compactMap { item -> URL? in
            if case let .readable(_, folder) = item { return folder }
            return nil
        }.first)
        state.setSessionStatus(.processed, in: folder)
        XCTAssertEqual(state.pendingSessionCount, 0)
    }

    func testCountsMultipleEndedPendingSessions() {
        state.startMeeting(named: "One")
        state.endMeeting()
        state.startMeeting(named: "Two")
        state.endMeeting()
        XCTAssertEqual(state.pendingSessionCount, 2)
    }
}
