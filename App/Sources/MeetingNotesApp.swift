import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var appState = AppState()
    @State private var hotkeysInstalled = false

    var body: some Scene {
        MenuBarExtra("MeetingNotes", systemImage: appState.activeSession == nil
                     ? "note.text" : "record.circle.fill") {
            MenuContent(state: appState)
                .onAppear { installHotkeysOnce() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: appState)
        }

        Window("Sessions", id: "browser") {
            SessionBrowser(state: appState)
        }
    }

    private func installHotkeysOnce() {
        guard !hotkeysInstalled else { return }
        hotkeysInstalled = true
        HotkeyManager.install(
            onScreenshot: { /* Task 8 wires CaptureController.begin(state:) here */ },
            onQuickNote: { showQuickNote() }
        )
    }

    private func showQuickNote() {
        var panel: FloatingPanel!
        panel = FloatingPanel(
            view: QuickNoteView(state: appState, dismiss: { panel.close() }),
            width: 480, height: 120)
        panel.show()
    }
}
