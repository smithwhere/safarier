# Safarier 独立 iOS 浏览器（开发预览）

在 iPhone / iPad 本机运行，不依赖远程 Mac。最低 iOS 17，使用系统 WKWebView。

## 构建

在安装 Xcode 和命令行工具的 Mac 上执行：

```sh
brew install xcodegen
xcodegen generate --spec iOS/project.yml
open iOS/SafarierIOS.xcodeproj
```

选择 SafarierIOS scheme，在 Signing & Capabilities 选择自己的开发团队并修改 Bundle ID，然后选择 iPhone 运行。真机安装或导出 IPA 需要有效的 Apple 签名；CI 的 unsigned .app 不能直接安装到普通 iPhone。无需为日常浏览持续连接 Mac。

自动化检查位于 `.github/workflows/ios.yml`：生成工程、构建未签名的真机 app、运行模拟器测试。macOS 原有 Package.swift 与目标保持独立。

## 已实现范围

- 中文 iPhone/iPad 界面，环境创建与删除；地址/搜索栏、前进、后退、刷新。
- UUID 标识的独立持久网站数据存储；临时环境使用独立内存数据存储，关闭时释放。
- 每个环境独立的无需认证 SOCKS5 / HTTP CONNECT 配置；明确 `allowFailover = false`，配置无效则禁止创建网页视图。
- 不设置自定义 UA，不添加 WKUserScript，不调用私有接口。保留系统 WebKit 的默认安全与隐私行为。
- 新窗口链接在当前环境打开，不转交 Safari 或其它应用。环境设置不允许在浏览中更改。

## 能力边界

这是开发预览，不是已验证可用于敏感账号的完整指纹浏览器。

- 本机呈现 iOS WebKit 环境，不是 macOS Safari，也不保证与 Safari App 完全相同。
- 不声称已开启或验证 Safari 高级 Canvas/WebGL/Audio 加噪；无“34 款 Mac”模拟。
- 数据存储隔离不等于物理隔离，不保证每个环境独占 WebKit 进程。第一版一次打开一个环境。
- 无订阅导入、sing-box、代理认证、多标签、下载管理或跨平台配置导入；后续需独立移植。
- 原生 WebKit 默认处理网页 JavaScript 对话框的支持有限，本版尚未实现完整浏览器功能。
- 代理配置禁止回退，但 DNS、WebRTC、媒体和重定向路径的网络泄漏仍需要真机抓包验证。不能把设置成功称为零泄漏验证通过。
- 关闭临时环境会释放网页视图和存储引用；iOS 对 WebKit 进程回收时机自行调度。
- 目前没有 App Store / TestFlight 发布或证书配置。

## 发布前必测

1. 在两个持久环境登录不同的自有测试账号，重启应用后确认会话分别保留且不串用。
2. 关闭后重开临时环境，确认 Cookie、localStorage、IndexedDB 和 Service Worker 数据不残留。
3. 对自有测试服务观察代理出口，断开代理后确认主页面、iframe、WebSocket、媒体、DNS 与 WebRTC 不旁路直连。
4. 验证环境删除、应用被杀、设备锁定/解锁、后台恢复、网页进程被回收。
5. 在目标 iPhone/iPad 上验证输入法、键盘布局、旋转、登录流程和证书错误处理。

## 官方 API

- https://developer.apple.com/documentation/webkit/wkwebsitedatastore
- https://developer.apple.com/documentation/network/proxyconfiguration
- https://developer.apple.com/documentation/network/proxyconfiguration/allowfailover
