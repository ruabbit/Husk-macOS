# 上游功能与 macOS 接入现况

核对日期：2026-10-10（Asia/Shanghai）。本轮已 fetch origin、upstream 并读取远端 refs。上游 `main` 与 fork `main` 同为 `a08b69551332c6b9f166c2efa1ea28c171082a6c`；macOS 分支已包含该提交，没有待合并的上游提交。源码最新不代表 macOS 功能已经齐全。

## 已确认的迁移遗漏

Unity 的上游原生启动入口在 `00ecffb`（北京时间 2026-10-05）加入，Store 在 `bac475a`（北京时间 2026-10-08）加入。它们都已进入 macOS 分支的 Git 历史。macOS 当前构建只选择 GameActivity 驱动，资料库和 Runner 也只接受 Orbit/Minecraft；Unity 不能运行是平台接入遗漏，不能描述为上游尚不支持。

| 功能 | 上游实现与来源 | 当前 macOS 接入 | 尚缺的工作 |
| --- | --- | --- | --- |
| Unity | `husk-tl-unity-app.c`、`husk-tl-unity.c`、`TLUnityView.swift` | 源码在分支中，未编入或分发到 Runner | 编译依赖、启动分发、画布方向、触摸/键盘、暂停和正常关闭协议，以及实际游戏验证 |
| Cocos、SDL、Rockstar、Godot、Unreal / NativeActivity | `TLReport.nativeEngine` 已识别，`husk-tl-unity-app.c` 有对应启动分发 | 未编入对应驱动，资料库未放行 | 按上游入口逐个接入 macOS，不能仅修改 playable |
| Minecraft / GameActivity | `husk-tl-gameactivity.c` | 已编入，独立 NativeRunner 驱动 | 已有指定样本证据；其他版本和游戏功能仍需对应验证 |
| Play 商店 | `src/app/Husk/Play`，`bac475a` 及后续修复 | macOS 复用 Protobuf、PlayDevice、PlayAPI，使用原生商店窗口、Keychain 和 APK 集合导入 | 个人账号登录失败；已购交付、OBB / 按需 PAD 尚未验收 |
| Play 登录修复 | `ca70a4b` 为两处 auth 请求添加 `droidguard_results` | 两处参数均已同步 | 当前用户遇到 Google 浏览器拒绝；不能通过重复合并这个补丁解决 |
| 图形依赖补丁 | 上游构建脚本和补丁已合并 | macOS 使用自身固定的 ANGLE / MoltenVK 构建 | 每次上游图形修复须检查 macOS 构建是否采用，不能只看源文件存在 |

核对入口：根目录 `CMakeLists.txt` 的 `GameActivityRuntime` 与 `MAC_PLAY_SOURCES`；`src/macos/SharedLibrary/Models.swift` 的 `runtime`；`src/macos/NativeRunner/main.m` 的参数检查与生命周期；`src/macos/SharedLibrary/SessionController.swift` 的存储关闭判断。上游参照 `src/app/Husk/TranslationLayer.swift`、`TLUnityView.swift` 及 `src/app/project.yml`。

## 后续执行与同步验收

优先补 Unity 的 macOS 运行链路，沿用上游 loader/JNI/引擎代码；保留 AppKit 固定画布、真实鼠标事件处理、默认失焦继续、独立 Runner 和正常关闭存储的协议。不能用新增白名单或成功编译替代这条链路的实际验证。Play 登录继续核对上游实现和补丁，当前 Chrome 调试连接方案已被 Google 拒绝，不记作已完成。

每日任务除 Git 合并外，还要对照上游引擎列表、Store、登录及依赖构建变化，检查 macOS 是否实际编入、是否有入口、生命周期和输入是否接通、对应验证是否完成。即使上游没有新提交，已记录的平台接入缺口也仍是待办，继续推进既有迁移范围；不能以“源码已同步”将它们关闭。每轮更新本文件与 progress.md，写明完成的部分和剩余的具体工作。

本轮只核对同步状态并修正后续任务范围，没有修改运行时代码、启动游戏或重新构建。真实 Google 账号 / passkey 登录仍未通过，Unity 尚未接入 macOS。
