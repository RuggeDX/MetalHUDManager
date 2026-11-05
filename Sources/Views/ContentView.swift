import SwiftUI

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.globalOn { GlobalHUDBanner(model: model) }

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
            .toolbar { toolbar }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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

/// Warning shown while the HUD is forced on for every app.
struct GlobalHUDBanner: View {
    @ObservedObject var model: Model

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("The HUD is enabled globally, so it shows in every Metal app.")
            Spacer()
            Button("Turn off global") { model.setGlobal(false) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
    }
}
