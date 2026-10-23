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
- 用 `pkgbuild` 打组件包（不可重定位，`preinstall` 先退出旧实例），`productbuild` 加 `Distribution.xml` 打成产品包，`productsign` 用 Developer ID Installer 签名。
- `notarytool` 用现有的钥匙串 profile 提交公证，通过后 `stapler staple`。
- `Scripts/check-release.sh` 不安装就能验证：安装包签名、公证票据、Gatekeeper 评估，以及包里 app 的签名、Team ID、hardened runtime、entitlements、架构，并实际启动一次确认 librime 能加载。
- 签名设置从环境变量读取（`KEYCHAIN_DB`、`KEYCHAIN_PASSWORD_FILE`、`NOTARY_PROFILE`、`NOTARY_KEYCHAIN`），和 mac-switch 的发布脚本一致。密码只在运行时从文件读取，不打印、不写日志。

### 发布流程

- `.github/workflows/release.yml` 跑在 Max 的 Mac 上的自托管 runner（label `scribe-release`），只由推送到 main 和手动触发，绝不由 pull request 触发，同一时间只跑一个。
- M0 阶段的产物是签名、公证、staple 过的 `.pkg`，作为 workflow artifact 上传。发 GitHub Release 和 Sparkle 更新留到 M4，到时只在 `validate_only` 为假时运行。
- 普通 CI（`ci.yml`）在 GitHub 托管机器上用 `build-release.sh --unsigned` 检查打包流程，不需要任何凭据。
