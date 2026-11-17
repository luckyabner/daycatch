import Foundation

let shanghai = TimeZone(identifier: "Asia/Shanghai")!

/// 2026-11-17 17:43（周二，上海时间），与设计稿一致
let referenceNow: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 17
    components.hour = 17
    components.minute = 43
    components.timeZone = shanghai
    return Calendar(identifier: .gregorian).date(from: components)!
}()

func shanghaiDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = shanghai
    return Calendar(identifier: .gregorian).date(from: components)!
}

/// 返回预设回复的假 AI，同时记录收到的请求
final class FakeProvider: AIProvider, @unchecked Sendable {
    var reply: Result<String, Error>
    private(set) var requests: [AICompletionRequest] = []

    init(reply: String) { self.reply = .success(reply) }
    init(error: Error) { self.reply = .failure(error) }

    func complete(_ request: AICompletionRequest) async throws -> String {
        requests.append(request)
        return try reply.get()
    }
}

/// 按顺序返回预设 HTTP 响应，同时记录请求
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    var error: Error?

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        let (status, body) = responses.isEmpty ? (500, "") : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func body(at index: Int) -> [String: Any] {
        guard requests.indices.contains(index), let data = requests[index].httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}

/// 设计稿 §6 的示例回复
let specSampleJSON = """
{
  "summary": "周四下午 3 楼开 Q4 复盘会，会前需准备数据。",
  "items": [
    {
      "kind": "event",
      "title": "Q4 复盘会",
      "start": "2026-11-19T15:00:00+08:00",
      "end": "2026-11-19T16:30:00+08:00",
      "location": "3 楼大会议室",
      "notes": "线上会议号 728 391 045",
      "alarmMinutesBefore": 15,
      "inferred": []
    },
    {
      "kind": "todo",
      "title": "准备各自模块的 Q4 数据",
      "due": "2026-11-19T15:00:00+08:00",
      "inferred": []
    }
  ]
}
"""
