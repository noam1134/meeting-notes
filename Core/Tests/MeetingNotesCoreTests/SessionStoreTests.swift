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
        XCTAssertEqual(note.images, [])
        let session = try store.loadSession(in: try XCTUnwrap(store.activeSessionFolder()))
        XCTAssertEqual(session.notes, [note])
    }

    func testAddImageNoteWritesSequentialPNGs() throws {
        let folder = try store.startSession(named: "a")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let n1 = try store.addNote(text: "one", category: "FYI", imageData: data)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: data)
        XCTAssertEqual(n1.images, ["img-001.png"])
        XCTAssertEqual(n2.images, ["img-002.png"])
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
        XCTAssertEqual(note.images, ["img-002.png"])
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

    // Shaped exactly like the sessions on disk when `images` was introduced:
    // every note carries the singular `image` key, some of them null. Loading
    // must preserve every reference, and the migrating write must not disturb
    // the PNGs those references point at.
    func testLegacySessionOnDiskLoadsAndMigratesWithoutLosingImages() throws {
        let folder = rootURL().appendingPathComponent("2026-08-12-1414-legacy", isDirectory: false)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = """
        {
          "name" : "weekly meeting",
          "startedAt" : "2026-08-12T11:14:00Z",
          "endedAt" : "2026-08-12T13:00:00Z",
          "status" : "pending",
          "notes" : [
            { "id" : "11111111-1111-1111-1111-111111111111", "timestamp" : "2026-08-12T11:47:00Z",
              "category" : "Trello task", "text" : "modal closes on mouse-up outside",
              "image" : "img-003.png", "status" : "pending", "trello" : null },
            { "id" : "22222222-2222-2222-2222-222222222222", "timestamp" : "2026-08-12T12:02:24Z",
              "category" : "FYI", "text" : "add type for the task entity",
              "image" : null, "status" : "processed", "trello" : null },
            { "id" : "33333333-3333-3333-3333-333333333333", "timestamp" : "2026-08-12T12:22:20Z",
              "category" : "Trello task", "text" : "assignees should auto-update",
              "image" : "img-008.png", "status" : "pending", "trello" : null }
          ]
        }
        """
        try Data(legacy.utf8).write(to: folder.appendingPathComponent("session.json"))
        let three = Data([0x89, 0x03]), eight = Data([0x89, 0x08])
        try three.write(to: folder.appendingPathComponent("img-003.png"))
        try eight.write(to: folder.appendingPathComponent("img-008.png"))

        let loaded = try store.loadSession(in: folder)
        XCTAssertEqual(loaded.notes.map(\.images),
                       [["img-003.png"], [], ["img-008.png"]])

        // Any write migrates the file; the new capture must not land on a name
        // the legacy notes still hold.
        let added = try store.addNote(text: "new", category: "FYI",
                                      imageData: Data([0x89, 0x99]), to: folder)
        XCTAssertFalse(["img-003.png", "img-008.png"].contains(added.images[0]))

        let migrated = try store.loadSession(in: folder)
        XCTAssertEqual(migrated.notes.map(\.images),
                       [["img-003.png"], [], ["img-008.png"], added.images])
        XCTAssertEqual(migrated.notes.map(\.text).prefix(3),
                       ["modal closes on mouse-up outside", "add type for the task entity",
                        "assignees should auto-update"])
        XCTAssertEqual(migrated.notes[1].status, .processed)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-003.png")), three)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-008.png")), eight)

        let json = try String(contentsOf: folder.appendingPathComponent("session.json"), encoding: .utf8)
        XCTAssertTrue(json.contains("\"images\""))
        XCTAssertFalse(json.contains("\"image\" :"))
    }

    private func rootURL() -> URL { root }

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
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(n1.images[0]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(n2.images[0]).path))
    }

    // Deleting an image note used to shrink the "count + 1" counter, so the next
    // capture handed out a filename another note was still using and overwrote it.
    func testImageNameNotReusedAfterDeletingAnImageNote() throws {
        let folder = try store.startSession(named: "a")
        let one = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        let two = Data([0x89, 0x50, 0x4E, 0x47, 0x02])
        let three = Data([0x89, 0x50, 0x4E, 0x47, 0x03])
        let four = Data([0x89, 0x50, 0x4E, 0x47, 0x04])

        let n1 = try store.addNote(text: "one", category: "FYI", imageData: one, to: folder)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: two, to: folder)
        let n3 = try store.addNote(text: "three", category: "FYI", imageData: three, to: folder)
        try store.deleteNote(id: n2.id, in: folder)
        let n4 = try store.addNote(text: "four", category: "FYI", imageData: four, to: folder)

        XCTAssertNotEqual(n4.images, n1.images)
        XCTAssertNotEqual(n4.images, n3.images)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(n1.images[0])), one)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(n3.images[0])), three)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(n4.images[0])), four)
    }

    // Claude (or any external edit) may clear a note's image without deleting the
    // file; the orphan must still not be handed to the next note.
    func testImageNameSkipsOrphanFileOnDisk() throws {
        let folder = try store.startSession(named: "a")
        let orphan = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        try orphan.write(to: folder.appendingPathComponent("img-001.png"))

        let note = try store.addNote(text: "one", category: "FYI",
                                     imageData: Data([0x89, 0x50, 0x4E, 0x47, 0x01]), to: folder)

        XCTAssertNotEqual(note.images, ["img-001.png"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-001.png")), orphan)
    }

    // Sessions written before the fix contain notes sharing one filename; deleting
    // either must not take the surviving note's screenshot with it.
    func testDeleteNoteKeepsImageStillReferencedByAnotherNote() throws {
        let folder = try store.startSession(named: "a")
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let n1 = try store.addNote(text: "one", category: "FYI", imageData: data, to: folder)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: nil, to: folder)
        try store.updateNote(id: n2.id, in: folder) { $0.images = n1.images }

        try store.deleteNote(id: n1.id, in: folder)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(n1.images[0]).path))
    }

    func testDeleteNoteUnknownIdThrowsNoteNotFound() throws {
        let folder = try store.startSession(named: "a")
        let unknown = UUID()
        XCTAssertThrowsError(try store.deleteNote(id: unknown, in: folder)) {
            XCTAssertEqual($0 as? SessionStoreError, .noteNotFound(unknown))
        }
    }

    func testDeleteNoteTrashesEveryImageItHolds() throws {
        let folder = try store.startSession(named: "a")
        let note = try store.addNote(text: "one", category: "FYI",
                                     imageData: Data([0x89, 0x01]), to: folder)
        let second = try store.attachImage(noteID: note.id, in: folder, imageData: Data([0x89, 0x02]))
        let third = try store.attachImage(noteID: note.id, in: folder, imageData: Data([0x89, 0x03]))

        try store.deleteNote(id: note.id, in: folder)

        for name in [note.images[0], second, third] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(name).path), "\(name) survived")
        }
    }

    // MARK: - attachImage

    func testAttachImageAppendsToExistingNote() throws {
        let folder = try store.startSession(named: "a")
        let first = Data([0x89, 0x50, 0x01])
        let second = Data([0x89, 0x50, 0x02])
        let note = try store.addNote(text: "one", category: "FYI", imageData: first, to: folder)

        let name = try store.attachImage(noteID: note.id, in: folder, imageData: second)

        let session = try store.loadSession(in: folder)
        XCTAssertEqual(session.notes[0].images, [note.images[0], name])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(name)), second)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(note.images[0])), first)
    }

    func testAttachImageToTextOnlyNoteGivesItAnImage() throws {
        let folder = try store.startSession(named: "a")
        let note = try store.addNote(text: "no shot", category: "FYI", imageData: nil, to: folder)

        let name = try store.attachImage(noteID: note.id, in: folder, imageData: Data([0x89, 0x01]))

        XCTAssertEqual(try store.loadSession(in: folder).notes[0].images, [name])
    }

    // The allocator must see other notes' images and stray files, not just this note's.
    func testAttachImageNeverCollides() throws {
        let folder = try store.startSession(named: "a")
        let other = try store.addNote(text: "other", category: "FYI",
                                      imageData: Data([0x89, 0x01]), to: folder)
        let target = try store.addNote(text: "target", category: "FYI", imageData: nil, to: folder)
        let orphan = Data([0x89, 0xFF])
        try orphan.write(to: folder.appendingPathComponent("img-002.png"))

        let name = try store.attachImage(noteID: target.id, in: folder, imageData: Data([0x89, 0x03]))

        XCTAssertFalse(other.images.contains(name))
        XCTAssertNotEqual(name, "img-002.png")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(other.images[0])), Data([0x89, 0x01]))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("img-002.png")), orphan)
    }

    func testAttachImageUnknownIdThrowsNoteNotFound() throws {
        let folder = try store.startSession(named: "a")
        let unknown = UUID()
        XCTAssertThrowsError(try store.attachImage(noteID: unknown, in: folder,
                                                   imageData: Data([0x89]))) {
            XCTAssertEqual($0 as? SessionStoreError, .noteNotFound(unknown))
        }
    }

    // MARK: - detachImage

    func testDetachImageDropsRefAndTrashesFile() throws {
        let folder = try store.startSession(named: "a")
        let note = try store.addNote(text: "one", category: "FYI",
                                     imageData: Data([0x89, 0x01]), to: folder)
        let second = try store.attachImage(noteID: note.id, in: folder, imageData: Data([0x89, 0x02]))

        try store.detachImage(noteID: note.id, in: folder, named: second)

        XCTAssertEqual(try store.loadSession(in: folder).notes[0].images, [note.images[0]])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(second).path))
    }

    func testDetachImageKeepsFileAnotherNoteReferences() throws {
        let folder = try store.startSession(named: "a")
        let n1 = try store.addNote(text: "one", category: "FYI",
                                   imageData: Data([0x89, 0x01]), to: folder)
        let n2 = try store.addNote(text: "two", category: "FYI", imageData: nil, to: folder)
        try store.updateNote(id: n2.id, in: folder) { $0.images = n1.images }

        try store.detachImage(noteID: n1.id, in: folder, named: n1.images[0])

        XCTAssertEqual(try store.loadSession(in: folder).notes[0].images, [])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(n1.images[0]).path))
    }

    func testDetachImageUnknownIdThrowsNoteNotFound() throws {
        let folder = try store.startSession(named: "a")
        let unknown = UUID()
        XCTAssertThrowsError(try store.detachImage(noteID: unknown, in: folder,
                                                   named: "img-001.png")) {
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
