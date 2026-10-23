# 中书 · Scribe

为 macOS 从零打造的 Rime 输入法前端。

- **引擎**：[librime](https://github.com/rime/librime)，原样使用，不做改动
- **前端**：全新 Swift 实现，取代鼠须管（Squirrel）；鼠须管的代码仅作参考
- **系统要求**：macOS 14 及以上
- **Bundle ID**：`io.github.itvx.inputmethod.Scribe`

## 目标

- **从鼠须管无损迁移**：导入鼠须管的用户目录（`~/Library/Rime`）后即可完整沿用全部配置，包括输入方案（如雾凇拼音）、词库与用户词典，以及 `squirrel.yaml` / `squirrel.custom.yaml` 中的皮肤与外观设置
- **独立用户目录**：使用 `~/Library/Scribe`，与鼠须管互不干扰
- **前端配置**：完全兼容鼠须管的配置格式，同时提供 Scribe 自己的新格式，并引导用户迁移
- **设置界面**：提供图形化设置界面，常用配置无需手改 YAML

## 状态

早期开发阶段（M0 骨架）：能装进系统、被识别为输入法，但还不会打字。

## 开发

开发需要 Xcode 27（和 CI 一致）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。构建出来的中书支持 macOS 14 及以上。

### 仓库结构

| 目录 | 内容 |
| --- | --- |
| `project.yml` | XcodeGen 工程描述，`Scribe.xcodeproj` 由它生成，不进仓库 |
| `App/` | Scribe.app：输入法进程和 InputMethodKit 适配层 |
| `Packages/` | 四个本地 Swift 包：`RimeKit`、`ScribeConfig`、`ScribeCore`、`ScribeUI` |
| `SharedSupport/` | 随包附带的共享数据 |
| `Frameworks/` | 脚本下载的 librime 和插件，不进仓库 |
| `Scripts/` | 下载 librime、安装到本机、打发布包和验证的脚本；`Scripts/pkg/` 是安装包的配置和安装脚本 |
| `Tests/Fixtures/` | 测试样本 |
| `docs/` | 设计决定记录和各类清单 |

### 下载 librime

```bash
Scripts/fetch-librime.sh
```

下载 librime 1.17.0 官方发布包和默认数据（plum 默认安装的那几套：prelude、essay、朙月拼音、地球拼音、注音、倉頡五代、速成、筆畫，和鼠须管自带的一致，都固定到具体提交），校验 sha256，生成 `Frameworks/librime.xcframework`；插件放在 `Frameworks/rime-plugins`，OpenCC 数据放在 `Frameworks/opencc`，默认数据放在 `Frameworks/rime-data`。构建时插件嵌入 `Scribe.app/Contents/Frameworks/rime-plugins`，OpenCC 和默认数据嵌入 `Contents/SharedSupport`。重复运行不会重新下载，下载的压缩包缓存在 `build/downloads`。

### 运行测试

```bash
swift test --package-path Packages/RimeKit
```

其他包同理，换成 `Packages/ScribeConfig`、`Packages/ScribeCore`、`Packages/ScribeUI`。测试依赖上一步下载的 librime。

### 生成工程并构建

```bash
xcodegen generate
```

```bash
xcodebuild -project Scribe.xcodeproj -scheme Scribe -configuration Release -derivedDataPath build/DerivedData build
```

也可以生成后用 Xcode 打开 `Scribe.xcodeproj`。改了 `project.yml` 或增删文件后要重新运行 `xcodegen generate`。本地构建用 ad-hoc 签名，不需要开发者证书。

### 装到本机测试

```bash
Scripts/install-local.sh
```

脚本会下载 librime（如果还没有）、生成工程、构建 Release 版，退出正在运行的旧版本，装到 `~/Library/Input Methods/Scribe.app`，再用 `Scribe --install` 注册输入源。要装 Debug 版就在前面加 `CONFIGURATION=Debug`。

注册之后输入源不会自动启用。到「系统设置 → 键盘 → 输入法」点「+」，在「简体中文」或「繁体中文」下添加「中书」。

### 本机检查

```bash
Scripts/check-install.sh
```

构建并装到本机，然后在不切换当前输入法的前提下逐项检查：两个输入模式已注册、中书已启用、进程能启动、日志里有 librime 版本并开始监听、完整重新部署成功且 librime 没有记录错误。`xcrun swift Scripts/tis-status.swift` 可以单独查看输入源状态。

### 雾凇拼音

```bash
Scripts/install-rime-ice.sh
```

把固定版本的[雾凇拼音](https://github.com/iDvel/rime-ice)（校验 sha256）放进 `~/Library/Scribe`，然后让正在运行的中书重新部署。只增加或覆盖雾凇拼音自己的文件，不碰鼠须管的 `~/Library/Rime`。

不切换输入法也能检查打字效果：`--replay` 用 app 自带的 librime 和插件，在 `~/Library/Scribe` 的临时副本上回放按键（副本里不带用户词库，正在运行的输入法占用着它们）：

```bash
"$HOME/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe" --replay Tests/Fixtures/gate/rime-ice.replay
```

### 查看日志

librime 的日志在 `~/Library/Logs/Scribe`。中书自己用系统的统一日志，子系统是 `io.github.itvx.inputmethod.Scribe`。可以在「控制台」里按子系统过滤，也可以在终端里看：

```bash
log show --last 10m --info --predicate 'subsystem == "io.github.itvx.inputmethod.Scribe"'
```

### 打发布包

```bash
Scripts/build-release.sh --unsigned
```

不需要证书，生成 `build/release/Scribe-<版本>-<构建号>.pkg`：app 用 ad-hoc 签名，安装包不签名，只用来检查打包流程。用 `Scripts/check-release.sh --unsigned <pkg>` 验证。

正式的发布包（Developer ID 签名、公证、staple）由 `.github/workflows/release.yml` 在自托管 runner 上生成：推送到 main 时自动运行，也可以在 Actions 页面手动运行（`validate_only` 只验证不发布）。生成的 `.pkg` 作为 workflow artifact 下载。签名和公证的设置见 `Scripts/build-release.sh` 开头的说明和 `docs/decisions/0002-release-signing-and-packaging.md`。

安装 `.pkg` 会装到 `/Library/Input Methods`。装之前先删掉 `~/Library/Input Methods/Scribe.app`，免得同一个输入法装了两份。

### 命令行参数

`Scribe.app/Contents/MacOS/Scribe` 支持：

- `--install`：注册输入源（不启用、不切换）
- `--quit`：退出所有正在运行的中书进程
- `--reload`：让正在运行的中书重新部署
- `--sync`：让正在运行的中书同步用户数据
- `--self-test`：检查 librime 和插件能否从这个 app 加载
- `--replay 文件`：在 `~/Library/Scribe` 的临时副本上回放按键
- `--help`：显示帮助

详见 `docs/decisions/0005-server-commands.md`。

## 许可

[GPL-3.0-or-later](LICENSE)
