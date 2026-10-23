# 0011 发布和自动更新

日期：2026-10-23

## 决定

### Sparkle 2.10.0

- 用 [Sparkle](https://sparkle-project.org) 做自动更新，和鼠须管一样。`Scripts/fetch-sparkle.sh` 下载官方发布的 `Sparkle-2.10.0.tar.xz`，校验 sha256，放进 `Frameworks/`；不用 Swift Package Manager，和 librime 的取法一致，版本和校验和都写在脚本里。
- 删掉框架里的 XPC 服务（`Downloader.xpc`、`Installer.xpc`）。只有设置了 `SUEnableDownloaderService` 或 `SUEnableInstallerLauncherService` 才会用到它们，而这两项只有沙盒应用需要；中书没有沙盒。少两个要签名、要公证的可执行文件。删掉后框架的签名失效，脚本用 ad-hoc 重签框架本身，`Autoupdate` 和 `Updater.app` 保留 Sparkle 自己的签名；发布版由 `build-release.sh` 用 Developer ID 由内到外全部重签（`Autoupdate`、`Updater.app`、框架，都带 hardened runtime，不带 entitlements）。
- `sign_update` 和 `generate_keys` 放在 `Frameworks/sparkle-bin`，只在发布时用，不进安装包。

### 更新包就是 `.pkg`

- appcast 里的下载项直接指向发布的 `.pkg`，`sparkle:installationType="package"`（Sparkle 叫 guided package）：Sparkle 下载、校验签名后请求管理员权限，以 root 运行安装器，再重新启动中书。安装包的 `preinstall`（退出旧实例）和 `postinstall`（注册输入源）照常运行。
- Sparkle 的 `generate_appcast` 不支持 `.pkg`，所以 appcast 由我们自己的 `Tools/scribe-release` 写（鼠须管也是自己写），再用 Sparkle 的 `sign_update` 签名。

### 签名的更新源

- `Info.plist` 里 `SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction` 都打开：appcast 本身必须带 EdDSA 签名，下载的安装包也必须先验签再处理。Sparkle 要求开 `SURequireSignedFeed` 时必须同时开 `SUVerifyUpdateBeforeExtraction`，否则更新器拒绝启动。
- appcast 的签名附在文件末尾（`<!-- sparkle-signatures: … -->`），覆盖它之前的全部字节。
- 发布时三重检查：签名前先确认私钥对应 app 里的 `SUPublicEDKey`；签名后用 Sparkle 的 `sign_update --verify` 验一遍；再用 `scribe-release verify` 按已安装的中书会做的方式独立验证（以 app 里的 `SUPublicEDKey` 为准）：appcast 签名、下载项唯一、版本号、渠道、安装方式、长度、安装包签名。

### 更新源的位置

- 和 mac-switch 一样，appcast 是一个固定发布（tag `appcast`）的附件：`https://github.com/iTvX/scribe/releases/download/appcast/appcast.xml`。这个地址写进发布版的 `SUFeedURL`，以后不能改，所以 `appcast` 发布和它的标签不能删。它标成预发布、不算「最新版本」，不影响仓库首页显示的版本。
- 每次发布从这个地址取回当前的 appcast，把新版本放在最前面，保留旧版本（同一个下载地址、或同渠道同构建号的旧条目被替换），重新签名后上传覆盖。第一次发布时地址返回 404，就新建。

### 触发方式

- 推送 `v*` 标签发布：GitHub Release（附 `.pkg`，说明来自 `CHANGELOG.md` 对应的一节，加上安装包的 SHA-256）和 appcast。标签必须是 `vX.Y.Z` 或 `vX.Y.Z-alpha.N` / `-beta.N` / `-rc.N`，版本号必须等于 `project.yml` 的 `MARKETING_VERSION`，标签指向的提交必须在 main 上，`CHANGELOG.md` 必须有这一节。
- 手动运行 `release.yml` 默认只验证（`validate_only`）：完整地签名、公证、验证，生成 appcast，但什么都不发布。只有关掉 `validate_only` 且 ref 是 `v*` 标签时才发布。推送到 main 不再触发发布流程。
- 签名和公证在自托管 runner 上做；发布（创建 Release、上传 appcast）在 GitHub 托管的机器上做，只有这一步拿到能写仓库的 token。自托管 runner 永远只有只读 token。

### 构建号

- `CFBundleVersion` 是构建时的 UTC 时间戳（如 `20261023120000`），也就是 appcast 里的 `sparkle:version`。Sparkle 用它比较新旧，时间戳天然单调递增。
- 写 appcast 时检查：新构建号必须全是数字，appcast 里留下的每一项都必须比它小。Sparkle 不会提供比已安装版本小的构建，这个检查防止发出一个永远不会被安装的版本。

### 测试版

- 带 `-alpha.N`、`-beta.N`、`-rc.N` 的标签发成 GitHub 预发布，appcast 里加 `<sparkle:channel>beta</sparkle:channel>`。
- 默认只收正式版。想收测试版：`defaults write io.github.itvx.inputmethod.Scribe BetaUpdates -bool YES`，下次检查时生效（`SPUUpdaterDelegate.allowedChannels(for:)` 每次检查都重新读）。

### 只有安装包装的那份会更新

- 只有发布版带 `SUFeedURL` 和 `SUPublicEDKey`（`build-release.sh` 在签名前写进 `Info.plist`，两个都有或都没有）。本地构建（`install-local.sh`、Xcode）不带，永远不检查更新。
- 就算带了，也只有直接位于 `/Library/Input Methods` 的那份（安装包装的位置）才启动更新器（`UpdateConfiguration`）。`~/Library/Input Methods` 里的本地测试版、构建目录里的 app 都不会检查，也不会被替换。
- 只有启动了更新器，输入法菜单才显示「检查更新…」。

### 打字时不弹窗

- 输入法绝不能在用户打字时抢焦点。用 Sparkle 的 gentle reminders：每天的定时检查发现新版本时，Sparkle 不自己显示窗口（`standardUserDriverShouldHandleShowingScheduledUpdate` 返回 false），中书发一条安静的系统通知（和部署提示一样用 provisional 授权，不弹授权对话框）。
- 用户点通知或选「检查更新…」时才打开 Sparkle 的窗口；这时临时切成普通应用并激活，更新会话结束后切回 accessory，和鼠须管一样。

### 不自动安装

- `SUEnableAutomaticChecks` 为真：每天自动检查，不先问用户（和鼠须管一样）。
- `SUAllowsAutomaticUpdates` 为假：安装包需要管理员权限，所以从不在后台或退出时静默安装，每次都由用户确认。

### 签名私钥

- 更新签名用 Ed25519 密钥。私钥以 generic password 的形式存在发布用的钥匙串（和 Developer ID 证书同一个钥匙串），service 是 `https://sparkle-project.org`，account 是 `io.github.itvx.inputmethod.Scribe`；`make-appcast.sh` 用 `security find-generic-password -w` 读出后只通过管道交给 `sign_update` 和 `scribe-release`，不存进变量、文件或日志。
- 私钥不离开发布用的 Mac，但必须另外备份（密码管理器）：丢了私钥，已安装的中书就再也收不到更新，只能让用户手动重装。
- 真正的密钥要等 Max 同意后才生成。在那之前 `release.yml` 里的 `SPARKLE_PUBLIC_KEY` 是空的，发布会直接拒绝运行；验证运行用每次新生成、用完即删的临时密钥，app 和 appcast 都只信任这把临时密钥。步骤见 `docs/releasing.md`。

## 原因

- 和鼠须管、mac-switch 用同一套做法（Sparkle、`.pkg`、固定发布里的 appcast），维护的人只需要懂一套。
- appcast 签名之后，即使 GitHub 上的文件被替换，已安装的中书也不会接受；安装包本身另有签名和 Apple 公证。
- 发布由标签触发，版本号、更新记录和 main 分支都要对上，发错版本的机会更少；平时手动验证不会发布任何东西。

## 测试

- `Tools/scribe-release` 的测试覆盖标签格式、更新记录提取、密钥、签名块拆分（与 Sparkle 的 `SPUExtractAppcastContent` 一致）、appcast 生成与合并、降级检查，以及用临时密钥签名后的完整验证往返。
- `App/Tests/UpdateConfigurationTests.swift` 测更新器什么时候启用；`InputMenuTests` 测「检查更新…」只在启用时出现。
- CI 每次都用临时密钥打包，`check-release.sh --expect-feed` 检查 Sparkle 已嵌入、XPC 服务已删除、`Info.plist` 的更新设置，再用 `make-appcast.sh` 扩展 `Tests/Fixtures/appcast/published.xml`（一个签过名的两条目 appcast），走一遍 `sign_update` 签名和独立验证。
- 发布前按 `docs/manual-checklist.md` 的「更新」一节检查。
