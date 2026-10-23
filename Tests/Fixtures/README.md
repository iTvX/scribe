# 测试样本

- `rime/`：测试用的共享数据，一个最小拼音方案 `scribe_test`（固定词频、不学习），RimeKit 和 ScribeCore 的测试用它启动真实的 librime。
- `replays/`：回放文件，一行一个按键加期望结果，在假引擎和真实 librime 上都跑，格式见其中的 README。
