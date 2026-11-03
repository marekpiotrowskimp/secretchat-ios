import GemmaKit
import SwiftData
import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var model: ChatViewModel?

    var body: some View {
        Group {
            if let model {
                ChatContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model == nil { model = ChatViewModel(conversation: conversation, app: app, context: context) }
        }
    }
}

private struct ChatContent: View {
    @Bindable var model: ChatViewModel
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            // Not lazy on purpose: a LazyVStack only estimates the height of rows it hasn't laid out,
            // and with tall, uneven answers (Markdown, code, formulas) "scroll to bottom" landed on a
            // wrong offset — sometimes far below the last message, on an empty screen.
            VStack(alignment: .leading, spacing: 18) {
                if model.conversation.messages.isEmpty, !model.isBusy {
                    emptyState
                }
                ForEach(model.conversation.orderedMessages) { message in
                    switch message.role {
                    case .user:
                        UserMessageView(text: message.text, images: message.images)
                    case .assistant:
                        AssistantMessageView(text: message.text, thinking: message.thinking, stats: message.stats,
                                             webQuery: message.webQuery, sources: message.sources, messageID: message.id,
                                             memoryEvents: message.memoryEvents)
                    case .system:
                        EmptyView()
                    }
                }
                if model.isBusy { streamingMessage }
                if let notice = model.webNotice, !model.isBusy {
                    Label(notice, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if model.webApprovedForConversation {
                    // Searching without asking stays visible and can be turned off with one tap.
                    HStack(spacing: 6) {
                        Label("Wyszukiwanie bez pytania w tej rozmowie", systemImage: "globe")
                            .foregroundStyle(Theme.internet)
                        Spacer()
                        Button("Pytaj ponownie") { model.revokeWebApproval() }
                            .buttonStyle(.bordered)
                            .tint(Theme.internet)
                    }
                    .font(.footnote)
                }
                if model.lastTrimmedMessages > 0, !model.isBusy {
                    // Earlier answers are shortened first; this shows only when whole turns no longer fit.
                    Label("Rozmowa jest długa — \(model.lastTrimmedMessages) najstarszych wiadomości nie mieści się już w pamięci modelu. Możesz wydłużyć kontekst w Ustawieniach (Pamięć rozmowy) albo zacząć nową rozmowę.", systemImage: "text.badge.minus")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { errorBanner(error) }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        // A new question and the finished answer always end up on screen, wherever the user scrolled.
        .onChange(of: model.conversation.messages.count) { scrollToBottom() }
        .onChange(of: model.isBusy) { scrollToBottom() }
        .secretBackground()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) { thermalBanner }
        .safeAreaInset(edge: .bottom) { ComposerView(model: model) }
        .toolbar {
            if app.speech.speakingID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    // Green speaker with moving waves = "reading aloud now"; tap stops it.
                    Button { app.speech.stop() } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel(Text("Zatrzymaj czytanie"))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.setVoiceMode(!model.voiceMode)
                } label: {
                    Label(model.voiceMode ? "Wyłącz tryb głosowy" : "Tryb głosowy",
                          systemImage: model.voiceMode ? "waveform.circle.fill" : "waveform.circle")
                }
                .tint(model.voiceMode ? .red : nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $settings.thinkingEnabled) {
                    Label("Tryb myślenia", systemImage: "brain")
                }
                .toggleStyle(.button)
                .disabled(model.isBusy)
            }
        }
        .sensoryFeedback(.success, trigger: model.conversation.messages.count)
        .onDisappear { model.setVoiceMode(false) }
    }

    /// New chat: what is actually active right now (model, offline/internet, photos, thinking) —
    /// derived from the current settings, never hard-coded.
    private var emptyState: some View {
        let variant = app.selectedVariant
        let experimental = app.fit(of: variant) != .recommended && !app.fit(of: variant).isComfortable
        return VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("O czym porozmawiamy?").font(.title3.bold())
            Text("Model działa w całości na tym iPhonie. Rozmowa nie opuszcza telefonu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            FlowChips {
                InfoChip(text: Text(verbatim: variant.displayName), icon: "cpu", tint: Theme.accent)
                if settings.responseStyle != .balanced {
                    InfoChip(text: Text(settings.responseStyle.title), icon: settings.responseStyle.icon, tint: Theme.textSecondary)
                }
                if experimental {
                    InfoChip(text: Text("eksperymentalny"), icon: "flask", tint: .yellow)
                }
                if settings.webSearchEnabled {
                    InfoChip(text: Text("Internet na żądanie"), icon: "globe", tint: Theme.internet)
                } else {
                    InfoChip(text: Text("W pełni offline"), icon: "lock.fill", tint: Theme.accent)
                }
                if app.isVisionReady {
                    InfoChip(text: Text("Zdjęcia"), icon: "photo", tint: Theme.textSecondary)
                }
                if settings.thinkingEnabled {
                    InfoChip(text: Text("Tryb myślenia"), icon: "brain", tint: Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .accessibilityElement(children: .combine)
    }

    private func scrollToBottom() {
        Task { @MainActor in
            // After this layout pass, so the new content's real height is known.
            await Task.yield()
            withAnimation(.easeOut(duration: 0.25)) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }

    @ViewBuilder private var streamingMessage: some View {
        if !model.streamingAnswer.isEmpty || !model.streamingThinking.isEmpty {
            AssistantMessageView(
                text: model.streamingAnswer,
                thinking: model.streamingThinking,
                isStreaming: true,
                isThinkingNow: model.phase == .thinking
            )
        }
        switch model.phase {
        case .awaitingWebConsent(let query):
            WebConsentCard(query: query, engine: app.searchEngineName) { model.answerWebConsent($0, forConversation: $1) }
        case .searching(let query, let step):
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    if case .reading(let pages)? = step {
                        Text("Czytam strony z wyników (\(pages))…")
                    } else {
                        Text("Szukam w internecie…")
                    }
                    Text("»\(query)«").font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .foregroundStyle(.orange)
        case .answering, .thinking:
            EmptyView()
        default:
            if model.streamingAnswer.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                }
                if case .prefill(let p?) = model.phase {
                    ProgressView(value: p).frame(maxWidth: 220)
                }
                if case .loading(let p) = app.engineState, model.phase == .loadingModel {
                    ProgressView(value: p).frame(maxWidth: 220)
                }
            }
        }
    }

    private var statusText: LocalizedStringKey {
        switch model.phase {
        case .loadingModel: "Ładowanie modelu do pamięci…"
        case .prefill(let p) where p != nil: "Przetwarzanie rozmowy…"
        case .prefill: "Czytam…"
        case .thinking: "Myśli…"
        default: "Pisze…"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            HStack {
                Button("Spróbuj ponownie", action: model.retry)
                    .buttonStyle(.borderedProminent)
                Button("Zamknij", action: model.dismissError)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private var thermalBanner: some View {
        if app.thermalState == .serious || app.thermalState == .critical {
            Label("Telefon jest gorący — generowanie zwalnia.", systemImage: "thermometer.high")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.orange.opacity(0.2))
        }
    }
}

private struct InfoChip: View {
    let text: Text
    let icon: String
    let tint: Color

    var body: some View {
        Label { text } icon: { Image(systemName: icon) }
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13), in: .capsule)
    }
}

/// Wraps chips onto several centered lines.
private struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
