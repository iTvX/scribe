# 随包第三方许可

中书项目本身使用 GPL-3.0-or-later，完整文本在仓库根目录 `LICENSE`，安装包中另附 `Scribe-LICENSE.txt`。

本目录保存 0.1.5 随包组件及默认数据的上游许可和相关说明；原文保留，来源、固定版本或提交和文件摘要见 `manifest.json`。`SHA256SUMS` 在打包检查中校验，升级依赖时应同时更新相应声明。安装后副本位于 `Scribe.app/Contents/Resources/ThirdPartyNotices`。

- librime 1.17.0（33e7814），以及其固定的 glog、LevelDB、yaml-cpp、marisa-trie、OpenCC 和 Boost 依赖。
- 随二进制 `librime-version-info.txt` 指定的 librime-lua、librime-octagram、librime-predict；Lua 5.4.8 的声明取自该版本的 `lua.h`。
- OpenCC 内带的 marisa-trie、依赖发行包中的 darts-clone。
- Sparkle 2.10.0，包含其 LICENSE 列出的附属组件声明。
- plum 的固定提交，以及 `Scripts/fetch-librime.sh` 固定的 prelude、essay、luna-pinyin、stroke、terra-pinyin、bopomofo、cangjie、quick 和 octagram 数据。相应 README 一并保留，以保留数据来源和使用说明。

本清单针对中书自带内容。用户另行安装的方案、插件、字体和数据以各自来源的许可为准。
