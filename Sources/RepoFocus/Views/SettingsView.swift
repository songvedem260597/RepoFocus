import RepoFocusCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var reminderService: ProjectReminderService
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.large) {
                appearanceCard
                reminderCard
                githubConnectionCard
                gitLabConnectionCard
                dataCard
                securityNote
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(Layout.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appCanvas)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            HStack(spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Nhắc việc hôm nay", "Today reminders"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(preferences.language.text(
                        "Biết repo và branch nào cần được xử lý trong ngày.",
                        "Know which repositories and branches need attention today."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            FocusCheckbox(
                title: preferences.language.text("Nhắc tôi mỗi ngày", "Remind me every day"),
                isOn: $preferences.remindersEnabled
            )

            Text(preferences.language.text(
                "Thông báo gồm các dự án đang tập trung, branch hiện tại, việc tiếp theo và cảnh báo đến hạn, bị chặn hoặc conflict.",
                "Notifications include focused projects, current branches, next actions, deadlines, blockers and conflicts."
            ))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Layout.regular) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preferences.language.text("Giờ nhắc", "Reminder time"))
                        .font(.system(size: 10.5, weight: .semibold))
                    ReminderTimeInput(minutes: $preferences.reminderTimeMinutes)
                        .disabled(!preferences.remindersEnabled)
                }

                Spacer()

                Button {
                    Task {
                        _ = await reminderService.sendTestNotification(
                            items: store.todayReminderItems(),
                            language: preferences.language
                        )
                    }
                } label: {
                    Label(
                        preferences.language.text("Gửi thử", "Send test"),
                        systemImage: "paperplane.fill"
                    )
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))
            }

            Label(authorizationMessage, systemImage: authorizationSymbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(authorizationColor)
        }
        .padding(Layout.section)
        .panelStyle()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            HStack(spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(.purple)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Giao diện và ngôn ngữ", "Appearance and language"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(preferences.language.text(
                        "Tùy chỉnh RepoFocus theo cách bạn làm việc.",
                        "Make RepoFocus feel right for your workspace."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: Layout.compact) {
                Text(preferences.language.text("Chủ đề", "Theme"))
                    .font(.system(size: 11, weight: .semibold))

                HStack(spacing: 6) {
                    ForEach(AppTheme.allCases) { theme in
                        choiceButton(
                            title: themeTitle(theme),
                            symbol: theme.symbol,
                            isSelected: preferences.theme == theme
                        ) {
                            preferences.theme = theme
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Layout.compact) {
                Text(preferences.language.text("Ngôn ngữ", "Language"))
                    .font(.system(size: 11, weight: .semibold))

                HStack(spacing: 6) {
                    ForEach(AppLanguage.allCases) { language in
                        choiceButton(
                            title: language == .vietnamese ? "Tiếng Việt" : "English",
                            symbol: language == .vietnamese ? "textformat.abc" : "character.book.closed",
                            isSelected: preferences.language == language
                        ) {
                            preferences.language = language
                        }
                    }
                }
            }
        }
        .padding(Layout.section)
        .panelStyle()
    }

    private var githubConnectionCard: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            HStack(spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "link")
                            .foregroundStyle(.blue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Kết nối GitHub", "GitHub connection"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(gitHubConnectionDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: Layout.regular) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.language.text(
                        "Dùng tài khoản GitHub CLI đang đăng nhập",
                        "Use the signed-in GitHub CLI account"
                    ))
                        .font(.system(size: 11, weight: .semibold))
                    Text(preferences.language.text(
                        "RepoFocus đọc phiên `gh auth` hiện có và không lưu thêm token riêng, vì vậy macOS sẽ không hiện hộp thoại xin quyền Keychain.",
                        "RepoFocus reads the existing `gh auth` session and stores no separate token, so macOS will not show a Keychain permission dialog."
                    ))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Layout.compact) {
                Button {
                    Task { await store.connectUsingCurrentCredentials() }
                } label: {
                    if store.connectionState == .syncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(store.connectionState == .connected
                            ? preferences.language.text("Đồng bộ ngay", "Sync now")
                            : preferences.language.text("Kết nối tài khoản hiện tại", "Connect current account"))
                    }
                }
                .buttonStyle(FocusButtonStyle(role: .primary))
                .disabled(store.connectionState == .syncing)

                Spacer()

                if store.connectionState == .connected || store.connectionState == .ready {
                    Button(preferences.language.text("Ngắt kết nối", "Disconnect"), role: .destructive) {
                        store.disconnect()
                    }
                    .buttonStyle(FocusButtonStyle(role: .destructive))
                }
            }

            if case .failed(let message) = store.connectionState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(Layout.section)
        .panelStyle()
    }

    private var gitLabConnectionCard: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            HStack(spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: RepositoryProvider.gitlab.symbolName)
                            .foregroundStyle(.orange)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Kết nối GitLab", "GitLab connection"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(gitLabConnectionDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: Layout.regular) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.language.text(
                        "Dùng tài khoản GitLab CLI đang đăng nhập",
                        "Use the signed-in GitLab CLI account"
                    ))
                        .font(.system(size: 11, weight: .semibold))
                    Text(preferences.language.text(
                        "RepoFocus gọi `glab api` trực tiếp, không đọc hoặc lưu bản sao token. Repo GitLab vẫn có thể clone bằng URL khi chưa kết nối tài khoản.",
                        "RepoFocus calls `glab api` directly and never reads or stores a token copy. GitLab repositories can still be cloned by URL without an account connection."
                    ))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.gitLabConnectionState == .unavailable {
                VStack(alignment: .leading, spacing: Layout.compact) {
                    Label(
                        preferences.language.text(
                            "Máy chưa có lệnh `glab`. Cài GitLab CLI rồi chạy `glab auth login` để nhập repo từ tài khoản.",
                            "The `glab` command is not installed. Install GitLab CLI and run `glab auth login` to import account repositories."
                        ),
                        systemImage: "info.circle"
                    )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: "https://docs.gitlab.com/cli/") {
                            openURL(url)
                        }
                    } label: {
                        Label(
                            preferences.language.text("Xem hướng dẫn cài GitLab CLI", "View GitLab CLI installation"),
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    .buttonStyle(FocusButtonStyle(role: .secondary))
                }
            } else {
                HStack(spacing: Layout.compact) {
                    Button {
                        Task { await store.connectGitLabUsingCurrentCredentials() }
                    } label: {
                        if store.gitLabConnectionState == .syncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(store.gitLabConnectionState == .connected
                                ? preferences.language.text("Đồng bộ ngay", "Sync now")
                                : preferences.language.text("Kết nối tài khoản hiện tại", "Connect current account"))
                        }
                    }
                    .buttonStyle(FocusButtonStyle(role: .primary))
                    .disabled(store.gitLabConnectionState == .syncing)

                    Spacer()

                    if store.gitLabConnectionState == .connected || store.gitLabConnectionState == .ready {
                        Button(preferences.language.text("Ngắt kết nối", "Disconnect"), role: .destructive) {
                            store.disconnectGitLab()
                        }
                        .buttonStyle(FocusButtonStyle(role: .destructive))
                    }
                }
            }

            if case .failed(let message) = store.gitLabConnectionState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(Layout.section)
        .panelStyle()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: Layout.section) {
            Text(preferences.language.text("Dữ liệu trên máy", "Local workspace"))
                .font(.system(size: 14, weight: .semibold))

            LabeledContent(preferences.language.text("Số repo", "Repositories")) {
                Text("\(store.repositories.count)")
                    .monospacedDigit()
            }

            LabeledContent(preferences.language.text("Đang tập trung", "Focused")) {
                Text("\(store.focusedRepositories.count)")
                    .monospacedDigit()
            }

            if let lastSyncAt = store.lastSyncAt {
                LabeledContent(preferences.language.text("Lần đồng bộ nguồn gần nhất", "Last source sync")) {
                    Text(lastSyncAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                }
            }
        }
        .font(.system(size: 11))
        .padding(Layout.section)
        .panelStyle()
    }

    private var securityNote: some View {
        Label {
            Text(preferences.language.text(
                "RepoFocus không lưu bản sao token GitHub hoặc GitLab. Trạng thái, tiến độ, hạn chót và ghi chú chỉ nằm trong Application Support trên máy Mac này.",
                "RepoFocus stores no copy of GitHub or GitLab tokens. Focus status, progress, deadlines and notes stay in Application Support on this Mac."
            ))
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var gitHubConnectionDescription: String {
        switch store.connectionState {
        case .sampleData:
            store.isUsingSampleData
                ? preferences.language.text("Chưa kết nối — đang hiển thị dữ liệu mẫu", "Not connected — sample data is currently shown")
                : preferences.language.text("Đã ngắt kết nối — repo đã lưu vẫn dùng được", "Disconnected — cached repositories remain available")
        case .ready: preferences.language.text("Đã tìm thấy phiên GitHub CLI", "GitHub CLI session found")
        case .syncing: preferences.language.text("Đang nhập repo từ GitHub…", "Importing repositories from GitHub…")
        case .connected: preferences.language.text("Đã kết nối, sẵn sàng sử dụng", "Connected and ready")
        case .failed: preferences.language.text("Lần kết nối gần nhất không thành công", "The most recent connection attempt failed")
        }
    }

    private var gitLabConnectionDescription: String {
        switch store.gitLabConnectionState {
        case .unavailable:
            preferences.language.text("Chưa cài GitLab CLI", "GitLab CLI is not installed")
        case .disconnected:
            preferences.language.text("Chưa kết nối — repo GitLab đã lưu vẫn dùng được", "Not connected — cached GitLab repositories remain available")
        case .ready:
            preferences.language.text("Đã tìm thấy phiên GitLab CLI", "GitLab CLI session found")
        case .syncing:
            preferences.language.text("Đang nhập repo từ GitLab…", "Importing repositories from GitLab…")
        case .connected:
            preferences.language.text("Đã kết nối, sẵn sàng sử dụng", "Connected and ready")
        case .failed:
            preferences.language.text("Lần kết nối gần nhất không thành công", "The most recent connection attempt failed")
        }
    }

    private var authorizationMessage: String {
        switch reminderService.authorizationState {
        case .unknown, .notRequested:
            preferences.language.text(
                "macOS sẽ hỏi quyền khi bạn bật nhắc việc hoặc gửi thử.",
                "macOS will ask for permission when you enable reminders or send a test."
            )
        case .authorized:
            preferences.remindersEnabled
                ? preferences.language.text("Thông báo hằng ngày đã sẵn sàng.", "Daily notifications are ready.")
                : preferences.language.text("macOS đã cho phép thông báo.", "Notifications are allowed by macOS.")
        case .denied:
            preferences.language.text(
                "Thông báo đang bị tắt trong Cài đặt hệ thống của macOS.",
                "Notifications are disabled in macOS System Settings."
            )
        case .failed(let message): message
        }
    }

    private var authorizationSymbol: String {
        switch reminderService.authorizationState {
        case .authorized: "checkmark.circle.fill"
        case .denied, .failed: "exclamationmark.triangle.fill"
        case .unknown, .notRequested: "info.circle"
        }
    }

    private var authorizationColor: Color {
        switch reminderService.authorizationState {
        case .authorized: .green
        case .denied, .failed: .red
        case .unknown, .notRequested: .secondary
        }
    }

    private func themeTitle(_ theme: AppTheme) -> String {
        switch theme {
        case .system: preferences.language.text("Theo hệ thống", "System")
        case .light: preferences.language.text("Sáng", "Light")
        case .dark: preferences.language.text("Tối", "Dark")
        }
    }

    private func choiceButton(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.quietBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderTimeInput: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Button { adjust(-30) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .help(preferences.language.text("Sớm hơn 30 phút", "30 minutes earlier"))
            .disabled(minutes <= 0)

            Text(timeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 58, height: 32)
                .background(Color.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                        .stroke(Color.quietBorder, lineWidth: 1)
                }

            Button { adjust(30) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .help(preferences.language.text("Muộn hơn 30 phút", "30 minutes later"))
            .disabled(minutes >= 1_439)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preferences.language.text("Giờ nhắc", "Reminder time"))
        .accessibilityValue(timeText)
    }

    private var timeText: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func adjust(_ amount: Int) {
        minutes = min(max(minutes + amount, 0), 1_439)
    }
}
