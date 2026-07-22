import RepoFocusCore
import SwiftUI

struct FocusDashboardView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    let repositories: [RepositoryRecord]
    @Binding var selectedRepositoryID: String?

    var body: some View {
        if repositories.isEmpty {
            ContentUnavailableView {
                Label(
                    preferences.language.text("Danh sách tập trung đang trống", "Your focus list is empty"),
                    systemImage: "scope"
                )
            } description: {
                Text(preferences.language.text(
                    "Mở Tất cả repo và chọn những việc quan trọng nhất lúc này.",
                    "Open All Repositories and add the work that matters now."
                ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.section) {
                    if store.isUsingSampleData {
                        sampleBanner
                    }

                    let reminderItems = store.todayReminderItems()
                    if !reminderItems.isEmpty {
                        TodayReminderBanner(items: reminderItems) { repositoryID in
                            selectedRepositoryID = repositoryID
                        }
                    }

                    HStack(spacing: Layout.regular) {
                        SummaryCard(
                            title: preferences.language.text("Đang làm", "Active"),
                            value: repositories.filter { $0.tracking.status == .active }.count,
                            symbol: "bolt.fill",
                            color: .blue
                        )
                        SummaryCard(
                            title: preferences.language.text("Bị chặn", "Blocked"),
                            value: repositories.filter { $0.tracking.status == .blocked }.count,
                            symbol: "exclamationmark.octagon.fill",
                            color: .red
                        )
                        SummaryCard(
                            title: preferences.language.text("PR đang mở", "Open PRs"),
                            value: repositories.reduce(0) { $0 + $1.github.openPullRequestCount },
                            symbol: "arrow.triangle.pull",
                            color: .purple
                        )
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(preferences.language.text("Đang tập trung", "Current focus"))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(preferences.language.text(
                                "\(repositories.count) repo",
                                "\(repositories.count) repositories"
                            ))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(Layout.regular)

                        Divider()

                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(repositories) { repository in
                                Button {
                                    selectedRepositoryID = repository.id
                                } label: {
                                    RepositoryRow(
                                        repository: repository,
                                        isSelected: selectedRepositoryID == repository.id
                                    )
                                }
                                .buttonStyle(RepositoryRowButtonStyle())
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(Layout.grid)
                    }
                    .panelStyle()
                }
                .padding(Layout.section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)
        }
    }

    private var sampleBanner: some View {
        HStack(spacing: Layout.regular) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(preferences.language.text("Đang xem dữ liệu mẫu", "Exploring with sample data"))
                    .font(.system(size: 12, weight: .semibold))
                Text(preferences.language.text(
                    "Kết nối GitHub hoặc GitLab trong Cài đặt để nhập repo của bạn.",
                    "Connect GitHub or GitLab in Settings when you are ready to import your repositories."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Layout.regular)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct TodayReminderBanner: View {
    @EnvironmentObject private var preferences: AppPreferences
    let items: [RepositoryReminderItem]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Layout.regular) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Hôm nay cần xử lý", "Needs attention today"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(preferences.language.text(
                        "Ưu tiên theo hạn chót, trạng thái và conflict của branch.",
                        "Prioritized by deadlines, status and branch conflicts."
                    ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(preferences.language.text("\(items.count) dự án", "\(items.count) projects"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(Layout.regular)

            Divider()

            VStack(spacing: 0) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item.repositoryID)
                    } label: {
                        reminderRow(item)
                    }
                    .buttonStyle(.plain)

                    if index < min(items.count, 4) - 1 {
                        Divider().padding(.leading, 40)
                    }
                }

                if items.count > 4 {
                    Text(preferences.language.text(
                        "Và \(items.count - 4) dự án khác trong danh sách tập trung",
                        "And \(items.count - 4) more projects in your focus list"
                    ))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Layout.regular)
                        .padding(.vertical, Layout.compact)
                }
            }
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
    }

    private func reminderRow(_ item: RepositoryReminderItem) -> some View {
        HStack(spacing: Layout.compact) {
            Image(systemName: item.reasons.first?.symbol ?? "scope")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.reasons.first?.color ?? Color.accentColor)
                .frame(width: 26, height: 26)
                .background((item.reasons.first?.color ?? Color.accentColor).opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(item.repositoryName)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)

            if let branch = item.branchName {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.subtleFill)
                    .clipShape(Capsule())
            }

            Spacer(minLength: Layout.compact)

            Text(summary(item))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(item.reasons.first?.color ?? Color.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Layout.regular)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
    }

    private func summary(_ item: RepositoryReminderItem) -> String {
        if let reason = item.reasons.first {
            return reason.title(preferences.language)
        }
        if !item.nextAction.isEmpty { return item.nextAction }
        return preferences.language.text("Xác định việc tiếp theo", "Choose the next action")
    }
}
