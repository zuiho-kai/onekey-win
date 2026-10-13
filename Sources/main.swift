// 一键切换win：一个菜单栏图标，管理 Windows 用户转 Mac 常用的几个开源工具。
// 它不替代这些工具，只负责：看状态、安装、启动/重启、打开设置、显示或隐藏它们自己的菜单栏图标。
import AppKit
import ServiceManagement

// MARK: - 工具清单

enum IconPref {
    case bool(key: String, hiddenValue: Bool)      // 布尔开关
    case string(key: String, shown: String, hidden: String)
    case int(key: String, shown: Int, hidden: Int)
}

struct Tool {
    let name: String          // App 名
    let role: String          // 对应的 Windows 习惯
    let bundleID: String
    let repo: String          // GitHub owner/repo，用来安装
    let iconPrefs: [IconPref] // 控制它自己菜单栏图标的偏好设置
}

let tools: [Tool] = [
    Tool(name: "Rectangle", role: "窗口贴边（Win+方向键）", bundleID: "com.knollsoft.Rectangle",
         repo: "rxhanson/Rectangle",
         iconPrefs: [.bool(key: "hideMenubarIcon", hiddenValue: true)]),
    Tool(name: "AltTab", role: "Alt+Tab 切窗口", bundleID: "com.lwouis.alt-tab-macos",
         repo: "lwouis/alt-tab-macos",
         iconPrefs: [.string(key: "menubarIconShown", shown: "true", hidden: "false")]),
    Tool(name: "LinearMouse", role: "滚轮方向 / 中键滚动", bundleID: "com.lujjjh.LinearMouse",
         repo: "linearmouse/linearmouse",
         iconPrefs: [.bool(key: "showInMenuBar", hiddenValue: false),
                     // Defaults 库把字符串枚举存成 JSON 字符串
                     .string(key: "menuBarVisibilityMode", shown: "\"always\"", hidden: "\"never\"")]),
    Tool(name: "MonitorControl", role: "外接显示器亮度", bundleID: "app.monitorcontrol.MonitorControl",
         repo: "MonitorControl/MonitorControl",
         iconPrefs: [.int(key: "menuIcon", shown: 0, hidden: 2)]),
]

// 和 Windows 一样的鼠标手感：反向滚动、每格 3 行无加速、⌘+滚轮缩放、中键自动滚动
let linearMousePreset = """
{
  "$schema": "https://app.linearmouse.org/schema/0.12.0",
  "schemes": [
    {
      "if": { "device": { "category": "mouse" } },
      "scrolling": {
        "reverse": { "vertical": true, "horizontal": true },
        "smoothed": { "enabled": false },
        "distance": { "vertical": "3", "horizontal": "3" },
        "modifiers": { "command": { "type": "zoom" } }
      },
      "buttons": {
        "autoScroll": {
          "enabled": true,
          "trigger": { "button": 2 },
          "mode": ["toggle", "hold"],
          "toggleActivation": "shortPress",
          "speed": 0.5
        }
      }
    }
  ]
}

"""

// MARK: - 工具状态与操作

enum ToolState { case running, stopped, missing }

func appURL(_ t: Tool) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleID) }
func runningApp(_ t: Tool) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: t.bundleID).first
}
func state(_ t: Tool) -> ToolState {
    if runningApp(t) != nil { return .running }
    return appURL(t) == nil ? .missing : .stopped
}

func iconShown(_ t: Tool) -> Bool {
    guard let d = UserDefaults(suiteName: t.bundleID), let p = t.iconPrefs.first else { return true }
    switch p {
    case let .bool(key, hidden): return d.object(forKey: key) == nil || d.bool(forKey: key) != hidden
    case let .string(key, _, hidden): return d.string(forKey: key) != hidden
    case let .int(key, _, hidden): return d.object(forKey: key) == nil || d.integer(forKey: key) != hidden
    }
}

func setIconShown(_ t: Tool, _ show: Bool) {
    guard let d = UserDefaults(suiteName: t.bundleID) else { return }
    for p in t.iconPrefs {
        switch p {
        case let .bool(key, hidden): d.set(show ? !hidden : hidden, forKey: key)
        case let .string(key, shown, hidden): d.set(show ? shown : hidden, forKey: key)
        case let .int(key, shown, hidden): d.set(show ? shown : hidden, forKey: key)
        }
    }
    d.synchronize()
}

/// 打开 App。App 已在运行时，系统会发「重新打开」事件，这几个工具收到后都会弹出设置窗口。
func launch(_ t: Tool, activate: Bool) {
    guard let url = appURL(t) else { return }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = activate
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, err in
        if let err { NSLog("onekey-win: 打开 %@ 失败：%@", t.name, err.localizedDescription) }
    }
}

func runCommand(_ path: String, _ args: [String]) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    if p.terminationStatus != 0 {
        throw NSError(domain: "onekey-win", code: Int(p.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(path) 失败：\(text)"])
    }
    return text
}

/// 从 GitHub 最新 release 下载 dmg/zip，装进 /Applications。
func install(_ t: Tool) async throws {
    var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(t.repo)/releases/latest")!)
    req.setValue("onekey-win", forHTTPHeaderField: "User-Agent")
    let (meta, _) = try await URLSession.shared.data(for: req)
    struct Release: Decodable { struct Asset: Decodable { let name: String; let browser_download_url: URL }; let assets: [Asset] }
    let assets = try JSONDecoder().decode(Release.self, from: meta).assets
    guard let asset = assets.first(where: { $0.name.hasSuffix(".dmg") })
        ?? assets.first(where: { $0.name.hasSuffix(".zip") && !$0.name.contains("dSYM") })
    else { throw NSError(domain: "onekey-win", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(t.name) 的最新版本里没有 dmg 或 zip"]) }

    let (tmp, _) = try await URLSession.shared.download(from: asset.browser_download_url)
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("onekey-win-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let file = work.appendingPathComponent(asset.name)
    try FileManager.default.moveItem(at: tmp, to: file)

    var source = work.appendingPathComponent("x")
    var mount: String?
    if asset.name.hasSuffix(".dmg") {
        let mp = work.appendingPathComponent("mnt").path
        _ = try runCommand("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mp, file.path])
        mount = mp
        source = URL(fileURLWithPath: mp)
    } else {
        _ = try runCommand("/usr/bin/ditto", ["-x", "-k", file.path, source.path])
    }
    defer { if let mount { _ = try? runCommand("/usr/bin/hdiutil", ["detach", "-force", mount]) } }

    let items = try FileManager.default.contentsOfDirectory(atPath: source.path)
    guard let app = items.first(where: { $0.hasSuffix(".app") }) else {
        throw NSError(domain: "onekey-win", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(asset.name) 里找不到 .app"])
    }
    _ = try runCommand("/usr/bin/ditto", [source.appendingPathComponent(app).path, "/Applications/\(app)"])
}

// MARK: - 菜单栏

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var installing: Set<String> = []
    var appsObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        // 进程列表变化时才刷新图标，不轮询
        appsObserver = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshIcon() }
        }
        // 第一次运行默认打开开机启动；之后以用户在菜单里的选择为准
        if !UserDefaults.standard.bool(forKey: "loginItemInitialized") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemInitialized")
        }
        // 开机自启后，把装了但没运行的工具拉起来
        for t in tools where state(t) == .stopped { launch(t, activate: false) }
        refreshIcon()
    }

    @objc func refreshIcon() {
        let bad = tools.contains { state($0) == .stopped }
        let img = NSImage(systemSymbolName: bad ? "exclamationmark.triangle" : "w.square",
                          accessibilityDescription: "一键切换win")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = bad ? "一键切换win：有工具没在运行" : "一键切换win"
    }

    // 每次点开菜单都重建，保证状态是最新的
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "一键切换win", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        for (i, t) in tools.enumerated() {
            let st = installing.contains(t.bundleID) ? nil : state(t)
            let mi = NSMenuItem(title: "\(t.role) · \(t.name)", action: nil, keyEquivalent: "")
            let (dot, color): (String, NSColor) = switch st {
            case .running: ("●", .systemGreen)
            case .stopped: ("●", .systemRed)
            case .missing: ("○", .secondaryLabelColor)
            case nil: ("↓", .systemBlue)
            }
            // 新版 macOS 菜单不画 item.image，所以用彩色文字圆点表示状态
            let label = NSMutableAttributedString(string: "\(dot)  ", attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 0)])
            label.append(NSAttributedString(string: "\(t.role) · \(t.name)", attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            mi.attributedTitle = label
            let sub = NSMenu()
            let statusText = switch st {
            case .running: "运行中"
            case .stopped: "没在运行"
            case .missing: "未安装"
            case nil: "正在安装…"
            }
            let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            status.isEnabled = false
            sub.addItem(status)
            sub.addItem(.separator())
            switch st {
            case .running:
                sub.addItem(action("打开设置", #selector(openSettings(_:)), i))
                sub.addItem(action("重启", #selector(restart(_:)), i))
                let icon = action("显示它自己的菜单栏图标", #selector(toggleIcon(_:)), i)
                icon.state = iconShown(t) ? .on : .off
                sub.addItem(icon)
            case .stopped:
                sub.addItem(action("启动", #selector(start(_:)), i))
            case .missing:
                sub.addItem(action("安装（从 GitHub 下载最新版）", #selector(installOne(_:)), i))
            case nil: break
            }
            sub.addItem(action("项目主页", #selector(homepage(_:)), i))
            mi.submenu = sub
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        if tools.contains(where: { state($0) == .missing }) {
            menu.addItem(action("一键安装缺少的工具", #selector(installAll), 0))
        }
        if tools.contains(where: { state($0) == .stopped }) {
            menu.addItem(action("一键启动全部", #selector(startAll), 0))
        }
        if state(tools[2]) != .missing {
            menu.addItem(action("应用 Windows 鼠标手感（LinearMouse）…", #selector(applyMousePreset), 0))
        }
        menu.addItem(.separator())
        let login = action("开机启动", #selector(toggleLogin), 0)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func action(_ title: String, _ sel: Selector, _ tag: Int) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        m.target = self
        m.tag = tag
        return m
    }

    @objc func openSettings(_ s: NSMenuItem) { launch(tools[s.tag], activate: true) }
    @objc func start(_ s: NSMenuItem) { launch(tools[s.tag], activate: false) }
    @objc func startAll() { for t in tools where state(t) == .stopped { launch(t, activate: false) } }
    @objc func homepage(_ s: NSMenuItem) { NSWorkspace.shared.open(URL(string: "https://github.com/\(tools[s.tag].repo)")!) }
    @objc func restart(_ s: NSMenuItem) { restartTool(tools[s.tag]) }

    @objc func toggleIcon(_ s: NSMenuItem) {
        let t = tools[s.tag]
        setIconShown(t, !iconShown(t))
        restartTool(t)  // 这几个工具都只在启动时读这个设置
    }

    func restartTool(_ t: Tool) {
        guard let app = runningApp(t) else { launch(t, activate: false); return }
        app.terminate()
        var waited = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            waited += 0.25
            if app.isTerminated {
                timer.invalidate()
                launch(t, activate: false)
            } else if waited >= 5 {
                app.forceTerminate()
            }
        }
    }

    @objc func installOne(_ s: NSMenuItem) { installTools([tools[s.tag]]) }
    @objc func installAll() { installTools(tools.filter { state($0) == .missing }) }

    func installTools(_ list: [Tool]) {
        for t in list { installing.insert(t.bundleID) }
        Task { @MainActor in
            var failed: [String] = []
            for t in list {
                do {
                    try await install(t)
                    launch(t, activate: true)
                } catch {
                    failed.append("\(t.name)：\(error.localizedDescription)")
                }
                installing.remove(t.bundleID)
            }
            refreshIcon()
            if !failed.isEmpty { alert("有工具没装上", failed.joined(separator: "\n")) }
        }
    }

    @objc func applyMousePreset() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/linearmouse")
        let file = dir.appendingPathComponent("linearmouse.json")
        let a = NSAlert()
        a.messageText = "把鼠标改成 Windows 手感？"
        a.informativeText = """
        • 鼠标滚动方向和 Windows 一样（触控板不变）
        • 滚轮每格 3 行，不加速、不惯性
        • ⌘+滚轮缩放（换过 Ctrl/⌘ 的话就是 Ctrl+滚轮）
        • 按一下中键出现圆点，移动鼠标自动滚动

        原来的配置会备份成 linearmouse.json.bak-时间戳。
        """
        a.addButton(withTitle: "应用")
        a.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                try FileManager.default.copyItem(at: file, to: dir.appendingPathComponent("linearmouse.json.bak-\(stamp)"))
            }
            try linearMousePreset.write(to: file, atomically: true, encoding: .utf8)
            restartTool(tools[2])
        } catch {
            alert("没写进去", error.localizedDescription)
        }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("开机启动设置失败", error.localizedDescription)
        }
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
