// MetalHUDManager.swift
// A small SwiftUI app to enable the Metal Performance HUD per application.
//
// Build as an .app with ./build-app.sh, or run directly:
//   swiftc -parse-as-library -O Sources/MetalHUDManager.swift -o MetalHUDManager
//   ./MetalHUDManager

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Build flavor

/// Development builds from ./dev.sh are compiled with -D DEV.
#if DEV
let appTitle = "Metal HUD Manager [DEV]"
#else
let appTitle = "Metal HUD Manager"
#endif

// MARK: - Model types

struct AppEntry: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
    let url: URL
    var hudEnabled: Bool
    let detectedGame: Bool  // heuristic, see Scanner.looksLikeGame; the user can override it
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
}

// MARK: - Preferences (reading/writing MetalForceHudEnabled)

enum Prefs {
    static let key = "MetalForceHudEnabled"

    private static func boolValue(_ v: CFPropertyList?) -> Bool {
        guard let v else { return false }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["1", "yes", "true"].contains(s.lowercased()) }
        return false
    }

    static func isEnabled(bundleID: String) -> Bool {
        let domain = bundleID as CFString
        CFPreferencesAppSynchronize(domain)
        return boolValue(CFPreferencesCopyAppValue(key as CFString, domain))
    }

    static func globalEnabled() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return boolValue(CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication))
    }

    /// Writes go through /usr/bin/defaults, which also handles sandboxed apps' containers.
    @discardableResult
    static func defaults(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }

    static func set(_ on: Bool, bundleID: String) {
        if on { defaults(["write", bundleID, key, "-bool", "YES"]) }
        else  { defaults(["delete", bundleID, key]) }
    }

    static func setGlobal(_ on: Bool) {
        if on { defaults(["write", "-g", key, "-bool", "YES"]) }
        else  { defaults(["delete", "-g", key]) }
    }
}

// MARK: - App scanner

enum Scanner {
    static func entry(for url: URL) -> AppEntry? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppEntry(id: id, name: name, url: url, hudEnabled: Prefs.isEnabled(bundleID: id),
                        detectedGame: looksLikeGame(url: url, info: info))
    }

    /// Files that common game engines and Steam's SDK put inside an app bundle.
    private static let gameMarkers = [
        "Contents/Frameworks/UnityPlayer.dylib",                // Unity
        "Contents/Resources/Data/Managed/UnityEngine.dll",      // Unity (older)
        "Contents/UE",                                          // Unreal Engine 5
        "Contents/UE4",                                         // Unreal Engine 4
        "Contents/Frameworks/libsteam_api.dylib",               // Steamworks
        "Contents/MacOS/libsteam_api.dylib",
    ]

    /// Best-effort guess: a games App Store category, game controller support,
    /// installed through Steam, or bundled with a known game engine.
    static func looksLikeGame(url: URL, info: [String: Any]) -> Bool {
        if let category = info["LSApplicationCategoryType"] as? String,
           category == "public.app-category.games" || category.hasSuffix("-games") { return true }
        if info["GCSupportsControllerUserInteraction"] != nil || info["GCSupportedGameControllers"] != nil { return true }
        if url.path.contains("/steamapps/common/") { return true }
        let fm = FileManager.default
        if gameMarkers.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) { return true }
        // Godot exports ship their game data as a .pck file.
        let resources = url.appendingPathComponent("Contents/Resources")
        if let files = try? fm.contentsOfDirectory(atPath: resources.path), files.contains(where: { $0.hasSuffix(".pck") }) {
            return true
        }
        return false
    }

    static func scan(extra: [URL]) -> [AppEntry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots: [(URL, Int)] = [
            (URL(fileURLWithPath: "/Applications"), 3),
            (home.appendingPathComponent("Applications"), 3),
            (home.appendingPathComponent("Library/Application Support/Steam/steamapps/common"), 4),
        ]

        var seen = Set<String>()
        var out: [AppEntry] = []

        for (root, maxDepth) in roots {
            guard let en = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in en {
                if en.level > maxDepth { en.skipDescendants(); continue }
                if url.pathExtension == "app", let e = entry(for: url), seen.insert(e.id).inserted {
                    out.append(e)
                }
            }
        }
        for url in extra where fm.fileExists(atPath: url.path) {
            if let e = entry(for: url), seen.insert(e.id).inserted { out.append(e) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Update checker

struct ReleaseInfo: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let body: String?
    let htmlUrl: URL
    let assets: [Asset]

    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

    /// The release's .dmg if it has one, otherwise the release page.
    var downloadURL: URL { assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadUrl ?? htmlUrl }
}

enum Updater {
    static let repo = "RuggeDX/MetalHUDManager"

    /// Dev builds run as a bare binary without an Info.plist, so they report 0.0.0.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Compares dotted version numbers. Anything after a "-" (e.g. "-dev") is ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            (v.split(separator: "-").first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Latest published release (drafts and pre-releases are excluded by GitHub).
    static func latestRelease() async throws -> ReleaseInfo {
        #if DEV
        if ProcessInfo.processInfo.environment["MHM_MOCK_UPDATE"] == "1" { return mockRelease }
        #endif
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReleaseInfo.self, from: data)
    }

    #if DEV
    /// Fake release for previewing the update UI: MHM_MOCK_UPDATE=1 ./dev.sh
    static let mockRelease = ReleaseInfo(
        tagName: "v9.9.9",
        body: """
        ## What's Changed
        * Add an **enable/disable all** switch by @RuggeDX in https://github.com/RuggeDX/MetalHUDManager/pull/1
        * Attach a `.dmg` to releases by @RuggeDX in https://github.com/RuggeDX/MetalHUDManager/pull/2
        * Check for [updates](https://github.com/RuggeDX/MetalHUDManager/releases) on launch by @RuggeDX in https://github.com/RuggeDX/MetalHUDManager/pull/3

        **Full Changelog**: https://github.com/RuggeDX/MetalHUDManager/compare/v1.0.0...v9.9.9
        """,
        htmlUrl: URL(string: "https://github.com/RuggeDX/MetalHUDManager/releases")!,
        assets: []
    )
    #endif
}

// MARK: - View model

@MainActor
final class Model: ObservableObject {
    @Published var apps: [AppEntry] = []
    @Published var globalOn = false
    @Published var loading = false
    @Published var search = ""
    @Published var filter = AppFilter(rawValue: UserDefaults.standard.string(forKey: "appFilter") ?? "") ?? .all {
        didSet { UserDefaults.standard.set(filter.rawValue, forKey: "appFilter") }
    }
    /// Per-app "is a game" choices that override the detection heuristic.
    @Published var gameOverrides = UserDefaults.standard.dictionary(forKey: "gameOverrides") as? [String: Bool] ?? [:] {
        didSet { UserDefaults.standard.set(gameOverrides, forKey: "gameOverrides") }
    }
    @Published var needsRestart: Set<String> = []
    @Published var bulkBusy = false
    @Published var update: ReleaseInfo?
    @Published var showUpdate = false

    private let extraKey = "extraAppPaths"
    private var extraPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: extraKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: extraKey) }
    }

    func isGame(_ app: AppEntry) -> Bool { gameOverrides[app.id] ?? app.detectedGame }

    /// Marks an app as a game or not. Choosing what the heuristic already says clears the override.
    func setGame(_ game: Bool, for app: AppEntry) {
        gameOverrides[app.id] = game == app.detectedGame ? nil : game
    }

    var filtered: [AppEntry] {
        apps.filter { app in
            let matchesFilter = switch filter {
            case .all: true
            case .games: isGame(app)
            case .enabled: app.hudEnabled
            }
            return matchesFilter &&
            (search.isEmpty
             || app.name.localizedCaseInsensitiveContains(search)
             || app.id.localizedCaseInsensitiveContains(search))
        }
    }

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

    func isRunning(_ app: AppEntry) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.id).isEmpty
    }

    func setHUD(_ on: Bool, for app: AppEntry) {
        Prefs.set(on, bundleID: app.id)
        if let i = apps.firstIndex(where: { $0.id == app.id }) {
            apps[i].hudEnabled = Prefs.isEnabled(bundleID: app.id)
        }
        if isRunning(app) { needsRestart.insert(app.id) }
    }

    /// Enables or disables the HUD for several apps at once.
    /// Runs off the main thread since each change spawns /usr/bin/defaults.
    func setHUD(_ on: Bool, for targets: [AppEntry]) {
        let changed = targets.filter { $0.hudEnabled != on }
        guard !changed.isEmpty else { return }
        bulkBusy = true
        let ids = changed.map(\.id)
        Task.detached {
            let results = ids.map { id -> (String, Bool) in
                Prefs.set(on, bundleID: id)
                return (id, Prefs.isEnabled(bundleID: id))
            }
            await MainActor.run {
                for (id, enabled) in results {
                    if let i = self.apps.firstIndex(where: { $0.id == id }) { self.apps[i].hudEnabled = enabled }
                }
                for app in changed where self.isRunning(app) { self.needsRestart.insert(app.id) }
                self.bulkBusy = false
            }
        }
    }

    func setGlobal(_ on: Bool) {
        Prefs.setGlobal(on)
        globalOn = Prefs.globalEnabled()
    }

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
}

// MARK: - Views

struct AppRow: View {
    let app: AppEntry
    @ObservedObject var model: Model

    var body: some View {
        let running = model.isRunning(app)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                    if model.isGame(app) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Game")
                    }
                    if running {
                        Text("running")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    }
                }
                Text(app.id).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if running && model.needsRestart.contains(app.id) {
                Button("Restart to apply") { model.relaunch(app, envHUD: false) }
                    .controlSize(.small)
            }

            Menu {
                Button(running ? "Relaunch" : "Launch") { model.relaunch(app, envHUD: false) }
                Button("Launch once with HUD (env var)") { model.relaunch(app, envHUD: true) }
                Divider()
                if model.isGame(app) {
                    Button("Not a Game") { model.setGame(false, for: app) }
                } else {
                    Button("Mark as Game") { model.setGame(true, for: app) }
                }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Toggle("HUD", isOn: Binding(
                get: { app.hudEnabled },
                set: { model.setHUD($0, for: app) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

struct BulkToggleRow: View {
    @ObservedObject var model: Model
    @State private var pending: Bool?

    var body: some View {
        let shown = model.filtered
        let enabledCount = shown.filter(\.hudEnabled).count
        let allOn = !shown.isEmpty && enabledCount == shown.count
        let title = !model.search.isEmpty ? "All shown apps"
            : model.filter == .games ? "All games"
            : model.filter == .enabled ? "All shown apps"
            : "All apps"

        HStack(spacing: 10) {
            Text(title).font(.headline)
            Text("\(enabledCount) of \(shown.count) enabled").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.bulkBusy { ProgressView().controlSize(.small) }
            Toggle("HUD for all", isOn: Binding(
                get: { allOn },
                set: { pending = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(shown.isEmpty || model.bulkBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .confirmationDialog(
            pending == true ? "Enable the HUD for \(shown.count - enabledCount) apps?"
                            : "Disable the HUD for \(enabledCount) apps?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button(pending == true ? "Enable All" : "Disable All") {
                if let on = pending { model.setHUD(on, for: model.filtered) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Running apps need a restart for the change to take effect.")
        }
    }
}

/// Renders GitHub release notes: headings, bullet lists and inline Markdown (bold, code, links).
struct ChangelogView: View {
    let markdown: String

    var body: some View {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty { Text("No release notes.").foregroundStyle(.secondary) }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("#") {
                    Text(inline(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
                        .font(.headline)
                } else if line.hasPrefix("* ") || line.hasPrefix("- ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
                } else {
                    Text(inline(line))
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct UpdateSheet: View {
    let release: ReleaseInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A new version is available").font(.title2.bold())
                    Text("Metal HUD Manager \(release.version) is available. You have \(Updater.currentVersion).")
                        .foregroundStyle(.secondary)
                }
            }

            Text("What's new").font(.headline)
            ScrollView {
                ChangelogView(markdown: release.body ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 160, maxHeight: 300)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            HStack {
                Link("View on GitHub", destination: release.htmlUrl)
                Spacer()
                Button("Later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download") {
                    NSWorkspace.shared.open(release.downloadURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.globalOn {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The HUD is enabled globally, so it shows in every Metal app.")
                        Spacer()
                        Button("Turn off global") { model.setGlobal(false) }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                }

                BulkToggleRow(model: model)
                Divider()

                List(model.filtered) { app in
                    AppRow(app: app, model: model)
                }
                .overlay {
                    if model.loading { ProgressView("Scanning apps…") }
                    else if model.filtered.isEmpty { Text("No apps match.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(appTitle)
            .searchable(text: $model.search, prompt: "Search apps")
            .toolbar {
                ToolbarItem {
                    if let update = model.update {
                        Button { model.showUpdate = true } label: {
                            Label("Update Available", systemImage: "arrow.down.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                        }
                        .help("Version \(update.version) is available")
                    }
                }
                ToolbarItemGroup {
                    Picker("Show", selection: $model.filter) {
                        ForEach(AppFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .help("Filter the list")
                    Button { model.addApp() } label: { Label("Add App…", systemImage: "plus") }
                    Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .sheet(isPresented: $model.showUpdate) {
            if let update = model.update { UpdateSheet(release: update) }
        }
        .onAppear {
            model.reload()
            model.checkForUpdates()
        }
    }
}

@main
struct MetalHUDManagerApp: App {
    init() {
        // Needed when run as a bare binary from Terminal so it gets a Dock icon and focus.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup(appTitle) { ContentView() }
    }
}
