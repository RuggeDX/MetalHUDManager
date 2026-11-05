import SwiftUI
import AppKit

struct AppRow: View {
    let app: AppEntry
    @ObservedObject var model: Model

    var body: some View {
        let running = app.isRunning
        let isGame = model.isGame(app)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                    if isGame {
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
                Button(isGame ? "Not a Game" : "Mark as Game") { model.setGame(!isGame, for: app) }
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
