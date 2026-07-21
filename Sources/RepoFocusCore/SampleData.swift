import Foundation

public enum SampleData {
    public static let repositories: [RepositoryRecord] = {
        let calendar = Calendar.current

        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        }

        func deadline(daysFromNow: Int) -> Date {
            calendar.date(byAdding: .day, value: daysFromNow, to: .now) ?? .now
        }

        return [
            RepositoryRecord(
                github: GitHubRepository(
                    id: "sample-1",
                    name: "atlas-macos",
                    nameWithOwner: "yourname/atlas-macos",
                    url: URL(string: "https://github.com")!,
                    description: "Không gian tập trung để lập kế hoạch và đưa sản phẩm tới đích.",
                    isPrivate: true,
                    primaryLanguage: "Swift",
                    languageColor: "#F05138",
                    defaultBranch: "main",
                    openIssueCount: 8,
                    openPullRequestCount: 2,
                    pushedAt: date(daysAgo: 1),
                    updatedAt: date(daysAgo: 1)
                ),
                tracking: RepositoryTracking(
                    repositoryID: "sample-1",
                    status: .active,
                    priority: .high,
                    progress: 68,
                    nextAction: "Hoàn thiện đồng bộ repo và các trạng thái trống",
                    notes: "Bản đầu tiên chỉ đọc dữ liệu từ GitHub.",
                    isFocused: true,
                    focusOrder: 0,
                    deadline: deadline(daysFromNow: 5)
                )
            ),
            RepositoryRecord(
                github: GitHubRepository(
                    id: "sample-2",
                    name: "signal-api",
                    nameWithOwner: "yourname/signal-api",
                    url: URL(string: "https://github.com")!,
                    description: "API và tác vụ nền phục vụ tín hiệu tiến độ dự án.",
                    isPrivate: true,
                    primaryLanguage: "TypeScript",
                    languageColor: "#3178C6",
                    defaultBranch: "main",
                    openIssueCount: 13,
                    openPullRequestCount: 1,
                    pushedAt: date(daysAgo: 4),
                    updatedAt: date(daysAgo: 4)
                ),
                tracking: RepositoryTracking(
                    repositoryID: "sample-2",
                    status: .blocked,
                    priority: .high,
                    progress: 42,
                    nextAction: "Chốt cấu trúc dữ liệu sự kiện",
                    notes: "Đang chờ duyệt cấu trúc dữ liệu.",
                    isFocused: true,
                    focusOrder: 1,
                    deadline: deadline(daysFromNow: -1)
                )
            ),
            RepositoryRecord(
                github: GitHubRepository(
                    id: "sample-3",
                    name: "studio-web",
                    nameWithOwner: "yourname/studio-web",
                    url: URL(string: "https://github.com")!,
                    description: "Trang giới thiệu và tài liệu sản phẩm.",
                    primaryLanguage: "Astro",
                    languageColor: "#BC52EE",
                    defaultBranch: "main",
                    openIssueCount: 4,
                    openPullRequestCount: 0,
                    pushedAt: date(daysAgo: 8),
                    updatedAt: date(daysAgo: 8)
                ),
                tracking: RepositoryTracking(
                    repositoryID: "sample-3",
                    status: .active,
                    priority: .medium,
                    progress: 25,
                    nextAction: "Viết lại trang hướng dẫn bắt đầu",
                    isFocused: true,
                    focusOrder: 2
                )
            ),
            RepositoryRecord(
                github: GitHubRepository(
                    id: "sample-4",
                    name: "design-tokens",
                    nameWithOwner: "yourname/design-tokens",
                    url: URL(string: "https://github.com")!,
                    description: "Bộ màu sắc, typography và spacing dùng chung.",
                    primaryLanguage: "JavaScript",
                    languageColor: "#F1E05A",
                    defaultBranch: "main",
                    openIssueCount: 1,
                    openPullRequestCount: 0,
                    pushedAt: date(daysAgo: 30),
                    updatedAt: date(daysAgo: 30)
                ),
                tracking: RepositoryTracking(
                    repositoryID: "sample-4",
                    status: .paused,
                    priority: .low,
                    progress: 80,
                    nextAction: "Rà soát cách đặt tên trước bản phát hành tiếp theo"
                )
            ),
            RepositoryRecord(
                github: GitHubRepository(
                    id: "sample-5",
                    name: "cli-tools",
                    nameWithOwner: "yourname/cli-tools",
                    url: URL(string: "https://github.com")!,
                    description: "Các công cụ tự động hóa nhỏ dùng cho nhiều dự án.",
                    primaryLanguage: "Go",
                    languageColor: "#00ADD8",
                    defaultBranch: "main",
                    openIssueCount: 0,
                    openPullRequestCount: 0,
                    pushedAt: date(daysAgo: 12),
                    updatedAt: date(daysAgo: 12)
                ),
                tracking: RepositoryTracking(
                    repositoryID: "sample-5",
                    status: .done,
                    priority: .medium,
                    progress: 100,
                    nextAction: "",
                    notes: "Đã phát hành phiên bản 1.0."
                )
            )
        ]
    }()
}
