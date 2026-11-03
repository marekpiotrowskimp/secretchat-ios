import SwiftData
import SwiftUI

struct ConversationListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var allConversations: [Conversation]
    @State private var path: [Conversation] = []
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var showSettings = false

    /// Empty conversations (opened but never used) are not listed.
    private var conversations: [Conversation] { allConversations.filter { !$0.messages.isEmpty } }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("Brak rozmów", systemImage: "lock.shield")
                    } description: {
                        Text("Zacznij nową rozmowę. Wszystko działa offline — nic nie opuszcza telefonu.")
                    } actions: {
                        Button("Nowa rozmowa", action: newConversation)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Rozmowy")
            .secretBackground()
            .safeAreaInset(edge: .top) {
                HStack {
                    PrivacyBadge()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ustawienia", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nowa rozmowa", systemImage: "square.and.pencil", action: newConversation)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Zmień nazwę", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nazwa", text: $newTitle)
                Button("Zapisz") {
                    renaming?.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    renaming = nil
                }
                Button("Anuluj", role: .cancel) { renaming = nil }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(conversations) { conversation in
                NavigationLink(value: conversation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversation.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(conversation.updatedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Theme.surface)
                .contextMenu {
                    Button("Zmień nazwę", systemImage: "pencil") {
                        newTitle = conversation.title
                        renaming = conversation
                    }
                    Button("Usuń", systemImage: "trash", role: .destructive) { context.delete(conversation) }
                }
            }
            .onDelete { offsets in
                offsets.map { conversations[$0] }.forEach(context.delete)
            }
        }
    }

    private func newConversation() {
        // Reuse an existing empty conversation instead of piling up blank ones.
        if let empty = allConversations.first(where: { $0.messages.isEmpty }) {
            path = [empty]
            return
        }
        let conversation = Conversation()
        context.insert(conversation)
        path = [conversation]
    }
}
