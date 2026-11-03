import SwiftData
import SwiftUI

/// Chips under an answer: what the model did with memory.
struct MemoryEventsView: View {
    let events: [MemoryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                Label(title(event), systemImage: icon(event.kind))
                    .font(.caption.bold())
                    .foregroundStyle(event.kind == .missing ? Theme.textSecondary : Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.1), in: .capsule)
            }
        }
    }

    private func title(_ event: MemoryEvent) -> LocalizedStringKey {
        switch event.kind {
        case .saved: "Zapamiętano: \(event.name)"
        case .updated: "Zaktualizowano w pamięci: \(event.name)"
        case .read: "Użyto pamięci: \(event.name)"
        case .deleted: "Zapomniano: \(event.name)"
        case .missing: "Brak w pamięci: \(event.name)"
        }
    }

    private func icon(_ kind: MemoryEvent.Kind) -> String {
        switch kind {
        case .saved, .updated: "brain.head.profile"
        case .read: "book.closed"
        case .deleted: "trash"
        case .missing: "questionmark.circle"
        }
    }
}

/// Settings → Pamięć → list of memories.
struct MemoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryItem.updatedAt, order: .reverse) private var memories: [MemoryItem]
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if memories.isEmpty {
                ContentUnavailableView {
                    Label("Pamięć jest pusta", systemImage: "brain.head.profile")
                } description: {
                    Text("Powiedz w czacie np. „Zapamiętaj, że mój pies ma na imię Burek” albo dodaj wspomnienie ręcznie.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(memories) { memory in
                NavigationLink {
                    MemoryEditView(memory: memory)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: memory.name).font(.headline)
                        Text(verbatim: memory.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if memory.useCount > 0 {
                            Text("Użyto \(memory.useCount)×").font(.caption2).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .onDelete { offsets in
                offsets.map { memories[$0] }.forEach(context.delete)
                try? context.save()
            }

            if !memories.isEmpty {
                Section {
                    Button("Usuń wszystkie wspomnienia", role: .destructive) { confirmDeleteAll = true }
                        .listRowBackground(Theme.surface)
                } footer: {
                    Text("Wspomnienia są zapisane tylko na tym telefonie. Model widzi w każdej nowej rozmowie listę nazw i opisów, a treść wczytuje tylko wtedy, gdy jest potrzebna.")
                }
            }
        }
        .secretBackground()
        .navigationTitle("Pamięć")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    MemoryEditView(memory: nil)
                } label: {
                    Label("Dodaj wspomnienie", systemImage: "plus")
                }
            }
        }
        .confirmationDialog("Usunąć wszystkie wspomnienia (\(memories.count))?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Usuń wszystkie", role: .destructive) {
                memories.forEach(context.delete)
                try? context.save()
            }
        }
    }
}

/// View / edit / create one memory.
struct MemoryEditView: View {
    let memory: MemoryItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""
    @State private var content = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Nazwa", text: $name)
            } header: {
                Text("Nazwa")
            } footer: {
                Text("Krótka, po niej model wczytuje wspomnienie.")
            }
            Section {
                TextField("Kiedy się przyda", text: $summary, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Opis")
            } footer: {
                Text("Jedno zdanie: czego dotyczy i kiedy się przyda. Na tej podstawie model decyduje, czy sięgnąć po treść.")
            }
            Section("Treść") {
                TextEditor(text: $content)
                    .frame(minHeight: 140)
            }
            if let memory {
                Section {
                    LabeledContent("Utworzono", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let used = memory.lastUsedAt {
                        LabeledContent("Ostatnio użyte", value: used.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Usuń wspomnienie", role: .destructive) {
                        context.delete(memory)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .secretBackground()
        .navigationTitle(memory == nil ? "Nowe wspomnienie" : "Wspomnienie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Zapisz", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = memory?.name ?? ""
            summary = memory?.summary ?? ""
            content = memory?.content ?? ""
        }
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let memory {
            memory.name = name
            memory.summary = summary.isEmpty ? content : summary
            memory.content = content
            memory.updatedAt = .now
        } else {
            context.insert(MemoryItem(name: name, summary: summary.isEmpty ? content : summary, content: content))
        }
        try? context.save()
        dismiss()
    }
}
