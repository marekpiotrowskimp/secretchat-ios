import GemmaKit
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: DiagnosticsModel?
    private let metricsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("Diagnostyka")
        .onAppear { if model == nil { model = DiagnosticsModel(app: app) } }
        .onReceive(metricsTimer) { _ in model?.refreshMetrics() }
    }

    private func content(_ model: DiagnosticsModel) -> some View {
        List {
            Section("Pamięć i termika") {
                LabeledContent("Footprint", value: model.footprint.formattedGB)
                if let available = model.available {
                    LabeledContent("Dostępne do limitu", value: available.formattedGB)
                }
                LabeledContent("Stan termiczny", value: model.thermal)
                LabeledContent("Kontekst", value: "\(app.settings.contextLength / 1024)K")
            }

            if let running = model.running {
                Section {
                    HStack {
                        ProgressView()
                        Text(running)
                        Spacer()
                        Button("Przerwij", role: .destructive, action: model.cancel)
                    }
                }
            }

            Section("Testy") {
                Button("Przeładuj model", action: model.load)
                Button("Załaduj moduł obrazów", action: model.loadVision)
                Button("Benchmark (~500 + 256 tok)", action: model.runBenchmark)
                Button("Wypełnij kontekst (80%)", action: model.runContextFill)
                Button("Test obrazu", action: model.runVisionTest)
                Button("Test ciągły 10 min") { model.runSustained() }
            }
            .disabled(model.isRunning)

            Section("Log") {
                ForEach(Array(model.log.enumerated().reversed()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }
}
