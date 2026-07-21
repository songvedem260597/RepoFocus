import AppKit
import RepoFocusCore
import SwiftUI
import UserNotifications

enum ReminderAuthorizationState: Equatable {
    case unknown
    case notRequested
    case authorized
    case denied
    case failed(String)
}

@MainActor
final class ProjectReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationState: ReminderAuthorizationState = .unknown

    private let center: UNUserNotificationCenter
    private let dailyIdentifier = "repofocus.today-reminder"

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func refreshAuthorizationState() async {
        let settings = await center.notificationSettings()
        authorizationState = Self.state(for: settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationState()
        switch authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .unknown, .notRequested, .failed:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationState()
                return granted
            } catch {
                authorizationState = .failed(error.localizedDescription)
                return false
            }
        }
    }

    func scheduleDailyReminder(
        items: [RepositoryReminderItem],
        minutesFromMidnight: Int,
        language: AppLanguage
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
        await refreshAuthorizationState()
        guard authorizationState == .authorized, !items.isEmpty else { return }

        let normalizedMinutes = min(max(minutesFromMidnight, 0), 1_439)
        var components = DateComponents()
        components.hour = normalizedMinutes / 60
        components.minute = normalizedMinutes % 60

        let content = makeContent(items: items, language: language, isTest: false)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    @discardableResult
    func sendTestNotification(
        items: [RepositoryReminderItem],
        language: AppLanguage
    ) async -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }

        let content = makeContent(items: items, language: language, isTest: true)
        let request = UNNotificationRequest(
            identifier: "repofocus.reminder-test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            authorizationState = .failed(error.localizedDescription)
            return false
        }
    }

    func updateDockBadge(count: Int, isEnabled: Bool) {
        NSApplication.shared.dockTile.badgeLabel = isEnabled && count > 0 ? String(count) : nil
    }

    private func makeContent(
        items: [RepositoryReminderItem],
        language: AppLanguage,
        isTest: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let count = items.count
        content.title = isTest
            ? language.text("Thông báo thử · RepoFocus", "Test notification · RepoFocus")
            : language.text("Hôm nay cần xử lý \(count) dự án", "\(count) projects need attention today")

        if items.isEmpty {
            content.body = language.text(
                "Hiện chưa có dự án nào trong danh sách tập trung.",
                "There are no projects in your focus list yet."
            )
        } else {
            let visibleItems = items.prefix(3).map { item in
                let branch = item.branchName.map { " · \($0)" } ?? ""
                return "\(item.repositoryName)\(branch): \(summary(for: item, language: language))"
            }
            let remaining = max(items.count - visibleItems.count, 0)
            var lines = visibleItems
            if remaining > 0 {
                lines.append(language.text("và \(remaining) dự án khác", "and \(remaining) more"))
            }
            content.body = lines.joined(separator: "\n")
        }

        content.sound = .default
        content.badge = NSNumber(value: count)
        content.threadIdentifier = "repofocus.today"
        content.userInfo = ["destination": "focus"]
        return content
    }

    private func summary(for item: RepositoryReminderItem, language: AppLanguage) -> String {
        if let reason = item.reasons.first {
            return reason.title(language)
        }
        if !item.nextAction.isEmpty {
            return item.nextAction
        }
        return language.text("Cần xác định việc tiếp theo", "Choose the next action")
    }

    private static func state(for status: UNAuthorizationStatus) -> ReminderAuthorizationState {
        switch status {
        case .notDetermined: .notRequested
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unknown
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .repoFocusOpenTodayFocus, object: nil)
            completionHandler()
        }
    }
}

extension Notification.Name {
    static let repoFocusOpenTodayFocus = Notification.Name("RepoFocusOpenTodayFocus")
}

extension RepositoryReminderReason {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .overdue: language.text("Đã quá hạn", "Overdue")
        case .dueToday: language.text("Đến hạn hôm nay", "Due today")
        case .blocked: language.text("Đang bị chặn", "Blocked")
        case .conflicts: language.text("Có conflict cần xử lý", "Merge conflicts need attention")
        }
    }

    var symbol: String {
        switch self {
        case .overdue: "calendar.badge.exclamationmark"
        case .dueToday: "calendar.badge.clock"
        case .blocked: "exclamationmark.octagon.fill"
        case .conflicts: "arrow.trianglehead.branch"
        }
    }

    var color: Color {
        switch self {
        case .overdue, .blocked, .conflicts: .red
        case .dueToday: .orange
        }
    }
}
