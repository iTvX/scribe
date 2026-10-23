# 测试样本

- `rime/`：测试用的共享数据，一个最小拼音方案 `scribe_test`（固定词频、不学习），RimeKit 和 ScribeCore 的测试用它启动真实的 librime。
- `replays/`：回放文件，一行一个按键加期望结果，在假引擎和真实 librime 上都跑，格式见其中的 README。
- `gate/`：需要真实配置的检查，比如 `rime-ice.replay`，不在 CI 里跑，用 `Scribe --replay` 在本机回放。
- `rime-dir/`：合成的鼠须管用户目录（雾凇拼音式配置、Lua、OpenCC、其他前端的配置），供导入测试使用；git 存不了的 `build/`、`.git/`、用户词库等由测试在运行时补上。
- `snapshots/`：候选窗快照的基准图。`scribe/` 是中书自己画的，按测试分组；更新方法见仓库 README 的「运行测试」。
