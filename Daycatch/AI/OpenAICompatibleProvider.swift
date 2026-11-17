import Foundation

/// OpenAI Chat Completions 兼容接口（OpenAI / DeepSeek / 通义千问 / 自定义）。
///
/// 默认请求 `response_format: json_object`；若服务端不支持该参数（400），去掉后重试一次。
struct OpenAICompatibleProvider: AIProvider {
    var apiKey: String
    var model: String
    var baseURL: URL
    var http: any HTTPClient

    func complete(_ request: AICompletionRequest) async throws -> String {
        do {
            return try await send(request, jsonMode: true)
        } catch AIError.badRequest {
            return try await send(request, jsonMode: false)
        }
    }

    func makeURLRequest(_ request: AICompletionRequest, jsonMode: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.user],
            ],
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        return try .jsonPost(
            baseURL.appending(path: "chat/completions"),
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
    }

    private func send(_ request: AICompletionRequest, jsonMode: Bool) async throws -> String {
        let (data, response) = try await http.send(makeURLRequest(request, jsonMode: jsonMode))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(status: response.statusCode, body: data, model: model)
        }
        return try Self.text(from: data)
    }

    static func text(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse(Localization.strings.responseNotJSON)
        }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            if let message = AIError.errorMessage(in: data) { throw AIError.badRequest(message) }
            throw AIError.badResponse(Localization.strings.responseMissingChoices)
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIError.refused }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw ExtractionError.emptyResponse
        }
        return content
    }
}
