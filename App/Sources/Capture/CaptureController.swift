import AppKit
import SwiftUI

@MainActor
enum CaptureController {
    private static var regionWindow: RegionSelectWindow?

    static func begin(state: AppState) {
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

    // Task 9 replaces this stub with the annotate+note window.
    static func presentCaptureWindow(image: CGImage, state: AppState) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        if state.activeSession == nil { state.startMeeting(named: nil) }
        state.addNote(text: "(screenshot)", category: state.settings.categories.first ?? "FYI",
                      imageData: png)
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
