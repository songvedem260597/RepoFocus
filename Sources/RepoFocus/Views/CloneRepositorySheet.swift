import AppKit
import RepoFocusCore
import SwiftUI

private enum CloneSourceMode {
    case account
    case url
}

struct CloneRepositorySheet: View {
    @EnvironmentObject private var store: RepositoryStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss

    let initialRepositoryID: String?
    let onCloned: (String) -> Void

    @State private var sourceMode: CloneSourceMode = .account
    @State private var selectedRepositoryID: String?
    @State private var customRemoteURL = ""
    @State private var destinationParent = RepositoryStore.defaultCloneParentDirectory

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.section) {
                    sourceSection
                    destinationSection
                    cloneResult
                }
                .padding(Layout.section)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 510)
        .background(Color.appCanvas)
        .interactiveDismissDisabled(isCloning)
        .onAppear {
            store.resetCloneState()
            selectedRepositoryID = validInitialRepositoryID ?? accountRepositories.first?.id
            if accountRepositories.isEmpty {
                sourceMode = .url
            }
        }
    }

    private var header: some View {
        HStack(spacing: Layout.regular) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(preferences.language.text("Clone repository", "Clone repository"))
                    .font(.system(size: 17, weight: .semibold))
                Text(preferences.language.text(
                    "Tải source về máy và liên kết với RepoFocus.",
                    "Download the source and link it to RepoFocus."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 14)
            }
            .buttonStyle(FocusButtonStyle(role: .icon))
            .disabled(isCloning)
            .help(preferences.language.text("Đóng", "Close"))
        }
        .padding(Layout.section)
        .background(Color.headerBackground)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            sectionTitle(preferences.language.text("Nguồn repository", "Repository source"))

            HStack(spacing: 3) {
                sourceModeButton(
                    title: preferences.language.text("Từ tài khoản đã kết nối", "From connected accounts"),
                    symbol: "person.crop.circle",
                    mode: .account
                )
                sourceModeButton(
                    title: preferences.language.text("Dùng URL Git", "Use Git URL"),
                    symbol: "link",
                    mode: .url
                )
            }
            .padding(3)
            .frame(height: 38)
            .background(Color.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(Color.quietBorder, lineWidth: 1)
            }

            if sourceMode == .account {
                CloneRepositoryPicker(
                    repositories: accountRepositories,
                    selection: $selectedRepositoryID
                )
            } else {
                FocusTextInput(
                    placeholder: "https://github.com/owner/repo.git hoặc git@gitlab.com:group/repo.git",
                    text: $customRemoteURL,
                    leadingSymbol: "link"
                )
                Text(preferences.language.text(
                    "Hỗ trợ HTTPS, SSH và mọi remote URL mà Git trên máy có thể truy cập.",
                    "Supports GitHub, GitLab, HTTPS, SSH, and any remote URL available to Git on this Mac."
                ))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: Layout.regular) {
            sectionTitle(preferences.language.text("Lưu trên máy", "Save on this Mac"))

            HStack(spacing: Layout.compact) {
                FocusTextInput(
                    placeholder: preferences.language.text("Thư mục chứa các repo", "Parent folder for repositories"),
                    text: $destinationParent,
                    leadingSymbol: "folder"
                )

                Button {
                    chooseDestinationFolder()
                } label: {
                    Label(preferences.language.text("Chọn", "Choose"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(FocusButtonStyle(role: .secondary))
                .disabled(isCloning)
            }

            HStack(spacing: Layout.compact) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                Text(finalPathPreview)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var cloneResult: some View {
        switch store.cloneState {
        case .idle:
            EmptyView()
        case .cloning:
            Label(
                preferences.language.text("Đang clone repository…", "Cloning repository…"),
                systemImage: "arrow.down.circle"
            )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
        case .succeeded:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Label(
                preferences.language.text("RepoFocus chỉ chạy lệnh git clone.", "RepoFocus only runs git clone."),
                systemImage: "lock.shield"
            )
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(preferences.language.text("Hủy", "Cancel"))
            }
            .buttonStyle(FocusButtonStyle(role: .secondary))
            .disabled(isCloning)

            Button {
                startClone()
            } label: {
                Label(
                    isCloning
                        ? preferences.language.text("Đang clone…", "Cloning…")
                        : preferences.language.text("Clone về máy", "Clone to Mac"),
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(FocusButtonStyle(role: .primary))
            .disabled(!canClone || isCloning)
        }
        .padding(Layout.section)
        .background(Color.headerBackground)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func sourceModeButton(
        title: String,
        symbol: String,
        mode: CloneSourceMode
    ) -> some View {
        let isSelected = sourceMode == mode
        return Button {
            sourceMode = mode
            store.resetCloneState()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isSelected ? Color.elevatedBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.quietBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var accountRepositories: [RepositoryRecord] {
        store.repositories.filter { !$0.id.hasPrefix("sample-") && !$0.id.hasPrefix("external-") }
    }

    private var validInitialRepositoryID: String? {
        guard let initialRepositoryID,
              accountRepositories.contains(where: { $0.id == initialRepositoryID }) else {
            return nil
        }
        return initialRepositoryID
    }

    private var selectedRepository: RepositoryRecord? {
        accountRepositories.first { $0.id == selectedRepositoryID }
    }

    private var remoteURL: String {
        switch sourceMode {
        case .account:
            selectedRepository?.github.url.absoluteString ?? ""
        case .url:
            customRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var canClone: Bool {
        !remoteURL.isEmpty && !destinationParent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCloning: Bool {
        store.cloneState == .cloning
    }

    private var finalPathPreview: String {
        let parent = NSString(string: destinationParent).expandingTildeInPath
        guard let folderName = try? LocalRepositoryCloner.folderName(from: remoteURL),
              !folderName.isEmpty else {
            return preferences.language.text("Chọn nguồn repo để xem đường dẫn đích", "Choose a source to preview its destination")
        }
        return URL(fileURLWithPath: parent, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .path
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = preferences.language.text("Chọn thư mục lưu repository", "Choose a repository folder")
        panel.prompt = preferences.language.text("Chọn thư mục", "Choose Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: NSString(string: destinationParent).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            destinationParent = url.path
        }
    }

    private func startClone() {
        let targetRepositoryID = sourceMode == .account ? selectedRepositoryID : nil
        Task {
            if let repositoryID = await store.cloneRepository(
                repositoryID: targetRepositoryID,
                remoteURL: remoteURL,
                destinationParent: destinationParent
            ) {
                onCloned(repositoryID)
                dismiss()
            }
        }
    }
}

private struct CloneRepositoryPicker: View {
    @EnvironmentObject private var preferences: AppPreferences
    let repositories: [RepositoryRecord]
    @Binding var selection: String?

    @State private var isOpen = false
    @State private var searchText = ""

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: Layout.compact) {
                Image(systemName: selectedRepository?.github.isPrivate == true ? "lock.fill" : "shippingbox.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedRepository?.github.name ?? preferences.language.text("Chọn repository", "Choose repository"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let owner = selectedRepository?.github.nameWithOwner {
                        Text(owner)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(isOpen ? Color.elevatedBackground : Color.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(isOpen ? Color.accentColor : Color.quietBorder, lineWidth: isOpen ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: Layout.compact) {
                FocusTextInput(
                    placeholder: preferences.language.text("Tìm repository", "Search repositories"),
                    text: $searchText,
                    leadingSymbol: "magnifyingglass",
                    showsClearButton: true
                )

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredRepositories) { repository in
                            Button {
                                selection = repository.id
                                isOpen = false
                            } label: {
                                HStack(spacing: Layout.compact) {
                                    Image(systemName: repository.github.isPrivate ? "lock.fill" : "shippingbox")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repository.github.name)
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text(repository.github.nameWithOwner)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selection == repository.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 38)
                                .background(selection == repository.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 250)
            }
            .padding(8)
            .frame(width: 420)
        }
    }

    private var selectedRepository: RepositoryRecord? {
        repositories.first { $0.id == selection }
    }

    private var filteredRepositories: [RepositoryRecord] {
        guard !searchText.isEmpty else { return repositories }
        return repositories.filter {
            $0.github.nameWithOwner.localizedCaseInsensitiveContains(searchText)
        }
    }
}
