# 0007 候选窗的排版、绘制和快照测试

日期：2026-10-23

## 决定

设计文档写的是「候选窗用 Core Text 自绘」。实际做法是：排版用 TextKit 2，和鼠须管一样；背景、边框、高亮和翻页箭头用 Core Graphics 在 `draw(_:)` 里画；文字由 TextKit 2 的布局片段（`NSTextLayoutFragment`）画出。鼠须管的代码只用来弄清它的行为，ScribeUI 里的实现是重写的。

- **文字**：`PanelText` 照鼠须管的方式拼出候选窗的文字：替换 `candidate_format` 里的占位符、NFC 规范化、`noBreak` 标记、横排时候选之间用两个空格、各段的段落样式、竖排列表时按标签宽度缩进折行。预编辑是否内嵌由会话按应用决定（鼠须管的 `inline_preedit` 加上 `no_inline`、`inline` 选项），内嵌时快照里没有预编辑；面板不看主题，快照里有预编辑就画。
- **排版**：`PanelTextLayout` 里有一个不显示的 `NSTextView`（TextKit 2），设置和鼠须管的一致：`lineFragmentPadding` 为 0，布局代理不在 `noBreak` 前断行，竖排时 `setLayoutOrientation(.vertical)`。行长取屏幕宽度的三分之一（竖排取高度的四分之一），字号越大越长。
- **形状**：鼠须管从 TextKit 的选区矩形算出背景、高亮和翻页箭头的路径。`PanelGeometry` 和 `PanelShapes` 用纯函数重写了这套计算，连同它的边界情况（比如 `hilited_corner_radius` 为 0 时扩展半径里的除零），不画图就能做单元测试。
- **绘制**：`PanelView.draw(_:)` 按鼠须管图层的顺序画：面板背景、预编辑背景、边框、预编辑高亮、候选背景、高亮候选和它的阴影，然后是翻页箭头和文字。鼠须管用 `CAShapeLayer` 加蒙版叠出来的效果，这里用奇偶填充和裁剪实现；`mutual_exclusive` 也是靠奇偶填充把背景挖空。阴影按实测的 Core Animation 行为换算：模糊取 `shadowRadius` 的两倍，偏移在翻转坐标里向右下。
- **竖排**：面板在自己的坐标系里横着画（x 沿着行），由窗口整体顺时针转 90 度。窗口和鼠须管一样把内容视图的 bounds 转 -90 度；实测 AppKit 在图层模式下把这个旋转做成内容视图图层的变换，面板视图自己的图层不转，所以屏幕上也是先横着画、再整体转。
- **尺寸和位置**：`PanelPlacement` 是纯函数，照搬鼠须管的 `show()`：自然尺寸、超大面板缩小到屏幕中央、放在光标下方（竖排放在左侧）、碰到屏幕边缘时翻转或推回、`memorize_size`。
- **毛玻璃背景**：`PanelBackground` 在 macOS 26 及以上用 `NSGlassEffectView`（clear），之前的系统用 `NSVisualEffectView`（hudWindow），由窗口按面板形状遮罩。
- **窗口**：`CandidatePanel` 和鼠须管的 `SquirrelPanel` 一样：不激活的 `NSPanel`，层级 `CGShieldingWindowLevel`，带窗口阴影，`alpha` 设在窗口上；超大面板窗口缩小、内容按自然尺寸画再缩放；`memorize_size` 的记忆在隐藏时清零。鼠标：按下和松开在同一个候选上才选中，悬停只在窗口里改高亮（不告诉 Rime），移出时恢复；点翻页箭头、滚轮和触控板翻页（阈值照搬）；点预编辑在光标前或后时光标往那边移一格。状态消息 1.2 秒后自动隐藏，新的候选或 `hide()` 会取消它。

## 原因

- **和鼠须管一致**：同一份 squirrel.yaml 皮肤要画出一样的候选窗。折行、行高、段落间距、基线这些细节都是 TextKit 2 的行为，换成 Core Text 自己排版很难逐像素对上；用同一个排版引擎最直接也最可靠。
- **离屏渲染要忠实**：`CALayer` 的离屏绘制（`render(in:)`、`cacheDisplay` 等）不支持蒙版，用鼠须管那套图层截出来的图和屏幕上不一样。全部在 `draw(_:)` 里画，快照和窗口里显示的是同一段代码画出来的。
- **竖排文字不能画在旋转过的上下文里**：实测 TextKit 2 在带旋转的绘图上下文里画竖排文字会被拉伸变形，直接截取旋转后的 `NSTextView` 也一样。屏幕上没有这个问题，因为图层是先不旋转地画好、合成时才转。所以竖排面板也是先不旋转地画，再整体转 90 度。

## 快照测试

首帧显示不能只靠 `NSWindow.displayIfNeeded()`：隐藏的图层视图会把实际绘制留到后续事件循环。0.1.3 起，在每段输入第一次显示候选窗时先调用 `PanelView.display()` 画好内容，再显示窗口并提交 Core Animation 事务；窗口关闭出入动画，启动时预先创建隐藏窗口。后续可见状态的更新仍交给 AppKit 合并。`CandidatePresentationTests` 直接观察 `draw(_:)`，不用会主动触发绘制的截图接口，确认横写、竖写和隐藏后再次显示都在 `show` 返回前画好首帧。

- `PanelRenderer.render(_:theme:appearance:screen:scale:)` 不开窗口，把面板画进位图：8 位 sRGB、预乘 alpha、2 倍、参考屏幕 1440×900。选 sRGB 是为了让皮肤颜色的十六进制值原样出现在像素里，方便检查；Display P3 里超出 sRGB 的颜色在快照里会被截断。毛玻璃背景和窗口阴影截不到，快照里这些地方是透明的。
- native 配色的系统颜色从 `SystemPalette` 取，测试里用固定值，快照不受本机强调色和高亮色影响。测试里的字体一律写明，只用系统自带的字体（Avenir、PingFang SC、Helvetica、Menlo），不用 `NSFont.userFont`。
- 基准图在 `Tests/Fixtures/snapshots/scribe/<组>/<名字>.png`。对比时任一通道（含 alpha）相差超过 4/255 的像素算不同，不同的像素超过 0.05% 就失败，尺寸不同也失败。`SnapshotHarnessTests` 证明了整体移动 1 点、标签字号小 1 点、高亮圆角加 1 点、颜色偏 9/255 都会失败。
- 设 `SCRIBE_RECORD_SNAPSHOTS=1` 运行测试会重写基准图，并让测试失败，提醒检查新图后去掉这个变量再跑一遍。没有基准图也算失败。
- 失败时期望图、实际图和差异图写到 `$SCRIBE_SNAPSHOT_ARTIFACTS`（默认 `build/snapshot-failures`），CI 失败时把这个目录作为 artifact 上传。新加的快照还没有基准图时，CI 渲染的图也在里面。
- 以 CI（GitHub 托管的 xcode-27 runner）为准：本机和 CI 的结果超出容差时，从 CI 上传的实际图里取基准图。

## 鼠须管对照

- `Tools/squirrel-oracle` 用鼠须管 46962d2 自己的 `SquirrelTheme`、`SquirrelView`、`SquirrelPanel`（构建时下载，不进仓库）画出同样的用例，参考图在 `Tests/Fixtures/snapshots/squirrel/`。用法见那里的 README。
- 用例都在 `Tests/Fixtures/snapshots/cases.json`，中书的快照和鼠须管的参考图共用：排版和功能的组合、`SharedSupport/squirrel.yaml` 的全部 21 个预设、Max 风格的部署样本（亮、暗，以及按应用不内嵌时带预编辑）。真实配置先经 librime 读出（样本用 librime 实际部署），扁平化存在 `configs/`，两边从同一份配置出发；`SnapshotConfigTests` 保证它和 YAML 一致，并和 ScribeConfig 记录的部署结果一致。
- `SquirrelReferenceTests` 在 CI 上比较中书的渲染和鼠须管的参考图。容差只覆盖抗锯齿：每个通道相差不超过 32/255，或者和对方相邻的像素一致；不同的像素不超过 0.2%，或者不超过 64 个（小面板的圆角）。`SnapshotHarnessTests` 证明这个容差仍然抓得住整体移动 1 点、标签字号小 1 点和明显的颜色错误；更小的偏差由中书自己的逐像素快照把关。
- 对照查出并修掉的问题：面板最外一圈像素被抗锯齿了三次（多了一次按视图边界的裁剪），比鼠须管淡；窗口把内容视图取整到像素，面板在取整变小时会被切掉不到一个像素的一边，渲染器现在也这样切，快照和屏幕上一致。
- 窗口位置也和鼠须管自己的 `SquirrelPanel` 对照：`Tests/Fixtures/snapshots/placements.json` 列出光标位置（中间、靠右、靠下、靠上、靠左）、横排和竖排、有无预编辑、有无翻页条、`memorize_size` 开关下内容变长变短再隐藏的序列，以及超大面板。对照工具在固定的 1440×900 屏幕上记下鼠须管要的窗口框、面板视图尺寸和旋转，`SquirrelPlacementTests` 让中书的候选窗走同样的步骤，差别不超过 0.001 点。
- wechat_light 的高亮在左边被面板的圆角裁掉（左上、左下是圆角，右边是直角），鼠须管和中书一样。

### 已知差异

- **竖排文字的亚像素位置**：TextKit 把鼠须管的行图层对齐到窗口的像素网格，而竖排面板在窗口里差几分之一点才对齐，所以鼠须管的竖排字形和面板背景之间有最多约三分之一点的偏移。中书的文字跟着面板画，没有这个偏移。差别只在字形边缘的抗锯齿上，竖排用例的容差放宽到 3% 的像素。屏幕上中书的竖排面板也有同样的窗口偏移，只是文字和背景一起偏。

## 发现

- TextKit 2 会抵消整行统一的 `baselineOffset`：行的基线跟着下移同样的距离，字形位置不变。用真正的 `NSTextView` 实测也是这样，所以单独调 `base_offset` 看不出变化，鼠须管也一样。中书照样保留这个行为。
- Core Graphics 的阴影偏移是在上下文的 base space 里算的，位图和 AppKit 图层的上下文不一样，同一段代码在窗口里画不出阴影。现在阴影先画进自己的位图（那里 base space 就是设备空间），再贴到面板上。
- 鼠须管的文字由 TextKit 2 画进自己的图层，开着字体平滑，比关掉平滑时稍粗。中书画文字时同样打开平滑：和用鼠须管源码离屏渲染的同一个面板相比，77000 个像素里只有 38 个相差超过 32/255；关掉平滑则有 2000 多个。`CandidatePanelTests` 还比较窗口里的面板图层和渲染器的结果，确保两条路径画出来一样。
- 阴影的换算、竖排的方向和 TextKit 2 的细节，第二阶段用鼠须管本身的渲染结果逐一核对。


## macOS 27.2 字体级联修复（0.1.5）

该环境中原本的竖排隐式字体级联出现错误中文字形，上游固定版本的 oracle 也复现。中书在 27.2 及之后为每个组合字符使用具体的回退字体，再让 TextKit 排版；保留文本和颜色，接受实际字体带来的列宽变化。更改限定在竖排，旧系统行为保留。

参考图和位置按系统分组，27.2 组另存。oracle 使用独立的字体输入规整，几何与绘制继续来自上游；没有调整任何比较容差。见 `Tests/Fixtures/snapshots/macos-27.2/README.md`。
