import AppKit
import SwiftUI

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

final class RegionSelectWindow: NSPanel {
    private var finished = false
    private var onSelect: ((CGImage?) -> Void)?

    init(screenshot: CGImage, screen: NSScreen, onSelect: @escaping (CGImage?) -> Void) {
        let screenFrame = screen.frame
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.onSelect = onSelect
        level = .screenSaver
        isOpaque = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = FirstMouseHostingView(rootView: RegionSelectView(
            screenshot: screenshot,
            viewSize: screenFrame.size,
            onDone: { [weak self] image in
                self?.finish(image)
            }))
    }

    override var canBecomeKey: Bool { true }

    func begin() {
        NSCursor.crosshair.push()
        makeKeyAndOrderFront(nil)
    }

    func finish(_ image: CGImage?) {
        guard !finished else { return }
        finished = true
        NSCursor.pop()
        orderOut(nil)
        onSelect?(image)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            finish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        finish(nil)
    }

    override func rightMouseDown(with event: NSEvent) {
        finish(nil)
    }

    override func resignKey() {
        super.resignKey()
        finish(nil)
    }
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
            VStack {
                Text("Drag to select · Esc to cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(.top, 60)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in
                if start == nil { start = v.startLocation }
                current = v.location
            }
            .onEnded { _ in finish() })
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
