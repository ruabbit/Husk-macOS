# 上游功能与 macOS 接入现况

核对日期：2026-10-13（Asia/Shanghai）。上游发布标签 **2.0 = e02ac68**；当前 main **8e79a47** 包含该发布和随后社区兼容性改进。已再次 fetch origin、upstream，远端没有本轮初始快照之外的新提交。fork main 从 f0bd526 快进至 8e79a47，再通过 5866498 真实合入 macOS；没有文本冲突或 ours 策略。

本轮补齐此前仅进入源码树的功能，并在唯一 `build/macos/Product/HuskMac.app` 打包。当前候选版本为 **2.0.0 / build 5**，保留 VM=ON。最终验证、提交与窗口状态以 [progress.md](progress.md) 的最新记录为准。

## 2.0 发布功能

| 上游功能 | macOS 实现 | 验证边界 |
| --- | --- | --- |
| New UI | 原生首页、资料库、Store、帮助四个入口；最近应用、图标、导入入口、外观设置 | SwiftUI 编译与签名通过；前台结果单独记录 |
| Window manager | 独立 AppKit 窗口，显示/最小化/缩放/全屏；每应用启动全屏偏好；当前窗口控制及菜单 | 保留固定画布、真实鼠标事件、默认失焦继续；上游本身也是同时一个引擎窗口，不增加并行游戏限制或假模拟窗口 |
| Christmas decoration | 复用 Holiday.swift 的雪花、雪帽、圣诞树，设置可关闭，减少动态效果时不飘雪 | 动画层不拦截点击 |
| In-app help | 可搜索的 macOS 操作、窗口、输入、存档与常见问题；独立帮助窗口 | 删除不适用的 iPhone JIT 配对操作 |
| Remove downloads tab | 下载进度位于 Store 的“下载”面板，保留取消和导入流程 | 下载/登录共用此前已接入的 PlayAPI；个人账号拒绝问题没有据此关闭 |
| App shortcut | 详情页导出 webloc，husk-macos URL 打开已有资料库条目 | 外部链接不会结束另一个正在运行的游戏；无自动生成桌面文件 |
| 手柄（上轮遗漏） | Java AppRunner 同线程输入、设备 41–44、轴/按钮/热插拔，原生引擎保留共享 pad sink | 真 DEX 与打包 Runner 覆盖失焦/断连/暂停/停止释放；实体控制器未代替为自动化通过 |
| 社区兼容性 | 复用共享查询、缓存、服务回退和手动报告；Mac 报告带真实平台和组件摘要 | 客户端回归与此前线上 GET 通过；没有发送公共报告。iPhone 的 150+ 应用宣传不作为 macOS 验收 |

## 运行链路

| 功能 | 当前 macOS 接入 | 验证与剩余边界 |
| --- | --- | --- |
| Java / Dalvik / Unity 6 | 受控 boot class path、固定 Android 资源、源码构建 framework DEX、32 分包、触摸/键盘/IME/手柄、暂停/销毁和 worker/SQLite 检查；InputEvent 父类 getDevice；随包 Vulkan 与 Java/TextureView 合成 | 生产 fixture、真实 DEX、打包会话通过；Hole.io 已取得真实拖动和黑色洞口证据，关闭/保存重开仍未通过；其他游戏逐个验证 |
| Cocos 无 FMOD、SDL 无 DXVK、Python、Flutter、libGDX、Java、React Native、.NET | 与上游 TLReport.nativeEngine 一致，进入 Java profile | 不因为分类命中就声称插件或真实游戏兼容 |
| Unity 旧版 | 已有独立驱动、固定画布、输入和确认销毁保留 | 旧 Unity IME 仍未接；旧样本黑屏/崩溃不被本轮 fixture 结果覆盖 |
| Cocos + FMOD | 编入共享驱动、JNI 和文本栅格化；原生 profile、触摸/按键/手柄、IME hooks、GL 线程暂停和关闭 | 真实 ELF/ANGLE 与生产会话通过。Cocos 没有 renderer destroy，按其 Android nativeOnPause 保存，再 join/检查 worker；FMOD 线程残留会明确失败 |
| Godot / GameMaker | 编入共享驱动，资料库/Runner 分发，方向与固定画布、触摸/按键、同线程暂停；Godot ondestroy / GameMaker Exit 后关闭 | 真实 ELF 与生产会话通过；缺少 destroy 拒绝回执，暂停失败不会被后续成功销毁覆盖；真实游戏和插件另验 |
| SDL + DXVK | launcher Activity 与分包传递、MoltenVK 配置、SDL/UI 线程生命周期、触摸/按键/手柄、文本 hooks | nativeSendQuit → SDLMain 完成/join → nativeQuit，再检查 worker；正常及缺 destroy 测试通过 |
| Rockstar | 原生 profile、触摸/手柄，Escape 映射 Android Back；同线程暂停、从 DEX 核对无参销毁函数后关闭 | 真实 ELF 与生产会话通过；上游的 Social Club/影片等兼容限制保留，未验证真实 GTA |
| Unreal | UE4 profile 复用真实 NativeActivity/UE JNI 驱动，配置 Vulkan，解析 manifest 与分包 | 含 libUE4 的 Android ELF fixture 走完整打包路径，回调/输入/保存退出通过；真实 Unreal 游戏未验收 |
| NativeActivity | 既有库名/方向/alias、分包、触摸/键盘/手柄与关闭协议保留 | Egg 仍在 libegginc.so 构造函数的未重定位 PLT 跳转失败；没有重复运行未修复样本。PR #82 单例修复已本地采用，PR 未合并 |
| Capacitor / Cordova / Ionic | 独立无 JIT 权限的 WebRunner，复用上游 WebAppRuntime 桥；APK 资源校验/受限提取、原生窗口/IME、返回、暂停定时器/动画/媒体和输入屏蔽 | 两种引擎的真实 WebKit fixture 通过 localStorage/IndexedDB 退出重开、清除后不复现；本地自定义 scheme 的 document.cookie 为空，不宣称 cookie 或 service worker 兼容 |
| Java 内嵌 WebView | 既有 AppKit 固定画布、透明合成与 Java Web 桥 | 使用持久化 WebKit 数据的 Java 会话仍拒绝 native storage-closed；本轮独立 WebRunner 的回执没有偷换到 Java 路径 |
| Minecraft / GameActivity | 既有独立 Runner、固定画布、鼠标修复、存储关闭保留 | 旧的真实样本证据仍有效，但本轮没有启动用户游戏 |
| Geode | 共享 native 模块已编入 Cocos 的链接依赖 | macOS 的 Geode 下载/配置界面与 launcher 注入尚未接入；保持开放，不能用链接成功替代功能 |
| 图形依赖 | 固定 MoltenVK 1.4.2 / SPIRV-Cross，并实际应用上游 zero-init-stride 补丁 | 缓存记录补丁 SHA，打包前拒绝旧缓存，包内附构建记录/补丁；针对随包 MoltenVK 的 workgroup 零初始化 shader 编译回归通过 |

## Web 存档协议

每个 `Saves/<id>/web-store.json` 保存独立 UUID，WebRunner 使用 macOS 14 的 `WKWebsiteDataStore(forIdentifier:)`。数据库由系统 WebKit 保管，不把其数据库文件复制为另一份游戏存档。关闭先发页面生命周期事件，完成脚本顺序屏障，停媒体、卸载文档，等待 cookie/data-record API 回调，再发 `web-storage-detached`。该回执明确为 `webkit-managed`，不是 native 的 `storage-closed/destroyed`，也不声称系统断电时的全局 fsync 保证。监督器核对 session、runtime、UUID 和进程回收。

用户清除存档时，先在同一个 WebRunner bundle 中删除该 UUID 的数据存储，成功才删除标识与资源缓存。失败保留标识；删除过程中禁止同应用重新 prepare。单独移除应用继续保留存档。测试验证进程重开和实际删除，而不只校验 JSON 回执。曾发现静态删除 API 在未初始化 WebKit 的辅助进程中崩溃，已增加独立非持久化 WebView 初始化，并通过删除/重建回归；未反复运行未修复版本。

## 后续开放项

1. Java 内嵌 WebView：将 stable store 与原生 Android 数据目录关联，补 Java 文档销毁与 WebKit 所有权回执、清除数据测试。保留现有拒绝错误保存确认的行为，不能直接复用独立 WebRunner 回执冒充 native 销毁。
2. Geode：复用上游 GeodeSupport 的版本匹配下载，改接资料库的每应用配置，向 Cocos 传入 release/launcher/resources/version，补文件完整性和关闭验证。
3. 真实应用：按独立数据逐个验首帧、交互、保存重开和所需插件；实体手柄、前台 IME、全屏多显示器也需实际设备/窗口证据。禁止在没有相关修复时重复启动已知崩溃样本。
4. Egg：继续核对 DT_INIT/PLT；已知构造函数 RVA 0x1621794 调用 0x16413c0，槽 0x17636b8 仍为 0x1625d90 且没有该槽重定位。2026-10-13 静态检查确认 DT_INIT=0x17a0000，通过槽 0x1798000 调用导入的 ExecuteProgram；尚不能证明其完成所需初始化。NativeActivity 目前提供合成 Activity，未执行自定义 Application 的 Java 启动；不能直接切换到 Java profile，因为 framework 的 NativeActivity 仍是签名 stub。下一步核对 ExecuteProgram 的输入/输出和 Java Application 初始化契约，再设计对应 bridge/fixture；未复跑 Egg，也没有跳过保护或修改用户 APK。
5. 三款游戏修复（2026-10-13）：跨 split/adaptive 图标解析、旧缓存升级、全 NativeRunner profile 的 Android 字体/CA 映射、有界 stderr 首尾保留和独立 supervisor.json 已实现。字体来自同一固定镜像，保留 CJK 和系统别名，旧配置的两个缺失名称在 lock 中记录兼容别名。实际资料库十款图标均已刷新，与隔离解码 PNG 一致，包含 Egg、War、Clash。
   - War Thunder：字体修复后成功生成三种 CJK 字体子集；随后补 `libvulkan.so.1` 映射和通用 NativeActivity 的 MoltenVK 配置。第二次探测的 RVA 0x5875dc4 空缓冲区崩溃进一步定位到 OpenSL 回调：宿主停止/清空操作没有等待正在读取的缓冲区和回调，游戏随后清空缓冲区。已修复排空/队列代际，补通用 NativeActivity 的 FMOD Java HLE。受控生命周期测试通过，第三次探测实际创建 Vulkan 设备/swapchain 并渲染 1280×720 的 Checking the data 加载页，5 项首帧/截图/失焦/暂停/恢复检查通过。
   - War 仍开放：20 秒观察没有进入主菜单，自定义 DagorUpdater 的 getFreeDiskSpace/isInstanceCreated 等方法仍返回未实现结果，需要接真实 Java 启动/更新器路径。停止后进程 exit 0，但没有 storage-closed，仍按失败处理；须追踪原生销毁末尾的进程退出与生命周期确认，不能把 exit 0 或 application destroyed 文本当成存档成功。最新会话 F55D0587，实测截图 `current-war-thunder-repair/frame.png`，解码引擎日志 `current-war-thunder-repair-engine-latest.log`。此次没有证明完整玩法或保存重开。
   - Clash：日志修复后的单次探测输出 5,913,771 bytes，末尾仍保留 `exit(101)` 和 NativeRunner 实际退出 70。退出发生在原生库初始化期间；`JNI_OnLoad+0x12c4c` 是最近导出符号标注，不能当成已执行 JNI_OnLoad 的证据。静态原始 RVA 0x6207bc 为 exit(101) 调用，前置控制流经过 0x61a668；需要继续检查混淆初始化分支及其真实 OS/JNI 前置条件，禁止简单跳过 exit。
   - 日志/静态证据在 `build/logs/current-three-games-audit.json`、`current-icon-repair.log`、`current-war-thunder-repair/`、`current-war-thunder-audio-static.log`、`current-clash-repair/`、`current-egg-init-static.log`、`current-egg-init-relocations.log`、`current-clash-exit-static.log`。自动真实探测静音/不可见，存档位于独立输出目录；三款仍未通过完整运行验收。
6. Play：个人账号/passkey 仍被 Google 拒绝；只有本人真实登录成功且 Play 会话可用才通过。OBB/PAD、设备配置和已购交付验收仍开放。
7. VM/P6：VM Minecraft 黑屏与持续 PCM 未通过；QEMU/libssh/OpenSSL 许可、Android 对应源码和发行签名仍按发行门槛处理。
8. Hole.io（2026-10-13）：InputEvent.getDevice 的父类 JNI 查找与 Java Vulkan 合成已修复，最终 build 5 的后台真实游戏确认拖动、计分、正常黑色洞口以及暂停/恢复。证据在 `build/macos/TestResults/HoleCandidate/`，会话 E86FC7A5。仍需完成可见 AppKit 窗口鼠标拖动验收（CUA 详情导航 native pipe closed）、Unity 进程退出与 SharedPreferences/worker 关闭、保存重开和长期性能。UnityPlayerForActivityOrService 的销毁路径在 mProcessKillRequested 时调用 onUnityPlayerQuitted 后进入 UnityPlayer.kill → Process.killProcess；当前 host 如实保持失败状态。下一步核对该退出请求的真实时序与写入/worker 所有权，补覆盖该行为的 DEX fixture，再运行真实保存重开；不能忽略 killProcess 或直接发 storage-closed。Vulkan 目前同步读回到 Java 合成器，可进一步评估 GPU 共享纹理，但要保留 present 等待和独立 layer 所有权。

检查入口：CMakeLists.txt、Models/NativeLaunch/SessionController、MacNativeDrivers、NativeRunner、WebRunner、WebApp.swift、build_macos_graphics.py；对照上游 TLReport.nativeEngine、TLUnityView.swift、AppWindows.swift、src/app/project.yml 和 Play。后续每日同步须同时交付平台适配、当前候选与相应验证，不能以 Git 祖先或旧测试替代。
