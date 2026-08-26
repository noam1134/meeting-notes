import AppKit
import XCTest
@testable import MeetingNotes

// Covers `NoteTextMetrics`, which decides whether a note card shows its
// "Show N more lines" control. SwiftUI never reports that a `Text` was
// truncated, so the card measures the note with the same font, width and
// line spacing it renders with.
final class NoteTextMetricsTests: XCTestCase {
    private let font = ExpandableNoteText.font
    private let spacing = ExpandableNoteText.lineSpacing
    private let width: CGFloat = 300

    private func lines(_ text: String) -> Int {
        NoteTextMetrics.lineCount(text: text, width: width, font: font, lineSpacing: spacing)
    }

    private func hidden(_ text: String) -> Int {
        NoteTextMetrics.hiddenLineCount(text: text, width: width, font: font, lineSpacing: spacing,
                                        visibleLines: ExpandableNoteText.collapsedLines)
    }

    func testEmptyNoteMeasuresNoLines() {
        XCTAssertEqual(lines(""), 0)
        XCTAssertEqual(hidden(""), 0)
    }

    // Width is 0 until the card lays out; measuring then must not flash a
    // "Show more" control on notes that turn out to fit.
    func testUnmeasuredWidthHidesNothing() {
        XCTAssertEqual(NoteTextMetrics.hiddenLineCount(text: "anything at all", width: 0, font: font,
                                                       lineSpacing: spacing, visibleLines: 6), 0)
    }

    func testShortNoteIsOneLineAndNotTruncated() {
        XCTAssertEqual(lines("ship it"), 1)
        XCTAssertEqual(hidden("ship it"), 0)
    }

    func testExplicitNewlinesCount() {
        XCTAssertEqual(lines("one\ntwo\nthree"), 3)
    }

    func testNoteAtTheCollapsedLimitOffersNoExpansion() {
        let sixLines = (1...6).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(lines(sixLines), 6)
        XCTAssertEqual(hidden(sixLines), 0)
    }

    func testLongNoteReportsTheLinesItHides() {
        let twenty = (1...20).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(lines(twenty), 20)
        XCTAssertEqual(hidden(twenty), 14)
    }

    // Wrapping, not just newlines: one long paragraph must also be detected.
    func testWrappedParagraphCountsWrappedLines() {
        let paragraph = String(repeating: "wrapping prose that keeps going ", count: 30)
        XCTAssertGreaterThan(lines(paragraph), 6)
        XCTAssertEqual(hidden(paragraph), lines(paragraph) - 6)
    }
}
