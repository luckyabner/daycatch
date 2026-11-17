import XCTest

final class ExtractionServiceTests: XCTestCase {
    private func service(_ provider: FakeProvider) -> ExtractionService {
        ExtractionService(provider: provider, timeZone: shanghai, now: { referenceNow })
    }

    func testEndToEndWithFakeAI() async throws {
        let provider = FakeProvider(reply: specSampleJSON)
        let result = try await service(provider).extract(text: "周四下午3点开 Q4 复盘会")
        XCTAssertEqual(result.items.map(\.title), ["Q4 复盘会", "准备各自模块的 Q4 数据"])

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertTrue(request.user.contains("2026-11-17T17:43:00+08:00"))
        XCTAssertTrue(request.user.contains("周四下午3点开 Q4 复盘会"))
        XCTAssertNotNil(request.responseSchema)
    }

    func testPropagatesProviderErrors() async {
        do {
            _ = try await service(FakeProvider(error: AIError.unauthorized)).extract(text: "明天开会")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? AIError, .unauthorized)
        }
    }

    func testUnparseableReplyIsFriendlyError() async {
        do {
            _ = try await service(FakeProvider(reply: "我不确定你的意思")).extract(text: "明天开会")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ExtractionError, .notJSON)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }

    func testEmptyInputSkipsAI() async throws {
        let provider = FakeProvider(reply: specSampleJSON)
        let result = try await service(provider).extract(text: "   \n ")
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testTooLongInputRejected() async {
        let text = String(repeating: "字", count: ExtractionService.maxInputLength + 1)
        do {
            _ = try await service(FakeProvider(reply: "{}")).extract(text: text)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? AIError, .textTooLong(ExtractionService.maxInputLength))
        }
    }
}

final class ExtractionPromptTests: XCTestCase {
    func testUserMessageContainsDateContext() {
        let message = ExtractionPrompt.userMessage(text: "下周一前发给法务", now: referenceNow, timeZone: shanghai, language: .chinese)
        XCTAssertTrue(message.contains("当前时间：2026-11-17T17:43:00+08:00（星期二）"))
        XCTAssertTrue(message.contains("时区：Asia/Shanghai（UTC+08:00）"))
        XCTAssertTrue(message.contains("- 2026-11-17 星期二（今天）"))
        XCTAssertTrue(message.contains("- 2026-11-18 星期三（明天）"))
        XCTAssertTrue(message.contains("- 2026-11-23 星期一"))
        XCTAssertTrue(message.contains("<text>\n下周一前发给法务\n</text>"))
    }

    func testNegativeOffset() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let message = ExtractionPrompt.userMessage(text: "x", now: referenceNow, timeZone: newYork, language: .chinese)
        XCTAssertTrue(message.contains("UTC-05:00"))
        XCTAssertTrue(message.contains("2026-11-17T04:43:00-05:00"))
    }

    func testSchemaIsValidJSON() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: ExtractionPrompt.responseSchema) as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertTrue(ExtractionPrompt.system(.chinese).contains("inferred"))
        XCTAssertTrue(ExtractionPrompt.system(.english).contains("inferred"))
    }
}
