import Foundation

public enum CodexWorkspaceLink {
    public static func newTaskURL(workspacePath: String) -> URL? {
        let expandedPath = NSString(string: workspacePath)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard expandedPath.hasPrefix("/"), !expandedPath.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "path", value: expandedPath)
        ]
        return components.url
    }
}
