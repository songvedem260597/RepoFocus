import RepoFocusCore
import SwiftUI

struct RepositoryInspectorView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openURL) private var openURL

    let repository: RepositoryRecord
    @State private var newPlanItemTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.large) {
                repositoryHeader
                if !localPathIsEmpty, repository.tracking.gitStatus != nil {
                    LocalGitWorkspaceView(repository: repository)
                }
                trackingSection
                deadlineSection
                localGitSection
                contextSection
                notesSection

                if let error = store.persistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(Layout.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCanvas)
        .navigationTitle(repository.github.name)
    }

    private var repositoryHeader: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            HStack(alignment: .top, spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(repository.tracking.status.color.opacity(0.12))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: repository.github.isPrivate ? "lock.fill" : "shippingbox.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(repository.tracking.status.color)
                    }

                VStack(alignment: .leading, spacing: Layout.grid) {
                    Text(repository.github.name)
                        .font(.system(size: 18, weight: .semibold))
                    HStack(spacing: 6) {
                        Label(
                            repository.github.sourceProvider.localizedTitle(preferences.language),
                            systemImage: repository.github.sourceProvider.symbolName
                        )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(repository.github.sourceProvider.tintColor)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(repository.github.sourceProvider.tintColor.opacity(0.08))
                            .clipShape(Capsule())

                        Text(repository.github.nameWithOwner)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }

            if let description = repository.github.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Layout.compact) {
                Button {
                    openURL(repository.github.url)
                } label: {
                    Label(
                        openRepositoryTitle,
                        systemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))

                Button {
                    store.toggleFocus(repositoryID: repository.id)
                } label: {
                    Label(
                        repository.tracking.isFocused
                            ? preferences.language.text("Đang tập trung", "In Focus")
                            : preferences.language.text("Thêm vào tập trung", "Add to Focus"),
                        systemImage: repository.tracking.isFocused ? "scope" : "plus"
                    )
                }
                .buttonStyle(FocusButtonStyle(role: .primary))
            }
        }
    }

    private var trackingSection: some View {
        InspectorSection(title: preferences.language.text("Theo dõi", "Tracking")) {
            VStack(spacing: Layout.regular) {
                if repository.tracking.isFocused {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        Text(preferences.language.text("Nhánh tập trung", "Focus branch"))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        FocusBranchSelect(
                            branches: availableBranches,
                            selection: focusBranchBinding
                        )
                    }

                    Text(preferences.language.text(
                        "Trạng thái, tiến độ, deadline và outline bên dưới chỉ áp dụng cho branch này.",
                        "Status, progress, deadline, and the outline below apply only to this branch."
                    ))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Layout.compact) {
                    Text(preferences.language.text("Trạng thái", "Status"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)
                    FocusStatusSelect(selection: binding(\.status))
                    Spacer(minLength: 0)
                }

                HStack(spacing: Layout.regular) {
                    Text(preferences.language.text("Ưu tiên", "Priority"))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 60, alignment: .leading)
                    FocusPriorityControl(selection: binding(\.priority))
                    Spacer(minLength: 0)
                }

                if repository.tracking.deadline != nil {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        HStack {
                            Text(preferences.language.text("Tiến độ", "Progress"))
                            Spacer()
                            Text("\(repository.displayProgress)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }

                        if repository.tracking.usesOutlinePlan == true {
                            FocusProgressBar(
                                value: repository.displayProgress,
                                tint: repository.tracking.status.color,
                                height: 7
                            )
                            .padding(.vertical, 8)
                        } else {
                            FocusProgressSlider(
                                value: Binding(
                                    get: { repository.tracking.progress },
                                    set: { newValue in
                                        store.updateTracking(repositoryID: repository.id) { $0.progress = newValue }
                                    }
                                ),
                                tint: repository.tracking.status.color
                            )
                        }
                    }
                }
            }
        }
    }

    private var deadlineSection: some View {
        InspectorSection(title: preferences.language.text("Kế hoạch", "Plan")) {
            VStack(alignment: .leading, spacing: Layout.regular) {
                Text(preferences.language.text("Việc tiếp theo", "Next action"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                FocusTextInput(
                    placeholder: preferences.language.text("Bước tiếp theo để đẩy repo tiến lên", "What moves this repo forward?"),
                    text: binding(\.nextAction)
                )

                if repository.tracking.isFocused {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        Text(preferences.language.text("Cách theo dõi tiến độ", "Progress method"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        FocusPlanModeControl(usesOutline: outlinePlanBinding)
                    }

                    if repository.tracking.usesOutlinePlan == true {
                        outlinePlanEditor
                    }
                }

                FocusCheckbox(
                    title: preferences.language.text("Đặt hạn hoàn thành", "Set deadline"),
                    isOn: deadlineEnabledBinding
                )

                if repository.tracking.deadline != nil {
                    HStack(alignment: .top) {
                        Text(preferences.language.text("Hạn chót", "Deadline"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 9)
                        Spacer()
                        FocusDateInput(date: deadlineBinding)
                    }
                }
            }
        }
    }

    private var outlinePlanEditor: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            HStack {
                Text(preferences.language.text("Outline công việc", "Task outline"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(outlineSummaryText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if planItems.isEmpty {
                HStack(spacing: Layout.compact) {
                    Image(systemName: "checklist")
                        .foregroundStyle(.secondary)
                    Text(preferences.language.text(
                        "Thêm từng việc để theo dõi tiến độ của repo.",
                        "Add tasks to track this repository's progress."
                    ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    ForEach(planItems) { item in
                        planItemRow(item)
                    }
                }
            }

            HStack(spacing: Layout.compact) {
                FocusTextInput(
                    placeholder: preferences.language.text("Tên việc hoặc cụm từ trong commit", "Task name or commit phrase"),
                    text: $newPlanItemTitle,
                    onSubmit: addPlanItem
                )

                Button {
                    addPlanItem()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 14)
                }
                .buttonStyle(FocusButtonStyle(role: .primary))
                .disabled(newPlanItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(preferences.language.text("Thêm việc", "Add task"))
            }

            Label(
                preferences.language.text(
                    "RepoFocus tự tích khi tiêu đề commit mới chứa tên việc; bạn cũng có thể tự tích.",
                    "RepoFocus auto-checks a task when a new commit title contains its name; you can also check it manually."
                ),
                systemImage: "sparkles"
            )
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private func planItemRow(_ item: RepositoryPlanItem) -> some View {
        HStack(alignment: .top, spacing: Layout.compact) {
            Button {
                store.togglePlanItem(repositoryID: repository.id, itemID: item.id)
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.isCompleted ? Color.accentColor : Color.subtleFill)
                    .frame(width: 18, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(item.isCompleted ? Color.accentColor : Color.quietBorder, lineWidth: 1)
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
            .help(item.isCompleted
                ? preferences.language.text("Đánh dấu chưa hoàn thành", "Mark incomplete")
                : preferences.language.text("Đánh dấu hoàn thành", "Mark complete"))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(planItemDetail(item), systemImage: planItemDetailSymbol(item))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(item.completionSource == .commit ? Color.green : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Layout.grid)

            Button {
                store.removePlanItem(repositoryID: repository.id, itemID: item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(preferences.language.text("Xóa việc", "Delete task"))
        }
        .padding(9)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder.opacity(0.8), lineWidth: 1)
        }
    }

    private var contextSection: some View {
        InspectorSection(title: preferences.language.text("Thông tin repo", "Repository")) {
            VStack(spacing: Layout.regular) {
                MetadataRow(label: preferences.language.text("Ngôn ngữ", "Language"), value: repository.github.primaryLanguage ?? "—")
                MetadataRow(label: preferences.language.text("Nhánh mặc định", "Default branch"), value: repository.github.defaultBranch ?? "—")
                MetadataRow(label: preferences.language.text("Issue đang mở", "Open issues"), value: "\(repository.github.openIssueCount)")
                MetadataRow(label: preferences.language.text("Pull request đang mở", "Open pull requests"), value: "\(repository.github.openPullRequestCount)")
                MetadataRow(label: preferences.language.text("Lần push gần nhất", "Last push"), value: lastPushText)
            }
        }
    }

    private var localGitSection: some View {
        InspectorSection(title: preferences.language.text("Git trên máy", "Local Git")) {
            VStack(alignment: .leading, spacing: Layout.regular) {
                Text(preferences.language.text("Thư mục repo đã clone", "Cloned repository folder"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(preferences.language.text(
                    "Đây là thư mục chứa source Git của repo trên máy. RepoFocus dùng nó để đọc trạng thái commit, push và conflict.",
                    "This is the folder containing the repository's Git source on your Mac. RepoFocus uses it to read commit, push and conflict status."
                ))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FocusTextInput(
                    placeholder: preferences.language.text("Dán đường dẫn thư mục repo", "Paste the repository folder path"),
                    text: localPathBinding,
                    leadingSymbol: "folder"
                )

                HStack(spacing: Layout.compact) {
                    if localPathIsEmpty {
                        Button {
                            Task { await store.autoDetectLocalRepositories(repositoryID: repository.id) }
                        } label: {
                            if isDetectingLocalRepository {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(preferences.language.text("Đang tìm…", "Searching…"))
                                }
                            } else {
                                Label(
                                    preferences.language.text("Tự tìm trên máy", "Find on this Mac"),
                                    systemImage: "magnifyingglass"
                                )
                            }
                        }
                        .buttonStyle(FocusButtonStyle(role: .secondary))
                        .disabled(isDetectingLocalRepository)
                    } else {
                        Button {
                            Task { await store.checkLocalGit(repositoryID: repository.id) }
                        } label: {
                            if isCheckingLocalGit {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(preferences.language.text("Đang kiểm tra…", "Checking…"))
                                }
                            } else {
                                Label(
                                    preferences.language.text("Kiểm tra Git", "Check Git"),
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                        }
                        .buttonStyle(FocusButtonStyle(role: .secondary))
                        .disabled(isCheckingLocalGit)
                    }

                    Spacer()

                    if let status = repository.tracking.gitStatus {
                        Text(preferences.language.text(
                            "Kiểm tra \(preferences.language.relativeDate(from: status.checkedAt))",
                            "Checked \(preferences.language.relativeDate(from: status.checkedAt))"
                        ))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }

                localGitResult

            }
        }
    }

    @ViewBuilder
    private var localGitResult: some View {
        if store.localRepositoryDetectionState(repositoryID: repository.id) == .notFound,
           localPathIsEmpty {
            Label(
                preferences.language.text(
                    "Không tìm thấy checkout khớp trên máy. Bạn vẫn có thể dán đường dẫn thủ công.",
                    "No matching checkout was found. You can still paste its path manually."
                ),
                systemImage: "folder.badge.questionmark"
            )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if case let .failed(message) = store.localRepositoryDetectionState(repositoryID: repository.id) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if case let .failed(message) = store.localGitCheckState(repositoryID: repository.id) {
            Label(localizedGitError(message), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status = repository.tracking.gitStatus {
            VStack(alignment: .leading, spacing: Layout.compact) {
                HStack {
                    Label(status.branch ?? preferences.language.text("HEAD tách rời", "Detached HEAD"), systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10.5, weight: .semibold))
                    Spacer()
                    Text(status.hasUpstream
                        ? preferences.language.text("Có nhánh remote", "Remote tracked")
                        : preferences.language.text("Chưa có nhánh remote", "No remote branch"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                LocalGitBadgeRow(status: status)
            }
            .padding(10)
            .background(Color.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(Color.quietBorder, lineWidth: 1)
            }
        } else if !localPathIsEmpty {
            Text(preferences.language.text(
                "Nhấn Kiểm tra Git để đọc trạng thái hiện tại.",
                "Choose Check Git to read the current state."
            ))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private var notesSection: some View {
        InspectorSection(title: preferences.language.text("Ghi chú", "Notes")) {
            FocusTextArea(
                placeholder: preferences.language.text("Ghi lại bối cảnh, quyết định hoặc điều cần nhớ…", "Add context, decisions or reminders…"),
                text: binding(\.notes),
                minHeight: 100
            )
        }
    }

    private var deadlineEnabledBinding: Binding<Bool> {
        Binding(
            get: { repository.tracking.deadline != nil },
            set: { enabled in
                store.updateTracking(repositoryID: repository.id) { tracking in
                    tracking.deadline = enabled
                        ? Calendar.current.date(byAdding: .day, value: 7, to: .now)
                        : nil
                }
            }
        )
    }

    private var outlinePlanBinding: Binding<Bool> {
        Binding(
            get: { repository.tracking.usesOutlinePlan == true },
            set: { store.setOutlinePlanEnabled(repositoryID: repository.id, enabled: $0) }
        )
    }

    private var planItems: [RepositoryPlanItem] {
        repository.tracking.planItems ?? []
    }

    private var outlineSummaryText: String {
        let summary = repository.planCompletionSummary
        return preferences.language.text(
            "\(summary.completed)/\(summary.total) hoàn thành",
            "\(summary.completed)/\(summary.total) complete"
        )
    }

    private func addPlanItem() {
        guard !newPlanItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.addPlanItem(repositoryID: repository.id, title: newPlanItemTitle)
        newPlanItemTitle = ""
        if repository.tracking.localPath != nil {
            Task { await store.checkLocalGit(repositoryID: repository.id) }
        }
    }

    private func planItemDetail(_ item: RepositoryPlanItem) -> String {
        if item.completionSource == .commit, let sha = item.matchedCommitSHA {
            return preferences.language.text(
                "Tự động từ commit \(String(sha.prefix(7)))",
                "Auto-completed by commit \(String(sha.prefix(7)))"
            )
        }
        if item.completionSource == .manual {
            return preferences.language.text("Đã tích thủ công", "Checked manually")
        }
        return preferences.language.text(
            "Chờ commit chứa “\(item.commitKeyword)”",
            "Waiting for a commit containing “\(item.commitKeyword)”"
        )
    }

    private func planItemDetailSymbol(_ item: RepositoryPlanItem) -> String {
        if item.completionSource == .commit { return "point.topleft.down.curvedto.point.bottomright.up" }
        if item.completionSource == .manual { return "hand.tap" }
        return "text.magnifyingglass"
    }

    private var deadlineBinding: Binding<Date> {
        Binding(
            get: { repository.tracking.deadline ?? .now },
            set: { date in
                store.updateTracking(repositoryID: repository.id) { $0.deadline = date }
            }
        )
    }

    private var localPathBinding: Binding<String> {
        Binding(
            get: { repository.tracking.localPath ?? "" },
            set: { store.setLocalPath(repositoryID: repository.id, path: $0) }
        )
    }

    private var focusBranchBinding: Binding<String> {
        Binding(
            get: {
                repository.tracking.focusBranch
                    ?? repository.tracking.gitStatus?.branch
                    ?? repository.github.defaultBranch
                    ?? "main"
            },
            set: { branchName in
                store.setFocusBranch(repositoryID: repository.id, branchName: branchName)
                if repository.tracking.localPath != nil {
                    Task { await store.checkLocalGit(repositoryID: repository.id) }
                }
            }
        )
    }

    private var availableBranches: [String] {
        var branches = repository.tracking.localBranches ?? []
        if let defaultBranch = repository.github.defaultBranch {
            branches.append(defaultBranch)
        }
        if let currentBranch = repository.tracking.gitStatus?.branch {
            branches.append(currentBranch)
        }
        if let focusBranch = repository.tracking.focusBranch {
            branches.append(focusBranch)
        }
        return Array(Set(branches))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var localPathIsEmpty: Bool {
        (repository.tracking.localPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var isCheckingLocalGit: Bool {
        store.localGitCheckState(repositoryID: repository.id) == .checking
    }

    private var isDetectingLocalRepository: Bool {
        store.localRepositoryDetectionState(repositoryID: repository.id) == .scanning
    }

    private func localizedGitError(_ message: String) -> String {
        guard preferences.language == .english else { return message }
        return switch message {
        case LocalGitStatusError.emptyPath.localizedDescription:
            "The repository path is empty."
        case LocalGitStatusError.folderNotFound.localizedDescription:
            "This folder could not be found on your Mac."
        case LocalGitStatusError.notARepository.localizedDescription:
            "This folder is not a Git repository."
        default:
            message
        }
    }

    private var lastPushText: String {
        guard let pushedAt = repository.github.pushedAt else { return "—" }
        return preferences.language.relativeDate(from: pushedAt)
    }

    private var openRepositoryTitle: String {
        switch repository.github.sourceProvider {
        case .github: preferences.language.text("Mở trên GitHub", "Open on GitHub")
        case .gitlab: preferences.language.text("Mở trên GitLab", "Open on GitLab")
        case .other: preferences.language.text("Mở nguồn repo", "Open repository source")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RepositoryTracking, Value>) -> Binding<Value> {
        Binding(
            get: { repository.tracking[keyPath: keyPath] },
            set: { value in
                store.updateTracking(repositoryID: repository.id) {
                    $0[keyPath: keyPath] = value
                }
            }
        )
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
    }
}
