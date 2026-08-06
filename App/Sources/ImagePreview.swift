import SwiftUI

// Full-size screenshot viewer presented as a sheet from a note card thumbnail.
// Pinch (MagnificationGesture) zooms; ScrollView pans when zoomed past the
// window bounds. Esc or the close button dismisses.
//
// The zoomed content's frame is sized to `image.size * scale` (not
// `.scaleEffect`, which is a render-only transform that leaves the
// ScrollView's layout-computed content bounds at the pre-scale size, making
// the overflow unreachable by panning).
struct ImagePreview: View {
    let image: NSImage
    var dismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.92).ignoresSafeArea()

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 0.2), 6)
                    }
                    .onEnded { _ in lastScale = scale }
            )

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(16)
            .keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 640, minHeight: 480)
        .onExitCommand(perform: dismiss)
    }
}
