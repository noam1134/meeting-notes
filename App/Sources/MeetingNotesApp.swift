import SwiftUI
import UserNotifications
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var state: AppState?          // assigned in MeetingNotesApp.init
    private var rightClickMonitor: Any?
    private var shiftReturnMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if let state = Self.state { BrowserWindowController.shared.show(state: state) }

        // One-time self-registration as a login item. Only fires the first time
        // the app ever launches (guarded by didAutoRegisterLoginItem) so that a
        // user who later disables it in System Settings never gets re-enrolled.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didAutoRegisterLoginItem") {
            switch SMAppService.mainApp.status {
            case .notRegistered, .notFound:
                try? SMAppService.mainApp.register()
            default:
                break   // already enabled, or user has to approve/declined — leave as-is
            }
            defaults.set(true, forKey: "didAutoRegisterLoginItem")
        }

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

        shiftReturnMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == 36,                                   // Return
                  event.modifierFlags.contains(.shift),
                  !event.modifierFlags.contains(.command),
                  NSApp.keyWindow?.firstResponder is NSTextView          // field editor active
            else { return event }
            // Re-post as Option+Return: text fields insert a newline at the caret for it.
            return NSEvent.keyEvent(with: .keyDown,
                                    location: event.locationInWindow,
                                    modifierFlags: event.modifierFlags.subtracting(.shift).union(.option),
                                    timestamp: event.timestamp,
                                    windowNumber: event.windowNumber,
                                    context: nil,
                                    characters: "\n",
                                    charactersIgnoringModifiers: "\n",
                                    isARepeat: event.isARepeat,
                                    keyCode: 36) ?? event
        }
    }
    // Show banners even while the app is frontmost (the browser may be on a
    // different session than the one Claude is asking about).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["sessionFolder"] as? String {
            let folder = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                if let state = AppDelegate.state {
                    BrowserWindowController.shared.show(state: state)
                }
                NotificationCenter.default.post(name: .mnOpenSession, object: folder)
            }
        }
        completionHandler()
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
        MenuBarExtra {
            MenuContent(state: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.activeSession == nil ? "note.text" : "record.circle.fill")
                if appState.pendingSessionCount > 0 {
                    Text("\(appState.pendingSessionCount)")
                }
            }
            .accessibilityLabel("MeetingNotes")
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
