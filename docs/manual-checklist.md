# 真实应用的手动检查清单

单元测试和回放测试只能覆盖中书和 librime 之间的部分，应用怎么接收文字只能到真实应用里看。每次发版前，以及改动按键处理、上屏、候选窗或 `app_options` 之后，都按这份清单过一遍。

## 怎么用

- 用要发布的版本：本地构建用 `Scripts/install-local.sh` 安装，发布包装到 `/Library/Input Methods`。默认配置（没有 `squirrel.custom.yaml`、`scribe.custom.yaml`），方案用雾凇拼音或朙月拼音都行。
- 每一行只有一个预期结果。符合就打勾。不符合的话，先把按键序列录成回放（`Tests/Fixtures/replays/`），看到它失败再修，和其他 bug 一样。
- 拿不准对不对时，切到鼠须管做同样的操作，以鼠须管的表现为准。
- `app_options` 在切到应用、中书被激活时生效，按 bundle ID 精确匹配。重测一行前，先切到别的应用再切回来。
- 系统设置 → 键盘 → 输入法里的「使用大写锁定键切换 ABC 输入法」保持关闭，否则大写锁定会切走输入法。
- 「西文模式」的判断方法：直接敲字母，字母原样进入应用，不出现候选窗。
- 没装的应用跳过，记为「未装」。

## 基准：文本编辑

先在文本编辑（TextEdit）里确认基本功能正常，后面各节的问题才能归到具体应用上。

| # | 操作 | 预期 |
|---|------|------|
| B1 | 新建文稿，切到中书，输入 `nihao` | 拼音带下划线内嵌在正文里，光标旁出现候选窗 |
| B2 | 接着按空格 | 「你好」上屏，候选窗消失 |
| B3 | 输入 `nihao`，按 `2` | 第二个候选上屏 |
| B4 | 输入 `nihao`，按回车 | 原样上屏 `nihao` |
| B5 | 输入 `nihao`，按 Esc | 拼音清空，什么都不上屏 |
| B6 | 单按一下左 Shift，再敲 `abc` | `abc` 原样上屏（切到西文） |
| B7 | 回到中文，按住 Shift 敲 `a` 再松开 Shift，按 Esc，再输入 `nihao` | 出现候选窗（Shift 带着别的键按下，不切换中西文） |
| B8 | 打开大写锁定，敲 `abc` | 上屏 `ABC`，不出现候选窗 |
| B9 | 输入 `nihao` 后按 Cmd+A | 全选生效，中书不吞 Cmd 快捷键 |
| B10 | 输入 `nihao` 后点另一个文稿窗口 | 原文稿里留下 `nihao`，没有下划线 |
| B11 | 输入 `nihao` 后用 Ctrl+空格切到别的输入法 | 原文稿里留下 `nihao`，没有下划线 |
| B12 | 菜单栏输入法菜单 → 重新部署，等几秒再输入 `nihao` | 照常出现候选窗 |
| B13 | 在文稿里输入 `nihao`，然后在终端用脚本切到 ABC（如 `macism com.apple.keylayout.ABC`） | 文稿里留下 `nihao`，没有下划线，候选窗消失 |

## 终端

| # | 应用 | 操作 | 预期 |
|---|------|------|------|
| T1 | 终端（Terminal） | 切到终端窗口，敲 `ls` | 西文模式，`ls` 原样出现在命令行 |
| T2 | 终端 | 单按 Shift 切到中文，输入 `nihao` | 拼音不内嵌在命令行里，只显示在候选窗里 |
| T3 | 终端 | 接着按空格 | 命令行里是「你好」，没有残留的拼音 |
| T4 | 终端 | 命令行有字时按 Ctrl+C | 终端照常中断当前行 |
| T5 | iTerm2 | 切到 iTerm2，敲 `ls` | 西文模式，`ls` 原样出现在命令行 |
| T6 | iTerm2 | 单按 Shift 切到中文，输入 `nihao` | 拼音不内嵌在命令行里，只显示在候选窗里 |
| T7 | iTerm2 | 接着按空格 | 命令行里是「你好」，没有残留的拼音 |

## 浏览器地址栏

| # | 应用 | 操作 | 预期 |
|---|------|------|------|
| S1 | Safari | Cmd+L，输入 `nihao` | 拼音带下划线内嵌在地址栏里 |
| S2 | Safari | 接着按空格 | 地址栏里是「你好」，下面的搜索建议跟着更新 |
| S3 | Safari | Cmd+L，输入 `nihao` 后按回车 | 地址栏里是 `nihao`，页面没有跳转 |
| S4 | Safari | Cmd+L，输入 `nihao` 后点网页正文 | 地址栏里留下 `nihao`，没有下划线 |
| C1 | Chrome | Cmd+L，输入 `nihao` | 拼音内嵌在地址栏里（`app_options` 打开了 `inline`） |
| C2 | Chrome | 接着按空格 | 地址栏里是「你好」，下面的搜索建议跟着更新 |
| C3 | Chrome | Cmd+L，输入 `nihao` 后按回车 | 地址栏里是 `nihao`，页面没有跳转 |
| C4 | Chrome | Cmd+L，输入 `nihao` 后点网页正文 | 地址栏里留下 `nihao`，没有下划线 |

## VS Code

| # | 操作 | 预期 |
|---|------|------|
| V1 | 切到编辑器，敲 `let` | 西文模式，`let` 原样上屏 |
| V2 | 单按 Shift 切到中文，在编辑器里输入 `nihao` 再按空格 | 「你好」上屏，光标在它后面 |
| V3 | 在集成终端里输入 `nihao` 再按空格 | 「你好」上屏到终端 |
| V4 | 输入 `nihao` 后按 Cmd+Shift+P | 命令面板打开 |

## 微信

| # | 操作 | 预期 |
|---|------|------|
| W1 | 在聊天输入框输入 `nihao` | 候选窗出现在输入框的光标旁边 |
| W2 | 接着按空格 | 「你好」上屏到输入框 |
| W3 | 输入 `nihao` 后按回车 | 输入框里是 `nihao`，消息没有发出 |
| W4 | 没有拼音时按回车 | 消息照常发出 |

## Office

| # | 应用 | 操作 | 预期 |
|---|------|------|------|
| O1 | Word | 在正文输入 `nihao` 再按空格 | 「你好」上屏 |
| O2 | Word | 输入 `nihao` 后按 Cmd+B | 加粗生效，中书不吞 Cmd 快捷键 |
| O3 | Excel | 选中一个单元格（不进入编辑），直接输入 `nihao` 再按空格 | 单元格里是「你好」，开头的 `n` 没有丢 |
| O4 | PowerPoint | 在文本框输入 `nihao` 再按空格 | 「你好」上屏 |

## 密码框

| # | 操作 | 预期 |
|---|------|------|
| P1 | 在 Safari 的登录页点进密码框，敲 `abc` | 不出现候选窗，密码框里多了三个圆点 |
| P2 | 从密码框切回普通输入框，输入 `nihao` 再按空格 | 「你好」上屏，中书恢复正常 |
| P3 | 终端菜单 → 安全键盘输入打开，切到中文后敲 `abc`（之后关掉安全键盘输入） | 不出现候选窗，`abc` 原样出现在命令行 |

## 全屏应用

| # | 操作 | 预期 |
|---|------|------|
| F1 | 文本编辑全屏（Ctrl+Cmd+F），输入 `nihao` | 候选窗显示在全屏窗口上面，跟着光标 |
| F2 | 全屏时把光标移到屏幕最底下一行，输入 `nihao` | 候选窗完整显示在屏幕内 |
| F3 | 有副屏时，在副屏上全屏的应用里输入 `nihao` | 候选窗出现在副屏上 |

## 默认 `app_options` 表里的应用

`SharedSupport/squirrel.yaml` 默认的 `app_options` 表，每个应用一行。表变了，这一节跟着改。

| # | 应用（bundle ID） | 操作 | 预期 |
|---|------|------|------|
| A1 | 聚焦搜索（`com.apple.Spotlight`） | Cmd+空格，敲 `safari` | 西文模式，`safari` 原样进入搜索框 |
| A2 | Alfred（`com.alfredapp.Alfred`） | 打开 Alfred，敲 `safari` | 西文模式，`safari` 原样进入搜索框 |
| A3 | Alfred 2（`com.runningwithcrayons.Alfred-2`） | 打开 Alfred 2，敲 `safari` | 西文模式，`safari` 原样进入搜索框 |
| A4 | Quicksilver（`com.blacktree.Quicksilver`） | 打开 Quicksilver，敲 `safari` | 西文模式，`safari` 原样进入搜索框 |
| A5 | 终端（`com.apple.Terminal`） | 见 T1–T3 | 西文模式开始，拼音不内嵌 |
| A6 | Alacritty（`org.alacritty`） | 切到中文，直接按逗号 | 「，」上屏一次，不丢字也不重复 |
| A7 | iTerm2（`com.googlecode.iterm2`） | 见 T5–T7 | 西文模式开始，拼音不内嵌 |
| A8 | MacVim（`org.vim.MacVim`） | 切到 MacVim，按 `i` 进入插入模式，敲 `abc` | 西文模式，`abc` 原样上屏 |
| A9 | MacVim | 插入模式下切到中文，输入 `nihao` | 拼音不内嵌在缓冲区里，只显示在候选窗里 |
| A10 | MacVim | 缓冲区至少两行。插入模式下切到中文，按 Esc 回到普通模式，再按 `j` | 中书已切回西文，`j` 让光标下移一行 |
| A11 | Xcode（`com.apple.dt.Xcode`） | 在源码编辑器敲 `let` | 西文模式，`let` 原样上屏 |
| A12 | TextWrangler（`com.barebones.textwrangler`） | 在文稿里敲 `abc` | 西文模式，`abc` 原样上屏 |
| A13 | TextMate 预览（`com.macromates.TextMate.preview`） | 在文稿里敲 `abc` | 西文模式，`abc` 原样上屏 |
| A14 | Atom（`com.github.atom`） | 在编辑器敲 `abc` | 西文模式，`abc` 原样上屏 |
| A15 | VS Code（`com.microsoft.VSCode`） | 见 V1 | 西文模式，`let` 原样上屏 |
| A16 | Sublime Text 2（`com.sublimetext.2`） | 在编辑器敲 `abc` | 西文模式，`abc` 原样上屏 |
| A17 | Aquamacs（`org.gnu.Aquamacs`） | 在缓冲区敲 `abc` | 西文模式，`abc` 原样上屏 |
| A18 | Emacs（`org.gnu.Emacs`） | 在缓冲区敲 `abc` | 西文模式，`abc` 原样上屏 |
| A19 | Emacs | 切到中文，输入 `nihao` | 拼音不内嵌在缓冲区里，只显示在候选窗里 |
| A20 | Hyper（`co.zeit.hyper`） | 在命令行敲 `ls` | 西文模式，`ls` 原样上屏 |
| A21 | Chrome（`com.google.Chrome`） | 见 C1 | 拼音内嵌在地址栏里 |
| A22 | Edge（`com.microsoft.edgemac`） | Cmd+L，输入 `nihao` | 拼音内嵌在地址栏里 |
| A23 | Telegram（`ru.keepcoder.Telegram`） | 在聊天输入框输入 `nihao` | 拼音内嵌在输入框里 |
