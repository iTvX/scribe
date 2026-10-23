# 鼠须管对照渲染

用鼠须管自己的候选窗代码，把 `Tests/Fixtures/snapshots/cases.json` 里的每个用例画成参考图，供 ScribeUI 的测试对照。

```bash
Tools/squirrel-oracle/render.sh
```

也可以只画几个用例：`Tools/squirrel-oracle/render.sh aqua stacked-vertical-light`。

## 做法

- 从 rime/squirrel 的固定提交（46962d2）下载 `SquirrelTheme.swift`、`SquirrelView.swift`、`SquirrelPanel.swift`、`ReservedProperty.swift`，校验 sha256，放在 `build/squirrel-oracle`，不进仓库。
- `Sources/` 里是这个工具自己的代码：`Shims.swift` 提供上面几个文件需要的 `SquirrelConfig`（从字典读配置）、`SquirrelInputController`（只带注释颜色的序号）和 `?=` 等运算符；`Cases.swift` 读用例；`main.swift` 逐个用例显示鼠须管的面板，再用 `CARenderer` 把窗口的图层（包括蒙版和阴影）合成到 Metal 纹理里，裁出面板的区域，存成 2 倍、sRGB 的 PNG。
- 配置：用例里写的 `style` 和配色，或者 `configs/` 下由 ScribeUI 测试从 `SharedSupport/squirrel.yaml` 和 Max 风格的样本生成的扁平配置。两边读的是同一份配置。
- 预编辑：用例里有预编辑就交给面板，相当于输入法按应用决定不内嵌时的情形。
- 窗口不可见（alpha 为 0），透明度在合成时加上；毛玻璃背景截不到，和中书的渲染一样不画。
- 不管这台 Mac 的屏幕是不是 Retina，都按 2 倍排版和绘制：TextKit 会把行的图层对齐到窗口的像素网格，所以排版时就得是 2 倍。
- 进程里所有屏幕都报告成同一块固定的 1440×900 屏幕（只替换 `NSScreen.frame`，鼠须管的代码不动），行长和窗口位置都不受这台 Mac 的显示器影响；`screen.json` 记录这个尺寸，ScribeUI 对照时用同样的尺寸。
- 窗口位置：按 `Tests/Fixtures/snapshots/placements.json` 里的每个用例，在同一个鼠须管面板里依次显示、隐藏，记下鼠须管每次交给 `setFrame` 的窗口框（AppKit 取整之前）、面板视图的尺寸和内容视图的旋转，写到 `squirrel/placements.json`。ScribeUI 的 `SquirrelPlacementTests` 用同样的步骤驱动中书的候选窗，要求结果一致。

画出来的图和记录的位置在 `Tests/Fixtures/snapshots/squirrel/`，提交进仓库，CI 不运行这个工具。改了 `cases.json` 或配置以后重新运行，检查差异再提交。
