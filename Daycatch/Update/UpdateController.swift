import AppKit
import Observation
import Sparkle

/// 自动更新：把 Sparkle 的 `SPUStandardUpdaterController` 包一层，给设置页和菜单栏提供
/// 当前版本、检查入口和检查结果。
///
/// 更新源是 GitHub Release 上的 `appcast.xml`（`SUFeedURL`，见 docs/updates.md）。
/// 安装由 Sparkle 自己完成：下载 → 校验 EdDSA 签名 → 替换 /Applications 里的 app → 重启。
@MainActor
@Observable
final class UpdateController: NSObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(String)
        case failed(String)
    }

    private var controller: SPUStandardUpdaterController!

    /// 检查结果。Sparkle 的下载/安装进度由它自己的窗口显示，这里只记「有没有新版本」
    private(set) var status: Status = .idle
    /// `automaticallyChecksForUpdates` 的镜像：Sparkle 把它存在 UserDefaults 里，
    /// 这里存一份是为了让 SwiftUI 能观察到变化。
    private(set) var checksAutomatically = true
    private(set) var lastCheckDate: Date?

    /// 后台检查发现新版本、但 app 不在前台时回调（由 AppController 用通知卡片提醒）
    var onScheduledUpdateFound: ((String) -> Void)?
    /// 用户已经开始处理这个更新了：收起自己的提醒卡片
    var onUpdateAttention: (() -> Void)?

    /// 显示的版本形如 `0.2.0 (37)`：`CFBundleShortVersionString` 给人看，
    /// `CFBundleVersion` 是 Sparkle 比较用的递增整数。
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    override init() {
        super.init()
        // startingUpdater: true：按 Info.plist 的 SUEnableAutomaticChecks / SUScheduledCheckInterval
        // 安排后台检查。要在 applicationDidFinishLaunching 之后创建，AppController 正好满足。
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        lastCheckDate = controller.updater.lastUpdateCheckDate
    }

    var isChecking: Bool { status == .checking }

    /// 用户主动检查：Sparkle 会显示自己的窗口（正在检查 / 发现更新 / 已是最新 / 出错）
    func checkForUpdates() {
        guard status != .checking, controller.updater.canCheckForUpdates else { return }
        status = .checking
        controller.updater.checkForUpdates()
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        checksAutomatically = enabled
    }
}

// MARK: - Sparkle 回调

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .updateAvailable(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        if case .updateAvailable = status { return }
        status = .upToDate
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        lastCheckDate = Date()
        if let error {
            // 「没有新版本」不算失败；已经发现新版本时，后续错误留给 Sparkle 的窗口去说
            if case .updateAvailable = status { return }
            let failure = error as NSError
            let sparkle = failure.domain == SUSparkleErrorDomain
                && SUError(rawValue: Int32(failure.code)) == .noUpdateError
            if sparkle { status = .upToDate } else { status = .failed(error.localizedDescription) }
            return
        }
        if status == .checking { status = .upToDate }
    }
}

/// 菜单栏 app 没有 Dock 图标，平时在后台跑：按 Sparkle 的「温和提醒」流程处理后台检查——
/// 在前台就让它自己弹窗口，在后台则交给 AppController 的右下角卡片，不抢焦点。
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // 返回 YES 表示由 Sparkle 的标准窗口负责显示；只有在 app 前台时才这么做
        NSApp.isActive
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            // 标准窗口要弹了：先把 app 拉到前台，否则窗口会建在别的 app 后面
            NSApp.activate()
        } else {
            onScheduledUpdateFound?(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onUpdateAttention?()
    }
}
