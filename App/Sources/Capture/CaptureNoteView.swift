import SwiftUI
import MeetingNotesCore

struct CaptureNoteView: View {
    let image: CGImage
    let state: AppState
    let dismiss: () -> Void

    @State private var tool: AnnotationTool = .box
    @State private var shapes: [AnnotationShape] = []
    @State private var draft: AnnotationShape?
    @State private var textLabel = ""
    @State private var note = ""
    @State private var category: String

    private let maxDisplay = CGSize(width: 640, height: 400)
    private var displaySize: CGSize {
        let scale = min(maxDisplay.width / CGFloat(image.width),
                        maxDisplay.height / CGFloat(image.height),
                        1.0)
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    init(image: CGImage, state: AppState, dismiss: @escaping () -> Void) {
        self.image = image
        self.state = state
        self.dismiss = dismiss
        _category = State(initialValue: state.settings.categories.first ?? "FYI")
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $tool) {
                    Image(systemName: "rectangle").tag(AnnotationTool.box)
                    Image(systemName: "arrow.up.right").tag(AnnotationTool.arrow)
                    Image(systemName: "textformat").tag(AnnotationTool.text)
                    Image(systemName: "scribble").tag(AnnotationTool.pen)
                }
                .pickerStyle(.segmented).frame(width: 180)
                if tool == .text {
                    TextField("Label text — then click image", text: $textLabel)
                        .frame(width: 200)
                }
                Spacer()
                Button("Undo") { _ = shapes.popLast() }
                    .disabled(shapes.isEmpty)
                    .keyboardShortcut("z")
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy screenshot (⌘C)")
                .keyboardShortcut("c")
            }

            canvas

            NoteComposer(text: $note, category: $category, categories: state.settings.categories, onSubmit: save)
        }
        .padding(14)
        .frame(width: max(displaySize.width + 28, 480))
        .onExitCommand(perform: dismiss)   // Esc
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
            Canvas { ctx, _ in
                for shape in shapes + (draft.map { [$0] } ?? []) {
                    draw(shape, in: &ctx)
                }
            }
            .frame(width: displaySize.width, height: displaySize.height)
        }
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard tool != .text else { return }
                if tool == .pen {
                    var points = draft?.points ?? [v.startLocation]
                    points.append(v.location)
                    draft = AnnotationShape(id: draft?.id ?? UUID(), tool: tool,
                                            start: v.startLocation, end: v.location,
                                            label: "", points: points)
                } else {
                    draft = AnnotationShape(id: draft?.id ?? UUID(), tool: tool,
                                            start: draft?.start ?? v.startLocation,
                                            end: v.location, label: "")
                }
            }
            .onEnded { _ in
                if let draft {
                    if draft.tool == .pen {
                        if draft.points.count >= 2 { shapes.append(draft) }
                    } else {
                        shapes.append(draft)
                    }
                }
                draft = nil
            })
        .onTapGesture { location in
            guard tool == .text, !textLabel.isEmpty else { return }
            shapes.append(AnnotationShape(id: UUID(), tool: .text,
                                          start: location, end: location, label: textLabel))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func draw(_ shape: AnnotationShape, in ctx: inout GraphicsContext) {
        let stroke = GraphicsContext.Shading.color(.red)
        switch shape.tool {
        case .box:
            let rect = CGRect(x: min(shape.start.x, shape.end.x),
                              y: min(shape.start.y, shape.end.y),
                              width: abs(shape.start.x - shape.end.x),
                              height: abs(shape.start.y - shape.end.y))
            ctx.stroke(Path(rect), with: stroke, lineWidth: 2)
        case .arrow:
            var path = Path()
            path.move(to: shape.start)
            path.addLine(to: shape.end)
            let angle = atan2(shape.end.y - shape.start.y, shape.end.x - shape.start.x)
            for offset in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                path.move(to: shape.end)
                path.addLine(to: CGPoint(x: shape.end.x + 12 * cos(angle + offset),
                                         y: shape.end.y + 12 * sin(angle + offset)))
            }
            ctx.stroke(path, with: stroke, lineWidth: 2)
        case .text:
            ctx.draw(Text(shape.label).font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red),
                     at: shape.start, anchor: .topLeading)
        case .pen:
            var path = Path()
            path.addLines(shape.points)
            ctx.stroke(path, with: stroke, lineWidth: 2)
        }
    }

    private func save() {
        guard let png = AnnotationRenderer.flatten(image: image, shapes: shapes,
                                                   viewSize: displaySize) else {
            state.lastError = "Failed to render annotated screenshot"
            return
        }
        if state.activeSession == nil { state.startMeeting(named: nil) }
        state.addNote(text: note, category: category, imageData: png)
        dismiss()
    }

    private func copyToClipboard() {
        guard let png = AnnotationRenderer.flatten(image: image, shapes: shapes,
                                                   viewSize: displaySize) else {
            state.lastError = "Failed to render annotated screenshot"
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        dismiss()
    }
}
