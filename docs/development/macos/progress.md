# 审计进度

## 2026-10-28：Play 详情与原标志导航，build 22

- 上游 `9519faf..a06a74d` **7 提交/26 路径**，origin 无新增。普通合并 main=`e3b08b8`、macOS merge=`3e5e8c3`；唯一 HuskLogo 修改/删除冲突按上游恢复原标志意图处理。3.1 tag=`7cc583c`，没有整批 ours/theirs。
- 退出空闲旧候选后在唯一 build/macos 构建 **3.1.0/build 22**，Mac 原图标/TabView/头像菜单/设置账号入口、共享新主域及回退、Play 富元数据/描述/独立截图窗口均已接通。中英文各 **766 条**文案打包；旧 Mac 帮助/动态诊断仍有未翻译部分。
- 新离线详情回归验证真实 protobuf/解析器、直接与回退版本号、预取包装、元数据完整性、鉴权错误、下载量溢出边界、富文本安全链接、图片 URL、窄页/空截图布局。实验性 ELF 工具将自建 Android ELF 转成临时签名 dylib，实际 dyld 检查字节/16 KiB/RX-RW 分离通过；未接入 Runner/重定位/代码改写，不代表真实游戏无 JIT。
- 针对性 **6/6（4.06 秒）**；最终默认 **166/166（275.00 秒）**，其中 WebView **48 项（164.83 秒）**、HTTP **5 项（22.16 秒）**。包检查 **18 arm64 Mach-O/406 Java 资源**及两个语言资源通过；iOS 共享 Swift 仅语法检查。日志复用 build/logs/current-upstream-*。
- CUA 单次启动准确 Product，PID **70008**；18 个二进制哈希对照包验证一致，主程序完整路径、原图标/标签导航、11 应用/图标、头像菜单、独立账号登录页及设置账号入口/新社区域名均通过 AX/截图确认，最后返回首页。没有登录/上传、修改偏好、启动用户游戏/VM或碰其他项目 UTM。
- 源码与来源锁已本地验证；提交推送两分支及 hosted CI 待本轮收尾。
- 真实 Play 详情/网络图片和截图操作、真实账号/Keychain、可见中文、WebView 具体交叠/加载中/跨源/真实第三方插件、实体 IME/手柄、Geode/.NET/文件面板/URI、Play/VM/P6 继续开放。War Thunder 仍为更新器完成后的设备黑名单 exit 1；本轮未重跑该游戏、Egg或Clash。

## 2026-10-27：上游 3.1 接入，build 21

起点 `1c9cafe` 工作区干净；Product/build 20/PID 98822 只有主程序，无项目 Runner/VM/构建，其他项目 UTM 保留。前轮 CI 40253576983 重新确认 success。首次 origin SSH fetch 连接被关闭，重试成功；origin 无外来提交，上游 `3b87cbc..9519faf` 新增 **27 提交、66 路径**。普通合并 main=`99169de`，再合回 macOS=`52c17da`，均无冲突。对照 TLReport.nativeEngine、TLUnityView/project.yml、CMake/能力判断/Runner、Play/登录与图形构建，落实本轮 3.1 增量；图形 pin、权限、独立 Runner、固定画布、默认失焦继续和正常关闭协议保持。

Godot Kotlin 别名编入并共用既有文件/目录句柄，修复双表导致跨对象访问不一致、写入结果和过期目录句柄。压缩堆预留移到 NativeRunner 最早入口；共享 font-path、V8 jitless、JNI native 重新注册与 W^X 代码已编入并补对应回归。真 DEX 验证无文本框的中文/emoji、按键和 GL resize/insets/设置 Activity 取消；Mac ⌘T 手动输入接到 Java、旧 Unity 及支持的原生驱动，SDL 补 ASCII/shift 键。APK 主包按 manifest 识别，误导性文件名的完整签名 bundle 回归通过。

新版侧栏、共享 H 标志/启动页、Husk 账号/资料库同步、游玩计时、Store 分类和应用语言已接入。账号复用 Account.swift 服务协议，Mac 使用 AppKit 头像；凭据失败不发布登录身份，Keychain 更新失败不先删除原 token。账号测试仅用拦截 HTTP、临时偏好与凭据，没有真实注册、登录或上传。中英文各 **331 条**资源进入包，语言仅影响本应用和下一次 Runner；旧动态文本/帮助诊断仍有中文，未声称全面翻译。

唯一 `build/macos`、VM=ON 与缓存保留；相关后台 **15/15（11.95 秒）**。最后账号/文案检查改动重建后，最终默认 **CTest 164/164（256.95 秒）**，其中 Java WebView **48/48（161.14 秒）**、回环 HTTP **5/5（21.62 秒）**。新鲜包检查 **18 个 arm64 Mach-O/406 个 Java 资源**及中英文文案通过，启动前逐项摘要一致。共享 Account/HuskLogo Swift 与 Godot C 的 iOS 27/deployment 15 语法检查通过，没有 iOS 真机结论。日志复用 current-upstream-build/targeted/ctest/bundle/ios-syntax 与 validation.json；首轮账号测试的偏好断言错误和意外 SIGTRAP 保留在 account-first.log，已改为临时 suite 检查和显式失败退出。

旧空闲 Husk 经 CUA ⌘Q 退出后确认进程消失。最终唯一 **3.1.0/build 21** Product 通过 CUA 只启动一次，PID **13975**；完整路径、AX/截图确认侧栏、原有 **11 个应用**与图标、账号登录页及同步说明，再返回首页。App SHA-256 `1d13b6ad80dff155c072c113182caf3414876beda173c15cac90db4edc941dfd`，NativeRunner `1ca327f32f405f3a61e2175625ff9b5a392d6589e90926d7ac9b3f88fa6a360a`，framework DEX `e3ed98a47c0a28b573eb986e9c47cede8dd9cb7e87defab916f797c387e64489`。

真实 Godot/Cocos/Flutter/Geode 应用、实体 IME/手柄、真实账号服务、认证 Play 与 VM/P6 继续开放。下一轮继续 WebView 历史恢复与 host-stop、导航/destroy、Activity replacement/recreate、加载中/跨来源和真实插件；本轮未将这些关闭。War Thunder 已知用户日志是更新器完成后的 Vulkan 设备黑名单 exit 1，具体规则仍未知。本轮没有运行用户游戏或 Android VM、操作 USB、修改 APK/存档/Android 磁盘，未向上游发布任何内容。

源码 [fb1e7b0](https://github.com/ruabbit/Husk-macOS/commit/fb1e7b0b0e87724908a5f915ad84d479df54cda9) 与 [main 99169de](https://github.com/ruabbit/Husk-macOS/commit/99169de4e6a419678003d8ab0a6aea6613392d77) 已正常原子推送，两分支远端 SHA 读回一致。[CI 40434410977](https://github.com/ruabbit/Husk-macOS/actions/runs/40434410977) 已 **completed/success**，head=fb1e7b0：构建、包检查、**41 项 hosted 核心回归（48.68 秒）**及 P0 memory/core 均通过；hardware job skipped。每日自动化已通过工具更新到 build 21 与当前 War Thunder/WebView 状态，原聊天、每日 09:00、贡献范围与会话保护约束均保留，提示全文已精确读回。

## 2026-10-26：HTTP WebView 保存与停止交叠，build 20

从干净 `codex/macos-p0=d57d683` 起步，origin/upstream fetch 均无新增；`upstream/main=3b87cbc` 已是 `main=2c3af7a` 的祖先，main 又是 macOS 分支祖先，没有重复合并或冲突。前轮 build 19 的 Actions 40150135195 已确认 completed/success。重新对照上游 TLReport.nativeEngine、TLUnityView/project.yml 与 macOS CMake、资料库/Runner 分发、输入/暂停/关闭、共享 PlayAPI/登录和固定图形依赖，既有接入保持，没有新的上游平台增量。

回环 HTTP + 真 Java DEX baseline 复现导航保存刚进入插件后 host-stop 直接失败，`/saved` 未收到请求（3.13 秒）。现在停止请求接续正在进行的文档保存，立即取消尚未放行的导航，保留 Java 插件与即时 UI 写入，等待同一个保存结果后再销毁 Android/WebKit；原六秒期限不重置，拒绝/超时仍保持最终关闭失败。新测试验证真实 HTTP POST、重定向和历史请求次数、localStorage/IndexedDB、普通 cookie 出站及 Java 插件的跨进程重开，另核对 HttpOnly 对 Java 与页面脚本的可见性；这里只是本机回环服务器与受控 APK，不是第三方 HTTP 应用验收。

HTTP 首轮 **5/5（20.68 秒）**通过；追加晚到 host-stop 不延长原期限的断言后，最终默认 **CTest 155/155（247.80 秒）**通过，其中 **48 项 Java WebView（155.25 秒）**，HTTP 五项共 **20.99 秒**。唯一 `build/macos` 的 **3.0.0/build 20** 完整构建、**18 个 arm64 Mach-O/406 个 Java 资源**包检查通过；共享 Web host 的 iOS 27 SDK/deployment 15 语法检查通过，只有既有弃用警告，不代表 iOS 真机验证。证据复用 `current-upstream-http-baseline.log`、`-http-first.log`、`-build.log`、`-ctest.log`、`-bundle.log`、`-ios-syntax.log` 和 `current-upstream-validation.json`。

初始空闲 Product/PID 99255 经 CUA ⌘Q 后消失，但后续观察出现新空闲 PID 68212，打包保护正确拒绝替换，具体再次出现原因未确定。复核完整路径及无本项目 Runner/VM 后 SIGTERM 正常终止该空闲实例，无需 SIGKILL；保护失败日志保留为 `current-upstream-build-idle-guard.log`。最终包报告的 18 个二进制摘要逐项复核一致后，CUA 单次启动当前 Product/PID **98822**；完整路径、AX/截图确认首页原有 **11 个应用**与可见图标。App SHA-256 `50e320db2c22ec44aa4585d02d68c32203be799f291755667a422850e3da5559`，NativeRunner `31df7c153d21e581609cf992cf815472d110fdc931f0a510da224402a888f04d`，framework DEX `49d738b4b695cb94d23edecb97ca9b4b012b9a26ee523bc9c959f64228e76707`。

昨天用户 War Thunder 的两次真实会话均 exit 1、没有 storage-closed；当前日志已经完成更新器，随后 Vulkan 报设备黑名单并退出。已修正 parity 的现况，旧“更新器未接通”只保留为 10-13 历史证据，具体黑名单命中规则仍未知。今天没有重跑 War/Egg/Clash/Hole.io 或任何用户游戏、启动 Android VM、操作 USB、修改用户 APK/存档/Android 磁盘，其他项目 UTM 保持原状。

源码 [97de762](https://github.com/ruabbit/Husk-macOS/commit/97de7623fca14f5d5e8e8bec4a0d7e48601d225c) 已正常推送，main/macOS 两分支远端 SHA 已读回一致，main 保持 2c3af7a。本批 [CI 40253576983](https://github.com/ruabbit/Husk-macOS/actions/runs/40253576983) 已 **completed/success**，head 为 97de762：构建、包检查、**36 项 hosted 核心回归（48.98 秒）**及 P0 memory/core 通过，build-and-core 用时 5 分 32 秒；hardware job skipped。最终来源锁与交付记录随文档提交保存，远端完整 SHA 在交付时再次读回。下一轮优先验证历史恢复检查与 host-stop 的交叠，再验真实 HTTP/第三方插件；导航保存与逐视图 destroy 的交叠尚无专门回归。Activity replacement/recreate 更多顺序、加载中/跨源页面、页面脚本直接 file URL、非 GET 历史的显式应用恢复及未登记异步任务继续开放；真实游戏保存重开、实体 IME/手柄、Play/VM/P6 边界保持。

## 2026-10-25：导航许可与文档保存边界

从干净 `codex/macos-p0=72f272a` 开始，origin/upstream fetch 均无新增，`upstream/main=3b87cbc` 已是 `main=2c3af7a` 的祖先，没有重复合并或冲突。逐项核对上游引擎分类、TLUnityView/project.yml、macOS CMake/资料库/Runner、输入/暂停/双侧关闭、Store/登录和固定图形依赖，既有接入保持。前轮 build 18 的 CI 40065200939 已重新确认 success。初始空闲 Product/PID 39662 只有 11 应用首页，通过 CUA ⌘Q 正常退出，随后进程消失；没有用户游戏/本项目 VM，不需要强制结束。

修复页面导航绕过 Java WebViewClient、同文档锚点错误保存、旧导航计时器误伤下一文档的边界；已批准的主 frame 重放保留请求属性，文件子 frame 拒绝不再提升为主页面。`didFinish` 不再抹掉已开始的下一次保存；导航期间插件异常即使被 catch 也取消导航并保留最终关闭失败。新文档恢复媒体许可，没有播放音频。真 DEX 新测试发现 WebKit 后退缓存恢复已封闭的文档（persisted=true、closing=true）；现在只对确认封闭且宿主已成功保存的 GET 历史项原位 reload，普通历史加载不重复请求。非 GET 历史项在进入前拒绝并向 Java 报错，保留当前页面，不自动重发 POST。

旧 build 18 的导航拦截反例失败（7.55 秒）；首轮新用例存在 timer/reload 断言时序问题，改成明确文档 token 与 timer 进度后收紧验证。之后 history back 的真实缓存问题经过状态诊断定位并修复。失败证据保留在 `current-upstream-navigation-baseline.log`、`-first.log`、`-second.log` 和 `-diagnostic.log`。最终针对性 **9/9（35.40 秒）**通过；唯一 build/macos 的 **3.0.0/build 19** 完整构建成功，包检查 **18 arm64 Mach-O/406 Java 资源**通过，iOS 27 SDK/deployment 15 共享 Web host 语法检查通过（既有弃用警告）。最终默认 **CTest 150/150（224.02 秒）**通过，其中 **43 项 Java WebView（129.23 秒）**。候选 18 个二进制逐项复核与新鲜包报告一致后，经 CUA 单次启动当前 Product/PID **99255**；AX/截图显示原有 **11 个应用**及图标。启动首次读取为异步加载中的 0 个应用，随后同一实例加载完成为 11，没有重复启动。源码 [963975e](https://github.com/ruabbit/Husk-macOS/commit/963975e1026f5f188a4c0f7a26f8178c4e1791b4) 已正常推送，两分支远端 SHA 已读回一致，main 保持 2c3af7a。Actions [40150135195](https://github.com/ruabbit/Husk-macOS/actions/runs/40150135195) 已 **completed/success**，源码 head 为 963975e：构建、包检查、**36 项 hosted 核心回归（48.66 秒）**和 P0 memory/core 通过；hardware job skipped，不代表实体设备验收。来源锁和本轮交付文档随文档提交保存，最终远端 SHA 在交付时再次读回。

下一轮先补隔离 HTTP DEX 的重定向/历史请求次数、cookie/插件保存重开和导航/host-stop 交叠回归，再验合法真实应用。仍开放：真实 HTTP/第三方插件持久化、Activity replacement/recreate 更多顺序、加载中/跨源页面保存、导航与 host-stop 交叠、页面脚本直接 file URL、非 GET 历史的应用显式恢复；原有真实游戏保存重开、旧 Unity 实体 IME、手柄/前台窗口、Play/VM/P6 等边界保持。未启动用户游戏/Android VM，未操作 USB、用户 APK/存档或 Android 磁盘，也未向上游写入任何内容。

## 2026-10-24：同一 WebView 导航前保存，build 18

从 `codex/macos-p0=8c7b7c8` 开始，先核对工作区、远程和运行进程；`origin` 与 `upstream` fetch 均无新增，`upstream/main=3b87cbc` 已是本地 `main=2c3af7a` 的祖先，本轮没有重复合并或冲突。对照 TLReport.nativeEngine、TLUnityView、project.yml、macOS CMake/资料库/Runner、输入/暂停/关闭、Store/登录和固定图形依赖，没有新的上游平台增量。

本轮推进 Java 内嵌 WebView 的同一视图主文档导航保存。`HuskWeb` 为每个文档维护独立的导航保存状态；主 frame 的 reload/back/forward 以及 Java `WebView.loadUrl` 在替换旧文档前先交付 `__huskPrepareClose()`，等待 pagehide/unload、Java 插件写入和 `event.waitUntil`，成功后才放行导航并在 `didCommitNavigation` 重置状态。失败或 6 秒超时取消导航并保持 `g_detach_failed`，最终 host-stop 不会伪造 `storage-closed`。`file:///android_asset/`、`file:///android_res/` 和一般 file URL 在导航委托中映射到 `huskapp://`，避免 macOS 直接查找 Android 路径；首屏 `about:blank` 不触发保存。页面脚本直接设置 file URL 的导航回调没有单独验收，不能写成已通过。

真实 Java DEX 新增 `navigation-save` 与 `navigation-rejected`：前者通过 Java `loadUrl` 验证旧文档的 localStorage、IndexedDB 和 Java 插件写入，换页后继续运行并在真实进程重开后恢复；后者使用永不完成的 `event.waitUntil`，验证导航被取消、Activity 仍运行且最终 host-stop 失败。两项单独回归通过；含本轮场景的 WebView 组 **36/36（136.66 秒）**通过。重打包后的 Product 再复核两项 **2/2（12.82 秒）**。

唯一 `build/macos` 原位更新为 **3.0.0 / build 18**，保留 VM=ON 与依赖缓存。默认 **CTest 143/143（207.93 秒）**通过；`scripts/verify_macos_bundle.py build/macos/Product/HuskMac.app --output build/macos/bundle-verification.json` 通过，包内 **18 个 arm64 Mach-O / 406 个 Java 资源**。最终 App SHA-256 为 `847efa488ba3e48706520eda91e56aa647ffa8117d416c642bdd984129ea9318`，NativeRunner 为 `8d904f1b632b732b97f21c8732e2a0418d49c6888125853506ad6781687fc1cf`，WebRunner 为 `8cf245602c6e139d3e43f1ee80619fe24e8c95a2fcc157ddc98595631b883074`，VMRunner 为 `b6d73a49a9e3be6d621625a6d0ff9f7915cbaec96d17063f7ace09a6b1040c4a`，framework DEX 为 `49d738b4b695cb94d23edecb97ca9b4b012b9a26ee523bc9c959f64228e76707`。

源码提交 [6d16dda](https://github.com/ruabbit/Husk-macOS/commit/6d16dda) 与交付文档提交 [3389c93](https://github.com/ruabbit/Husk-macOS/commit/3389c93) 已正常推送，远端 SHA 已读回一致。Actions [40065200939](https://github.com/ruabbit/Husk-macOS/actions/runs/40065200939) 已 **completed/success**：构建、包检查和 **36 项 hosted 核心回归（46.68 秒）**通过；hardware job 为 skipped，不代表实体设备、电源、IME 或手柄验收。CUA 只启动一次当前 Product，PID **39662**；精确可执行路径、AX 和截图确认主窗口、原有 **11 个应用**及可见图标。没有启动用户游戏或 Android VM，也没有触碰 VirtIO-XPDM/UTM、Telegram 构建、APK、存档、Android 磁盘或 USB 设备。

同一视图页面脚本直接 file URL、Activity replacement/recreate 的更多顺序、加载中文档、跨来源 frame、真实 HTTP 应用/第三方插件、未登记异步任务与 trusted unload 继续开放；真实游戏正常销毁/存档重开、旧 Unity 实体 IME、实体手柄/前台窗口、Play/VM/P6、Egg/War/Clash/Hole.io 的既有阻塞也没有因 fixture 或 CTest 通过而改变。

## 2026-10-23：上游 bundle 与宿主环境，build 17

从干净 eebd248 起步，Husk/本项目 Runner 与构建均已退出；其他项目 UTM/Telegram 构建保留。origin 无新增，upstream 新增 2df074b..3b87cbc 两提交/10 路径，普通合并 main=2c3af7a、macOS=ef287c0，无冲突。再次审计引擎/CMake/资料库/Runner 输入与暂停关闭、Play/登录、固定图形依赖，没有新引擎或图形 pin。

已补 macOS IOKit 内部电池读取与无电池桌面状态、单次 sticky snapshot；24 小时制复用上游实现。Java 默认语言从共同宿主属性启动；Android TimeZone 实际通过 RuntimeHooks 获取，已在 Application/provider 之前安装 supplier，保留 guest 覆盖/清除语义。macOS 导入器继续使用共享 ZIP64/deflate/OBB 解析，新增 64 KiB 流式写入、CRC/完整长度/压缩流结尾校验、失败清理及既有文件/符号链接保护；单条 512 MiB、总量 4 GiB、50,000 条限制保持。

新增真 DEX 暴露 guest System.out 与 NativeRunner 控制协议共用 stdout 的旧问题。现在控制事件使用带 CLOEXEC 的私有 writer，guest stdout/stderr 进入原有有界诊断。测试保留原始 println、JSON 形状文本和 onDestroy 输出，明确检查日志保留、事件未混入、正常输入/失焦/暂停/关闭与单次 storage-closed。

首轮新测试目标漏链接 MacDiagnostics 已补；首轮针对性 5/15 因 Java GMT 与 native Asia/Shanghai 不一致失败，user.timezone 路径复验仍失败，查阅 Android libcore 源码后改接 RuntimeHooks。后续 17/17（15.84 秒）、包检查和首次默认 141/141（212.82 秒）通过，但新增 fixture println 会污染打包协议，临时改 Android Log 后继续定位并修复真正输出隔离。最终输出/流式针对性 2/2（3.22 秒）通过，最终代码的默认 **141/141（201.91 秒）**及包检查 **18 个 arm64 Mach-O / 406 个 Java 资源**通过。首次失败证据及隔离前完整套件日志保留，中途结果未计作最终交付。日志复用 build/logs/current-upstream-{build,ctest,bundle,stdio-recheck,ios-syntax}.log，汇总 current-upstream-validation.json 与 build/macos/bundle-verification.json。

唯一 build/macos 为 3.0.0/build 17，VM=ON、缓存保留。5 个共享 C/Objective-C 文件 iOS 27 SDK/deployment 15 语法通过，只有命令行重复宏警告；不是 iOS 完整构建/真机证据。本机实时电源为无内部电池桌面，语言 en-US/时区 Asia/Shanghai；中文和法文测试只使用进程参数，未修改系统偏好。MacBook 物理插拔、真实大包/Play 网络交付和游戏兼容仍待验。

最终验证后通过 CUA 只启动一次当前 Product，PID **25881**；进程完整路径、AX 与截图确认首页原有 **11 个应用**及可见图标。App SHA-256 `e5f0f66eb8794a61a451e73c7c552f796cc60fcaafaefc3e322274c63bd53546`，NativeRunner `00dcae150758f307e66ab0589105aa15487c228ec2e3db0807ee5cb1ba9e519a`，framework DEX `49d738b4b695cb94d23edecb97ca9b4b012b9a26ee523bc9c959f64228e76707`。本轮源码 [aa2cdbf](https://github.com/ruabbit/Husk-macOS/commit/aa2cdbf925d67fb30b351e7f10db93947ab0e2a5) 与 main [2c3af7a](https://github.com/ruabbit/Husk-macOS/commit/2c3af7aa599f2ee4d68f6934c145b1ff04f14c15) 已正常原子推送，远端 SHA 读回一致。[CI 39884106041](https://github.com/ruabbit/Husk-macOS/actions/runs/39884106041) 已 **completed/success**：构建、包检查、**36 项 hosted 核心回归（42.59 秒）**与 P0 memory/core 通过；hardware job 跳过，不代表实体设备验收。每日任务已更新并精确读回，保持原聊天/每天 09:00/仅写自己仓库/空闲自动退出及原有保护边界。最后只补交文档与来源记录，不重复构建或启动候选。

真实 WebView 导航/Activity 替换保存、跨源/HTTP 插件、实体 IME/手柄、Geode、Hole.io 关闭/存档、Egg Play 密钥、War/Clash、Play/VM/P6 继续开放。本轮没有启动这些游戏或 Android VM、修改用户 APK/存档/Android 磁盘、检查 USB 或向上游写入。PR #82 当前 GitHub 查询无法解析，不推断合并状态。

## 2026-10-22：上游无变化，单个 WebView 保存与 build 16

从干净的 codex/macos-p0=15c8f1b 开始，两远端 fetch 均无新增；upstream/main=2df074b 已是 main/macOS 祖先，来源锁一致，main=cc99757 保持不变，没有冲突或重复合并。初始 Git 刷新产生的临时 index.lock 已自然消失，未删除锁。对照 TLReport.nativeEngine、TLUnityView、project.yml、macOS CMake/能力判断/Runner、Store/登录和固定图形依赖，没有新引擎或 Store/图形增量。

修复会话继续时直接 WebView.destroy 先移除 Java 对象、导致页面插件失去保存入口的问题。现在普通 WebView API 立即停止，原 Java 对象/插件保留到受控保存完成，再经过 JavaBridge → AppMain 排空回执后卸载。新视图可以继续工作，重复销毁不重复保存，整场停止等待已移出活动视图表但仍在保存的视图；失败/超时不因换了视图而清除。AndroidX WebMessageListener 在 AppMain 实际执行后回执，ReplyProxy 在保存期间仍能回复页面，异常不再被吞掉。空白卸载页不再重新注入插件启动脚本。

唯一 build/macos 原位更新为 **3.0.0 / build 16**，保留 VM=ON 与所有固定缓存。最终默认 **CTest 137/137（190.34 秒）**、其中 **34 项 Java WebView（97.65 秒）**通过；新增 10 项覆盖 direct destroy、无替代视图、重复调用、暂停、保存/插件拒绝、超时、host-stop 交叠及 AndroidX listener 成功/失败，验证真实 DEX/Java 插件和 localStorage/IndexedDB 保存重开。包检查 **18 个 arm64 Mach-O / 406 个 Java 资源**通过。共享 Web host 的 iOS 27 SDK / iOS 15 deployment target 语法检查通过，只有既有弃用警告，不代表 iOS 完整构建或真机验收。

首轮逐视图测试 6/7：stop-race 在替代页尚未加载时关闭，保存脚本未注入而被正确拒绝；该用例改为先确认新页 ready，同时断言旧页仍在异步保存。加载中文档的保存仍开放。加入 AndroidX 后首轮 8/9，定位到空白卸载页重复注入插件启动脚本；修复后 listener/无视图/late-bridge 四项复核 4/4（12.25 秒），随后完整默认套件一次通过。没有更改图形代码/环境/断言，本轮既有 Vulkan 测试均通过。首次证据保留 current-upstream-view-tests.log、view-final.log，最终见 current-upstream-view-message-recheck.log、current-upstream-ctest.log、current-upstream-bundle.log、current-upstream-ios-syntax.log、current-upstream-validation.json 和 build/macos/bundle-verification.json。

CUA 先核对空闲 build 15/PID 18451 的主窗口并正常退出，OS 确认进程消失，无需强退。完整验证后仅启动一次当前 Product，PID **52520**；AX/截图确认首页、原有 **11 个应用**及可见图标。App SHA-256 `b067f8f2ef4bd502bd7c680615d251f2ac17598ebf5226193be97dca0dbf32ec`，NativeRunner `be8f521f82ba4a96ac7063cafa66c3fdc98bd593681f3c67d7459acd52262656`，framework DEX `fd3b65fb0ea00e8feba909a4c91b15d8336f6d65201ec0e3ec5e45c191e4ecc6`。没有启动用户游戏/Android VM、修改用户 APK/存档/Android 磁盘、检查 USB 或向上游写入；其他项目 UTM/构建未触碰。

代码 [54910cc](https://github.com/ruabbit/Husk-macOS/commit/54910cce15f12f4a4def176010c7a04a1686f2d8) 已正常推送自己的 macOS 分支；main 保持 cc99757，两条远端完整 SHA 已读回一致。本批 [CI 39705343544](https://github.com/ruabbit/Husk-macOS/actions/runs/39705343544) 已确认 **completed / success**，源码 head 为 54910cc，build-and-core 用时 **3 分 46 秒**；构建、包检查、**34 项 hosted 核心回归（43.44 秒）**与 P0 memory/core 通过，hardware job 按配置 skipped。每日提示更新并精确读回，保持每天 09:00、原聊天、空闲自动退出及全部边界。最后仅补交文档与来源锁，不重复构建或启动候选。继续开放：真实 HTTP 应用/第三方插件、同 WebView 的导航/页面替换、Activity 替换/recreate 销毁前自动保存、加载中文档、跨来源 frame、未登记异步任务及 trusted unload。真实游戏保存重开、Hole.io killProcess、Egg Play 密钥、Geode/实体手柄/IME、Play/VM/P6 均没有因 fixture 通过获得兼容结论。

## 2026-10-21：上游无变化，guest finish 保存与 build 15

从干净的 `codex/macos-p0=f40ae23` 开始，两远端地址正确，没有其他 Git 操作或本项目构建/游戏/VM。依次 fetch origin/upstream 均无新增，`upstream/main=2df074b` 已是两条分支祖先、来源锁一致，`main=cc99757` 保持不变，没有重复合并或冲突。本轮对照了上游 TLReport.nativeEngine、TLUnityView、project.yml、共享 PlayAPI/登录与固定 ANGLE/MoltenVK 依赖，以及 macOS 的 CMake、能力判断、Runner/输入/暂停/关闭链路；没有新增引擎/Store/图形增量。

最后 Activity 的 `finish()` 和整栈 `finishAffinity()` 现在先交给 NativeRunner 执行既有 Web 保存阶段，再走 phase 10 销毁。AppMain/JavaBridge 继续服务已接受的插件与即时 UI 写入；重复关闭只交接一次。先让已经排队的 Activity 启动完成再复查，保留 `finish(); startActivity(...)`、反向顺序及子 Activity 返回结果。保存开始后拒绝新 Activity 启动/重建。无回调的旧驱动路径保留，`Process.killProcess` 仍是失败。监督器收到首个合法 `stopping` 事件就启动原有 30 秒期限，持续 heartbeat 不延期。

唯一 `build/macos` 原位更新为 **3.0.0 / build 15**，保留 VM=ON 与依赖缓存。最终 **默认 CTest 127/127（143.77 秒）**、**18 个 arm64 Mach-O / 406 个 Java 资源**包检查通过；其中 **24 项 Java WebView 真 DEX 后台回归（63.07 秒）**，新增 11 项覆盖主动关闭/整栈/重复/暂停、插件及 Web 存储重开、保存拒绝/超时/销毁失败、两种替换顺序与子页返回。另有真实子进程验证 30 秒 guest stop 期限，已纳入 hosted CI 核心集合。旧无回调 NativeActivity guest-finish 与打包 Java/NativeActivity 会话也通过。共享 Java C driver 的 iOS 27 SDK / iOS 15 deployment target 语法检查通过，不等于 iOS 构建/真机验收。

首轮针对性 12/13：暂停测试错误地在 paused 状态使用仅供 running 的 evaluate，改为 Activity.onPause 自行 finish 后通过；首次测试编译漏处理 Task.sleep throws 已修正。首轮默认 **125/127（170.01 秒）**，两个既有 Vulkan compositor 因 Metal Internal Error (00000206) 和 GPU timeout 未出合成帧。该二进制仍为 10-19，图形源码/依赖 pin 本轮未变；隔离诊断后，原配置四项 Vulkan **4/4（0.52 秒）**及完整默认复跑通过。没有修改图形实现、默认环境或测试断言，也没有终止其他项目 UTM。底层瞬时 GPU 错误的根因仍未确定，首次证据保留，不写成“已修复 GPU”。

CUA 重新核对空闲 build 14/PID 67505 的主窗口后正常 ⌘Q，进程退出，不需强退。完成验证后按完整 Product 路径只启动一次 **PID 18451**，AX/截图确认原有 **11 个应用**及图标。没有启动用户游戏/Android VM、修改用户 APK/存档/Android 磁盘、检查 USB 或向上游写入。App SHA-256 `b5ef3b893809b617db08c5faf41d71ffcfc6157d6c616f93131ca898e0a1ef2f`，NativeRunner `fc6339195003872a65f0d57cc9b1fd666e30e8f9a85375922946d77b747f4488`，framework DEX `e18716a0f8f890aa78adbcc000fd90d1e9636580c045b8c9ea32c17b3924ec79`。

代码 [c549924](https://github.com/ruabbit/Husk-macOS/commit/c54992447ec80e59de9fd995b3258c2a476e888d) 已正常推送自己的 macOS 分支；main 保持 cc99757。两条远端完整 SHA 已读回一致；[CI 39541085280](https://github.com/ruabbit/Husk-macOS/actions/runs/39541085280) 已确认 **completed / success**，源码 head 正是 c549924；build-and-core 用时 **3 分 38 秒**，构建、包检查、**34 项 hosted 核心回归（42.14 秒）**与 P0 memory/core 均通过，hardware job 按配置 skipped。每日 husk 提示已更新并读回，保持每天 09:00、原聊天与全部保护约束，后续直接读取最新交付记录。最后仅补交文档与来源锁，不重复构建或重开候选。证据复用 `current-upstream-build.log`、`current-upstream-guest-tests.log` / `guest-recheck.log`、`current-upstream-ctest.log` / `ctest-first.log`、`current-upstream-vulkan-*`、`current-upstream-bundle.log`、`current-upstream-ios-syntax.log`、`current-upstream-validation.json` 和 `build/macos/bundle-verification.json`。

最后 Activity/整栈主动 finish 已落地，不再整项列为未实现。仍开放：真实 HTTP 应用/插件、会话继续时直接 WebView.destroy()/页面替换/recreate 的逐视图保存、跨来源 frame、未登记异步任务与 trusted unload。真实游戏保存重开、Hole.io killProcess、Egg Play 密钥、真实 Geode/实体手柄/IME、Play/VM/P6 均未因 fixture 通过获得兼容结论。

## 2026-10-20：WebView 关闭前保存与 build 14

从干净的 `codex/macos-p0=4b1d5b5` 开始，远端地址正确，没有其他合并/构建或本项目游戏/VM。fetch origin/upstream 后均无新增，`upstream/main=2df074b` 已是两条分支的祖先，来源锁一致；`main=cc99757` 保持不变，没有重复合并。本轮推进已记录的 Java 内嵌 WebView 保存阶段。

NativeRunner 现在先在 AppMain/JavaBridge 存活时停止 Web 媒体，保留已接受的插件请求，交付受控保存生命周期并等待显式 `event.waitUntil(promise)`；即时 Java UI 写入先于 Activity 销毁。后续真实卸载抑制重复事件，仍等待 Android worker/preferences/SQLite、WebKit 文档/网络/cookie 与两侧关闭回执。脚本、插件、Promise 错误和超时保留为失败，跨来源 child frame 也明确拒绝，不能凭 Android 已销毁就报保存成功。相应协议与剩余边界见 [upstream-parity.md](upstream-parity.md)。

唯一 `build/macos` 原位更新为 **3.0.0 / build 14**，保留 VM=ON 和缓存。最终 **默认 CTest 115/115（110.75 秒）**、**18 个 arm64 Mach-O / 406 个 Java 资源**包检查通过。新增 8 项 WebView 回归，连同原有 5 项共 **13/13（36.77 秒）**，覆盖真实 DEX/Java 插件与 UI 队列写入、localStorage/IndexedDB 进程重开、单次事件、暂停关闭、插件/Promise/脚本拒绝、6 秒超时、同源与跨来源 frame；迟到桥接的失败检查仍在。完整默认套件同时复验 NativeActivity/Java 生命周期、文件选择器、手柄与其他引擎。共享 Objective-C Web host 使用已安装的 iOS 27 SDK、iOS 15 deployment target 语法检查通过，仅有原先 javaScriptEnabled 弃用警告；不是完整 iOS 构建或真机验收。

本轮先用 CUA 检查空闲主窗口并尝试正常退出；复查时看到相同 Product 路径的新 PID 55410，再确认无 Runner/游戏/VM后自动 SIGTERM，进程退出，未使用 SIGKILL，也未要求用户操作。交付时仅调用一次 CUA getApp 完整路径；该调用超时但实际启动 PID **67505**。确认进程路径后，用已有绑定只读获取 AX/截图成功，主窗口显示原有 **11 个应用**及图标，没有第二次启动。未运行任何用户游戏/Android VM，未修改用户 APK/存档/Android 磁盘、检查 USB 或向上游写入。

主程序 SHA-256 `2b4760ff3f14b6c983c0b7e1d337acb0558e67df1838748368c1c8fdc8cde055`，NativeRunner `5d7bf937614fa10cf2d9ceadc4c2960e2523a37efd3a4288311983fcf32f67cd`，framework DEX `c5a68af371f3d5f22621315243cd9a4b5a44ff7dc6be39e9926b0674e1358268`。证据复用 `build/logs/current-upstream-build.log`、`current-upstream-web-tests.log`（首轮 11 项）、`current-upstream-ctest.log`（最终 115 项）、`current-upstream-bundle.log`、`current-upstream-ios-syntax.log` 与 `build/macos/bundle-verification.json`。

代码 [ee26f7f](https://github.com/ruabbit/Husk-macOS/commit/ee26f7f0bd49b8bb0380e58a65aee8646d04accf) 已正常推送到 origin/codex/macos-p0，main 仍为 cc99757，两条远端完整 SHA 读回一致。对应 [CI 39371120881](https://github.com/ruabbit/Husk-macOS/actions/runs/39371120881) 已确认 **completed / success**，build-and-core 用时 **3 分 43 秒**；构建、包检查、**33 项 hosted 核心回归（12.66 秒）**与 P0 memory/core 通过，hardware job 按配置 skipped。每日 husk 任务已更新并从配置读回，保留每日 09:00、原聊天和全部权限/保护约束；不再把已交付保存阶段整项列为待办。最后仅补交来源与交付记录，不重复构建或重开候选。真实 HTTP 应用/插件、guest 自行销毁、跨来源保存、未登记异步任务和 trusted unload 仍开放；Hole.io 保存重开、Egg Play 密钥、真实 Geode/实体手柄/IME、PS4/VM/P6 没有因本次 fixture 而获得兼容结论。

## 2026-10-19：4 个上游提交、文件选择器与运行时修复（build 13）

从干净的 codex/macos-p0=b6eb031 开始，两远端地址正确、origin 无新提交。只有空闲 Product build 12/PID 13331；其他项目的构建/UTM 未触碰。fetch 得到 cedb01e..2df074b（4 提交 / 29 路径），普通 merge 到本地 main=cc99757，再合回 macOS。3 处 Java 冲突按共享 LoadedApk 的状态处理，保留 custom ClassLoader、provider/NativeActivity 桥与关闭回执。具体实现见 upstream-parity.md 顶部。

macOS NSOpenPanel 与 Java GET_CONTENT/OPEN_DOCUMENT/PICK 已接线，复制到游戏缓存、只读 URI、取消/重复请求和关闭排空均有后台验证。.NET 文件/信号/AOT/dlsym 接入并修复映射记录溢出、部分 unmap 误释放和并发库提取问题；Native HLE 新增方法回归通过。57 个不依赖 PackageMac 的目标编译完成（含 App/Runner），预备 build 13。新测试首轮宏/未知 MIME/异步请求时序失败已定位并修正，未制造可见窗口或崩溃。

先完成 **84/84 源码 CTest（42.29 秒）**及 5 个共享 C 文件 iOS 15.5 SDK 语法检查；候选更新后，最终 **默认 CTest 107/107（72.19 秒）**，没有排除项，原先暂缓的 23 项 Product 回归全部通过。包检查 **18 个 arm64 Mach-O / 406 个 Java 资源**通过。日志复用 current-upstream-build.log、current-upstream-targeted.log、current-upstream-runtime-recheck.log、current-upstream-ctest.log、current-upstream-bundle.log、current-upstream-ios-syntax.log；最终结果在 build/logs/current-upstream-validation.json 和 build/macos/bundle-verification.json。初次针对性正则意外跑到旧 build 12 的 NativeActivity session，未把该成功算入新候选验证。

早期 CUA getApp 超时、重连 native pipe closed，没有发送退出。用户随后明确要求：确认没有游戏或 VM 时自行退出空闲 Husk，正常退出不可用就强制退出，不再请求 ⌘Q。继续时复查旧 Husk 已不在进程表，因此本次无需发送终止信号。保留 VM=ON 与缓存，在唯一 build/macos 原位完成 **3.0.0 / build 13**。CUA 按完整 Product 路径只启动一次，PID **39849**；主窗口 AX 和截图核对原有 **11 个应用**及图标，未启动游戏或 VM。每日任务 husk 已更新并读回，保持每天 09:00、ACTIVE 和原聊天，写明空闲主程序自动退出/强退规则。

主程序 SHA-256 `3abf83fe859e88fa3c18b5f669e4109d3bdb04a443346c56785a04ba56155d8b`，NativeRunner `7ffb4af58be71798c32349b38babeeab30d71821ccf1902b15ee75cb9d2d3100`，framework DEX `3a4cb76fe13b57fbaac6cd66e186a19c44641da6d0304ddfd88cceb41a503319`。

代码合并 [ee5d553](https://github.com/ruabbit/Husk-macOS/commit/ee5d553d4d4eea553d1ff9af5394c0af6f756afb) 与 main [cc99757](https://github.com/ruabbit/Husk-macOS/commit/cc99757e65d3923851e4df383bef186c0d311cd5) 已普通原子推送，两个远端完整 SHA 读回一致。对应 [CI 39185361624](https://github.com/ruabbit/Husk-macOS/actions/runs/39185361624) 已确认 **completed / success**，build-and-core 用时 **4 分 10 秒**；构建、签名/依赖闭包、**33 项 hosted 核心测试（18.11 秒）**与 P0 memory/core 均通过，hardware job 按配置 skipped。CI JSON 和日志复用 current-upstream-ci.json/current-upstream-ci.log。最后仅补交来源锁与验证记录，不再次替换或重启当前候选；工作分支保持 codex/macos-p0。

没有运行 Egg/Hole.io/War/Clash 或其他用户游戏/VM，没有修改用户 APK/存档/Android 磁盘、检查 USB、向上游 PR/issue 写入。Egg 的真实 Play 密钥服务、WebView 保存阶段、真实游戏/实体 IME/手柄/Geode、PS4/VM/P6 等保持开放。

## 2026-10-18：正式 3.0 上游同步与 build 12

从干净的 `codex/macos-p0=b9caa81` 开始，origin 地址和 upstream 地址符合任务要求；无其他合并/构建/游戏/VM。CUA 检查到空闲主窗口后正常退出旧 PID 7656。fetch 后 origin 两分支无外来提交，上游 `a3407fc..cedb01e` 有 64 个提交、82 个路径，正式 `3.0=cffaf8b`。先普通合并到 main **308793d**，再合回 macOS；七个冲突逐项处理，没有 ours 策略、stash、重置或上游写操作。前一提交 b9caa81 的 CI 39061615178 已确认 success。

实际接入旧 Unity 的 MacTextInput/UnityMain 文字提交、退格、完成/取消、多行和 UTF-16 选择偏移；48 个 APK 完整导入与 Runner 加载；共享流式下载；Play/XAPK 的 OBB 与 APK 原子安装、摘要验证、目录映射和 Java/HLE getObbDir。保留 Application attach 后的自定义加载器，同时采用上游 AppComponentFactory。上游 Java 缺类/Unicode/数组上限/资源/Wi-Fi、Godot 4 Compatibility/NativeBridge、外部纹理 shader 重写均进入当前 NativeRunner 和 framework DEX。Mac 首页加入游戏选择及启动/显示窗口入口，装饰限圣诞季；兼容报告可显式选日志、预览/移除并发送快照，默认不附日志。

新增测试中曾发现 Unity fixture 误把类名当类对象、重复 APK 的幂等行为断言错误，以及 D8 优化掉未使用的数组分配；已修正测试本身。真实 ELF 地址一致性回归还发现普通 4 KiB ELF 的只读重定位被 16 KiB 页写权限误分到 RW，而 ADRP 保持 RX；已统一按实际 PT_LOAD 与代码范围分类。该修复与 Go 数据视图、代码指针和 raw syscall NZCV/q8–q15 一并验证，没有猜测游戏地址或绕过保护。测试的首次意外失败均保留日志，没有重复运行未修复的用户游戏。

最终 **19 项针对性回归通过；默认 CTest 103/103（82.65 秒）**。唯一 `build/macos` 原位构建 **3.0.0 / build 12**，VM=ON，**18 个 arm64 Mach-O / 406 个 Java 资源** 的包检查通过；共享 loader/Unity/Bionic 的 iOS 15.5 SDK 语法检查通过。原有签名、固定依赖、关闭/存储协议和默认失焦继续保留。CJK 字体已随 Mac 包提供，不采用上游为精简 iOS 包新增的非固定下载。VM 仍为 32 APK，明确拒绝 OBB；PS4 新 ABI 只进入未打包的宿主测试组件，真实模块和其他差异在 upstream-parity.md 保持开放。

CUA 按完整 Product 路径只启动一次，PID **13331**；主窗口 AX/截图核对原有 **11 个应用**、正确图标和游戏选择后的展示区。进入详情页时报 native pipe closed，一次只读重试也失败，故详情/日志选择操作未声称通过；没有重复启动。主程序 SHA-256 `ca156721f8e0137e9ddd2e924033be1768616d098ca6ec404ba08d434b45fe6a`，NativeRunner `6232396133282a2dbc40b088c14a3574dd89df74b4d95f1de4f3bb5035fd6909`，framework DEX `5668fb5bc1444654996f4a81441afc9e225e2541a8e7f6d04b4361907aff9b68`。

本轮未启动 Egg、Hole.io、War、Clash 或其他用户游戏/VM，没有播放音频、检查 USB 或改动用户 APK、存档与 Android 磁盘；没有发送公共兼容报告。Egg 的真实 Play 密钥服务、个人 Play/passkey、真实游戏保存重开、实体手柄/IME、PS4 和 VM/P6 仍开放。来源锁和功能对齐表已更新。

代码合并 [70c2764](https://github.com/ruabbit/Husk-macOS/commit/70c27644a34822286524216235a1d39ecf0b7773) 与 main [308793d](https://github.com/ruabbit/Husk-macOS/commit/308793d30b8ebc4d7247914bfaa8231e44aee101) 已正常原子推送，两条远端完整 SHA 读回一致；未 force push。对应 [CI 39087010940](https://github.com/ruabbit/Husk-macOS/actions/runs/39087010940) 已确认 **completed / success**，build-and-core 用时 **5 分 12 秒**，构建、签名/依赖闭包、**29 项 hosted 核心测试（19.61 秒）**及 P0 memory/core 通过；实体硬件 job 按配置 skipped，不能替代实际手柄/IME/游戏验收。CI JSON 和完整日志复用 `current-upstream-ci.json`、`current-upstream-ci.log`。最后只补交交付文档，工作分支保持 codex/macos-p0。

证据复用 `build/logs/current-upstream-build.log`、`current-upstream-targeted.log`、`current-upstream-runtime-tests.log`、`current-upstream-runtime-recheck.log`、`current-upstream-ctest.log`、`current-upstream-bundle.log`、`current-upstream-ios-syntax.log`，以及 `build/macos/bundle-verification.json`。

## 2026-10-18：补齐 Egg 所需的软件密钥接收端

在上一轮 Java/NativeActivity 修复后继续追踪实际 APK，确认普通密钥返回后还会触发缺失的 `setEntry(SecretKeyEntry, KeyProtection)`。现已补软件 AES/GCM 导入、不导出字节的句柄及用途/模式/有效期/IV 检查；不支持的硬件/认证/包装密钥要求明确失败。KeyStore 改为 0600 临时文件同步后原子替换，失败保留旧文件和内存条目，损坏文件不再变成空库。详见 [Egg 报告](2026-10-18_reverse-egg-startup-report.md)。

真实 DEX 的八进程测试覆盖导入/重开/真实 GCM 加解密与标签失败、写入和删除失败、目录隔离、删除持久化及损坏文件保护。默认 CTest **97/97（77.84 秒）**、当前候选包检查通过。新增测试只用随机测试密钥，未启动 Egg、修改用户 APK/存档或现有 Android 磁盘。Play 密钥下发服务仍开放，不能写成 Egg 已可运行。

当前候选 **3.0.0 / build 11** 已原地打包，VM=ON；18 个 arm64 Mach-O、406 个 Java 资源校验通过。CUA 正常退出空闲旧实例后，单次打开 Product，PID **7656**，主窗口显示原有 11 个应用。App SHA-256 为 `810a5533490062621abf08f899139ab247b4cee69666a9305fff84c44e44feb6`，本次修改所在 framework DEX 为 `53f535efa0627cca47c631a486ce740e5707cd7da886cda8fbabb70bec1b1107`；NativeRunner 可执行文件未变。证据复用 `build/logs/current-egg-keystore-*`。

已准备单套官方 ARM64 Play Android 对照环境（Emulator 37.2.12，API 35 镜像 revision 9），无窗口/静音冷启动成功。预装 Play 41.3.25 对所需 action 查询返回 **No services found**；未登录、未安装或启动 Egg，随后 guest 正常关机。该环境独立于 Husk VMRunner，路径为 `build/macos/PlayValidation/avd/husk-play-validation.avd`。后续需要可用的实际 Play 服务和用户本人身份验证，不能用导入端回归代替；用户 APK、存档、原 Android 磁盘及 USB 设备均未修改。

前一代码提交 e1d8060 的 [CI 39059495981](https://github.com/ruabbit/Husk-macOS/actions/runs/39059495981) 已读回 **completed / success**；下方“in_progress”为当时记录。


## 2026-10-18 Egg 启动桥与 build 10

用户授权按调查建议修复；基线 eaf9911，工作区初始干净，仍在 codex/macos-p0。通用 NativeActivity profile 已改为真实 Java Application → attachBaseContext/自定义 ClassLoader → providers/Application.onCreate → Java Activity → NDK 入口；UE4 专用路径保留。补 framework NativeActivity、ContextImpl/LoadedApk 的加载器状态、Class.forName 指定加载器派发、同线程窗口/输入/暂停/失败清理及原生销毁确认。SessionController 同时校验 Java Web 存储关闭回执。

实测发现宿主空格目录的 APK 资源 URL 被游戏直接截取为 `%20` 路径，新增精确 Android 安装路径映射；资源、DEX 和原始 APK 读取一致，未复制/修改用户文件。签名 base/split 的实际资料库/Runner 会话在含空格目录通过。新增 6 项回归，覆盖显式 JNI 先于依赖库构造函数、自定义加载器反射安装、provider 次序、NDK 生命周期/输入、guest finish、缺 destroy 和 Java/原生 onCreate 失败。旧诊断测试的临时存档目录也按调用契约补齐。

最终默认 **CTest 96/96，82.91 秒**；包检查 **18 个 arm64 Mach-O / 406 个 Java 资源** 通过。保留 VM=ON 和既有缓存，唯一候选原位更新为 **3.0.0 / build 10**。用户确认 ⌘Q 后已验证旧进程退出；完成验证后 CUA 恢复，仅按完整 Product 路径启动一次，主窗口 AX 显示 **11 个应用**，PID **89011** 对应当前候选。主程序 SHA-256 `3e06f8d165a801ab0dd36653c551317ac25dfb550b53efc43b30ba381454aeb5`；NativeRunner `9acc7371fa0ba65edab4e9cf75443febbf27b6292a6896d4a93f4a09615246f2`。

真实 Egg 每次仅在相关修复后用隔离数据、静音、无可见窗口复测：先发现缺 mPackageInfo，再发现资源路径问题，最终越过两项并成功记录 PairIP JNI_OnLoad。最新阻塞明确为 **KeyStore 缺加密密钥，Play 的 IAntiTamperKeyTransferService 绑定失败**。当前是游戏自带 Google Play 错误页，未进入游戏原生入口；最终 probe exit 0、1813 帧和 Java runtime destroyed 只证明错误页生命周期，不是原生初始化、玩法或存档重开。用户 APK 四份摘要前后一致，未触碰用户存档、Android 磁盘或其他项目的 UTM。

证据在 `build/logs/current-egg-build.log`、`current-egg-ctest.log`、`current-egg-bundle.json`、`current-egg-repair.log`、`current-egg-repair-result.json`，逐步失败与下一步见 [Egg 报告](2026-10-18_reverse-egg-startup-report.md)。修复和提交仅在自己的 fork。Egg 的实际 Play 服务/密钥环境继续开放，不再按“尚缺 Java NativeActivity 桥”重复处理。

代码提交 [e1d8060](https://github.com/ruabbit/Husk-macOS/commit/e1d806049ced39a7d3b6d2ea5ef2135225e71285) 已普通推送到 origin/codex/macos-p0，远端 SHA 读回一致。当前 [CI 39059495981](https://github.com/ruabbit/Husk-macOS/actions/runs/39059495981) head 为该提交，记录时仍 in_progress，不能记为 CI 通过。每日自动化已通过工具更新并从配置读回确认：保留每日 09:00 和仅自己仓库写入范围，Egg 待办改为实际 Play 密钥服务环境；不再重复做已完成的 Java 启动桥。

## 2026-10-18 Egg 启动调查与贡献范围

用户要求调查 Egg 崩溃，并明确以后所有修复仅在自己的 `ruabbit/Husk-macOS` 仓库完成。上游 PR #118 已关闭，fork PR #1 保持已合并；每日 `husk` 自动化已读回确认包含该范围，保留上游只读同步，不重开或更新上游 PR/issue。

当前资料库目标为 Egg, Inc.（`com.auxbrain.egginc`，versionCode 111359）。四个 APK 的摘要与导入索引一致；2026-10-18 01:33 的已有真实会话 `3468A3D8-88FF-43B6-9B12-4CDF84823C8D` 在约 0.625 秒后退出 139，没有首帧。重新检查 ELF 确认首个构造函数通过未绑定槽 0x17636b8 跳到 0x1625d90；136,362 条标准重定位中无该槽和相邻两个槽的条目。独立 LLVM 反汇编进一步确认 ExecuteProgram 所需 JNI 环境/就绪状态依赖 PairIP JNI_OnLoad 建立的 JavaVM；NativeActivity 驱动没有运行 APK 的自定义 Application/类加载器，现有日志只有 PairIP 构造函数完成。启动顺序缺口已具体定位，但初始化成功、首帧和正常存档尚未验证。

此次只调查和记录，未启动游戏、未改 APK/存档、未替换或重启候选、未改运行时代码。源码基线 a0700fe；取证使用原始 APK、现有日志和源码，临时 ELF 反汇编后即回收。证据为 `build/logs/current-egg-diagnosis.json`、`current-egg-jni-init.log` 及既有 startup audit。下一步为 Application/类加载器/JNI/NativeActivity 顺序 fixture 与桥接，再验证前置初始化；不能只改 runtime 标签或跳转地址。完整结论见 [调查报告](2026-10-18_reverse-egg-startup-report.md)。

## 2026-10-17 上游 3.0 运行时修复与 build 9

从干净的 `codex/macos-p0=8fa4003` 开始，确认远端地址、单一工作区、没有未完成 Git 操作或本项目构建/游戏/VM。主程序已退出；系统中其他项目的 UTM/QEMU 不属于 Husk，未触碰。fetch origin/upstream 后，origin 两分支无外来提交，上游 `4c03823..a3407fc` 有 11 个提交、19 个路径。源码版本为 3.0.0，远端没有 3.0 tag，最新发布 tag 仍为 2.0。先普通 merge 到 main **fa9aa3fa349c53d6e00ce5e14f99528c4fba600c**，再合回 macOS，无文本冲突；未使用 ours、stash、重置或清理用户工作。

共享 loader 的运行时/应用库隔离已进入 NativeRunner。Resources 的 Configuration 密度、精简 framework 图像回退、TextView compound drawable 递归修复、View.cancelLongPress，以及 Picture/RenderNode/绘图缓存的位图释放均进入重新构建的 framework DEX。对照 TLReport.nativeEngine、TLUnityView、project.yml、CMake/资料库/Runner、Store/Play 和图形依赖，本轮没有新的引擎/Store 分发项；既有输入、手柄、固定画布、默认失焦继续、正常关闭协议和 Geode 均保留。iOS 的 QEMU/原生共享 JIT 分区、TrollStore 和诊断修复完整合入，但不套用到 macOS 独立 Runner 的内存模型。

新增 7 项后台回归：4 组真实 Android ELF 覆盖 APK/解包目录、同名库两种加载顺序、依赖构造函数/重定位/dlsym/重复加载；2 组真实 Dalvik/Conscrypt 覆盖应用携带冲突 libcrypto；1 组真实 Java Activity 检查资源密度、framework 图片、TextView 子类转发、View 绘图缓存复用和回收、Picture/RenderNode 替换后的像素与 display list 释放。针对性回归 **7/7（2.13 秒）**，完整默认 **CTest 90/90（70.58 秒）**。这批是独立 fixture，不代表微信、Compose 应用或其他真实游戏已验收，也不是长期内存压力测试。

额外预检发现 CI 的 P0 classic harness 未链接上游新增的 `tl_jit_reserve_bottom`，确实复现 undefined symbol。构建脚本已链接真实 husk-tl-xmem 实现，随后在 build/macos 内编译、按既有测试权限签名并执行经典 16 KiB ELF，构造函数/全局重定位通过。4 个共享 loader/JIT/console 文件的 iOS 17 SDK 语法检查通过；iOS 专用 JIT 文件首轮缺 QEMU include 路径，补用现有 QEMU 源码 include 后也通过。未声称 iOS 完整构建或真机验证。

唯一候选 **3.0.0 / build 9** 已原位更新，保留 VM=ON 和依赖/Java 缓存。包检查通过 **18 个 arm64 Mach-O / 406 个 Java 资源**。验证后 CUA 只启动一次完整 Product 路径，主窗口 AX 显示原有 10 个应用，PID **53326** 对应当前候选。主程序 SHA-256 `29408f26de18ad99321223bafaa3ac3c349ca2e0093cef64613652c505c8dfd7`；NativeRunner `205aa11ad5119b8e095da72eed428765b51bbdd61a06cba28feaae365442c4f7`。没有启动用户游戏/VM、播放测试音频或修改用户 APK/存档/Android 磁盘。

本轮 WebView 关闭顺序复核已补入 upstream-parity.md：真实 unload 中 prompt 被压制，单纯提前宿主 close 无效，需保持 Java 桥可用的卸载前保存阶段和单次生命周期交付。该实现及真实游戏保存重开、旧 Unity IME、实体手柄、Geode 真模组、个人 Play 登录、PS4 产品链路、VM/P6 继续开放。fork PR #1 已合并；上游 #118 仍开放草稿无 review；#82 接口仍 404。

证据复用 `build/logs/current-upstream-build.log`、`current-upstream-new-regressions.log`、`current-upstream-ctest.log`、`current-upstream-bundle.log`、`current-upstream-classic-build.log`、`current-upstream-classic-test.log`、`current-upstream-ios-syntax.log`、`current-upstream-ios-jit-syntax.log` 及 `build/macos/bundle-verification.json`。代码 [c24f0ca](https://github.com/ruabbit/Husk-macOS/commit/c24f0ca8c8d9e774449a5a95f16ecfdf0d916b27) 和 main [fa9aa3f](https://github.com/ruabbit/Husk-macOS/commit/fa9aa3fa349c53d6e00ce5e14f99528c4fba600c) 已正常原子推送，两个完整 SHA 读回一致。对应 [CI 38990038463](https://github.com/ruabbit/Husk-macOS/actions/runs/38990038463) 已读回 **completed / success**，build-and-core 用时 5 分 11 秒：应用/helpers 构建、包校验、26 项 hosted 核心测试（含本轮 6 项库隔离/Conscrypt 用例）、P0 memory/core 和共享 iOS 语法检查均通过。hardware job 按配置 skipped，不能替代本机完整 90 项回归或实体设备验收；JSON/完整日志保存为 `current-upstream-ci.json` 和 `current-upstream-ci.log`。最后仅提交交付记录，保留在 codex/macos-p0。

## 2026-10-16 上游 build 120 与 Java WebView 存档（build 8）

从干净的 `codex/macos-p0=ba5ec17` 开始，核对工作区、origin/upstream、未完成操作和本项目进程后 fetch。origin 没有外来新提交；上游 `0695248..4c03823` 只有 `Build 120`，将 iOS 构建号 119 改为 120，发布标签仍为 2.0。对照 TLReport.nativeEngine、TLUnityView、project.yml、CMake、Models、NativeLaunch、SessionController、NativeRunner、Store/PlayAPI 与图形依赖，本轮没有新增上游运行时功能，继续交付已记录的平台缺口。保留手柄、输入/窗口/失焦策略、Geode 和既有引擎接线。

先普通合并到 main [b377a45](https://github.com/ruabbit/Husk-macOS/commit/b377a459de381f3e10dd1b1e66a03cd6db0ec1fc)，再合回 macOS 并完成适配，得到 [b551a50](https://github.com/ruabbit/Husk-macOS/commit/b551a5062cfc9f3df1e352cd5fd51a1ea940f158)。两次合并无文本冲突，没有使用 ours 策略、stash 或清理用户工作。两个分支已正常原子推送并用 `ls-remote` 读回完整 SHA，未 force push。上游在最终读取时仍为 4c03823。

Java 内嵌 WebView 现通过 `java-web-store.json` 与 Android 存档绑定。新存档使用独立 UUID，升级前已有 Android data 的存档保留原来的包级 UUID 并标记 legacyPackage，避免丢失旧关联。清除独立存档先调用同一 NativeRunner bundle 的 WebKit 删除 API，成功才删除存档目录；失败保留 marker 与 Android 数据。旧包级数据可能仍被其他资料库共享，因此清除旧存档只解除当前关联，保留共享 WebKit 字节，下次启动创建独立 UUID。测试冻结旧实现对 `org.husk.webstorage` 的 UUID `C7020BE8-5B59-43B2-8BF2-5A72363F9E96`，核对升级后相同标识、真实重开及删除后的 store 枚举。

原 WebView.destroy() 留下的 WKWebView—configuration—scheme handler 引用环已解除。待回复导航/对话框/资源请求使用带类型的记录，关闭时按类型结束，取消并等待网络回调，阻止迟到 cookie 写入；真实空白文档导航触发一次 pagehide，停媒体并等待 cookie 写入及数据记录回调。Android 销毁与 WebKit 托管独立验证：前者必须完成 AppMain/GL/worker/preferences/SQLite，后者写 web 子回执，未使用 WebKit 时显式 unused。监督器检查启动时、当前磁盘及事件/存档中的 UUID，再等进程回收。WebKit 部分不冒充数据库 fsync。

测试暴露两项需要修复的退出行为。首轮 Java WebView 的 IO worker 没有结束，因为上游 Thread.interrupt0 仍为空；现在 WebView 框架线程池使用有界空闲等待，shutdown 后仍要求实际任务结束。第二项是已经空闲的 SharedPreferences writer 无法被 shutdown 的中断唤醒；现在在串行写队列内排入 shutdown，使 worker 在任务末尾观察关闭状态，保留 awaitTermination 和写入失败检查。新增 preferences-idle 回归覆盖这一时序，未声称任意 guest 线程中断已支持。

完整测试首轮为 81/82：卸载期间 WebKit 自动压掉 prompt，迟到的 Java 插件保存调用没有执行却未被宿主看见。共享 JS 桥现显式报告关闭后调用并拒绝完成回执；新增用例先验证真实 JavaScriptInterface 可保存，再确认 Android 已成功销毁，而卸载后的插件调用使组合回执失败。该路径当前仍不兼容，需要后续设计 Android 销毁前的受控 Web 关闭阶段，不能把拒绝失败写成插件已支持。

最终默认 **CTest 83/83（68.96 秒）**，覆盖五组新增 Java WebView 打包会话（持久化/同包隔离/删除、legacy 关联、Android 销毁失败、标识不匹配、迟到插件调用）及一组 idle preferences 生命周期。额外补入旧 UUID 常量核对后，该 legacy 回归单独再通过（6.85 秒），产品代码未再改变。包检查通过 **18 个 arm64 Mach-O / 406 个运行资源**；共享 Objective-C Web bridge 的 iOS 17 SDK 语法检查通过，只有原有 javaScriptEnabled 弃用警告，不代表 iOS 构建或真机通过。本轮 [CI 38835337776](https://github.com/ruabbit/Husk-macOS/actions/runs/38835337776) 已读回 **completed / success**，head 正是 b551a50：应用/helpers 构建、包检查、共享核心及 Hardened Runtime loader 检查通过；hardware job 按配置 skipped。远端 CI 的核心子集不替代本机 83 项完整运行回归，证据在 `current-upstream-ci.json` 和 `current-upstream-ci.log`。

唯一候选原位更新为 **2.0.0 / build 8**，保留 VM=ON 及三套既有依赖/Java 缓存。打包前 CUA 正常退出空闲 Husk，确认 Product 主程序消失且没有游戏/VM。完成验证后通过 CUA 按完整 Product 路径只启动一次，PID **86539**，主窗口 AX 显示原有 **10 个应用**。主程序 SHA-256 `a5947bcdaa8e8a4a227a8a8e7e740d8507a60748e26b53951740d3db85f6222e`；NativeRunner `257bf6b7e3c19bd834ba16a4dac9963c9aea9e2a0b9859491a969c132628893e`。没有启动用户游戏、播放测试音频、主动制造系统崩溃或修改用户 APK/存档/Android 磁盘。

证据复用 `build/logs/current-upstream-build.log`、`current-java-web-build.log`、`current-upstream-ctest.log`、`current-java-web-legacy.log`、`current-upstream-bundle.log`、`current-java-web-ios-syntax.log` 与 `build/macos/bundle-verification.json`。最终真实 DEX 数据示例为 TestResults 下的 JavaWeb-6958406A（持久化）、JavaWeb-97166CBD（legacy）和 JavaWeb-5A7A0A41（Android 已销毁但拒绝迟到插件）。先前失败记录保留在 JavaWeb-DB516298（worker）和 JavaWeb-F91DECDE（漏报卸载桥接），没有反复运行已知失败的用户游戏。

fork PR #1 已合并；上游 #118 仍为开放草稿，无评论/review；#82 接口返回 404。真实 Geometry Dash/Geode、Hole.io 正常销毁/保存重开、Egg/Clash/War、旧 Unity IME、实体手柄、个人 Play 登录、PS4 产品链路及 VM/P6 继续开放，详见 [upstream-parity.md](upstream-parity.md)。

## 2026-10-15 上游 PS4 宿主与 build 7

从干净的 `codex/macos-p0=6818ad3` 开始，核对 origin/upstream、未完成操作及本项目进程后 fetch 两个远端。origin 没有外来新增提交；上游 `8e79a47..0695248` 共 10 个提交、25 个路径，主要是 PS4 Console ABI/host、JIT arena、手柄快照和 iOS 资料库/界面，iOS build 升至 119。发布标签仍为 2.0。本轮 Android 引擎分发、TLUnityView、Store/PlayAPI 和图形依赖无实质新功能；既有 Java/原生/Web/Geode 链路继续参与全套回归。

先在 main 普通合并上游，得到 [73a6943](https://github.com/ruabbit/Husk-macOS/commit/73a694368e65fbea7b11071a2546a6556589510b)，再合回 macOS 并完成适配，得到 [ca91909](https://github.com/ruabbit/Husk-macOS/commit/ca91909237b602cd14502fef1135ed7276930721)。两次合并无文本冲突，保留已有历史与平台改动。已普通原子推送两个分支，`ls-remote` 读回上述完整 SHA 一致，没有 force push。

ConsoleHostRuntime、MacConsoleProbe 和 5 组后台回归已进入 macOS CMake，CI 的无窗口核心测试集也包含 console 测试。JIT 使用独立 RW/RX 映射和现有 Hardened Runtime 权限，修复大小溢出、环境参数和部分/跨分配释放；真实 arm64 代码在执行别名上运行，VM region 检查确认没有 RWX view。宿主先校验模块 ABI/platform/回调，再创建 JIT；控制器合并支持模拟与数字扳机，暂停释放输入、立即恢复重发持有状态、断连释放，停止后拒绝新输入并允许回收宿主 pump 线程。probe 现在要求模块报告终止并成功回收宿主线程，停止超时不能再返回成功。测试模块不含模拟器/游戏/音频，帧数恒为 0；模块、probe 和测试 fixture 没有打包入 Product。

PS4 仍是开放的平台接入项。公开核心 `Leviidev/AetherPS4@d953592` 有 macOS Husk 模块入口；公开 FEX `220ab1e` 的 `AllocatorHooks.h` 没有核心检测的 `SetJITHostHooks`。未将会退回独立分配 JIT 的配置当作宿主预算协议通过，也未把作者本地路径当成可复现依赖。核心模块线程 detach，主循环返回后即置 STOPPED；新 `husk_console_join()` 只回收宿主线程，不是模块 worker/存档完成回执。进一步追到公开核心 `src/emulator.cpp:665–698`：RunLoop 返回路径只更新游玩时长并关闭 Storage::DataBase，没有停止/join 周期写入 jthread 或 guest workers；停止入口只推送 SDL_EVENT_QUIT，这些是后续关闭协议必须解决的具体位置。下一步的固定来源、FEX hooks、依赖打包、独立 ConsoleRunner/资料库/窗口/输入和真正关闭协议逐项记录在 [upstream-parity.md](upstream-parity.md)。本轮未运行真实 PS4 游戏。

核对远端发现上一轮 [CI 38534659516](https://github.com/ruabbit/Husk-macOS/actions/runs/38534659516) 实际失败于 `macos-play-support` 的 “login persists through credential storage”：测试用 120 ms 等待模拟服务的 80 ms 延时，负载下并不可靠。本轮改用受控 continuation 与返回的 login Task，验证未完成登录、取消后迟到响应和旧搜索响应隔离；产品登录的 generation/cancellation 语义保留。不能据此宣称个人 Google/passkey 已成功登录。本轮代码 [CI 38664636797](https://github.com/ruabbit/Husk-macOS/actions/runs/38664636797) 已读回 **completed / success**，build-and-core 用时 5 分 57 秒；应用构建、包签名/依赖契约、包含 console 与 Play 的核心测试及 P0 memory/core 回归通过。hardware job 按配置 skipped，不代替实体设备验收。完整远端记录复用 `build/logs/current-upstream-ci.json` 与 `current-upstream-ci.log`。

唯一候选原位更新为 **2.0.0 / build 7**，VM=ON，依赖缓存保留。默认 **CTest 77/77（52.93 秒）**，包检查 **18 个 arm64 Mach-O / 406 个运行资源** 全部通过；共享 console/JIT/gamepad C 文件的 iOS SDK 语法检查通过，不能替代 iOS 构建或真机。日志复用 `build/logs/current-upstream-build.log`、`current-upstream-ctest.log`、`current-upstream-bundle.log`、`current-console-ios-syntax.log`；包报告为 `build/macos/bundle-verification.json`。

开工时只有空闲 Husk PID 55811，没有本项目游戏或 VM。CUA 先报 native pipe closed 并请求手动退出；连接随后恢复，经 CUA 发送 ⌘Q 并确认进程消失，无需用户继续处理该问题。完成构建验证后仅通过 CUA 启动一次 Product，主窗口 AX 显示原有 10 个应用，新 PID 73158 的可执行路径与唯一候选一致。主程序 SHA-256 为 `83b36ade7e135ba2912fa0cc90f7035d7e72da977daf40f18e9a381d1d48aac9`，NativeRunner 为 `76530538145ed2e6114a02c22accc4e8f1c3ddc07773a70f6169b451b97faad8`。未启动用户游戏、播放测试音频或修改 APK/存档/Android 磁盘。真实 Geode、Hole.io 正常销毁/保存重开、Java 内嵌 WebView、旧 Unity IME、实体手柄、Play 与 VM/P6 待办均保留。

fork PR #1 已合并；上游 PR #118 本次核对仍为开放草稿、无评论/review。PR #82 的 PR 与 issue 接口均返回 404，仅记录无法确认其当前远端状态，已采用的单例修复保留。

## 2026-10-14 合并 Hole.io 渲染 PR

按用户授权，将 fork [PR #1](https://github.com/ruabbit/Husk-macOS/pull/1) 合入 main，使用普通 merge 并核对预期 head `c87d891b7b36163ef362d0ee8f49d9ab52c09192`。GitHub 读回确认状态为 MERGED，合并提交为 [35f27e9](https://github.com/ruabbit/Husk-macOS/commit/35f27e942bac1de8710a3756bacbdcf42e0bcdf2)。上游 [PR #118](https://github.com/Leviidev/Husk/pull/118) 仍是开放草稿；iOS 真机、帧节奏与性能验证待完成，不要求等待上游接受才合并 fork。该 head 分支继续保留，供上游审查。

本地 main 快进至合并提交，再合入 codex/macos-p0。唯一文本冲突是 Java runtime 的 gamepad/Vulkan include；逐段核对后保留已有受控启动入口、手柄 sink 与正常关闭实现。macOS 已在公开的 tl_javaapp_start 入口配置 Vulkan，自动合并却在内部 start_app 再加一次，故消除重复并保持现有生产文件内容。共享 Vulkan bridge 与 build 6 相同；新增的生产接线只有 iOS 的 TLUnityView 和 husk-tl-unity-app.c，两者均不在 macOS 编译源中。

MacVulkanCompositorTests 改用 PR 的共用回归，删除旧副本。旧测试尝试从同一 queue family 取得两条队列，在 MoltenVK 上实际退回单队列；共用测试明确使用 family 0 和 1，并单独运行 --same-queue，额外覆盖 sRGB 和非 Java 直接显示。PR head 的无窗口真实 MoltenVK 两种模式均通过；整合后的默认 **CTest 72/72（45.41 秒）**，包校验 **18 个 arm64 Mach-O / 406 个运行资源** 通过，iOS Swift 语法解析通过。既有 Geode 代码 a2a6fee 的 [远端 CI](https://github.com/ruabbit/Husk-macOS/actions/runs/38496000094) 已读回 completed/success（hardware job skipped），不代替本次本地完整回归或 iOS 真机验收。

只在既有 build/macos 编译测试目标，未重新打包生产候选。当前 build 6 的主程序及 NativeRunner SHA-256 与来源锁一致，仍分别为 `718f63f07035c1f189c3a97738f3bc0de3b29390ab8b46a8945dae8bd7c0cd6f` 和 `1febf2c7be08ece47c912cfaf72ebee60f2bf89153c305e95b38e2d0b2a8beb5`。仅主程序 PID 55811 处于运行状态；本次 CUA 读取返回 native pipe closed，未据此声称新的前台检查通过。由于 macOS 生产代码没有变化，无需退出或重启现有候选。没有启动用户游戏、修改 APK/存档/Android 磁盘。Hole.io 的可见鼠标拖动、完整销毁/保存重开与性能待办继续保留。

证据复用 `build/logs/current-pr-vulkan-compositor.log`、`current-pr-integration-build.log`、`current-pr-integration-tests.log`、`current-pr-integration-bundle.log` 及 `build/macos/bundle-verification.json`。

## 2026-10-14 上游核对与 Geode 候选（2.0.0 / build 6）

本轮从干净的 `1e737fd` 开始，两次 fetch 后，main、origin/main、upstream/main 仍为 `8e79a47`，origin/codex/macos-p0 没有外来新增提交，祖先关系及来源锁一致。没有新合并或冲突。按每日任务要求，继续完成已有平台缺口。

Geode 现已接到 macOS 资料库与独立 Cocos Runner。共享 `GeodeRelease.swift` 复用上游版本索引和 arm64 launcher 选择，iOS 工程引用同步更新；macOS 只对 Geometry Dash 的 Cocos profile 显示每游戏开关、下载状态、取消和检查更新。按 APK 的 versionCode 选择 Geode，5+ 要求独立资源包，4.x 检查内嵌资源；下载前后验证归档路径、大小、arm64 ELF 和 SHA-256，安装通过同卷原子目录交换提交。匹配的完整缓存可离线启动；失败更新保留旧缓存，停用不会删除模组和存档。下载期间阻止同游戏导入/删除/并发启动，正常退出会取消下载并等待清理。

Runner 启动前重新检查受管目录、游戏摘要、版本和文件哈希，随后把 release、launcher、数据目录和版本传给共享 Geode loader。macOS 启用 Geode 后若 JNI 加载失败，启动会失败，不再悄悄运行没有 Geode 的游戏。共享解压原先只比较文件长度，可能留下同大小的旧库/资源；现改为检查写入和关闭结果后原子替换。保留 Cocos 的输入、GL 线程暂停、join/worker 检查与 storage-closed 协议。

最终默认 **CTest 71/71（50.84 秒）**，包校验通过 **18 个 arm64 Mach-O / 406 个运行资源**。新增 4 组测试：离线索引/缓存/失败更新、真实 Android ELF 构造函数与 JNI 注入、JNI_ERR 拒绝启动、资料库—SessionController—打包 Runner 的完整会话；后者验证首帧、输入、暂停/继续、保存退出、单一 storage-closed 及资源落盘。真实 Geode 和模组没有被自建 fixture 代替为通过。iOS 共享 Swift 文件语法解析及 Xcode 工程格式检查通过，未声称完成 iOS 构建或真机验证。

第一次全套为 70/71：旧资料库测试把周期心跳误认成 step 命令的完成回执。失败会话 ADF83624 的日志依次为 input/ticks=24、周期 status/ticks=24、step status/ticks=32，实际失焦继续正常。现在 automation 的 status/step 支持可选请求标识，测试只等待对应回执，并显式插入不相关状态验证隔离；没有更改默认失焦行为。失败证据保存在 `build/logs/geode-test-race-before.log` 和该会话目录。

开工时只有空闲主程序 PID 90701，没有本项目游戏/VM 或打开的游戏、存档、会话及下载临时文件。CUA 重连两次仍报 native pipe closed；随后按已有退出授权发送 `NSRunningApplication.terminate()` 标准退出请求，返回 true，并确认旧进程消失，再原位打包。未强制终止、未绕过活动包保护。最终通过 CUA 按完整 Product 路径只打开一次，PID **55811**，主窗口 AX 实际读到原来的 **10 个应用**。没有启动用户游戏或 VM，没有播放测试音频；本轮所有运行回归使用仓库 fixture 和独立数据。当前资料库没有 Geometry Dash，前台 Geode 开关、实际网络下载、真实游戏/模组和保存重开仍待验证。

代码 [a2a6fee](https://github.com/ruabbit/Husk-macOS/commit/a2a6feebfd710f167b606577127eb86fe172b5cb) 已正常推送并读回一致，main 保持 8e79a47。 本批 [Native macOS CI](https://github.com/ruabbit/Husk-macOS/actions/runs/38496000094) 已实际启动，记录时 in_progress；本地验证不代替远端 CI 成功。自动化 `husk` 已更新并读回 ACTIVE，仍每天 09:00 回到本聊天；删除了过时的“Java/Unity 6 和多个原生引擎未接入”描述，保留真实游戏、WebView 关闭、个人 Play 登录与 VM/P6 的开放项。

证据复用 `build/logs/geode-build.log`、`geode-tests.log`、`geode-full-tests.log`、`geode-bundle.log`、`geode-ios-parse.log` 和 `build/macos/bundle-verification.json`。主程序 SHA-256 为 `718f63f07035c1f189c3a97738f3bc0de3b29390ab8b46a8945dae8bd7c0cd6f`，NativeRunner 为 `1febf2c7be08ece47c912cfaf72ebee60f2bf89153c305e95b38e2d0b2a8beb5`。渲染修复已有 fork PR #1 和上游 draft PR #118，本轮未重复创建或合并这些 PR。

## 2026-10-13 Hole.io 输入与洞口材质修复（2.0.0 / build 5）

Unity 6000.3.2f1 通过 JNI 在父类 `android.view.InputEvent` 查找 `getDevice()`；原实现只在 MotionEvent/KeyEvent 子类提供该方法，真实日志报 NoSuchMethodError，输入被拒绝。方法已移回父类，两个子类继承。真实 Dalvik/JNI 回归在修改前复现相同错误，修改后通过。

Hole.io 2.55.4 的 `Hole/Mask 2.19` 与 `Hole/Master VFX Shader` 只有 GLES 3.1 和 Vulkan 变体，原 Java profile 实际提供 ANGLE GLES 3.0，洞口使用洋红错误材质。Java 启动现已配置随包 MoltenVK，游戏自行选择 Vulkan。Vulkan SurfaceView/TextureView 使用独立 Metal layer，通过缓存的 Metal readback 接入既有 Java 合成器，处理 BGRA/RGBA、行方向、跨队列 present semaphore、swapchain 替换与 ANativeWindow 引用释放。没有修改 APK 或 shader，也没有为了本游戏谎报 GLES 3.1。同步 readback 有额外成本，120 秒后台探测稳定阶段约 58 帧/秒，不作为长期性能保证。新增 GLES 链接失败日志，只有显式 diagnostics 才导出有界 shader 源码。

完整默认 **CTest 67/67（49.27 秒）**，随包 **18 个 Mach-O / 406 个运行资源** 的签名、权限、架构与依赖核对通过。新增真实 MoltenVK 无窗口回归验证非对称像素、颜色通道、上下方向、跨队列等待、swapchain 替换及 Java/TextureView 的释放行为；输入回归与六项 Java 生命周期回归通过。首次调用构建脚本命中了系统 Python 3.9；随后使用本机 Python 3.14.8 完成全量构建和验证。构建只复用 `build/macos`。

最终 Product 的隔离会话 **E86FC7A5-76EF-463D-9264-6CD6856BD6A1** 使用原始 base/split APK、独立数据、静音和无窗口模式，实际渲染 720×1280。`before-drag.png` 中教程及黑色洞口可见；协议拖动后的 `frame.png` 中教程消失，洞移到广告牌旁，计分变为 1/500。首帧、截图、默认失焦继续、暂停和恢复五项通过。关闭仍失败：Unity 销毁路径请求 Process.killProcess，没有 storage-closed，SharedPreferences 关闭和残留 worker 未通过，因此整次会话的 result.json 保留 failed，不能写完整游戏兼容或保存重开通过。此前 120 秒 JavaAppProbe 的退出码同为 72；没有为通过测试伪造生命周期回执。

用户授权结束旧游戏后，CUA 点击旧 Hole.io 窗口关闭按钮；确认 Runner 退出后，重新核对空闲 Husk 无数据/网络句柄，结束无法通过 CUA 退出的残留主程序，再原位打包。新候选通过 CUA 只打开一次，PID 90701，已读到包含十款应用的首页 AX；详情导航、截图随后再次返回 native pipe closed。**新候选的可见窗口鼠标拖动未验收**，后台协议输入不替代该项。没有再启动可见游戏，没有清理或手工改写用户存档。

证据：`build/logs/current-hole-input-before.log`、`current-hole-input-after.log`、`current-hole-vulkan-regression.log`、`current-hole-final-checks.log`、`current-hole-candidate-probe.log`、`build/macos/TestResults/HoleCandidate/` 和 `build/macos/bundle-verification.json`。主程序 SHA-256 为 `ef19a7c3285ef2e353254e1dc44b06146406e817f197c5871eaef861ab6a7229`，NativeRunner 为 `e966fba4cb3926c8da43b98d833e29aad9ed9e180fa58efbef90110b2e6e16f5`。真实样本诊断工具 JavaAppProbe 是显式调用的有时限工具，不加入默认 CTest；拒绝复用已有 data 目录。

## 2026-10-13 三款游戏修复候选（2.0.0 / build 4）

已修复跨 split 图标和 adaptive XML 被当成图片缓存的问题。实际资料库 10 个图标均自动刷新为 PNG，与隔离解析结果逐字节一致；最终 CUA 主窗口截图确认 Egg、War Thunder、Clash 及其余图标正常。没有改写资料库索引、应用名称或设置。

所有 NativeRunner profile 现在先校验并配置固定 Android 字体/CA 资源。保留 210 个字体名称、CJK 和 XML 引用，兼容别名写入依赖锁，原始 NOTICE 同包保存。通用 NativeActivity 配置 MoltenVK，libvulkan.so.1 使用相同 Vulkan handle/可用性检查，并注册既有 FMOD Java HLE。新增 OpenSL 停止/清空排空：等待正在读取的缓冲区和已开始的回调，避免游戏释放缓冲区后仍被访问；队列代际保护新入队内容，暂停中的完成回调仍能补充缓冲区供恢复使用。新增受控回归覆盖这些竞态，不播放音频。

War 三次自动探测分别对应字体、Vulkan、音频修复，均不可见、静音、使用独立数据。最后会话 F55D0587 实际渲染 1280×720 的 Checking the data 加载页；首帧、截图、默认失焦继续、暂停、恢复 5 项通过。此前 OpenSL 回调的空缓冲区崩溃未再出现。20 秒观察未进入主菜单，自定义 DagorUpdater Java 方法仍未接通；停止后进程 exit 0，但没有 storage-closed/终态回执，监督器仍如实判失败。最新候选在该探测后补了 Vulkan 状态帧数和暂停补队列行为，由最终回归覆盖，未重复启动真实游戏。没有证明完整玩法、音频输出或保存重开。

Clash 在一次日志修复后的探测中输出 5,913,771 bytes；新的首尾轮转和 supervisor.json 保留原生初始化 exit(101)、Runner 实际退出 70、storageClosed=false。Egg 未再次启动，静态证据确认 DT_INIT 经 ExecuteProgram 后仍有未重定位 PLT 初始化问题，Java Application/NativeActivity bridge 仍需补。具体偏移、证据和下一步见 upstream-parity.md。

最终完整默认 CTest **66/66（53.85 秒）**，verify_macos_bundle.py 通过 **18 个 arm64 Mach-O** 的签名/依赖/权限核对和 **406 个运行资源**。唯一候选仍为 `build/macos/Product/HuskMac.app`，保留 VM=ON。CUA 退出通道反复 native pipe closed；每次重新确认仅空闲主程序、无游戏/VM、无导入/安装操作和打开的用户数据后，按已有授权 SIGTERM 空闲残留并确认退出，再原位打包。最终通过 CUA 打开一次 Product，PID 87531，已读取首页 AX 与真实截图；没有启动可见游戏窗口。此前资料库详情导航受 CUA 断开限制，首页截图不能替代该项交互验收。

资料保护核对：437 个原始文件中 435 个 SHA-256 一致，包含全部 APK、索引及其余保存内容。War 的错误时间标记消失、last_debug 更新，另新增一份引擎日志和两份字体缓存；时间均对应 18:23 主界面会话 7F02AF51（headless=false），区别于 18:14 已结束的后台探测。该会话由独立 supervisor/events 记录确认；没有擅自还原用户会话文件，也不能声称所有文件均未变。自动探测的数据目录与日常资料库独立。

证据复用 `build/logs/current-game-repair-result.json`、`current-game-repair-tests.log`、`current-game-repair-bundle.json`、`current-war-thunder-repair/frame.png`、`current-war-thunder-repair-engine-latest.log` 和 `current-clash-repair/`。主 App SHA-256 为 `01170b6bb984da775950a5731c2b4b21cad742ea919e71ea8c635d4749d5f1c9`，NativeRunner 为 `acb0f33fa5460b28b8b9716f39fb2c390c47975039ac6d802a7f4484828cb365`。

修复代码 [9eb9970](https://github.com/ruabbit/Husk-macOS/commit/9eb9970df52c1f6100e1c23dc75e9495a1f2f052) 已正常推送并读回远端一致，main 仍为 8e79a47；保持 codex/macos-p0，无 force push。旧 2.0 代码的 CI 38374832136 已通过，本批 [CI 38386696549](https://github.com/ruabbit/Husk-macOS/actions/runs/38386696549) 已实际启动，记录时 in_progress，不能提前记为通过。三款完整运行兼容仍开放。

## 2026-10-13 Husk 2.0 候选验证完成

上游发布标签 2.0 为 e02ac68；当前 main 为 8e79a47，包含发布与随后社区兼容性更新。origin/main 从 f0bd526 对齐到本地 main=8e79a47（3 提交、10 路径），再经真实合并 5866498 进入 macOS；没有文本冲突或 ours 策略。收尾前再次 fetch 两个远端，没有新提交。以下是本轮最终实现与验证，替代上午的“38 项、待退出/打包”状态。

2.0 的首页、资料库、Store、帮助导航、最近应用、外观、圣诞装饰、独立窗口管理、按应用全屏偏好和启动快捷方式已进入 macOS。下载进度改为 Store 面板。共享社区查询/缓存/回退和手动报告保留 macOS 来源，未提交公共报告。Java 手柄接 AppRunner 所属线程，包含设备 41–44、按钮/轴、热插拔和断连/失焦/暂停/停止释放；真实 DEX 与打包会话验证完成。没有把 iPhone 的 150+ 游戏宣传当作 macOS 兼容结论。

新增 Cocos+FMOD、Godot、GameMaker、SDL+DXVK、Rockstar 的原生 profile，以及 Unreal 的 NativeActivity 路径。实际共享驱动编译、资料库判断、Runner 分发、输入、GL 线程暂停、销毁/join、worker 与存储回执一并接入。失败状态保持 sticky，后续成功销毁不能覆盖早先 JNI 失败；缺少销毁入口不会伪报保存成功。六条路径均用本仓库 Android ELF fixture 经过实际打包 Runner 验证，真实商业游戏另行验收。

Capacitor/Cordova 使用独立 WebRunner，复用上游 WebAppRuntime，增加原生窗口、菜单/输入法、返回、暂停及独立 WebKit store。localStorage/IndexedDB 写入、进程退出重开、清除后不复现均经真实 WebKit 验证。回执为 web-storage-detached / webkit-managed，明确区别于 native storage-closed，不声称 WebKit 提供断电 fsync 保证。未初始化 WebKit 时直接删除 store 的崩溃已修复；失败测试留下的 4 个已知 fixture store 也通过修复后的 helper 清理，没有触碰用户存档。隐藏页面的定时器会被 WebKit 节流，测试先观察实际 tick 后验证暂停与恢复。

固定 MoltenVK/SPIRV-Cross 已实际应用上游 zero-init-stride 补丁；构建记录、补丁哈希和许可证随包保存。针对实际包内 MoltenVK 的 Vulkan workgroup 零初始化 compute shader 编译回归通过。CI 图形缓存键包含补丁内容，避免后续上游补丁变化继续命中旧缓存。

唯一候选仍为 build/macos/Product/HuskMac.app，版本 **2.0.0 / build 3**，HUSK_BUILD_VM=ON。完整构建通过，默认 **CTest 61/61**（39.38 秒），verify_macos_bundle.py 通过 **18 个 arm64 Mach-O** 的签名/依赖/权限核对和 **194 个 Java 资源**。主 App 与 WebRunner 无 JIT entitlement，执行内存权限仍限定在相应原生 helper。日志复用 build/logs/current-2.0-build.log、current-2.0-tests.log、current-2.0-web-cleanup.log，结构化包证据为 build/macos/bundle-verification.json。

用户已正常退出旧候选，本轮没有绕过活动包保护。CUA 按完整 Product 路径只启动一次，实际 PID 68836 指向当前候选。已读到新首页初始 AX 和商店完整截图/应用列表；随后导航请求先被工具的“user changed”状态保护拒绝，再次读取报 native pipe closed。因此资料库加载后详情、帮助页、前台 IME 和窗口调整尚未完成可见验收，不能冒充通过；没有再次重启。没有运行用户游戏或本项目 Android VM、播放测试音频、修改用户 APK/存档/Android 磁盘。

候选主程序 SHA-256 为 17eb20da8de8bbf5d45d51d52306fa5c356df7ced3543c9dac46a1e76a698431，NativeRunner 为 9e691aac0103d12355f3aac704d8e580d1f5fdd893d30e69f32dd71029bf3add，WebRunner 为 30a4eb4fb232d73cc6ebf869d1fbb2fe509c5a22dca3b839353700527bfe9695。

本地交付门槛已通过，代码提交 [dfd7f6f](https://github.com/ruabbit/Husk-macOS/commit/dfd7f6fa7c4091daf16825cfadbe5dc248ac6809) 已正常推送。远端读回确认 origin/main=8e79a47b3f771eddd005bf338749e01a96443689、origin/codex/macos-p0=dfd7f6fa7c4091daf16825cfadbe5dc248ac6809；保持 codex/macos-p0，没有 force push。新的 [Native macOS CI 38374832136](https://github.com/ruabbit/Husk-macOS/actions/runs/38374832136) 已实际运行，记录时为 in_progress，不能提前写成通过。其后文档交付记录不改变候选代码。Java 内嵌 WebView 关闭、Geode 配置/下载接入、真实引擎/实体手柄、Egg 初始化、个人 Play/passkey 登录、VM/P6 继续开放，具体证据和下一步见 upstream-parity.md。

## 2026-10-12 上游同步与 Java 运行链路

开始于干净的 `12f3cc0`，origin 两分支无新增，无 Husk/Runner/本项目 VM 或竞争构建。上游 `8a9dc1b..f0bd526` 共 70 个提交、139 路径；本地 main 快进，再合入 macOS，没有文本冲突。上游本轮 Java/Dalvik、bionic、WebView、preferences、GLES 等更新实际进入当前构建；Store/PlayAPI 与固定图形依赖无增量。原 macOS 输入、固定画布、默认失焦继续、分包和生命周期适配保留。首次链接发现上游 Java 的 `tl_manifest_gles` 被放在未编入的 SDL driver，已拆为共享模块并补 UTF-8/UTF-16、stripped resource ID 和损坏边界测试。

Java 依赖从固定的原始 Lineage vda-v12 缓存只读提取，校验镜像 SHA-256、大小和无 backing file；没有使用或写入用户 Android 磁盘。新增 JDK 21 / D8 hash 固定、生成源码一致性检查、framework DEX 构建、资源清单校验与打包。最终包含 194 个文件，约 96 MB；原始 ART/ICU/Conscrypt/tzdata/system NOTICE 同包保存，完整对应源码与发行许可仍未完成。临时 raw/system/APEX 提取文件清理；保留一套 JavaRuntime 缓存和唯一 Product。`build_macos.sh` 现在复用或准备依赖，CI 增加工具/SDK/资源缓存，`actionlint` 通过；远程新 CI 未验证。

独立 NativeRunner 新增 Java profile，使用真实 Dalvik boot、manifest 元数据、32 分包、AppKit 固定画布、触摸/键盘/IME 提交桥接，以及隔离数据路径。资料库与 Runner 对齐上游 Unity 6、普通 Java、Cocos（无 FMOD）、SDL（无 DXVK）、Python、Flutter 等分发。旧 Unity 导入只读复扫并缓存结果，避免 Hole.io 等旧记录继续走过时 driver；不在列表读取时重写索引或存档。

暂停回执在 Activity 回调返回后发出；正常关闭需 Activity/Service 销毁、SharedPreferences 写入、AppMain/GL/混合器 join，以及 Java/原生 worker 完成（含 pthread_exit 后 TLS 析构）。关闭后禁止新建 guest worker。SQLite 连接和语句显式关闭，未完成事务不会被擅自 commit，也不会获得正常回执。Java 异常、失败写入、残留线程、SQLite 未完成或进程提前退出均按失败处理。WebView 已绑定 AppKit 容器，后台不创建上游 harness 的可见窗；WebKit 数据进程持久化确认仍缺，因此使用过 website data store 的会话不会被伪报 storage-closed。

最终默认 **CTest 40/40**，包验证通过 **17 个 Mach-O** 和 **194 个 Java 资源**。新增真实 DEX 的 boot、生命周期正常/销毁异常/写失败/残留线程/未提交 SQLite、原生 worker/TLS、生产资料库—SessionController—打包 Runner 会话；后者验证首帧、实际触摸/键盘回调、失焦继续、暂停/恢复、最终 preferences 持久化、单一关闭回执和进程回收。扩充 AppKit NSEvent、输入法组合文字和旧索引升级。容器缩放新增测试最初因精确比较浮点数误报，改为与其他画布检查相同的误差界限后通过。没有可见游戏窗口、音频、用户 APK 运行或主动 native crash。

当前候选已在唯一 `build/macos` 原地构建，保留 `HUSK_BUILD_VM=ON`。通过 CUA 按 Product 完整路径只打开一次，实际进程 PID 98251 指向当前包；首次 AX 返回主窗口，随后 AX/截图均再次报 `native pipe closed`。首次树是异步加载中的 0 款游戏状态，磁盘资料库仍为原来的 7 条记录，**没有完成加载后的资料列表、详情页或交互的可见验收**，没有重复重开。没有 NativeRunner/VMRunner 会话。App SHA-256 `b34bb10eb6fc569e361d99fb1640d0944663fc04d7a3790f86a3a59989eac85d`，Runner SHA-256 `17a17a96273a46fbf388479a9b630c96114db9ed6091d3eb4608180d418159ff`。

未完成：真实 Unity 6/Flutter/SDL 等各应用兼容；Java 手柄；WebKit 持久化关闭；前台 IME/画布交互；其余独立 native profiles；Egg 的未重定位 PLT 初始化；个人 Play/passkey 登录。PR #82 在本轮只读复查仍 open / 未合并，已采用的 JNI 修复保留。没有重跑 Egg、Hole.io 或 VM。各项具体下一步见 [upstream-parity.md](upstream-parity.md)，不得用共同 fixture 通过关闭真实应用待办。

证据：`build/logs/current-upstream-build.log`、`current-upstream-ctest.log`、`current-upstream-bundle.log`、`current-upstream-candidate.json` 和 `build/macos/bundle-verification.json`。合并与平台适配保存为 `fcce001b7e53230d5b945c6dd7998d6e357dc272`，已正常推送并读回确认：`origin/main=f0bd526cdf15356cac1d272cfebe6a5ea11ef6fa`，`origin/codex/macos-p0=fcce001b7e53230d5b945c6dd7998d6e357dc272`。没有 force push，保留两个 merge parent；当前仍在 macOS 分支。此后仅补交付记录，不改变已验证候选代码。GitHub [本轮 Native macOS CI](https://github.com/ruabbit/Husk-macOS/actions/runs/38193490652) 已实际启动，记录时运行中；旧 `12f3cc0` 的远程 CI 已通过，但不能替代本轮新资源准备步骤的结果。

## 2026-10-11 NativeActivity / Egg, Inc. 接入

从干净的 `3de61f0` 开始补入上游已有的 NativeActivity 驱动。macOS 已编译共享驱动及其 UE4 JNI 链接依赖，资料库、SessionController 和 NativeRunner 增加 `nativeactivity` 分发、32 APK 集合复核、manifest 包名/库名/launcher alias/横竖屏、固定画布及触摸/键盘/手柄。旧导入动态获得入口，不要求重新下载；Unreal profile 尚未开放。启动元数据按 binary XML 的真实层级读取，其他 Activity 或 application 的元数据不会选成游戏入口。

活动线程串行执行 NDK 回调，暂停回调返回后才确认暂停；关闭依次撤销焦点、暂停、销毁窗口/输入队列、stop/destroy，并 join 线程后才确认 storage-closed。缺少 onDestroy、onCreate 抛出 JNI 异常或进程提前退出均失败，不写正常关闭回执。加载与停止共用宿主串行队列，保留默认失焦继续和已有 AppKit 鼠标修复。采用上游开放 PR [#82](https://github.com/Leviidev/Husk/pull/82)（head `e304785404971b088eb0703b3aca3916aba44bcd`）的 ActivityThread.currentApplication 修复；复用现有 Application 单例，未将 PR 记为已合并。

当前候选已在唯一 `build/macos` 完成全量构建和原地打包，默认 CTest **29/29 通过**；`verify_macos_bundle.py` 通过 **17 个 Mach-O** 的 arm64、签名、权限和依赖闭包检查。覆盖 NativeActivity 正常生命周期、缺失销毁、guest finish、onCreate 失败、JNI Application 单例、NDK 触摸/键盘/虚拟手柄，以及正式 AppKit 响应方法的点击/拖动/失焦。包级回归已确认旧索引获得 NativeActivity 入口、Runner 在执行前拒绝伪造引擎，资料库/原有会话回归也通过。实体手柄和真实游戏内输入尚未验收。

真实 Egg, Inc.（`com.auxbrain.egginc`，versionCode 111359）只运行一次隔离、静音、无窗口的生产驱动探测。读取现有 base 与三个分包，测试数据在 `build/macos/TestResults/NativeActivityEgg`。主库和 PairIP 依赖已加载，故障发生在 libegginc.so 的原生构造函数、早于 ANativeActivity_onCreate 和首帧：PLT 槽 `0x17636b8` 仍为未重定位的 `0x1625d90`，间接分支到该地址触发 SIGSEGV。诊断处理器记录并回收进程，无系统崩溃窗口。尚未证明 PairIP 是根因，没有跳过保护、猜测偏移打补丁或重复启动已知失败样本；**Egg 仍未通过运行验证**。

候选更新已完成。用户确认通过 ⌘Q 退出后，系统仍残留 PID 27488；只读采样显示空闲事件循环，无候选内 Runner/VM、无网络句柄。对这一已授权退出的残留主进程发送 SIGTERM 后确认回收，实际通过 package_macos.py 的活动进程保护，随后原地打包。完整验证后通过 CUA 按 Product 完整路径只启动一次，确认新 PID 314 指向当前候选；CUA 随后的 AX 读取仍报 native pipe 断开，**前台详情页/按钮的可见检查未完成**。未重复启动 Egg。主 App SHA-256 为 `3ceb1973ba0a6e5df05362af9c88c014ad4f7e97ff1f157b3d091041d7cd1bb8`，NativeRunner 为 `8ef38085380095987ae0caffc70b0dc8e175d30d6d68682e2f7fdf2fda0a2d08`。

日志复用 `build/logs/current-nativeactivity-build.log`、`current-nativeactivity-tests.log`、`current-nativeactivity-egg.log`、`current-nativeactivity-egg-result.json`。用户 APK、存档和 Android 磁盘未写入。每日 09:00 的原任务已更新并读回确认：新功能同步须在同一轮完成对应 macOS 适配和验证；未完成的具体交付与兼容缺口保持开放，不以合并历史或旧测试关闭。

## 2026-10-11 上游运行时合并与 macOS 编译接入

本轮开始时工作树干净，位于 `codex/macos-p0`，两个 origin 分支与本地一致，无未完成 Git 操作。fetch 得到上游 `a08b695..8a9dc1b` 共 75 个提交、3,210 个变化路径，主要新增 Java/Dalvik 框架、Flutter、GameMaker、Python/Web 路径及底层 JNI/NDK 修复。先将本地 main 快进至上游，再以真实 merge 合入 macOS，未使用 ours 策略。Store / Play 登录和 ANGLE / MoltenVK 构建脚本、补丁在该范围内无新改动。

5 个冲突文件逐段处理：loader 保留 32 APK 上限及按 4 KiB 段判断数据地址，同时采用上游避免将回调代码指针转入写视图的检查；EGL 合入纹理窗口并保留离屏提交与节流；AAudio 合入 float / channel / burst 与写入式播放，保留 FMOD 探测和 callback STOP 后 join / restart；Unity 保留串行生命周期与 nativeDone 回执，并兼容上游两参数 initJni。AppKit 鼠标、画布、默认失焦继续、会话和存储关闭代码保持不变。

CMake 补入新 NDK、long double、AudioTrack、Dalvik 核心、Java 图形/GLES/媒体/音频/SQLite/传感器/WebView 模块及 Vorbis 解码器，主 App 与 NativeRunner 编译链接通过。新 long double 表最初覆盖了精确 binary128 缩放，被原有测试检出；将精确 frexpl/ldexpl 移到新的统一模块后通过。Java app profile、boot class path 与框架 DEX 的资源打包尚未接入，不将模块编译成功写成 Java 或 Unity 6 已能运行。

默认 CTest **25/25 通过**，`verify_macos_bundle.py` 通过 arm64、签名、UI 无额外权限及依赖闭包检查。新增 Android runtime 契约、两参数 Unity 初始化、打包活动进程保护，扩充 float PCM / callback-free write / STOP 重启测试。扩展回归曾发现上游 prefs-test 写死作者机器目录并在 fopen 失败后崩溃，修正为系统临时目录和失败检查后复验通过；没有重复运行未修复的崩溃测试。没有运行用户 APK、Android VM、真实登录或播放测试音频。旧游戏验收结果不挪用为本候选结果。

窗口更新有遗留：CUA 的 native pipe 在绑定旧 Husk 时持续断开，重建连接仍失败。构建其余测试目标时未注意到 MacIntegrationTests 对 PackageMac 的隐式依赖，提前替换了运行中主程序的候选目录；此为执行失误。已经补 `package_macos.py` 入口进程检查，并确认它能在任何写入前拒绝 PID 27488 的活动候选；回归也覆盖候选内 NativeRunner / VMRunner 和包含空格的路径。当前磁盘包已完成全部验证，主 App / Runner 的 UUID 与代码、数据段和当前编译产物相同（签名后整文件 hash 不同）；旧 PID 27488 尚未正常退出重启，已向用户说明工具阻塞。没有关闭游戏、删除用户资料库或存档。

证据复用 `build/logs/current-upstream-build.log`、`current-upstream-tests.log`、`current-upstream-bundle.log`、`current-upstream-guards.log`、`current-upstream-candidate.json`，包证据为 `build/macos/bundle-verification.json`。具体 Java / Unity 6 接线和销毁协议下一步保存于 [upstream-parity.md](upstream-parity.md)，Play 个人登录仍按失败处理。

## 2026-10-10 Unity 运行时接入

Unity 驱动已编入 macOS NativeRunner。资料库按引擎和 arm64 ABI 动态分发，旧 Play 导入无需重下；Runner 独立复核全部 APK 的 hash、引擎和 ABI。启动读取 manifest 中的包名和 launcher 方向，支持 Activity alias；固定画布为横屏 1280×720 或竖屏 720×1280。鼠标左键/拖动映射触摸，键盘与手柄进入 Unity JNI；默认失焦继续并释放输入，未接入 Unity 软键盘/IME。

初始化与关闭在同一串行队列协调，UI 与控制通道在加载时保持响应。UnityMain 完成 nativePause/nativeResume 后才确认状态，nativeDone 返回且线程 join 后才写入当前会话的 storage-closed 回执。引擎主动退出、缺失销毁入口、加载失败或超时不会伪报正常存储关闭。新旧 UnityPlayer 注册类、三参数 initJni 和 Class.forName 重载均有适配。

最终默认 CTest **22/22 通过**，包签名、权限、依赖闭包通过。新增新旧 Unity 生命周期、缺失销毁、引擎退出、manifest 方向/alias 测试；扩充 AppKit 真实 NSEvent 的 Unity 点击/拖动/失焦检查和旧资料库升级/伪造引擎拒绝检查。证据：`build/logs/current-runtime-ctest.log`、`build/macos/bundle-verification.json`。

真实游戏均只读使用现有 APK，在 `build/macos/TestResults/UnityReal`、`UnityFruit`、`UnityHole` 使用独立数据，无可见游戏窗口、无声音。Subway Surf 已显示 720×1280 年龄界面，拖动滑块从 00 变为 22，未提交年龄或确认条款；失焦继续、暂停/恢复、正常销毁与进程回收通过。Fruit Ninja 能持续提交帧并正常暂停/关闭，但 20 秒画面仍全黑。Hole.io 的新版接口加载已接通，首帧前仍有 SIGSEGV / 空指针，Runner 已捕获并按失败回收，无系统崩溃窗口；日志同时记录 AChoreographer 等未实现导入，尚不能确定故障根因。没有把后二者记为游戏兼容。

候选继续覆盖同一个 `build/macos/Product/HuskMac.app`，已单次重开并核对进程路径。CUA 原生通道仍断开，资料库按钮的前台点击未验收。日常 APK、资料库设置、存档和 Android 磁盘未修改；其他引擎接入和 Play 个人账号登录保留为后续待办。

## 2026-10-10 每日同步范围复核

用户指出上游早已支持 Unity 和 Store。重新 fetch 两个远程、核对 Git 祖先与远端 SHA：上游和 fork main 均为 `a08b695`，macOS 分支已包含它，没有遗漏的新提交。Unity 原生入口来自 `00ecffb`，Store 来自 `bac475a`；上游 `ca70a4b` 的两处登录参数修复也在当前共享 PlayAPI 中。

遗漏在平台迁移：CMake 未编入 Unity 等引擎驱动，资料库与 NativeRunner 只接受 Orbit/Minecraft。Store 已使用共享上游 API，macOS 窗口和下载入库由平台代码适配。此前只以 Git 合并和已有 CTest 作为每日同步完成条件，没有持续推进或准确报告这些功能缺口。新增 [功能接入现况](upstream-parity.md) 作为后续同步检查和迁移待办；本轮没有运行时代码变化，不重复构建或启动应用。

## 2026-10-10 Google 拒绝个人账号登录

用户实际验证上一候选后，Chrome 显示 `accounts.google.com/v3/signin/rejected`，提示“此浏览器或应用可能不安全”。重新读取 Husk 界面确认应用只显示“Google 登录连接中断”，仍宣称支持 passkey 并要求重开。该结果推翻了上一节中 Chrome 路径可用的假设，个人账号与 passkey 验收失败。

本次补上浏览器每轮目标页面检查、拒绝时立即结束和 renderer 切换期间的错误归因；内置 WebKit 使用相同拒绝判断。错误文本不包含 URL 参数或协议内容。删除确定性的 passkey 支持承诺，拒绝后不再提示原样重试或切回另一个未验证的登录方式。前置邮箱输入保持删除。

查阅 Google 当前支持说明、桌面 OAuth 与 scope 列表：软件控制的浏览器可能被拒绝；公开桌面 OAuth 没有当前下载器所用的 `googleplay` scope，Play Developer API 的 `androidpublisher` 不能替代消费者下载凭据。尚无已验证的替代登录方案。这次修复的是拒绝处理，不能写成个人账号或 passkey 已恢复。

针对性回归覆盖登录中途拒绝、首次即拒绝、renderer 切换与拒绝同时发生、正常换页后取得合成 cookie，以及来源校验和 URL 参数不泄露。测试使用合成协议，不登录真实账号。完整默认 CTest **17/17 通过**，签名、权限与依赖检查通过；证据复用 `build/logs/current-play-login-checks.log` 和 `build/macos/bundle-verification.json`。候选覆盖到同一个 `build/macos/Product/HuskMac.app`，正常退出旧进程后重开；新的进程路径已核对，更新后 UI 自动化绑定仍失败，没有把界面及真实登录验收记为通过。

## 2026-10-10 Google 登录流程修复

删除 macOS 登录前置邮箱输入，后台从 Google 账号令牌交换响应读取 Email，缺少身份时明确报错，不从网页文本猜测。原有 iOS accountToken 调用签名保留。内置 WebView 恢复默认桌面 user agent，并处理同窗口 Google 跳转。

普通 WKWebView 无法为未关联的 Google 域名使用 passkey；有 Chrome 时改为独立浏览器登录窗口，让浏览器处理身份验证。每次登录使用独立临时目录和仅继承给该子进程的 fd 3/4 私有管道，不开放端口或连接日常 Chrome。只读取 Google 登录 URL 适用的 cookie，并接受安全 Google 域名下唯一的 oauth_token；结果和协议数据不写日志。取消、超时、窗口关闭和主 App 退出均结束本次登录，等待子进程退出后清理目录。无 Chrome 时保留内置密码/验证码登录。

已正常退出空闲 Husk、在唯一 build/macos 中构建并原地更新，默认 17/17 CTest 与包签名/权限检查通过。回归新增 Google 返回账号身份、缺失身份拒绝、cookie 来源与歧义检查、登录管道分片/错误/超时/取消/断连。证据：build/logs/current-play-login-checks.log。已重新打开候选；界面自动化在本次重启后连接失败，完整个人账号及 passkey 登录等待本人验证，未记为已通过。

## 2026-10-10 Play 支持

已接入 macOS 商店窗口、隔离的 Google 登录 WebView、Keychain 会话、访客模式、搜索/详情、带取消的下载及自动入库。复用上游 PlayAPI/PlayDevice/Protobuf，补齐失效令牌错误、缺失报价不得推定免费、详情包名匹配及协议解析边界。付费应用只请求已有授权交付，不发送购买请求。设备指纹设置按用户安排留到后续，以完整设备配置为单位设计。

共用资料库现在处理最多 32 个 APK 的集合，校验 manifest 中的包名、版本、base/split、必需依赖、v2/v3 签名及 Android 分块内容摘要；同包同签名的新版本更新保留身份、设置和存档，事务日志恢复中断更新。NativeRunner 接收全部分包并重新核对集合 hash，loader 不再静默丢弃旧四分包上限之后的文件。VM 安装改为一次 create/write/commit 会话，任一文件失败则 abandon 并清理传输文件。

本地构建、签名和依赖包检查通过，默认 **17/17 CTest** 通过，含新增 Play 支持、原生分包和 VM 安装事务三组。OpenSSL 独立签名的七文件集合验证了升级、混包、混签名、损坏/取消清理和更新中断恢复。用户提供的 Minecraft APK 通过只读真实签名与完整内容摘要校验，没有运行或修改它。

真实联网验证取得 Aurora 访客会话，搜索返回 18 个应用；Google 计算器 `com.google.android.calculator` 的详情、base 与分包下载、签名校验和整组导入通过。联网测试仅写入临时资料库，完成后清理，没有保存账号令牌或修改日常资料库。当前候选仍在唯一 `build/macos/Product/HuskMac.app` 中覆盖构建。主进程空闲时通过系统“Quit”正常退出后再打包。

证据复用 `build/logs/current-play-final-checks.log`、`current-play-tests.log`、`current-play-live.log` 和 `build/macos/bundle-verification.json`。原地更新后已重新打开当前候选，并核对运行路径。重启后窗口自动化连接恢复，读取到 Play 访客列表、应用详情和已入库状态；这次界面观察不等同于完整点击流程验收。真实 Google 账号登录、已购 Minecraft、VM 内多分包安装、OBB/按需 PAD、签名轮换、GApps 与设备认证均没有通过结论。


## 2026-10-10 每日上游同步：合并与完整本地验收完成

本地 `main` 从 `5a7d2df` 快进到上游 `a08b695`，随后通过真实 merge 合入 `codex/macos-p0`。相对此前源码同步点 `75dc21f`，本次新增 30 个提交、61 个变化路径，包含 Play 搜索与登录修正、iOS 下载管理、bionic 接口、手柄初始化和 Vulkan/DXVK 适配。macOS 的商店界面和 SDL/DXVK 游戏入口没有在本轮接入。

首次 merge 前逐项核对 `82f33e8..75dc21f` 的 117 个路径：109 个与上游 blob 相同，8 个保留已记录的本地实现。14 个显式冲突按这个已整合源码基线解决：11 个本地文件等于旧上游，接纳其后上游增量；3 个上游文件自该点未变，保留本地音频、GameActivity 和 Minecraft JNI 修复。另外移除了 Git 自动合并重复插入的 Geode 设置区块。最终源码树与以 `75dc21f` 为基线的独立三方核对结果完全一致，再更新本次来源和状态文档；没有使用 ours 合并策略。`src/macos`、`tests/macos`、CMake、macOS 依赖锁和打包实现均与合并前一致。

保留 `build/macos` 的 Release、VM=ON 和已有依赖缓存，运行 `scripts/test_macos.sh` 完成主 App、两种 Runner 的编译与原地打包。完整默认 CTest **14/14 通过**，包括鼠标、画布、文字输入、AAudio、binary128、VM 控制器、bridge、核心测试，以及依赖最终 App 包的 `macos-input-vulkan`、`macos-library-session` 和 `macos-library-upgrade`。`verify_macos_bundle.py` 通过签名、arm64 架构、权限和依赖路径校验。没有启动 Android 或用户 APK，也没有新增可见游戏窗口。

源码合并保存在 `71265d1`。最初因主 App 仍在运行而暂缓打包；用户随后明确授权空闲时正常退出 Husk、更新后重启。每日任务已保存这一规则，运行时间仍为北京时间每日 09:00。后续根据实际游戏/VM 会话判断是否空闲，不再把仅运行主界面视为阻塞。此次补验收时 Husk 已退出，直接覆盖同一个 `build/macos/Product/HuskMac.app`，没有另存候选副本。更新后已重新打开该路径的 Husk，进程路径与应用清单均确认其运行；应用控制工具在读取窗口时断开，未取得主窗口的视觉验收结果。

上游新加的 SPIRV-Cross 补丁及 iOS 构建接线已同步；本轮没有重建或修改 macOS 固定图形依赖，不能把上游 iOS 修复视为当前 macOS MoltenVK 二进制已更新。P5 的 Minecraft 黑屏/持续音频和 P6 发行门槛仍未通过。

本轮日志复用 `build/logs/current-upstream-*`：`reconciliation.json` 记录 117 个旧同步路径的 blob 核对，`conflicts.json` 记录 14 个冲突的逐文件依据，`build.log`、`tests.log` 保存初次编译和 11 项测试，`active-bundle.json` 是替换前候选的历史快照；`final-checks.log` 保存最终打包和完整 14 项测试。最终包校验结果为 `build/macos/bundle-verification.json`。

## 2026-10-08 单一构建目录

用户要求清理旧编译并重建当前候选。已清理 10 个 CMake 构建目录、4 份源码导出副本、各测试候选、P0 产物及依赖编译中间目录，移除约 2.38 GiB；必要旧日志约 9 MiB 集中到 `build/logs/previous-builds`。Minecraft 资料库/存档、Android 磁盘/缓存和日常资料库共 662 个受保护文件的大小及修改时间保持不变。固定依赖缓存各保留一套（图形约 40 MiB、VM 约 35 MiB）。

当前源码候选在 `build/macos` 全新 Release 构建，启用已有 VM 配置；12/12 CTest、17 个 Mach-O 的签名/权限/rpath/最低版本校验通过。产物入口 `build/macos/Product/HuskMac.app`；日志为 `build/logs/current-build.log`、`current-tests.log`、`current-bundle.json` 和 `cleanup.json`。没有启动主 GUI、Android 或用户 APK，测试结束后没有 Husk/Runner 进程遗留。后续复用这个目录覆盖构建，Git 负责版本回退。P5/P6 的未通过项没有变化。

## 2026-10-08 审查修复

八项审查修复：已创建全部迁移工作的本地检查点 `9573597`；运行时修复已提交 `fd9c470`。新候选 `build/macos-review-20261008/Product/HuskMac.app` 构建、12/12 CTest、17 个 Mach-O 的签名/rpath/最低系统校验通过。P0 harness 迁移后 30/30；actionlint 通过。测试均后台静音，没有启动 Android 或 Minecraft，没有重启日常 GUI。

## 2026-10-08 P4 / Minecraft

- 最终交付：本轮指定 Minecraft 样本的 P4 后台闭环完成。session11 实际世界采样 600.1678 秒、35,920 帧、59.8499 fps、RSS 1,784.25–1,823.23 MiB；20 次 Activity 暂停/恢复通过，41 次已记录 mixerResume 均返回 0。世界内恢复后的非零 PCM 继续增长。
- session11 正常关闭后，session12 重新进入 `Husk P4 世界 OK`，实际截图确认位置/视角恢复，再次正常 storage-closed / exited / reaped。复制资料的 session13 `_exit(74)` 被监督器正确报告 failed 并回收；session14 重新启动，关闭帧诊断后建立真实 CAMetalLayer window surface（EGL_SUCCESS），60 秒控制期 / 7,177 帧后正常关闭。9 个世界文件在受控退出与恢复后 hash 完全一致，主测试世界未改变。
- 最终实现 281 文件、bundle 56 文件、343 文件的独立源码导出一致性通过；原 APK hash 未变。最终源码 9/9、本地集成 31 项和 P0 30/30 已通过，签名/架构/rpath 检查通过。当前没有测试 Runner 或 MacMinecraftSession 残留；原主界面 PID 15359 保持运行。
- 已保存 docs/2026-10-08-macos-p4-report.md、results.json 和 7 张实际游戏 PNG；README、macOS 指南、迁移计划与本页状态已更新。本地修改未提交/推送；其他引擎、前台输入/实体设备、Xbox/联机及发行明确不在通过结论中。下方各条是诊断过程的历史状态。

- 当前最终验收 session11：98B4D6AF-731B-44AF-A4DC-F4AE3037BA00，Runner PID 24869。session10 已正常 storage-closed / exited / reaped。session11 在同一世界确认中文原内容保留并追加为 “Husk P4 世界 OK”，键盘移动、相对鼠标转向、虚拟手柄与失焦清键通过。
- session11 的 20 次 Activity 暂停/恢复通过，FMOD 恢复返回 0。恢复后的 Minecraft 自己保持暂停菜单，因此第一段 lifecycle soak 不作为完整世界时长；点击 Resume Game 后另开 `session11/world-soak` 的 600 秒采样，目前进行中。世界存档重开、隐藏 CAMetalLayer 路径与受控退出/恢复仍待最终闭环。
- 审查发现主 UI 仍用 5/22/6 秒等待，短于 Minecraft 监督器的 30/90 秒门槛，已改为关闭/退出 35 秒、启动 95 秒。仅主 App Mach-O 变化，Runner SHA-256 仍为 ff984b5d1dae1c772150ca1bc128ace76e24258743be0ff976fa20becc942ca9；source/bundle 冻结清单保留前后版本。281 实现文件、56 产物文件与源码导出核对一致。
- 最新独立源码目录 build/macos-p4-clean-source 在 build/macos-p4-final-clean 重建通过，UI 等待修正后再次通过 9/9；签名/依赖检查通过。最终日志 final-clean-build-test.log 与 final-clean-ui-build-test.log。README/构建指南正在补充 P4 范围，最终报告尚未写完。

- session10 已通过真实世界名称编辑：画面显示 “Husk P4 世界”。补齐 UTF-8 Charset/ByteBuffer 解码、GameActivity 与 Minecraft textbox 回调；还定位并修复 State 构造后 caller 删除本地 jstring 引用造成的宿主初始文本丢失，新增引用生命周期测试。原生中文组合输入/字符删除与 JNI Unicode 测试分别保留。
- 原生 9/9 CTest 已通过，P0 30/30 后台回归通过。343 文件独立源码导出的重建/9 组测试通过于前一个文本候选；最新文本引用修复后需重新核对最终源码/产物，不能挪用为最终证据。

- session05 定位根因：FMOD 恢复先用无 data callback 的合法 AAudio 流查询配置，适配层此前拒绝；首次启动有后备路径而恢复没有。允许探测流打开/查询后，session06 两次 mixerResume 返回 0，重新启动播放流，非零 PCM 计数恢复增长。此修复有独立探测/回调重启测试。
- 继续补齐 macOS 文本输入与鼠标捕获/失焦释放：使用本样本 DEX 确認的 GameTextInput.State 字段与 JNI 签名，新增 NSTextInputClient 桥接。移除为诊断音频而增加的暂停 surface 重建；随后需要在最终候选重新验证。

- 续接检查：session04 的 supervisor PID 98571 与 Runner PID 98761 仍运行，主 UI PID 15359 未触碰。session02 已成功重入同一世界并恢复原位置/视角；session03 修复真实鼠标主菜单点击，正常关闭通过。所有测试保持无可见窗口、静音。
- 当前阻塞已收敛：FMOD mixerSuspend 两次返回 0，显式停止并关闭 AAudio；恢复时 mixerResume 返回 51（OUTPUT_INIT）及 28（INTERNAL），未重建音频流，PCM 计数冻结。独立 AAudio callback STOP/restart 回归通过，但不是此处根因。下一步跟踪 builder 配置/open 失败。
- 暂停销毁/恢复重建 surface 已能恢复图形，但未修复音频；此假设需要重新评估。诊断 interposer 仅转调真实 FMOD 导出并记录返回值，不绕过行为。

- session01 已生成并进入创造世界，键盘 W 移动、虚拟手柄摇杆移动/转视角均有真实截图；暂停后帧/PCM 计数冻结，恢复后画面继续。直接关闭已加载世界（未先点 Save & Quit）走完 pause/stop/surface destroy/terminateNativeCode；游戏报告 Application shutdown successfully，storage-closed -> exited，4 项监督器检查通过，PID 已回收。世界目录 H1M2jQ1lC4s= 含 8 文件/1,596,151 字节，hash 快照已留存。
- 发现恢复后音频计数未增长，不能把暂停恢复视为全面通过。补齐 AAudio 回调 STOP 后状态重置与重启前 join，加入 callback STOP/restart/close 回归；并以精确保留全部 112 fraction bits 的 binary128 实现 frexpl/ldexpl，边界/次正规数/舍入测试通过。
- session02 PID 92996 使用更新签名产物与同一存档目录重新启动，运行时已无缺失导入；正在验证旧世界重入和真实音频恢复。

- 已将完整运行库接入同一个 NativeRunner，以 runtime profile 分派 Orbit/Minecraft，APK 全文件 hash 在资料库准备与 Runner 两侧核对。正式 SessionController 的导入/启动/键鼠/静音真实 AudioQueue 均已运行；首次全套回归 5/5 通过。
- session01 PID 86944（后台，1200 秒上限）通过真实鼠标事件跳过账号登录、进入游戏模式选择。音频非零样本计数持续增长，队列增益为 0。2 个缺失导入为 frexpl/ldexpl，当前未调用；需要实现 Android binary128 ABI，不能直接指向 Darwin long double。
- GameActivity 官方 Java 源码与该 APK RegisterNatives 均确认 terminateNativeCode(J)V、onSurfaceDestroyedNative(J)V。新增异步正常关闭与独立 storage-closed 回执，世界数据仍需保存/重入核验。

- run01 静音离屏 Minecraft 首次启动 exit 0，完成初始化与欢迎界面持续渲染；原始帧 first-frame.png，实际帧数见 probe.log（45 秒）。2 个导入绑定为记录 stub，需核对是否被调用；未把欢迎首帧或主机 marker 当作世界保存成功。
- 共享 EGL 已加入 glFinish 与单调时钟 60 Hz 节流，仅作用离屏路径。编译通过；首次签名命令误写 entitlements 文件名，改为现存 NativeRunner.development.entitlements 后通过。

- 完整 GameActivityRuntime 与显式限时 MinecraftProbe 已编译链接成功（38 步，build/macos-p4/first-runtime-build.log）；尚未执行真实 Minecraft guest。主界面 PID 15359 仍运行，未触碰。
- 发现共享 husk-tl-egl 离屏路径直接跳过 swap，缺少 P3 已验证必要的 glFinish 和帧率节流；先修正，再执行一次静音后台诊断。产品 Runner 仍保持 fixture 限制，尚未扩大兼容宣称。
- 用户授权执行 P4，并指定本地 Minecraft APK；继续遵守不循环可见窗口、不处理旧崩溃提示、不主动触发崩溃的约束。
- 原始 APK 大小 1,048,027,974 字节，SHA-256 83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95；12,949 个 ZIP 条目，10 个 arm64 原生库，libminecraftpe.so 328,419,680 字节。尚未宣称包来源为官方原版。
- 已找到上游 GameActivity/Minecraft JNI、FMOD、bionic、输入和 offscreen ga-test 路径；当前原生 App 只链接 fixture ABI，需接入真实引擎与生命周期，不能仅解除 hash 限制。

## 2026-10-08 P1–P3

- 最终交付：P1–P3 内部原型及本机后台验收完成。30 分钟修复候选 1,800.07 秒 / 107,860 帧 / 59.92 fps / RSS 25.5–30.4 MiB；最终候选 300.05 秒 / 17,974 帧 / 59.90 fps / RSS 30.4–30.5 MiB。两者均有 checkpoint ack、终态 exited 及 PID 消失证据；最终候选 56 个普通文件与交付产物 hash 相同。
- 已写 docs/2026-10-08-macos-p1-p3-report.md 与 results.json，保留 31 项检查、20 次会话和完整持续运行采样；三个实际渲染 PNG 已检查并存入 docs/macos-evidence。269 个实现文件与最终干净源码导出一致；报告本地链接和代码围栏检查通过。
- 收尾核对：最终原生 5/5 CTest 通过，端到端 31 项；P0 默认后台 30/30 再次通过（gui=false、faults=false）。20 次交替游戏启动/60 帧/保存/回收全部通过。
- 最终实现导出 325 个非 ignored 文件到 build/macos-p3-clean-source，在独立 build/macos-p3-clean 重建；复用已校验 SHA-256 的图形依赖缓存，5/5 组及签名检查通过。不是另一台干净 Mac 验收。
- 收尾修复：导入队列在 reload await 期间仍可收到新项目，因此将 reload 放回消费循环；各游戏设置按字段从最新索引合并；不可读取的 checkpoint 先判空再交给 JSON。新增设置合并及无崩溃报错测试通过。
- glFinish 修复后的 30 分钟离屏持续运行已超过 20 分钟，RSS 约 26–31 MB；最终候选另做 5 分钟后台检查。两份候选 hash 独立保留，结束前不记作验收通过。
- 通过 Context7 再核对 actions/runner-images：xcode-27 是 arm64 preview label，默认 Xcode 27.0；CI 物理机 job 已接入 20 次后台会话与 30 分钟运行。未推送或执行远程 CI。
- 用户明确授权自主推进到 P3，并要求不再处理系统崩溃提示、不循环弹窗干扰桌面。
- 已建立 CMake 的 HuskMac / NativeRunner / SharedCore / SharedLibrary / NativeRuntime 目标，原 iOS target 保留。
- ANGLE 固定 WebKit f488eac0e00cee453b7ca9f24c42f585df236e97；MoltenVK 固定 v1.4.2/db66022459ffb663aa2b50f6b018bc2e124f5edf；两者 macOS 构建完成。
- SwiftUI 资料库、复制导入、ZIP/bundle 扫描、图标、设置、原子索引、存档独立目录及原生 Process 会话监督器已实现。
- 自建 Orbit Garden/Dusk 为真正由新版 loader 加载的 Android arm64 ELF，guest 执行玩法/GLES 绘图/PCM 混音；目前只允许与打包清单 hash 匹配的 fixture 执行，其他 APK 可导入扫描并明确显示未验证状态。
- 默认后台端到端 27 项通过；另有 CTest 核心三组、输入/静音 AudioQueue/MoltenVK 设备枚举通过。没有主动 crash 信号或可见窗口循环。
- ad-hoc Hardened Runtime 下 dlopen ANGLE 被 Team ID 校验拒绝，正常失败退出；已把 disable-library-validation 限定到开发 Runner entitlement。Developer ID 模板不含此项；主 App 无任何 entitlement。真实证书/公证未执行。
- CMake Swift 原先漏发最低版本 target，Mach-O 意外 minos 27，已改为显式 arm64-apple-macosx14.0，并核验输出 minos 14.0。14 实机仍待验证。
- 第一次持续运行发现后台 autorelease 对象累积，121 秒 RSS 达 431 MiB。已停止该自有 supervisor，Runner 通过父进程退出路径回收；逐帧和后台 run loop 增加 autoreleasepool，随后全部 5 个 CTest 再通过。
- 增加 autoreleasepool 后仍增长，已停止第二次短时诊断。核对锁定 ANGLE 的 OffscreenSurfaceMtl::swap 源码，确认 pbuffer swap 不提交命令，导致 Metal command buffer 累积；已让离屏每帧 glFinish，待重新验证。不可把尚未完成的 30 分钟测试记作通过。
- 离屏 NSHostingView 导出的图片无法正确显示 AppKit 材质/控件，不作为 UI 视觉通过证据。一次正常 Husk 主窗口通过 CUA 在后台打开（PID 15359），点击添加示例游戏后 index 已包含两项；后续 CUA native pipe 断开，主 App 仍存活且未见 Husk crash report。不要再次循环开窗。

## 2026-10-07

- 完成初始工作区、分支、fork 父仓库和文件清单检查。
- 读取 planning-with-files、docs-generator、writer 和 Context7 工作指引。
- 审计只写计划和报告，未改动产品源代码。
- 正在核对上游分支与现有 macOS 验证入口。
- 已读取上游两分支 refs（仅 fetch，未切换、合并或改动源码）；核对 merge-base 和独有提交。
- 已通过 Context7 获取 Apple 的 JIT 和 SwiftUI/AppKit 文档。
- 已审计原生引擎单例、JIT allocator、渲染窗口原型、QEMU 参数、iOS 音频/文件选择器和依赖构建入口。
- 建立 build/audit-2026-10-07 用于隔离测试产物；topic 源码仅 git archive 导出测试所需目录。
- 本地验证完成：51/51 C/ObjC 语法检查、两分支 page planner、两分支 scanner 各 41 项（main 需要宿主适配）、prefs/blit/va/pacer。
- 对 JIT 做独立子进程实验并核对 codesign 与系统 crash report，确认当前 allocator 在 Hardened Runtime + allow-jit 配置下执行页被拒绝。
- 正在写入审计报告、证据记录和迁移计划；尚未合并分支或实施迁移。
- 已完成 docs/2026-10-07-audit-Husk-report.md、docs/2026-10-07-macos-migration-plan.md、docs/2026-10-07-husk-audit-evidence.md。
- 通过全部本地文件链接/源码行号/代码围栏检查；Mermaid 用已安装 Chrome 成功渲染，无新工具安装。
- 最后 git 核对仅新增三份文档与三个 planning 文件；src/scripts/tests/tools/README/LICENSE 无变化，当前分支仍为 main。
- 审计与规划完成。实施起点建议为 P0：发行态 JIT、测试宿主与独立 Runner 原型。

## P0 实施

- 已获用户授权，建立 `codex/macos-p0`，基线为上游 `82f33e8`。
- 已通过 Context7 核对 Apple 可执行内存 entitlement、MAP_JIT 线程写保护及 AppKit 退出生命周期文档。
- `allow-unsigned-executable-memory` 单项权限已让现有双映射程序在 ad-hoc Hardened Runtime 下返回 42；当前继续建立可复现测试入口，验证真实 loader 和独立窗口 Runner。
- 新增 `scripts/test_macos_p0.sh`、合成 ELF/memory/core 测试和 `src/macos-p0` 原生窗口 Runner/监督器。
- 修复 allocator 的零长度、溢出与非法环境参数；修复新版 loader 的混合页函数指针/ADR/ADRP 分类；classic 无双映射时安全拒绝混合页。
- 内存与 ELF 测试已通过，Runner 10 组生命周期测试已通过，其中包含 20 次独立进程启停；完成实际 AppKit 窗口快捷键和菜单操作。
- 测试接线问题已定位并修正：Xcode clang 需要显式 SDK；fixture 禁用 outline atomics、保留 volatile 构造函数/指针以防编译优化消除验收点；blit 回归需要链接 CoreGraphics。这些与产品运行缺陷分开记录。
- 正在完成统一全套回归、iOS 编译守卫、结果快照和决策/许可文档。
- 统一运行发现并解决系统恢复窗口提示导致的启动超时；Runner 10 组再次全部通过。补充启动期停止的检查后，进行最终 all 验收。
- 39 组统一验收通过，但用户指出测试窗口循环及主动 abort 的系统弹窗严重影响桌面。已停止可见测试、核对崩溃归因与进程回收，并保留历史结果。
- 默认入口改为无窗口/无故障注入；原生 helper 使用 Foundation run loop 执行相同控制协议。正在完成最后的后台验证及文档更正，不再自动打开测试窗口。
- 最新默认入口 30/30 组通过，含新版/classic 能力边界、后台生命周期、core 回归和 iOS 语法检查。历史 39/39 组的交互/故障结果保留为独立快照，未再执行可见测试。
- P0 报告、测试说明、迁移计划状态与依赖许可清单已完成。用户投诉的崩溃记录已匹配到主动 abort，相关测试从默认入口移除。P1 尚未开始。

## P5 续接（2026-10-08）

- 用户要求继续推进；开始 P5 原生 VM 模式。P4 构建保留在 build/macos，P5 使用独立构建目录。
- 已核对旧 UI PID 15359 仍运行，不触碰它；没有 QEMU 或新的测试会话。默认无可见窗口、静音、不主动 crash。
- 原 guest 为 LineageOS v12 直接 QEMU 启动。旧 macOS 验证脚本关闭 GL/HVF，仅可参考，不能作为 P5 成品。当前准备固定源和冷启动素材。

- 固定 guest v12 2,057,568,256 字节与 QEMU tarball 已下载且 SHA-256 通过。Husk 0.9.0 IPA 只用于提取 3 个冷启动种子，整包与成员 hash 已锁定；未运行或安装 IPA。
- 首次 epoxy 构建缺少 EGL/eglplatform.h：已改为显式引用已固定 ANGLE 的 include 目录并重新配置。QEMU 仅集成显示/音频，不采用 iOS JIT 或迁移 blocker 绕过补丁。

- 首次 VMRunner 启动正常报错退出（exit 1，非 crash）：virtio-net 默认寻找 efi-virtio.rom。该 VM 从磁盘 UEFI 启动、不使用 PXE，已显式禁用网卡 ROM；准备重新验证。
- 匹配的 QEMU/virgl/epoxy 已构建完成，依赖闭包打包并 ad-hoc 签名通过。Homebrew GLib/slirp 当前要求 macOS 27，P5 helper 暂明确声明 27；P4 的最低系统声明不变，发行前需单独重建/验证。

- HVF + virgl 已从空白 userdata 完成 Android 冷启动：sys.boot_completed=1，shell uid=2000，eth0=10.0.2.15；已获取 LineageOS Welcome 的真实 Metal scanout PNG。正在安装指定 Minecraft，尚未宣称可玩。
- TCG + software 已启动内核但 SurfaceFlinger 未稳定、桥接未响应，未记作成功；已请求关闭，保留日志。下一步隔离 GPU 配置与加速器差异。
- VMRunner 和主界面的 Android 控制入口已编译；主 App 仍无 entitlement。新测试进程保持不可见、真实音频队列增益为 0，原 UI PID 15359 未触碰。

- TCG + virgl 冷启动通过：sys.boot_completed=1、SurfaceFlinger 与 zygote running；HTTPS 200；指定 Minecraft 双端 hash + pm install Success。软件图形路径不支持当前 guest EGL 配置，不作为默认路径。
- HVF + virgl 的 Minecraft 已出现真实通知权限界面，输入可操作；但之后游戏自身 SurfaceView 持续黑屏。guest screencap 同样黑屏、Activity 为 resumed、无 Minecraft crash/ANR，不能把安装/Activity 启动记作游戏可玩。首次拒绝通知与重启后允许通知都未解决，排除单纯权限等待。
- 本机回归 10/10 通过，含真实 socket 的分段状态帧与超时不重放测试。Bundle 验证曾发现 VMRunner CMake 构建绝对 rpath，已从打包产物移除；完整嵌套 helper 依赖闭包/签名验证通过。

- P5 续接：HVF/TCG Minecraft 黑屏均复现；Android AudioFlinger 报告 MMAP_PLAYBACK，但宿主 PCM 仅短促启动后冻结。Context7 的 AOSP 文档确认可用 aaudio.mmap_policy=1 禁用 MMAP，当前仅是待验证假设。
- 两个首次 VM 的 guest 关机/磁盘清理已完成，但宿主退出挂起。sample 明确定位 AppKit 主线程 exit -> qemu_run_exit_notifiers -> BQL；已结束清理完毕的挂起进程（结果 exit -9），不算干净退出。修复 QEMU API 声明、清理后的锁释放和同线程退出。
- 修复依赖初次 clone 未 checkout pin、重复集成导出符号，以及 VMController 重开后残留 shutdownTask 阻止二次关机。加入使用正式 Swift 控制器的静默 VM 验收入口，待实际关机/重开验证。

- 修复后的真实 Swift VMController 验收通过：HVF PID 7107 正常关闭（含先暂停再关机）后同对象重开 PID 12535，二次正常退出；4 项检查通过。最终候选 TCG PID 13013 ready/暂停/继续/关机，2 项检查通过。全部后台 VM 已回收，原 UI PID 15359 保留。
- 磁盘重开读回 Minecraft 安装、HuskP5HVFPersistence/HuskP5DiskCheck 与新 controller marker。Android 设置界面实际键鼠输入 sound，截图和 UI hierarchy 一致。
- 游戏后续 ANR 栈显示 onSaveInstanceStateNative -> pthread_cond_wait。AAudio policy 试验及 guest audioserver 正常重启未修复黑屏，设置已撤回并冷启动；持续 PCM 未验收。guest 初始 rc 的“无 SetupWizard”注释与实际存在的包不符，不能据此宣称首次设置已完成。
- 367 文件独立源码重建（固定依赖缓存）+ 10/10 CTest、TL-only 重建 + 9/9 CTest、产物签名/依赖闭包通过；原 P4 与新候选 NativeRunner SHA-256 相同。P5 报告明确阶段未通过，P6 未启动。

## GUI / 上游同步（2026-10-08）

- 实际资料库含三款游戏，Minecraft digest 为 bceb3203f3b8897ee498bb3f22bd2373ac9b411a37cd4968a62f942c35d0c37e，非 P4 的 83468d0a…。三款均无存档文件；Minecraft 保存了旧 Orbit-only 原因。旧 UI PID 15359 尚在，无测试 Runner。
- upstream main 最新为 75dc21f82c1fd748867ad4d4b5dfb0e981c2d468；topic 仍为 756c8d0。开始 fetch/audit，尚未修改运行库或资料库。

- 上游 27 个提交/117 文件已三方整合到工作区，HEAD 保持原基线；本地 P0–P5 修改保留。音频计数与上游重采样合并，Minecraft JNI 同时转发 iOS 键盘及 macOS 输入；macOS 保留完整 UTF-8/组合输入实现。首次编译暴露两套 text_job/text_run 名称冲突，已将上游内部任务改名。
- GUI 按当前 runtime 动态计算能力，不再持久化禁止启动原因；其他单 APK arm64 Minecraft 标为可试运行。Runner 继续验证导入 hash 并独立复扫引擎/ABI，其他未接入引擎不冒充可玩。

- 用户实际 Minecraft APK 在隔离复制的资料库与 P4 测试世界中通过菜单、世界加载、W 键移动、两次 Activity 暂停/恢复、60.125 秒世界采样（3,597 帧，59.825 fps，RSS 1,791.06–1,792.88 MiB），非零 PCM 持续增加；正常 storage-closed/exited/PID 消失，4 项监督器检查通过。
- 正在检查 P4 原 APK 在同一新版 runtime 上的世界加载和退出。日常 index 字节仍与开始时相同。
- CUA 原生通道返回 native pipe closed；重置连接后仍失败，无法取新 GUI 的 AX/截图。停止 UI 自动化重试；不会点系统崩溃提示。

- 原 P4 APK 在相同新版 runtime 通过菜单、既有世界和正常销毁退出，4 项监督器检查，PID 10442 已回收。两个测试 Runner 均已结束；没有新匹配的宿主 DiagnosticReports。
- 最终查看时旧 UI PID 15359 已不在，本轮没有向其发送信号。只调用一次新版路径的 CUA getApp 后，尽管 AX 通道仍报错，候选已成功后台启动：PID 13772，0.2.0/build 2。未执行备用 AppKit 刷新脚本，已移除该临时脚本。
- 用同一编译 SharedLibrary 只读检查实际日常资料库：Minecraft runtime=minecraft、playable=true、verified=false、reason=null、status=可试运行。日常 index 字节完全不变，两个原始 APK 重新 hash 一致；326 个实现/构建/测试/依赖源文件与测试冻结清单一致。
- 已完成 upstream sync report/results、README/构建指南/来源锁与计划记录。GUI 截图/前台按钮点击受 CUA 原生通道阻塞未验收；P5 VM 黑屏和持续音频仍未解决，P6 未开始。源码整合未 commit/push，HEAD 保持原基线。

## 窗口缩放与焦点修复（2026-10-09）

- 观察到现有 Minecraft 窗口画面偏左、黑边不对称。游戏报告 1280×720；ANGLE 按可变 layer.bounds × contentsScale 重设缓冲区，宿主没有同步游戏尺寸。新增固定像素画布父图层，仅缩放、居中显示；鼠标换算复用实际图层变换。Minecraft 初始内容区域改为 960×540 点。动态游戏分辨率尚未实现。
- 失焦暂停来自 macOS 移植默认设置，不是上游要求。新游戏默认关闭，已有偏好不批量迁移；本机当前 Minecraft 单独关闭。开关支持运行中修改；失焦始终释放输入，手动暂停不会因设置变化而自动恢复。
- 13/13 CTest 通过，含 24 个真实 ANGLE 隐藏窗口尺寸/模拟 backing-scale 组合、四角像素和输入映射，以及 37 项资料库/会话检查；17 个 Mach-O 的签名与依赖闭包通过。
- 实际用户 Minecraft APK 在既有隔离测试库中通过一次静音隐藏窗口检查：EGL 1280×720、收到失焦事件后继续从 2073 帧前进至 2327 帧、正常 storage-closed/exited、PID 回收。日志在 `build/logs/current-minecraft-window`，未修改日常游戏存档。
- 原日常游戏自行正常退出后更新同一 `build/macos` 候选。初次窗口截图已观察；随后 CUA 原生 pipe 断开，重置后仍失败，新候选可见窗口截图/拖拽验收未完成。没有循环启动可见测试游戏。
- 最后修正设置区原有的整组禁用：运行时可切换失焦暂停，静音仍在下次启动生效。UI 编译及最终签名通过；以原子替换更新候选主程序，保留已开的资料库进程。该进程需重新打开一次才能加载最后这项设置界面调整；游戏 helper 已是通过验证的新版。

## 鼠标点击修复（2026-10-09）

- 用户确认手动 Settings 点击无响应。旧会话 `CFE11150-5A50-4E33-858F-0FAAEFFA2A5E` 的鼠标计数停在 53，而 Tab 可以改变选择。此前隐藏画布与坐标测试没有覆盖真实点击链路，这属于验证遗漏。
- 修复 GameView 对非滚轮事件读取 `scrollingDeltaY` 引起的 AppKit 异常；改用事件序列维护鼠标按钮，支持首次点击激活窗口及中键拖动。暂停、失焦、黑边起始按压与跨边界松开均有处理，状态事件保留一份 lastClick 供诊断；临时本地事件监听器已移除。
- 新增 `macos-native-mouse`，用正式 GameView 响应方法和真实 NSEvent 对象验证六类输入场景。临时恢复旧的无条件滚轮属性读取后，首次左键点击捕获同样异常、输入边界事件数为 0；恢复修复后全部通过。该过程仅构建后台测试，不重启可见游戏、不制造崩溃提示。
- 用户启动并点击的会话 `12FB5AFA-7AA6-4EB9-B759-3BD50C1BE057` 已显示 Settings。随后通过 CUA 点击 Keyboard & Mouse；原生 zoom 调整到 1920×956 点后点击 Accessibility 并返回主菜单，再恢复 960×540 点。保存的 Settings、Keyboard & Mouse、返回主菜单截图位于 `build/logs/current-mouse`；没有操作设置开关、创建世界或登录。
- 现场可见验证使用带临时监听器的诊断版本。磁盘候选随后去掉监听器，并完善黑边起始按压、滚轮属性访问和失焦后拖动的过滤；这些收尾由后台回归验证。两版 helper 的哈希保存在 `build/logs/current-mouse/candidate.json`。更新时保留游戏进程；随后该会话收到 controller-stop，正常完成 storage-closed / exited，两个 App 进程均消失，没有新增崩溃报告。本轮没有再启动可见游戏，下次启动加载最终 helper。
- 最终候选覆盖同一 `build/macos/Product/HuskMac.app`，对被映射的可执行文件原子替换后重新签名，未复制额外 App。14/14 CTest 与 17 个 Mach-O 签名/依赖闭包检查通过；日志为 `build/logs/current-tests.log`、`current-mouse-regression-before.log`、`current-mouse-regression-after.log`，包检查为 `build/macos/bundle-verification.json`。世界内视角捕获和完整玩法未在本轮验收。
