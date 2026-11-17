# Daycatch

macOS 菜单栏应用：用 AI 从微信、钉钉、邮件里的文字中提取日程和待办，确认后一键写入「日历」和「提醒事项」。

## 构建

需要 macOS 14+、Xcode 15+，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
make build      # 生成 Daycatch.xcodeproj 并编译 Debug
make test       # 运行单元测试（不联网、不启动 App）
make run        # 编译并启动（菜单栏出现日历图标）
make snapshot   # 用示例数据把各界面渲染成 PNG：build/snapshots/
```

工程文件由 `project.yml` 生成，不要手动修改 `Daycatch.xcodeproj`。

## 使用

| 入口 | 默认快捷键 | 说明 |
|---|---|---|
| 选中识别 | ⌥ Space | 读取当前选中的文字，结果显示在鼠标旁的浮动面板 |
| 截图识别 | ⌥ ⇧ S | 框选屏幕区域，本机 OCR 后识别，图片不上传 |
| 手动输入 | ⌥ ⇧ Space / 点击菜单栏图标 | 粘贴文字后按 ⌘↩ 识别 |

结果面板：↩ 添加勾选项，⌘E 行内编辑，esc 关闭。右键菜单栏图标可打开设置或退出。

首次使用需要在设置的「AI 服务」中选择服务商、填写 API Key 和模型。

## 权限

| 权限 | 用途 | 何时请求 |
|---|---|---|
| 辅助功能 | 读取选中文字、在读取失败时模拟 ⌘C，以及在 macOS 15 上可靠捕获 ⌥Space 等快捷键 | 第一次按 ⌥Space |
| 屏幕录制 | 截图识别 | 第一次按 ⌥⇧S |
| 日历 / 提醒事项（完全访问） | 写入事项，撤销时删除 | 第一次点「添加」 |

没有开发者证书。`make build` 会用 `scripts/sign.sh` 生成并使用一个本地自签名证书（存放在项目内的 `.signing/`，不改动登录钥匙串），签名身份固定为「Bundle ID + 证书」，**重新编译后已授予的权限不会失效**。只有删除 `.signing/` 才需要重新授权一次。

注意：

- 请用 `make run` 或 `open build/Build/Products/Debug/Daycatch.app` 启动。直接在终端运行 `Contents/MacOS/Daycatch` 时，系统会按终端来判断权限。
- 直接用 Xcode 或 `xcodebuild` 编译出来的是 ad-hoc 签名，权限会随每次编译失效。

API Key 不放钥匙串（钥匙串会因签名变化反复弹窗），而是存在 `~/Library/Application Support/com.luckyabner.daycatch/credentials.json`，文件权限 0600，只有当前用户可读写。

## 代码结构

```
Daycatch/
  App/          入口、AppController（串起各流程）、浮动面板、菜单栏图标、设置窗口
  UI/           设计 Token、结果面板 ①②、菜单栏弹窗 ③、通知卡片、设置页 ④
  AI/           AIProvider 协议、Claude / OpenAI 兼容实现、提示词、ExtractionService
  Model/        事项模型、AI 返回 JSON 的解析、日期解析、展示文字格式化
  Recognition/  选中文字读取（AX + ⌘C 回退）、截图 + Vision OCR、权限
  Calendar/     EventKit 写入与撤销
  Settings/     UserDefaults 设置、API Key 文件存储
  Hotkeys/      全局快捷键（Carbon + CGEventTap）
DaycatchTests/  单元测试（假 AI 响应、假 HTTP）
Spikes/         系统 API 的最小验证脚本
```
