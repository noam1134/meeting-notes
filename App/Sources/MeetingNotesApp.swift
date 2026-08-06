import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("MeetingNotes", systemImage: appState.activeSession == nil
                     ? "note.text" : "record.circle.fill") {
            MenuContent(state: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Sessions", id: "browser") {
            SessionBrowser(state: appState)
        }
    }
}
