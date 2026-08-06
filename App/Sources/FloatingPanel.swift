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
        // Window auto-sizing tracks preferredContentSize through the contentViewController
        // mechanism — a bare NSHostingView contentView never resizes the panel.
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        host.safeAreaRegions = []   // hidden titlebar must not inset the content
        contentViewController = host
        let fit = host.sizeThatFits(in: NSSize(width: width, height: 2000))
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
