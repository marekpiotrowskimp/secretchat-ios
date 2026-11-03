import GemmaKit
import SwiftUI

/// First launch: pick a model (the best one for this phone is preselected) and download it.
struct ModelSetupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    ModelPickerSection()
                }
                .padding()
            }
            .navigationTitle(Theme.appName)
            .secretBackground()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.5), radius: 16)
            Text("Prywatny czat AI. Bez internetu.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Model działa w całości na Twoim iPhonie — bez kont, bez chmury, bez śledzenia. Rozmowy nie opuszczają telefonu. Wybierz model i pobierz go jednorazowo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

/// Model cards + download controls. Used on first launch and in Settings → Model.
struct ModelPickerSection: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var chosen: ModelVariant?
    @State private var includeVision = true
    @State private var confirmTooLarge = false
    @State private var confirmDelete: ModelVariant?

    private var selection: ModelVariant { chosen ?? app.selectedVariant }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            DeviceSummary(device: app.device)

            ForEach(ModelCatalog.variants) { variant in
                ModelCard(
                    variant: variant,
                    fit: app.fit(of: variant),
                    isSelected: variant == selection,
                    status: status(of: variant)
                )
                .onTapGesture { chosen = variant }
                .contextMenu {
                    if app.storedBytes(of: variant) > 0 {
                        Button("Usuń pliki modelu", systemImage: "trash", role: .destructive) { confirmDelete = variant }
                    }
                }
            }

            progress(of: selection)

            if !app.isDownloaded(selection) {
                Toggle(isOn: $includeVision) {
                    VStack(alignment: .leading) {
                        Text("Moduł obrazów")
                        Text("Pozwala wysyłać zdjęcia. +\(selection.vision.expectedBytes.formatted(.byteCount(style: .file)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Pozwól pobierać przez sieć komórkową", isOn: $settings.allowCellularDownload)
                diskSpaceNote
            }

            actionButton

            // The model's license is shown where the user chooses to download it.
            Text("Modele Gemma 4 udostępnia Google na licencji Apache 2.0. Pliki są pobierane z Hugging Face.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(destination: URL(string: "https://ai.google.dev/gemma/docs/gemma_4_license")!) {
                Label("Licencja modelu", systemImage: "doc.text")
                    .font(.caption)
            }
        }
        .confirmationDialog(
            app.fit(of: selection).isRunnable ? "Ten model jest eksperymentalny na Twoim telefonie" : "Ten model może być za duży dla Twojego telefonu",
            isPresented: $confirmTooLarge,
            titleVisibility: .visible
        ) {
            Button("Pobierz mimo to", role: .destructive) { startDownload() }
            Button("Wybierz \(app.recommendedVariant.displayName)") {
                chosen = app.recommendedVariant
            }
        } message: {
            if app.fit(of: selection).isRunnable {
                Text("W trakcie odpowiedzi \(selection.displayName) zajmuje ok. \(selection.peakMemoryGB.formatted(.number.precision(.fractionLength(1)))) GB z \(app.device.ramGB) GB pamięci telefonu — może zwalniać telefon i zamykać inne aplikacje. Komfortowo: \(selection.suggestedPhones).")
            } else {
                Text("\(selection.displayName) potrzebuje \(selection.requiredRAMGB) GB RAM, a ten telefon ma \(app.device.ramGB) GB. Zalecany telefon: \(selection.suggestedPhones).")
            }
        }
        .confirmationDialog(
            "Usunąć \(confirmDelete?.displayName ?? "")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Usuń", role: .destructive) {
                if let variant = confirmDelete { Task { await app.delete(variant) } }
            }
        } message: {
            Text("Rozmowy zostaną zachowane.")
        }
    }

    private func status(of variant: ModelVariant) -> ModelCard.Status {
        guard app.isDownloaded(variant) else { return .none }
        return variant == app.selectedVariant && app.modelsReady ? .active : .downloaded
    }

    @ViewBuilder private func progress(of variant: ModelVariant) -> some View {
        let rows = variant.assets.filter { app.state(of: $0) != .missing }
        if !rows.isEmpty, !app.isDownloaded(variant) || rows.contains(where: { app.state(of: $0).isActive }) {
            VStack(spacing: 10) {
                ForEach(rows) { asset in
                    AssetRow(title: asset == variant.model ? "Model językowy" : "Moduł obrazów", asset: asset, state: app.state(of: asset))
                }
            }
            .padding()
            .background(Theme.surface, in: .rect(cornerRadius: 16))
        }
    }

    @ViewBuilder private var diskSpaceNote: some View {
        let needed = selection.model.expectedBytes + (includeVision ? selection.vision.expectedBytes : 0)
        if let free = ModelStore.availableDiskSpace() {
            let enough = free > needed + 500_000_000
            Label {
                Text("Do pobrania: \(needed.formatted(.byteCount(style: .file))) · wolne: \(free.formatted(.byteCount(style: .file)))")
            } icon: {
                Image(systemName: enough ? "internaldrive" : "exclamationmark.triangle.fill")
                    .foregroundStyle(enough ? Color.secondary : Color.orange)
            }
            .font(.footnote)
            .foregroundStyle(enough ? .secondary : .primary)
        }
    }

    @ViewBuilder private var actionButton: some View {
        let variant = selection
        let states = variant.assets.map { app.state(of: $0) }
        if states.contains(where: \.isActive) {
            Button("Wstrzymaj", systemImage: "pause.fill") { app.pauseDownloads(of: variant) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        } else if app.isDownloaded(variant) {
            if variant != app.selectedVariant || settings.selectedModelID == nil {
                Button {
                    app.select(variant)
                    chosen = nil
                } label: {
                    Label("Używaj \(variant.displayName)", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if !app.state(of: variant.vision).isReady {
                Button("Pobierz moduł obrazów (+\(variant.vision.expectedBytes.formatted(.byteCount(style: .file))))", systemImage: "photo") {
                    app.download(variant, includeVision: true)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Button {
                if app.fit(of: variant).isComfortable { startDownload() } else { confirmTooLarge = true }
            } label: {
                Label(
                    states.contains { if case .paused = $0 { true } else { false } } ? "Wznów pobieranie" : "Pobierz \(variant.displayName)",
                    systemImage: "arrow.down.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Zalecane Wi-Fi. Pobieranie trwa dalej, gdy aplikacja jest w tle.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func startDownload() {
        app.select(selection)
        chosen = nil
        app.download(app.selectedVariant, includeVision: includeVision)
    }
}

private struct AssetRow: View {
    let title: LocalizedStringKey
    let asset: ModelAsset
    let state: AssetState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(asset.expectedBytes.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch state {
            case .missing:
                EmptyView()
            case .paused(let received):
                ProgressView(value: Double(received), total: Double(asset.expectedBytes))
                Text("Wstrzymano").font(.caption).foregroundStyle(.secondary)
            case .downloading(let received, let total):
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                Text("\(received.formatted(.byteCount(style: .file))) z \(total.formatted(.byteCount(style: .file)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .verifying:
                ProgressView().progressViewStyle(.linear)
                Text("Sprawdzanie sumy kontrolnej…").font(.caption).foregroundStyle(.secondary)
            case .ready:
                Label("Gotowe", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
