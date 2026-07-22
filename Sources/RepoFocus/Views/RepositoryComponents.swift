import RepoFocusCore
import SwiftUI

struct StatusChip: View {
    @EnvironmentObject private var preferences: AppPreferences
    let status: WorkStatus

    var body: some View {
        Label(status.localizedTitle(preferences.language), systemImage: status.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct RepositoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct RepositoryRow: View {
    @EnvironmentObject private var preferences: AppPreferences
    let repository: RepositoryRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Layout.regular) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(repository.tracking.status.color.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: repository.github.isPrivate ? "lock.fill" : "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(repository.tracking.status.color)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.green)
                            .background(Circle().fill(Color.elevatedBackground).padding(1))
                            .offset(x: 4, y: 4)
                            .accessibilityLabel(preferences.language.text("Đã hoàn thành", "Completed"))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(repository.github.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if repository.tracking.priority == .high {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(repository.tracking.priority.color)
                            .help(preferences.language.text("Ưu tiên cao", "High priority"))
                    }
                }

                if let branchName {
                    HStack(spacing: 7) {
                        Label(
                            repository.github.sourceProvider.localizedTitle(preferences.language),
                            systemImage: repository.github.sourceProvider.symbolName
                        )
                            .foregroundStyle(repository.github.sourceProvider.tintColor)
                        Label(branchName, systemImage: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(branchName)
                    }
                    .font(.system(size: 9.5, weight: .medium))
                } else {
                    Text(repository.github.primaryLanguage
                        ?? preferences.language.text("Chưa xác định branch", "Branch unavailable"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 195, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    StatusChip(status: repository.tracking.status)

                    if let gitStatus = repository.tracking.gitStatus {
                        RepositoryGitSummaryBadge(status: gitStatus)
                    }

                    if repository.tracking.usesOutlinePlan == true {
                        let summary = repository.planCompletionSummary
                        Label("\(summary.completed)/\(summary.total)", systemImage: "checklist")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .frame(height: 21)
                            .background(Color.secondary.opacity(0.09))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text(repository.tracking.nextAction.isEmpty
                        ? preferences.language.text("Chưa có việc tiếp theo", "No next action")
                        : repository.tracking.nextAction)
                        .font(.system(size: 10.5))
                        .foregroundStyle(repository.tracking.nextAction.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .help(repository.tracking.nextAction.isEmpty
                            ? preferences.language.text("Chưa có việc tiếp theo", "No next action")
                            : repository.tracking.nextAction)

                    Spacer(minLength: 4)

                    if repository.tracking.deadline != nil {
                        Text("\(repository.displayProgress)%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(FocusProgressAppearance.tint(for: visualProgress))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        FocusProgressBar(
                            value: visualProgress,
                            height: 4
                        )
                        .frame(width: 52)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 10) {
                    MetadataCount(symbol: "smallcircle.filled.circle", value: repository.github.openIssueCount)
                    MetadataCount(symbol: "arrow.triangle.pull", value: repository.github.openPullRequestCount)
                }

                Text(lastPushText)
                    .font(.system(size: 10))
                    .foregroundStyle(repository.needsAttention ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 102, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.regular)
        .frame(height: 72)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
    }

    private var lastPushText: String {
        guard let pushedAt = repository.github.pushedAt else {
            return preferences.language.text("Chưa có lần push nào", "No pushes")
        }
        return preferences.language.text(
            "Push \(preferences.language.relativeDate(from: pushedAt))",
            "Pushed \(preferences.language.relativeDate(from: pushedAt))"
        )
    }

    private var branchName: String? {
        repository.tracking.focusBranch
            ?? repository.tracking.gitStatus?.branch
            ?? repository.github.defaultBranch
    }

    private var isCompleted: Bool {
        repository.tracking.status == .done || repository.displayProgress >= 100
    }

    private var visualProgress: Int {
        isCompleted ? 100 : repository.displayProgress
    }
}

private struct RepositoryGitSummaryBadge: View {
    @EnvironmentObject private var preferences: AppPreferences
    let status: LocalGitStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: primary.symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(primary.title)
                .lineLimit(1)
            if signals.count > 1 {
                Text("+\(signals.count - 1)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(primary.color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .frame(height: 21)
        .background(primary.color.opacity(0.1))
        .clipShape(Capsule())
        .help(signals.map(\.title).joined(separator: " · "))
    }

    private var primary: GitSignal {
        signals.first ?? GitSignal(
            title: preferences.language.text("Git chưa kiểm tra", "Git not checked"),
            symbol: "questionmark.circle",
            color: .secondary
        )
    }

    private var signals: [GitSignal] {
        var values: [GitSignal] = []
        if status.hasConflicts {
            values.append(GitSignal(
                title: preferences.language.text("Xung đột \(status.conflictCount)", "Conflicts \(status.conflictCount)"),
                symbol: "exclamationmark.triangle.fill",
                color: .red
            ))
        }
        if status.hasUncommittedChanges {
            values.append(GitSignal(
                title: preferences.language.text("Chưa commit \(status.changedFileCount)", "Uncommitted \(status.changedFileCount)"),
                symbol: "pencil.line",
                color: .orange
            ))
        }
        if status.hasUnpushedCommits {
            values.append(GitSignal(
                title: preferences.language.text("Chờ push \(status.aheadCount)", "To push \(status.aheadCount)"),
                symbol: "arrow.up",
                color: .blue
            ))
        }
        if status.behindCount > 0 {
            values.append(GitSignal(
                title: preferences.language.text("Cần pull \(status.behindCount)", "To pull \(status.behindCount)"),
                symbol: "arrow.down",
                color: .purple
            ))
        }
        if status.isCleanAndSynced {
            values.append(GitSignal(
                title: preferences.language.text("Đã đồng bộ", "Up to date"),
                symbol: "checkmark.circle.fill",
                color: .green
            ))
        } else if !status.hasUpstream && !status.hasUncommittedChanges {
            values.append(GitSignal(
                title: preferences.language.text("Chưa nối remote", "No remote branch"),
                symbol: "link.badge.plus",
                color: .secondary
            ))
        }
        return values
    }
}

private struct GitSignal {
    let title: String
    let symbol: String
    let color: Color
}

struct LocalGitBadgeRow: View {
    @EnvironmentObject private var preferences: AppPreferences
    let status: LocalGitStatus
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            if status.hasConflicts {
                LocalGitSignalPill(
                    title: preferences.language.text("Xung đột \(status.conflictCount)", "Conflicts \(status.conflictCount)"),
                    symbol: "exclamationmark.triangle.fill",
                    color: .red,
                    compact: compact
                )
            }

            if status.hasUncommittedChanges {
                LocalGitSignalPill(
                    title: preferences.language.text("Chưa commit \(status.changedFileCount)", "Uncommitted \(status.changedFileCount)"),
                    symbol: "pencil.line",
                    color: .orange,
                    compact: compact
                )
            }

            if status.hasUnpushedCommits {
                LocalGitSignalPill(
                    title: preferences.language.text("Chờ push \(status.aheadCount)", "To push \(status.aheadCount)"),
                    symbol: "arrow.up",
                    color: .blue,
                    compact: compact
                )
            }

            if status.behindCount > 0 {
                LocalGitSignalPill(
                    title: preferences.language.text("Cần pull \(status.behindCount)", "To pull \(status.behindCount)"),
                    symbol: "arrow.down",
                    color: .purple,
                    compact: compact
                )
            }

            if status.isCleanAndSynced {
                LocalGitSignalPill(
                    title: preferences.language.text("Đã đồng bộ", "Up to date"),
                    symbol: "checkmark.circle.fill",
                    color: .green,
                    compact: compact
                )
            } else if !status.hasUpstream && !status.hasUncommittedChanges {
                LocalGitSignalPill(
                    title: preferences.language.text("Chưa nối nhánh remote", "No remote branch"),
                    symbol: "link.badge.plus",
                    color: .secondary,
                    compact: compact
                )
            }
        }
    }
}

private struct LocalGitSignalPill: View {
    let title: String
    let symbol: String
    let color: Color
    let compact: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: compact ? 8.5 : 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

private struct MetadataCount: View {
    let symbol: String
    let value: Int

    var body: some View {
        Label("\(value)", systemImage: symbol)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct SummaryCard: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: Layout.regular) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Layout.regular)
        .panelStyle()
    }
}

struct RepositoryCollectionView: View {
    let repositories: [RepositoryRecord]
    @Binding var selectedRepositoryID: String?
    let emptyTitle: String
    let emptyMessage: String

    var body: some View {
        if repositories.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "shippingbox",
                description: Text(emptyMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)
        } else {
            ScrollView {
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
                .padding(Layout.compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)
        }
    }
}
