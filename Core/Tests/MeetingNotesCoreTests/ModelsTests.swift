import XCTest
@testable import MeetingNotesCore

final class ModelsTests: XCTestCase {
    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func sample() -> Session {
        Session(
            name: "sprint-planning",
            startedAt: date("2026-08-06T07:30:00Z"),
            endedAt: nil,
            status: .pending,
            notes: [Note(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                         timestamp: date("2026-08-06T07:42:11Z"),
                         category: "Trello task",
                         text: "fix login redirect bug",
                         images: ["img-001.png"],
                         status: .pending,
                         trello: nil)]
        )
    }

    func testRoundTrip() throws {
        let s = sample()
        let decoded = try SessionJSON.decode(try SessionJSON.encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testJSONFieldNamesMatchSpec() throws {
        let json = try JSONSerialization.jsonObject(with: SessionJSON.encode(sample())) as! [String: Any]
        XCTAssertEqual(Set(json.keys), ["name", "startedAt", "endedAt", "status", "notes"])
        let note = (json["notes"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(note.keys), ["id", "timestamp", "category", "text", "images", "status", "trello"])
        XCTAssertEqual(json["status"] as? String, "pending")
    }

    // One source of truth: writing both keys is how the filename-collision bug
    // started, so the legacy key must not survive a write.
    func testEncodeWritesImagesArrayAndDropsLegacyImageKey() throws {
        let json = try JSONSerialization.jsonObject(with: SessionJSON.encode(sample())) as! [String: Any]
        let note = (json["notes"] as! [[String: Any]])[0]
        XCTAssertEqual(note["images"] as? [String], ["img-001.png"])
        XCTAssertNil(note["image"])
    }

    func testTextOnlyNoteHasEmptyImages() throws {
        var s = sample()
        s.notes[0].images = []
        let decoded = try SessionJSON.decode(try SessionJSON.encode(s))
        XCTAssertEqual(decoded.notes[0].images, [])
    }

    func testMultipleImagesRoundTrip() throws {
        var s = sample()
        s.notes[0].images = ["img-001.png", "img-004.png", "img-009.png"]
        let decoded = try SessionJSON.decode(try SessionJSON.encode(s))
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.notes[0].images, ["img-001.png", "img-004.png", "img-009.png"])
    }

    // Every session already on disk uses the singular key; all three legacy
    // shapes must load without a migration step.
    func testDecodeLegacySingleImageKey() throws {
        XCTAssertEqual(try legacyNote(imageField: "\"image\": \"img-001.png\",").images,
                       ["img-001.png"])
    }

    func testDecodeLegacyNullImageKey() throws {
        XCTAssertEqual(try legacyNote(imageField: "\"image\": null,").images, [])
    }

    func testDecodeMissingImageKey() throws {
        XCTAssertEqual(try legacyNote(imageField: "").images, [])
    }

    private func legacyNote(imageField: String) throws -> Note {
        let json = """
        {
          "name": "legacy-session",
          "startedAt": "2026-08-06T07:30:00Z",
          "endedAt": null,
          "status": "pending",
          "notes": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "timestamp": "2026-08-06T07:42:11Z",
              "category": "Trello task",
              "text": "fix login redirect bug",
              \(imageField)
              "status": "pending"
            }
          ]
        }
        """
        return try SessionJSON.decode(Data(json.utf8)).notes[0]
    }

    func testTrelloDefaultsToNullInJSON() throws {
        let s = sample()
        let json = try XCTUnwrap(String(data: SessionJSON.encode(s), encoding: .utf8))
        XCTAssertTrue(json.contains("\"trello\" : null"))
    }

    func testTrelloRoundTrip() throws {
        var s = sample()
        s.notes[0].trello = "https://trello.com/c/abc123"
        let decoded = try SessionJSON.decode(try SessionJSON.encode(s))
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.notes[0].trello, "https://trello.com/c/abc123")
    }

    func testDecodeOldSessionWithoutTrelloField() throws {
        // Old sessions predate the trello field entirely; decode must tolerate its absence.
        let legacyJSON = """
        {
          "name": "legacy-session",
          "startedAt": "2026-08-06T07:30:00Z",
          "endedAt": null,
          "status": "pending",
          "notes": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "timestamp": "2026-08-06T07:42:11Z",
              "category": "Trello task",
              "text": "fix login redirect bug",
              "image": "img-001.png",
              "status": "pending"
            }
          ]
        }
        """
        let decoded = try SessionJSON.decode(Data(legacyJSON.utf8))
        XCTAssertNil(decoded.notes[0].trello)
    }

    func testIsActive() {
        var s = sample()
        XCTAssertTrue(s.isActive)
        s.endedAt = date("2026-08-06T08:00:00Z")
        XCTAssertFalse(s.isActive)
    }
}
