# 鼠须管兼容进度

对照设计文档「鼠须管兼容清单」里核心部分（前端、命令行、共享数据）的条目，逐条记录现状。基准是鼠须管 mainline（2026-10-18，提交 a685441ad）。

- **完成**：行为和鼠须管一致，有自动测试覆盖。
- **部分**：已实现，但测试或数据还没跟上，缺口写在「说明」里。
- **缺失**：还没做。
- **手动**：只能在真实应用里由人检查，见 [manual-checklist.md](manual-checklist.md) 里对应的行号。

测试名前面的位置：「回放」是 `Tests/Fixtures/replays/` 里的文件，同时跑假引擎和真 librime；Core、UI、Config、RimeKit 分别是 `Packages/ScribeCore`、`ScribeUI`、`ScribeConfig`、`RimeKit` 的测试；App 是 `App/Tests`；check-release、check-install 是 `Scripts/` 里的脚本。

## 全局设置

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| `config_version` 部署 | 完成 | RimeKit `deployingAConfigFileAppliesTheUserPatch`、`anOutdatedUserCopyIsReplaced`、`deployingAMissingConfigFileBuildsNothing`；App `FrontendConfigTests.aPatchTakesEffectAfterAReload`（squirrel.custom.yaml 和 scribe.custom.yaml 两种）；Config `LibrimeConfigTests.deployPatchesTheUserCopy` | 版本不比自带的新的用户副本移进 `trash/`，更新的留下。check-install 后 `build/squirrel.yaml`、`build/scribe.yaml` 都在 |
| `keyboard_layout`（last / default / 名称） | 完成 | Config `ScribeSettingsTests.keyboardLayout`；App `SessionConfigurationTests.takesTheSettingsAndTheTheme`、`InputAdapterTests.activationNamesTheKeyboardLayoutToUse` | 控制器把激活时得到的布局交给 `overrideKeyboard`，只有这一行没有测试 |
| `chord_duration` | 完成 | App `SessionConfigurationTests`、`InputAdapterTests.theChordDurationReachesTheSession`、`FrontendConfigTests`；回放 `chord-typing` | |
| `show_notifications_when` | 完成 | App `SessionConfigurationTests`、`InputAdapterTests.statusFollowsTheConfiguration`；回放 `status`（`@notifications`） | |
| `status_icon/show` | 完成 | Config `ScribeSettingsTests.statusIconAndBundleIDReport`；Core `InputSessionTests.theModeIndicatorUsesTheSchemasShortLabel`；App `InputAdapterTests.theModeIndicatorFollowsASCIIMode` | 菜单栏图标本身手动 M1–M4 |
| `unsafe/report_bundleid` | 完成 | Config `ScribeSettingsTests.statusIconAndBundleIDReport`；Core `InputSessionTests.theBundleIDIsReportedWhenAllowed`；RimeKit `propertiesRoundTrip` | |
| `app_options`（默认表每个应用一个行为测试） | 完成 | App `AppOptionsTableTests`（默认表 20 个应用各一个测试，读 SharedSupport/squirrel.yaml，逐项检查 `ascii_mode`、`no_inline`、`inline`、`vim_mode`、`force_marked_text_for_direct_commit`）；回放 `app-options`、`app-option-inline` | 表里多一个应用或一个选项而没有对应的检查，测试就会失败。手动 A1–A23 |

## 选项和属性

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| `ascii_mode` | 完成 | 回放 `shift-toggles-ascii`、`shift-with-a-key-keeps-the-mode`、`caps-lock`、`app-options`；App `InputAdapterTests.theModeIndicatorFollowsASCIIMode` | |
| `inline` | 完成 | 回放 `app-option-inline` | |
| `no_inline` | 完成 | 回放 `app-options`；App `InputAdapterTests.aNoInlineAppSeesTheInputInTheWindowEvenWithoutCandidates` | |
| `soft_cursor` | 完成 | 回放 `inline-preedit`、`inline-preedit-off`、`inline-candidate-without-preedit` | 真 librime 上输入码带「‸」 |
| `vim_mode` | 完成 | 回放 `vim-mode`、`vim-mode-off` | 手动 A10 |
| `_chord_typing` | 完成 | 回放 `chord-typing`；App `InputAdapterTests.chordReleasesReachTheLastClient` | 回放只跑假引擎：测试方案没有并击，前端的计时和释放都覆盖了 |
| `_linear` / `_vertical` | 完成 | 回放 `layout-options`；App `SessionConfigurationTests` | 和鼠须管一样每次按键前写入 |
| `force_marked_text_for_direct_commit` | 完成 | Core `InputSessionTests.forcedMarkedTextPrecedesADirectCommit`、`committingAfterMarkedTextNeedsNoForcing` | 手动 A6 |
| `client_app` | 完成 | Core `InputSessionTests.theBundleIDIsReportedWhenAllowed`、`appOptionsAreSetWhenTheSessionStarts`；RimeKit `propertiesRoundTrip` | |
| `_comment_highlight` / `_comment_warning` | 完成 | Core `ReservedPropertyTests`；回放 `reserved-properties`；UI `CandidatePanelTests.commentMarksFromTheSnapshotReachTheDrawing`、`PanelTextTests.accentAndWarningColourUnhighlightedComments` | |
| `_refresh_ui` | 完成 | 回放 `reserved-properties`；App `InputAdapterTests.aPluginsRefreshRedrawsTheWindow` | |

## 行为

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| 修饰键（同一事件里先放后按） | 完成 | Core `MacKeyTranslatorTests.releaseComesBeforePressInOneEvent`、`modifierPressCarriesTheNewState`、`modifierReleaseCarriesTheNewStateAndRelease`；App `InputAdapterTests.modifierChangesGoToRimeAndTheClient` | |
| Caps Lock（最先发送，激活时读硬件状态） | 完成 | Core `MacKeyTranslatorTests.capsLockGoesFirst`、`capsLockCarriesThePreviousLockState`；App `InputAdapterTests.capsLockStateIsSeededOnActivation`；回放 `caps-lock` | 读硬件状态的一行代码手动 B8 |
| Cmd 组合键直通 | 完成 | Core `MacKeyTranslatorTests.commandShortcutsAreNotTranslated`；App `InputAdapterTests.commandShortcutsNeverReachRime` | 手动 B9、V4、O2 |
| 远程桌面的修饰键 | 完成 | Core `MacKeyTranslatorTests.modifierKeyIsInferredWithoutAKeyCode` | |
| 鼠标：点击、悬停、点输入码、翻页箭头 | 完成 | UI `CandidatePanelTests`（`clickingACandidateSelectsIt`、`releasingOnAnotherCandidateSelectsNothing`、`hoveringHighlightsOnlyInTheWindow`、`pagingArrowsPage`、`clickingThePreeditMovesTheCaretOneStep`）；App `InputAdapterTests`（`clickingACandidateCommitsIt`、`clickingThePreeditMovesTheCaret`、`requestsGoToTheClientShownLast`） | |
| 滚轮和轻扫翻页（竖排时对调） | 完成 | UI `ScrollPagerTests`；App `InputAdapterTests.scrollingPagesTheCandidates` | |
| 状态消息约 1.2 秒 | 完成 | UI `CandidatePanelTests.statusMessagesHideByThemselves`、`candidatesReplaceTheStatusMessage`；App `InputAdapterTests.statusIsShownNearTheCaret` | |
| 候选窗位置 | 完成 | UI `PanelPlacementTests`、`SquirrelReferenceTests`（和鼠须管自己的渲染对比） | 手动 F1–F3 |
| 方案 `style` 切换 | 完成 | App `FrontendConfigTests.aSchemasStyleOverridesSquirrelYAML`（真 librime：方案的 style 盖过 squirrel.yaml，外观和会话的显示方式都跟着变）、`InputAdapterTests.theSessionsSchemaIsReported`；Core `InputSessionTests.theSchemaIsReportedOncePerSession`；Config `LibrimeConfigTests.schemaStyleThroughLibrime` | |
| 失焦、切换输入法、脚本切走时上屏 | 完成 | 回放 `commit-composition`；App `InputAdapterTests.deactivatingNeverDropsText`、`finishingCommitsToTheLastClient`、`InputSourceInstallerTests.scribeIsCurrentInEitherMode` | 手动 B10、B11、B13 |
| 输入法菜单 | 完成 | App `menuOffersTheMaintenanceCommandsInOrder`、`everyLanguageHasEveryString` | 手动 B12 |
| 启动保护（2 秒内重启不加载 Rime，语音提示） | 完成 | App `LaunchGuardTests` | 语音提示和恢复手动 M6、M7 |

## 命令行和外部

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| 鼠须管的全部命令行参数 | 完成 | App `CommandTests`、`InputSourceInstallerTests`（假 TIS，不碰真实输入法） | 和 mainline `Main.swift` 逐个对照：`--quit`、`--reload`、`--register-input-source`/`--install`、`--enable-input-source`、`--disable-input-source`、`--select-input-source`、`--build`、`--sync`、`--ascii`、`--nascii`、`--getascii`、`--help` |
| `distribution_code_name` 和兼容开关 | 完成 | App `DistributionIdentityTests`；Config `ScribeCompatibilityTests`、`LibrimeConfigTests.scribeCompatibilityDeploy` | check-install 后 installation.yaml 是 Scribe；librime 1.17 每次初始化都重新设置发行名称，实测过（决定 0009） |
| `RIME_LOG_DIR` 和日志目录 | 完成 | RimeKit `logFilesAreNamedAfterTheApp` | check-install 在 `~/Library/Logs/Scribe` 里检查 librime 日志；`RIME_LOG_DIR` 本身只有代码 |
| SharedSupport 作 OpenCC 工作目录 | 完成 | 回放 `Tests/Fixtures/gate/rime-ice.replay`（打开雾凇拼音的 `traditionalization`，用自带的 `s2t.json` 出「漢字」） | `--replay` 和输入法用同一个函数设工作目录。librime 1.17 的 OpenCC 按配置文件所在目录找词典，换个工作目录也能转换；工作目录保留，和鼠须管一致。这个回放需要 `~/Library/Scribe` 里的雾凇拼音，在本机跑，不在 CI 里 |
| 自带 `rime_deployer`、`rime_dict_manager`、`rime-install` | 完成 | check-release（存在、通用二进制、签名、能运行） | 在公证过的发布包上检查 |

## 共享数据

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| librime 1.17.0 原样 | 完成 | RimeKit `cAPIReportsBundledVersion`、`versionMatchesCAPI`；`fetch-librime.sh` 固定 sha256 | 和 mainline 是同一个发布包（33e7814） |
| lua、octagram、predict 插件 | 完成 | check-release 自检（三个插件都能加载） | |
| plum 预置方案（prelude、essay、luna_pinyin、terra_pinyin、bopomofo、cangjie5、stroke、quick5） | 完成 | check-release 检查 `default.yaml`、`essay.txt`、`luna_pinyin.schema.yaml`、`quick5.schema.yaml` | 每个包都固定到 2026-10-18 时的提交，和 mainline 当天的构建一致；按 plum 的规则挑文件。和鼠须管 1.1.2 的差别见决定 0010 |
| octagram 语法数据 | 完成 | check-release 检查 `grammar.yaml`、`zh-hant-t-essay-bgc.gram`、`zh-hant-t-essay-bgw.gram` | 和 mainline 的 `SQUIRREL_BUNDLED_RECIPES` 一致：默认分支的 `grammar.yaml` 加 hant 分支的语言模型。mainline 不打包 hans 分支的模型，中书也不带（决定 0010） |
| OpenCC 数据 | 完成 | check-release（`s2t.json`、`STCharacters.ocd2`） | 来自 librime 1.17.0 的 rime-deps，和 mainline 相同 |
| `squirrel.yaml` 原样（版本 1.0） | 完成 | check-release；Config `LibrimeConfigTests.presetsInSharedSupport`（21 套预设） | 和 mainline 一致；比鼠须管 1.1.2 多 `status_icon` 和 Alacritty 的 `app_options` |
| 预编译 `SharedSupport/build` | 完成 | check-release 把发布包里的 `SharedSupport` 复制出来运行 `--build`，检查 `build/` 里的二进制 | postinstall 经安装器以 root 运行 `Scribe --build`，失败不影响安装，`RIME_NO_PREBUILD` 可跳过（决定 0002）。签名发布包上验证过 |
| 命令行工具 | 完成 | check-release | 同上「自带 `rime_deployer`…」 |

## 外观设置（`style`）

候选窗的渲染都和鼠须管自己的代码对照：UI `SquirrelReferenceTests` 把 `Tests/Fixtures/snapshots/cases.json` 里的每个用例画出来，和 `Tools/squirrel-oracle` 用鼠须管 46962d2 的 `SquirrelTheme`、`SquirrelView`、`SquirrelPanel` 画的参考图比较（容差只覆盖抗锯齿，决定 0007）；同一批用例另有中书自己的逐像素基准图（UI `PanelSnapshotTests`）。下表「测试」里的 `组/名字` 是 `cases.json` 的用例，「完成」要求至少一个用例把这一项设成非默认值。配置的读取（YAML、回退规则、`%c`/`%@`、字体列表的拆分）在 ScribeConfig（工作流 1），这里只记候选窗这一侧。

离屏渲染截不到的部分：`translucency` 的毛玻璃背景、窗口阴影、窗口的实时行为（位置、尺寸记忆、外观切换）。它们的覆盖方式写在对应行的「说明」里。

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| `color_scheme` / `color_scheme_dark` | 完成 | UI `SquirrelReferenceTests`：`schemes/*`、`presets/*`（`color_scheme` 依次设成 21 个预设）、`max-sample/light`、`max-sample/dark`（`color_scheme_dark`，暗色外观下用 wechat_dark）；UI `PanelThemeTests.nativeColoursComeFromThePalette` | 选哪套由 ScribeConfig 的 `Appearance` 决定；窗口每次显示时按系统外观取亮或暗主题，只有非 native 的亮色主题时固定用浅色外观（和鼠须管 `show()` 一样），这一步没有单独的测试 |
| `candidate_list_layout` | 完成 | `layout/linear-*`（4 个）、`features/preedit-linear`、`wrap-linear`、`shadow-linear`、`expansion-linear`、`hilited-corner-linear`、`paging-linear-vertical`、`scheme-overrides`、`schemes/wechat_*`、`presets/apathy`、`clean_white`、`max-sample/*` | `_linear` 选项见上面「选项和属性」 |
| `text_orientation` | 完成 | `layout/*-vertical-*`（4 个）、`features/preedit-vertical`、`paging-linear-vertical`、`status-message-vertical`、`scheme-orientation`（写在配色里）；UI `CandidatePanelTests.verticalPanelsTurnAsLayers`、`PanelRendererTests.verticalPanelsTurnClockwise` | 已知差异：TextKit 把鼠须管的行图层对齐到窗口像素网格，竖排面板差几分之一点才对齐，所以竖排字形和鼠须管差最多约三分之一点，竖排用例的容差放宽到 3%（决定 0007）。`_vertical` 选项见上面 |
| `inline_preedit` | 完成 | 回放 `inline-preedit`、`inline-preedit-off`、`app-option-inline`、`app-options`；UI `PanelTextTests.preeditShowsWhateverTheTheme`；`features/preedit-*`（主题不内嵌）、`features/preedit-inline-theme`、`max-sample/light-no-inline`、`max-sample/dark-no-inline`（主题内嵌、应用 `no_inline`） | 是否内嵌由 ScribeCore 按会话决定（加上 `no_inline`、`inline` 选项），内嵌时快照里没有预编辑；候选窗不看这个设置，有预编辑就画，和鼠须管的面板一样 |
| `inline_candidate` | 完成 | 回放 `inline-candidate`、`inline-candidate-caret`、`inline-candidate-without-preedit` | 只改输入框里的标记文本（ScribeCore、IMK），候选窗不看它，鼠须管的面板也不看，所以没有渲染用例 |
| `translucency` | 部分 | `features/translucent`、`features/mutual-exclusive`、`features/scheme-overrides`（半透明颜色叠加的效果） | 毛玻璃背景（macOS 26 起 `NSGlassEffectView`，之前 `NSVisualEffectView`，按面板轮廓遮罩）显示的是窗口后面的内容，离屏截不到，中书的快照和鼠须管的参考图里都不画。缺口：毛玻璃本身既没有自动测试，也还没有手动检查条目 |
| `mutual_exclusive` | 完成 | `features/mutual-exclusive`（和 `features/translucent` 只差这一项）、`features/scheme-overrides`；UI `PanelShapesTests.mutualExclusionCutsCandidatesOutOfTheBackground` | |
| `memorize_size` | 部分 | UI `PanelPlacementTests.verticalPanelsKeepTheirLongestLength`（照鼠须管 `show()` 的条件写，连运算符优先级一起） | 尺寸记忆是窗口跨多次显示的行为，参考图只画单次显示，所以没有和鼠须管自己的结果对比。缺口：让对照工具也记录鼠须管的窗口位置和尺寸 |
| `show_paging` | 完成 | `features/paging-stacked`（上下都能翻）、`paging-linear-vertical`（只能往下）、`scheme-overrides`；UI `PanelShapesTests.pagingArrowsSitInTheStrip`、`CandidatePanelTests.pagingArrowsPage`、`PanelThemeTests.pagingStripFollowsTheLabelSize` | |
| `status_message_type` | 完成 | 回放 `status`（`@status-message long`、`short`）；App `SessionConfigurationTests`、`InputAdapterTests.statusFollowsTheConfiguration`；UI `features/status-message`、`status-message-vertical`、`CandidatePanelTests.statusMessagesHideByThemselves` | 长短在 ScribeCore 里选，候选窗只显示传来的消息（用候选文字的样式和段落样式，和鼠须管一样） |
| `candidate_format` | 完成 | `features/format-four-per-em-space`（U+2005）、`format-without-label`、`scheme-overrides`、`presets/clean_white`（`%c %@`）、`apathy`、`dust`、`mojave_dark`、`max-sample/*`（`"%c %@ "`，含 U+2005）；UI `PanelTextTests.formatPlaceholdersAndLabels` | `%c`、`%@` 的换算在 ScribeConfig 的 `CandidateFormat` |
| `font_face` / `font_point` | 完成 | 全部用例（默认样式固定为 `Avenir, PingFang SC` 16 点）；`schemes/wechat_*`、`max-sample/*`（`PingFangSC-Regular`）、`presets/apathy`（`PingFangSC-Regular,HanaMinB`）、`dust`（没装的字体，走回退）、`mojave_dark`（`PingFangSC`）、`scheme-overrides`（15 点）；UI `PanelThemeTests.fontListsCascade`、`familyAndFaceEntries`、`noFaceUsesTheUserFont` | 字体列表的拆分在 ScribeConfig 的 `FontFace` |
| `label_font_face` / `label_font_point` | 完成 | `features/part-fonts`（Menlo 12）、`scheme-overrides`（写在配色里）、`schemes/wechat_*`、`max-sample/*`（12 点）、`presets/apathy`、`dust`；UI `PanelThemeTests.smallerLabelsSitHigherInHorizontalText`、`partsWithoutFacesUseTheCandidateFont` | |
| `comment_font_face` / `comment_font_point` | 完成 | `features/part-fonts`（Helvetica 13）、`scheme-overrides`；UI `PanelThemeTests.partsWithoutFacesUseTheCandidateFont` | |
| `preedit_font_face` / `preedit_font_point` | 完成 | `features/part-fonts`（Menlo 15）、`scheme-overrides`（Menlo 14） | |
| `alpha` | 完成 | `features/alpha`（0.6）、`scheme-overrides`（0.9） | 屏幕上设在窗口的 `alphaValue`；对照工具在合成时乘上鼠须管给窗口设的值 |
| `corner_radius` / `hilited_corner_radius` | 完成 | 全部用例（默认样式 7）；`features/hilited-corner-stacked`、`hilited-corner-linear`、`shadow-*`、`expansion-*`、`translucent`、`mutual-exclusive`、`scheme-overrides`、`presets/mojave_dark`、`starcraft`；UI `PanelGeometryTests.radiusRoundsEveryCorner`、`SnapshotHarnessTests.highlightOnePointRounderFails` | |
| `border_height` / `border_width` | 完成 | 全部用例（默认样式 -2）；`features/border`（4、4，带边框色）、`schemes/wechat_*`、`max-sample/*`（8、0）、`scheme-overrides`（3、2）；UI `PanelThemeTests.insetsSwapInVerticalMode` | |
| `line_spacing` / `spacing` | 完成 | 全部用例（默认样式 5、8）；`features/scheme-overrides`（10、12）、`features/preedit-*`（`spacing` 决定预编辑和候选之间的距离）；UI `PanelThemeTests.paragraphSpacingComesFromTheStyle` | |
| `base_offset` | 完成 | `features/base-offset`（3）、`scheme-overrides`（2） | TextKit 2 会抵消整行统一的 `baselineOffset`，单独设 `base_offset` 看不出变化；参考图证实鼠须管也一样（决定 0007） |
| `shadow_size` | 完成 | `features/shadow-stacked`、`shadow-linear`、`scheme-overrides` | 这是高亮候选的阴影。窗口本身的阴影（`hasShadow`）离屏截不到，只在屏幕上 |
| `surrounding_extra_expansion` | 完成 | `features/expansion-stacked`（2）、`expansion-linear`（-2）、`translucent`、`mutual-exclusive`、`scheme-overrides` | |

## 配色（`preset_color_schemes`）

同上：「测试」里的 `组/名字` 是 `cases.json` 的用例，都在 UI `SquirrelReferenceTests` 里和鼠须管的参考图比较。颜色值的解析和回退（缺的颜色用哪个）在 ScribeConfig 的 `ThemeColors`，候选窗负责把它们画对，包括 2:1 混合的计算。

| 条目 | 状态 | 测试 | 说明 |
|------|------|------|------|
| `name` / `author` | —— | | 不画在候选窗里，只在设置界面列配色时用；读取在 ScribeConfig 的 `PresetColorScheme` |
| `color_space` | 完成 | `presets/solarized_light`（`display_p3`）；UI `PanelThemeTests.coloursResolve` | 快照和参考图都是 sRGB，超出 sRGB 的 Display P3 颜色在图里会被截断；屏幕上不截断 |
| `back_color` | 完成 | `schemes/*`、`presets/*`、`max-sample/*`、`features/*` 里非 native 的用例 | |
| `border_color` | 完成 | `features/border`、`scheme-overrides`、`presets/dust`、`google`、`mojave_dark`、`retro_green`、`retro_orange`、`solarized_dark`、`solarized_light`、`solarized_rock`、`starcraft` | `schemes/wechat_*` 设了边框色但边框宽度取 `min(border_width, border_height)` = 0，不画，和鼠须管一样 |
| `preedit_back_color` | 完成 | `features/preedit-stacked`、`preedit-linear`、`preedit-vertical`、`preedit-only`、`translucent`、`mutual-exclusive`、`expansion-*`、`scheme-overrides`、`presets/solarized_dark`、`solarized_light` | |
| `candidate_back_color` | 完成 | `features/preedit-*`、`translucent`、`mutual-exclusive`、`expansion-stacked`、`expansion-linear`、`scheme-overrides` | |
| `hilited_back_color` | 完成 | `features/preedit-*`、`translucent`、`mutual-exclusive`、`expansion-*`、`scheme-overrides`、`presets/dark_temple`、`google`、`mojave_dark`、`psionics`、`purity_of_essence`、`purity_of_form`、`solarized_dark`、`solarized_light`、`starcraft` | 预设用例都带预编辑和选中范围，画得出这一项 |
| `hilited_candidate_back_color` | 完成 | 几乎所有非 native 用例；`presets/*` 里没设它的预设用 `hilited_back_color` 回退 | |
| `text_color` / `hilited_text_color` | 完成 | `features/preedit-*`、`scheme-overrides`、`presets/*`（预编辑和选中部分） | |
| `candidate_text_color` / `hilited_candidate_text_color` | 完成 | `schemes/*`、`presets/*`、`max-sample/*`、`features/*` 里非 native 的用例 | |
| `label_color` / `hilited_candidate_label_color`（缺省时 2:1 混合） | 完成 | 写明颜色：`schemes/wechat_*`、`presets/clean_white`、`dust`、`mojave_dark`、`psionics`、`retro_green`、`retro_orange`、`solarized_dark`、`solarized_light`、`starcraft`、`max-sample/dark`；2:1 混合：`schemes/aqua`、`lost_temple`、`max-sample/light` 和其余预设；UI `PanelThemeTests.blendIsTwoPartsForeground` | 混合在 deviceRGB 里按分量算，含 alpha |
| `comment_text_color` / `hilited_comment_text_color` | 完成 | `schemes/*`、`presets/*`、`max-sample/*`、`features/*` 里非 native 的用例 | |
| `accent_text_color` / `warning_text_color` | 完成 | `features/accent-warning-comments`、`accent-without-colour`（没设颜色时注释保持标签颜色）；UI `PanelTextTests.accentAndWarningColourUnhighlightedComments`、`CandidatePanelTests.commentMarksFromTheSnapshotReachTheDrawing` | 标记来自 `_comment_highlight` / `_comment_warning`，见上面「选项和属性」 |
| 配色里覆盖外观设置 | 完成 | `features/scheme-overrides`（排版、字体和三种分部字体、圆角、边框、行距、间距、基线、阴影、alpha、扩展、翻页、互斥、半透明、格式、内嵌都写在配色里）、`features/scheme-orientation`（竖排写在配色里）、`schemes/wechat_*`、`presets/apathy`、`clean_white`、`dust`、`mojave_dark`、`starcraft`、`max-sample/*` | 只能写在 `style` 里的 `memorize_size`、`status_message_type` 由 ScribeConfig 处理 |
| 内置的 21 套配色 | 完成 | `presets/*`（`SharedSupport/squirrel.yaml` 里全部 21 个，各带预编辑和选中高亮）；Config `LibrimeConfigTests.presetsInSharedSupport` | 字体按各配色原样，没装的字体走回退 |
