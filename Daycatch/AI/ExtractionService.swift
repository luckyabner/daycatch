import Foundation

/// 组合提示词 → 调用 AI → 解析 JSON 的完整流程。
struct ExtractionService: Sendable {
    static let maxInputLength = 20_000

    var provider: any AIProvider
    var timeZone: TimeZone = .current
    var now: @Sendable () -> Date = { Date() }

    func extract(text: String) async throws -> ExtractionResult {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= Self.maxInputLength else { throw AIError.textTooLong(Self.maxInputLength) }
        guard !input.isEmpty else { return ExtractionResult(summary: nil, items: []) }

        let request = AICompletionRequest(
            system: ExtractionPrompt.system,
            user: ExtractionPrompt.userMessage(text: input, now: now(), timeZone: timeZone),
            responseSchema: ExtractionPrompt.responseSchema
        )
        let reply = try await provider.complete(request)
        try Task.checkCancellation()
        return try ExtractionParser(timeZone: timeZone).parse(reply)
    }
}
