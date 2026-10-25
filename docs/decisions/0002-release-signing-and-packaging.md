# 0002 发布版的签名、打包和发布流程

日期：2026-10-23

## 决定

### 发布版保留 `disable-library-validation`

发布版的 `Scribe.app` 和本地构建用同一份 `App/Scribe.entitlements`，保留 `com.apple.security.cs.disable-library-validation`。

原因是兼容优先：鼠须管带着这一项，用户可以在 `rime.lua` 里加载自己编译的 Lua C 模块（`.so`）。这些模块不是用我们的 Team ID 签的，开启库验证就加载不了。中书要做到从鼠须管无损迁移，就得同样允许。

代价是 hardened runtime 少了库验证这一层保护：进程可以加载任何签名（包括 ad-hoc）的动态库。

### `.pkg` 只注册输入源

安装包装到 `/Library/Input Methods`，`postinstall` 以当前登录用户的身份运行 `Scribe --install`，只注册输入源，不启用、不选中。鼠须管的安装包会顺手启用并选中；中书把这一步留到 M3，和一键导入一起设计。

### 签名、打包和公证

- `Scripts/build-release.sh`：Xcode 构建时不签名，由脚本由内到外签名：先签 `Contents/Frameworks` 里的 dylib，再带 entitlements 签 app，全部用 Developer ID Application、hardened runtime 和安全时间戳。这样 Xcode 本地签名带的 `get-task-allow` 不会进入发布版。
- CI 和发布构建用 `io.github.itvx.scribe.Build` 及对应模式 ID；Xcode 会主动注册构建产物，不能只依靠 `.noindex` 和结束后的清理隔离日常安装。发布脚本只在 `.noindex` 暂存副本中恢复正式 ID，然后签名；验证安装包时也展开到 `.noindex`。普通本地安装仍使用正式 ID。
- 用 `pkgbuild` 打组件包（不可重定位，`preinstall` 先退出旧实例），`productbuild` 加 `Distribution.xml` 打成产品包，`productsign` 用 Developer ID Installer 签名。
- `notarytool` 用现有的钥匙串 profile 提交公证，通过后 `stapler staple`。
- `Scripts/check-release.sh` 不安装就能验证：安装包签名、公证票据、Gatekeeper 评估，以及包里 app 的签名、Team ID、hardened runtime、entitlements、架构，并实际启动一次确认 librime 能加载。
- 签名设置从环境变量读取（`KEYCHAIN_DB`、`KEYCHAIN_PASSWORD_FILE`、`NOTARY_PROFILE`、`NOTARY_KEYCHAIN`），和 mac-switch 的发布脚本一致。密码只在运行时从文件读取，不打印、不写日志。
- Developer ID Installer 证书由 Developer ID G2 中间证书签发，系统根证书里没有它，签名用的钥匙串又不在搜索列表上，所以发布用的 Mac 要把 Apple 的 `DeveloperIDG2CA.cer`（公开证书）导入登录钥匙串，否则 `productsign` 找不到可用的身份。不改搜索列表，免得同时发版的几个 runner 互相影响。

### 发布流程

- `.github/workflows/release.yml` 跑在 Max 的 Mac 上的自托管 runner（label `scribe-local`，和 Max 其他仓库的 runner 一样的做法），只由推送到 main 和手动触发，绝不由 pull request 触发，同一时间只跑一个。
- M0 阶段的产物是签名、公证、staple 过的 `.pkg`，作为 workflow artifact 上传。发 GitHub Release 和 Sparkle 更新留到 M4，到时只在 `validate_only` 为假时运行。
- 普通 CI（`ci.yml`）在 GitHub 托管机器上用 `build-release.sh --unsigned` 检查打包流程，不需要任何凭据。
- 触发方式和发布步骤已由 [0011](0011-releases-and-updates.md) 取代：推送 `v*` 标签才发布，手动运行只验证，推送到 main 不再触发。

## 签名前预编译共享数据

自带方案在发布构建时预编译，生成的 `SharedSupport/build` 和 app 一起签名。安装器只注册输入源，不再改写 app。以后部署这些方案时仍可使用预编译结果。

- `build-release.sh` 把共享数据复制到 bundle 外运行 `Scribe --build`，失败就停止构建；只把 `build/` 放回 app，再签名、公证和打包。
- `installation.yaml` 和 `user.yaml` 属于构建过程的临时状态，不随安装包分发。用户自己的安装标识和配置继续在用户数据目录生成。
- `check-release.sh` 检查安装包已经包含预编译文件、没有构建机器的安装状态，并在独立副本中验证 `--build`。验证结束再次检查 app 签名。
- 0.1.3 及以前模仿鼠须管，在 postinstall 以 root 运行预编译。这会向已签名 app 新增文件，实机 `codesign --verify --deep --strict` 因资源封印不符失败，因此撤销这一做法。签名失败与升级后菜单缺项的因果关系仍需实机验证，不能仅凭注册成功断言菜单已恢复。
- `RIME_NO_PREBUILD` 不再影响安装；发布包始终携带预编译结果。
