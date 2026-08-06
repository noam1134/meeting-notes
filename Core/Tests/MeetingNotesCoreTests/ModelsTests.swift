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
                         image: "img-001.png",
                         status: .pending)]
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
        XCTAssertEqual(Set(note.keys), ["id", "timestamp", "category", "text", "image", "status"])
        XCTAssertEqual(json["status"] as? String, "pending")
    }

    func testTextOnlyNoteHasNullImage() throws {
        var s = sample()
        s.notes[0].image = nil
        let json = try XCTUnwrap(String(data: SessionJSON.encode(s), encoding: .utf8))
        XCTAssertTrue(json.contains("\"image\" : null"))
    }

    func testIsActive() {
        var s = sample()
        XCTAssertTrue(s.isActive)
        s.endedAt = date("2026-08-06T08:00:00Z")
        XCTAssertFalse(s.isActive)
    }
}
