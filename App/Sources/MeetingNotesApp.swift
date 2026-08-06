import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var appState: AppState

    init() {
        let appState = AppState()
        _appState = State(initialValue: appState)
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

        Window("Sessions", id: "browser") {
            SessionBrowser(state: appState)
        }
        .defaultSize(width: 920, height: 640)
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
            width: 480, height: 150)
        quickNotePanel = panel
        panel.show()
    }
}
