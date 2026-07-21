import RepoFocusCore
import SwiftUI

struct StatusChip: View {
    @EnvironmentObject private var preferences: AppPreferences
    let status: WorkStatus

    var body: some View {
        Label(status.localizedTitle(preferences.language), systemImage: status.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct RepositoryRow: View {
    @EnvironmentObject private var preferences: AppPreferences
    let repository: RepositoryRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Layout.regular) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(repository.tracking.status.color.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: repository.github.isPrivate ? "lock.fill" : "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(repository.tracking.status.color)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Layout.compact) {
                    Text(repository.github.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    StatusChip(status: repository.tracking.status)

                    if repository.tracking.priority == .high {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(repository.tracking.priority.color)
                            .help(preferences.language.text("Ưu tiên cao", "High priority"))
                    }
                }

                Text(repository.tracking.nextAction.isEmpty
                    ? preferences.language.text("Chưa có việc tiếp theo", "No next action")
                    : repository.tracking.nextAction)
                    .font(.system(size: 11))
                    .foregroundStyle(repository.tracking.nextAction.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)

                if let gitStatus = repository.tracking.gitStatus {
                    LocalGitBadgeRow(status: gitStatus, compact: true)
                }
            }

            Spacer(minLength: Layout.regular)

            Group {
                if repository.tracking.deadline != nil {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(repository.tracking.progress)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        ProgressView(value: Double(repository.tracking.progress), total: 100)
                            .tint(repository.tracking.status.color)
                            .frame(width: 72)
                    }
                } else {
                    Color.clear
                        .frame(width: 72, height: 28)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: Layout.compact) {
                    MetadataCount(symbol: "smallcircle.filled.circle", value: repository.github.openIssueCount)
                    MetadataCount(symbol: "arrow.triangle.pull", value: repository.github.openPullRequestCount)
                }

                Text(lastPushText)
                    .font(.system(size: 10))
                    .foregroundStyle(repository.needsAttention ? Color.orange : Color.secondary)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, Layout.regular)
        .padding(.vertical, 10)
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
                .padding(Layout.compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appCanvas)
        }
    }
}
