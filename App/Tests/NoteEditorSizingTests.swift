import AppKit
import XCTest
@testable import MeetingNotes

// Covers `NoteEditorMetrics`, the pure sizing used by the note editor's
// scroll view. Regression target: the editor was a
// `TextField(axis: .vertical).lineLimit(1...6)`, whose AppKit backing caps
// the field at 6 lines while its field editor keeps the full text — and
// that field editor sits in an `_NSKeyboardFocusClipView`, not an
// `NSScrollView`, so overflowing text had no scroller and ignored the
// wheel (only caret motion scrolled it). The replacement is a real
// NSScrollView whose viewport height these functions compute.
final class NoteEditorSizingTests: XCTestCase {
    private let lineHeight: CGFloat = 20
    private let insets: CGFloat = 4

    private func viewport(lines: CGFloat) -> CGFloat {
        NoteEditorMetrics.viewportHeight(contentHeight: lines * lineHeight,
                                         lineHeight: lineHeight, insets: insets,
                                         minLines: 1, maxLines: 6)
    }

    func testEmptyTextGetsOneLineViewport() {
        XCTAssertEqual(NoteEditorMetrics.viewportHeight(contentHeight: 0, lineHeight: lineHeight,
                                                        insets: insets, minLines: 1, maxLines: 6),
                       lineHeight + insets, accuracy: 0.01)
    }

    func testGrowsWithContentBelowTheCap() {
        XCTAssertEqual(viewport(lines: 3), 3 * lineHeight + insets, accuracy: 0.01)
    }

    func testStopsGrowingAtMaxLines() {
        XCTAssertEqual(viewport(lines: 40), 6 * lineHeight + insets, accuracy: 0.01)
    }

    // The bug in one assertion: 40 lines of text in a 6-line viewport must
    // report as scrollable so the scroll view shows (and flashes) a scroller.
    func testOverflowingContentIsScrollable() {
        XCTAssertTrue(NoteEditorMetrics.isScrollable(contentHeight: 40 * lineHeight,
                                                     viewportHeight: viewport(lines: 40),
                                                     insets: insets))
    }

    func testFittingContentIsNotScrollable() {
        XCTAssertFalse(NoteEditorMetrics.isScrollable(contentHeight: 3 * lineHeight,
                                                      viewportHeight: viewport(lines: 3),
                                                      insets: insets))
    }

    // The session browser passes maxLines: nil so an opened note keeps the
    // height it had as static text instead of collapsing to a 6-line box.
    func testNilMaxLinesGrowsWithoutLimit() {
        let uncapped = NoteEditorMetrics.viewportHeight(contentHeight: 40 * lineHeight,
                                                        lineHeight: lineHeight, insets: insets,
                                                        minLines: 1, maxLines: nil)
        XCTAssertEqual(uncapped, 40 * lineHeight + insets, accuracy: 0.01)
        XCTAssertFalse(NoteEditorMetrics.isScrollable(contentHeight: 40 * lineHeight,
                                                      viewportHeight: uncapped, insets: insets))
    }

    func testNilMaxLinesStillHonoursTheMinimum() {
        XCTAssertEqual(NoteEditorMetrics.viewportHeight(contentHeight: 0, lineHeight: lineHeight,
                                                        insets: insets, minLines: 1, maxLines: nil),
                       lineHeight + insets, accuracy: 0.01)
    }
}
