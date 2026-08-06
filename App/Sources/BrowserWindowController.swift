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
}
