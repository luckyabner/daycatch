import Foundation

/// API Key 存储：`~/Library/Application Support/com.luckyabner.daycatch/credentials.json`。
///
/// 不用钥匙串：App 是 ad-hoc 签名，每次重新编译签名都会变，钥匙串会反复弹窗要求授权。
/// 文件权限设为 0600（目录 0700），只有当前用户能读写；不写进 UserDefaults，也不进代码。
struct CredentialStore: Sendable {
    static let shared = CredentialStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "com.luckyabner.daycatch", directoryHint: .isDirectory)
    )

    let directory: URL
    var fileURL: URL { directory.appending(path: "credentials.json") }

    func apiKey(for provider: ProviderKind) -> String {
        load()[provider.rawValue] ?? ""
    }

    @discardableResult
    func setAPIKey(_ key: String, for provider: ProviderKind) -> Bool {
        var keys = load()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keys[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        return save(keys)
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let keys = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return keys
    }

    private func save(_ keys: [String: String]) -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(keys)
            // 先以 0600 创建空文件再写入，避免内容出现在默认权限的文件里
            if !manager.fileExists(atPath: fileURL.path) {
                manager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
