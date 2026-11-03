import SwiftUI

/// Mic button in the composer: dictate into the text field.
struct MicButton: View {
    @Bindable var model: ChatViewModel
    @Environment(AppModel.self) private var app

    var body: some View {
        let listening = model.isDictating
        Button(action: model.toggleDictation) {
            Image(systemName: listening ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(listening ? Color.white : Color.accentColor)
                .frame(width: 36, height: 36)
                .background {
                    if listening {
                        Circle()
                            .fill(.red)
                            .scaleEffect(1 + CGFloat(app.dictation.level) * 0.35)
                            .animation(.easeOut(duration: 0.1), value: app.dictation.level)
                    }
                }
        }
        .disabled(model.isBusy)
        .accessibilityLabel(listening ? "Zakończ dyktowanie" : "Dyktuj")
    }
}

/// Voice mode status above the composer: listening / paused while answering / reading.
struct VoiceModeBar: View {
    @Bindable var model: ChatViewModel
    @Environment(AppModel.self) private var app

    var body: some View {
        if model.voiceMode {
            HStack(spacing: 10) {
                status
                Spacer()
                Button("Zakończ") { model.setVoiceMode(false) }
                    .font(.footnote.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        } else if let notice = model.voiceNotice {
            Label(notice, systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var status: some View {
        if model.isDictating {
            HStack(spacing: 8) {
                LevelBars(level: app.dictation.level)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Słucham…").font(.subheadline.bold())
                    Text(app.settings.autoSendDelay > 0
                         ? "Pauza wyśle wiadomość · „wyczyść” · „koniec dyktowania”"
                         : "Powiedz „wyślij” · „wyczyść” · „koniec dyktowania”")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if app.speech.speakingID != nil {
            Label("Czytam odpowiedź — potem znów słucham", systemImage: "speaker.wave.2.fill")
                .font(.subheadline)
        } else if model.isBusy {
            Label("Mikrofon wyłączony — model odpowiada", systemImage: "mic.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label("Włączam mikrofon…", systemImage: "mic")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5) { i in
                let weight: [Float] = [0.5, 0.8, 1, 0.8, 0.5]
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: 6 + CGFloat(min(1, level * weight[i] * 1.6)) * 16)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
