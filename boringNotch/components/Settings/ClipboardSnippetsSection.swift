//
//  ClipboardSnippetsSection.swift
//  NotchFun
//

import Defaults
import SwiftUI

/// Settings → Clipboard → Snippets: add, edit and remove named texts.
struct ClipboardSnippetsSection: View {
    @Default(.clipboardSnippets) private var snippets
    @State private var editing: ClipboardSnippet?

    var body: some View {
        Section {
            if snippets.isEmpty {
                Text("None yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(snippets) { snippet in
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snippet.name)
                        Text(snippet.text.replacingOccurrences(of: "\n", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Edit") { editing = snippet }
                        .buttonStyle(.borderless)
                    Button {
                        snippets.removeAll { $0.id == snippet.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this snippet")
                }
            }
            Button("Add Snippet…") {
                editing = ClipboardSnippet(name: "", text: "")
            }
        } header: {
            Text("Snippets")
        } footer: {
            Text("Text you paste often, like an address or a reply. In the clipboard tab, start typing a snippet's name and press Return.")
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { saved in
                if let index = snippets.firstIndex(where: { $0.id == saved.id }) {
                    snippets[index] = saved
                } else {
                    snippets.append(saved)
                }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }
}

private struct SnippetEditor: View {
    @State var snippet: ClipboardSnippet
    let onSave: (ClipboardSnippet) -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !snippet.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snippet.name.isEmpty && snippet.text.isEmpty ? "New Snippet" : "Edit Snippet")
                .font(.headline)
            TextField("Name", text: $snippet.name, prompt: Text("Home address"))
            TextEditor(text: $snippet.text)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    snippet.name = snippet.name.trimmingCharacters(in: .whitespaces)
                    onSave(snippet)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
