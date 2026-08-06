import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureScreenshot = Self("captureScreenshot",
        default: .init(.s, modifiers: [.control, .shift]))
    static let quickNote = Self("quickNote",
        default: .init(.n, modifiers: [.control, .shift]))
}

enum HotkeyManager {
    static func install(onScreenshot: @escaping () -> Void,
                        onQuickNote: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .captureScreenshot, action: onScreenshot)
        KeyboardShortcuts.onKeyUp(for: .quickNote, action: onQuickNote)
    }
}
