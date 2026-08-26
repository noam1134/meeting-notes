import AppKit
import SwiftUI

/// Line arithmetic for a note rendered as static text.
///
/// SwiftUI reports nothing about whether `lineLimit` actually truncated a
/// `Text`, so the card measures the note itself to decide whether to offer
/// an expand control — and how many lines it is hiding.
enum NoteTextMetrics {
    static func lineHeight(font: NSFont, lineSpacing: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font) + lineSpacing
    }

    static func measuredHeight(text: String, width: CGFloat, font: NSFont, lineSpacing: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attributed = NSAttributedString(string: text,
                                            attributes: [.font: font, .paragraphStyle: paragraph])
        return attributed.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    }

    /// Wrapped lines the note occupies at `width`. `n` lines measure
    /// `n * lineHeight + (n - 1) * lineSpacing`, so adding one spacing back
    /// makes the division exact.
    static func lineCount(text: String, width: CGFloat, font: NSFont, lineSpacing: CGFloat) -> Int {
        let height = measuredHeight(text: text, width: width, font: font, lineSpacing: lineSpacing)
        guard height > 0 else { return 0 }
        return Int(((height + lineSpacing) / lineHeight(font: font, lineSpacing: lineSpacing)).rounded())
    }

    static func hiddenLineCount(text: String, width: CGFloat, font: NSFont, lineSpacing: CGFloat,
                                visibleLines: Int) -> Int {
        max(lineCount(text: text, width: width, font: font, lineSpacing: lineSpacing) - visibleLines, 0)
    }
}

/// A note's text, clamped to `collapsedLines` with a "Show N more lines"
/// toggle when it overflows. The card owns the click gestures — a tap
/// anywhere on it expands or collapses — so this view only draws the
/// affordance. Editing shows the whole note instead, so the card never
/// gets *shorter* when you open it.
struct ExpandableNoteText: View {
    let text: String
    @Binding var isExpanded: Bool

    static let collapsedLines = 6
    static let font = NSFont.systemFont(ofSize: 15)
    static let lineSpacing: CGFloat = 3

    @State private var width: CGFloat = 0

    private var hiddenLines: Int {
        NoteTextMetrics.hiddenLineCount(text: text, width: width, font: Self.font,
                                        lineSpacing: Self.lineSpacing,
                                        visibleLines: Self.collapsedLines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(Self.lineSpacing)
                .lineLimit(isExpanded ? nil : Self.collapsedLines)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width, initial: true) { _, new in width = new }
                })
            if hiddenLines > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        Text(isExpanded
                             ? "Show less"
                             : "Show \(hiddenLines) more line\(hiddenLines == 1 ? "" : "s")")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse this note" : "Show the rest of this note")
            }
        }
    }
}
