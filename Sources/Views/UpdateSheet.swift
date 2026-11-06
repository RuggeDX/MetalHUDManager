import AppKit
import SwiftUI

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
