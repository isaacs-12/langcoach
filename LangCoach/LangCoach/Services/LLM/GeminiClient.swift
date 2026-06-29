import Foundation

struct GeminiClient: LLMClient {
    let apiKey: String
    let model: String

    func send(system: String, messages: [ChatMessage]) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard var components = URLComponents(string: urlString) else {
            throw LLMError.badResponse("invalid URL")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw LLMError.badResponse("invalid URL") }

        let contents: [[String: Any]] = messages.map { msg in
            [
                "role": msg.role == .assistant ? "model" : "user",
                "parts": [["text": msg.content]],
            ]
        }

        var body: [String: Any] = ["contents": contents]
        if !system.isEmpty {
            body["system_instruction"] = ["parts": [["text": system]]]
        }
        body["generationConfig"] = ["temperature": 0.7]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPHelper.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "—")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text
    }
}
