import Foundation

/// Long-term memory the model manages through tools. Each memory has a name, a one-sentence
/// description (what it is about and when it helps) and the content. Only names + descriptions go
/// into the prompt; the model loads content on demand with `memory_read`.
public struct MemoryEntry: Sendable, Hashable, Codable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public extension ToolDeclaration {
    static let memorySave = ToolDeclaration(
        name: "memory_save",
        description: "Zapisuje informację w pamięci długotrwałej użytkownika — zostaje między rozmowami.",
        parameters: [
            .init(name: "name", description: "Krótka nazwa wspomnienia (1–4 słowa). Jeśli użytkownik jej nie podał, wymyśl ją."),
            .init(name: "description", description: "Jedno zdanie: czego dotyczy wspomnienie i kiedy się przyda."),
            .init(name: "content", description: "Pełna treść do zapamiętania."),
        ],
        required: ["name", "description", "content"]
    )

    static let memoryRead = ToolDeclaration(
        name: "memory_read",
        description: "Wczytuje treść wspomnienia z pamięci długotrwałej.",
        parameters: [.init(name: "name", description: "Nazwa wspomnienia z listy.")],
        required: ["name"]
    )

    static let memoryDelete = ToolDeclaration(
        name: "memory_delete",
        description: "Usuwa wspomnienie, gdy użytkownik prosi, żeby o czymś zapomnieć.",
        parameters: [.init(name: "name", description: "Nazwa wspomnienia z listy.")],
        required: ["name"]
    )

    static let memoryTools: [ToolDeclaration] = [.memorySave, .memoryRead, .memoryDelete]
}

public enum MemoryInstructions {
    /// At most this many memories are listed (most recently used first) to keep the prompt small.
    public static let maxListed = 40

    /// System-prompt part with the memory index. Wording measured on 12B / E4B / E2B: all three save
    /// (naming it themselves when no name is given), read when the question matches a description,
    /// don't read for unrelated questions, and delete on "zapomnij".
    public static func text(index: [MemoryEntry]) -> String {
        let listed = index.prefix(maxListed)
        let list = listed.isEmpty
            ? "(pamięć jest pusta)"
            : listed.map { "- \(GemmaPromptBuilder.sanitize($0.name)): \(GemmaPromptBuilder.sanitize($0.description))" }.joined(separator: "\n")
        return """
        Masz pamięć długotrwałą: informacje, które użytkownik kazał Ci zapamiętać w poprzednich rozmowach. Zapisane wspomnienia (nazwa: opis):
        \(list)
        Gdy pytanie dotyczy czegoś z tej listy, najpierw wywołaj memory_read z nazwą wspomnienia i odpowiedz na podstawie jego treści — \
        nie pytaj o to użytkownika i nie zgaduj. \
        Gdy użytkownik prosi o zapamiętanie czegoś, wywołaj memory_save; jeśli nie podał nazwy, nadaj krótką nazwę sam. \
        Gdy prosi o zapomnienie, wywołaj memory_delete. \
        Samo napisanie „zapamiętam” albo „zapomniałem” niczego nie zmienia — pamięć zmienia tylko wywołanie narzędzia.
        """
    }
}

/// A message that starts with an explicit memory command ("Zapamiętaj…", "Zapomnij…", "Remember…",
/// "Forget…", optionally after "proszę"/"please"). Measured: the smallest model with a chatty style
/// answered such commands with "Jasne, zapamiętam!" without saving — these answers start with a call.
public enum MemoryCommand {
    static let verbs = ["zapamietaj", "zapamiętaj", "zapomnij", "remember", "forget"]
    static let politePrefixes = ["prosze", "proszę", "please", "hej", "hey"]

    public static func isExplicit(_ message: String) -> Bool {
        var words = message.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }[...]
        while let first = words.first, politePrefixes.contains(first) { words = words.dropFirst() }
        return words.first.map(verbs.contains) ?? false
    }
}

/// Finds memories by the name the model passes, tolerating case, Polish diacritics and punctuation
/// ("Adres domowy" = "adres-domowy" = "adres domowy."), and suggests near names when nothing matches.
public enum MemoryLookup {
    public static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The stored name matching `query`, if any.
    public static func match(_ query: String, in names: [String]) -> String? {
        let key = normalize(query)
        guard !key.isEmpty else { return nil }
        return names.first { normalize($0) == key }
    }

    /// Names that look related (shared words or containment), best first — offered when a read misses.
    public static func suggestions(for query: String, in names: [String], limit: Int = 3) -> [String] {
        let words = Set(normalize(query).split(separator: " ").map(String.init))
        let scored = names.map { name -> (String, Int) in
            let n = normalize(name)
            let shared = words.intersection(n.split(separator: " ").map(String.init)).count
            let contains = n.contains(normalize(query)) || normalize(query).contains(n) ? 2 : 0
            return (name, shared + contains)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
