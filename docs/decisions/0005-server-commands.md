# 0005 输入法进程的命令行和通知

日期：2026-10-23

## 决定

`Scribe.app/Contents/MacOS/Scribe` 不带参数时作为输入法服务运行（InputMethodKit 就是这样启动它的）。带参数时：

| 参数 | 作用 |
| --- | --- |
| `--install` | 注册输入源，不启用、不选中 |
| `--quit` | 退出所有正在运行的中书进程 |
| `--reload` | 发通知让正在运行的中书重新部署 |
| `--sync` | 发通知让正在运行的中书同步用户数据 |
| `--self-test` | 用 app 自带的 librime 和临时用户目录启动，检查插件能否加载 |
| `--help` | 显示帮助 |

认不出的参数打印用法到标准错误，退出码 2，绝不会再启动一个服务进程。例外是 Cocoa 启动时自己加的参数（`-psn_…`、`-NS…`/`-Apple…` 开头的 defaults 参数），直接忽略，免得系统或 Xcode 启动时意外失败。

`--reload` 和 `--sync` 只发分布式通知然后退出，名字固定，设置程序等其他程序也按名字发送（常量在 ScribeCore 的 `ServerNotification`）：

- `io.github.itvx.inputmethod.Scribe.ReloadNotification`：结束 librime、重新初始化、完整部署。
- `io.github.itvx.inputmethod.Scribe.SyncNotification`：同步用户数据（librime 的 `sync_user_data`）。

## 排队

librime 在维护（部署或同步）期间会拒绝再开始一次维护。设置程序导入后会紧接着发「重新部署」和「同步」，所以输入法进程用一个队列按顺序执行：librime 空闲时立刻执行，忙时等部署通知或定时检查，空闲后再执行下一个；重复的请求合并成一个。两种操作都会关闭所有会话，各个应用在下一次按键时自动建立新会话。
