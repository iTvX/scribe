# 中书 · Scribe

为 macOS 从零打造的 Rime 输入法前端。

- **引擎**：[librime](https://github.com/rime/librime)，原样使用，不做改动
- **前端**：全新 Swift 实现，取代鼠须管（Squirrel）；鼠须管的代码仅作参考
- **系统要求**：macOS 14 及以上
- **Bundle ID**：`com.maxyu.inputmethod.Scribe`

## 目标

- **从鼠须管无损迁移**：导入鼠须管的用户目录（`~/Library/Rime`）后即可完整沿用全部配置，包括输入方案（如雾凇拼音）、词库与用户词典，以及 `squirrel.yaml` / `squirrel.custom.yaml` 中的皮肤与外观设置
- **独立用户目录**：使用 `~/Library/Scribe`，与鼠须管互不干扰
- **前端配置**：完全兼容鼠须管的配置格式，同时提供 Scribe 自己的新格式，并引导用户迁移
- **设置界面**：提供图形化设置界面，常用配置无需手改 YAML

## 状态

早期规划阶段，架构与设计讨论中，尚无可用版本。

## 许可

[GPL-3.0-or-later](LICENSE)
