# 配置样本

ScribeConfig 读取鼠须管配置的测试样本。

- `rime-ice/squirrel.yaml`：雾凇拼音 2026.06.30 的 `squirrel.yaml`，原样保留，开头加了来源注释。部署测试把它当作用户目录里的副本。
- `max-sample/squirrel.custom.yaml`：Max 风格的补丁，追加 wechat_light、wechat_dark 两套皮肤，设置亮暗配色和 iTerm2 的 `ascii_mode`。数值和 `Packages/ScribeConfig/Tests/ScribeConfigTests/Support/MaxSample.swift` 一致。
- `max-sample/scribe.custom.yaml`：同样的两套皮肤写成中书自己的格式（一个 `themes/wechat`，带亮色和暗色两套配色），部署后得到的亮暗主题应与上面的鼠须管格式完全一致。
- `every-key/`：`squirrel.custom.yaml` 把中书从 squirrel.yaml 读的每个键都设成非默认值（叠在 SharedSupport/squirrel.yaml 上，加一个设了全部 16 种颜色、Display P3 和每个方案级键的预设），`every_key.schema.yaml` 的 style 再把每个方案级键设一遍。快照见 `snapshots/every-key-*.txt`。
- `snapshots/`：主题和设置的快照，由测试里的 `snapshot` 生成。改了读取规则以后用 `SCRIBE_RECORD_SNAPSHOTS=1 swift test --package-path Packages/ScribeConfig` 重新生成，再检查差异。
