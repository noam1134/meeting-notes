import Foundation

public struct AppSettings: Equatable {
    public static let defaultCategories = ["Trello task", "Decision", "Question", "FYI"]
    private static let key = "categories"
    private static let morningReminderKey = "morningReminderEnabled"

    public var categories: [String]
    public var morningReminderEnabled: Bool

    public init(categories: [String], morningReminderEnabled: Bool = true) {
        self.categories = categories
        self.morningReminderEnabled = morningReminderEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        let saved = defaults.stringArray(forKey: key) ?? []
        let morningReminderEnabled = defaults.object(forKey: morningReminderKey) as? Bool ?? true
        return AppSettings(categories: saved.isEmpty ? defaultCategories : saved,
                            morningReminderEnabled: morningReminderEnabled)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(categories, forKey: Self.key)
        defaults.set(morningReminderEnabled, forKey: Self.morningReminderKey)
    }
}
