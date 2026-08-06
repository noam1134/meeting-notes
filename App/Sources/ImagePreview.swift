import AppKit
import SwiftUI

// Full-size screenshot viewer presented as a sheet from a note card thumbnail.
//
// Default state is "fit": the image is scaled down (never up) to fit
// entirely inside the sheet, so nothing needs scrolling at open. Zoom is
// relative to that fitted size, 1.0 == fit. The displayed content's frame is
// sized to `fittedSize * zoom` (not `.scaleEffect`, which is a render-only
// transform that leaves the ScrollView's layout-computed content bounds at
// the pre-scale size, making the overflow unreachable by panning), wrapped
// in a viewport-sized frame so images smaller than the viewport stay
// centered instead of pinned to a corner.
struct ImagePreview: View {
    let image: NSImage
    var dismiss: () -> Void

    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    private let zoomRange: ClosedRange<CGFloat> = 0.25...4.0
    private let zoomStep: CGFloat = 0.25
    private let toolbarHeight: CGFloat = 44

    private var screenFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private var sheetSize: CGSize {
        CGSize(width: screenFrame.width * 0.85, height: screenFrame.height * 0.85)
    }

    private var fittedSize: CGSize {
        let available = CGSize(width: sheetSize.width, height: sheetSize.height - toolbarHeight)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return available }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height, 1)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                Color.black.opacity(0.92)
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fittedSize.width * zoom, height: fittedSize.height * zoom)
                            .frame(width: max(fittedSize.width * zoom, geo.size.width),
                                   height: max(fittedSize.height * zoom, geo.size.height),
                                   alignment: .center)
                    }
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = clamped(lastZoom * value)
                    }
                    .onEnded { _ in lastZoom = zoom }
            )
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .onExitCommand(perform: dismiss)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                setZoom(zoom - zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)

            Text("\(Int(zoom.rounded(times: 100)))%")
                .monospacedDigit()
                .frame(minWidth: 44)

            Button {
                setZoom(zoom + zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Fit") { setZoom(1.0) }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    private func setZoom(_ value: CGFloat) {
        zoom = clamped(value)
        lastZoom = zoom
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }
}

private extension CGFloat {
    func rounded(times multiplier: CGFloat) -> CGFloat {
        (self * multiplier).rounded()
    }
}
