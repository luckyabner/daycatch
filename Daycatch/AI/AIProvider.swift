import Foundation

/// 设置里可选的服务商。除 Claude 外都走 OpenAI 兼容接口。
enum ProviderKind: String, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai
    case deepseek
    case qwen
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Claude（Anthropic）"
        case .openai: "OpenAI"
        case .deepseek: "DeepSeek"
        case .qwen: "通义千问"
        case .custom: "自定义（OpenAI 兼容）"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openai: "https://api.openai.com/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openai: "gpt-5-mini"
        case .deepseek: "deepseek-chat"
        case .qwen: "qwen-plus"
        case .custom: ""
        }
    }

    var usesAnthropicAPI: Bool { self == .anthropic }
}

struct AIConfiguration: Sendable, Equatable {
    var provider: ProviderKind
    var apiKey: String
    var model: String
    var baseURL: String
}

struct AICompletionRequest: Sendable {
    var system: String
    var user: String
    /// 期望返回的 JSON Schema（序列化后的 JSON）。支持结构化输出的服务商会用它约束回复。
    var responseSchema: Data?
}

/// AI 服务抽象：输入提示词，返回模型的原始文本回复。
protocol AIProvider: Sendable {
    func complete(_ request: AICompletionRequest) async throws -> String
}

enum AIProviderFactory {
    static func make(_ config: AIConfiguration, http: any HTTPClient = URLSessionHTTPClient()) throws -> any AIProvider {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.missingAPIKey }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIError.missingModel }
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        else { throw AIError.invalidBaseURL }

        if config.provider.usesAnthropicAPI {
            return AnthropicProvider(apiKey: key, model: model, baseURL: url, http: http)
        }
        return OpenAICompatibleProvider(apiKey: key, model: model, baseURL: url, http: http)
    }
}

// MARK: - HTTP

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.badResponse("不是 HTTP 响应") }
            return (data, http)
        } catch let error as URLError {
            throw AIError(urlError: error)
        }
    }
}

// MARK: - 错误

enum AIError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case missingModel
    case invalidBaseURL
    case offline
    case timedOut
    case network(String)
    case unauthorized
    case forbidden(String)
    case modelNotFound(String)
    case rateLimited
    case server(Int, String)
    case badRequest(String)
    case refused
    case badResponse(String)
    case textTooLong(Int)

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            self = .offline
        case .timedOut:
            self = .timedOut
        default:
            self = .network(urlError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "还没有填写 API Key"
        case .missingModel: "还没有填写模型名称"
        case .invalidBaseURL: "服务地址（Base URL）无效"
        case .offline: "网络未连接"
        case .timedOut: "请求超时"
        case .network(let message): "网络错误：\(message)"
        case .unauthorized: "API Key 无效"
        case .forbidden(let message): "没有访问权限：\(message)"
        case .modelNotFound(let model): "找不到模型「\(model)」"
        case .rateLimited: "请求太频繁或额度不足"
        case .server(let status, _): "AI 服务暂时不可用（HTTP \(status)）"
        case .badRequest(let message): "请求被拒绝：\(message)"
        case .refused: "AI 拒绝处理这段文字"
        case .badResponse(let message): "AI 返回了无法理解的响应：\(message)"
        case .textTooLong(let limit): "文字太长（超过 \(limit) 字）"
        }
    }

    /// 根据 HTTP 状态码和响应体映射错误。
    static func from(status: Int, body: Data, model: String) -> AIError {
        let message = Self.errorMessage(in: body) ?? HTTPURLResponse.localizedString(forStatusCode: status)
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .modelNotFound(model)
        case 408: return .timedOut
        case 429: return .rateLimited
        case 400..<500:
            if message.lowercased().contains("model") && (message.contains("not") || message.contains("invalid")) {
                return .modelNotFound(model)
            }
            if message.lowercased().contains("api key") || message.lowercased().contains("api_key") {
                return .unauthorized
            }
            return .badRequest(message)
        default: return .server(status, message)
        }
    }

    /// 兼容 `{"error": {"message": ...}}` 和 `{"error": "..."}`、`{"message": ...}` 几种写法。
    static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? String(text!.prefix(200)) : nil
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        if let message = object["message"] as? String { return message }
        return nil
    }
}

extension URLRequest {
    static func jsonPost(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval = 60) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
