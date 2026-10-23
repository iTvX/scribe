# 发布中书

发布由 `.github/workflows/release.yml` 完成：推送 `v*` 标签就发布，手动运行只验证。为什么这样设计见 [`decisions/0011-releases-and-updates.md`](decisions/0011-releases-and-updates.md)。

> 现状：更新签名密钥还没有生成（要等 Max 同意），`release.yml` 里的 `SPARKLE_PUBLIC_KEY` 是空的，所以现在只能验证，推送标签会在第一步失败。生成密钥的步骤见最后一节。

## 发一个正式版

1. **改版本号**：开一个 PR，把 `project.yml` 里的 `MARKETING_VERSION` 改成新版本号，比如 `0.2.0`。
2. **写更新记录**：同一个 PR 里，在 `CHANGELOG.md` 最上面加一节 `## 0.2.0`，写给用户看（中文、Markdown）。这一节原样成为 GitHub Release 的说明，也是 Sparkle 更新窗口里显示的内容。
3. **合并**，等 main 的 CI 通过。
4. **手动检查**：先跑一次验证（见下一节），下载产物里的 `.pkg` 装到 `/Library/Input Methods`，按 [`manual-checklist.md`](manual-checklist.md) 过一遍。
5. **打标签并推送**（标签必须指向 main 上的提交）：

   ```bash
   git fetch origin main
   git tag -a v0.2.0 -m "中书 0.2.0" origin/main
   git push origin v0.2.0
   ```

6. **看运行**：

   ```bash
   gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
   ```

   `build` 在自托管 runner 上测试、构建、签名、公证、检查安装包，用钥匙串里的私钥签 `.pkg` 和 appcast；`publish` 在 GitHub 托管的机器上创建 Release、更新 `appcast` 发布里的 `appcast.xml`，并等到公开地址返回新文件为止（最多 5 分钟）。

7. **检查结果**：

   ```bash
   gh release view v0.2.0
   ```

   ```bash
   curl -sL https://github.com/iTvX/scribe/releases/download/appcast/appcast.xml | head -30
   ```

   Release 里有 `Scribe-0.2.0.pkg`，说明是 CHANGELOG 那一节加安装包的 SHA-256；appcast 第一项是 0.2.0，之前的版本都还在。已安装旧版的中书在一天之内会收到通知，也可以在输入法菜单里选「检查更新…」马上看到。

第一步就会挡住的情况：标签格式不对（只接受 `vX.Y.Z` 和 `vX.Y.Z-alpha.N` / `-beta.N` / `-rc.N`）、版本号和 `MARKETING_VERSION` 不一致、标签不在 main 上、CHANGELOG 没有这一节、`SPARKLE_PUBLIC_KEY` 为空。

### 出错了

- `publish` 失败（比如 GitHub 暂时出错）：在 Actions 页面对这次运行选 Re-run failed jobs。已经建好的 Release 会被覆盖上传（`--clobber`），appcast 同样。
- `build` 失败：什么都还没发布。修好后合并到 main，删掉远端和本地的标签（`git push --delete origin v0.2.0`、`git tag -d v0.2.0`），在新的 main 上重新打标签推送。已经发布的标签不要删，出了问题就发下一个版本号。

## 只验证，不发布

```bash
gh workflow run release.yml --ref main
```

`validate_only` 默认为真：完整地构建、签名、公证、检查，用 `Scripts/make-appcast.sh` 生成 appcast（扩展当前公开的 appcast，第一次发布前公开地址是 404，就新建），但不创建 Release、不上传 appcast。产物 `Scribe-<版本>-<构建号>-validation` 保留 7 天，里面有 `Scribe-<版本>.pkg`、`appcast.xml` 和 `release-notes.md`。

在真实密钥生成之前，验证运行每次用一把临时密钥：app 和 appcast 都只信任这把用完即删的密钥。所以验证产物可以拿来做手动检查，但不要装着日常用，它永远收不到真正的更新。

本地也能走一遍同样的流程（不需要证书）：

```bash
Scripts/release-tool.sh key new > /tmp/scribe-key && chmod 600 /tmp/scribe-key
```

```bash
SPARKLE_FEED_URL=https://github.com/iTvX/scribe/releases/download/appcast/appcast.xml SPARKLE_PUBLIC_KEY="$(Scripts/release-tool.sh key public < /tmp/scribe-key)" Scripts/build-release.sh --unsigned
```

```bash
APPCAST_EXISTING=Tests/Fixtures/appcast/published.xml SPARKLE_KEY_FILE=/tmp/scribe-key Scripts/make-appcast.sh build/release/Scribe-*.pkg build/release/publish
```

## 测试版

1. `MARKETING_VERSION` 写成带后缀的版本号，比如 `0.3.0-beta.1`，`CHANGELOG.md` 加 `## 0.3.0-beta.1` 一节。
2. 打标签 `v0.3.0-beta.1` 推送。

测试版发成 GitHub 预发布，appcast 里这一项带 `<sparkle:channel>beta</sparkle:channel>`，只有选择接收测试版的用户会收到：

```bash
defaults write io.github.itvx.inputmethod.Scribe BetaUpdates -bool YES
```

下次检查时生效。收到测试版的用户之后照样会收到正式版（构建号是时间戳，正式版总是更新）。

## 更新签名密钥

已安装的中书只接受用这把密钥签名的 appcast 和安装包。私钥只存在发布用的 Mac 上（发布用的钥匙串，和 Developer ID 证书在一起），但**必须另外备份**：丢了它，已安装的中书就再也收不到更新，只能让用户手动重装新版。

### 生成（需要 Max 同意后才做）

发布用的钥匙串只能在 Max 的图形界面登录会话里解锁，所以这几步由 Max 在本机「终端」里运行（`KEYCHAIN_DB` 换成 runner 的 `.env` 里同名的路径）：

1. 生成私钥，存进发布用的钥匙串。`-T /usr/bin/security` 让 runner 读它时不弹授权框：

   ```bash
   security add-generic-password -s https://sparkle-project.org -a io.github.itvx.inputmethod.Scribe -l "中书 Scribe 更新签名密钥" -T /usr/bin/security -w "$(Scripts/release-tool.sh key new)" "$KEYCHAIN_DB"
   ```

2. 备份：把下面这条命令显示的私钥存进密码管理器，然后清屏：

   ```bash
   security find-generic-password -s https://sparkle-project.org -a io.github.itvx.inputmethod.Scribe -w "$KEYCHAIN_DB"
   ```

3. 算出公钥：

   ```bash
   security find-generic-password -s https://sparkle-project.org -a io.github.itvx.inputmethod.Scribe -w "$KEYCHAIN_DB" | Scripts/release-tool.sh key public
   ```

4. 开 PR 把公钥填进 `release.yml` 的 `SPARKLE_PUBLIC_KEY`。合并后跑一次验证：这次 `make-appcast.sh` 会从钥匙串读私钥，并确认它和 app 里的公钥对得上。

### 换密钥

不能直接换：已安装的中书只信任旧公钥。要换就得先用旧密钥发一个带新公钥的版本，等用户都更新到这一版之后，再改用新密钥签名。没有特别的理由（比如私钥泄露）就不要换。
