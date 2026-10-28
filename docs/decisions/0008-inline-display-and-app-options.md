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

## 什么时候读配置

- 每次开始维护（启动、重新部署、`--reload`）时，先部署 squirrel.yaml 和 scribe.yaml，紧接着读设置（scribe.yaml 里设了的键覆盖 squirrel.yaml）：这两个文件在主线程上同步部署，读的时候已经是新的。
- 方案的 `style` 在部署结束后读，也在某个会话开始用一个方案时读；部署进行中不读，因为方案文件正在重写。0.1.6 起按方案缓存解析结果，在重新部署后失效，首键前就准备好配置。
- 每个会话取得自己方案的 `SessionConfiguration`：`chord_duration`、`show_notifications_when`、`status_message_type`、行内显示、`_linear`/`_vertical`、`app_options`、`unsafe/report_bundleid`、`keyboard_layout`。不能将最后一个切换方案的配置广播给其他会话。重新激活保留的会话时，按它在引擎中的实际方案恢复候选窗主题。
- 观察应用的 `effectiveAppearance`，深浅色改变时同步当前会话的行内显示和候选窗；下一次按键前也检查，覆盖观察回调尚未执行的情况。已有拼音重新呈现，不发送合成按键，不提交文字。

## 共享窗口的归属

0.1.6 起由 `RimeService` 记录当前激活的适配器。输入会话继续保留，但只有当前适配器能显示、隐藏或接收候选窗操作。较晚到达的旧控制器失焦可以向旧输入框上屏，不得隐藏新输入框的候选窗；失焦和关闭会撤销当前适配器的归属。

异步通知只路由给当前会话，并核对方案或选项是否仍是通知所说的状态，避免过期提示覆盖现在的状态。方案改变回调只修改配置：它可能发生在一次更新中间，不能递归刷新，否则会打乱上屏文字和新的标记文字的顺序。应用专属选项在激活时设置，当前模式标识在按键后同步更新。

`App/ServiceTests/SessionStateTests.swift` 用真实服务、适配器、输入会话和 librime 重现应用间、同应用输入框间的切换；录制客户端和候选窗用于精确核对文字、归属和可见状态。测试目录和词库均为临时副本。`ScribeCore` 另测首次配置、无按键重画和失效会话，真实应用仍按手动清单检查。
