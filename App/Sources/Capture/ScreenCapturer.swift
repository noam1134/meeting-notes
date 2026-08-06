import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCapturer {
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }
    static func requestPermission() { CGRequestScreenCaptureAccess() }

    @MainActor
    static func captureDisplay(containing point: CGPoint) async throws -> (image: CGImage, screen: NSScreen) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else {
            throw NSError(domain: "MeetingNotes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw NSError(domain: "MeetingNotes", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No display id for screen"])
        }
        let displayID = CGDirectDisplayID(truncating: screenNumber)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "MeetingNotes", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Display \(displayID) not capturable"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, screen)
    }
}
