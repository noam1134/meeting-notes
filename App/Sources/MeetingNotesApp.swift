import SwiftUI

@main
struct MeetingNotesApp: App {
    var body: some Scene {
        MenuBarExtra("MeetingNotes", systemImage: "note.text") {
            Text("MeetingNotes — scaffold").padding()
        }
        .menuBarExtraStyle(.window)
    }
}
