# iOS Ad Hoc 签名与安装

本流程使用 Apple Distribution 证书和 Ad Hoc 描述文件，导出只可安装在描述文件所列设备上的 IPA。需要付费 Apple Developer Program 账号、已注册的 App ID 和目标设备 UDID；这不是 TestFlight 或 App Store 发布。

1. 在 Apple Developer 账号中创建明确的 App ID，注册需要安装的 iPhone/iPad；创建 Apple Distribution 证书并从钥匙串导出含私钥的 `.p12`；创建包含该证书、App ID 和这些设备的 Ad Hoc `.mobileprovision` 描述文件。
2. 在仓库 Settings → Secrets and variables → Actions → New repository secret 添加以下 Secrets，避免将证书、私钥、密码或描述文件提交到仓库、聊天或公开日志：
   - `IOS_CERTIFICATE_P12_BASE64`：`.p12` 文件的单行 Base64 内容。
   - `IOS_CERTIFICATE_PASSWORD`：导出 `.p12` 时设置的密码。
   - `IOS_PROVISIONING_PROFILE_BASE64`：`.mobileprovision` 文件的单行 Base64 内容。

   在 Mac 本地可以使用 `base64 -i /path/to/file | tr -d '\n' | pbcopy` 复制 Base64 内容，然后直接粘贴到对应的 GitHub Secret。描述文件绑定的 Bundle ID 和 Team ID 会自动用于签名。
3. 签名工作流需先存在于仓库默认分支，然后在 Actions → **Sign iOS IPA for registered devices** → Run workflow 中选择要签名的可信分支并运行。手动运行使用该分支上的代码和工作流；不要在不可信的分支上使用签名 Secrets。
4. 从成功运行下载 `Safarier-iOS-AdHoc` artifact，用 Finder/Apple Configurator 或 Xcode 将 IPA 安装到已注册的设备。Artifact 保留 7 天；仓库有读取 Actions 产物权限的人可以下载，IPA 内的描述文件包含设备标识，请按仓库访问权限管理。

脚本使用临时钥匙串，验证描述文件类型、签名与导出包内的 Bundle ID 和描述文件 UUID，运行结束清理临时凭据。仍需在目标真机上验证功能与网络隔离。证书过期、撤销，设备不在描述文件、证书与描述文件不匹配、或者 App ID 已被占用时，需在 Apple 开发者账号中修正。

没有付费开发者账号但有 Mac 的情况下，可用 Xcode 的个人团队自动签名并直接连接设备运行；这种方式不能使用本 Ad Hoc 分发工作流，签名有效期和设备使用受 Apple 限制。
