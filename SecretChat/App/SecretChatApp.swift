import GemmaKit
import SwiftData
import SwiftUI

@main
struct SecretChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                #if DEBUG
                .task { await DiagnosticsModel.autorunIfRequested(app: app) }
                .task { Self.seedForUITests() }
                #endif
        }
        .modelContainer(Self.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.enterBackground() }
        }
    }
}

extension SecretChatApp {
    static let container: ModelContainer = {
        let schema = Schema(AppSchema.models)
        // SwiftData logs noisy errors if the store's parent folder does not exist yet (first launch).
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
        #else
        let inMemory = false
        #endif
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }()
}

#if DEBUG
extension SecretChatApp {
    /// `-UITestSeedMath`: a conversation with a real Gemma answer full of LaTeX, for rendering tests.
    @MainActor static func seedForUITests() {
        if ProcessInfo.processInfo.arguments.contains("-UITestSeedLongChat") { seedLongChat() }
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedMath") else { return }
        let conversation = Conversation(title: "Wzory")
        container.mainContext.insert(conversation)
        conversation.append(role: .user, text: "Podaj wzór na pole koła, wzór na pierwiastki równania kwadratowego i twierdzenie Pitagorasa.")
        conversation.append(role: .assistant, text: """
        Oto żądane wzory:

        1. **Pole koła:**
           $P = \\pi r^2$
           *(gdzie $r$ to promień)*

        2. **Pierwiastki równania kwadratowego ($ax^2 + bx + c = 0$):**
           $x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}$
           *(gdzie $\\Delta = b^2 - 4ac$)*

        3. **Twierdzenie Pitagorasa:**
           $a^2 + b^2 = c^2$

        Wzór Eulera w bloku:
        $$
        e^{i\\pi} + 1 = 0
        $$
        A to nie wzór: bilet kosztuje 5$ a karnet 10$.
        """)
        try? container.mainContext.save()
    }

    /// `-UITestSeedLongChat`: a long conversation of tall, uneven answers (lists, code, formulas) —
    /// the case where the chat used to scroll into empty space below the messages.
    @MainActor static func seedLongChat() {
        let conversation = Conversation(title: "Długa rozmowa")
        container.mainContext.insert(conversation)
        for i in 1...8 {
            conversation.append(role: .user, text: "Pytanie \(i): opisz temat numer \(i) szczegółowo.")
            let items = (1...(4 + i % 4)).map { "\($0). **Punkt \($0)** — " + String(repeating: "Dłuższe wyjaśnienie tego punktu w kilku zdaniach. ", count: 1 + ($0 + i) % 4) }
            conversation.append(role: .assistant, text: """
            ## Temat \(i)

            \(items.joined(separator: "\n"))

            ```swift
            let wynik = (1...\(i)).reduce(0, +)
            print(wynik)
            ```

            $$
            x = \\frac{-b \\pm \\sqrt{\\Delta}}{2a}
            $$

            Podsumowanie tematu \(i).
            """)
        }
        try? container.mainContext.save()
    }
}
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Background model download finished while the app was suspended or terminated.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelStore.backgroundSessionID else { return completionHandler() }
        nonisolated(unsafe) let handler = completionHandler
        AppModel.sharedStore.setBackgroundCompletionHandler { handler() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.modelsReady {
            ConversationListView()
        } else {
            ModelSetupView()
        }
    }
}
