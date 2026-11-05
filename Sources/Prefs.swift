import Foundation

/// Reads and writes MetalForceHudEnabled, per app or globally.
enum Prefs {
    static let key = "MetalForceHudEnabled"

    static func isEnabled(bundleID: String) -> Bool { read(domain: bundleID as CFString) }
    static func globalEnabled() -> Bool { read(domain: kCFPreferencesAnyApplication) }

    static func set(_ on: Bool, bundleID: String) { write(on, domain: bundleID) }
    static func setGlobal(_ on: Bool) { write(on, domain: "-g") }

    private static func read(domain: CFString) -> Bool {
        CFPreferencesAppSynchronize(domain)
        return boolValue(CFPreferencesCopyAppValue(key as CFString, domain))
    }

    private static func boolValue(_ v: CFPropertyList?) -> Bool {
        guard let v else { return false }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["1", "yes", "true"].contains(s.lowercased()) }
        return false
    }

    /// Writes go through /usr/bin/defaults, which also handles sandboxed apps' containers.
    private static func write(_ on: Bool, domain: String) {
        defaults(on ? ["write", domain, key, "-bool", "YES"] : ["delete", domain, key])
    }

    @discardableResult
    private static func defaults(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
