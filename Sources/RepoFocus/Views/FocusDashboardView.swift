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

                        LazyVStack(spacing: 2) {
                            ForEach(repositories) { repository in
                                Button {
                                    selectedRepositoryID = repository.id
                                } label: {
                                    RepositoryRow(
                                        repository: repository,
                                        isSelected: selectedRepositoryID == repository.id
                                    )
                                }
                                .buttonStyle(.plain)
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
                    "Kết nối GitHub trong Cài đặt để nhập repo của bạn.",
                    "Connect GitHub in Settings when you are ready to import your repositories."
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
