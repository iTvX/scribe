# 中书 · Scribe

中书是 macOS 上的 [Rime](https://rime.im) 输入法前端：引擎是原样使用的 [librime](https://github.com/rime/librime)，前端用 Swift 重新实现，可以替代鼠须管（Squirrel）。按键、行内显示、`app_options`、皮肤等行为都和鼠须管一致，鼠须管的 `squirrel.yaml` / `squirrel.custom.yaml` 照常生效。中书用自己的用户目录 `~/Library/Scribe`，和鼠须管可以同时装着，互不影响。

- **当前版本**：0.2.0，改动见 [更新记录](CHANGELOG.md)
- **系统要求**：macOS 14 及以上

## 安装

1. 从 [GitHub Releases](https://github.com/iTvX/scribe/releases/latest) 下载 `Scribe-<版本>.pkg`，双击安装（需要管理员密码）。中书装在 `/Library/Input Methods/Scribe.app`。
2. 打开「系统设置 → 键盘 → 输入法」，点「编辑…」再点「+」，在「简体中文」下添加「中书」（繁体是「中書」）。
3. 在菜单栏的输入法菜单里切到中书。

装过自己构建的开发版（`~/Library/Input Methods/Scribe.app`）的话，先把它移到废纸篓再装安装包，免得同一个输入法装了两份。

## 从鼠须管迁移

在输入法菜单里选「设置…」打开中书设置，「导入配置」页的「开始导入」会把 `~/Library/Rime` 复制到 `~/Library/Scribe`，用户词也一起合并过来，鼠须管的文件一个都不改。中书设置随中书一起安装（0.1.1 起才有；还在用 0.1.0 的话，先在输入法菜单里选「检查更新…」）。步骤、哪些文件不复制、怎么切回鼠须管，见 [从鼠须管迁移](docs/migrating-from-squirrel.md)。

## 使用

- **输入法菜单**：重新部署（Control-Option-`）、同步用户数据、设置、日志目录、用户目录、使用说明、检查更新。
- **中书设置**：在输入法菜单里选「设置…」，可以导入鼠须管的配置，选方案、改快捷键和外观，把鼠须管格式的设置转成中书的格式。外观页提供真实候选窗预览；「自定义外观」会复制主题，保留原配色，再调整字号、排列和间距。
- **配置**：鼠须管格式的 `squirrel.custom.yaml` 和中书自己的 `scribe.custom.yaml` 都放在 `~/Library/Scribe`，改完选「重新部署」。中书的格式（`#RRGGBB` 颜色、一个主题同时带浅色和深色配色）见 [配置](docs/configuration.md)。
- **菜单栏图标**：切到中书时显示当前的中西文状态，`scribe.custom.yaml` 里设 `status_icon: false` 可以关掉。
- **日志**：librime 的日志在 `~/Library/Logs/Scribe`；中书自己的日志在「控制台」里按子系统 `io.github.itvx.inputmethod.Scribe` 过滤。

## 更新

中书用 [Sparkle](https://sparkle-project.org) 自动更新：每天检查一次，有新版本时只发一条通知，不会在打字时弹窗。也可以在输入法菜单里选「检查更新…」马上检查。安装更新需要管理员密码。

## 卸载

1. 「系统设置 → 键盘 → 输入法」里选中「中书」，点「−」移除。
2. 在终端退出中书：

   ```bash
   "/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe" --quit
   ```

3. 在访达里把 `/Library/Input Methods/Scribe.app` 移到废纸篓（需要管理员密码）。
4. 不再用的话，还可以删掉：
   - `~/Library/Scribe`：你的配置和用户词，想以后再用就留着；
   - `~/Library/Logs/Scribe`：日志；
   - 中书的偏好设置：`defaults delete io.github.itvx.inputmethod.Scribe`；
   - 安装记录：`sudo pkgutil --forget io.github.itvx.inputmethod.Scribe`。

卸载中书不影响鼠须管和 `~/Library/Rime`。

## 支持与反馈

当前以官网／GitHub 开源分发为主。已验证范围与限制见 [支持状态](docs/support-status.md)，安装、更新或配置异常的处理见 [故障恢复](docs/recovery.md)。反馈问题请使用 [Bug 模板](https://github.com/iTvX/scribe/issues/new/choose)，只提供最小配置和虚构输入，不要上传完整词库或未经检查的日志。

[隐私说明](PRIVACY.md) · [第三方许可](ThirdPartyNotices/README.md)

## 从源码构建

需要 Xcode 27 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）：

```bash
Scripts/install-local.sh
```

脚本会下载 librime 和 Sparkle、生成工程、构建并装到 `~/Library/Input Methods/Scribe.app`。仓库结构、测试、打包和发布见 [开发](docs/development.md)，所有文档的目录见 [docs](docs/README.md)。

## English

Scribe (中书) is a [Rime](https://rime.im) input method for macOS: [librime](https://github.com/rime/librime) as is, with a new Swift frontend that replaces Squirrel and behaves like it. Squirrel's `squirrel.yaml` and `squirrel.custom.yaml` keep working, and Scribe also has its own `scribe.yaml` format with `#RRGGBB` colours and themes that carry light and dark palettes. Scribe keeps its user data in `~/Library/Scribe` and can be installed next to Squirrel.

- **Status**: 0.1.5. macOS 14 or later.
- **Install**: download `Scribe-<version>.pkg` from [GitHub Releases](https://github.com/iTvX/scribe/releases/latest) and open it, then add 中书 under Simplified Chinese in System Settings → Keyboard → Input Sources.
- **Updates**: Sparkle checks once a day and posts a notification; the input menu also has Check for updates….
- **Uninstall**: remove 中书 from Input Sources, run `"/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe" --quit`, and move `/Library/Input Methods/Scribe.app` to the Trash. `~/Library/Scribe` holds your settings and learned words.
- **Build from source**: Xcode 27 and XcodeGen, then `Scripts/install-local.sh`. See [docs/development.md](docs/development.md).
- **Documentation** (in Chinese): [migrating from Squirrel](docs/migrating-from-squirrel.md), [configuration](docs/configuration.md), [all docs](docs/README.md).

## 许可

[GPL-3.0-or-later](LICENSE)
