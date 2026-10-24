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

## 菜单栏、通知和启动保护

| # | 操作 | 预期 |
|---|------|------|
| M1 | 切到中书 | 菜单栏出现「中」（雾凇拼音中文状态的简短标签） |
| M2 | 单按一下 Shift | 菜单栏的「中」变成「Ａ」 |
| M3 | 切到 ABC | 菜单栏的中书图标消失 |
| M4 | 在 `~/Library/Scribe/scribe.custom.yaml` 里写 `patch: {status_icon: false}`，菜单 → 重新部署，再切回中书 | 菜单栏不显示中书的图标（测完删掉这个补丁，再重新部署） |
| M5 | 菜单 → 重新部署 | 通知中心里有中书的「正在部署…」，接着换成「部署完成。」，不弹横幅也不要求授权 |
| M6 | 在终端运行 `killall Scribe; open -g "$HOME/Library/Input Methods/Scribe.app"; sleep 1; killall Scribe; open -g "$HOME/Library/Input Methods/Scribe.app"` | 听到语音提示「中书启动时崩溃了……」 |
| M7 | 紧接 M6，在文本编辑里切到中书输入 `nihao`，再选菜单 → 重新部署，然后再输入 `nihao` | 第一次字母原样进入文稿；重新部署后出现候选窗 |

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
| C1 | Chrome | Cmd+L，输入 `nihao` | 拼音内嵌在地址栏里（`app_options` 打开了 `inline`），只有下划线、没有底色，和鼠须管一样 |
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

## 鼠标和触控板

在文本编辑里测。K4 要在终端里测，因为终端的 `app_options` 关了行内显示，输入码显示在候选窗里。K5 要先在 `~/Library/Scribe/scribe.custom.yaml` 里写 `patch: {appearance/show_paging: true}` 并重新部署（测完删掉，再重新部署）。

| # | 操作 | 预期 |
|---|------|------|
| K1 | 输入 `nihao`，用鼠标点候选窗里的第二个候选 | 第二个候选上屏 |
| K2 | 输入 `nihao`，把鼠标移到第三个候选上，不点 | 高亮框跟着鼠标移到第三个候选 |
| K3 | 紧接 K2，鼠标不动，按空格 | 上屏的是第一个候选（悬停只改显示，不改选中） |
| K4 | 在终端里切到中文，输入 `nihao`，点候选窗里输入码的 `ni` | 输入码里的「‸」向左移一个字母 |
| K5 | 输入 `ni`，点候选窗右边的下一页箭头 | 候选窗换成第二页 |
| K6 | 输入 `ni`，鼠标停在候选窗上，滚轮往下滚两三格 | 候选窗换成第二页 |
| K7 | 紧接 K6，滚轮往上滚两三格 | 回到第一页 |
| K8 | 输入 `ni`，两指在触控板上向右横扫一下 | 候选窗翻一页（竖写时同一个手势往反方向翻） |

## 输入法菜单

切到中书后打开菜单栏的输入法菜单。重新部署见 B12，检查更新见 U1、U2。

| # | 操作 | 预期 |
|---|------|------|
| I1 | 选「同步用户数据」 | 同步文件夹（默认 `~/Library/Scribe/sync`，`installation.yaml` 里设了 `sync_dir` 就是那里）下中书自己的子文件夹里，`.userdb.txt` 的修改时间变成刚才 |
| I2 | 选「日志目录…」 | 访达打开 `~/Library/Logs/Scribe` |
| I3 | 选「用户目录…」 | 访达打开 `~/Library/Scribe` |
| I4 | 选「使用说明…」 | 浏览器打开 GitHub 上中书的 README |
| I5 | 在文本编辑里按 Control-Option-` | 通知中心先后出现「正在部署…」「部署完成。」 |
| I6 | 选「设置…」 | 中书设置的窗口出现在最前面，左边是导入、方案、外观、快捷键 |
| I7 | 把系统语言换成英文（系统设置 → 通用 → 语言与地区），注销再登录，打开输入法菜单 | 菜单项是 Deploy、Sync user data、Settings…、Logs…、User folder…、Help…、Check for updates… |

## 导入和设置

R1 用临时目录，不碰 `~/Library/Scribe`。下面的 `<中书设置>` 是 `/Library/Input Methods/Scribe.app/Contents/Helpers/ScribeSettings.app`（0.1.1 起才有）。L1–L3 在真正导入过鼠须管配置之后做。

| # | 操作 | 预期 |
|---|------|------|
| R1 | 在终端运行 `mkdir -p /tmp/scribe-lua/rime/lua /tmp/scribe-lua/scribe && echo 'if rime_api.get_distribution_code_name() == "Squirrel" then end' > /tmp/scribe-lua/rime/lua/check.lua`，再运行 `"<中书设置>/Contents/MacOS/ScribeSettings" -ScribeImportSource /tmp/scribe-lua/rime -ScribeUserDirectory /tmp/scribe-lua/scribe -ScribeImportOnLaunch YES` | 导入报告的「需要留意」里有「lua/check.lua 第 1 行按前端名称判断，这段脚本在中书里可能走另一条分支。」（测完退出中书设置，删掉 `/tmp/scribe-lua`） |
| N1 | 打开中书设置 → 外观，点开「浅色主题」 | 列表里的主题显示的是名字（比如「微信键盘」），不是 ID |
| N2 | 紧接 N1，选一个写了作者的主题，鼠标停在「浅色主题」上 | 浮出的提示是这个主题的作者 |
| L1 | 导入之后，输入法菜单 → 重新部署 | 通知中心出现「部署完成。」，没有「部署出错，请查看日志。」 |
| L2 | 在鼠须管里打一个你常打、鼠须管已经学会的词（比如一个人名），记下它在第几位；切到中书打同样的编码 | 这个词在中书里也在同一位 |
| L3 | 挑三个你常用的编码，在鼠须管和中书里各打一遍，比较第一页 | 两边第一页的候选和顺序一样 |

## 命令行工具

| # | 操作 | 预期 |
|---|------|------|
| X1 | 中书设置 → 方案，在「用东风破（plum）安装方案」的「配方」里输入 `prelude` | 下面的命令是 `rime_dir='/Users/<你>/Library/Scribe' bash '/Library/Input Methods/Scribe.app/Contents/MacOS/rime-install' prelude` |
| X2 | 紧接 X1，点「拷贝命令」，在终端里粘贴，把 `rime_dir=` 后面引号里的目录改成 `/tmp/scribe-plum` 再回车 | `/tmp/scribe-plum/default.yaml` 出现（测完删掉 `/tmp/scribe-plum`） |
| X3 | 在终端运行 `cd ~/Library/Scribe && "/Library/Input Methods/Scribe.app/Contents/MacOS/rime_dict_manager" --list` | 列出你的用户词库名，比如 `rime_ice` |

## 半透明候选窗

玻璃背景截不到离屏图里，只能在屏幕上看。先在 `~/Library/Scribe/squirrel.custom.yaml` 里打开 `style/translucency: true`，换一个背景色带透明度的配色，重新部署，再把候选窗移到一个色彩鲜艳的窗口（比如一张彩色图片）上面输入 `nihao`。测完删掉补丁，再重新部署。

| # | 系统 | 操作 | 预期 |
|---|------|------|------|
| G1 | macOS 26 及以上 | 在彩色窗口上输入 `nihao` | 候选窗是 Liquid Glass 的玻璃效果，透出下面的颜色 |
| G2 | macOS 14、15 | 在彩色窗口上输入 `nihao` | 候选窗背景是普通的模糊磨砂，透出下面模糊的颜色 |

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

## 更新

只对发布版：用 `.pkg` 装到 `/Library/Input Methods` 的、带真实更新密钥的版本。U3、U4 要等 appcast 里有比它新的版本，可以先装上一版再发新版时检查。

| # | 操作 | 预期 |
|---|------|------|
| U1 | 切到中书，打开输入法菜单 | 最后一项是「检查更新…」；`~/Library/Input Methods` 里的本地构建没有这一项 |
| U2 | 选「检查更新…」 | Sparkle 的窗口出现在最前面：有新版本时显示版本号和更新内容，没有时提示已是最新版本 |
| U3 | 有新版本时，在窗口里点安装 | 要求输入管理员密码；装完后中书自动重新启动，菜单栏照常显示中西文状态，输入 `nihao` 照常出现候选窗 |
| U4 | 有新版本时，打着字等每天的定时检查（或者把系统时间往后调一天） | 不弹出任何窗口，只在通知中心出现一条「X 版可以更新了」；点通知才打开 Sparkle 的窗口 |
| U5 | 开着中书设置（I6）时按 U3 装好更新；中书设置如果还开着，按 ⌘Q 退出，再从输入法菜单选「设置…」 | 打开的中书设置是新版：它的菜单「ScribeSettings → 关于 ScribeSettings」里是新的版本号 |
