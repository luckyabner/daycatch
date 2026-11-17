// 最小验证：macOS 15 上只带 ⌥ / ⌥⇧ 修饰键的 Carbon 全局快捷键是否还能触发。
//
// 运行：swiftc Spikes/HotkeySpike.swift -o /tmp/hk && /tmp/hk
// 需要给运行它的终端开启「辅助功能」权限，否则模拟按键发不出去，结果没有意义。
// 输出 FIRED id 1 / 2 说明 ⌥Space / ⌥⇧S 能触发；只有 id 3（⌃⌥⌘K 对照组）触发则说明被系统拦截。

import Carbon
import AppKit
var fired: [UInt32] = []
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
  var hk = EventHotKeyID()
  GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
  print("FIRED id", hk.id); fflush(stdout)
  return noErr
}, 1, &spec, nil, nil)
func reg(_ key: Int, _ mods: Int, _ i: UInt32) { var r: EventHotKeyRef?; print(i, RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x44435448, id: i), GetApplicationEventTarget(), 0, &r)); refs.append(r) }
var refs: [EventHotKeyRef?] = []
reg(kVK_Space, optionKey, 1)
reg(kVK_ANSI_S, optionKey|shiftKey, 2)
reg(kVK_ANSI_K, optionKey|cmdKey|controlKey, 3)
print("AX trusted:", AXIsProcessTrusted())
func post(_ key: CGKeyCode, _ flags: CGEventFlags) {
  let src = CGEventSource(stateID: .hidSystemState)
  let d = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)!; d.flags = flags; d.post(tap: .cghidEventTap)
  let u = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)!; u.flags = flags; u.post(tap: .cghidEventTap)
}
DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
  post(CGKeyCode(kVK_ANSI_K), [.maskCommand,.maskAlternate,.maskControl])
  post(CGKeyCode(kVK_Space), .maskAlternate)
  post(CGKeyCode(kVK_ANSI_S), [.maskAlternate,.maskShift])
}
DispatchQueue.main.asyncAfter(deadline: .now()+2) { print("done"); exit(0) }
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
