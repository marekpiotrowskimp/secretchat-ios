import GemmaKit
import SwiftUI
import UIKit

struct UserMessageView: View {
    let text: String
    let images: [Data]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: images.count == 1 ? 200 : 110, height: images.count == 1 ? 200 : 110)
                                .clipShape(.rect(cornerRadius: 14))
                        }
                    }
                }
            }
            if !text.isEmpty {
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.userBubble, in: .rect(cornerRadius: 18))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .contextMenu {
            if !text.isEmpty {
                Button("Kopiuj", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            }
        }
    }
}

struct AssistantMessageView: View {
    let text: String
    let thinking: String
    var stats: GenerationStats?
    var webQuery: String? = nil
    var sources: [WebSource] = []
    /// Stored message id — enables "read aloud" (nil while streaming).
    var messageID: UUID? = nil
    var memoryEvents: [MemoryEvent] = []
    var isStreaming = false
    var isThinkingNow = false
    @Environment(AppSettings.self) private var settings
    @State private var showThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !thinking.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { showThinking || isThinkingNow }, set: { showThinking = $0 })) {
                    Text(thinking)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label(isThinkingNow ? "Myśli…" : "Rozumowanie", systemImage: "brain")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: isThinkingNow)
                }
                .padding(10)
                .background(Theme.surface, in: .rect(cornerRadius: 12))
            }

            if !text.isEmpty {
                MarkdownText(text: text)
                    .textSelection(.enabled)
            }

            if !memoryEvents.isEmpty {
                MemoryEventsView(events: memoryEvents)
            }

            if let webQuery {
                WebSourcesView(query: webQuery, sources: sources)
            }

            if (stats != nil && settings.showStats) || messageID != nil, !isStreaming {
                HStack(spacing: 12) {
                    if let messageID, !text.isEmpty { SpeakButton(id: messageID, markdown: text) }
                    if let stats, settings.showStats { StatsLine(stats: stats) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if !text.isEmpty {
                Button("Kopiuj", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                if let messageID {
                    SpeakButton(id: messageID, markdown: text)
                }
            }
        }
    }
}

/// 🔊 Read this answer aloud / stop reading.
struct SpeakButton: View {
    let id: UUID
    let markdown: String
    @Environment(AppModel.self) private var app

    var body: some View {
        let speaking = app.speech.isSpeaking(id)
        Button {
            app.speech.toggle(id, markdown: markdown)
        } label: {
            Label(speaking ? "Zatrzymaj czytanie" : "Czytaj na głos",
                  systemImage: speaking ? "stop.circle" : "speaker.wave.2")
                .font(.caption)
                .labelStyle(.iconOnly)
                .symbolEffect(.variableColor.iterative, isActive: speaking)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(speaking ? "Zatrzymaj czytanie" : "Czytaj na głos")
    }
}

struct StatsLine: View {
    let stats: GenerationStats

    var body: some View {
        HStack(spacing: 10) {
            Label("\(stats.decodeTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) tok/s", systemImage: "speedometer")
            Label("\(stats.generatedTokens) tok", systemImage: "text.word.spacing")
            if stats.promptTokens > 0 {
                Label("\(stats.prefillSeconds.formatted(.number.precision(.fractionLength(1)))) s", systemImage: "hourglass")
            }
            Label(stats.peakFootprintBytes.formatted(.byteCount(style: .memory)), systemImage: "memorychip")
            if stats.stopReason == .cancelled { Image(systemName: "stop.circle") }
            if stats.stopReason == .maxTokens || stats.stopReason == .contextFull { Image(systemName: "scissors") }
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
