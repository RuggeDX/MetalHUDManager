import Foundation

/// Finds installed apps and reads their HUD state.
enum Scanner {
    /// Folders to search for .app bundles, with how deep to look in each.
    private static var roots: [(url: URL, maxDepth: Int)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (URL(fileURLWithPath: "/Applications"), 3),
            (home.appendingPathComponent("Applications"), 3),
            (home.appendingPathComponent("Library/Application Support/Steam/steamapps/common"), 4),
        ]
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

    static func scan(extra: [URL]) -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [AppEntry] = []
        func add(_ url: URL) {
            if let e = entry(for: url), seen.insert(e.id).inserted { out.append(e) }
        }

        for (root, maxDepth) in roots {
            guard let en = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in en {
                if en.level > maxDepth { en.skipDescendants(); continue }
                if url.pathExtension == "app" { add(url) }
            }
        }
        for url in extra where fm.fileExists(atPath: url.path) { add(url) }

        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func entry(for url: URL) -> AppEntry? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppEntry(id: id, name: name, url: url, hudEnabled: Prefs.isEnabled(bundleID: id),
                        detectedGame: looksLikeGame(url: url, info: info))
    }

    /// Best-effort guess: a games App Store category, game controller support,
    /// installed through Steam, or bundled with a known game engine.
    static func looksLikeGame(url: URL, info: [String: Any]) -> Bool {
        if let category = info["LSApplicationCategoryType"] as? String,
           category == "public.app-category.games" || category.hasSuffix("-games") { return true }
        if info["GCSupportsControllerUserInteraction"] != nil || info["GCSupportedGameControllers"] != nil {
            return true
        }
        if url.path.contains("/steamapps/common/") { return true }
        let fm = FileManager.default
        if gameMarkers.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) { return true }
        // Godot exports ship their game data as a .pck file.
        let resources = url.appendingPathComponent("Contents/Resources")
        if let files = try? fm.contentsOfDirectory(atPath: resources.path),
           files.contains(where: { $0.hasSuffix(".pck") }) {
            return true
        }
        return false
    }
}
