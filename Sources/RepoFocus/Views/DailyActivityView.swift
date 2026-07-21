import RepoFocusCore
import SwiftUI

struct DailyActivityView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private var snapshot: DailyActivitySnapshot? {
        store.activitySnapshot(for: selectedDate)
    }

    private var groups: [DailyActivityGroup] {
        guard let snapshot else { return [] }
        return Dictionary(grouping: snapshot.pushes) {
            "\($0.sourceProvider.rawValue)\u{0}\($0.repositoryName)\u{0}\($0.branchName)"
        }
        .values
        .map(DailyActivityGroup.init(pushes:))
        .sorted {
            if $0.latestPush != $1.latestPush { return $0.latestPush > $1.latestPush }
            return $0.repositoryName.localizedStandardCompare($1.repositoryName) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.section) {
                dateToolbar

                if let snapshot {
                    if store.activityLoadState == .loading {
                        loadingNotice
                    }
                    summaryGrid(snapshot)
                    dataNotice(snapshot)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            ActivityGroupCard(group: group)
                        }
                    }
                } else {
                    stateView
                }
            }
            .padding(Layout.section)
        }
        .background(Color.appCanvas)
        .task(id: dayIdentifier) {
            await store.loadDailyActivity(for: selectedDate)
        }
        .onChange(of: selectedDate) {
            let today = Calendar.current.startOfDay(for: .now)
            if selectedDate > today { selectedDate = today }
        }
    }

    private var dateToolbar: some View {
        HStack(alignment: .top, spacing: Layout.compact) {
            VStack(alignment: .leading, spacing: Layout.grid) {
                Text(preferences.language.text("Thống kê theo ngày", "Daily summary"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(formattedSelectedDate)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Layout.compact)

            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .help(preferences.language.text("Ngày trước", "Previous day"))

            FocusDateInput(date: $selectedDate)

            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .help(preferences.language.text("Ngày sau", "Next day"))
            .disabled(Calendar.current.isDateInToday(selectedDate))

            if !Calendar.current.isDateInToday(selectedDate) {
                Button(preferences.language.text("Hôm nay", "Today")) {
                    selectedDate = Calendar.current.startOfDay(for: .now)
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))
            }

            Button {
                Task { await store.loadDailyActivity(for: selectedDate) }
            } label: {
                if store.activityLoadState == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .disabled(store.activityLoadState == .loading)
            .help(preferences.language.text("Cập nhật hoạt động", "Refresh activity"))
        }
        .padding(Layout.regular)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private func summaryGrid(_ snapshot: DailyActivitySnapshot) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 78), spacing: Layout.compact), count: 4),
            spacing: Layout.compact
        ) {
            ActivityMetricCard(
                value: snapshot.totalPushes,
                label: preferences.language.text("Lượt push", "Pushes"),
                symbol: "arrow.up.circle.fill"
            )
            ActivityMetricCard(
                value: snapshot.totalCommits,
                label: preferences.language.text("Commit", "Commits"),
                symbol: "point.topleft.down.to.point.bottomright.curvepath"
            )
            ActivityMetricCard(
                value: snapshot.branchCount,
                label: preferences.language.text("Nhánh", "Branches"),
                symbol: "arrow.triangle.branch"
            )
            ActivityMetricCard(
                value: snapshot.repositoryCount,
                label: preferences.language.text("Repo", "Repositories"),
                symbol: "shippingbox.fill"
            )
        }
    }

    private func dataNotice(_ snapshot: DailyActivitySnapshot) -> some View {
        HStack(alignment: .top, spacing: Layout.compact) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(preferences.language.text(
                "Sự kiện GitHub/GitLab có thể cập nhật chậm. Dữ liệu gần nhất được tải lúc \(time(snapshot.fetchedAt)) và đã lưu trên máy.",
                "GitHub and GitLab events can be delayed. This data was last fetched at \(time(snapshot.fetchedAt)) and cached on this Mac."
            ))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, Layout.grid)
    }

    @ViewBuilder
    private var stateView: some View {
        switch store.activityLoadState {
        case .idle, .loading:
            VStack(spacing: Layout.regular) {
                ProgressView()
                Text(preferences.language.text("Đang đọc hoạt động từ các nguồn…", "Loading activity from connected sources…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        case .failed(let message):
            ActivityStatePanel(
                symbol: "exclamationmark.triangle",
                title: preferences.language.text("Chưa tải được hoạt động", "Could not load activity"),
                message: message,
                buttonTitle: preferences.language.text("Thử lại", "Try again")
            ) {
                Task { await store.loadDailyActivity(for: selectedDate) }
            }
        case .loaded:
            emptyState
        }
    }

    private var loadingNotice: some View {
        HStack(spacing: Layout.compact) {
            ProgressView().controlSize(.small)
            Text(preferences.language.text("Đang cập nhật dữ liệu mới…", "Refreshing with the latest data…"))
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, Layout.regular)
        .frame(height: 36)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        ActivityStatePanel(
            symbol: "calendar.badge.clock",
            title: preferences.language.text("Ngày này chưa có lượt push", "No pushes on this day"),
            message: preferences.language.text(
                "Khi bạn push commit lên một branch, repo và nội dung thay đổi sẽ xuất hiện ở đây.",
                "When you push commits to a branch, its repository and change summary will appear here."
            )
        )
    }

    private var dayIdentifier: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.locale = preferences.language.locale
        if preferences.language == .vietnamese {
            formatter.dateFormat = "EEEE, 'ngày' d 'tháng' M 'năm' yyyy"
        } else {
            formatter.dateStyle = .full
        }
        return formatter.string(from: selectedDate)
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = preferences.language.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func moveDay(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = min(date, Calendar.current.startOfDay(for: .now))
    }
}

private struct ActivityMetricCard: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: Layout.compact) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 27, height: 27)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 62)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }
}

private struct DailyActivityGroup: Identifiable {
    let provider: RepositoryProvider
    let repositoryName: String
    let branchName: String
    let pushes: [DailyPushActivity]

    var id: String { "\(provider.rawValue)\u{0}\(repositoryName)\u{0}\(branchName)" }
    var latestPush: Date { pushes.map(\.pushedAt).max() ?? .distantPast }
    var totalCommits: Int { pushes.reduce(0) { $0 + $1.commitCount } }

    var categoryCounts: [(category: CommitChangeCategory, count: Int)] {
        let categories = pushes.flatMap(\.commits).map { CommitChangeCategory.classify($0.subject) }
        return CommitChangeCategory.allCases.compactMap { category in
            let count = categories.filter { $0 == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    init(pushes: [DailyPushActivity]) {
        let sorted = pushes.sorted { $0.pushedAt > $1.pushedAt }
        self.pushes = sorted
        provider = sorted.first?.sourceProvider ?? .other
        repositoryName = sorted.first?.repositoryName ?? ""
        branchName = sorted.first?.branchName ?? ""
    }
}

private struct ActivityGroupCard: View {
    @EnvironmentObject private var preferences: AppPreferences
    let group: DailyActivityGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Layout.compact) {
                HStack(alignment: .center, spacing: Layout.compact) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Color.accentColor)
                    Text(group.repositoryName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Label(
                        group.provider.localizedTitle(preferences.language),
                        systemImage: group.provider.symbolName
                    )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(group.provider.tintColor)
                        .padding(.horizontal, 6)
                        .frame(height: 21)
                        .background(group.provider.tintColor.opacity(0.08))
                        .clipShape(Capsule())

                    ActivityBranchPill(branch: group.branchName)
                    Spacer(minLength: Layout.grid)

                    Text(summaryText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !group.categoryCounts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(group.categoryCounts, id: \.category) { item in
                                ActivityCategoryPill(category: item.category, count: item.count)
                            }
                        }
                    }
                }
            }
            .padding(Layout.regular)
            .background(Color.elevatedBackground)

            Divider()

            VStack(spacing: 0) {
                ForEach(Array(group.pushes.enumerated()), id: \.element.id) { index, push in
                    ActivityPushSection(push: push)
                    if index < group.pushes.count - 1 {
                        Divider().padding(.leading, Layout.regular)
                    }
                }
            }
        }
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var summaryText: String {
        preferences.language.text(
            "\(group.pushes.count) push · \(group.totalCommits) commit",
            "\(group.pushes.count) pushes · \(group.totalCommits) commits"
        )
    }
}

private struct ActivityPushSection: View {
    @EnvironmentObject private var preferences: AppPreferences
    let push: DailyPushActivity

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            HStack(spacing: Layout.compact) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Circle())

                Text(push.pushedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))

                Text(preferences.language.text(
                    "\(push.commitCount) commit được đẩy lên",
                    "\(push.commitCount) commits pushed"
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if push.commits.isEmpty {
                Text(preferences.language.text(
                    "\(providerName) không cung cấp nội dung commit cho lượt push này.",
                    "\(providerName) did not include commit details for this push."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(push.commits.enumerated()), id: \.offset) { _, commit in
                        ActivityCommitRow(commit: commit)
                    }
                }
                .padding(.leading, 30)

                if push.commitCount > push.commits.count {
                    Text(preferences.language.text(
                        "Còn \(push.commitCount - push.commits.count) commit không có trong nội dung sự kiện \(providerName).",
                        "\(push.commitCount - push.commits.count) more commits were not included in the \(providerName) event payload."
                    ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
        .padding(Layout.regular)
    }

    private var providerName: String {
        push.sourceProvider.localizedTitle(preferences.language)
    }
}

private struct ActivityCommitRow: View {
    @EnvironmentObject private var preferences: AppPreferences
    let commit: DailyCommitActivity

    private var category: CommitChangeCategory {
        CommitChangeCategory.classify(commit.subject)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.compact) {
            Text(String(commit.sha.prefix(7)))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Color.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(commit.subject)
                .font(.system(size: 11.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Layout.compact)

            Text(category.title(preferences.language))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(category.color)
                .lineLimit(1)
        }
    }
}

private struct ActivityBranchPill: View {
    let branch: String

    var body: some View {
        Label(branch, systemImage: "arrow.triangle.branch")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.subtleFill)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(Color.quietBorder, lineWidth: 1) }
    }
}

private struct ActivityCategoryPill: View {
    @EnvironmentObject private var preferences: AppPreferences
    let category: CommitChangeCategory
    let count: Int

    var body: some View {
        Label("\(category.title(preferences.language)) · \(count)", systemImage: category.symbol)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(category.color.opacity(0.09))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(category.color.opacity(0.2), lineWidth: 1) }
    }
}

private struct ActivityStatePanel: View {
    let symbol: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Layout.regular) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(FocusButtonStyle(role: .secondary))
            }
        }
        .padding(Layout.large)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }
}

private extension CommitChangeCategory {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .feature: language.text("Tính năng", "Feature")
        case .fix: language.text("Sửa lỗi", "Fix")
        case .refactor: language.text("Tái cấu trúc", "Refactor")
        case .documentation: language.text("Tài liệu", "Documentation")
        case .test: language.text("Kiểm thử", "Tests")
        case .build: language.text("Build / CI", "Build / CI")
        case .maintenance: language.text("Bảo trì", "Maintenance")
        case .other: language.text("Thay đổi khác", "Other change")
        }
    }

    var symbol: String {
        switch self {
        case .feature: "sparkles"
        case .fix: "bandage.fill"
        case .refactor: "arrow.triangle.2.circlepath"
        case .documentation: "doc.text.fill"
        case .test: "checkmark.seal.fill"
        case .build: "hammer.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .other: "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .feature: .green
        case .fix: .red
        case .refactor: .purple
        case .documentation: .orange
        case .test: .teal
        case .build: .indigo
        case .maintenance: .secondary
        case .other: .secondary
        }
    }
}
