import RepoFocusCore
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese
    case english

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: self == .vietnamese ? "vi_VN" : "en_US")
    }

    func text(_ vietnamese: String, _ english: String) -> String {
        self == .vietnamese ? vietnamese : english
    }

    func relativeDate(from date: Date, relativeTo referenceDate: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    init() {
        theme = AppTheme(
            rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? ""
        ) ?? .system
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Keys.language) ?? ""
        ) ?? .vietnamese
    }

    private enum Keys {
        static let theme = "appearance.theme"
        static let language = "appearance.language"
    }
}

extension WorkStatus {
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .inbox: language.text("Chưa phân loại", "Inbox")
        case .planned: language.text("Đã lên kế hoạch", "Planned")
        case .active: language.text("Đang làm", "Active")
        case .blocked: language.text("Đang bị chặn", "Blocked")
        case .paused: language.text("Tạm dừng", "Paused")
        case .done: language.text("Hoàn thành", "Done")
        case .archived: language.text("Đã lưu trữ", "Archived")
        }
    }
}

extension WorkPriority {
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .low: language.text("Thấp", "Low")
        case .medium: language.text("Vừa", "Medium")
        case .high: language.text("Cao", "High")
        }
    }
}
