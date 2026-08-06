import Foundation

/// Maps a category's zero-based index to its ⌘-digit quick-select shortcut.
///
/// `Character(_:String)` traps unless the string is exactly one extended
/// grapheme cluster, so a shortcut can only be built for indices 0-8
/// (categories 1-9). Centralizing that boundary here — instead of each call
/// site re-deriving it from `Character("\(i + 1)")` — makes the boundary a
/// single, unit-testable fact instead of an implicit trap.
public enum CategoryHotkey {
    /// ⌘-digit shortcuts only span 1-9, so at most this many categories can
    /// have one.
    public static let maxShortcutCount = 9

    /// The single-digit shortcut character for the category at `index`, or
    /// `nil` if that index has no digit shortcut (negative, or >= `maxShortcutCount`).
    public static func digitCharacter(forIndex index: Int) -> Character? {
        guard index >= 0, index < maxShortcutCount else { return nil }
        return Character(String(index + 1))
    }
}
