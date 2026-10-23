# 回放文件

每个 `.replay` 文件是一段按键序列和期望结果，由 ScribeCore 的测试分别在假引擎和真实 librime（`Tests/Fixtures/rime` 里的最小拼音方案）上回放。格式见 `Packages/ScribeCore/Sources/ScribeCore/Replay.swift` 开头的说明。

修输入问题时，先把出错的按键序列写成回放文件，确认它失败，再改代码。
