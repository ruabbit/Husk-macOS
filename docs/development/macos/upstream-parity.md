# 上游功能与 macOS 接入现况

核对日期：2026-10-11（Asia/Shanghai）。本轮 fetch 两个远程后，上游 `main` 从 `a08b695` 前进到 `8a9dc1bffc63c2d7cc6c5c3642c8d2ac4ae8bcd0`，共 75 个提交、3,210 个变化路径。本地 fork main 已快进并合入 macOS 工作树；来源锁与 Git 祖先记录本次范围。源码同步和下表的平台接入分别验收。

## 已确认的迁移遗漏

Unity 的上游原生启动入口在 `00ecffb`（北京时间 2026-10-05）加入，Store 在 `bac475a`（北京时间 2026-10-08）加入。它们都已进入 macOS 分支的 Git 历史。此前 macOS 构建与分发遗漏了 Unity；2026-10-10 已将驱动编入 NativeRunner，并接通资料库启动、分包、输入和生命周期。各游戏仍需分别验证。

NativeActivity 的上游 `b7480b6` 同样早已合入，但没有 macOS 入口。2026-10-11 已补完整运行链路和回归，更新 Product 并单次重开；Egg 的具体原生初始化故障仍未修复，不能将入口接入等同于游戏兼容。

| 功能 | 上游实现与来源 | 当前 macOS 接入 | 尚缺的工作 |
| --- | --- | --- | --- |
| Unity 旧版原生驱动 | `husk-tl-unity.c`、共享 loader/JNI/HLE | 已接入独立 Runner；支持新旧 UnityPlayer 接口、32 APK 集合、横竖固定画布、鼠标触摸/键盘/手柄、暂停和销毁确认 | Subway Surf 年龄界面可显示和拖动；Fruit Ninja 黑屏、Hole.io 首帧前崩溃仍待修复；IME、实际玩法和实体手柄未验收 |
| Java / Dalvik、Unity 6 | 上游 `e590b87`、`4313ac0` 引入解释器和 Java 框架，`db2c9e5` 明确将 Unity 6 分发至 `.java` | Dalvik 核心、JNI、图形/GLES、媒体、音频、SQLite、传感器和 WebView 已编入 macOS；未打包 Android boot class path 或接入 `--runtime java` | macOS 仍沿用旧 Unity 分发，不能视为已采用 Unity 6 的新启动链路；须完成下节资源、分发和销毁协议，Hole.io 不重复启动验证 |
| Flutter、GameMaker、Python/Kivy、Web 应用 | 本次上游新增各驱动或 WebKit 路径 | 源码已合并，未接入 macOS 的 Runner / 平台窗口 | 各自补启动、输入、暂停、关闭与对应样本验证 |
| NativeActivity | `b7480b6` 的 `husk-tl-nativeactivity.c`；开放 PR #82 的 Application 单例修复 | 已编译驱动，接入资料库/Runner、32 分包、manifest 库名/方向/alias、触摸/键盘/手柄、同线程生命周期和 join 后的 storage-closed | 当前候选已更新，默认 29 项回归和包校验通过。Egg 在 native 构造函数未重定位 PLT 跳转失败，未到 onCreate 或首帧；前台入口、IME、真实交互与实体手柄未验收 |
| Cocos、SDL、Rockstar、Godot、Unreal | `TLReport.nativeEngine` 已识别，`husk-tl-unity-app.c` 有对应启动分发 | 尚无 macOS 分发；UE4 JNI 仅作为 NativeActivity 共享驱动的链接依赖编入 | 按上游入口逐个接入 macOS，不能仅修改 playable |
| Minecraft / GameActivity | `husk-tl-gameactivity.c` | 已编入，独立 NativeRunner 驱动 | 已有指定样本证据；其他版本和游戏功能仍需对应验证 |
| Play 商店 | `src/app/Husk/Play`，`bac475a` 及后续修复 | macOS 复用 Protobuf、PlayDevice、PlayAPI，使用原生商店窗口、Keychain 和 APK 集合导入 | 个人账号登录失败；已购交付、OBB / 按需 PAD 尚未验收 |
| Play 登录修复 | `ca70a4b` 为两处 auth 请求添加 `droidguard_results` | 两处参数均已同步 | 当前用户遇到 Google 浏览器拒绝；不能通过重复合并这个补丁解决 |
| 图形依赖补丁 | 本轮 ANGLE / MoltenVK 构建脚本与补丁无增量；共享 EGL 增加纹理窗口与同步修复 | 共享 EGL 已编入，保留 macOS 离屏 glFinish / 60 Hz 节流；固定图形二进制未重建 | 更早的 iOS SPIRV-Cross 补丁仍未在 macOS 固定 MoltenVK 二进制中验收 |

核对入口：根目录 `CMakeLists.txt` 的 `GameActivityRuntime` 与 `MAC_PLAY_SOURCES`；`src/macos/SharedLibrary/Models.swift` 的 `runtime`；`src/macos/NativeRunner/main.m` 的参数检查与生命周期；`src/macos/SharedLibrary/SessionController.swift` 的存储关闭判断。上游参照 `src/app/Husk/TranslationLayer.swift`、`TLUnityView.swift` 及 `src/app/project.yml`。

## 后续执行与同步验收

Unity 旧版运行链路已补齐；NativeActivity 源码接入、默认回归和候选更新已完成。继续定位实际游戏问题和其他引擎的 macOS 接入。保留 AppKit 固定画布、真实鼠标事件处理、默认失焦继续、独立 Runner 和正常关闭存储的协议。不能用新增白名单或成功编译替代游戏验证。Play 登录继续核对上游实现和补丁，当前 Chrome 调试连接方案已被 Google 拒绝，不记作已完成。

每日任务除 Git 合并外，还要对照上游引擎列表、Store、登录及依赖构建变化，在同一轮完成迁移范围内所需的编译、分发、生命周期/输入适配和对应验证，更新实际候选后才报告该功能已交付。即使上游没有新提交，已记录的平台接入缺口也仍是待办，继续推进既有迁移范围；不能以“源码已同步”将它们关闭。较大的未完成项保存已实现部分、具体证据和下一步，保持开放并主动继续。每轮更新本文件与 progress.md。原每日 09:00 任务已采用此要求，未新建重复任务。

当前 NativeActivity 候选默认 CTest **29/29** 与 **17 个 Mach-O** 的签名、权限、依赖闭包检查通过。新增四项 NativeActivity 回归覆盖回调线程、暂停/销毁完成、主动 finish、onCreate 异常，并扩充 manifest 元数据层级、AppKit 鼠标、NDK 触摸/键盘/虚拟手柄和旧资料库升级/伪造引擎拒绝。Subway Surf 的年龄界面和输入证据仍来自 2026-10-10；Egg 本轮单次探测失败。Fruit Ninja 黑屏和 Hole.io 首帧失败未复验，真实 Google 账号 / passkey 登录仍未通过。

## NativeActivity 交付与 Egg 下一步

1. 当前 Product 已完成原地打包、默认 CTest 及包校验；新主程序单次启动为 PID 314。CUA 仍无法读取 AX，连接恢复后核对 Egg 详情页运行入口，保留未完成的前台验证。
2. 入口可用不表示 Egg 已兼容；没有相关修复时不要再启动当前会崩溃的样本。继续验证真实游戏的首帧、交互、暂停、保存和回收。
3. Egg 的 libegginc.so 构造函数通过 PLT 槽 `0x17636b8` 跳到原始 `0x1625d90`，尚无该槽为何未重定位的根因。核对 DT_INIT 和上游 loader 变更；保留 APK 与用户数据，不跳过保护或用猜测偏移补丁。证据和精确范围见 [findings.md](findings.md) 的 NativeActivity 段。


## Java / Unity 6 下一步

本轮已实际编入上游共享模块，并修复链接缺少的 Vorbis 解码器。无需重新实现解释器。尚缺以下启动链路，保持待办：

1. 将 `scripts/build_java_runtime.sh` 与 `src/java-framework/build.sh` 从上游作者的绝对路径改为受控资源输入。锁定 libcore / ICU / Conscrypt / framework-res 的来源与 hash，构建 `husk-framework.dex`，补许可证与打包验证；不能读写用户的运行中 Android 磁盘来凑依赖。
2. 复用 `husk-tl-unity-app.c` 的 `java_boot` 顺序，在独立 NativeRunner 增加 Java profile、资源校验、32 分包与 manifest 分发。对齐 `TLReport.nativeEngine` 对 Unity 6、纯 Java、libGDX 等的选择，不能仅扩大资料库可运行判断。
3. `tl_javaapp_set_paused` 当前仅发事件，`tl_javaapp_start` 未提供可 join 的完整停止接口。需要让 `husk.AppRunner` 的关闭完成回到宿主，收束 AppMain / GL / 音频线程，再写 `storage-closed`；保留会话失败时不报保存成功的约束。
4. 接入 AppKit 画布、触摸/键盘、IME 与 WebView 宿主，在独立测试数据上验证首帧、交互、暂停、保存关闭和进程回收后再交付。

前一轮上游合并时，构建测试目标曾通过隐式 PackageMac 依赖提前替换活动候选，随后已增加打包入口进程保护。本轮在用户确认退出后回收空闲残留主进程，通过该保护再更新 Product，没有替换运行中的包。当前单次重开的新进程指向已验证候选；只有前台 AX/可见检查因 CUA 连接失败尚未完成。
