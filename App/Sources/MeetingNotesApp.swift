import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var state: AppState?          // assigned in MeetingNotesApp.init
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let state = Self.state { BrowserWindowController.shared.show(state: state) }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
            guard let window = event.window,
                  window.className.contains("StatusBarWindow") else { return event }
            let button = (window.contentView as? NSStatusBarButton)
                ?? window.contentView?.subviews.compactMap { $0 as? NSStatusBarButton }.first
                ?? window.contentView?.subviews.flatMap(\.subviews).compactMap { $0 as? NSStatusBarButton }.first
            guard let button else { return event }
            button.performClick(nil)
            return nil   // swallow the right-click
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if let state = Self.state { BrowserWindowController.shared.show(state: state) }
        return false
    }
}

@main
struct MeetingNotesApp: App {
    @State private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let appState = AppState()
        _appState = State(initialValue: appState)
        AppDelegate.state = appState
        HotkeyManager.install(
            onScreenshot: { CaptureController.begin(state: appState) },
            onQuickNote: { Self.showQuickNote(state: appState) }
        )
    }

    var body: some Scene {
        MenuBarExtra("MeetingNotes", systemImage: appState.activeSession == nil
                     ? "note.text" : "record.circle.fill") {
            MenuContent(state: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: appState)
        }
    }

    private static var quickNotePanel: FloatingPanel?

    private static func showQuickNote(state: AppState) {
        if let existing = quickNotePanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = FloatingPanel(
            view: QuickNoteView(state: state, dismiss: {
                quickNotePanel?.close()
                quickNotePanel = nil
            }),
            width: 480)
        quickNotePanel = panel
        panel.show()
    }
}
