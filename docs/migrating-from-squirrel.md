# 从鼠须管迁移

中书和鼠须管用同一个引擎（librime）、同样的配置格式，可以同时装着。迁移就是把鼠须管的用户目录 `~/Library/Rime` 复制成中书的 `~/Library/Scribe`，鼠须管和它的目录都不改动，随时可以切回去。

## 一键导入

一键导入在中书设置（ScribeSettings.app）的「导入」页。0.1.0 的安装包里还没有中书设置，目前要从源码构建（见 [开发](development.md)），构建好的在 `build/DerivedData/Build/Products/Release/ScribeSettings.app`。

1. 先在鼠须管的输入法菜单里选一次「同步用户数据」，让用户词的快照是最新的（可选，见下面「用户词」）。
2. 打开中书设置，选「导入」。「来源」默认是 `~/Library/Rime`，要导入别的目录就点「选择其他目录…」。
3. 点「一键导入」。中书目录里已经有东西的话，会先问一次，点「移到备份并导入」。
4. 导入完成后看下面的报告：复制了多少文件、跳过了什么、有没有需要留意的地方。正在运行的中书会自动重新部署。

### 复制什么

除了下一节列出的东西，`~/Library/Rime` 里的文件都原样复制，包括：

- 方案（`*.schema.yaml`）、词库（`*.dict.yaml`，包括 `cn_dicts/` 这样的子目录）、补丁（`*.custom.yaml`）
- `default.yaml`、`symbols.yaml` 等共享配置
- `squirrel.yaml`、`squirrel.custom.yaml`：中书照鼠须管的方式读它们，皮肤和 `app_options` 照常生效
- `rime.lua` 和 `lua/` 下的全部脚本
- `opencc/` 下的全部文件
- `custom_phrase*.txt`、语言模型（`*.gram`）
- `.git` 仓库：整个复制，中书不读也不动它
- 小狼毫、仓输入法、ibus-rime、同文的配置（`weasel.yaml`、`hamster.yaml`、`ibus_rime.yaml`、`trime.yaml` 和它们的 `.custom.yaml`、`*.trime.yaml`）：原样复制，中书不读
- README、LICENSE 等其他文件

### 不复制什么

- `build/`：部署生成的文件，中书部署时自己生成
- 用户词库（`*.userdb`、`*.userdb.kct`、`*.userdb.txt`）：不直接复制，见下一节
- `sync/` 同步文件夹（或者 `installation.yaml` 里的 `sync_dir` 指向 `~/Library/Rime` 里面的话，那个文件夹）
- `trash/`：librime 放被替换文件的地方
- `.DS_Store`

`installation.yaml` 会重新生成：中书有自己的安装 ID，`sync_dir` 沿用鼠须管的。

### 用户词

鼠须管学到的词在用户词库里，鼠须管运行时一直开着这些文件。导入不碰原文件：先把词库复制到临时目录，从副本导出鼠须管学到的词，再合并进中书的词库。导出失败的词库，改用鼠须管上次「同步用户数据」时留下的快照（`sync/<鼠须管的安装 ID>/<词库>.userdb.txt`）。

报告的「用户词」一节列出每个词库：「已合并」、「中书同步时合并」或「失败」。没法直接合并的会放进中书同步文件夹里的 `squirrel-import/`，中书下一次同步用户数据时合并（中书正在运行的话，导入后马上就会同步），合并完这个文件夹会自动删掉。

### 需要留意的地方

报告会单独列出：

- **Lua 脚本里提到 Squirrel 的行**：脚本可能按前端的名字分支，见下面「兼容开关」。
- **其他前端的配置**：复制了，但中书不读。
- **符号链接**：指向绝对路径，或者指向 `~/Library/Rime` 外面的链接，复制过来可能失效。

## 备份和再导入

导入前，`~/Library/Scribe` 里已有的东西会整个移到旁边的备份文件夹，名字是「Scribe backup <日期-时间>」，比如 `~/Library/Scribe backup 20261023-100343`，从不删除。用不着的话自己删掉就行。

可以随时再导入一次，比如在鼠须管里改了很多配置之后。注意：再导入会把当前的 `~/Library/Scribe` 整个移到新的备份里，**导入以后在中书里学到的新词也在备份里，不会带到新的中书目录**。想留住它们，先按下面「两边同步」把中书的词同步出去，或者导入后从备份里导出再导入（见「切回鼠须管」）。

## 两边同步

librime 的「同步用户数据」把每个安装的用户词写到同步文件夹里自己的子文件夹（`<sync_dir>/<安装 ID>/`），同时合并其他子文件夹里的词。

- 鼠须管的 `installation.yaml` 里设了 `sync_dir`（比如指向 iCloud 云盘里的一个文件夹）的话，导入后中书沿用同一个 `sync_dir`，用的是自己的安装 ID。两边都选一次「同步用户数据」，就能互相看到对方学到的词。
- 没设的话，鼠须管同步到 `~/Library/Rime/sync`，中书同步到 `~/Library/Scribe/sync`，两边不相通。想相通，就在两边的 `installation.yaml` 里写上同一个 `sync_dir`（绝对路径），比如：

  ```yaml
  sync_dir: "/Users/你/Library/Mobile Documents/com~apple~CloudDocs/RimeSync"
  ```

  改完在两边各选一次「重新部署」，再各选一次「同步用户数据」。

## 兼容开关：报告为鼠须管

中书默认告诉 librime 自己是「Scribe」。有的 Lua 脚本用 `rime_api.get_distribution_code_name()` 判断当前前端，只认 `Squirrel`；这种脚本在中书里会走别的分支。导入报告会列出 Lua 里提到 Squirrel 的行，看一眼那行在做什么：

- 只是判断是不是小狼毫（`weasel`）或 ibus，其他前端都一样处理的，不用管。
- 真要求前端是 `Squirrel` 的，在 `~/Library/Scribe/scribe.custom.yaml` 里打开兼容开关：

  ```yaml
  patch:
    compatibility/report_as_squirrel: true
  ```

  再选「重新部署」。中书会改报「Squirrel / 鼠鬚管」，并重启 librime 让它生效，以后启动也一直这样，直到关掉这个开关。

## 换了的路径和命令

| 鼠须管 | 中书 |
| --- | --- |
| `~/Library/Rime` | `~/Library/Scribe` |
| `/Library/Input Methods/Squirrel.app` | `/Library/Input Methods/Scribe.app` |
| `"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload` | `"/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe" --reload` |
| `… Squirrel --sync`、`--ascii`、`--nascii`、`--getascii`、`--quit` | 同名参数，换成 `Scribe` |
| plum：`bash rime-install <配方>`（装进 `~/Library/Rime`） | `rime_dir="$HOME/Library/Scribe" bash "/Library/Input Methods/Scribe.app/Contents/MacOS/rime-install" <配方>` |
| 日志在 `$TMPDIR` 里的 `rime.squirrel.*` | `~/Library/Logs/Scribe` 里的 `rime.scribe.*` |

用 plum 装完配方，在中书的输入法菜单里选「重新部署」。中书自带的 `rime-install` 和鼠须管的是同一版 plum。

输入法菜单里的项目和鼠须管同名：重新部署（Control-Option-`）、同步用户数据、日志目录、用户目录、使用说明，另外有「检查更新」。

## 切回鼠须管

鼠须管一直装着，`~/Library/Rime` 也和导入前一样，在菜单栏的输入法菜单里选回「鼠须管」就行。不想要中书了，按 [README](../README.md) 里的「卸载」删掉它。

在中书里学到的新词留在 `~/Library/Scribe`。想带回鼠须管：

- 两边用同一个 `sync_dir` 的话，在中书里选「同步用户数据」，再在鼠须管里选一次。
- 否则用自带的 `rime_dict_manager` 导出、导入（导入前先在终端退出鼠须管：`"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit`）：

  ```bash
  cd ~/Library/Scribe
  "/Library/Input Methods/Scribe.app/Contents/MacOS/rime_dict_manager" --export rime_ice ~/Desktop/rime_ice.txt
  cd ~/Library/Rime
  "/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_dict_manager" --import rime_ice ~/Desktop/rime_ice.txt
  ```

  把 `rime_ice` 换成你的词库名（`~/Library/Scribe` 里 `.userdb` 前面的部分）。
