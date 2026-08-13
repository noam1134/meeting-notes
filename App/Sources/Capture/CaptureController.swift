import AppKit
import SwiftUI

// Where a finished capture lands: a brand-new note (⌃⇧S) or an existing one
// ("Add Screenshot…" on a note card).
enum CaptureDestination {
    case newNote
    case existingNote(id: UUID, folder: URL)
}

@MainActor
enum CaptureController {
    private static var regionWindow: RegionSelectWindow?
    private static var capturePanel: FloatingPanel?

    static func begin(state: AppState, destination: CaptureDestination = .newNote) {
        // Re-entrancy guard: a region-select window or capture note panel is
        // already open, so ignore this ⌃⇧S press rather than opening a second.
        guard regionWindow == nil, capturePanel == nil else { return }
        // Only capture-from-a-note runs with the browser on screen; the ⌃⇧S
        // path is usually invoked while it's already hidden.
        let hidBrowser: Bool
        if case .existingNote = destination, BrowserWindowController.shared.isVisible {
            BrowserWindowController.shared.hide()
            hidBrowser = true
        } else {
            hidBrowser = false
        }
        let restoreBrowser = { if hidBrowser { BrowserWindowController.shared.restore() } }
        let mouse = NSEvent.mouseLocation
        Task {
            do {
                // orderOut returns before the compositor has actually dropped the
                // window, so grabbing the display immediately still catches it.
                if hidBrowser { try? await Task.sleep(nanoseconds: 150_000_000) }
                // Attempt-first: CGPreflightScreenCaptureAccess() is known to
                // return stale `false` on macOS 14/15 even when TCC has
                // already granted access, so don't gate on it up front.
                let (screenshot, screen) = try await ScreenCapturer.captureDisplay(containing: mouse)
                let window = RegionSelectWindow(screenshot: screenshot, screen: screen) { cropped in
                    regionWindow = nil
                    guard let cropped else { return restoreBrowser() }
                    presentCaptureWindow(image: cropped, state: state,
                                         destination: destination, onDismiss: restoreBrowser)
                }
                regionWindow = window
                window.begin()
            } catch {
                restoreBrowser()
                if isPermissionError(error) {
                    showPermissionExplainer()
                } else {
                    state.lastError = "Capture failed: \(String(describing: error)) [preflight=\(ScreenCapturer.hasPermission())]"
                }
            }
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain.contains("SCStream"), nsError.code == -3801 || nsError.code == -3802 {
            return true
        }
        if nsError.domain == "com.apple.screencapturekit" {
            return true
        }
        let description = String(describing: error).lowercased()
        return description.contains("declined")
            || description.contains("not permitted")
            || description.contains("tcc")
    }

    static func presentCaptureWindow(image: CGImage, state: AppState,
                                     destination: CaptureDestination = .newNote,
                                     onDismiss: @escaping () -> Void = {}) {
        // Fit the captured image within a max display box, same logic as
        // CaptureNoteView.displaySize, so the panel matches the rendered view.
        let maxDisplay = CGSize(width: 640, height: 400)
        let scale = min(maxDisplay.width / CGFloat(image.width),
                        maxDisplay.height / CGFloat(image.height),
                        1.0)
        let displaySize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let width = max(displaySize.width + 28, 480)
        let panel = FloatingPanel(
            view: CaptureNoteView(image: image, state: state, destination: destination, dismiss: {
                capturePanel?.close()
                capturePanel = nil
                onDismiss()
            }),
            width: width, movableByBackground: false)
        capturePanel = panel
        panel.show()
    }

    private static func showPermissionExplainer() {
        if !ScreenCapturer.hasPermission() {
            ScreenCapturer.requestPermission()
        }
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "MeetingNotes needs Screen Recording access to capture screenshots. Grant it in System Settings, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}
