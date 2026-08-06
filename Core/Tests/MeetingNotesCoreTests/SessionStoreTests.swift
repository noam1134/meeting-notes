import XCTest
@testable import MeetingNotesCore

final class SessionStoreTests: XCTestCase {
    var root: URL!
    var store: SessionStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mn-tests-\(UUID().uuidString)")
        store = SessionStore(rootURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testStartSessionCreatesFolderAndJSON() throws {
        let folder = try store.startSession(named: "Sprint Planning",
                                            at: date("2026-08-06T07:30:00Z"))
        XCTAssertEqual(folder.lastPathComponent.hasPrefix("2026-08-06-"), true)
        XCTAssertTrue(folder.lastPathComponent.hasSuffix("-sprint-planning"))
        let session = try store.loadSession(in: folder)
        XCTAssertEqual(session.name, "Sprint Planning")
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.status, .pending)
        XCTAssertEqual(session.notes, [])
    }

    func testUnnamedSessionUsesTimestampName() throws {
        let folder = try store.startSession(named: nil, at: date("2026-08-06T07:30:00Z"))
        let session = try store.loadSession(in: folder)
        XCTAssertFalse(session.name.isEmpty)
        XCTAssertFalse(folder.lastPathComponent.hasSuffix("-"))
    }

    func testActiveSessionFolderFindsOpenSession() throws {
        XCTAssertNil(try store.activeSessionFolder())
        let folder = try store.startSession(named: "a")
        XCTAssertEqual(try store.activeSessionFolder(), folder)
        try store.endActiveSession()
        XCTAssertNil(try store.activeSessionFolder())
    }

    func testAddTextNote() throws {
        try store.startSession(named: "a")
        let note = try store.addNote(text: "hello", category: "Decision", imageData: nil)
        XCTAssertNil(note.image)
        let session = try store.loadSession(in: try XCTUnwrap(store.activeSessionFolder()))
        XCTAssertEqual(session.notes, [note])
    }

    func testAddImageNoteWritesSequentialPNGs() throws {
        let folder = try store.startSession(named: "a")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let n1 = try store.addNote(text: "one", category: "FYI", imageData: data)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: data)
        XCTAssertEqual(n1.image, "img-001.png")
        XCTAssertEqual(n2.image, "img-002.png")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-001.png")), data)
    }

    func testAddNoteWithoutActiveSessionThrows() {
        XCTAssertThrowsError(try store.addNote(text: "x", category: "FYI", imageData: nil)) {
            XCTAssertEqual($0 as? SessionStoreError, .noActiveSession)
        }
    }

    // External-edit tolerance: Claude rewrites session.json between our writes.
    func testExternalEditSurvivesNextWrite() throws {
        let folder = try store.startSession(named: "a")
        try store.addNote(text: "one", category: "FYI", imageData: nil)
        var edited = try store.loadSession(in: folder)
        edited.notes[0].status = .processed
        try SessionJSON.encode(edited).write(to: folder.appendingPathComponent("session.json"))
        try store.addNote(text: "two", category: "FYI", imageData: nil)
        let final = try store.loadSession(in: folder)
        XCTAssertEqual(final.notes.count, 2)
        XCTAssertEqual(final.notes[0].status, .processed)   // external edit kept
    }

    func testMalformedJSONListedAsUnreadableAndNeverOverwritten() throws {
        let folder = try store.startSession(named: "bad")
        let jsonURL = folder.appendingPathComponent("session.json")
        try Data("{not json".utf8).write(to: jsonURL)
        let items = store.listSessions()
        XCTAssertEqual(items, [.unreadable(folder: folder)])
        XCTAssertThrowsError(try store.addNote(text: "x", category: "FYI", imageData: nil))
        XCTAssertEqual(try Data(contentsOf: jsonURL), Data("{not json".utf8))  // untouched
    }

    func testStartSessionSameDateDoesNotOverwriteExistingFolder() throws {
        let d = date("2026-08-06T07:30:00Z")
        let folder1 = try store.startSession(named: "a", at: d)
        try store.addNote(text: "keep me", category: "FYI", imageData: nil)
        try store.endActiveSession(at: d)
        let folder2 = try store.startSession(named: "a", at: d)

        XCTAssertNotEqual(folder1, folder2)

        let session1 = try store.loadSession(in: folder1)
        XCTAssertEqual(session1.notes.map(\.text), ["keep me"])
        XCTAssertEqual(session1.endedAt, d)

        let session2 = try store.loadSession(in: folder2)
        XCTAssertEqual(session2.notes, [])
        XCTAssertNil(session2.endedAt)
    }

    func testAddNoteToFolderWorksOnEndedSession() throws {
        let folder = try store.startSession(named: "a")
        try store.addNote(text: "first", category: "FYI", imageData: nil)
        try store.endActiveSession()
        let before = try store.loadSession(in: folder)
        let note = try store.addNote(text: "later", category: "Decision", imageData: nil, to: folder)
        let after = try store.loadSession(in: folder)
        XCTAssertEqual(after.notes.map(\.text), ["first", "later"])
        XCTAssertEqual(after.endedAt, before.endedAt)
        XCTAssertEqual(after.notes.last, note)
    }

    func testAddNoteToFolderWithCorruptSessionThrowsAndLeavesUntouched() throws {
        let folder = try store.startSession(named: "bad")
        let jsonURL = folder.appendingPathComponent("session.json")
        try Data("{not json".utf8).write(to: jsonURL)
        XCTAssertThrowsError(try store.addNote(text: "x", category: "FYI", imageData: nil, to: folder)) {
            XCTAssertEqual($0 as? SessionStoreError, .corruptSession(folder))
        }
        XCTAssertEqual(try Data(contentsOf: jsonURL), Data("{not json".utf8))
    }

    func testAddNoteToFolderImageNumberingContinuesFromExisting() throws {
        let folder = try store.startSession(named: "a")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        try store.addNote(text: "one", category: "FYI", imageData: data)
        let note = try store.addNote(text: "two", category: "FYI", imageData: data, to: folder)
        XCTAssertEqual(note.image, "img-002.png")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-002.png")), data)
    }

    func testListSessionsNewestFirst() throws {
        try store.startSession(named: "old", at: date("2026-08-05T07:00:00Z"))
        try store.endActiveSession(at: date("2026-08-05T08:00:00Z"))
        try store.startSession(named: "new", at: date("2026-08-06T07:00:00Z"))
        let items = store.listSessions()
        guard case let .readable(first, _) = items[0],
              case let .readable(second, _) = items[1] else { return XCTFail() }
        XCTAssertEqual(first.name, "new")
        XCTAssertEqual(second.name, "old")
    }

    // MARK: - updateNote

    func testUpdateNoteEditsTextCategoryStatusOfRightNoteOnly() throws {
        let folder = try store.startSession(named: "a")
        let n1 = try store.addNote(text: "one", category: "FYI", imageData: nil, to: folder)
        let n2 = try store.addNote(text: "two", category: "Decision", imageData: nil, to: folder)

        try store.updateNote(id: n2.id, in: folder) { note in
            note.text = "two edited"
            note.category = "Question"
            note.status = .processed
        }

        let session = try store.loadSession(in: folder)
        XCTAssertEqual(session.notes[0], n1)   // untouched
        XCTAssertEqual(session.notes[1].text, "two edited")
        XCTAssertEqual(session.notes[1].category, "Question")
        XCTAssertEqual(session.notes[1].status, .processed)
    }

    func testUpdateNoteUnknownIdThrowsNoteNotFound() throws {
        let folder = try store.startSession(named: "a")
        try store.addNote(text: "one", category: "FYI", imageData: nil, to: folder)
        let unknown = UUID()
        XCTAssertThrowsError(try store.updateNote(id: unknown, in: folder) { $0.text = "x" }) {
            XCTAssertEqual($0 as? SessionStoreError, .noteNotFound(unknown))
        }
    }

    // MARK: - deleteNote

    func testDeleteNoteRemovesNoteAndItsImageOthersIntact() throws {
        let folder = try store.startSession(named: "a")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let n1 = try store.addNote(text: "one", category: "FYI", imageData: data, to: folder)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: data, to: folder)

        try store.deleteNote(id: n1.id, in: folder)

        let session = try store.loadSession(in: folder)
        XCTAssertEqual(session.notes, [n2])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(n1.image!).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(n2.image!).path))
    }

    func testDeleteNoteUnknownIdThrowsNoteNotFound() throws {
        let folder = try store.startSession(named: "a")
        let unknown = UUID()
        XCTAssertThrowsError(try store.deleteNote(id: unknown, in: folder)) {
            XCTAssertEqual($0 as? SessionStoreError, .noteNotFound(unknown))
        }
    }

    // MARK: - renameSession

    func testRenameSessionChangesNameFolderUnchanged() throws {
        let folder = try store.startSession(named: "a")
        try store.renameSession(in: folder, to: "New Name")
        let session = try store.loadSession(in: folder)
        XCTAssertEqual(session.name, "New Name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: - setSessionStatus

    func testSetSessionStatusRoundTrips() throws {
        let folder = try store.startSession(named: "a")
        try store.setSessionStatus(.processed, in: folder)
        XCTAssertEqual(try store.loadSession(in: folder).status, .processed)
        try store.setSessionStatus(.pending, in: folder)
        XCTAssertEqual(try store.loadSession(in: folder).status, .pending)
    }

    // MARK: - deleteSession

    func testDeleteSessionTrashesFolder() throws {
        let folder = try store.startSession(named: "a")
        try store.deleteSession(in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(store.listSessions().isEmpty)
    }
}
