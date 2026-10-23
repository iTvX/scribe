# 0009 发行名称和 report_as_squirrel

日期：2026-10-23

## 决定

- librime 的 `distribution_name`、`distribution_code_name` 默认是 Scribe。scribe.yaml 里 `compatibility/report_as_squirrel: true` 时报成「鼠鬚管」和 Squirrel，给检查前端名字的 Lua 脚本用（line 1 的 `ScribeCompatibility`）。
- 这两个名字在 librime 启动时传入，而 scribe.yaml 要部署之后才能读，所以：
  - 每次部署结束后读一次 `ScribeCompatibility`，和当前不一样就存进中书自己的 UserDefaults（`distributionName`、`distributionCodeName`），并且当场重启 librime（`stop` 再 `start`），不用重启进程，也不用提示用户。客户端下一次按键时自动建新会话。
  - 启动时先从 UserDefaults 读，没有就用 Scribe。

## 原因

- 实测 librime 1.17 每次 `initialize` 都会重新设置发行名称（重启后 installation.yaml 里的 `distribution_code_name` 立即变成新的），所以进程内重启就够了，不需要重启输入法进程。
- 存在 UserDefaults 里，启动时第一次部署之前名字就是对的，平常启动不会多重启一次。

## 测试

`App/Tests/DistributionIdentityTests.swift` 用临时的 UserDefaults 套件测存取往返、默认值和损坏的记录，不碰真实的默认设置。
