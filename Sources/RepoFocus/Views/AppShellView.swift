import AppKit
import RepoFocusCore
import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case focus
    case activity
    case allRepositories
    case needsAttention
    case completed
    case settings

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .focus: language.text("Đang tập trung", "Focus")
        case .activity: language.text("Hoạt động", "Activity")
        case .allRepositories: language.text("Tất cả repo", "All Repositories")
        case .needsAttention: language.text("Cần chú ý", "Needs Attention")
        case .completed: language.text("Đã hoàn thành", "Completed")
        case .settings: language.text("Cài đặt", "Settings")
        }
    }

    func subtitle(_ language: AppLanguage) -> String {
        switch self {
        case .focus: language.text("Những repo quan trọng nhất lúc này", "The repositories that matter right now")
        case .activity: language.text("Push, commit và thay đổi theo từng branch", "Pushes, commits and changes by branch")
        case .allRepositories: language.text(
            "Repo từ GitHub, GitLab và các nguồn Git đã thêm",
            "Repositories from GitHub, GitLab, and added Git sources"
        )
        case .needsAttention: language.text("Repo đang bị chặn, quá hạn hoặc lâu chưa cập nhật", "Blocked, overdue or quiet for too long")
        case .completed: language.text("Công việc đã hoàn tất hoặc được lưu trữ", "Finished and archived work")
        case .settings: language.text("Kết nối GitHub/GitLab, giao diện và dữ liệu cục bộ", "GitHub/GitLab connections, appearance and local data")
        }
    }

    var symbol: String {
        switch self {
        case .focus: "scope"
        case .activity: "chart.bar.xaxis"
        case .allRepositories: "shippingbox"
        case .needsAttention: "exclamationmark.triangle"
        case .completed: "checkmark.circle"
        case .settings: "gearshape"
        }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    @State private var destination: SidebarDestination? = .focus
    @State private var selectedRepositoryID: String?
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsCloneSheet = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 440, ideal: 620)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        }
        .onAppear(perform: selectFirstRepositoryIfNeeded)
        .onChange(of: destination) {
            searchText = ""
            selectFirstRepositoryIfNeeded()
        }
        .onChange(of: store.repositories) {
            selectFirstRepositoryIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repoFocusOpenTodayFocus)) { _ in
            destination = .focus
            selectFirstRepositoryIfNeeded()
        }
        .sheet(isPresented: $showsCloneSheet) {
            CloneRepositorySheet(initialRepositoryID: selectedRepositoryID) { repositoryID in
                destination = .allRepositories
                selectedRepositoryID = repositoryID
            }
            .environmentObject(store)
            .environmentObject(preferences)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            AppBrandHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.compact) {
                    SidebarSectionLabel(
                        title: preferences.language.text("Không gian làm việc", "Workspace")
                    )

                    VStack(spacing: 3) {
                        ForEach(workspaceDestinations) { item in
                            SidebarMenuItem(
                                destination: item,
                                isSelected: destination == item,
                                badge: badgeCount(for: item)
                            ) {
                                destination = item
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, Layout.section)
            }

            Divider()

            SidebarMenuItem(
                destination: .settings,
                isSelected: destination == .settings,
                badge: nil
            ) {
                destination = .settings
            }
            .padding(.horizontal, 10)
            .padding(.vertical, Layout.compact)

            Divider()
            ConnectionFooter()
                .padding(Layout.regular)
        }
        .background(Color.sidebarBackground)
        .navigationTitle("RepoFocus")
    }

    private var workspaceDestinations: [SidebarDestination] {
        [.focus, .activity, .allRepositories, .needsAttention, .completed]
    }

    private func badgeCount(for destination: SidebarDestination) -> Int? {
        let count: Int
        switch destination {
        case .focus: count = store.focusedRepositories.count
        case .activity: count = store.activitySnapshot(for: .now)?.totalPushes ?? 0
        case .allRepositories: count = store.repositories.count
        case .needsAttention: count = store.needsAttentionRepositories.count
        case .completed: count = store.completedRepositories.count
        case .settings: count = 0
        }
        return count > 0 ? count : nil
    }

    @ViewBuilder
    private var content: some View {
        let currentDestination = destination ?? .focus

        VStack(spacing: 0) {
            ContentHeader(
                destination: currentDestination,
                searchText: $searchText,
                onClone: { showsCloneSheet = true }
            )

            Divider()

            switch currentDestination {
            case .focus:
                FocusDashboardView(
                    repositories: filter(store.focusedRepositories),
                    selectedRepositoryID: $selectedRepositoryID
                )
            case .activity:
                DailyActivityView()
            case .allRepositories:
                RepositoryCollectionView(
                    repositories: filter(store.repositories),
                    selectedRepositoryID: $selectedRepositoryID,
                    emptyTitle: preferences.language.text("Không tìm thấy repo", "No repositories found"),
                    emptyMessage: preferences.language.text("Hãy thử từ khóa khác hoặc kết nối tài khoản GitHub/GitLab.", "Try another search or connect your GitHub/GitLab account.")
                )
            case .needsAttention:
                RepositoryCollectionView(
                    repositories: filter(store.needsAttentionRepositories),
                    selectedRepositoryID: $selectedRepositoryID,
                    emptyTitle: preferences.language.text("Mọi thứ đang ổn", "Everything looks clear"),
                    emptyMessage: preferences.language.text("Không có repo ưu tiên nào bị chặn, quá hạn hoặc lâu chưa cập nhật.", "No focused repository is blocked, overdue or stale.")
                )
            case .completed:
                RepositoryCollectionView(
                    repositories: filter(store.completedRepositories),
                    selectedRepositoryID: $selectedRepositoryID,
                    emptyTitle: preferences.language.text("Chưa có repo hoàn thành", "Nothing completed yet"),
                    emptyMessage: preferences.language.text("Repo được đánh dấu Hoàn thành hoặc Đã lưu trữ sẽ xuất hiện tại đây.", "Repositories marked Done or Archived appear here.")
                )
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appCanvas)
    }

    @ViewBuilder
    private var inspector: some View {
        if destination == .settings {
            InspectorPlaceholder(
                symbol: "lock.shield",
                title: preferences.language.text("Ưu tiên dữ liệu cục bộ", "Local-first by design"),
                message: preferences.language.text("Trạng thái, tiến độ và ghi chú chỉ được lưu trên máy Mac này.", "Your focus status, progress and notes stay on this Mac.")
            )
        } else if destination == .activity {
            InspectorPlaceholder(
                symbol: "chart.bar.xaxis",
                title: preferences.language.text("Tổng quan theo ngày", "Daily overview"),
                message: preferences.language.text(
                    "Chọn một ngày để xem số lượt push, commit và nội dung thay đổi của từng branch.",
                    "Choose a date to review pushes, commits and changes for each branch."
                )
            )
        } else if let repository = store.repository(id: selectedRepositoryID) {
            RepositoryInspectorView(
                repository: repository,
                isFocusDestination: destination == .focus
            )
                .id(repository.id)
        } else {
            InspectorPlaceholder(
                symbol: "sidebar.right",
                title: preferences.language.text("Chọn một repo", "Select a repository"),
                message: preferences.language.text("Chọn repo để cập nhật trạng thái, tiến độ và việc cần làm tiếp theo.", "Choose a repository to update its focus, progress and next action.")
            )
        }
    }

    private func filter(_ repositories: [RepositoryRecord]) -> [RepositoryRecord] {
        guard !searchText.isEmpty else { return repositories }
        return repositories.filter {
            $0.github.nameWithOwner.localizedCaseInsensitiveContains(searchText)
                || ($0.github.description?.localizedCaseInsensitiveContains(searchText) ?? false)
                || $0.tracking.nextAction.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func selectFirstRepositoryIfNeeded() {
        guard destination != .settings && destination != .activity else {
            selectedRepositoryID = nil
            return
        }

        let available: [RepositoryRecord]
        switch destination ?? .focus {
        case .focus: available = store.focusedRepositories
        case .activity: available = []
        case .allRepositories: available = store.repositories
        case .needsAttention: available = store.needsAttentionRepositories
        case .completed: available = store.completedRepositories
        case .settings: available = []
        }

        if !available.contains(where: { $0.id == selectedRepositoryID }) {
            selectedRepositoryID = available.first?.id
        }
    }
}

private struct AppBrandHeader: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.13), radius: 2, y: 1)

            Text("RepoFocus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.sidebarBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RepoFocus")
    }
}

private struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .frame(height: 20, alignment: .leading)
    }
}

private struct SidebarMenuItem: View {
    @EnvironmentObject private var preferences: AppPreferences
    let destination: SidebarDestination
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            menuLabel
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .help(destination.subtitle(preferences.language))
        .accessibilityLabel(destination.title(preferences.language))
        .accessibilityValue(isSelected
            ? preferences.language.text("Đang chọn", "Selected")
            : "")
    }

    private var menuLabel: some View {
        HStack(spacing: 9) {
            menuIcon

            Text(destination.title(preferences.language))
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer(minLength: 5)

            if let badge {
                SidebarCountBadge(value: badge, isSelected: isSelected)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 38)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) { selectionIndicator }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selectionBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var menuIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(iconBackground)
            Image(systemName: destination.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 18)
                .padding(.leading, 1)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.105) }
        if isHovered { return Color.primary.opacity(0.045) }
        return .clear
    }

    private var iconBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        return Color.primary.opacity(isHovered ? 0.07 : 0.045)
    }

    private var iconColor: Color {
        isSelected ? .accentColor : .secondary
    }

    private var selectionBorder: Color {
        isSelected ? Color.accentColor.opacity(0.16) : .clear
    }
}

private struct SidebarCountBadge: View {
    let value: Int
    let isSelected: Bool

    var body: some View {
        Text(value > 99 ? "99+" : "\(value)")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22)
            .frame(height: 19)
            .background(badgeBackground)
            .clipShape(Capsule())
    }

    private var badgeBackground: Color {
        isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.055)
    }
}

private struct ContentHeader: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    let destination: SidebarDestination
    @Binding var searchText: String
    let onClone: () -> Void

    var body: some View {
        HStack(spacing: Layout.section) {
            VStack(alignment: .leading, spacing: Layout.grid) {
                Text(destination.title(preferences.language))
                    .font(.system(size: 21, weight: .semibold))
                Text(destination.subtitle(preferences.language))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Layout.section)

            if destination != .settings && destination != .activity {
                Button(action: onClone) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(FocusButtonStyle(role: .icon))
                .help(preferences.language.text("Clone repository về máy", "Clone a repository to this Mac"))

                FocusTextInput(
                    placeholder: preferences.language.text("Tìm repo", "Search repositories"),
                    text: $searchText,
                    leadingSymbol: "magnifyingglass",
                    showsClearButton: true
                )
                    .frame(width: 210)

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isSyncingSources {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(FocusButtonStyle(role: .icon))
                .help(preferences.language.text("Đồng bộ GitHub và GitLab (⌘R)", "Sync GitHub and GitLab (⌘R)"))
                .disabled(store.isSyncingSources)
            }
        }
        .padding(.horizontal, Layout.section)
        .padding(.vertical, Layout.regular)
        .background(Color.headerBackground)
    }
}

private struct ConnectionFooter: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        HStack(spacing: Layout.compact) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if let lastSyncAt = store.lastSyncAt {
                    Text(preferences.language.text(
                        "Đồng bộ \(preferences.language.relativeDate(from: lastSyncAt))",
                        "Synced \(preferences.language.relativeDate(from: lastSyncAt))"
                    ))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var indicatorColor: Color {
        if store.isSyncingSources { return .blue }
        if isGitHubConnected || isGitLabConnected { return .green }
        if case .failed = store.connectionState { return .red }
        if case .failed = store.gitLabConnectionState { return .red }
        return .orange
    }

    private var label: String {
        if store.isSyncingSources {
            return preferences.language.text("Đang đồng bộ…", "Syncing…")
        }
        if isGitHubConnected && isGitLabConnected {
            return preferences.language.text("Đã kết nối GitHub + GitLab", "GitHub + GitLab connected")
        }
        if isGitHubConnected {
            return preferences.language.text("Đã kết nối GitHub", "GitHub connected")
        }
        if isGitLabConnected {
            return preferences.language.text("Đã kết nối GitLab", "GitLab connected")
        }
        if store.isUsingSampleData {
            return preferences.language.text("Dữ liệu mẫu", "Sample workspace")
        }
        return preferences.language.text("Không gian cục bộ", "Local workspace")
    }

    private var isGitHubConnected: Bool {
        store.connectionState == .connected || store.connectionState == .ready
    }

    private var isGitLabConnected: Bool {
        store.gitLabConnectionState == .connected || store.gitLabConnectionState == .ready
    }
}

private struct InspectorPlaceholder: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCanvas)
    }
}
