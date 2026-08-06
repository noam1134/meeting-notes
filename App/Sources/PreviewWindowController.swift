import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()
    private var panel: NSPanel?

    func show(image: NSImage) {
        panel?.close()
        let p = AutoClosePanel(contentRect: .zero,
                               styleMask: [.titled, .closable, .resizable, .utilityWindow],
                               backing: .buffered, defer: false)
        p.title = "Screenshot"
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: ImagePreview(image: image) { [weak p] in p?.close() })
        host.safeAreaRegions = []
        p.contentViewController = host
        p.setContentSize(ImagePreview.idealPanelSize(for: image))
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
