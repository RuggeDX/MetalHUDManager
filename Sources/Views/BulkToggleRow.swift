import SwiftUI

struct BulkToggleRow: View {
    @ObservedObject var model: Model
    @State private var pending: Bool?

    private var title: String {
        guard model.search.isEmpty else { return "All shown apps" }
        switch model.filter {
        case .all: return "All apps"
        case .games: return "All games"
        case .enabled: return "All shown apps"
        }
    }

    var body: some View {
        let shown = model.filtered
        let enabledCount = shown.filter(\.hudEnabled).count
        let allOn = !shown.isEmpty && enabledCount == shown.count

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
