import AppKit
import RepoFocusCore
import SwiftUI

@main
struct RepoFocusApp: App {
    @StateObject private var store = RepositoryStore()
    @StateObject private var preferences = AppPreferences()

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
                .environment(\.locale, preferences.language.locale)
                .preferredColorScheme(preferences.theme.colorScheme)
                .tint(Color.brandAccent)
                .background(WindowChromeConfigurator())
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    if store.connectionState == .ready {
                        await store.sync()
                    }
                    await store.checkAllLocalGit()
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            CommandMenu(preferences.language.text("Repo", "Repository")) {
                Button(preferences.language.text("Đồng bộ với GitHub", "Sync with GitHub")) {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.connectionState == .syncing)
            }
        }
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
