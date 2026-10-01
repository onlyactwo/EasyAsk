import Foundation

struct DeepSeekMessage {
    let role: String
    let text: String
    let images: [Data]
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case badResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "请先在设置中填写 DeepSeek API Key。"
        case .badResponse: "DeepSeek 返回了无法识别的响应。"
        case .server(let code, let detail): "DeepSeek 请求失败（HTTP \(code)）：\(detail)"
        }
    }
}

enum DeepSeekDelta: Equatable {
    case reasoning(String)
    case answer(String)
}

enum DeepSeekStreamParser {
    static func parse(_ line: String) -> [DeepSeekDelta] {
        guard line.hasPrefix("data:") else { return [] }
        let dataString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard dataString != "[DONE]", let data = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let delta = choice["delta"] as? [String: Any] else { return [] }
        var result: [DeepSeekDelta] = []
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            result.append(.reasoning(reasoning))
        }
        if let answer = delta["content"] as? String, !answer.isEmpty {
            result.append(.answer(answer))
        }
        return result
    }
}

struct DeepSeekClient {
    private let endpoint: URL

    init(endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!) {
        self.endpoint = endpoint
    }

    func complete(messages: [DeepSeekMessage], apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingKey
        }
        let payload: [String: Any] = [
            "model": "deepseek-flash",
            "messages": messages.map(Self.encode),
            "stream": false,
            "thinking": ["type": "disabled"]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.server(http.statusCode, Self.errorMessage(String(data: data, encoding: .utf8) ?? ""))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stream(
        messages: [DeepSeekMessage],
        apiKey: String,
        thinkingEnabled: Bool,
        reasoningEffort: String,
        onDelta: @escaping @MainActor (DeepSeekDelta) -> Void
    ) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.missingKey
        }

        var payload: [String: Any] = [
            "model": "deepseek-flash",
            "messages": messages.map(Self.encode),
            "stream": true,
            "thinking": ["type": thinkingEnabled ? "enabled" : "disabled"]
        ]
        if thinkingEnabled { payload["reasoning_effort"] = reasoningEffort }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 2000 { break }
            }
            throw DeepSeekError.server(http.statusCode, Self.errorMessage(body))
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            for delta in DeepSeekStreamParser.parse(line) {
                await onDelta(delta)
            }
        }
    }

    private static func encode(_ message: DeepSeekMessage) -> [String: Any] {
        if message.images.isEmpty {
            return ["role": message.role, "content": message.text]
        }
        var parts: [[String: Any]] = []
        if !message.text.isEmpty { parts.append(["type": "text", "text": message.text]) }
        for image in message.images {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/png;base64,\(image.base64EncodedString())"]
            ])
        }
        return ["role": message.role, "content": parts]
    }

    private static func errorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return body.isEmpty ? "未知错误" : body
        }
        return message
    }
}
