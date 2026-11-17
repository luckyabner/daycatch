import AppKit

@main
@MainActor
enum DaycatchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            DebugSnapshots.render(to: URL(fileURLWithPath: arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.make()
        controller = AppController()
        // 调试用：等菜单栏图标布局完成后再打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if arguments.contains("--open-settings") { self?.controller?.openSettings() }
            if arguments.contains("--open-manual") { self?.controller?.openManual() }
            if arguments.contains("--open-agenda") { self?.controller?.openAgenda() }
        }
    }

    /// 再次打开 App（例如在访达里双击）时显示设置
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openSettings()
        return false
    }
}
