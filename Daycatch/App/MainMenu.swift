import AppKit

/// 菜单栏应用不显示主菜单，但 ⌘V / ⌘C / ⌘X / ⌘A / ⌘Z 这些快捷键要靠主菜单里的
/// "编辑"菜单项才会转发给输入框（不激活应用的浮动面板也一样）。没有它，设置页和输入框里都无法粘贴。
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let t = Localization.strings
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Daycatch")
        appMenu.addItem(withTitle: t.menuCloseWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: t.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: t.menuEdit)
        edit.addItem(withTitle: t.menuUndo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: t.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: t.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: t.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: t.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: t.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
