import SwiftUI
import KeyboardShortcuts
import MeetingNotesCore

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var newCategory = ""

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Screenshot note:", name: .captureScreenshot)
                KeyboardShortcuts.Recorder("Quick note:", name: .quickNote)
            }
            Section("Categories") {
                ForEach(state.settings.categories, id: \.self) { cat in
                    HStack {
                        Text(cat)
                        Spacer()
                        Button(role: .destructive) {
                            state.settings.categories.removeAll { $0 == cat }
                            state.settings.save()
                        } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    TextField("New category", text: $newCategory)
                    Button("Add") {
                        let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        state.settings.categories.append(trimmed)
                        state.settings.save()
                        newCategory = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}
