import AppKit
import SwiftUI

final class RegionSelectWindow: NSWindow {
    private let onSelect: (CGImage?) -> Void

    init(screenshot: CGImage, onSelect: @escaping (CGImage?) -> Void) {
        self.onSelect = onSelect
        let screenFrame = NSScreen.main?.frame ?? .zero
        super.init(contentRect: screenFrame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: RegionSelectView(
            screenshot: screenshot,
            viewSize: screenFrame.size,
            onDone: { [weak self] image in
                self?.orderOut(nil)
                onSelect(image)
            }))
    }

    override var canBecomeKey: Bool { true }

    func begin() { makeKeyAndOrderFront(nil) }
}

private struct RegionSelectView: View {
    let screenshot: CGImage
    let viewSize: CGSize
    let onDone: (CGImage?) -> Void
    @State private var start: CGPoint?
    @State private var current: CGPoint?

    var body: some View {
        ZStack {
            Image(decorative: screenshot, scale: 1)
                .resizable()
                .frame(width: viewSize.width, height: viewSize.height)
            Color.black.opacity(0.35)
            if let rect = selectionRect {
                Rectangle()
                    .path(in: rect)
                    .fill(Color.white.opacity(0.001))   // punch-through look kept simple
                Rectangle()
                    .path(in: rect)
                    .stroke(Color.white, lineWidth: 1.5)
            }
        }
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                if start == nil { start = v.startLocation }
                current = v.location
            }
            .onEnded { _ in finish() })
        .onExitCommand { onDone(nil) }   // Esc cancels
        .ignoresSafeArea()
    }

    private var selectionRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    private func finish() {
        guard let rect = selectionRect, rect.width > 4, rect.height > 4 else {
            return onDone(nil)
        }
        let scaleX = CGFloat(screenshot.width) / viewSize.width
        let scaleY = CGFloat(screenshot.height) / viewSize.height
        let pixelRect = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY,
                               width: rect.width * scaleX, height: rect.height * scaleY)
        onDone(screenshot.cropping(to: pixelRect))
    }
}
