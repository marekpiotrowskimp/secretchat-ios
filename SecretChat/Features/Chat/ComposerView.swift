import GemmaKit
import PhotosUI
import SwiftUI
import UIKit

struct ComposerView: View {
    @Bindable var model: ChatViewModel
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoLoadFailed = false
    static let maxImages = 3

    var body: some View {
        VStack(spacing: 8) {
            VoiceModeBar(model: model)
            if !model.draftImages.isEmpty { attachments }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    if app.isVisionReady {
                        // A PhotosPicker placed directly inside a Menu never presents (the menu
                        // dismisses first) — open it from the view instead.
                        Button("Biblioteka zdjęć", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Zrób zdjęcie", systemImage: "camera") { showCamera = true }
                        }
                    } else if app.state(of: app.selectedVariant.vision).isActive {
                        Text("Pobieranie modułu obrazów…")
                    } else {
                        Button("Pobierz moduł obrazów (\(app.selectedVariant.vision.expectedBytes.formatted(.byteCount(style: .file))))",
                               systemImage: "arrow.down.circle", action: app.downloadVision)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(model.isBusy || model.draftImages.count >= Self.maxImages)
                .accessibilityLabel("Dodaj zdjęcie")

                TextField("Wiadomość", text: $model.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.elevated, in: .rect(cornerRadius: 20))

                MicButton(model: model)

                if model.isBusy {
                    Button(action: model.stop) {
                        Image(systemName: "stop.circle.fill").font(.system(size: 32))
                    }
                    .accessibilityLabel("Zatrzymaj")
                } else {
                    Button {
                        model.send()
                        focused = false
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .disabled(!model.canSend)
                    .accessibilityLabel("Wyślij")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.96))
        .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: max(1, Self.maxImages - model.draftImages.count),
            matching: .images
        )
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
        .alert("Nie udało się wczytać zdjęcia", isPresented: $photoLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Jeśli zdjęcie jest tylko w iCloud, sprawdź połączenie i spróbuj ponownie.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in add(data) }
                .ignoresSafeArea()
        }
    }

    private var attachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.draftImages.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.draftImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("Usuń zdjęcie")
                            }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var failed = false
        for item in items {
            // iCloud-only originals are downloaded here; a failure must not be silent.
            if let data = try? await item.loadTransferable(type: Data.self), add(data) { continue }
            failed = true
        }
        pickerItems = []
        photoLoadFailed = failed
    }

    @discardableResult
    private func add(_ data: Data) -> Bool {
        guard model.draftImages.count < Self.maxImages,
              let jpeg = ImageDecoder.jpegThumbnail(from: data) else { return false }
        model.draftImages.append(jpeg)
        return true
    }
}

/// Camera capture via UIImagePickerController.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
