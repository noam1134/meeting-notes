import SwiftUI
import MeetingNotesCore

// Fixed 6-color palette; CategoryStyle.colorIndex(for:in:) (Core) picks the
// index deterministically so category colors stay stable across launches.
// Shared by every surface (sidebar dots, note chips, quick-note/capture
// pickers) so the same category always renders the same color everywhere.
let categoryPalette: [Color] = [.purple, .teal, .orange, .pink, .blue, .green]

func categoryColor(_ category: String, categories: [String]) -> Color {
    let idx = CategoryStyle.colorIndex(for: category, in: categories)
    return categoryPalette[idx]
}
