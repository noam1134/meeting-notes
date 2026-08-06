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
    }

    private static func showQuickNote(state: AppState) {
        var panel: FloatingPanel!
        panel = FloatingPanel(
            view: QuickNoteView(state: state, dismiss: { panel.close() }),
            width: 480, height: 120)
        panel.show()
    }
}
