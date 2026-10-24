# 开发

开发中书需要的工具、仓库结构、构建测试和发布打包。用户文档见 [README](../README.md)。

开发需要 Xcode 27（和 CI 一致）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。构建出来的中书支持 macOS 14 及以上。

## 仓库结构

| 目录 | 内容 |
| --- | --- |
| `project.yml` | XcodeGen 工程描述，`Scribe.xcodeproj` 由它生成，不进仓库 |
| `App/` | Scribe.app：输入法进程和 InputMethodKit 适配层 |
| `Settings/` | 中书设置（ScribeSettings.app）：导入鼠须管配置、方案、快捷键和外观设置 |
| `Packages/` | 四个本地 Swift 包：`RimeKit`、`ScribeConfig`、`ScribeCore`、`ScribeUI` |
| `SharedSupport/` | 随包附带的共享数据 |
| `Frameworks/` | 脚本下载的 librime、插件和 Sparkle，不进仓库 |
| `Scripts/` | 下载 librime、安装到本机、打发布包和验证的脚本；`Scripts/pkg/` 是安装包的配置和安装脚本 |
| `Tests/Fixtures/` | 测试样本 |
| `Tools/` | 开发工具：`squirrel-oracle` 画鼠须管的参考图，`scribe-release` 处理发布标签、更新记录和 Sparkle appcast |
| `CHANGELOG.md` | 写给用户的更新记录，每个版本一节，发布时成为 Release 说明和更新窗口里的内容 |
| `docs/` | 用户文档、设计决定记录和各类清单 |

## 下载 librime

```bash
Scripts/fetch-librime.sh
```

下载 librime 1.17.0 官方发布包和默认数据（plum 默认安装的那几套：prelude、essay、朙月拼音、地球拼音、注音、倉頡五代、速成、筆畫，加上八股文语法模型 `grammar.yaml` 和 `zh-hant-t-essay-*.gram`，和鼠须管 mainline 打包的一致，都固定到 2026-10-18 的提交），校验 sha256，生成 `Frameworks/librime.xcframework`；插件放在 `Frameworks/rime-plugins`，OpenCC 数据放在 `Frameworks/opencc`，默认数据放在 `Frameworks/rime-data`。`rime_deployer`、`rime_dict_manager` 和 plum 的 `rime-install` 放在 `Frameworks/bin`。构建时插件嵌入 `Scribe.app/Contents/Frameworks/rime-plugins`，OpenCC 和默认数据嵌入 `Contents/SharedSupport`，三个命令行工具和鼠须管一样放在 `Contents/MacOS`。重复运行不会重新下载，下载的压缩包缓存在 `build/downloads`。

## 下载 Sparkle

```bash
Scripts/fetch-sparkle.sh
```

下载自动更新用的 Sparkle 2.10.0 官方发布包，校验 sha256，删掉只有沙盒应用才用的 XPC 服务，放在 `Frameworks/Sparkle.framework`；发布时用的 `sign_update` 和 `generate_keys` 放在 `Frameworks/sparkle-bin`，不进 app。`build-release.sh` 和 `install-local.sh` 会自动运行它。

## 运行测试

```bash
swift test --package-path Packages/RimeKit
```

其他包同理，换成 `Packages/ScribeConfig`、`Packages/ScribeCore`、`Packages/ScribeUI`。测试依赖上一步下载的 librime。发布工具的测试是 `swift test --package-path Tools/scribe-release`。

ScribeUI 的测试里有候选窗快照：把面板画成图，和 `Tests/Fixtures/snapshots/scribe` 里的基准图逐像素对比，对不上的图写到 `build/snapshot-failures`。改了绘制、需要更新基准图时这样跑一遍（测试会故意失败），检查新图后再正常跑：

```bash
SCRIBE_RECORD_SNAPSHOTS=1 swift test --package-path Packages/ScribeUI
```

同样的用例也和鼠须管自己的代码画出的参考图比较（`Tests/Fixtures/snapshots/squirrel`）。参考图由 `Tools/squirrel-oracle/render.sh` 生成，改了用例或配置后在本机运行再提交，CI 只做比较。做法和容差见 `decisions/0007-candidate-panel-rendering.md`。

## 生成工程并构建

```bash
xcodegen generate
```

```bash
xcodebuild -project Scribe.xcodeproj -scheme Scribe -configuration Release -derivedDataPath build/DerivedData build
```

也可以生成后用 Xcode 打开 `Scribe.xcodeproj`。改了 `project.yml` 或增删文件后要重新运行 `xcodegen generate`。本地构建用 ad-hoc 签名，不需要开发者证书。

## 装到本机测试

```bash
Scripts/install-local.sh
```

脚本会下载 librime（如果还没有）、生成工程、构建 Release 版，退出正在运行的旧版本，装到 `~/Library/Input Methods/Scribe.app`，再用 `Scribe --install` 注册输入源。要装 Debug 版就在前面加 `CONFIGURATION=Debug`。

注册之后输入源不会自动启用。到「系统设置 → 键盘 → 输入法」点「+」，在「简体中文」或「繁体中文」下添加「中书」。

## 本机检查

```bash
Scripts/check-install.sh
```

构建并装到本机，然后在不切换当前输入法的前提下逐项检查：两个输入模式已注册、中书已启用、进程能启动、日志里有 librime 版本并开始监听、完整重新部署成功且 librime 没有记录错误。`xcrun swift Scripts/tis-status.swift` 可以单独查看输入源状态。

## 雾凇拼音

```bash
Scripts/install-rime-ice.sh
```

把固定版本的[雾凇拼音](https://github.com/iDvel/rime-ice)（校验 sha256）放进 `~/Library/Scribe`，然后让正在运行的中书重新部署。只增加或覆盖雾凇拼音自己的文件，不碰鼠须管的 `~/Library/Rime`。

不切换输入法也能检查打字效果：`--replay` 用 app 自带的 librime 和插件，在 `~/Library/Scribe` 的临时副本上回放按键（副本里不带用户词库，正在运行的输入法占用着它们）。回放文件里可以用 `@schema` 指定方案：

```bash
"$HOME/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe" --replay Tests/Fixtures/gate/double-pinyin-flypy.replay
```

`Tests/Fixtures/gate` 里的两个回放（全拼 `rime_ice` 和小鹤双拼 `double_pinyin_flypy`）由 `Scripts/check-gate.sh` 在临时目录里装上固定版本的雾凇拼音来跑，不读 `~/Library/Scribe`，CI 里也跑：

```bash
Scripts/check-gate.sh
```

## 输入法菜单

切换到中书后，菜单栏输入法菜单里有：重新部署（Control-Option-`）、同步用户数据、日志目录、用户目录、使用说明。用安装包装到 `/Library/Input Methods` 的发布版还有「检查更新」：中书每天自动检查一次，有新版本时只发一条通知，不在打字时弹窗，安装要管理员密码。界面跟随系统语言（英文、简体中文、繁体中文）。

如果中书在两秒内又被启动（多半是配置有错导致启动时崩溃），这次不加载 Rime，并语音提示；改好配置后选「重新部署」即可。

和鼠须管一样：

- 切换到中书时，菜单栏显示当前的中西文状态（方案的简短标签，没有就是「中」或「Ａ」）；在 `scribe.yaml` 里设 `status_icon: false`（或 `squirrel.yaml` 里设 `status_icon/show: false`）可以关掉。
- 部署开始、完成或出错时，用系统通知安静地提示一下（不弹授权对话框）。
- 注销、关机或中书退出前，先正常关闭 librime，保证用户词典写回磁盘。

## 查看日志

librime 的日志在 `~/Library/Logs/Scribe`。中书自己用系统的统一日志，子系统是 `io.github.itvx.inputmethod.Scribe`。可以在「控制台」里按子系统过滤，也可以在终端里看：

```bash
log show --last 10m --info --predicate 'subsystem == "io.github.itvx.inputmethod.Scribe"'
```

## 打发布包

```bash
Scripts/build-release.sh --unsigned
```

不需要证书，生成 `build/release/Scribe-<版本>-<构建号>.pkg`：app 用 ad-hoc 签名，安装包不签名，只用来检查打包流程。用 `Scripts/check-release.sh --unsigned <pkg>` 验证。

正式的发布包（Developer ID 签名、公证、staple）由 `.github/workflows/release.yml` 在自托管 runner 上生成：推送 `v*` 标签时发布 GitHub Release 和 Sparkle 更新源；手动运行（`gh workflow run release.yml`）只验证不发布，生成的 `.pkg` 和 appcast 作为 workflow artifact 下载。发版步骤见 [`releasing.md`](releasing.md)，签名和公证的设置见 `Scripts/build-release.sh` 开头的说明和 `decisions/0002-release-signing-and-packaging.md`，自动更新见 `decisions/0011-releases-and-updates.md`。

安装 `.pkg` 会装到 `/Library/Input Methods`。装之前先删掉 `~/Library/Input Methods/Scribe.app`，免得同一个输入法装了两份。

## 命令行参数

`Scribe.app/Contents/MacOS/Scribe` 支持：

- `--install`：注册输入源（不启用、不切换）
- `--quit`：退出所有正在运行的中书进程
- `--reload`：让正在运行的中书重新部署
- `--sync`：让正在运行的中书同步用户数据
- `--self-test`：检查 librime 和插件能否从这个 app 加载
- `--replay 文件`：在 `~/Library/Scribe` 的临时副本上回放按键
- `--help`：显示帮助

详见 [`decisions/0005-server-commands.md`](decisions/0005-server-commands.md)。
