import RepoFocusCore
import SwiftUI

struct RepositoryInspectorView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openURL) private var openURL

    let repository: RepositoryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.large) {
                repositoryHeader
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
                    Text(repository.github.nameWithOwner)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                        preferences.language.text("Mở trên GitHub", "Open on GitHub"),
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
                            Text("\(repository.tracking.progress)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
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

                FocusTextInput(
                    placeholder: preferences.language.text("Dán đường dẫn thư mục repo", "Paste the repository folder path"),
                    text: localPathBinding,
                    leadingSymbol: "folder"
                )

                HStack(spacing: Layout.compact) {
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
                    .disabled(localPathIsEmpty || isCheckingLocalGit)

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

                Text(preferences.language.text(
                    "RepoFocus chỉ đọc `git status`; không commit, push, pull hay sửa file.",
                    "RepoFocus only reads `git status`; it never commits, pushes, pulls or changes files."
                ))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var localGitResult: some View {
        if case let .failed(message) = store.localGitCheckState(repositoryID: repository.id) {
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

    private var localPathIsEmpty: Bool {
        (repository.tracking.localPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var isCheckingLocalGit: Bool {
        store.localGitCheckState(repositoryID: repository.id) == .checking
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
