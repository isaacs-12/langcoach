import Foundation

struct ClaudeClient: LLMClient {
    let apiKey: String
    let model: String

    func send(system: String, messages: [ChatMessage]) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMError.badResponse("invalid URL")
        }

        let apiMessages: [[String: Any]] = messages.map { msg in
            [
                "role": msg.role == .assistant ? "assistant" : "user",
                "content": msg.content,
            ]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "messages": apiMessages,
        ]
        if !system.isEmpty { body["system"] = system }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPHelper.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "—")
        }
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        return text
    }
}
