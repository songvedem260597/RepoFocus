import AppKit
import RepoFocusCore
import SwiftUI

private enum GitWorkspaceSheet: String, Identifiable {
    case switchBranch
    case commit
    case merge
    case history
    case conflicts

    var id: String { rawValue }
}

struct LocalGitWorkspaceView: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences

    let repository: RepositoryRecord

    @State private var activeSheet: GitWorkspaceSheet?
    @State private var selectedBranch = ""
    @State private var commitMessage = ""
    @State private var pendingRevertSHA: String?
    @State private var confirmsAbort = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            HStack(spacing: Layout.compact) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.language.text("Không gian làm việc", "Git workspace"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(currentBranch)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Layout.compact),
                    GridItem(.flexible(), spacing: Layout.compact)
                ],
                spacing: Layout.compact
            ) {
                actionButton(
                    preferences.language.text("Đổi branch", "Switch branch"),
                    symbol: "arrow.left.arrow.right"
                ) {
                    selectedBranch = switchBranchOptions.first ?? ""
                    activeSheet = .switchBranch
                }
                actionButton(
                    preferences.language.text("Commit", "Commit"),
                    symbol: "checkmark.circle"
                ) {
                    commitMessage = ""
                    activeSheet = .commit
                }
                actionButton(
                    preferences.language.text("Pull", "Pull"),
                    symbol: "arrow.down.to.line"
                ) {
                    Task { await store.pull(repositoryID: repository.id) }
                }
                actionButton(
                    preferences.language.text("Push", "Push"),
                    symbol: "arrow.up.to.line"
                ) {
                    Task { await store.push(repositoryID: repository.id) }
                }
                actionButton(
                    preferences.language.text("Merge branch", "Merge branch"),
                    symbol: "arrow.triangle.merge"
                ) {
                    selectedBranch = mergeBranchOptions.first ?? ""
                    activeSheet = .merge
                }
                actionButton(
                    preferences.language.text("Lịch sử commit", "Commit history"),
                    symbol: "clock.arrow.circlepath"
                ) {
                    pendingRevertSHA = nil
                    activeSheet = .history
                }
            }

            if !conflictFiles.isEmpty || sequenceState != .none {
                Button {
                    confirmsAbort = false
                    activeSheet = .conflicts
                } label: {
                    HStack(spacing: Layout.compact) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(preferences.language.text(
                            conflictFiles.isEmpty
                                ? "Hoàn tất thao tác đang chờ"
                                : "Xử lý \(conflictFiles.count) file conflict",
                            conflictFiles.isEmpty
                                ? "Finish pending operation"
                                : "Resolve \(conflictFiles.count) conflicted files"
                        ))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FocusButtonStyle(role: .destructive))
                .disabled(isRunning)
            }

            operationBanner

            Text(preferences.language.text(
                "Các nút này chạy Git thật trong đúng thư mục repo. Pull chỉ fast-forward; hoàn tác luôn tạo commit mới bằng git revert, không dùng reset --hard.",
                "These actions run Git in this exact repository folder. Pull is fast-forward only; reverting always creates a new commit with git revert and never uses reset --hard."
            ))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
                .environmentObject(store)
                .environmentObject(preferences)
        }
        .onChange(of: operationState) { _, state in
            if case .needsConflictResolution = state {
                confirmsAbort = false
                activeSheet = .conflicts
            }
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .frame(width: 14)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FocusButtonStyle(role: .secondary))
        .disabled(isRunning)
    }

    @ViewBuilder
    private var operationBanner: some View {
        switch operationState {
        case .idle:
            EmptyView()
        case let .running(kind):
            statusBanner(
                title: operationTitle(kind, running: true),
                detail: nil,
                symbol: "arrow.triangle.2.circlepath",
                tint: .accentColor,
                spins: true
            )
        case let .succeeded(kind, _):
            statusBanner(
                title: operationSuccessTitle(kind),
                detail: nil,
                symbol: "checkmark.circle.fill",
                tint: .green
            )
        case let .needsConflictResolution(_, message):
            statusBanner(
                title: preferences.language.text("Cần xử lý conflict", "Conflicts need attention"),
                detail: localizedOperationDetail(message),
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        case let .failed(kind, message):
            statusBanner(
                title: kind.map { operationFailureTitle($0) }
                    ?? preferences.language.text("Thao tác Git thất bại", "Git operation failed"),
                detail: localizedOperationDetail(message),
                symbol: "xmark.circle.fill",
                tint: .red
            )
        }
    }

    private func statusBanner(
        title: String,
        detail: String?,
        symbol: String,
        tint: Color,
        spins: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: Layout.compact) {
            Group {
                if spins {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                }
            }
            .foregroundStyle(tint)
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)

            if !spins {
                Button {
                    store.dismissLocalGitOperationResult(repositoryID: repository.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: GitWorkspaceSheet) -> some View {
        switch sheet {
        case .switchBranch:
            branchSheet(isMerge: false)
        case .commit:
            commitSheet
        case .merge:
            branchSheet(isMerge: true)
        case .history:
            historySheet
        case .conflicts:
            conflictSheet
        }
    }

    private var commitSheet: some View {
        workspaceSheet(
            title: preferences.language.text("Tạo commit", "Create commit"),
            subtitle: preferences.language.text(
                "Commit toàn bộ thay đổi đang có trên branch \(currentBranch).",
                "Commit all current changes on \(currentBranch)."
            ),
            symbol: "checkmark.circle"
        ) {
            VStack(alignment: .leading, spacing: Layout.regular) {
                sectionLabel(preferences.language.text("Nội dung commit", "Commit message"))
                FocusTextArea(
                    placeholder: preferences.language.text(
                        "Mô tả thay đổi đã hoàn thành…",
                        "Describe the completed change…"
                    ),
                    text: $commitMessage,
                    minHeight: 112
                )

                Label(
                    preferences.language.text(
                        "RepoFocus sẽ stage toàn bộ file mới, đã sửa và đã xóa bằng git add -A.",
                        "RepoFocus will stage every new, modified, and deleted file using git add -A."
                    ),
                    systemImage: "info.circle"
                )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                sheetActions(primaryTitle: preferences.language.text("Commit toàn bộ", "Commit all")) {
                    Task {
                        await store.commitAll(repositoryID: repository.id, message: commitMessage)
                        closeSheetAfterSuccess()
                    }
                }
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
            }
        }
    }

    private func branchSheet(isMerge: Bool) -> some View {
        let options = isMerge ? mergeBranchOptions : switchBranchOptions
        return workspaceSheet(
            title: isMerge
                ? preferences.language.text("Merge branch", "Merge branch")
                : preferences.language.text("Đổi branch", "Switch branch"),
            subtitle: isMerge
                ? preferences.language.text(
                    "Nhập branch được chọn vào \(currentBranch).",
                    "Merge the selected branch into \(currentBranch)."
                )
                : preferences.language.text(
                    "Chuyển working directory sang branch khác.",
                    "Switch the working directory to another branch."
                ),
            symbol: isMerge ? "arrow.triangle.merge" : "arrow.left.arrow.right"
        ) {
            VStack(alignment: .leading, spacing: Layout.regular) {
                sectionLabel(isMerge
                    ? preferences.language.text("Branch cần merge", "Branch to merge")
                    : preferences.language.text("Branch cần chuyển sang", "Switch to branch"))

                if options.isEmpty {
                    Label(
                        preferences.language.text(
                            "Không có branch phù hợp. Hãy kiểm tra Git để tải lại danh sách.",
                            "No matching branch is available. Refresh Git to reload the list."
                        ),
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else {
                    FocusBranchSelect(branches: options, selection: $selectedBranch)
                }

                if isMerge {
                    Label(
                        preferences.language.text(
                            "Nếu hai branch sửa cùng vùng code, RepoFocus sẽ mở màn hình xử lý conflict.",
                            "If both branches changed the same code, RepoFocus will open conflict resolution."
                        ),
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                sheetActions(primaryTitle: isMerge
                    ? preferences.language.text("Merge vào branch hiện tại", "Merge into current")
                    : preferences.language.text("Chuyển branch", "Switch branch")) {
                    Task {
                        if isMerge {
                            await store.mergeLocalBranch(repositoryID: repository.id, branch: selectedBranch)
                        } else {
                            await store.switchLocalBranch(repositoryID: repository.id, branch: selectedBranch)
                        }
                        closeSheetAfterSuccess()
                    }
                }
                .disabled(selectedBranch.isEmpty || !options.contains(selectedBranch) || isRunning)
            }
        }
    }

    private var historySheet: some View {
        workspaceSheet(
            title: preferences.language.text("Lịch sử commit", "Commit history"),
            subtitle: preferences.language.text(
                "Hoàn tác an toàn bằng một commit mới trên \(currentBranch).",
                "Safely undo a change with a new commit on \(currentBranch)."
            ),
            symbol: "clock.arrow.circlepath",
            width: 600
        ) {
            VStack(spacing: Layout.regular) {
                if commits.isEmpty {
                    VStack(spacing: Layout.compact) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text(preferences.language.text(
                            "Chưa đọc được lịch sử commit.",
                            "No commit history is available yet."
                        ))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Layout.compact) {
                            ForEach(commits, id: \.sha) { commit in
                                commitRow(commit)
                            }
                        }
                    }
                    .frame(height: 390)
                }

                HStack {
                    Text(preferences.language.text(
                        "Không thay đổi lịch sử đã push.",
                        "Published history is never rewritten."
                    ))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(preferences.language.text("Đóng", "Close")) {
                        activeSheet = nil
                    }
                    .buttonStyle(FocusButtonStyle(role: .secondary))
                    .disabled(isRunning)
                }
            }
        }
    }

    private func commitRow(_ commit: LocalGitCommit) -> some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            HStack(alignment: .top, spacing: Layout.compact) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.subject)
                        .font(.system(size: 11.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Layout.compact) {
                        Text(String(commit.sha.prefix(7)))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                        Text(preferences.language.relativeDate(from: commit.committedAt))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Layout.compact)

                if pendingRevertSHA != commit.sha {
                    Button {
                        pendingRevertSHA = commit.sha
                    } label: {
                        Label(
                            preferences.language.text("Hoàn tác", "Revert"),
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .buttonStyle(FocusButtonStyle(role: .secondary))
                    .disabled(isRunning)
                }
            }

            if pendingRevertSHA == commit.sha {
                VStack(alignment: .leading, spacing: Layout.compact) {
                    Text(preferences.language.text(
                        "Tạo commit mới để đảo ngược thay đổi “\(commit.subject)”?",
                        "Create a new commit that reverses “\(commit.subject)”?"
                    ))
                        .font(.system(size: 10.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(preferences.language.text("Hủy", "Cancel")) {
                            pendingRevertSHA = nil
                        }
                        .buttonStyle(FocusButtonStyle(role: .secondary))
                        Spacer()
                        Button {
                            Task {
                                await store.revert(repositoryID: repository.id, sha: commit.sha)
                                if case .succeeded = operationState {
                                    pendingRevertSHA = nil
                                }
                            }
                        } label: {
                            Label(
                                preferences.language.text("Tạo commit hoàn tác", "Create revert commit"),
                                systemImage: "arrow.uturn.backward.circle"
                            )
                        }
                        .buttonStyle(FocusButtonStyle(role: .destructive))
                        .disabled(isRunning)
                    }
                }
                .padding(9)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                }
            }
        }
        .padding(10)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private var conflictSheet: some View {
        workspaceSheet(
            title: preferences.language.text("Xử lý conflict", "Resolve conflicts"),
            subtitle: conflictSubtitle,
            symbol: "exclamationmark.triangle",
            width: 640
        ) {
            VStack(spacing: Layout.regular) {
                if conflictFiles.isEmpty {
                    Label(
                        sequenceState == .none
                            ? preferences.language.text("Không còn file conflict.", "No conflicted files remain.")
                            : preferences.language.text(
                                "Mọi file đã được xử lý. Bạn có thể hoàn tất thao tác.",
                                "Every file is resolved. You can finish the operation."
                            ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Layout.compact) {
                            ForEach(conflictFiles) { file in
                                conflictRow(file)
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }

                Divider()

                if confirmsAbort {
                    VStack(alignment: .leading, spacing: Layout.compact) {
                        Text(preferences.language.text(
                            "Hủy toàn bộ thao tác đang diễn ra và đưa repo về trạng thái trước đó?",
                            "Abort the current operation and restore the repository to its previous state?"
                        ))
                            .font(.system(size: 10.5, weight: .medium))
                        HStack {
                            Button(preferences.language.text("Không hủy", "Keep working")) {
                                confirmsAbort = false
                            }
                            .buttonStyle(FocusButtonStyle(role: .secondary))
                            Spacer()
                            Button(preferences.language.text("Xác nhận hủy thao tác", "Abort operation")) {
                                Task {
                                    await store.abortLocalGitOperation(repositoryID: repository.id)
                                    closeSheetAfterSuccess()
                                }
                            }
                            .buttonStyle(FocusButtonStyle(role: .destructive))
                            .disabled(isRunning)
                        }
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    HStack(spacing: Layout.compact) {
                        Button(preferences.language.text("Đóng", "Close")) {
                            activeSheet = nil
                        }
                        .buttonStyle(FocusButtonStyle(role: .secondary))
                        .disabled(isRunning)

                        if sequenceState != .none {
                            Button(preferences.language.text("Hủy thao tác", "Abort operation")) {
                                confirmsAbort = true
                            }
                            .buttonStyle(FocusButtonStyle(role: .destructive))
                            .disabled(isRunning)
                        }

                        Spacer()

                        if sequenceState != .none {
                            Button {
                                Task {
                                    await store.continueLocalGitOperation(repositoryID: repository.id)
                                    closeSheetAfterSuccess()
                                }
                            } label: {
                                Label(continueTitle, systemImage: "checkmark.circle")
                            }
                            .buttonStyle(FocusButtonStyle(role: .primary))
                            .disabled(!conflictFiles.isEmpty || isRunning)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRunning)
    }

    private func conflictRow(_ file: LocalGitConflictFile) -> some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            HStack(spacing: Layout.compact) {
                Image(systemName: "doc.badge.ellipsis")
                    .foregroundStyle(.orange)
                Text(file.path)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    openConflictFile(file)
                } label: {
                    Label(preferences.language.text("Mở file", "Open file"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))
            }

            HStack(spacing: Layout.compact) {
                Button(preferences.language.text("Giữ branch hiện tại", "Keep current")) {
                    resolve(file, choice: .ours)
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))

                Button(preferences.language.text("Giữ branch được nhập", "Keep incoming")) {
                    resolve(file, choice: .theirs)
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))

                Spacer(minLength: 0)

                Button(preferences.language.text("Đã sửa xong", "Mark resolved")) {
                    resolve(file, choice: .markResolved)
                }
                .buttonStyle(FocusButtonStyle(role: .primary))
            }
            .disabled(isRunning)
        }
        .padding(10)
        .background(Color.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color.quietBorder, lineWidth: 1)
        }
    }

    private func workspaceSheet<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        width: CGFloat = 520,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Layout.regular) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    activeSheet = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 14)
                }
                .buttonStyle(FocusButtonStyle(role: .icon))
                .disabled(isRunning)
            }
            .padding(Layout.section)
            .background(Color.headerBackground)

            Divider()

            content()
                .padding(Layout.section)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .interactiveDismissDisabled(isRunning)
    }

    private func sheetActions(primaryTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(preferences.language.text("Hủy", "Cancel")) {
                activeSheet = nil
            }
            .buttonStyle(FocusButtonStyle(role: .secondary))
            .disabled(isRunning)
            Spacer()
            Button(action: action) {
                Text(primaryTitle)
            }
            .buttonStyle(FocusButtonStyle(role: .primary))
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func resolve(_ file: LocalGitConflictFile, choice: LocalGitConflictChoice) {
        Task {
            await store.resolveLocalConflict(
                repositoryID: repository.id,
                file: file.path,
                choice: choice
            )
        }
    }

    private func closeSheetAfterSuccess() {
        if case .succeeded = operationState {
            activeSheet = nil
        }
    }

    private func openConflictFile(_ file: LocalGitConflictFile) {
        guard let localPath = repository.tracking.localPath else { return }
        let root = URL(fileURLWithPath: NSString(string: localPath).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let target = root.appendingPathComponent(file.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard target.path.hasPrefix(root.path + "/") else { return }
        NSWorkspace.shared.open(target)
    }

    private var operationState: LocalGitOperationState {
        store.localGitOperationState(repositoryID: repository.id)
    }

    private var isRunning: Bool {
        if case .running = operationState { return true }
        return false
    }

    private var conflictFiles: [LocalGitConflictFile] {
        store.localGitConflictFiles[repository.id] ?? []
    }

    private var sequenceState: LocalGitSequenceState {
        store.localGitSequenceStates[repository.id] ?? .none
    }

    private var commits: [LocalGitCommit] {
        store.recentLocalCommits[repository.id] ?? []
    }

    private var currentBranch: String {
        store.repository(id: repository.id)?.tracking.gitStatus?.branch
            ?? repository.tracking.gitStatus?.branch
            ?? preferences.language.text("HEAD tách rời", "Detached HEAD")
    }

    private var allBranches: [String] {
        store.repository(id: repository.id)?.tracking.localBranches
            ?? repository.tracking.localBranches
            ?? []
    }

    private var switchBranchOptions: [String] {
        allBranches.filter { branch in
            guard branch != currentBranch else { return false }
            if branch.hasPrefix("origin/") {
                let localName = String(branch.dropFirst("origin/".count))
                if allBranches.contains(localName) { return false }
            }
            return true
        }
    }

    private var mergeBranchOptions: [String] {
        allBranches.filter { branch in
            branch != currentBranch && branch != "origin/\(currentBranch)"
        }
    }

    private var conflictSubtitle: String {
        switch sequenceState {
        case .merge:
            preferences.language.text(
                "Chọn nội dung cần giữ cho từng file, rồi tiếp tục merge.",
                "Choose what to keep in each file, then continue the merge."
            )
        case .revert:
            preferences.language.text(
                "Chọn nội dung cần giữ cho từng file, rồi tiếp tục hoàn tác.",
                "Choose what to keep in each file, then continue the revert."
            )
        case .none:
            preferences.language.text(
                "Mở file để sửa thủ công hoặc chọn nhanh một phiên bản.",
                "Open files for manual editing or quickly keep one version."
            )
        }
    }

    private var continueTitle: String {
        switch sequenceState {
        case .merge: preferences.language.text("Hoàn tất merge", "Finish merge")
        case .revert: preferences.language.text("Hoàn tất hoàn tác", "Finish revert")
        case .none: preferences.language.text("Hoàn tất", "Finish")
        }
    }

    private func operationTitle(_ kind: LocalGitOperationKind, running: Bool) -> String {
        let vietnamese: String
        let english: String
        switch kind {
        case .switchBranch: (vietnamese, english) = ("Đang đổi branch…", "Switching branch…")
        case .commit: (vietnamese, english) = ("Đang tạo commit…", "Creating commit…")
        case .pull: (vietnamese, english) = ("Đang pull…", "Pulling…")
        case .push: (vietnamese, english) = ("Đang push…", "Pushing…")
        case .revert: (vietnamese, english) = ("Đang tạo commit hoàn tác…", "Creating revert commit…")
        case .merge: (vietnamese, english) = ("Đang merge branch…", "Merging branch…")
        case .resolveConflict: (vietnamese, english) = ("Đang cập nhật conflict…", "Updating conflict…")
        case .continueOperation: (vietnamese, english) = ("Đang hoàn tất thao tác…", "Finishing operation…")
        case .abortOperation: (vietnamese, english) = ("Đang hủy thao tác…", "Aborting operation…")
        }
        return preferences.language.text(vietnamese, english)
    }

    private func operationSuccessTitle(_ kind: LocalGitOperationKind) -> String {
        let vietnamese: String
        let english: String
        switch kind {
        case .switchBranch: (vietnamese, english) = ("Đã đổi branch", "Branch switched")
        case .commit: (vietnamese, english) = ("Đã tạo commit", "Commit created")
        case .pull: (vietnamese, english) = ("Đã pull xong", "Pull completed")
        case .push: (vietnamese, english) = ("Đã push xong", "Push completed")
        case .revert: (vietnamese, english) = ("Đã tạo commit hoàn tác", "Revert commit created")
        case .merge: (vietnamese, english) = ("Đã merge branch", "Branch merged")
        case .resolveConflict: (vietnamese, english) = ("Đã cập nhật file conflict", "Conflict file updated")
        case .continueOperation: (vietnamese, english) = ("Đã hoàn tất thao tác", "Operation completed")
        case .abortOperation: (vietnamese, english) = ("Đã hủy thao tác", "Operation aborted")
        }
        return preferences.language.text(vietnamese, english)
    }

    private func operationFailureTitle(_ kind: LocalGitOperationKind) -> String {
        preferences.language.text(
            "Không thể hoàn tất thao tác Git",
            "Could not complete the Git operation"
        )
    }

    private func localizedOperationDetail(_ message: String) -> String {
        if preferences.language == .english { return message }
        if message.localizedCaseInsensitiveContains("would be overwritten by checkout") {
            return "Có thay đổi chưa commit sẽ bị ảnh hưởng khi đổi branch. Hãy commit hoặc xử lý các file đó trước."
        }
        if message.localizedCaseInsensitiveContains("not possible to fast-forward") {
            return "Branch local và remote đã lệch nhau. Hãy merge rõ ràng trước khi pull lại."
        }
        if message.localizedCaseInsensitiveContains("authentication failed") ||
            message.localizedCaseInsensitiveContains("could not read username") {
            return "Git không xác thực được với remote. Hãy kiểm tra đăng nhập GitHub/GitLab hoặc thông tin xác thực của Git."
        }
        if message.localizedCaseInsensitiveContains("conflict") {
            return "Git phát hiện thay đổi xung đột. Hãy chọn cách xử lý cho từng file bên dưới."
        }
        return message
    }
}
