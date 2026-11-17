import AppKit
import Foundation
import Vision

/// 截图识别：`screencapture -i` 交互框选 → Vision 本机 OCR。图片只存在临时目录，识别后立即删除，绝不上传。
enum ScreenCapture {
    /// 返回截图文件；用户按 esc 取消时返回 nil。
    static func captureInteractive() async throws -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "daycatch-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i 交互框选（空格切换窗口模式）  -x 不播放声音  -o 窗口截图不带阴影
        process.arguments = ["-i", "-x", "-o", url.path]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

enum TextRecognizer {
    enum Failure: Error, LocalizedError {
        case unreadableImage

        var errorDescription: String? { Localization.strings.screenshotUnreadable }
    }

    /// 在后台线程用 Vision 识别文字（简体中文 + 英文），按阅读顺序拼接。
    static func recognizeText(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Failure.unreadableImage }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

            let observations = request.results ?? []
            return orderedLines(observations.compactMap { observation in
                observation.topCandidates(1).first.map { (observation.boundingBox, $0.string) }
            })
        }.value
    }

    /// 从上到下、同一行从左到右排序。Vision 坐标原点在左下角。
    static func orderedLines(_ boxes: [(CGRect, String)]) -> String {
        var rows: [(midY: CGFloat, height: CGFloat, items: [(CGRect, String)])] = []
        for entry in boxes.sorted(by: { $0.0.midY > $1.0.midY }) {
            if let last = rows.indices.last,
               abs(rows[last].midY - entry.0.midY) < min(rows[last].height, entry.0.height) * 0.5 {
                rows[last].items.append(entry)
            } else {
                rows.append((entry.0.midY, entry.0.height, [entry]))
            }
        }
        return rows
            .map { row in row.items.sorted { $0.0.minX < $1.0.minX }.map(\.1).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
