import AppKit
import XCTest
@testable import MeetingNotes

// Covers `ImagePreview.idealPanelSize(for:)`, the pure sizing function
// `PreviewWindowController.show()` calls to size the panel (R18 Fix round
// 1). Regression target: before that fix, the panel was sized via
// `NSHostingController.sizeThatFits(in: NSSize(width: 4000, height: 4000))`,
// which — because `ImagePreview`'s root frame is `maxWidth/maxHeight:
// .infinity` — resolved to ~(4000, 4000) regardless of image size. These
// tests assert `idealPanelSize` instead tracks the image/screen-relative
// fitted size described in ImagePreview.swift's header comment (85% of
// screen cap, never upscaled, 360pt minWidth floor, +44pt toolbar).
final class ImagePreviewSizingTests: XCTestCase {
    // Mirrors ImagePreview's private screen-fallback and 85%-cap constants.
    // Duplicated here (rather than exposed from ImagePreview) because those
    // are `private` implementation details; `idealPanelSize` is the
    // intended, already-internal testing seam.
    private var screenFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private var cap: CGSize {
        CGSize(width: screenFrame.width * 0.85, height: screenFrame.height * 0.85)
    }

    private let toolbarHeight: CGFloat = 44
    private let minWidth: CGFloat = 360

    func testTinyImageClampsToMinWidthFloor() {
        let image = NSImage(size: NSSize(width: 10, height: 8))
        let result = ImagePreview.idealPanelSize(for: image)

        // Never upscaled: fitted size stays 10x8, but the container widens
        // to the 360pt floor so the zoom toolbar always fits.
        XCTAssertEqual(result.width, minWidth, accuracy: 0.01)
        XCTAssertEqual(result.height, 8 + toolbarHeight, accuracy: 0.01)
    }

    func testHugeSquareImageCapsProportionallyToScreen() {
        let image = NSImage(size: NSSize(width: 100_000, height: 100_000))
        let result = ImagePreview.idealPanelSize(for: image)

        // The regression this guards against: pre-fix this would have been
        // ~4000x4000 (the sizeThatFits proposal), not screen-relative.
        XCTAssertLessThan(result.width, 4000)
        XCTAssertLessThan(result.height, 4000)

        let expectedScale = min(cap.width / 100_000, cap.height / 100_000, 1)
        let expectedWidth = max(100_000 * expectedScale, minWidth)
        let expectedHeight = 100_000 * expectedScale + toolbarHeight
        XCTAssertEqual(result.width, expectedWidth, accuracy: 0.5)
        XCTAssertEqual(result.height, expectedHeight, accuracy: 0.5)
    }

    func testWideLandscapeImageIsWidthConstrained() {
        // Much wider than tall: width should hit the 85% width cap while
        // height stays proportionally under the 85% height cap.
        let image = NSImage(size: NSSize(width: 20_000, height: 100))
        let result = ImagePreview.idealPanelSize(for: image)

        XCTAssertEqual(result.width, cap.width, accuracy: 0.5)
        XCTAssertLessThanOrEqual(result.height - toolbarHeight, cap.height + 0.5)
    }

    func testTallPortraitImageIsHeightConstrained() {
        // Much taller than wide: height should hit the 85% height cap.
        let image = NSImage(size: NSSize(width: 100, height: 20_000))
        let result = ImagePreview.idealPanelSize(for: image)

        XCTAssertEqual(result.height - toolbarHeight, cap.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(result.width, minWidth)
    }

    func testSizeIsDeterministicAcrossRepeatedCalls() {
        // idealPanelSize must not depend on any SwiftUI layout pass (that
        // was the bug: sizeThatFits's answer depended on layout/proposal
        // behavior). Calling it repeatedly for the same image should be
        // pure and stable.
        let image = NSImage(size: NSSize(width: 1200, height: 800))
        let first = ImagePreview.idealPanelSize(for: image)
        let second = ImagePreview.idealPanelSize(for: image)
        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)
    }
}
