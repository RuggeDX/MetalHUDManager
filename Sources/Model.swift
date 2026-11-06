import AppKit
import SwiftUI

@MainActor
final class Model: ObservableObject {
    private enum Keys {
        static let filter = "appFilter"
        static let gameOverrides = "gameOverrides"
        static let extraPaths = "extraAppPaths"
    }

    @Published var apps: [AppEntry] = []
    @Published var globalOn = false
    @Published var loading = false
    @Published var search = ""
    @Published var filter = AppFilter(rawValue: UserDefaults.standard.string(forKey: Keys.filter) ?? "") ?? .all {
        didSet { UserDefaults.standard.set(filter.rawValue, forKey: Keys.filter) }
    }
    /// Per-app "is a game" choices that override the detection heuristic.
    @Published var gameOverrides =
        UserDefaults.standard.dictionary(forKey: Keys.gameOverrides) as? [String: Bool] ?? [:] {
        didSet { UserDefaults.standard.set(gameOverrides, forKey: Keys.gameOverrides) }
    }
    @Published var needsRestart: Set<String> = []
    @Published var bulkBusy = false
    @Published var update: ReleaseInfo?
    @Published var showUpdate = false

    private var extraPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: Keys.extraPaths) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Keys.extraPaths) }
    }

    var filtered: [AppEntry] {
        apps.filter { filter.includes($0, isGame: isGame($0)) && $0.matches(search: search) }
    }

    // MARK: Loading

    func reload() {
        loading = true
        let extras = extraPaths.map { URL(fileURLWithPath: $0) }
        Task.detached {
            let list = Scanner.scan(extra: extras)
            let global = Prefs.globalEnabled()
            await MainActor.run {
                self.apps = list
                self.globalOn = global
                self.loading = false
            }
        }
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var paths = extraPaths
        for url in panel.urls where !paths.contains(url.path) { paths.append(url.path) }
        extraPaths = paths
        reload()
    }

    func checkForUpdates() {
        Task {
            do {
                let release = try await Updater.latestRelease()
                if Updater.isNewer(release.version, than: Updater.currentVersion) { update = release }
            } catch {
                NSLog("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Game classification

    func isGame(_ app: AppEntry) -> Bool { gameOverrides[app.id] ?? app.detectedGame }

    /// Marks an app as a game or not. Choosing what the heuristic already says clears the override.
    func setGame(_ game: Bool, for app: AppEntry) {
        gameOverrides[app.id] = game == app.detectedGame ? nil : game
    }

    // MARK: HUD settings

    func setHUD(_ on: Bool, for app: AppEntry) {
        apply(Self.writeHUD(on, for: [app]), to: [app])
    }

    /// Enables or disables the HUD for several apps at once.
    /// Runs off the main thread since each change spawns /usr/bin/defaults.
    func setHUD(_ on: Bool, for targets: [AppEntry]) {
        let changed = targets.filter { $0.hudEnabled != on }
        guard !changed.isEmpty else { return }
        bulkBusy = true
        Task.detached {
            let states = Self.writeHUD(on, for: changed)
            await MainActor.run {
                self.apply(states, to: changed)
                self.bulkBusy = false
            }
        }
    }

    func setGlobal(_ on: Bool) {
        Prefs.setGlobal(on)
        globalOn = Prefs.globalEnabled()
    }

    /// Writes the setting for each app and returns what was actually stored, by bundle ID.
    nonisolated private static func writeHUD(_ on: Bool, for apps: [AppEntry]) -> [String: Bool] {
        Dictionary(apps.map { app in
            Prefs.set(on, bundleID: app.id)
            return (app.id, Prefs.isEnabled(bundleID: app.id))
        }, uniquingKeysWith: { _, last in last })
    }

    /// Updates the list with the stored states and flags running apps for a restart.
    private func apply(_ states: [String: Bool], to changed: [AppEntry]) {
        for i in apps.indices {
            if let enabled = states[apps[i].id] { apps[i].hudEnabled = enabled }
        }
        for app in changed where app.isRunning { needsRestart.insert(app.id) }
    }

    // MARK: Launching

    /// Quits the app if it's running, then launches it.
    /// envHUD = true launches it once with MTL_HUD_ENABLED=1 (no persistent setting).
    func relaunch(_ app: AppEntry, envHUD: Bool) {
        needsRestart.remove(app.id)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.id)
        running.forEach { $0.terminate() }
        Task {
            var waited = 0
            while !running.allSatisfy({ $0.isTerminated }) && waited < 50 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
            let cfg = NSWorkspace.OpenConfiguration()
            if envHUD { cfg.environment = ["MTL_HUD_ENABLED": "1"] }
            NSWorkspace.shared.openApplication(at: app.url, configuration: cfg) { _, error in
                if let error { NSLog("Launch failed for \(app.id): \(error.localizedDescription)") }
            }
        }
    }
}
