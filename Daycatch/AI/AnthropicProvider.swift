import Foundation

/// Claude Messages API（POST /v1/messages）。
///
/// 对支持的模型使用结构化输出（`output_config.format`）保证返回合法 JSON，并开启服务端
/// fallback。遇到 400 时会去掉这些可选参数重试一次，以兼容用户自己填写的旧模型。
struct AnthropicProvider: AIProvider {
    var apiKey: String
    var model: String
    var baseURL: URL
    var http: any HTTPClient

    /// 支持 `output_config.effort` 的模型前缀
    private static let effortModels = ["claude-opus-5", "claude-fable-5", "claude-sonnet-5", "claude-haiku-5-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6"]
    /// 支持 `fallbacks: "default"` 的模型
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]

    func complete(_ request: AICompletionRequest) async throws -> String {
        do {
            return try await send(request, full: true)
        } catch AIError.badRequest {
            // 可能是旧模型不支持 effort / 结构化输出 / fallbacks，退回最基础的请求
            return try await send(request, full: false)
        }
    }

    func makeURLRequest(_ request: AICompletionRequest, full: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": request.system,
            "messages": [["role": "user", "content": request.user]],
        ]
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]
        if full {
            var outputConfig: [String: Any] = [:]
            if Self.effortModels.contains(where: model.hasPrefix) {
                // 提取任务简单，低 effort 响应更快
                outputConfig["effort"] = "low"
            }
            if let schemaData = request.responseSchema,
               let schema = try? JSONSerialization.jsonObject(with: schemaData) {
                outputConfig["format"] = ["type": "json_schema", "schema": schema]
            }
            if !outputConfig.isEmpty { body["output_config"] = outputConfig }
            if Self.fallbackModels.contains(model) {
                body["fallbacks"] = "default"
                headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            }
        }
        return try .jsonPost(baseURL.appending(path: "v1/messages"), body: body, headers: headers)
    }

    private func send(_ request: AICompletionRequest, full: Bool) async throws -> String {
        let (data, response) = try await http.send(makeURLRequest(request, full: full))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(status: response.statusCode, body: data, model: model)
        }
        return try Self.text(from: data)
    }

    /// 从 Messages API 响应中取出文本（忽略 thinking 等其他内容块）。
    static func text(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse("响应不是 JSON")
        }
        if let stop = object["stop_reason"] as? String, stop == "refusal" {
            throw AIError.refused
        }
        guard let content = object["content"] as? [[String: Any]] else {
            throw AIError.badResponse("缺少 content")
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw ExtractionError.emptyResponse }
        return text
    }
}
