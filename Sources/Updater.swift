import Foundation

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
