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
        return AppEntry(id: id, name: name, url: url, hudEnabled: Prefs.isEnabled(bundleID: id))
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

// MARK: - View model

@MainActor
final class Model: ObservableObject {
    @Published var apps: [AppEntry] = []
    @Published var globalOn = false
    @Published var loading = false
    @Published var search = ""
    @Published var onlyEnabled = false
    @Published var needsRestart: Set<String> = []
    @Published var bulkBusy = false

    private let extraKey = "extraAppPaths"
    private var extraPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: extraKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: extraKey) }
    }

    var filtered: [AppEntry] {
        apps.filter { app in
            (!onlyEnabled || app.hudEnabled) &&
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
        let filtering = model.onlyEnabled || !model.search.isEmpty

        HStack(spacing: 10) {
            Text(filtering ? "All shown apps" : "All apps").font(.headline)
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
                ToolbarItemGroup {
                    Toggle("Enabled only", isOn: $model.onlyEnabled)
                    Button { model.addApp() } label: { Label("Add App…", systemImage: "plus") }
                    Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .onAppear { model.reload() }
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
