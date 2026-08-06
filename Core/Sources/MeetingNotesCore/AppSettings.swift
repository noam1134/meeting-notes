import Foundation

public struct AppSettings: Equatable {
    public static let defaultCategories = ["Trello task", "Decision", "Question", "FYI"]
    private static let key = "categories"

    public var categories: [String]

    public init(categories: [String]) {
        self.categories = categories
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        let saved = defaults.stringArray(forKey: key) ?? []
        return AppSettings(categories: saved.isEmpty ? defaultCategories : saved)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(categories, forKey: Self.key)
    }
}
