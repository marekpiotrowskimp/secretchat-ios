import Foundation

/// How the model talks to the user — chosen once in Settings instead of repeating it in every message.
/// Each style adds one short instruction to the system prompt; `.balanced` adds nothing.
/// Put it at the end of the system prompt, after the tool instructions: placed before them, chatty
/// styles made the small models skip tools (and "playful" even started needless web searches).
public enum ResponseStyle: String, CaseIterable, Sendable, Codable, Identifiable {
    case balanced, concise, detailed, friendly, teacher, professional, playful, custom

    public var id: String { rawValue }

    /// A user-written style is cut to this many characters (it is part of every prompt).
    public static let customLimit = 600

    /// Without this, styles that favour answering directly ("friendly", "concise") made the models
    /// skip tool calls — e.g. reply "Sure, I'll remember!" without calling memory_save.
    static let toolsStillApply = "Styl dotyczy tylko tego, jak piszesz odpowiedź. Narzędzia wywołuj tak samo jak bez stylu: najpierw wywołanie, potem odpowiedź w tym stylu — także wtedy, gdy styl każe zaczynać odpowiedź od określonych słów. Prośba „zapamiętaj” zawsze oznacza wywołanie memory_save, a „zapomnij” — memory_delete."

    /// System-prompt part for this style, or nil when it adds nothing (balanced, or an empty custom text).
    public func instruction(custom: String = "") -> String? {
        styleText(custom: custom).map { $0 + "\n" + Self.toolsStillApply }
    }

    private func styleText(custom: String) -> String? {
        switch self {
        case .balanced:
            return nil
        case .concise:
            return "Styl odpowiedzi: zwięźle i konkretnie. Odpowiadaj w 1–3 zdaniach albo krótką listą. Bez wstępów, powtarzania pytania i podsumowań. Rozwijaj temat tylko wtedy, gdy użytkownik o to poprosi."
        case .detailed:
            return "Styl odpowiedzi: wyczerpująco. Wyjaśniaj dokładnie i w uporządkowany sposób (nagłówki lub listy), podawaj przykłady, kontekst i zastrzeżenia oraz wyjaśniaj, dlaczego coś działa tak, a nie inaczej."
        case .friendly:
            return "Styl odpowiedzi: ciepło i przyjaźnie, jak dobry znajomy. Zwracaj się do użytkownika na „ty”, pisz swobodnie i życzliwie, okazuj zrozumienie. Możesz czasem użyć emoji."
        case .teacher:
            return "Styl odpowiedzi: jak cierpliwy nauczyciel. Tłumacz krok po kroku prostym językiem, używaj analogii i przykładów z życia, objaśniaj trudne pojęcia. Na końcu zadaj jedno krótkie pytanie, które sprawdzi zrozumienie."
        case .professional:
            return "Styl odpowiedzi: rzeczowo i profesjonalnie. Ton formalny i neutralny, precyzyjne sformułowania, bez emoji i potocznych zwrotów. Oddzielaj fakty od opinii."
        case .playful:
            return "Styl odpowiedzi: z humorem i luzem. Bądź dowcipny i pomysłowy, żartuj i używaj zabawnych porównań — ale informacje muszą pozostać poprawne."
        case .custom:
            let text = GemmaPromptBuilder.sanitize(String(custom.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.customLimit)))
            guard !text.isEmpty else { return nil }
            return "Użytkownik opisał, jak masz do niego mówić. Stosuj to w każdej odpowiedzi:\n\(text)"
        }
    }
}
