import Foundation

// Deterministic category -> color-palette-index mapping, shared by the
// sidebar chips and note cards so the same category always renders the
// same color within a run.
public enum CategoryStyle {
    public static let paletteSize = 6

    public static func colorIndex(for category: String, in categories: [String]) -> Int {
        if let index = categories.firstIndex(of: category) {
            return index % paletteSize
        }
        // Unknown category (not in the settings list): hash on unicode
        // scalar sum so the same string always maps to the same index,
        // even across launches, without needing to persist anything.
        let sum = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % paletteSize
    }
}
