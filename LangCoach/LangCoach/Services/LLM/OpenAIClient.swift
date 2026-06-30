import Foundation

struct OpenAIClient: LLMClient {
    let apiKey: String
    let model: String

    func send(system: String, messages: [ChatMessage], temperature: Double?) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMError.badResponse("invalid URL")
        }

        var apiMessages: [[String: String]] = []
        if !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages {
            apiMessages.append([
                "role": msg.role == .assistant ? "assistant" : "user",
                "content": msg.content,
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": temperature ?? 0.7,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPHelper.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "—")
        }
        return text
    }
}

enum HTTPHelper {
    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "—"
            throw LLMError.http(http.statusCode, String(body.prefix(500)))
        }
    }
}
