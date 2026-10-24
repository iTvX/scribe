# 配置

中书读两种格式的前端配置：鼠须管的 `squirrel.yaml`（皮肤叫配色方案 `preset_color_schemes`，颜色写成 `0xBBGGRR`），和中书自己的 `scribe.yaml`（颜色写成 `#RRGGBB`，一个主题同时带浅色和深色配色）。两种可以同时用，也可以用中书设置把鼠须管格式一键转成中书格式。

本页的键和对照表都来自 `ScribeConfig` 的代码（`ScribeKeyMap`），转换示例是转换器的实际输出。

## 改哪个文件

都放在用户目录 `~/Library/Scribe`，写在 `patch:` 下面，改完在输入法菜单里选「重新部署」：

- `scribe.custom.yaml`：中书格式。
- `squirrel.custom.yaml`：鼠须管格式，从鼠须管导入的就是这个。

中书自带的 `scribe.yaml`（在 `Scribe.app/Contents/SharedSupport`）只有一项 `compatibility/report_as_squirrel: false`，其余全是注释写的说明，一个键都不设，所以不会盖过任何人的鼠须管设置。不要改自带的文件，升级时会被换掉。

## 优先级

同一项设置，后面的盖过前面的：

1. 中书内置的默认值
2. `squirrel.yaml`，加上 `squirrel.custom.yaml` 的补丁
3. `scribe.yaml`，加上 `scribe.custom.yaml` 的补丁：设了的键才盖过鼠须管的，没设的照用鼠须管的值
4. 当前方案的 `style`（比如 `rime_ice.schema.yaml` 或它的补丁里的 `style/...`）：外观相关的键再盖过上面两种

`app_options` 按应用整个替换：`scribe.yaml` 里列了某个应用，这个应用就只用这里写的选项，鼠须管里给它写的选项不再生效；没列的应用照用鼠须管的。

## 颜色

- 中书：`"#RRGGBB"`，或带透明度的 `"#RRGGBBAA"`，按通常的红、绿、蓝顺序，大小写都行。**要加引号**，不然 YAML 把 `#` 当成注释开头。
- 鼠须管：`0xBBGGRR` 或 `0xAABBGGRR`，蓝、绿、红倒过来，透明度在最前面。

比如鼠须管的 `0x75B100` 就是中书的 `"#00B175"`；鼠须管的 `0x80FFFFFF`（半透明白色）是中书的 `"#FFFFFF80"`。主题的 `color_space` 可以是 `srgb`（默认）或 `display_p3`。

## 一个主题，浅色和深色

中书的主题放在 `themes/<主题 ID>` 下面，ID 只能用小写字母、数字和下划线：

- `name`、`author`、`color_space`：主题的名字、作者和色彩空间
- `style`：主题自己的样式，可以设下面「外观」表里的键，`theme`、`dark_theme`、`memorize_size`、`status_message` 除外，两套配色都用
- `light`：浅色配色，`dark`：深色配色（可选）；每套配色也可以有自己的 `style`，盖过主题的 `style`

`appearance/theme` 选主题。系统是深色模式时，用 `appearance/dark_theme` 指定的主题；没指定就用同一个主题的 `dark` 配色；主题没有 `dark` 就一直用浅色。`theme` 也可以写鼠须管的配色方案名，比如 `aqua`、`native`。

## 设置一览

### 通用

| `scribe.yaml` | `squirrel.yaml` | 值 | 说明 |
| --- | --- | --- | --- |
| `keyboard_layout` | `keyboard_layout` | 文字 | 中书激活时用的键盘布局：`last`（不变）、`default`（ABC）或布局名，比如 `USExtended` |
| `chord_duration` | `chord_duration` | 秒 | 并击输入等待其他键的时间，默认 0.1 |
| `notifications` | `show_notifications_when` | `always` / `appropriate` / `never` | 切换中西文、方案时要不要在光标旁提示 |
| `status_icon` | `status_icon/show` | 是 / 否 | 切到中书时在菜单栏显示中西文状态 |
| `report_bundle_id` | `unsafe/report_bundleid` | 是 / 否 | 把当前应用的 bundle ID 告诉 librime（会话属性 `client_app`），给按应用切换行为的 Lua 脚本用 |
| `app_options/<bundle ID>/<选项>` | `app_options/<bundle ID>/<选项>` | 是 / 否 | 某个应用里会话一开始就设上的 Rime 选项，比如 `ascii_mode`、`inline`、`no_inline`、`vim_mode` |
| `compatibility/report_as_squirrel` | （无） | 是 / 否 | 告诉 librime 前端是 Squirrel（鼠鬚管）而不是 Scribe，给只认鼠须管的 Lua 脚本用，见 [从鼠须管迁移](migrating-from-squirrel.md) |

### 外观（`appearance`）

| `scribe.yaml` | `squirrel.yaml` | 值 | 说明 |
| --- | --- | --- | --- |
| `appearance/theme` | `style/color_scheme` | 主题 ID | 浅色模式（和没有深色配色时）用的主题 |
| `appearance/dark_theme` | `style/color_scheme_dark` | 主题 ID | 深色模式用的主题 |
| `appearance/layout` | `style/candidate_list_layout` | `stacked` / `linear` | 候选竖排一列 / 横排一行 |
| `appearance/orientation` | `style/text_orientation` | `horizontal` / `vertical` | 文字横写 / 竖写 |
| `appearance/inline_preedit` | `style/inline_preedit` | 是 / 否 | 输入码显示在光标处，否则显示在候选窗里 |
| `appearance/inline_candidate` | `style/inline_candidate` | 是 / 否 | 光标处显示当前高亮的候选，而不是输入码 |
| `appearance/translucency` | `style/translucency` | 是 / 否 | 毛玻璃背景，背景色半透明时才看得出 |
| `appearance/mutual_exclusive` | `style/mutual_exclusive` | 是 / 否 | 半透明的颜色不互相叠加 |
| `appearance/show_paging` | `style/show_paging` | 是 / 否 | 显示翻页箭头 |
| `appearance/candidate_format` | `style/candidate_format` | 文字 | 一个候选怎么排，用 `[label]`、`[candidate]`、`[comment]`；鼠须管旧写法 `%c`、`%@` 也认 |
| `appearance/font/face`、`appearance/font/size` | `style/font_face`、`style/font_point` | 字体名、点数 | 候选的字体 |
| `appearance/label_font/face`、`…/size` | `style/label_font_face`、`style/label_font_point` | 字体名、点数 | 序号的字体 |
| `appearance/comment_font/face`、`…/size` | `style/comment_font_face`、`style/comment_font_point` | 字体名、点数 | 注释的字体 |
| `appearance/preedit_font/face`、`…/size` | `style/preedit_font_face`、`style/preedit_font_point` | 字体名、点数 | 候选窗里输入码的字体 |
| `appearance/alpha` | `style/alpha` | 0 到 1 | 整个候选窗的不透明度 |
| `appearance/corner_radius` | `style/corner_radius` | 点 | 候选窗的圆角 |
| `appearance/highlight_corner_radius` | `style/hilited_corner_radius` | 点 | 高亮框的圆角 |
| `appearance/padding/horizontal` | `style/border_width` | 点 | 候选窗左右的边距 |
| `appearance/padding/vertical` | `style/border_height` | 点 | 候选窗上下的边距 |
| `appearance/line_spacing` | `style/line_spacing` | 点 | 候选之间的距离 |
| `appearance/preedit_spacing` | `style/spacing` | 点 | 候选窗里输入码和候选之间的距离 |
| `appearance/baseline_offset` | `style/base_offset` | 点 | 文字基线的偏移 |
| `appearance/shadow_size` | `style/shadow_size` | 点 | 高亮的阴影大小 |
| `appearance/highlight_expansion` | `style/surrounding_extra_expansion` | 点 | 其他候选背景的大小 |
| `appearance/memorize_size` | `style/memorize_size` | 是 / 否 | 记住候选窗的大小，减少跳动 |
| `appearance/status_message` | `style/status_message_type` | `long` / `short` / `mix` | 中西文、方案提示用完整名字、简称，还是有简称时用简称 |

主题的 `style` 和配色的 `style` 可以设上表从 `layout` 到 `highlight_expansion` 的键，对应鼠须管配色方案里同名的键（比如 `themes/<ID>/style/padding/horizontal` 对应 `preset_color_schemes/<ID>/border_width`）。

### 主题（`themes/<ID>`）

| `scribe.yaml` | `squirrel.yaml` | 值 |
| --- | --- | --- |
| `themes/<ID>/name` | `preset_color_schemes/<ID>/name` | 文字 |
| `themes/<ID>/author` | `preset_color_schemes/<ID>/author` | 文字 |
| `themes/<ID>/color_space` | `preset_color_schemes/<ID>/color_space` | `srgb` / `display_p3` |

浅色配色 `themes/<ID>/light/…` 对应配色方案 `<ID>`，深色配色 `themes/<ID>/dark/…` 对应配色方案 `<ID>:dark`。librime 和鼠须管格式的工具看到的就是这样两个配色方案：

| 配色里的键 | 鼠须管的键 | 是什么的颜色 |
| --- | --- | --- |
| `background` | `back_color` | 候选窗背景 |
| `border` | `border_color` | 边框 |
| `preedit_background` | `preedit_back_color` | 输入码一栏的背景 |
| `candidate_background` | `candidate_back_color` | 候选的背景 |
| `preedit_highlight_background` | `hilited_back_color` | 输入码里正在转换的部分的背景 |
| `highlight_background` | `hilited_candidate_back_color` | 高亮候选的背景 |
| `preedit_text` | `text_color` | 输入码 |
| `preedit_highlight_text` | `hilited_text_color` | 输入码里正在转换的部分 |
| `candidate_text` | `candidate_text_color` | 候选 |
| `highlight_text` | `hilited_candidate_text_color` | 高亮的候选 |
| `label` | `label_color` | 序号 |
| `highlight_label` | `hilited_candidate_label_color` | 高亮候选的序号 |
| `comment` | `comment_text_color` | 注释 |
| `highlight_comment` | `hilited_comment_text_color` | 高亮候选的注释 |
| `accent` | `accent_text_color` | 插件标成强调的注释 |
| `warning` | `warning_text_color` | 插件标成警告的注释 |

## 用中书设置转换

中书设置的「外观」页发现鼠须管格式的设置（`squirrel.custom.yaml` 或用户目录里自己的 `squirrel.yaml`）时，会显示「鼠须管格式的设置」和「查看并转换…」。点开能看到要写进 `scribe.custom.yaml` 的每一项，按通用、外观、应用、主题分组；点「转换」才会写。转换只写 `scribe.custom.yaml`，鼠须管的文件不改。

怎么对应：

- 通用和外观的每一项按上面的表换成中书的键。和中书自带的 `squirrel.yaml` 一样的值不写。
- `scribe.custom.yaml` 已经设了的键不动，已有的主题也保留。
- 你新加的或改过的配色方案，每个变成一个只有浅色配色的主题：名字、作者、色彩空间和样式照抄，颜色换成 `#RRGGBB`。配色方案名不合主题 ID 规则的（有大写字母、空格、`-` 等），改成小写、其他字符换成 `_`，重名时加 `_2`、`_3`。`color_scheme`、`color_scheme_dark` 跟着换成新的 ID。
- `app_options` 里和自带设置不一样的应用，每个应用整个写一份。
- 中书的格式没法写「不设置」：自带的 `squirrel.yaml` 设了而你的配置去掉的键，转换不了，界面里会单独列出来；保留鼠须管的文件它就照常生效。

转换以后 `scribe.custom.yaml` 优先：再改 `squirrel.custom.yaml` 里的同一项不会生效，以后都在中书设置里或 `scribe.custom.yaml` 里改。想撤销，删掉 `scribe.custom.yaml` 里转换写进去的条目，再重新部署，就回到原样。

## 示例：转换一套鼠须管皮肤

下面是一份常见的 `squirrel.custom.yaml`：一套浅色、一套深色的微信风格皮肤，横排、苹方字体。

```yaml
patch:
  style/color_scheme: wechat_light
  style/color_scheme_dark: wechat_dark
  style/inline_preedit: true
  "preset_color_schemes/wechat_light":
    name: 微信浅色
    candidate_list_layout: linear
    corner_radius: 5
    border_height: 0
    border_width: 8
    font_face: PingFangSC
    font_point: 16
    label_font_point: 12
    back_color: 0xFFFFFF
    border_color: 0xE0E0E0
    candidate_text_color: 0x424242
    label_color: 0x999999
    hilited_candidate_back_color: 0x75B100
    hilited_candidate_text_color: 0xFFFFFF
    hilited_candidate_label_color: 0xFFFFFF
  "preset_color_schemes/wechat_dark":
    name: 微信深色
    candidate_list_layout: linear
    corner_radius: 5
    border_height: 0
    border_width: 8
    font_face: PingFangSC
    font_point: 16
    label_font_point: 12
    back_color: 0x2D2D2D
    border_color: 0x3C3C3C
    candidate_text_color: 0xE0E0E0
    label_color: 0x8C8C8C
    hilited_candidate_back_color: 0x75B100
    hilited_candidate_text_color: 0xFFFFFF
    hilited_candidate_label_color: 0xFFFFFF
```

中书设置转换后写进 `scribe.custom.yaml` 的内容（转换器的实际输出）：

```yaml
patch:
  appearance/theme: wechat_light
  appearance/dark_theme: wechat_dark
  themes/wechat_dark:
    light:
      background: "#2D2D2D"
      border: "#3C3C3C"
      candidate_text: "#E0E0E0"
      highlight_background: "#00B175"
      highlight_label: "#FFFFFF"
      highlight_text: "#FFFFFF"
      label: "#8C8C8C"
    name: "微信深色"
    style:
      corner_radius: 5
      font:
        face: PingFangSC
        size: 16
      label_font:
        size: 12
      layout: linear
      padding:
        horizontal: 8
        vertical: 0
  themes/wechat_light:
    light:
      background: "#FFFFFF"
      border: "#E0E0E0"
      candidate_text: "#424242"
      highlight_background: "#00B175"
      highlight_label: "#FFFFFF"
      highlight_text: "#FFFFFF"
      label: "#999999"
    name: "微信浅色"
    style:
      corner_radius: 5
      font:
        face: PingFangSC
        size: 16
      label_font:
        size: 12
      layout: linear
      padding:
        horizontal: 8
        vertical: 0
```

`style/inline_preedit: true` 没有写，因为中书自带的 `squirrel.yaml` 本来就是 `true`。两套皮肤变成了两个只有浅色配色的主题，用 `theme` 和 `dark_theme` 分别指定，效果和原来一模一样。

想要更整齐，可以手动合成一个同时带浅色和深色配色的主题，共用的样式只写一遍。下面这份和上面的效果相同（候选窗的样式和颜色逐项比较过）：

```yaml
patch:
  appearance/theme: wechat
  appearance/inline_preedit: true
  themes/wechat:
    name: 微信
    style:
      layout: linear
      corner_radius: 5
      padding: { horizontal: 8, vertical: 0 }
      font: { face: PingFangSC, size: 16 }
      label_font: { size: 12 }
    light:
      background: "#FFFFFF"
      border: "#E0E0E0"
      candidate_text: "#424242"
      label: "#999999"
      highlight_background: "#00B175"
      highlight_text: "#FFFFFF"
      highlight_label: "#FFFFFF"
    dark:
      background: "#2D2D2D"
      border: "#3C3C3C"
      candidate_text: "#E0E0E0"
      label: "#8C8C8C"
      highlight_background: "#00B175"
      highlight_text: "#FFFFFF"
      highlight_label: "#FFFFFF"
```

确认没问题以后，`squirrel.custom.yaml` 里对应的几项可以删掉，也可以留着：`scribe.custom.yaml` 设了的键优先。
