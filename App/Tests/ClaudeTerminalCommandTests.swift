import XCTest
@testable import MeetingNotes

// Covers `ClaudeTerminalManager.shellQuote(_:)`, the helper that
// embeds the (Claude-authored, arbitrary-content) processing prompt into the
// `/bin/zsh -l -c "claude '<prompt>'"` command line. The prompt is known to
// contain single quotes (e.g. "I've confirmed") and double quotes (the
// "trello" field instruction) — a naive single-quote wrap would let an
// apostrophe in the prompt break out of the quoted string and get
// interpreted as shell syntax. Round-tripping the escaped string back
// through a real zsh process is the only way to be sure the shell agrees
// with our escaping, rather than just eyeballing the algorithm.
final class ClaudeTerminalCommandTests: XCTestCase {
    private func roundTrip(_ original: String) throws -> String {
        let quoted = ClaudeTerminalManager.shellQuote(original)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf '%s' \(quoted)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testPlainTextRoundTrips() throws {
        XCTAssertEqual(try roundTrip("Process my meeting notes"), "Process my meeting notes")
    }

    func testSingleQuoteInTextDoesNotBreakOutOfQuoting() throws {
        // "I've confirmed" — the literal apostrophe from the real prompt text.
        XCTAssertEqual(try roundTrip("Only after I've confirmed, create the cards"),
                        "Only after I've confirmed, create the cards")
    }

    func testDoubleQuotesAndSpecialShellCharactersPassThroughLiterally() throws {
        let text = "write its URL into that note's \"trello\" field; $HOME `whoami` \\backslash"
        XCTAssertEqual(try roundTrip(text), text)
    }

    func testEmptyStringRoundTrips() throws {
        XCTAssertEqual(try roundTrip(""), "")
    }
}
