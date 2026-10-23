# 0005 输入法进程的命令行和通知

日期：2026-10-23

## 决定

`Scribe.app/Contents/MacOS/Scribe` 不带参数时作为输入法服务运行（InputMethodKit 就是这样启动它的）。带参数时：

| 参数 | 作用 |
| --- | --- |
| `--install`、`--register-input-source` | 注册输入源，不启用、不选中；已经启用的话跳过 |
| `--enable-input-source [ID...]` | 启用这些输入源；不给 ID 时启用主输入源（Hans），但用户已经启用了某个时保持原样 |
| `--disable-input-source [ID...]` | 停用这些输入源，不给 ID 时停用全部 |
| `--select-input-source [ID]` | 选中这个输入源，没启用的先启用；不给 ID 时只在主输入源已启用时选中它 |
| `--quit` | 退出所有正在运行的中书进程 |
| `--reload` | 发通知让正在运行的中书重新部署 |
| `--sync` | 发通知让正在运行的中书同步用户数据 |
| `--ascii`、`--nascii` | 发通知让正在运行的中书把所有会话切到西文或中文 |
| `--getascii` | 问正在运行的中书最近激活的那个应用是不是西文，打印 `ascii` 或 `nascii`，2 秒没有回答就打印 `nascii` |
| `--build` | 编译当前目录里的配置和方案（打包时预编译共享数据用） |
| `--self-test` | 用 app 自带的 librime 和临时用户目录启动，检查插件能否加载 |
| `--replay 文件` | 在 `~/Library/Scribe` 的临时副本上（不含用户词库）回放按键，开发和验收用 |
| `--help` | 显示帮助 |

ID 用完整的输入源 ID：`io.github.itvx.inputmethod.Scribe.Hans`、`io.github.itvx.inputmethod.Scribe.Hant`。语义和鼠须管相同；测试里通过假的输入源管理器检查这些规则，绝不改动本机实际选中的输入法。

认不出的参数打印用法到标准错误，退出码 2，绝不会再启动一个服务进程。例外是 Cocoa 启动时自己加的参数（`-psn_…`、`-NS…`/`-Apple…` 开头的 defaults 参数），直接忽略，免得系统或 Xcode 启动时意外失败。

`--reload` 和 `--sync` 只发分布式通知然后退出，名字固定，设置程序等其他程序也按名字发送（常量在 ScribeCore 的 `ServerNotification`）：

- `io.github.itvx.inputmethod.Scribe.ReloadNotification`：结束 librime、重新初始化、完整部署。
- `io.github.itvx.inputmethod.Scribe.SyncNotification`：同步用户数据（librime 的 `sync_user_data`）。
- `io.github.itvx.inputmethod.Scribe.SetASCIIModeNotification`（object 为 `ascii` 或 `nascii`）：所有会话切到西文或中文。
- `io.github.itvx.inputmethod.Scribe.GetASCIIModeNotification`：最近激活的应用的会话用 `io.github.itvx.inputmethod.Scribe.ASCIIModeResponse` 回答，object 为 `ascii` 或 `nascii`。

## 排队

librime 在维护（部署或同步）期间会拒绝再开始一次维护。设置程序导入后会紧接着发「重新部署」和「同步」，所以输入法进程用一个队列按顺序执行：librime 空闲时立刻执行，忙时等部署通知或定时检查，空闲后再执行下一个；重复的请求合并成一个。两种操作都会关闭所有会话，各个应用在下一次按键时自动建立新会话。
