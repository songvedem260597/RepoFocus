import RepoFocusCore
import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case focus
    case allRepositories
    case needsAttention
    case completed
    case settings

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .focus: language.text("Đang tập trung", "Focus")
        case .allRepositories: language.text("Tất cả repo", "All Repositories")
        case .needsAttention: language.text("Cần chú ý", "Needs Attention")
        case .completed: language.text("Đã hoàn thành", "Completed")
        case .settings: language.text("Cài đặt", "Settings")
        }
    }

    func subtitle(_ language: AppLanguage) -> String {
        switch self {
        case .focus: language.text("Những repo quan trọng nhất lúc này", "The repositories that matter right now")
        case .allRepositories: language.text("Toàn bộ repo mà tài khoản có quyền truy cập", "Every repository available to this account")
        case .needsAttention: language.text("Repo đang bị chặn, quá hạn hoặc lâu chưa cập nhật", "Blocked, overdue or quiet for too long")
        case .completed: language.text("Công việc đã hoàn tất hoặc được lưu trữ", "Finished and archived work")
        case .settings: language.text("Kết nối GitHub, giao diện và dữ liệu cục bộ", "GitHub connection, appearance and local data")
        }
    }

    var symbol: String {
        switch self {
        case .focus: "scope"
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
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $destination) {
                Section {
                    Label(SidebarDestination.focus.title(preferences.language), systemImage: SidebarDestination.focus.symbol)
                        .tag(SidebarDestination.focus)
                    Label(SidebarDestination.allRepositories.title(preferences.language), systemImage: SidebarDestination.allRepositories.symbol)
                        .tag(SidebarDestination.allRepositories)
                    Label(SidebarDestination.needsAttention.title(preferences.language), systemImage: SidebarDestination.needsAttention.symbol)
                        .tag(SidebarDestination.needsAttention)
                    Label(SidebarDestination.completed.title(preferences.language), systemImage: SidebarDestination.completed.symbol)
                        .tag(SidebarDestination.completed)
                }

                Section {
                    Label(SidebarDestination.settings.title(preferences.language), systemImage: SidebarDestination.settings.symbol)
                        .tag(SidebarDestination.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.sidebarBackground)

            Divider()
            ConnectionFooter()
                .padding(Layout.regular)
        }
        .background(Color.sidebarBackground)
        .navigationTitle("RepoFocus")
    }

    @ViewBuilder
    private var content: some View {
        let currentDestination = destination ?? .focus

        VStack(spacing: 0) {
            ContentHeader(
                destination: currentDestination,
                searchText: $searchText
            )

            Divider()

            switch currentDestination {
            case .focus:
                FocusDashboardView(
                    repositories: filter(store.focusedRepositories),
                    selectedRepositoryID: $selectedRepositoryID
                )
            case .allRepositories:
                RepositoryCollectionView(
                    repositories: filter(store.repositories),
                    selectedRepositoryID: $selectedRepositoryID,
                    emptyTitle: preferences.language.text("Không tìm thấy repo", "No repositories found"),
                    emptyMessage: preferences.language.text("Hãy thử từ khóa khác hoặc kết nối tài khoản GitHub.", "Try another search or connect your GitHub account.")
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
        } else if let repository = store.repository(id: selectedRepositoryID) {
            RepositoryInspectorView(repository: repository)
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
        guard destination != .settings else {
            selectedRepositoryID = nil
            return
        }

        let available: [RepositoryRecord]
        switch destination ?? .focus {
        case .focus: available = store.focusedRepositories
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

private struct ContentHeader: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    let destination: SidebarDestination
    @Binding var searchText: String

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

            if destination != .settings {
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
                    if store.connectionState == .syncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(FocusButtonStyle(role: .icon))
                .help(preferences.language.text("Đồng bộ với GitHub (⌘R)", "Sync with GitHub (⌘R)"))
                .disabled(store.connectionState == .syncing)
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
        switch store.connectionState {
        case .connected: .green
        case .syncing, .ready: .blue
        case .failed: .red
        case .sampleData: .orange
        }
    }

    private var label: String {
        switch store.connectionState {
        case .sampleData:
            store.isUsingSampleData
                ? preferences.language.text("Dữ liệu mẫu", "Sample workspace")
                : preferences.language.text("Đang ngoại tuyến", "Offline workspace")
        case .ready: preferences.language.text("Sẵn sàng đồng bộ", "Ready to sync")
        case .syncing: preferences.language.text("Đang đồng bộ…", "Syncing…")
        case .connected: preferences.language.text("Đã kết nối GitHub", "GitHub connected")
        case .failed: preferences.language.text("Kết nối gặp sự cố", "Connection issue")
        }
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
