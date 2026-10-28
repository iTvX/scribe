# macOS 27.2 候选窗参考集

生成环境：macOS 27.2 (26B123)，Apple Silicon，Xcode 27.1；用例仍为上一级 `cases.json` 与 `placements.json`。

该系统的字体栅格化与旧基线有差异。隐式字体级联的竖排还出现了错误字形：Avenir + PingFang 的「中书」被画成其他字形。未修正的固定版本鼠须管代码也能复现。

生产修复仅在 macOS 27.2 及之后的竖排中生效：通过 CoreText 为组合字符找到实际字体，再用该字体的具体名称构造 NSFont，避免把隐式级联描述传给竖排排版。文字、颜色和组合字符边界不变；实际字体度量可能增加列宽。

- `scribe/`：修复后的中书，69 个严格快照。
- `squirrel/`：固定上游绘制代码，应用同样目的的独立字体输入规整后生成；窗口绘制、尺寸与位置算法仍来自上游。47 组位置用例。
- `VerticalFontTests` 独立检查中文字体、组合字符和文本／颜色保持。
- 原图像和位置容差未修改；旧系统继续使用上一级原有参考集。

复核包含竖排预编辑、翻页、长文本、横排、浅色／深色和不同字体预设。先检查文字正确，再比较独立参考图。禁止用扩大容差掩盖差异。

重建：在相应系统运行 `SCRIBE_RECORD_SNAPSHOTS=1 swift test --package-path Packages/ScribeUI --filter ScribeUITests.PanelSnapshotTests`（记录会故意失败），运行 `Tools/squirrel-oracle/render.sh`，检查图像，再不带记录开关运行完整 UI 测试。
