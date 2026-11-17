import Foundation

/// 当前界面语言。AppController 在启动和设置变更时写入；
/// 界面重建后各处通过 `Localization.strings` / `ItemFormatter(...)` 取到对应语言。
enum Localization {
    private static let lock = NSLock()

    /// 默认中文：App 启动时由设置里的「语言」覆盖（测试和 `--snapshot` 也依赖这个默认值）。
    nonisolated(unsafe) private static var stored: AppLanguage = .chinese

    /// 写入时就解析掉 `.system`，界面读取时不必反复查系统首选语言
    static var language: AppLanguage {
        get { lock.withLock { stored } }
        set {
            let resolved = newValue.resolved
            lock.withLock { stored = resolved }
        }
    }

    static var strings: Strings { Strings(language: language) }
}
