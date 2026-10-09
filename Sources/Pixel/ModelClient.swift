import Foundation

public struct ModelClient: Sendable {
    public struct Message: Sendable {
        public enum Content: Sendable {
            case text(String)
            case multimodal(prompt: String, imageJPEG: Data)
            case toolCalls([ToolCall], text: String?)
            case toolResult(id: String, output: String)
        }

        public var role: String
        public var content: Content

        public init(role: String, content: Content) {
            self.role = role
            self.content = content
        }
    }

    public struct ToolCall: Sendable {
        public var id: String
        public var name: String
        public var arguments: [String: AnySendable]

        public init(id: String, name: String, arguments: [String: AnySendable] = [:]) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }

    public struct Reply: Sendable {
        public var text: String?
        public var toolCalls: [ToolCall]

        public init(text: String?, toolCalls: [ToolCall] = []) {
            self.text = text
            self.toolCalls = toolCalls
        }
    }

    public enum ClientError: LocalizedError {
        case invalidURL(String)
        case http(Int, String)
        case decode(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let u):
                return "Invalid API Endpoint URL: '\(u)'"
            case .http(let code, let body):
                return "API error (\(code)): \(body.prefix(180))"
            case .decode(let reason):
                return "Could not decode model reply: \(reason)"
            }
        }
    }

    public init() {}

    public func complete(
        endpoint: String,
        apiKey: String,
        model: String,
        messages: [Message]
    ) async throws -> Reply {
        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var fullURLString = cleanEndpoint
        if !fullURLString.hasSuffix("/chat/completions") {
            if fullURLString.hasSuffix("/") {
                fullURLString += "chat/completions"
            } else {
                fullURLString += "/chat/completions"
            }
        }

        guard let url = URL(string: fullURLString) else {
            throw ClientError.invalidURL(fullURLString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenRouter compatibility headers
        if fullURLString.contains("openrouter.ai") {
            request.addValue("https://github.com/AnwarKalonov/Pixel", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("Pixel macOS Notch Assistant", forHTTPHeaderField: "X-Title")
        }

        let bodyPayload: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages.map(encode),
            "temperature": 0.3,
            "max_tokens": 800
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown server response"
            throw ClientError.http(statusCode, errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let messageObj = firstChoice["message"] as? [String: Any] else {
            throw ClientError.decode(String(data: data, encoding: .utf8) ?? "")
        }

        let replyText = messageObj["content"] as? String
        return Reply(text: replyText)
    }

    public func testConnection(
        endpoint: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        let testMsg = Message(role: "user", content: .text("Reply with 'Connected successfully' in 3 words."))
        let reply = try await complete(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            messages: [testMsg]
        )
        return reply.text ?? "Connection verified!"
    }

    private func encode(_ message: Message) -> [String: Any] {
        switch message.content {
        case .text(let text):
            return ["role": message.role, "content": text]
        case .multimodal(let prompt, let imageJPEG):
            let b64 = imageJPEG.base64EncodedString()
            return [
                "role": message.role,
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "low"]
                    ]
                ]
            ]
        case .toolCalls(_, let text):
            return ["role": message.role, "content": text ?? ""]
        case .toolResult(_, let output):
            return ["role": message.role, "content": output]
        }
    }
}

public struct AnySendable: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}
