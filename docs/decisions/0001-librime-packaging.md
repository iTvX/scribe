# 0001 librime 的打包方式

日期：2026-10-23

## 决定

- 使用 librime 官方发布包 1.17.0（`rime-33e7814-macOS-universal.tar.bz2` 和 `rime-deps-33e7814-macOS-universal.tar.bz2`），由 `Scripts/fetch-librime.sh` 下载，脚本里固定 sha256，不自己编译。
- 把 `librime.1.dylib` 原样包成 `Frameworks/librime.xcframework`（dylib 加头文件和 module map），而不是改造成 `.framework`。RimeKit 通过 SwiftPM 的 `binaryTarget` 引用它。
- 插件（`librime-lua`、`librime-octagram`、`librime-predict`）和 OpenCC 数据放在 `Frameworks/rime-plugins` 和 `Frameworks/opencc`，M1 起嵌入 app。
- 只有 RimeKit 可以 `import librime`，CI 会检查。

## 原因

- 插件都按 `@rpath/librime.1.dylib` 链接 librime，librime 又在自己所在目录旁边的 `rime-plugins` 里找插件。保留 dylib 原名和 install name，app 里的布局就和鼠须管一样：`Contents/Frameworks/librime.1.dylib` 加 `Contents/Frameworks/rime-plugins/`，插件不用改。
- Xcode 构建时会自动把这个 dylib 嵌入 `Contents/Frameworks` 并重新签名；`swift test` 也能直接链接和加载它。

## 签名

工程开启了 hardened runtime。本地构建用 ad-hoc 签名，ad-hoc 签名没有 Team ID，库验证会拒绝加载 `librime.1.dylib`，所以 `App/Scribe.entitlements` 里加了 `com.apple.security.cs.disable-library-validation`（鼠须管也有这一项）。发布版也保留这一项，见 [0002](0002-release-signing-and-packaging.md)。
