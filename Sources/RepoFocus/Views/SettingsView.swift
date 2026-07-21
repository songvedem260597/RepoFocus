import RepoFocusCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.large) {
                appearanceCard
                connectionCard
                dataCard
                securityNote
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(Layout.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appCanvas)
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

    private var connectionCard: some View {
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
                    Text(connectionDescription)
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
                LabeledContent(preferences.language.text("Lần đồng bộ gần nhất", "Last GitHub sync")) {
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
                "RepoFocus không lưu bản sao token GitHub. Trạng thái, tiến độ, hạn chót và ghi chú chỉ nằm trong Application Support trên máy Mac này.",
                "RepoFocus stores no copy of your GitHub token. Focus status, progress, deadlines and notes stay in Application Support on this Mac."
            ))
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var connectionDescription: String {
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
