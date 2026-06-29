import Foundation

/// A chat message exchanged with the model.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant, system }
    var id = UUID()
    var role: Role
    var content: String
}

enum LLMProviderKind: String, CaseIterable, Identifiable, Codable {
    case gemini
    case claude
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }

    /// Keychain account name for this provider's key.
    var keychainAccount: String { "apikey.\(rawValue)" }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .claude: return "claude-sonnet-4-6"
        case .openai: return "gpt-4o"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .gemini: return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        case .claude: return ["claude-sonnet-4-6", "claude-opus-4-8", "claude-haiku-4-5-20251001"]
        case .openai: return ["gpt-4o", "gpt-4o-mini", "gpt-4.1"]
        }
    }

    var apiKeyURL: String {
        switch self {
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .claude: return "https://console.anthropic.com/settings/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        }
    }
}

enum LLMError: LocalizedError {
    case missingKey(LLMProviderKind)
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p):
            return "No API key set for \(p.displayName). Add one in Settings (⌘,)."
        case .badResponse(let msg):
            return "Unexpected response from the model: \(msg)"
        case .http(let code, let body):
            return "Request failed (HTTP \(code)): \(body)"
        }
    }
}

/// A provider-agnostic chat interface. Implementations adapt to each vendor's API.
protocol LLMClient {
    /// Sends a system prompt + conversation and returns the assistant's reply text.
    func send(system: String, messages: [ChatMessage]) async throws -> String
}
