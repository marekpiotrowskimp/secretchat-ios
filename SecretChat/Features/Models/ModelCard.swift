import GemmaKit
import SwiftUI

/// One model in the picker: size, quality, speed, fit for this phone and a warning when it is too large.
struct ModelCard: View {
    let variant: ModelVariant
    let fit: ModelFit
    let isSelected: Bool
    var status: Status = .none

    enum Status: Equatable { case none, downloaded, active }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                Text(verbatim: variant.displayName)
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if fit == .recommended {
                Label("Najlepszy dla Twojego telefonu", systemImage: "star.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jakość").font(.caption2).foregroundStyle(.secondary)
                    QualityDots(level: variant.qualityLevel)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Szybkość").font(.caption2).foregroundStyle(.secondary)
                    Text("~\(variant.typicalTokensPerSecond.lowerBound)–\(variant.typicalTokensPerSecond.upperBound) tok/s")
                        .font(.caption.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pobranie").font(.caption2).foregroundStyle(.secondary)
                    Text(variant.model.expectedBytes.formatted(.byteCount(style: .file)))
                        .font(.caption.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wymaga").font(.caption2).foregroundStyle(.secondary)
                    Text("\(variant.requiredRAMGB) GB RAM").font(.caption.monospacedDigit())
                }
            }

            if case .experimental(_, let deviceGB) = fit {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Eksperymentalny na tym telefonie", systemImage: "flask")
                        .font(.subheadline.bold())
                    Text("Na czas pisania odpowiedzi model zajmuje ok. \(variant.peakMemoryGB.formatted(.number.precision(.fractionLength(1)))) GB pamięci z \(deviceGB) GB — telefon może wtedy zwalniać, a inne aplikacje mogą być zamykane.")
                        .font(.caption)
                    Text("Komfortowo działa na: \(variant.suggestedPhones)")
                        .font(.caption.bold())
                }
                .foregroundStyle(.yellow.mix(with: .orange, by: 0.6))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
            } else if case .tooLarge(let required, let deviceGB) = fit {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Twój telefon może nie podołać temu modelowi", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                    Text("Model potrzebuje \(required) GB RAM, a ten telefon ma \(deviceGB) GB. Aplikacja może się zamykać albo działać bardzo wolno.")
                        .font(.caption)
                    Text("Zalecany telefon: \(variant.suggestedPhones)")
                        .font(.caption.bold())
                }
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            } else {
                Text("Dla telefonów: \(variant.suggestedPhones)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .none: EmptyView()
        case .downloaded:
            Label("Pobrany", systemImage: "arrow.down.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
        case .active:
            Label("Używany", systemImage: "bolt.fill")
                .font(.caption.bold()).foregroundStyle(.green)
        }
    }
}

private struct QualityDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel(Text("Jakość \(level) z 3"))
    }
}

/// "Your phone: iPhone 14 · 6 GB RAM" and a warning when even the smallest model is too big.
struct DeviceSummary: View {
    let device: DeviceProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                if let name = device.name {
                    Text("Twój telefon: \(name) · \(device.ramGB) GB RAM")
                } else {
                    Text("Twój telefon: \(device.ramGB) GB RAM")
                }
            } icon: {
                Image(systemName: "iphone")
            }
            .font(.subheadline)

            if ModelCatalog.isBelowMinimum(device) {
                Label {
                    Text("Ten telefon ma mniej pamięci, niż potrzebuje nawet najmniejszy model. Czat może działać niestabilnie. Zalecany jest iPhone z co najmniej 6 GB RAM (np. iPhone 13 Pro, iPhone 14, iPhone 15).")
                } icon: {
                    Image(systemName: "exclamationmark.octagon.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
