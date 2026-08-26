import AppKit
import SwiftUI

@MainActor
final class BrowserWindowController {
    static let shared = BrowserWindowController()
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let host = NSHostingController(rootView: SessionBrowser(state: state))
            let w = NSWindow(contentViewController: host)
            w.title = "Sessions"
            w.setContentSize(NSSize(width: 900, height: 620))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Region select photographs the display as it stands, so this window would
    // land in any screenshot taken from a note card. CaptureController hides it
    // for the duration and restores it on every exit path, cancel included.
    var isVisible: Bool { window?.isVisible ?? false }

    func hide() {
        window?.orderOut(nil)
    }

    func restore() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
