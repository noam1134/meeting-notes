import AppKit
import Observation
import SwiftUI
import XCTest
import MeetingNotesCore
@testable import MeetingNotes

// Covers `FloatingPanel` sizing itself to its SwiftUI content. Regression
// target: on macOS 27 a content height that wasn't a whole number of points
// (the capture canvas scaled to fit, the note editor growing by line
// metrics) could never match the window frame, so AppKit and SwiftUI kept
// re-running constraints until AppKit threw "more Update Constraints in
// Window passes than there are views in the window" and the app aborted —
// on showing the capture panel, or while typing into Quick Note.
//
// The tests run inside the app, so a regression takes the whole test host
// down rather than failing an assertion.
@Observable
private final class Box {
    var height: CGFloat = 40
}

private struct GrowingView: View {
    let box: Box
    var body: some View {
        Rectangle().frame(width: 300, height: box.height)
    }
}

@MainActor
final class FloatingPanelSizingTests: XCTestCase {
    private func runDisplayCycles(for seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testContentGrowingByFractionalPointsSettlesOnWholePoints() {
        let box = Box()
        let panel = FloatingPanel(view: GrowingView(box: box), width: 300)
        defer { panel.close() }
        panel.show()
        runDisplayCycles()

        for _ in 0..<5 {
            box.height += 0.3
            runDisplayCycles()
        }

        let height = panel.contentView?.frame.height ?? 0
        XCTAssertEqual(height, height.rounded(), "panel content height should be whole points")
        XCTAssertGreaterThanOrEqual(height, box.height)
        XCTAssertLessThan(height, box.height + 1)
    }

    private func makeState() -> AppState {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatingPanelSizingTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppState(store: SessionStore(rootURL: root))
    }

    private func firstSubview<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstSubview(type, in: $0) }.first
    }

    // Quick Note's editor sits under the panel's hidden titlebar; the scroll
    // view's automatic insets pushed the text down and out of its box.
    func testQuickNoteEditorTextIsNotInsetUnderTheHiddenTitlebar() throws {
        let panel = FloatingPanel(view: QuickNoteView(state: makeState(), dismiss: {}), width: 480)
        defer { panel.close() }
        panel.show()
        runDisplayCycles()

        let scroll = try XCTUnwrap(firstSubview(NSScrollView.self, in: panel.contentView))
        XCTAssertEqual(scroll.contentInsets.top, 0)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0)
    }

    func testCapturePanelWithFractionalCanvasShows() throws {
        let state = makeState()
        // 1400×1200 fits the 640×400 canvas box as 466.67×400.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1400, height: 1200, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())

        CaptureController.presentCaptureWindow(image: image, state: state)
        let panel = try XCTUnwrap(NSApp.windows.last { $0 is FloatingPanel && $0.isVisible })
        defer { panel.close() }
        runDisplayCycles(for: 0.5)

        XCTAssertEqual(panel.frame.height, panel.frame.height.rounded())
        XCTAssertGreaterThan(panel.frame.height, 400)
    }
}
