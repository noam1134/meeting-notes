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
    @FocusState private var noteFocused: Bool

    private let displayWidth: CGFloat = 640
    private var displaySize: CGSize {
        let scale = displayWidth / CGFloat(image.width)
        return CGSize(width: displayWidth, height: CGFloat(image.height) * scale)
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
                }
                .pickerStyle(.segmented).frame(width: 140)
                if tool == .text {
                    TextField("Label text — then click image", text: $textLabel)
                        .frame(width: 200)
                }
                Spacer()
                Button("Undo") { _ = shapes.popLast() }
                    .disabled(shapes.isEmpty)
                    .keyboardShortcut("z")
            }

            canvas

            TextField("Note…", text: $note)
                .textFieldStyle(.roundedBorder)
                .focused($noteFocused)
                .onSubmit(save)

            HStack {
                Picker("Category", selection: $category) {
                    ForEach(state.settings.categories, id: \.self) { Text($0) }
                }
                .frame(width: 240)
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: displayWidth + 28)
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
                draft = AnnotationShape(id: draft?.id ?? UUID(), tool: tool,
                                        start: draft?.start ?? v.startLocation,
                                        end: v.location, label: "")
            }
            .onEnded { _ in
                if let draft { shapes.append(draft) }
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
        }
    }

    private func save() {
        guard let png = AnnotationRenderer.flatten(image: image, shapes: shapes,
                                                   viewSize: displaySize) else { return }
        if state.activeSession == nil { state.startMeeting(named: nil) }
        state.addNote(text: note, category: category, imageData: png)
        dismiss()
    }
}
