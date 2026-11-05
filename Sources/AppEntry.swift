import AppKit

struct AppEntry: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
    let url: URL
    var hudEnabled: Bool
    let detectedGame: Bool  // heuristic, see Scanner.looksLikeGame; the user can override it

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    func matches(search: String) -> Bool {
        search.isEmpty
            || name.localizedCaseInsensitiveContains(search)
            || id.localizedCaseInsensitiveContains(search)
    }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case all, games, enabled
    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Apps"
        case .games: "Games"
        case .enabled: "HUD Enabled"
        }
    }

    func includes(_ app: AppEntry, isGame: Bool) -> Bool {
        switch self {
        case .all: true
        case .games: isGame
        case .enabled: app.hudEnabled
        }
    }
}
