import Foundation

struct ModelClient {
    struct Message {
        enum Content {
            case text(String)
            case multimodal(prompt: String, imageJPEG: Data)
            case toolCalls([ToolCall], text: String?)
            case toolResult(id: String, output: String)
        }

        var role: String
        var content: Content
    }

    struct ToolCall {
        var id: String
        var name: String
        var arguments: [String: Any]
    }

    struct Reply {
        var text: String?
        var toolCalls: [ToolCall]
    }

    enum ClientError: LocalizedError {
        case http(Int, String)
        case decode

        var errorDescription: String? {
            switch self {
            case .http(let code, let body):
                return "Model error \(code): \(body.prefix(180))"
            case .decode:
                return "Could not read the model reply."
            }
        }
    }

    func complete(apiKey: String, model: String, messages: [Message], tools: [[String: Any]]) async throws -> Reply {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages.map(encode),
            "tools": tools,
            "tool_choice": "auto",
            "temperature": 0.2,
            "max_tokens": 700
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClientError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            throw ClientError.decode
        }

        let text = message["content"] as? String
        var calls: [ToolCall] = []
        if let raw = message["tool_calls"] as? [[String: Any]] {
            for item in raw {
                let id = item["id"] as? String ?? UUID().uuidString
                let fn = item["function"] as? [String: Any]
                let name = fn?["name"] as? String ?? ""
                let argString = fn?["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argString.utf8))) as? [String: Any] ?? [:]
                calls.append(ToolCall(id: id, name: name, arguments: args))
            }
        }
        return Reply(text: text, toolCalls: calls)
    }

    private func encode(_ message: Message) -> [String: Any] {
        switch message.content {
        case .text(let text):
            return ["role": message.role, "content": text]
        case .multimodal(let prompt, let imageJPEG):
            let b64 = imageJPEG.base64EncodedString()
            return [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "low"]
                    ]
                ]
            ]
        case .toolCalls(let calls, let text):
            var body: [String: Any] = ["role": "assistant"]
            if let text { body["content"] = text }
            body["tool_calls"] = calls.map { call in
                let args = (try? JSONSerialization.data(withJSONObject: call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": args]
                ] as [String: Any]
            }
            return body
        case .toolResult(let id, let output):
            return ["role": "tool", "tool_call_id": id, "content": output]
        }
    }
}
