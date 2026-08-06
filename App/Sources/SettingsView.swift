import SwiftUI
import ServiceManagement
import KeyboardShortcuts
import MeetingNotesCore

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var newCategory = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    // QuickNoteView only ever offers ⌘-digit shortcuts up to
    // CategoryHotkey.maxShortcutCount; keep the category list at or below
    // that so every category stays reachable by hotkey.
    private var atCategoryLimit: Bool {
        state.settings.categories.count >= CategoryHotkey.maxShortcutCount
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            state.lastError = String(describing: error)
                        }
                    }
                Toggle("Morning reminder", isOn: Binding(
                    get: { state.settings.morningReminderEnabled },
                    set: { state.setMorningReminderEnabled($0) }
                ))
            }
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
                    Text("Maximum of \(CategoryHotkey.maxShortcutCount) categories — each needs its own ⌘-digit shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)   // window sizes to content instead of scrolling
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Front the window — the app is normally .accessory (no dock icon).
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
