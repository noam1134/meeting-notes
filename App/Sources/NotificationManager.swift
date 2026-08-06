import UserNotifications

// Schedules/refreshes the "N meeting sessions waiting for processing"
// morning reminder (daily 09:00 local) and removes it once nothing is
// pending. Kept as static functions over UNUserNotificationCenter.current()
// so AppState can call it without owning a notification-center instance.
enum NotificationManager {
    static let reminderIdentifier = "com.noamchuri.MeetingNotes.morningReminder"

    // Pure text builder — the only part of this file worth unit-testing
    // without a real UNUserNotificationCenter.
    static func reminderBody(pendingCount: Int) -> String {
        "\(pendingCount) meeting session\(pendingCount == 1 ? "" : "s") waiting for processing"
    }

    static func morningTrigger() -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    // Requests permission only the first time (status .notDetermined);
    // otherwise reports the existing authorization state.
    static func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .authorized, .provisional:
                DispatchQueue.main.async { completion(true) }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // Replaces the pending reminder request with one reflecting the current
    // count, or removes it entirely when disabled or nothing is pending.
    static func refresh(enabled: Bool, pendingCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        guard enabled, pendingCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "MeetingNotes"
        content.body = reminderBody(pendingCount: pendingCount)
        content.sound = .default

        let request = UNNotificationRequest(identifier: reminderIdentifier,
                                            content: content,
                                            trigger: morningTrigger())
        center.add(request)
    }
}
