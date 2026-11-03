import Foundation

/// A downloadable model file with its integrity data.
public struct ModelAsset: Sendable, Hashable, Identifiable {
    public let id: String
    /// Local file name (unique across all variants).
    public let fileName: String
    public let remoteURL: URL
    public let expectedBytes: Int64
    public let sha256: String

    public init(id: String, fileName: String, remoteURL: URL, expectedBytes: Int64, sha256: String) {
        self.id = id
        self.fileName = fileName
        self.remoteURL = remoteURL
        self.expectedBytes = expectedBytes
        self.sha256 = sha256
    }
}

/// One selectable Gemma 4 model: language model + optional vision projector, and what it needs.
public struct ModelVariant: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let model: ModelAsset
    public let vision: ModelAsset
    /// Below this RAM (GB, as marketed) the model does not fit at all.
    public let requiredRAMGB: Int
    /// From this RAM up the model runs comfortably: its peak GPU memory stays under ~45% of RAM.
    /// Between `requiredRAMGB` and this it works but is experimental (the phone may slow down).
    public let comfortableRAMGB: Int
    /// System memory the model wires while it writes an answer (measured on iPhone 17 Pro Max, 4K context).
    public let peakMemoryGB: Double
    /// Phones that run the model comfortably, for the "you need…" hint.
    public let suggestedPhones: String
    /// Relative answer quality, 1…3 (for the picker).
    public let qualityLevel: Int
    /// Generation speed on phones that meet the requirement (tokens/s). Upper bound measured on an
    /// iPhone 17 Pro Max (see PLAN.md); older phones in the tier are slower.
    public let typicalTokensPerSecond: ClosedRange<Int>

    public var downloadBytes: Int64 { model.expectedBytes + vision.expectedBytes }
    public var assets: [ModelAsset] { [model, vision] }
}

public enum ModelCatalog {
    private static func hf(_ repo: String, _ file: String) -> URL {
        URL(string: "https://huggingface.co/unsloth/\(repo)/resolve/main/\(file)")!
    }

    /// Gemma 4 12B instruction-tuned, quantization-aware-trained 4-bit (Unsloth dynamic quant).
    public static let gemma12B = ModelVariant(
        id: "gemma-4-12b",
        displayName: "Gemma 4 12B",
        model: ModelAsset(
            id: "gemma-4-12b-it-qat",
            fileName: "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf",
            remoteURL: hf("gemma-4-12B-it-qat-GGUF", "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"),
            expectedBytes: 6_716_356_800,
            sha256: "90fd44e29e0d7cffeb0fd00dc73cfdab9ed0b0e95306ecf7821ea634c940c370"
        ),
        vision: ModelAsset(
            id: "gemma-4-12b-mmproj",
            fileName: "mmproj-F16.gguf",
            remoteURL: hf("gemma-4-12B-it-qat-GGUF", "mmproj-F16.gguf"),
            expectedBytes: 175_115_840,
            sha256: "ecc4e93128da8363b7dbf2193eab98cf1142353f52ceaa0c95c0872997aaadd3"
        ),
        requiredRAMGB: 12,
        comfortableRAMGB: 16, // peak 7.8 GB: on 12 GB phones free RAM drops to ~0.1 GB while answering
        peakMemoryGB: 7.8,
        suggestedPhones: String(localized: "iPhone z 16 GB RAM", bundle: .module),
        qualityLevel: 3,
        typicalTokensPerSecond: 7...9
    )

    /// Gemma 4 E4B ("effective 4B", per-layer embeddings) — the mid-range on-device model.
    public static let gemmaE4B = ModelVariant(
        id: "gemma-4-e4b",
        displayName: "Gemma 4 E4B",
        model: ModelAsset(
            id: "gemma-4-e4b-it-qat",
            fileName: "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf",
            remoteURL: hf("gemma-4-E4B-it-qat-GGUF", "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"),
            expectedBytes: 4_215_695_776,
            sha256: "df0fd4ee07072c607c29a0a1cb4f98918426cca12f45a2776bdd6ee6d09a4de3"
        ),
        vision: ModelAsset(
            id: "gemma-4-e4b-mmproj",
            fileName: "mmproj-E4B-F16.gguf",
            remoteURL: hf("gemma-4-E4B-it-qat-GGUF", "mmproj-F16.gguf"),
            expectedBytes: 990_372_672,
            sha256: "6a255159ee4b01b304f633a57f017dd7d5a69d30fff52abb2614bf0813cef034"
        ),
        requiredRAMGB: 8,
        comfortableRAMGB: 12, // peak 4.9 GB
        peakMemoryGB: 4.9,
        suggestedPhones: "iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air",
        qualityLevel: 2,
        typicalTokensPerSecond: 14...21
    )

    /// Gemma 4 E2B — the smallest model, for 6 GB phones.
    public static let gemmaE2B = ModelVariant(
        id: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        model: ModelAsset(
            id: "gemma-4-e2b-it-qat",
            fileName: "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf",
            remoteURL: hf("gemma-4-E2B-it-qat-GGUF", "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf"),
            expectedBytes: 2_620_370_976,
            sha256: "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889"
        ),
        vision: ModelAsset(
            id: "gemma-4-e2b-mmproj",
            fileName: "mmproj-E2B-F16.gguf",
            remoteURL: hf("gemma-4-E2B-it-qat-GGUF", "mmproj-F16.gguf"),
            expectedBytes: 985_654_080,
            sha256: "13c8966d1635d02e6727f27402880614906fa291850c07feda18dbcddf2291b6"
        ),
        requiredRAMGB: 6,
        comfortableRAMGB: 8, // peak 3.2 GB
        peakMemoryGB: 3.2,
        suggestedPhones: "iPhone 15 Pro, iPhone 16, 16 Pro, 16e, iPhone 17",
        qualityLevel: 1,
        typicalTokensPerSecond: 30...40
    )

    /// Largest first.
    public static let variants = [gemma12B, gemmaE4B, gemmaE2B]
    public static var allAssets: [ModelAsset] { variants.flatMap(\.assets) }

    public static func variant(id: String?) -> ModelVariant? {
        variants.first { $0.id == id }
    }
}

// MARK: - Device fit

/// The device's memory class and name, used to recommend a model.
public struct DeviceProfile: Sendable, Hashable {
    /// Marketed RAM in GB (4, 6, 8, 12…), derived from the physical memory the OS reports.
    public let ramGB: Int
    /// Marketing name when known (e.g. "iPhone 17 Pro Max").
    public let name: String?

    public init(ramGB: Int, name: String?) {
        self.ramGB = ramGB
        self.name = name
    }

    public static var current: DeviceProfile {
        DeviceProfile(ramGB: marketedRAM(bytes: ProcessInfo.processInfo.physicalMemory), name: DeviceNames.name(for: machineIdentifier))
    }

    /// iOS reports less than the marketed size (the kernel and GPU carve-outs are excluded), never more —
    /// so round up to the next standard capacity.
    public static func marketedRAM(bytes: UInt64) -> Int {
        let gib = Double(bytes) / 1_073_741_824
        let tiers = [2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128]
        return tiers.first { gib <= Double($0) * 1.02 } ?? Int(gib.rounded())
    }

    static var machineIdentifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
    }
}

public enum ModelFit: Sendable, Equatable {
    /// The best model this device runs comfortably.
    case recommended
    /// Runs comfortably, but a better model fits too.
    case supported
    /// Fits, but while answering it takes so much memory that the phone may slow down.
    case experimental(comfortableGB: Int, deviceGB: Int)
    /// Needs more RAM than the device has.
    case tooLarge(requiredGB: Int, deviceGB: Int)

    public var isRunnable: Bool {
        if case .tooLarge = self { false } else { true }
    }

    public var isComfortable: Bool {
        switch self { case .recommended, .supported: true; default: false }
    }
}

public extension ModelCatalog {
    /// Best variant for the device: the largest it runs comfortably; failing that, the smallest one.
    static func recommended(for device: DeviceProfile) -> ModelVariant {
        variants.first { $0.comfortableRAMGB <= device.ramGB } ?? variants.last!
    }

    static func fit(of variant: ModelVariant, on device: DeviceProfile) -> ModelFit {
        if variant.requiredRAMGB > device.ramGB {
            return .tooLarge(requiredGB: variant.requiredRAMGB, deviceGB: device.ramGB)
        }
        if variant.comfortableRAMGB > device.ramGB {
            return .experimental(comfortableGB: variant.comfortableRAMGB, deviceGB: device.ramGB)
        }
        return variant == recommended(for: device) ? .recommended : .supported
    }

    /// True when even the smallest model needs more RAM than the device has.
    static func isBelowMinimum(_ device: DeviceProfile) -> Bool {
        device.ramGB < (variants.map(\.requiredRAMGB).min() ?? 0)
    }
}

/// Marketing names for iPhone model identifiers (only used for display).
enum DeviceNames {
    static func name(for identifier: String) -> String? { table[identifier] }

    private static let table: [String: String] = [
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
    ]
}
