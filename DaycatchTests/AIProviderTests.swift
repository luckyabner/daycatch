import XCTest

final class AIProviderTests: XCTestCase {
    private let request = AICompletionRequest(system: "SYS", user: "USER", responseSchema: ExtractionPrompt.responseSchema)

    // MARK: - 工厂

    func testFactoryValidatesConfiguration() {
        func make(_ key: String, _ model: String, _ url: String, _ provider: ProviderKind = .openai) -> Error? {
            do {
                _ = try AIProviderFactory.make(AIConfiguration(provider: provider, apiKey: key, model: model, baseURL: url))
                return nil
            } catch { return error }
        }
        XCTAssertEqual(make(" ", "m", "https://a.com") as? AIError, .missingAPIKey)
        XCTAssertEqual(make("k", "", "https://a.com") as? AIError, .missingModel)
        XCTAssertEqual(make("k", "m", "") as? AIError, .invalidBaseURL)
        XCTAssertEqual(make("k", "m", "ftp://a.com") as? AIError, .invalidBaseURL)
        XCTAssertNil(make("k", "m", "https://a.com/v1/"))
        XCTAssertTrue(try AIProviderFactory.make(AIConfiguration(provider: .anthropic, apiKey: "k", model: "m", baseURL: "https://api.anthropic.com")) is AnthropicProvider)
        XCTAssertTrue(try AIProviderFactory.make(AIConfiguration(provider: .deepseek, apiKey: "k", model: "m", baseURL: "https://api.deepseek.com/v1")) is OpenAICompatibleProvider)
    }

    // MARK: - Anthropic

    private func anthropic(_ http: StubHTTPClient, model: String = "claude-opus-5-5") -> AnthropicProvider {
        AnthropicProvider(apiKey: "sk-ant", model: model, baseURL: URL(string: "https://api.anthropic.com")!, http: http)
    }

    func testAnthropicRequestShape() async throws {
        let http = StubHTTPClient([(200, #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"items\":[]}"}],"stop_reason":"end_turn"}"#)])
        let text = try await anthropic(http).complete(request)
        XCTAssertEqual(text, #"{"items":[]}"#)

        let sent = http.requests[0]
        XCTAssertEqual(sent.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = http.body(at: 0)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["system"] as? String, "SYS")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["thinking"])
    }

    func testAnthropicOldModelOmitsOptionalParameters() async throws {
        let http = StubHTTPClient([(200, #"{"content":[{"type":"text","text":"{}"}]}"#)])
        _ = try await anthropic(http, model: "claude-3-5-haiku-latest").complete(request)
        let body = http.body(at: 0)
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil((body["output_config"] as? [String: Any])?["effort"])
        XCTAssertNil(http.requests[0].value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testAnthropicRetriesWithoutOptionalParametersOn400() async throws {
        let http = StubHTTPClient([
            (400, #"{"type":"error","error":{"type":"invalid_request_error","message":"output_config: not supported"}}"#),
            (200, #"{"content":[{"type":"text","text":"ok"}]}"#),
        ])
        let text = try await anthropic(http).complete(request)
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertNil(http.body(at: 1)["output_config"])
        XCTAssertNil(http.body(at: 1)["fallbacks"])
    }

    func testAnthropicErrors() async {
        await assertError(anthropic(StubHTTPClient([(401, #"{"error":{"message":"invalid x-api-key"}}"#)])), .unauthorized)
        await assertError(anthropic(StubHTTPClient([(404, #"{"error":{"message":"model: x"}}"#)])), .modelNotFound("claude-opus-5-5"))
        await assertError(anthropic(StubHTTPClient([(429, "{}")])), .rateLimited)
        await assertError(anthropic(StubHTTPClient([(529, #"{"error":{"message":"Overloaded"}}"#)])), .server(529, "Overloaded"))
        await assertError(anthropic(StubHTTPClient([(200, #"{"content":[],"stop_reason":"refusal"}"#)])), .refused)
        await assertError(anthropic(StubHTTPClient([(200, "<html>")])), .badResponse("响应不是 JSON"))

        let offline = StubHTTPClient([])
        offline.error = AIError(urlError: URLError(.notConnectedToInternet))
        await assertError(anthropic(offline), .offline)
    }

    // MARK: - OpenAI 兼容

    private func openAI(_ http: StubHTTPClient) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(apiKey: "sk-oa", model: "deepseek-chat", baseURL: URL(string: "https://api.deepseek.com/v1")!, http: http)
    }

    func testOpenAIRequestShape() async throws {
        let http = StubHTTPClient([(200, #"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[]}"}}]}"#)])
        let text = try await openAI(http).complete(request)
        XCTAssertEqual(text, #"{"items":[]}"#)

        let sent = http.requests[0]
        XCTAssertEqual(sent.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-oa")
        let body = http.body(at: 0)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "SYS"], ["role": "user", "content": "USER"]])
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testOpenAIRetriesWithoutJSONMode() async throws {
        let http = StubHTTPClient([
            (400, #"{"error":{"message":"response_format is not supported"}}"#),
            (200, #"{"choices":[{"message":{"content":"ok"}}]}"#),
        ])
        let text = try await openAI(http).complete(request)
        XCTAssertEqual(text, "ok")
        XCTAssertNil(http.body(at: 1)["response_format"])
    }

    func testOpenAIErrors() async {
        await assertError(openAI(StubHTTPClient([(401, #"{"error":{"message":"Incorrect API key provided"}}"#)])), .unauthorized)
        await assertError(openAI(StubHTTPClient([(200, #"{"choices":[{"message":{"content":null,"refusal":"no"}}]}"#)])), .refused)
        await assertError(openAI(StubHTTPClient([(500, "oops")])), .server(500, "oops"))
    }

    private func assertError(_ provider: any AIProvider, _ expected: AIError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await provider.complete(request)
            XCTFail("应该抛出 \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AIError, expected, file: file, line: line)
        }
    }
}
