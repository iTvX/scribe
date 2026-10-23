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
