import AppKit
import RepoFocusCore
import SwiftUI

@main
struct RepoFocusApp: App {
    @StateObject private var store = RepositoryStore()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var reminderService = ProjectReminderService()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(store)
                .environmentObject(preferences)
                .environmentObject(reminderService)
                .environment(\.locale, preferences.language.locale)
                .preferredColorScheme(preferences.theme.colorScheme)
                .tint(Color.brandAccent)
                .background(WindowChromeConfigurator())
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    await reminderService.refreshAuthorizationState()
                    if store.connectionState == .ready {
                        await store.sync()
                    }
                    if store.gitLabConnectionState == .ready {
                        await store.syncGitLab()
                    }
                    await store.autoDetectLocalRepositories()
                    await store.checkAllLocalGit()
                    await updateReminderSchedule(requestAuthorization: false)
                }
                .onChange(of: preferences.remindersEnabled) {
                    Task {
                        await updateReminderSchedule(requestAuthorization: preferences.remindersEnabled)
                    }
                }
                .onChange(of: preferences.reminderTimeMinutes) {
                    Task { await updateReminderSchedule(requestAuthorization: false) }
                }
                .onChange(of: preferences.language) {
                    Task { await updateReminderSchedule(requestAuthorization: false) }
                }
                .onChange(of: store.repositories) {
                    Task { await updateReminderSchedule(requestAuthorization: false) }
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandMenu(preferences.language.text("Repo", "Repository")) {
                Button(preferences.language.text("Đồng bộ GitHub và GitLab", "Sync GitHub and GitLab")) {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isSyncingSources)
            }
        }
    }

    @MainActor
    private func updateReminderSchedule(requestAuthorization: Bool) async {
        let items = store.todayReminderItems()
        reminderService.updateDockBadge(
            count: items.count,
            isEnabled: preferences.remindersEnabled
        )

        guard preferences.remindersEnabled else {
            reminderService.cancelDailyReminder()
            return
        }
        if requestAuthorization,
           !(await reminderService.requestAuthorizationIfNeeded()) {
            return
        }
        await reminderService.scheduleDailyReminder(
            items: items,
            minutesFromMidnight: preferences.reminderTimeMinutes,
            language: preferences.language
        )
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView()
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.applyWindowStyle()
    }
}

private final class WindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowStyle()
    }

    func applyWindowStyle() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar?.isVisible = false
        }
    }
}
