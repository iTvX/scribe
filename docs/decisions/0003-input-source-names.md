# 0003 输入源名称

日期：2026-10-23

## 决定

输入源名称跟随系统语言，和鼠须管的做法一致：

| 系统语言 | 简体模式（Hans） | 繁体模式（Hant） |
| --- | --- | --- |
| 简体中文 | 中书 | 中書 |
| 繁体中文 | 中书 | 中書 |
| 英文及其他 | Scribe - Simplified | Scribe - Traditional |

名称写在 `App/Resources/*.lproj/InfoPlist.strings` 里，以输入源 ID 为键。
