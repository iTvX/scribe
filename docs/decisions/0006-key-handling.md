# 0006 按键处理与鼠须管一致

日期：2026-10-23

macOS 的按键事件如何变成 Rime 的按键，按鼠须管的行为实现（代码自己写，在 `ScribeCore/MacKeyTranslator.swift`），每条规则都有单元测试或回放测试。

## 普通按键

- 带 Command 的组合键一律交给应用，不送给 Rime。
- 回车、方向键、功能键、小键盘、JIS/ISO 特有键等按位置识别。
- 其他键按打出的 ASCII 字符识别，跟随键盘布局：只按着 Shift 或开着 Caps Lock 时，符号取实际打出的字符（Shift+1 是 `!`）；按着其他修饰键时取不带修饰键的基础字符。Shift 和 Caps Lock 只有一个生效时，小写字母转成大写。Control+[、\、]、- 产生的控制字符换回对应的键。
- 打出非 ASCII 字符的布局（法语、俄语等）退回到 ANSI 键盘上同一位置的字符。

## 修饰键

- Shift、Control、Option、Command 的按下和松开都送给 Rime（单按 Shift 切换中英由 Rime 的 ascii_composer 决定），同时总是交给应用，保持应用里的修饰键状态正确；修饰键状态没有变化的事件直接吃掉。
- 一个事件里同时有松开和按下时，先送松开。按下带新的修饰键状态；松开带松开后的状态加 Release。
- Caps Lock 变化最先送，带切换之前的锁定状态，这是 Rime 期望的。
- 远程桌面工具发来的修饰键事件可能没有键码，按状态的变化推断是哪个键（Caps Lock、Shift、Control、Option、Command 依次）。
- 激活时没有修饰键事件，Caps Lock 的状态从系统（`CGEventSource` 的会话状态）读取，否则下一次切换会被当成没有变化而丢掉。

## vim_mode

会话开启 `vim_mode` 选项时，Rime 没有处理的 Esc、Control+C、Control+[ 会把会话切到 ASCII，就像 Vim 回到普通模式。这个选项由 `app_options` 按应用打开（接配置时实现）。
