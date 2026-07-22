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
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences
    let items: [RepositoryReminderItem]
    let onSelect: (String) -> Void
    @State private var expandedRepositoryID: String?

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
                        if canTogglePlanner(item) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedRepositoryID = expandedRepositoryID == item.repositoryID
                                    ? nil
                                    : item.repositoryID
                            }
                        } else {
                            onSelect(item.repositoryID)
                        }
                    } label: {
                        reminderRow(item, isExpanded: expandedRepositoryID == item.repositoryID)
                    }
                    .buttonStyle(.plain)

                    if expandedRepositoryID == item.repositoryID,
                       store.repository(id: item.repositoryID) != nil {
                        NextActionPlanPanel(repositoryID: item.repositoryID) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedRepositoryID = nil
                            }
                        }
                        .padding(.horizontal, Layout.regular)
                        .padding(.bottom, Layout.regular)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

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

    private func reminderRow(_ item: RepositoryReminderItem, isExpanded: Bool) -> some View {
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

            Image(systemName: canTogglePlanner(item) ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
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

    private func canOpenPlanner(_ item: RepositoryReminderItem) -> Bool {
        item.reasons.isEmpty
            && item.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.repository(id: item.repositoryID) != nil
    }

    private func canTogglePlanner(_ item: RepositoryReminderItem) -> Bool {
        expandedRepositoryID == item.repositoryID || canOpenPlanner(item)
    }
}

private struct NextActionPlanPanel: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    let repositoryID: String
    let onClose: () -> Void

    @State private var taskTitle = ""
    @State private var estimatedMinutes = 60

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            HStack(spacing: Layout.compact) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.language.text("Lập danh sách công việc", "Plan the next tasks"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(panelSubtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if remainingEstimate > 0 {
                    Label(
                        preferences.language.estimatedDuration(remainingEstimate),
                        systemImage: "clock"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.subtleFill)
                    .clipShape(Capsule())
                    .help(preferences.language.text(
                        "Tổng thời gian ước tính còn lại",
                        "Total remaining estimate"
                    ))
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 12)
                }
                .buttonStyle(FocusButtonStyle(role: .icon))
                .help(preferences.language.text("Đóng bảng", "Close panel"))
            }

            if !planItems.isEmpty {
                VStack(spacing: 6) {
                    ForEach(planItems) { item in
                        taskRow(item)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Layout.compact) {
                HStack {
                    Text(preferences.language.text("Công việc mới", "New task"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preferences.language.text("Ước lượng", "Estimate"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .center)
                }

                HStack(spacing: Layout.compact) {
                    FocusTextInput(
                        placeholder: preferences.language.text(
                            "Ví dụ: Hoàn thiện màn hình đăng nhập",
                            "Example: Finish the sign-in screen"
                        ),
                        text: $taskTitle,
                        leadingSymbol: "checklist",
                        onSubmit: addTask
                    )

                    TaskEstimateInput(minutes: $estimatedMinutes)

                    Button(action: addTask) {
                        Label(preferences.language.text("Thêm", "Add"), systemImage: "plus")
                    }
                    .buttonStyle(FocusButtonStyle(role: .primary))
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Label(
                preferences.language.text(
                    "Việc đầu tiên sẽ trở thành việc tiếp theo; tiến độ được tính theo danh sách và vẫn tự tích khi commit khớp tên việc.",
                    "The first task becomes the next action; progress follows this list and matching commits can still complete tasks automatically."
                ),
                systemImage: "sparkles"
            )
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.regular)
        .background(Color.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
        }
    }

    private var repository: RepositoryRecord? {
        store.repository(id: repositoryID)
    }

    private var planItems: [RepositoryPlanItem] {
        repository?.tracking.planItems ?? []
    }

    private var remainingEstimate: Int {
        planItems
            .filter { !$0.isCompleted }
            .compactMap(\.estimatedMinutes)
            .reduce(0, +)
    }

    private var panelSubtitle: String {
        let branch = repository?.tracking.focusBranch
            ?? repository?.tracking.gitStatus?.branch
            ?? repository?.github.defaultBranch
        guard let branch, !branch.isEmpty else {
            return preferences.language.text(
                "Thêm từng việc và thời gian dự kiến.",
                "Add each task and its expected duration."
            )
        }
        return preferences.language.text(
            "Kế hoạch cho branch \(branch)",
            "Plan for branch \(branch)"
        )
    }

    private func taskRow(_ item: RepositoryPlanItem) -> some View {
        HStack(spacing: Layout.compact) {
            Button {
                store.togglePlanItem(repositoryID: repositoryID, itemID: item.id)
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.isCompleted ? Color.green : Color.subtleFill)
                    .frame(width: 18, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(item.isCompleted ? Color.green : Color.quietBorder, lineWidth: 1)
                    }
                    .overlay {
                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                .strikethrough(item.isCompleted, color: .secondary)
                .lineLimit(2)

            Spacer(minLength: Layout.compact)

            if let minutes = item.estimatedMinutes {
                TaskEstimateInput(minutes: Binding(
                    get: { minutes },
                    set: {
                        store.updatePlanItemEstimate(
                            repositoryID: repositoryID,
                            itemID: item.id,
                            estimatedMinutes: $0
                        )
                    }
                ))
            } else {
                Button {
                    store.updatePlanItemEstimate(
                        repositoryID: repositoryID,
                        itemID: item.id,
                        estimatedMinutes: 60
                    )
                } label: {
                    Label(preferences.language.text("Thêm ước lượng", "Add estimate"), systemImage: "clock")
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))
            }

            Button {
                store.removePlanItem(repositoryID: repositoryID, itemID: item.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 12)
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .help(preferences.language.text("Xóa việc", "Delete task"))
        }
        .padding(8)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private func addTask() {
        let normalizedTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        store.addPlanItem(
            repositoryID: repositoryID,
            title: normalizedTitle,
            estimatedMinutes: estimatedMinutes,
            makeNextAction: true
        )
        taskTitle = ""
    }
}

private struct TaskEstimateInput: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 1) {
            Button { adjust(-stepDown) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(CompactEstimateButtonStyle())
            .disabled(minutes <= 15)

            Text(preferences.language.estimatedDuration(minutes))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48)

            Button { adjust(stepUp) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(CompactEstimateButtonStyle())
            .disabled(minutes >= 2_400)
        }
        .padding(2)
        .frame(width: 104, height: 30)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preferences.language.text("Thời gian ước tính", "Estimated duration"))
        .accessibilityValue(preferences.language.estimatedDuration(minutes))
    }

    private var stepUp: Int {
        if minutes < 60 { return 15 }
        if minutes < 240 { return 30 }
        return 60
    }

    private var stepDown: Int {
        if minutes <= 60 { return 15 }
        if minutes <= 240 { return 30 }
        return 60
    }

    private func adjust(_ amount: Int) {
        minutes = min(max(minutes + amount, 15), 2_400)
    }
}

private struct CompactEstimateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(isEnabled ? 1 : 0.3)
    }
}
