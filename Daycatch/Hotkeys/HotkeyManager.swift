import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 全局快捷键。
///
/// 两条通道同时工作：
/// 1. Carbon `RegisterEventHotKey`：不需要任何权限；但 macOS 15 起，只用 ⌥ 或 ⌥⇧ 作修饰键的
///    组合（正是默认的 ⌥Space、⌥⇧S）可能不再触发。
/// 2. `CGEventTap`：拿到辅助功能权限后启用，能可靠捕获上述组合并吞掉按键，避免在前台应用里
///    打出不间断空格等字符。
/// 两条通道都命中时按时间去重，只触发一次。
@MainActor
final class HotkeyManager {
    private var shortcuts: [HotkeyAction: Shortcut] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var carbonRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var carbonHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var lastFired: [HotkeyAction: Date] = [:]
    private var permissionTimer: Timer?

    /// 录制新快捷键时暂停响应
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            isSuspended ? unregisterCarbon() : registerCarbon()
        }
    }

    var isEventTapActive: Bool { eventTap != nil }

    func setHandler(for action: HotkeyAction, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    func update(_ newShortcuts: [HotkeyAction: Shortcut]) {
        shortcuts = newShortcuts
        installCarbonHandlerIfNeeded()
        if !isSuspended { registerCarbon() }
        installEventTapIfPossible()
        startPermissionPolling()
    }

    // MARK: - 分发

    fileprivate func fire(_ action: HotkeyAction) {
        let now = Date()
        if let last = lastFired[action], now.timeIntervalSince(last) < 0.35 { return }
        lastFired[action] = now
        handlers[action]?()
    }

    fileprivate func action(matching shortcut: Shortcut) -> HotkeyAction? {
        guard !isSuspended else { return nil }
        return shortcuts.first { $0.value == shortcut }?.key
    }

    // MARK: - Carbon

    private static let signature: OSType = 0x4443_5448 // "DCTH"

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let index = Int(hotKeyID.id)
            MainActor.assumeIsolated {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                guard !manager.isSuspended, HotkeyAction.allCases.indices.contains(index) else { return }
                manager.fire(HotkeyAction.allCases[index])
            }
            return noErr
        }
        InstallEventHandler(
            GetEventDispatcherTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &carbonHandler
        )
    }

    private func registerCarbon() {
        unregisterCarbon()
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let shortcut = shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr, let ref { carbonRefs[action] = ref }
        }
    }

    private func unregisterCarbon() {
        for ref in carbonRefs.values { UnregisterEventHotKey(ref) }
        carbonRefs.removeAll()
    }

    // MARK: - Event tap

    private func installEventTapIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let consumed: Bool = MainActor.assumeIsolated {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleTapEvent(type: type, event: event)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        tapSource = source
    }

    /// 返回 true 表示吞掉该按键
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        guard type == .keyDown else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let shortcut = Shortcut(keyCode: keyCode, cgFlags: event.flags)
        guard let action = action(matching: shortcut) else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            fire(action)
        }
        return true
    }

    /// 用户可能在运行中才授予辅助功能权限，定期检查以便及时启用 event tap。
    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.eventTap == nil {
                    self.installEventTapIfPossible()
                } else if !AXIsProcessTrusted() {
                    self.removeEventTap()
                }
            }
        }
    }

    private func removeEventTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        eventTap = nil
        tapSource = nil
    }
}
