import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init<V: View>(view: V, width: CGFloat, movableByBackground: Bool = true) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 0),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = movableByBackground
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = .preferredContentSize
        contentView = hostingView
        // preferredContentSize only takes over after the first layout pass; without an
        // initial size the panel shows as a zero-height sliver.
        let fit = hostingView.fittingSize
        setContentSize(NSSize(width: width, height: max(fit.height, 40)))
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    func show() {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - frame.width / 2
        let y = screen.frame.maxY - screen.frame.height * 0.25
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }
}
