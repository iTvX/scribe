# 0004 RimeKit 的串行化方式

日期：2026-10-23

## 决定

设计文档里写的是「RimeKit 用 actor 串行化调用」。实际实现为 `@MainActor` 隔离的 `LibrimeEngine`：所有 librime 调用都在主 actor 上同步执行。ScribeCore 通过 RimeKit 里的 `RimeEngine` 协议使用它，测试时换成 `FakeRimeEngine`。

## 原因

- InputMethodKit 在主线程上调用 `handle(_:client:)`，而且要求立刻返回「这个键处理了没有」。用独立的 actor 就得 `await`，主线程只能阻塞等待，既别扭又容易死锁。
- 主 actor 本身就是一个串行执行器，能起到同样的串行化作用；候选窗和 IMK 适配层也都在主线程上，不需要再跨线程。
- librime 的部署在它自己的维护线程里进行（`start_maintenance`），不会卡住主线程。librime 从其他线程发出的通知，统一转到主队列再交给 `notificationHandler`。

## 影响

- librime 是进程全局的，所以 `LibrimeEngine.shared` 只有一个实例；`setup` 每个进程只调用一次，`start`/`stop` 可以重复。
- 需要访问其他 librime 接口的新代码（读配置、写补丁、恢复用户词等）以扩展的形式放在 RimeKit 里，通过 `LibrimeEngine.api` 调用，同样在主 actor 上。
