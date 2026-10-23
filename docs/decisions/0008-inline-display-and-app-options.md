# 0008 行内显示和 app_options

日期：2026-10-23

## 决定

- 行内显示由会话决定，不由候选窗决定。`InputSession` 按鼠须管的规则算：`inline_preedit = (主题的 inline_preedit && !no_inline) || inline`，`inline_candidate = 主题的 inline_candidate && !no_inline`。`inline`、`no_inline` 是会话的 Rime 选项，一般来自 `app_options`。
  - 行内显示输入码时，交给候选窗的快照里没有 preedit，候选窗只画候选。
  - 不在行内显示时，客户端里只放一个全角空格「　」，候选窗显示输入码；同时打开 Rime 的 `soft_cursor`，输入码里带「‸」标出光标。
  - 行内显示候选时，客户端显示 `commit_text_preview`。光标移到中间时，后面接上光标后还没转换的输入码，光标位置和鼠须管一样。
- `app_options` 里的每一项都直接设成会话的 Rime 选项（`ascii_mode`、`inline`、`no_inline`、`vim_mode`、`force_marked_text_for_direct_commit` 等），在新建会话时、以及客户端应用变了时设置，和鼠须管一样。开了 `unsafe/report_bundleid` 时，同时把 bundle ID 设成会话的 `client_app` 属性。
- 每次按键前，把候选窗的排列方式写进 `_linear`、`_vertical` 两个选项，方案可以按它调整按键。
- 开了 `force_marked_text_for_direct_commit` 时，没有标记文字就直接上屏的文字，先设成标记文字再上屏（Alacritty 需要这样）。

## 原因

- 鼠须管就是这么做的，`app_options` 表和用户的方案、Lua 脚本都按这个行为写。
- 候选窗只知道主题，不知道当前应用，靠主题判断会让 Terminal、iTerm2 这类 `no_inline` 的应用在行内主题下两边都不显示输入码。

## 测试

回放 `Tests/Fixtures/replays/inline-*.replay`、`app-option*.replay`、`layout-options.replay` 同时跑假引擎和真 librime，新增的 `@style`、`@app` 指令和 `panel-preedit` 断言见 `Replay.swift`。

## 插件的保留属性

和鼠须管一样（rime/squirrel#1124），插件可以通过 librime 的属性通知前端：`_comment_highlight`、`_comment_warning` 标出本页哪些候选的注释用强调色、警告色，值是逗号分隔的序号，或者带 `value` 字段的查询串；`_refresh_ui` 让候选窗重画。标记保存在会话里，重画时带上，下一次正常更新（比如按键）就清掉。标记通过 `CandidateSnapshot.accentCommentIndices`、`warningCommentIndices` 交给候选窗。
