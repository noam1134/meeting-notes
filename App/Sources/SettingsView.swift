import SwiftUI
import KeyboardShortcuts
import MeetingNotesCore

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var newCategory = ""

    // QuickNoteView only ever offers ⌘1…⌘9 shortcuts; keep the category
    // list at or below that so every category stays reachable by hotkey.
    private static let maxCategories = 9

    private var atCategoryLimit: Bool {
        state.settings.categories.count >= Self.maxCategories
    }

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
                        guard !trimmed.isEmpty,
                              !state.settings.categories.contains(trimmed),
                              !atCategoryLimit
                        else { return }
                        state.settings.categories.append(trimmed)
                        state.settings.save()
                        newCategory = ""
                    }
                    .disabled(atCategoryLimit)
                }
                if atCategoryLimit {
                    Text("Maximum of \(Self.maxCategories) categories — each needs its own ⌘-digit shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}
