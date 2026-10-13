# 一键切换win

从 Windows 转到 Mac，常见做法是装一堆小工具：窗口贴边、Alt+Tab、滚轮方向、显示器亮度……
装完以后菜单栏挤满图标；把图标藏起来，又不知道它们还在不在跑、去哪改设置。

**一键切换win** 是一个菜单栏小程序，用一个图标管这些工具：

```
[W]
 ├─ ● 窗口贴边（Win+方向键）· Rectangle      ▸ 打开设置 / 重启 / 显示它自己的菜单栏图标 / 项目主页
 ├─ ● Alt+Tab 切窗口 · AltTab
 ├─ ● 滚轮方向 / 中键滚动 · LinearMouse
 ├─ ○ 外接显示器亮度 · MonitorControl        ▸ 安装（从 GitHub 下载最新版）
 ├─ 一键安装缺少的工具
 ├─ 应用 Windows 鼠标手感（LinearMouse）…
 └─ ✓ 开机启动
```

- **● 绿**：在运行。**● 红**：装了但没运行（菜单栏图标会变成 ⚠️）。**○**：没装。
- **一键安装**：从各工具的 GitHub 最新 release 下载 dmg/zip，装进 `/Applications`。这些工具本身都有开发者签名。
- **开机启动**：第一次运行时自动打开，可在菜单里关掉。它开机后会把装了但没运行的工具拉起来，所以各工具不用再单独设「登录时启动」。
- **不轮询**：只在进程列表变化时刷新状态，平时几乎不占 CPU。
- **显示/隐藏图标**：改的是各工具自己的设置，然后重启它让设置生效。
- **Windows 鼠标手感**：给 LinearMouse 写一份配置：鼠标滚动方向和 Windows 一样（触控板不变）、滚轮每格 3 行不加速、⌘+滚轮缩放、按一下中键自动滚动。原配置先备份。

它不改系统，也不替代这些工具，只是给它们一个统一的入口。

## 管理的工具

| 工具 | 对应 Windows 习惯 | 项目 |
|---|---|---|
| Rectangle | Win+方向键 分屏/贴边 | [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) |
| AltTab | Alt+Tab 切窗口（带缩略图） | [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) |
| LinearMouse | 滚轮方向、线性滚动、中键自动滚动 | [linearmouse/linearmouse](https://github.com/linearmouse/linearmouse) |
| MonitorControl | 键盘调外接显示器亮度 | [MonitorControl/MonitorControl](https://github.com/MonitorControl/MonitorControl) |

这几个工具都要「辅助功能」权限（AltTab 还要「屏幕录制」），第一次启动时按它们自己的提示授权。

**Ctrl 和 ⌘ 互换**不需要装工具：系统设置 → 键盘 → 键盘快捷键 → 修饰键，选你的键盘，把 Control 和 Command 对调。

## 安装

1. 到 [Releases](../../releases) 下载 `onekey-win-x.y.z.zip`，解压，把 `一键切换win.app` 拖进「应用程序」。
2. 这个 App 没有 Apple 公证。第一次打开时系统会拦截：到 系统设置 → 隐私与安全性，往下找到「一键切换win」，点「仍要打开」。
   或者在终端执行：`xattr -dr com.apple.quarantine /Applications/一键切换win.app`
3. 菜单栏出现 **W** 图标。点开，按需「一键安装缺少的工具」，开机启动默认已打开。

需要 macOS 13 或更新，Apple 芯片和 Intel 都能用。

> 国内直连 GitHub 下载可能很慢。一键安装走系统代理设置；没开系统代理的话，也可以自己下载这些工具装进「应用程序」，本程序会自动识别。

## 从源码编译

只需要 Xcode 命令行工具（`xcode-select --install`）：

```sh
./build.sh          # 生成 build/一键切换win.app
./build.sh --zip    # 另外打一个发布用的 zip
```

全部代码在 `Sources/main.swift` 一个文件里。想加别的工具，在 `tools` 数组里加一项：Bundle ID、GitHub 仓库、控制菜单栏图标的偏好设置键。

## 许可

MIT
