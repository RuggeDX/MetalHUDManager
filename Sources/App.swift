// Metal HUD Manager
// A small SwiftUI app to enable the Metal Performance HUD per application.
//
// Build as an .app with ./build-app.sh, or run directly:
//   swiftc -parse-as-library -O $(find Sources -name '*.swift') -o MetalHUDManager
//   ./MetalHUDManager

import SwiftUI
import AppKit

// MARK: - Build flavor

/// Development builds from ./dev.sh are compiled with -D DEV.
#if DEV
let appTitle = "Metal HUD Manager [DEV]"
#else
let appTitle = "Metal HUD Manager"
#endif

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
