import AppKit
import SwiftUI

@MainActor
enum CaptureController {
    private static var regionWindow: RegionSelectWindow?
    private static var capturePanel: FloatingPanel?

    static func begin(state: AppState) {
        // Re-entrancy guard: a region-select window or capture note panel is
        // already open, so ignore this ⌃⇧S press rather than opening a second.
        guard regionWindow == nil, capturePanel == nil else { return }
        guard ScreenCapturer.hasPermission() else {
            showPermissionExplainer()
            return
        }
        Task {
            do {
                let screenshot = try await ScreenCapturer.captureMainDisplay()
                let window = RegionSelectWindow(screenshot: screenshot) { cropped in
                    regionWindow = nil
                    guard let cropped else { return }
                    presentCaptureWindow(image: cropped, state: state)
                }
                regionWindow = window
                window.begin()
            } catch {
                state.lastError = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    static func presentCaptureWindow(image: CGImage, state: AppState) {
        let displayWidth: CGFloat = 640 + 28
        let height = CGFloat(image.height) * (640 / CGFloat(image.width)) + 160
        let panel = FloatingPanel(
            view: CaptureNoteView(image: image, state: state, dismiss: {
                capturePanel?.close()
                capturePanel = nil
            }),
            width: displayWidth, height: height)
        capturePanel = panel
        panel.show()
    }

    private static func showPermissionExplainer() {
        ScreenCapturer.requestPermission()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "MeetingNotes needs Screen Recording access to capture screenshots. Grant it in System Settings, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}
