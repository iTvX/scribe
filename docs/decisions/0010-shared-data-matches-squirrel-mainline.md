# 0010 共享数据对齐鼠须管 mainline

日期：2026-10-23

## 决定

- 随中书发布的共享数据，和鼠须管 mainline（2026-10-18，提交 a685441ad）的构建打包的一致，而不是和已发布的鼠须管 1.1.2 一致。兼容清单整体以 mainline 为基准，librime 也和 mainline 一样用 1.17.0。
- mainline 的构建用 plum（子模块固定在 b1be1969）装预置方案：prelude、essay、luna-pinyin、terra-pinyin、bopomofo、cangjie、stroke、quick，每个都取构建当时默认分支的最新提交；再按 `SQUIRREL_BUNDLED_RECIPES` 装 `lotem/rime-octagram-data`（默认分支，提供 `grammar.yaml`）和 `lotem/rime-octagram-data@hant`（提供 `zh-hant-t-essay-bgc.gram`、`zh-hant-t-essay-bgw.gram`）。`Scripts/fetch-librime.sh` 把这十个包都固定到 2026-10-18 时的提交，并按 plum 的规则挑文件（`*.yaml` 去掉 `*.custom.yaml`、`*.recipe.yaml`、`recipe.yaml`，加上 `*.txt`、`*.gram`）。
- 八个预置方案原先固定的提交，核对后正好就是 2026-10-18 时的提交，没有变化；新加的是八股文的三个文件。
- mainline 的配方只装 hant 分支的语言模型，不装 hans 分支（`zh-hans-*.gram`），所以中书也不带 hans 的模型。
- OpenCC 数据来自 librime 1.17.0 的 rime-deps 发布包，和 mainline 相同。

## 和鼠须管 1.1.2 的差别

核对已安装的鼠须管 1.1.2 的 SharedSupport 得到：

- 朙月拼音方案 0.31（1.1.2 是 0.30），地球拼音词典 2026.07.17（1.1.2 是 2021.08.05），倉頡五代 1.0（1.1.2 是 0.30），注音 3.1（1.1.2 是 3.0）。
- 中书带速成（quick5）和倉頡五代拆开的几个词典，1.1.2 没有；`default.yaml` 的方案列表也不同（1.1.2 的是旧版 prelude 的列表）。
- 1.1.2 也带 hant 的两个 `.gram`，但内容和 mainline 打包的不同（hant 分支 2026-07 更新过）；1.1.2 没有 `grammar.yaml`。
- 1.1.2 的 SharedSupport 里有预编译的 `build/`，由安装脚本运行 `Squirrel --build` 生成。中书也带预编译结果，但在发布签名前生成，避免安装时改写已签名 app（见决定 0002）。

## 验证

`Scripts/check-release.sh` 检查 `quick5.schema.yaml`、`grammar.yaml` 和两个 hant `.gram` 都在包里。
