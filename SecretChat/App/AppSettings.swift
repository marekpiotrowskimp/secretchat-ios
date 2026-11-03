import Foundation
import GemmaKit
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let contextOptions = [4096, 8192, 16384]
    static let maxTokenOptions = [512, 1024, 2048, 4096]
    static let defaultSystemPrompt = String(localized: "Jesteś pomocnym asystentem. Odpowiadaj w języku, w którym pisze użytkownik.")

    var systemPrompt: String { didSet { save(systemPrompt, Key.systemPrompt) } }
    var thinkingEnabled: Bool { didSet { save(thinkingEnabled, Key.thinking) } }
    var temperature: Double { didSet { save(temperature, Key.temperature) } }
    var topP: Double { didSet { save(topP, Key.topP) } }
    var topK: Int { didSet { save(topK, Key.topK) } }
    var maxTokens: Int { didSet { save(maxTokens, Key.maxTokens) } }
    var contextLength: Int { didSet { save(contextLength, Key.context) } }
    var showStats: Bool { didSet { save(showStats, Key.stats) } }
    var allowCellularDownload: Bool { didSet { save(allowCellularDownload, Key.cellular) } }
    /// Internet search — off by default; the app is meant to work offline.
    var webSearchEnabled: Bool { didSet { save(webSearchEnabled, Key.web) } }
    var searchProvider: SearchProvider { didSet { save(searchProvider.rawValue, Key.provider) } }
    /// Brave Search API key, stored in the Keychain.
    var braveAPIKey: String {
        didSet { KeychainStore.set(braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Key.braveKey) }
    }

    enum SearchProvider: String, CaseIterable, Identifiable {
        case duckDuckGo, brave
        var id: String { rawValue }
    }

    /// Read answers aloud while they are written (on-device speech synthesis).
    var speechAutoRead: Bool { didSet { save(speechAutoRead, Key.speechAuto) } }
    /// Multiplier of the normal speaking rate (0.5…2.0).
    var speechRate: Double { didSet { save(speechRate, Key.speechRate) } }
    /// Chosen voice identifier; nil = the best installed voice for the answer's language.
    var speechVoiceID: String? { didSet { defaults.set(speechVoiceID, forKey: Key.speechVoice) } }

    /// Dictation: language, auto-send after a pause in voice mode (0 = only on "wyślij"), reading answers in voice mode.
    var dictationLanguage: DictationLanguage { didSet { save(dictationLanguage.rawValue, Key.dictationLanguage) } }
    var autoSendDelay: Double { didSet { save(autoSendDelay, Key.autoSendDelay) } }
    var voiceModeReadsAloud: Bool { didSet { save(voiceModeReadsAloud, Key.voiceModeReads) } }

    enum DictationLanguage: String, CaseIterable, Identifiable {
        case automatic, polish, english
        var id: String { rawValue }
    }

    static let autoSendOptions: [Double] = [0, 1.5, 2.5, 4]

    /// How the model talks to the user (one instruction added to the system prompt).
    var responseStyle: ResponseStyle { didSet { save(responseStyle.rawValue, Key.style) } }
    /// The user's own description of the style, used when `responseStyle == .custom`.
    var customStyle: String { didSet { save(customStyle, Key.customStyle) } }

    /// The style's instruction (nil for balanced / an empty custom style). Goes at the very end of the
    /// system prompt, after the tool instructions — see `ResponseStyle`.
    var styleInstruction: String? { responseStyle.instruction(custom: customStyle) }

    /// Long-term memory across conversations (stored only on this device).
    var memoryEnabled: Bool { didSet { save(memoryEnabled, Key.memory) } }

    /// Chosen model variant; nil = the recommended one for this device.
    var selectedModelID: String? { didSet { defaults.set(selectedModelID, forKey: Key.model) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppSettings.defaultStore) {
        self.defaults = defaults
        systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? Self.defaultSystemPrompt
        thinkingEnabled = defaults.object(forKey: Key.thinking) as? Bool ?? false
        temperature = defaults.object(forKey: Key.temperature) as? Double ?? 1.0
        topP = defaults.object(forKey: Key.topP) as? Double ?? 0.95
        topK = defaults.object(forKey: Key.topK) as? Int ?? 64
        maxTokens = defaults.object(forKey: Key.maxTokens) as? Int ?? 2048
        contextLength = defaults.object(forKey: Key.context) as? Int ?? 4096
        showStats = defaults.object(forKey: Key.stats) as? Bool ?? true
        allowCellularDownload = defaults.object(forKey: Key.cellular) as? Bool ?? false
        selectedModelID = defaults.string(forKey: Key.model)
        memoryEnabled = defaults.object(forKey: Key.memory) as? Bool ?? true
        responseStyle = defaults.string(forKey: Key.style).flatMap(ResponseStyle.init) ?? .balanced
        customStyle = defaults.string(forKey: Key.customStyle) ?? ""
        speechAutoRead = defaults.object(forKey: Key.speechAuto) as? Bool ?? false
        speechRate = defaults.object(forKey: Key.speechRate) as? Double ?? 1.0
        speechVoiceID = defaults.string(forKey: Key.speechVoice)
        dictationLanguage = defaults.string(forKey: Key.dictationLanguage).flatMap(DictationLanguage.init) ?? .automatic
        autoSendDelay = defaults.object(forKey: Key.autoSendDelay) as? Double ?? 2.5
        voiceModeReadsAloud = defaults.object(forKey: Key.voiceModeReads) as? Bool ?? true
        webSearchEnabled = defaults.object(forKey: Key.web) as? Bool ?? false
        searchProvider = defaults.string(forKey: Key.provider).flatMap(SearchProvider.init) ?? .duckDuckGo
        braveAPIKey = KeychainStore.string(for: Key.braveKey) ?? ""
    }

    /// UI tests start from clean preferences (-UITestInMemoryStore).
    static var defaultStore: UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") {
            let suite = UserDefaults(suiteName: "UITest")!
            suite.removePersistentDomain(forName: "UITest")
            return suite
        }
        #endif
        return .standard
    }

    var sampling: SamplingParameters {
        SamplingParameters(temperature: Float(temperature), topK: Int32(topK), topP: Float(topP), maxTokens: maxTokens)
    }

    func resetGeneration() {
        temperature = 1.0
        topP = 0.95
        topK = 64
        maxTokens = 2048
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private enum Key {
        static let systemPrompt = "systemPrompt"
        static let thinking = "thinkingEnabled"
        static let temperature = "temperature"
        static let topP = "topP"
        static let topK = "topK"
        static let maxTokens = "maxTokens"
        static let context = "contextLength"
        static let stats = "showStats"
        static let cellular = "allowCellularDownload"
        static let model = "selectedModelID"
        static let memory = "memoryEnabled"
        static let style = "responseStyle"
        static let customStyle = "customStyle"
        static let speechAuto = "speechAutoRead"
        static let speechRate = "speechRate"
        static let speechVoice = "speechVoiceID"
        static let dictationLanguage = "dictationLanguage"
        static let autoSendDelay = "autoSendDelay"
        static let voiceModeReads = "voiceModeReadsAloud"
        static let web = "webSearchEnabled"
        static let provider = "searchProvider"
        static let braveKey = "braveAPIKey"
    }
}
