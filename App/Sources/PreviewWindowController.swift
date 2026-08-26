import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()
    private var panel: NSPanel?

    func show(images: [NSImage], startIndex: Int = 0) {
        guard let first = images.first else { return }
        panel?.close()
        let p = AutoClosePanel(contentRect: .zero,
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                               backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            p.standardWindowButton(buttonType)?.isHidden = true
        }
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false
        let host = NSHostingController(
            rootView: ImagePreview(images: images, startIndex: startIndex) { [weak p] in p?.close() })
        host.safeAreaRegions = []
        p.contentViewController = host
        // Sized for the screenshot you clicked; paging to a differently-shaped
        // one refits inside the panel rather than resizing it under you.
        let opening = images.indices.contains(startIndex) ? images[startIndex] : first
        p.setContentSize(ImagePreview.idealPanelSize(for: opening))
        p.center()
        p.onClose = { [weak self] in self?.panel = nil }
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }
}

private final class AutoClosePanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        close()          // click anywhere else = dismiss (preserves click-outside-closes behavior)
    }
    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }
    override func cancelOperation(_ sender: Any?) { close() }   // Esc
}
