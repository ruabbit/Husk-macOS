# 上游功能与 macOS 接入现况

## 2026-10-30：Unity / 静态签名页 / 服务维护，build 24

`ee85db6..645c22a` 共 **13 提交/23 路径**普通合并到 main=`7a6bb7f`，再合回 macOS=`ec0ed02`，origin 无外来提交。三处冲突按行为处理：兼容性服务保留 Mac 的显式日志与 POST 不重试；bionic 接入静态签名页复用后仍拒绝其他动态执行分配；Unity 按实际注册签名调用初始化并保留生命周期缺失失败。逐项对照 `TLReport.nativeEngine`、`TLUnityView`、`project.yml`、Mac CMake/能力判断/Runner 分发与输入/暂停/关闭、共享 Store/账号和图形构建，本批没有新引擎类型、图形 pin 或权限变化。

| 增量 | macOS 实际接入与证据 | 仍须区分的边界 |
| --- | --- | --- |
| 服务维护与报告排队 | 共享 503 maintenance 回答不切换备用站，保留本机缓存；Mac 展示维护/缓存提示与重试。202 queued 报告保留服务端回执、明确尚未发布并禁止该表单再次发送。账号资料修改保留排队状态。隔离 HTTP 测试覆盖缓存/无缓存、恢复、排队、失败和 POST 不重试 | 没有实际发报告、登录、上传或修改个人资料；线上维护及认证服务不是这些测试的验收对象 |
| libffi/JNA 静态代码页 | 复用上游 `vm_remap` 路径，补完整源 ELF SHA-256 与大小、PT_LOAD 文件偏移转换、调用方命名空间选择、纯代码页/范围校验与 RX 最大保护。固定地址仅覆盖 guest 自己的匿名预留；映射/释放后不会被匿名 madvise 当作数据页覆盖。默认/无执行 arena 两种路径保持 | 真实 ELF 验文件/虚拟偏移不同、同名不同字节拒绝、重命名副本、同字节跨命名空间歧义拒绝、固定预留、只读执行和原映像释放独立性。没有真实 JNA 第三方应用证据；混合代码/可写数据页及不满足 host 页对齐的重映射明确拒绝 |
| Java/SDL LuaJIT 解释器 | 上游 Java hook 已编入，SDL 在 TL_NO_XMEM 下也安装同一 hook；资料库与 NativeRunner 只对具备该 hook 的 Java/Java NativeActivity/SDL profile 放行。真实 DEX 经依赖 ELF 的 PLT 打开 Lua 标准库后关闭 JIT，再进入应用代码；SDL 打包会话同样验证 | 这里是 LuaJIT ABI 夹具，不是真实 LuaJIT 商业应用。Geode、已知 Mono JIT、其他 profile 的 LuaJIT 和 Web JIT-less 限制保持；默认模式既有能力保留 |
| Unity / ES 3.1 / Java framework | 旧 Unity 打包 ELF 验证 libmain JNI_OnLoad 前已有 Looper、同时注册一/三参数时选三参数 initJni、UnityPlayer.loadLibrary 执行插件 JNI_OnLoad 且重复加载只执行一次。ANGLE 真编译/链接验证 Unity sampler 与 block binding、资源查询和空 label。真 DEX 验 FeatureInfo 与 GLES 一致、未附加 View 的 insets；FMOD 列表查询不启音频 | 旧/新 Unity 真游戏、真实输入法/手柄和音频设备仍待独立验收；没有把 ES 3.1 shim 当成完整原生 ES 3.1 驱动 |
| AOT 原开放项 | 旧 Unity/Minecraft 的默认与 JIT-less 打包输入/暂停/正常关闭通过；Minecraft 验 V8 flag 与 Looper 先于 GameActivity。转换中 stop 保留旧 checkpoint、不发 storage-closed、不发布半成品缓存；下一进程清理临时阶段后转换并完成保存重开。Mac 缓存 revision 升为 mac-aot-2，ABI 保持 65540 | 只覆盖受控后台会话。转换中 abrupt host/process loss、真实大库/下载后才出现的库、未知 Mono 元数据和商业游戏仍开放 |

首轮 27 项针对性测试在修正 Unity 缺 DEX 类、SDL 缺 DXVK 分发标记后已 **27/27（32.90 秒）**。更早的静态映射夹具误把全部 ELF 布局当作文件/虚拟偏移不同，以及 GL label 测试头文件枚举缺失，已修正并保留失败日志。最终默认 **182/182（355.67 秒）**，其中 AOT 打包 12 项（27.85 秒）、WebView 48 项（208.06 秒）与 HTTP 5 项（26.09 秒）；包检查 18 arm64 Mach-O/406 Java 资源/中英文各 776 条通过，18 个二进制摘要一致。CUA 单次启动准确 build 24/PID 7565，AX/截图确认原图标/TabView、11 应用与图标、选中应用 JIT-less 关闭，已返回首页。源码 7761a0d 与 main 7a6bb7f 已正常推送，两分支远端 SHA 已读回；首轮 CI 40987432500 在新增 Java 夹具找不到 linker 时失败：临时 ANDROID_SDK_ROOT 只有 Java SDK，脚本遗漏标准 SDK 的 NDK。已补回退；本机模拟临时 SDK/无效显式 linker 生成的四个 APK 条目字节完全一致，相关 4/4（14.59 秒）通过。候选二进制未改变，工具链修复 [99d3386](https://github.com/ruabbit/Husk-macOS/commit/99d33861466e97a9c000a74667e764929e0359b4) 已推送并读回；第二轮 [CI 40988087109](https://github.com/ruabbit/Husk-macOS/actions/runs/40988087109)（head=99d3386）已 completed/success：构建/包检查、**47 项 hosted 核心回归（45.02 秒）**及 P0 memory/core 通过，build-and-core 用时 4 分 32 秒，hardware skipped。九个共享 C 文件和共享 Account/Compatibility Swift 的 iOS SDK 语法检查通过，不代表 iOS 完整构建、签名或实体设备验收。

下一步仍为合法真实应用的独立存档与 JNA/Lua 验证、WebView 历史恢复/host-stop 与导航/destroy 等顺序交叠、加载中/跨来源与真实第三方插件、实体输入和 Play/VM/P6。转换取消及旧 Unity/Minecraft 的受控打包回归已完成，不能再整项列为未实现。War Thunder 保持更新器完成后的 Vulkan 设备黑名单 exit 1 结论；本轮没有相关修复或重跑该游戏。

## 2026-10-29：JIT-less 接到独立 Runner，build 23

`a06a74d..ee85db6` 共 **13 提交/25 路径**普通合并到 main=`5258ed8`、macOS merge=`1b4acff`；origin 无外来提交。loader 内容冲突保留 fork 的 ELF 地址粒度判断，并复用新 AOT 的 `waddr/data_view` 混合页副本；不以整文件 ours/theirs 代替语义合并。对照 TranslationLayer.swift 的 TLReport.nativeEngine、TLUnityView、project.yml/Xcode 项目、Store/账号、图形构建和 Mac CMake/资料库/Runner，本批没有新增引擎类别或图形 pin。权限、固定画布、AppKit 输入、默认失焦继续、独立 Runner 和存储关闭协议保持。

| 上游增量 | macOS 实际接入 | 验证边界 |
| --- | --- | --- |
| 共享 AOT 转换、签名、加载与重定位 | `husk-tl-aot/codesign` 编入 NativeRuntime；每游戏默认关闭的 JIT-less 设置进入生产 NativeRunner，先异步转换 APK/split/Java runtime，Mac 采用共享本地 ad-hoc signer，无个人证书/Keychain 操作 | 受控 ELF 的代码改写、4 KiB/16 KiB 数据副本、Go/Mono 元数据、构造函数、命名空间、系统调用和 gzip tar/Python 模块通过；真实 Android 游戏及 iOS 签名设备仍未验收 |
| 禁止执行内存和缓存 | 同时禁止 loader arena 与 guest mmap/mprotect 动态代码；缺 dylib 明确失败。缓存绑定来源 SHA-256、fork AOT ABI 65540 与格式版本，私有临时目录完成摘要/签名验证后发布，重开重新验证。系统库使用独立 install name，防止相同字节的跨命名空间映射被二次重定位 | 缓存冷/暖、签名或摘要损坏、锁、符号链接和缺库失败通过；保留既有 Mac Runner entitlements，不等于在无权限的 iOS 上验证 |
| 生产窗口/输入/生命周期 | 8 条打包 profile：Cocos/Godot/GameMaker/SDL/GTA/UE4/Java/Java NativeActivity，沿用固定窗口与输入、暂停/继续、正常销毁和单次 storage-closed；进程状态确认执行 arena=0 | 后台真实 ELF/DEX 夹具，不是相应商业游戏兼容；实体 IME、手柄、前台游戏仍需单独验收。Geode、已知 Mono JIT/LuaJIT、Web profile 拒绝该选项 |
| JNI/数学兼容 | 三参数 Class.forName 复用真实 ClassLoader/initialize 语义，去除重复 HLE；Display.Mode 补宽高/60 Hz/ID；nexttoward/nexttowardf 通过 binary128 shim 接 Android q1 ABI | 真 DEX、自定义 ClassLoader、延迟初始化、fake JNI mode 与真 Android ELF 的一 quad ULP 方向验证；不是新版 Unity 游戏或显示器刷新率实测 |

最终默认 **176/176（336.09 秒）**、18 arm64 Mach-O/406 Java 资源与中英文各 771 条文案包检查通过。八条 AOT 打包会话确认零执行 arena，Java 第二进程读到前次偏好和 SQLite 记录并正常关闭。首次完整套件的夹具重复建表失败已修正并保留证据；单项重开复测 1/1（5.56 秒）。CUA 单次启动准确 build 23/PID 74471，AX/截图确认原有 11 应用、原图标/标签和默认关闭的 JIT-less 选项，返回首页；未启动游戏或改设置。首轮针对性 **22/22（22.44 秒）**通过。源码 3398744 与 main 5258ed8 已正常推送并读回；CI [40824326328](https://github.com/ruabbit/Husk-macOS/actions/runs/40824326328) completed/success，45 项 hosted 核心回归（51.90 秒）、构建/包检查及 P0 memory/core 通过，hardware skipped。9 个共享 C 文件 iOS SDK 语法通过；仅 macOS 完整构建，本轮未做 iOS 完整构建或真机验证。

JIT-less 仍开放转换期间停止的专门回归、旧 Unity/Minecraft 的 JIT-less 打包会话、真实游戏、解包后才出现/下载的动态库、未能确定代码范围的 Mono 文件信息、运行时生成代码的引擎与模组、iOS 个人证书及设备验收。下一轮先补转换取消与旧引擎专门回归，再对合法真实应用做独立存档验证。默认模式中既有 .NET/Java/Geode 支持保持；不能把 JIT-less 的限制写成这些功能整项未实现。WebView 的具体顺序交叠/加载中/跨源/第三方插件、实体输入/电源/文件面板/持久 URI、真实账号/Play、VM/P6 等既有待办保持开放；War Thunder 仍是已记录的更新器完成后黑名单 exit 1，本轮没有相关修复或重跑。


## 2026-10-28：Play 详情与原标志导航，build 22

`9519faf..a06a74d` 共 **7 提交/26 路径**已普通合并为 main=`e3b08b8`、macOS merge=`3e5e8c3`；origin 无外来提交。唯一冲突是 HuskLogo 的修改/删除，按上游恢复原图标的明确意图移除旧 H 组件，并在 Mac 保留原图标与标签导航。3.1 tag 指向 `7cc583c`。

| 上游增量 | macOS 接入与验证 | 证据边界 |
| --- | --- | --- |
| 原标志、无启动页/侧栏、账号入口 | Mac 使用原 Husk.icns、原生 TabView；首页头像菜单及设置打开独立账号窗口，保留独立游戏窗口、导入和资料库操作；首页移除重复上次使用时间 | CUA 单次启动确认首页/11 应用、头像菜单与两个账号入口；Mac 列表/表单继续尊重系统浅色/深色偏好 |
| itslevii.dev 与中文资源 | 共享 CompatibilityStore/Account 采用新主域及 antiweb.lol 回退，Mac 披露同步更新；合入上游中文，中英文各 766 条资源验证通过；账号/社区服务离线回归通过 | 未注册/登录真实账号或上传资料；旧 Mac 帮助长文和动态诊断仍有未翻译部分 |
| Play 富详情 | 共享 PlayApp/PlayText 实际编入 Mac，接到既有 Store 选中详情与安装事务；横幅、评分/下载/年龄、富描述/更新、标签/亮点、日期/开发者链接、独立截图翻页/缩放/全屏及主动点击预告链接 | 离线 protobuf/实际解析、版本号回退保留元数据、富文本/URL边界、窄窗口/空截图后台布局通过；真实 Google Play 详情与网络图片操作仍待已认证会话验收 |
| ELF→Mach-O 实验工具 | 上游工具编入独立开发目标；自建 Android ELF 转换后临时 ad-hoc 签名，实际 dyld 加载检查映像字节、16 KiB 对齐及 RX/RW 双副本，通过后清理夹具产物 | 未接到资料库/Runner；重定位、代码改写、无 JIT 游戏和 iOS 真机仍未实现或验证，不能视为新增运行引擎 |

对照 TLReport.nativeEngine、TLUnityView/project.yml、Mac CMake/资料库判断/Runner 启动与输入/暂停/正常关闭、Store 登录和图形依赖构建，本批没有运行引擎、图形依赖或权限增量。既有 Java/Dalvik/Unity、Cocos/Godot/SDL 等及独立 WebRunner 接线保持。最终默认 CTest **166/166（275.00 秒）**、原 WebView **48 项（164.83 秒）**及 HTTP **5 项（22.16 秒）**通过；针对性 **6/6（4.06 秒）**、包检查 **18 arm64 Mach-O/406 Java 资源**及 iOS 共享 Swift 语法已通过，后者不代表完整 iOS 构建或真机验证。

既有 WebView 主程序/Activity/destroy/导航/受控 HTTP 保存保持，历史恢复与 host-stop、导航/destroy、Activity replacement/recreate、加载中/跨源及真实 HTTP 第三方插件继续开放。本轮未重复启动 War Thunder、Egg 或 Clash；War Thunder 当前仍是更新器完成后设备黑名单主动 exit 1，无正常存储关闭回执。实体 IME/手柄、真实账号与 Play、Geode/.NET、文件面板/URI、VM/P6 继续保留专门验收。


唯一 build 22 已单次通过 CUA 启动，PID **70008**，完整路径、首页/头像菜单/账号页/设置的 AX 与截图通过，现已返回首页。源码 [59bacda](https://github.com/ruabbit/Husk-macOS/commit/59bacda14d7d53a21fa20612ff854964c7cfaa75) 与 main e3b08b8 已正常推送并读回；[CI 40615007325](https://github.com/ruabbit/Husk-macOS/actions/runs/40615007325) completed/success，43 项 hosted 核心回归（46.56 秒）、构建/包检查及 P0 memory/core 通过；hardware job skipped。

## 2026-10-27：上游 3.1，build 21

`3b87cbc..9519faf` 的 **27 提交/66 路径**已普通合并到 fork main=`99169de`，再合回 macOS=`52c17da`，没有冲突或 origin 外来提交。按 TLReport.nativeEngine、TLUnityView/project.yml、CMake、资料库判断、Runner 输入/暂停/关闭、共享 PlayAPI/登录及图形构建逐项核对；没有新增图形依赖 pin 或 Mac 权限。iOS 的 Bonjour RemotePairing、TrollStore/JIT fallback 与 jetsam 诊断保留上游源码，不映射成 Mac 平台能力。

| 3.1 增量 | macOS 接入与本轮验证 | 证据边界 |
| --- | --- | --- |
| Godot 4.7 Kotlin 文件/目录 | 新文件编入 NativeRuntime；所有别名复用 canonical HLE，保留 APK assets，修复跨对象句柄、写入返回值、翻译后路径与目录锁/过期 ID。二进制 flush/关闭/重开、resize、seek/eof、rename、独立目录/无效句柄回归通过；原 Godot ELF 输入/暂停/正常关闭保留 | 真实 Godot 4.7 游戏、可见窗口与存档重开仍待验收 |
| compressed heap、font-path、V8、JNI、W^X | NativeRunner 在 AppKit/Java 前预留；复用上游真实 Mach 早/晚预留和字体路径测试。打包 ELF 验证 JNI_OnLoad 前已设 `--jitless`；真 DEX 验证重新注册 native 后缓存失效。共享 RX/RW 改动进入现有 Hardened Runtime | 受控 ELF/DEX 与路径测试不代表 Cocos Creator、Flutter、Dex2C 真实应用兼容 |
| Java 布局/手动输入 | 真 DEX 覆盖 GL resize、fullscreen 零 insets、系统设置请求取消、无输入框的 ASCII/中文/emoji 与删除/确认。Mac ⌘T/keyboard 控制和旧 Unity 输入分支接通；SDL 手动文字生成 Android ASCII/shift 键。打包 Java/SDL 输入、暂停和关闭通过 | 实体输入法组合/实体手柄/前台真实游戏未验收；SDL 无法表示的 Unicode 仍需应用自身文本接口 |
| APK manifest 主包识别 | 导入复用共享 orderedAPKs；受控签名 bundle 将 base 与 split 文件名故意互换仍正确选择，原身份/版本/签名校验不变 | 不代表真实大包或已认证 Play 资源交付 |
| 侧栏、H 标志、账号、游玩时长、Store 分类 | 复用 Account/HuskLogo，加入 AppKit 头像、账号页、Mac library rows、暂停时停止计时、导入后/游玩后的同步调度及 All/Games/Apps。离线服务测试覆盖登录/注册/回退/资料库/编辑/退出/401/凭据失败；CUA 核对首页 11 应用与账号登录页 | 未创建或登录真实账号、上传个人资料、验证线上服务或 Google Play 认证 |
| 应用与 guest 语言 | en/zh-Hans 各 331 条文案进入 Product；仅改 Husk 自身偏好，白名单环境传给新 NativeRunner/WebRunner；真打包 DEX 在 Application 前取得对应语言 | CUA 当前核对英文主要界面，动态计数/旧帮助诊断仍有中文；运行中 guest 语言变化未实现 |

唯一 Product 为 **3.1.0/build 21**。针对性 **15/15（11.95 秒）**、最终默认 **164/164（256.95 秒）**、包检查 **18 arm64 Mach-O/406 Java 资源**及两语言资源通过；其中原 WebView **48 项（161.14 秒）**和 HTTP **5 项（21.62 秒）**保持通过。iOS 共享 Swift/C 语法通过，未做完整构建/真机验证。CUA 单次启动 PID **13975**，完整候选路径、首页/侧栏/账号页 AX 与截图核对成功；没有启动用户游戏/VM。源码 [fb1e7b0](https://github.com/ruabbit/Husk-macOS/commit/fb1e7b0b0e87724908a5f915ad84d479df54cda9) 与 main 99169de 已正常推送并读回；[CI 40434410977](https://github.com/ruabbit/Husk-macOS/actions/runs/40434410977) completed/success，41 项 hosted 核心回归（48.68 秒）、构建/包检查与 P0 memory/core 通过，hardware job skipped。

既有 WebView 主程序/Activity/destroy/导航与受控 HTTP 保存已交付；历史恢复/host-stop 交叠、导航/destroy 专门回归、Activity replacement/recreate、加载中文档、跨源 child frame 与真实 HTTP 第三方插件继续开放。下一轮先完成这些具体回归，再验合法真实应用；保留物理 IME/手柄、文件面板/URI、真实 .NET、真实 Geode、Play/VM/P6 等下文待办。War Thunder 最新真实证据仍是更新器完成后设备黑名单主动 exit 1，不能因这轮构建通过改记为游戏兼容。

## 2026-10-26：HTTP 保存与停止交叠，build 20

origin/upstream fetch 均无新增；upstream 3b87cbc 已在 main 2c3af7a 的历史内，main 又是 macOS 分支祖先，没有合并或冲突。逐项核对上游引擎、TLUnityView/project.yml、macOS CMake/资料库/Runner 输入与暂停关闭、Store/登录和固定图形依赖，既有接入保持。

回环 HTTP 真 DEX 暴露 host-stop 在导航保存途中直接失败。现在停止接续同一保存，立即取消未放行的跳转，保留旧文档与 Java 插件直至保存、即时 UI 写入及既有双侧关闭完成；原六秒期限不重置，失败仍为 sticky。HTTP POST、重定向/历史请求次数、cookie/Web 存储/Java 插件跨进程重开、停止交叠以及拒绝/超时五项均通过。迟到 3.5 秒的 stop 仍受原期限约束；目标页面请求数保持零。保存通过所需的 event.waitUntil 仍是 Husk 扩展，合成事件 isTrusted=false。

唯一 Product 为 **3.0.0/build 20**；最终默认 **CTest 155/155（247.80 秒）**，其中 **48 项 Java WebView（155.25 秒）**、新增 HTTP **5/5（20.99 秒）**通过。完整构建与包检查 **18 arm64 Mach-O/406 Java 资源**通过；iOS 共享 Web host 语法检查通过，未做 iOS 真机验收。CUA 单次启动 PID **98822**，完整路径、AX/截图确认原有 **11 个应用**及可见图标。

这组 HTTP 证据来自本机回环服务与受控 APK/DEX，真实第三方应用/插件、历史恢复检查与 host-stop 交叠、导航保存与逐视图 destroy 专门回归、Activity replacement/recreate 更多顺序、加载中/跨源文档继续开放。下一轮先验证历史恢复交叠，再验合法真实应用。用户 War Thunder 最新日志已改记为更新器完成后的 Vulkan 设备黑名单退出，具体命中规则未知；本轮未启动用户游戏或 VM。

源码 [97de762](https://github.com/ruabbit/Husk-macOS/commit/97de7623fca14f5d5e8e8bec4a0d7e48601d225c) 已正常推送，两分支远端 SHA 已读回一致；[CI 40253576983](https://github.com/ruabbit/Husk-macOS/actions/runs/40253576983) 已 **completed/success**，构建、包检查、36 项 hosted 核心回归（48.98 秒）及 P0 memory/core 通过；hardware job skipped。

## 2026-10-25：导航许可、文档代际与历史恢复，build 19

两远端 fetch 没有新增，`upstream/main=3b87cbc` 已在 `main=2c3af7a` 历史内；origin 两分支与本地一致，没有合并或冲突。重新对照上游 TLReport.nativeEngine、TLUnityView、project.yml 与 macOS CMake、资料库/Runner 分发、输入/暂停/关闭、Store/登录和图形构建，既有引擎接入与依赖 pin 保持，无新增上游平台功能。

Java WebView 的页面跳转先交由 `shouldOverrideUrlLoading` 决定，再保存旧文档。应用拦截、自定义 URL 和同文档锚点移动保持原页面与插件可用；显式加载不带锚点的基准 URL 仍会保存并替换文档。保存计时器及异步回调按文档代际隔离，`didFinish` 不再重置已开始的下一次保存。Java 插件异常即使被页面 catch，也会取消导航并保持最终关闭失败。新文档解除保存阶段的媒体挂起；没有播放测试音频。

真 DEX 的后退用例还发现 WebKit 会恢复已封闭脚本的历史缓存文档。现在记录宿主成功保存的历史项，只有确认恢复的是封闭 GET 文档才在原历史位置 reload；正常历史加载不重复加载。已保存的非 GET 历史项在导航前被拒绝并向 Java 报错，当前文档保持可用，不自动重发 POST。文件子 frame 的映射仍未接入，现明确拒绝，不再错误提升为主页面。

最终针对性导航 **9/9（35.40 秒）**通过，覆盖 Java loadUrl、页面许可、锚点/基准 URL、连续保存、reload/back/forward、POST 历史拒绝及插件异常/超时；其中七项是本轮新增。唯一 build/macos 的 build 19 构建与 **18 arm64 Mach-O / 406 Java 资源**包检查通过，默认 **CTest 150/150（224.02 秒）**通过，其中 43 项 Java WebView 共 129.23 秒；CUA 单次启动 Product/PID **99255**，完整路径、AX/截图确认原有 11 个应用及可见图标。上述均为受控 APK/DEX/WebKit fixture，不代表真实 HTTP 第三方应用或游戏兼容。

源码 [963975e](https://github.com/ruabbit/Husk-macOS/commit/963975e1026f5f188a4c0f7a26f8178c4e1791b4) 已正常推送，两分支远端 SHA 已读回。[CI 40150135195](https://github.com/ruabbit/Husk-macOS/actions/runs/40150135195) completed/success，构建、包检查、36 项 hosted 核心回归（48.66 秒）和 P0 memory/core 通过；hardware job skipped。

下一轮先补隔离 HTTP DEX 回归，核对重定向、普通历史重新加载的请求次数、cookie/插件保存重开，以及导航保存/历史检查期间 host-stop 的完成语义，再对合法真实 HTTP 应用做独立存档验收。Activity replacement/recreate 更多顺序、加载中文档、跨来源 frame、页面脚本直接 file URL、非 GET 历史的应用显式恢复及实体 IME/手柄验收继续开放。现有失败路径仍拒绝成功关闭回执；没有用旧 CTest 或 Git 祖先状态关闭这些待办。

## 2026-10-24：同一 WebView 导航前保存，build 18

两远端 fetch 均无新增，`upstream/main=3b87cbc` 已是本地 `main=2c3af7a` 的祖先，本轮没有重复合并或冲突。对照 TLReport.nativeEngine、TLUnityView、project.yml、CMake、资料库/Runner 分发、输入/暂停/关闭、Store/登录和固定图形依赖，没有新的上游平台增量。

Java 内嵌 WebView 现在在同一视图主文档被替换前执行独立的一次性保存阶段。reload、back、forward 和 Java `WebView.loadUrl` 都先等待旧文档的 pagehide/unload、Java 插件调用以及 `event.waitUntil`，保存成功才允许导航；`didCommitNavigation` 后重置状态。失败/超时取消导航并保留最终关闭失败标志。导航委托同时把 Android 的 `file:///android_asset/`、`file:///android_res/` 和 file URL 映射到 `huskapp://`，首屏 `about:blank` 不触发保存。页面脚本直接设置 file URL 的回调没有单独验收，因此不把它写成通过。

新增真实 Java DEX 的 `navigation-save` / `navigation-rejected` 回归：Java `loadUrl` 换页前保存 localStorage、IndexedDB 和插件数据，换页后继续运行并在进程重开后恢复；永不完成的 `waitUntil` 会取消导航，Activity 保持运行且 host-stop 保持失败。WebView 组 **36/36（136.66 秒）**、重打包 Product 复核 **2/2（12.82 秒）**，默认 **CTest 143/143（207.93 秒）**，包校验 **18 个 arm64 Mach-O / 406 个 Java 资源**均通过。

当前 build 18 的同一视图 Java `loadUrl` 链路已接入并有 fixture 证据；页面脚本直接 file URL、Activity replacement/recreate 的更多顺序、加载中文档、跨来源 frame、真实 HTTP 应用/第三方插件、未登记异步任务和 trusted unload 仍开放。Actions [40065200939](https://github.com/ruabbit/Husk-macOS/actions/runs/40065200939) 已 completed/success，构建/包检查和 36 项 hosted 核心回归（46.68 秒）通过，hardware job skipped；这些结果不能替代真实第三方应用、真实游戏保存重开或实体设备验收。

## 2026-10-23：bundle 流式导入与 Mac 宿主环境，build 17

上游 2df074b..3b87cbc 新增 5158e09（XAPK/OBB、deflate、Zip64）和 3b87cbc（电量、24 小时制、时区/语言、设备身份）。origin 无新增，普通合并 main=2c3af7a，再合回 macOS；没有冲突。对照 TLReport.nativeEngine、TLUnityView、project.yml、CMake、资料库/Runner 分发、输入/暂停/关闭、Store/登录和图形构建，本次没有新引擎或图形 pin；原有能力保持，新增平台行为见下。

- Mac 的 Sensors.battery 通过 IOKit 读取内部电源快照，区别充电、放电、暂停充电、满电和无电池桌面；排除 UPS/外设。BatteryManager 与 sticky Intent 复用该接口，sticky extras 从同一个快照生成。无电池桌面明确 present=false，温度/电压/化学类型不再伪装成电池；未知读取仍保留兼容回退。isCharging 包含充电和满电状态。
- Java 24 小时格式直接使用上游 CoreFoundation 实现；语言从共享宿主属性注入 libcore 的 user.locale。Android 默认时区实际使用 RuntimeHooks supplier，因此在 Application/provider 之前安装 supplier，清掉旧缓存；Java SystemProperties 与 native 属性共用来源，保留 guest 临时覆盖和清除覆盖。宿主时区/语言为进程启动快照，运行中系统变更广播仍未接入。兼容 Android Build 身份一致不等于真实设备认证或 Play Integrity。
- macOS 实际导入已经用共享 C ZIP 解析器支持 deflate、Zip64 和 OBB。本轮在该路径补 64 KiB 流式提取，校验本地记录、实际输出、压缩流结尾及 CRC；失败删除本次创建的未发布文件，既有文件/符号链接保留。复用既有 APK 签名/OBB 包名与摘要/安装事务及 Android OBB 路径映射。保持 512 MiB 单条、4 GiB 总量和 50,000 条目上限；Zip64 格式支持不代表允许超过这些限制。

同轮真实 DEX 回归发现 guest System.out/native stdout 会污染 NativeRunner 控制通道，已拆分专用控制 writer 与 guest 诊断 fd，保留 JSON 严格校验及有界 stderr；最终打包 Java 验证原始 println、JSON 形状日志和 onDestroy 输出保留，日志不进入控制事件且正常关闭只发一次 storage-closed。

针对性 17/17（15.84 秒）与 18 Mach-O/406 Java 资源包检查通过，包括强制 Zip64 的压缩 APK/OBB 资料库导入、库重开、CRC/长度/元数据拒绝、无覆盖清理、真实 DEX 的中文/法文/时区和打包 Java 的输入/失焦继续/暂停/正常关闭。最终输出隔离/流式复核 2/2（3.22 秒），最终默认 **141/141（201.91 秒）**；build 17 经 CUA 单次启动，PID **25881**，主窗口 AX/截图确认原有 11 个应用。源码 [aa2cdbf](https://github.com/ruabbit/Husk-macOS/commit/aa2cdbf925d67fb30b351e7f10db93947ab0e2a5) 与 main 2c3af7a 已正常推送并读回，[CI 39884106041](https://github.com/ruabbit/Husk-macOS/actions/runs/39884106041) completed/success，构建/包检查/36 项 hosted 核心回归（42.59 秒）和 P0 memory/core 通过；完整记录见 progress.md。MacBook 物理电源切换、真实大包/认证 Play 下载与 iOS 真机仍未验收。没有运行真实用户游戏或 Android VM。WebView 导航/Activity 替换保存等开放项继续保留；本轮优先接入新增上游功能，不把它们标为完成。

## 2026-10-22：单个 WebView 的保存与回收，build 16

两远端 fetch 无新增，upstream/main=2df074b 仍是 main/macOS 祖先，main=cc99757；没有合并冲突。再次对照 TLReport.nativeEngine、TLUnityView、project.yml、macOS 的 CMake/能力判断/Runner、共享 PlayAPI/登录和固定图形依赖，没有新增引擎/Store/图形增量。

会话内直接 WebView.destroy 现在保留原 Java 对象和插件，先执行受控保存，再经过 JavaBridge 与 AppMain 排空回执后卸载 WebKit。替代视图可继续运行；整场停止会等待正在回收的视图。重复销毁不重复保存，失败/超时保持为最终 storage-closed 的否决条件。AndroidX WebMessageListener 在 AppMain 实际投递后回执，ReplyProxy 可完成保存回复；listener 异常不会静默成功。空白卸载文档不再重新注入应用启动脚本。

唯一 build/macos 已原位更新 **3.0.0 / build 16**：默认 **137/137（190.34 秒）**、**34 项 Java WebView（97.65 秒）**、**18 Mach-O / 406 Java 资源**包检查通过。CUA 单次启动当前 Product/PID **52520**，AX/截图确认原有 11 个应用与可见图标；代码 [54910cc](https://github.com/ruabbit/Husk-macOS/commit/54910cce15f12f4a4def176010c7a04a1686f2d8) 已推送并读回，CI [39705343544](https://github.com/ruabbit/Husk-macOS/actions/runs/39705343544) 已 completed/success，构建/包检查、34 项 hosted 核心回归及 P0 memory/core 通过。完整交付见 [progress.md](progress.md)。新增 10 项真实 DEX 回归覆盖 direct destroy、无替代视图、重复/暂停、失败/超时、整场停止交叠与 AndroidX listener/ReplyProxy。构建和 fixture 不代表真实游戏或第三方插件验收。

## 2026-10-21：应用主动关闭保存，build 15

两远端均无新增，upstream/main 保持 `2df074b`、main 保持 `cc99757`，无需合并或处理冲突。本轮将最后 Activity 的 `finish()` / 整栈 `finishAffinity()` 接入已有 Web 保存阶段，保存完成前保留 Java 桥和 AppMain；Activity 替换、子页返回、重复请求及失败回执有真 DEX 验证。应用自行关闭也受监督器原有 30 秒期限约束。

当前候选 **3.0.0 / build 15**：默认 **127/127（143.77 秒）**、其中 **24 项 Java WebView（63.07 秒）**、**18 Mach-O / 406 Java 资源**包检查通过。CUA 单次启动 Product/PID **18451**，主窗口 AX/截图确认原有 11 个应用。源码 [c549924](https://github.com/ruabbit/Husk-macOS/commit/c54992447ec80e59de9fd995b3258c2a476e888d) 已推送，CI [39541085280](https://github.com/ruabbit/Husk-macOS/actions/runs/39541085280) 已 completed/success，34 项 hosted 核心回归、构建/包检查和 P0 memory/core 通过；完整交付见 [progress.md](progress.md)。首轮两个既有 Vulkan 测试出现系统 Metal 内部错误/超时，未改变图形代码/配置/断言即在原配置复核和完整复跑通过，原因仍待观察；首次日志保留。

再次核对上游引擎分类、TLUnityView/project.yml、CMake/资料库/Runner、Store 登录和图形依赖，没有其他增量。下面 Web 协议与开放项已缩小到实际未完成范围；本轮没有启动真实用户游戏，也不把 fixture 保存重开作为真实应用兼容。

## 2026-10-20：WebView 关闭前保存，build 14

两远端 fetch 后没有新提交，upstream/main 仍是 `2df074b`；main 保持 `cc99757`，无重复合并或冲突。本轮继续平台待办，在 Java 桥仍存活时交付受控保存阶段，再完成 Android 和 WebKit 双侧关闭。原先的“尚缺保存阶段”已落地，剩余范围见下方 Web 存档协议与开放项。

唯一候选 **3.0.0 / build 14** 通过默认 **115/115（110.75 秒）**、**18 Mach-O / 406 Java 资源**包检查，共享 Web host 的 iOS 语法检查也通过。WebView 的 13 项后台回归验证插件与即时 UI 写入、显式异步保存重开、暂停关闭和各类失败；真实应用兼容仍需另验。CUA 单次启动后核对 PID **67505** 与完整 Product 路径，已有绑定只读 AX/截图确认原有 11 个应用。代码 [ee26f7f](https://github.com/ruabbit/Husk-macOS/commit/ee26f7f0bd49b8bb0380e58a65aee8646d04accf) 已推送并读回，CI [39371120881](https://github.com/ruabbit/Husk-macOS/actions/runs/39371120881) 构建、包检查与 33 项 hosted 核心回归成功；完整交付在 [progress.md](progress.md)。

本轮再次对照 TLReport.nativeEngine、TLUnityView、project.yml、CMake/资料库/Runner、Store/Play 与图形依赖；没有新引擎/Store/图形增量。AppKit 窗口、固定画布、输入/手柄、默认失焦继续与原有正常关闭检查保留。

## 2026-10-19：运行时与原生文件选择器，build 13

已核对 `cedb01e..2df074b` 的 **4 个提交 / 29 个路径**，origin 两分支无外来提交。先普通合并到本地 main `cc99757`，再合回 macOS。LoadedApk、AppRunner、ContextImpl 三处冲突按意图解决：Context 与 ActivityThread 共用单一 LoadedApk，保留 component factory、自定义加载器、provider 顺序和 NativeActivity 双侧关闭。真 DEX 验证反射状态的一致性。

当前唯一 Product 已更新为 **3.0.0 / build 13**，保留 VM=ON 和依赖缓存。最终 **默认 CTest 107/107（72.19 秒）**及 **18 Mach-O / 406 Java 资源**包检查通过。CUA 按完整路径单次启动，PID **39849**；主窗口 AX/截图确认原有 11 个应用与图标。早期 CUA 退出失败已解除，用户明确授权在无游戏/VM时自行强制退出空闲 Husk，每日任务已保存该规则；实际构建前旧 Husk 已自行退出，没有替换活动候选。代码 **ee5d553** 与 main **cc99757** 已推送并读回；[CI 39185361624](https://github.com/ruabbit/Husk-macOS/actions/runs/39185361624) 构建/包检查/33 项 hosted 核心测试及 P0 memory/core 成功。完整证据见 [progress.md](progress.md)。可见游戏内文件面板和真实应用兼容不由这些后台回归代替。

| 本轮增量 | macOS 实际实现与验证边界 |
| --- | --- |
| Java 文件选择器 | GET_CONTENT / OPEN_DOCUMENT / 媒体 PICK 接到 NativeRunner 的 NSOpenPanel；支持 MIME 类型、多选和取消，启动期请求会显示实际游戏窗口。选择内容流式复制到该游戏 cache/picked，0600 文件、同名分目录；取消/失败整批回滚。Java 仅发只读 URI，拒绝未选择路径、写入和删除；重复请求拒绝新请求以防无 request-ID 的宿主回包串线；关闭先取消/排空复制再销毁 Android。真实 DEX 已验多选/读取/元数据/取消/重复请求/关闭，后台 Mac 复制与 MIME 回归已过。可见面板交互、真实应用，以及跨会话 persistable URI 尚未验收 |
| Application / loader internals | 上游 ActivityThread、LoadedApk、Instrumentation 状态合入；既有 attachBaseContext 后加载器采用保留。NativeActivity 真 DEX 反射检查 mPackages/mBoundApplication/Context 指向同一 LoadedApk，currentApplication 与 Instrumentation 可用；未重跑 Egg，Play 密钥问题保持开放 |
| .NET 基础运行时 | /proc access、APK 原生库读取、Linux arm64 信号上下文、Mono AOT 代码区限定、依赖库 dlsym 和 RX/RW 排序已进入 NativeRuntime。真实 ELF 验证 Mono 元数据不被当作 syscall 重写及代码仍可执行；运行时检查 96 个 4 KiB 偏移映射回收、proc、非崩溃信号、实际 ELF 文件内容及依赖符号查找。没有实际 .NET 应用兼容结论 |
| 合并发现的映射/文件问题 | 修复上游固定 64 个映射表溢出后无法回收、部分 munmap 误删整个映射；改动态记录，暂不支持的部分释放明确 EINVAL 并保留整段。可执行映射拒绝时回收偏移记录；读取/mprotect 失败不再成功返回。原生库提取改唯一临时文件同步后原子替换，避免同名临时文件并发覆盖 |
| Native HLE 与框架 | SystemClock、SharedPreferences 浮点/长整数默认值、FileOutputStream 已编入，新增 HLE 回归覆盖时钟、值与追加/关闭后写入异常。其他 Choreographer/ListView/NetworkSecurityPolicy 等共享 framework 变更纳入新 DEX；这不是完整 SharedPreferences HLE 持久化或真实游戏验收 |

核对了 TLReport.nativeEngine、TLUnityView、project.yml、Play/登录和图形依赖。本轮没有新增引擎、Store 或图形依赖 pin；macOS 的 .NET/Java 分发已存在，新钩子在实际 Java profile 中连接。独立 Runner、固定画布、键鼠/手柄、默认失焦继续和 storage-closed 协议保留。WebView 卸载前保存、真实游戏保存重开、Play/VM/P6 等下文开放项未关闭。

## 2026-10-18：已交付的 3.0 基线

上游核对日期：2026-10-18（Asia/Shanghai）。本轮 `a3407fc..cedb01e` 共 **64 个提交、82 个路径**；正式 **3.0 tag = cffaf8b**，上游 iOS build 129。origin 两分支没有外来新提交；先普通合并到本地 fork main **308793d**，再合回 macOS。七个冲突按语义解决，保留自定义 Java ClassLoader、NativeActivity 关闭协议、Mac 报告来源和加载器混合页修复。

本轮交付 **3.0.0 / build 12**，仍使用唯一 `build/macos`、VM=ON。以下新增接入已通过 **19 项针对性回归、默认 CTest 103/103（82.65 秒）**及 **18 Mach-O / 406 Java 资源**包校验。代码 **70c2764** 与 main **308793d** 已正常推送并读回 SHA；[CI 39087010940](https://github.com/ruabbit/Husk-macOS/actions/runs/39087010940) 构建/包检查/29 项 hosted 核心测试成功。CUA 单次重开 Product、首页截图和选择交互通过，详情导航后连接断开。完整交付在 [progress.md](progress.md) 最上方记录。构建和 fixture 通过不等于真实游戏兼容。

| 本轮上游能力 | macOS 实际接入与证据 |
| --- | --- |
| 旧 Unity TouchScreenKeyboard | 主线程 MacTextInput 与 UnityMain 队列接通，处理组合文字提交、退格、完成/取消和多行；UTF-16 选择偏移。生产驱动测试覆盖中文/emoji、长度限制和线程顺序，未声称实体输入法或旧 Unity 真游戏已通过 |
| Store 流式下载、48 APK、OBB | 共享 FileStreamer 直接写 0600 文件，支持取消、HTTPS 重定向和流量上限；48 APK 完整签名导入；main/patch OBB 与 APK 一次安装并保存大小/摘要。Play 与 XAPK 两条导入路径、重开和无效资源拒绝通过。运行时映射本应用 OBB 目录，Java/HLE getObbDir 与真实 open/read 通过 |
| Go 数据与裸 syscall | Go 标记 ELF 的只读数据使用一致视图，保留 4 KiB 指令页与 16 KiB 宿主页区分。新增测试发现普通 4 KiB ELF 的只读重定位和 ADRP 不一致，已统一按实际 PT_LOAD 地址分类；3 种真实 ELF 布局验证数据/代码指针和 syscall NZCV、完整 q8–q15。不是完整 Go 应用兼容验收 |
| Java framework / AppComponentFactory | 实际 factory 可以在 Application 前安装 ClassLoader，保留 attachBaseContext 后再次采用自定义 loader。真实 DEX 验非 ASCII 类名、缺可选类的可捕获错误、超过 256 MiB 的数组拒绝、Wi-Fi 对象和 Drawable 克隆；NativeActivity 生命周期回归保留 |
| Godot 4 / NativeBridge | 默认传递 OpenGL Compatibility 参数，显式 Vulkan 环境选择保持；GodotNativeBridge 提供 RenderView/InputHandler。真实 ELF 经完整输入/暂停/销毁验证；Vulkan override 测试只核对参数，没有运行 Vulkan Godot 游戏 |
| 外部纹理 shader | 新共享重写器通过实际 ANGLE 对普通与 samplerExternalOES shader 的编译，两种 ES31 shim 状态均通过；没有采集摄像头或验证真实外部视频图像 |
| 3.0 首页与兼容性日志 | Mac 首页加入选中游戏展示、直接启动/显示窗口和应用列表选择，保留原生资料库/Store/帮助；圣诞装饰限 12/1–1/6。报告日志默认不附带，用户选择后可预览/移除，发送所见快照，最多读取 400 KB；离线协议验证，无公共报告发送 |
| NativeActivity 分类 | 新导入采用上游 manifest/DEX 检查；旧 NativeActivity 标签按 APK 摘要在内存重新扫描，读取资料库不重写用户索引、设置或存档；Runner 继续独立核验入口 |
| CJK / iOS 特性 | macOS 已包含固定 Android 系统字体及 CJK，不需要上游为精简 iOS 包新增的按需下载；未删字体或改为未固定的远程来源。iOS 15.5/JIT 配对/UI 兼容代码保留，上游 graphics 依赖 pin 本轮未变化 |
| Console / VM 差异 | PS4 文本输入与 install_package ABI 已进未打包的 ConsoleHostRuntime，真实核心/包导入/关闭所有权仍未交付。Mac VM 不自动启动，也不使用 iOS 的快照下载器；仍最多 32 APK，明确拒绝 OBB 以免静默漏资源；未修改 Android 磁盘 |

fork [PR #1](https://github.com/ruabbit/Husk-macOS/pull/1) 已合并；[上游 PR #118](https://github.com/Leviidev/Husk/pull/118) 于 2026-10-18 按用户要求关闭，未合并。自该日起，修复、适配、提交与 PR 只在 `ruabbit/Husk-macOS` 完成；上游继续只读核对和同步，不新建、重开或更新上游 PR/issue，也不发表评论，除非用户重新明确授权。PR #82 上次接口返回 404，已采用的单例修复保留。

2026-10-18 上一候选为 **3.0.0 / build 10**。NativeActivity 已补真实 Java Application/ClassLoader/JNI/NDK 启动桥及 Android 安装路径映射；默认 **CTest 96/96（82.91 秒）**、18 个 Mach-O / 406 个 Java 资源校验通过。CUA 单次启动 Product，PID **89011**，主窗口显示当前资料库 **11 个应用**。真实 Egg 已进入 Java 密钥导入错误路径，尚未进入游戏原生入口，详见下方开放项和 [启动报告](2026-10-18_reverse-egg-startup-report.md)。

本轮之前的候选 **3.0.0 / build 11**：补齐软件 AES/GCM KeyProtection 导入、受限密钥句柄与原子持久化，默认 **CTest 97/97（77.84 秒）**、18 个 Mach-O / 406 个 Java 资源检查通过；CUA 单次重开，Product PID **7656**。这只修复 Play 返回密钥后的接收能力，Egg 所需的真实 Play 下发服务继续开放，本轮没有重复启动 Egg。

## 2026-10-17 的 3.0 预发布接入

| 上游变更 | macOS 接入和验证 |
| --- | --- |
| 运行时与应用同名 ELF 隔离 | 共享 loader 已编入 NativeRunner；真实 arm64 ELF 测试覆盖 APK/解包目录、应用先加载/运行时先加载、依赖重定位、构造函数、dlsym 和重复加载；Conscrypt SSLContext 在应用自带 libcrypto 时实际初始化通过 |
| Resources 密度与框架图片 | 新 framework DEX 已打包；真实 DEX 使用空 DisplayMetrics + 480 dpi Configuration，核对密度与图片加载，再切换 mdpi 验证固定 framework-res 的图像回退 |
| TextView / View | 子类在绝对和相对 compound drawable 接口间转发不会再递归；cancelLongPress 与绘图缓存重用/缩放后释放/销毁由真实 DEX 检查 |
| Picture / RenderNode | 已接入上游的替换位图释放；真实 DEX 连续改变尺寸并核对输出像素、discardDisplayList 后不再绘制与内存用量归零。没有把这些断言当作长期内存压力测试 |
| JIT 区域分配、诊断与 TrollStore | iOS 修复完整保留；共享 C 文件及 iOS JIT 文件 SDK 语法检查通过。macOS 本来由独立进程持有各自 JIT，保留现有内存/权限验证，不显示 iPhone 的 StikDebug 操作提示 |
| Console / Mac harness | 采用上游弱符号门控，保留本地停止与线程回收协议；console 回归全部通过。真实 PS4 core 仍未打包 |

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
| Java / Dalvik / Unity 6 | 受控 boot class path、固定 Android 资源、源码构建 framework DEX、48 个 APK、触摸/键盘/IME/手柄、暂停/销毁和 worker/SQLite 检查；InputEvent 父类 getDevice；随包 Vulkan 与 Java/TextureView 合成 | 生产 fixture、真实 DEX、打包会话通过；Hole.io 已取得真实拖动和黑色洞口证据，关闭/保存重开仍未通过；其他游戏逐个验证 |
| Cocos 无 FMOD、SDL 无 DXVK、Python、Flutter、libGDX、Java、React Native、.NET | 与上游 TLReport.nativeEngine 一致，进入 Java profile | 不因为分类命中就声称插件或真实游戏兼容 |
| Unity 旧版 | 已有独立驱动、固定画布、输入和确认销毁保留 | 旧 Unity IME 已于 build 12 接入并经过驱动/组合文字 fixture；实体输入法和旧样本黑屏/崩溃仍须真游戏验证 |
| Cocos + FMOD | 编入共享驱动、JNI 和文本栅格化；原生 profile、触摸/按键/手柄、IME hooks、GL 线程暂停和关闭 | 真实 ELF/ANGLE 与生产会话通过。Cocos 没有 renderer destroy，按其 Android nativeOnPause 保存，再 join/检查 worker；FMOD 线程残留会明确失败 |
| Godot / GameMaker | 编入共享驱动，资料库/Runner 分发，方向与固定画布、触摸/按键、同线程暂停；Godot ondestroy / GameMaker Exit 后关闭 | 真实 ELF 与生产会话通过；缺少 destroy 拒绝回执，暂停失败不会被后续成功销毁覆盖；真实游戏和插件另验 |
| SDL + DXVK | launcher Activity 与分包传递、MoltenVK 配置、SDL/UI 线程生命周期、触摸/按键/手柄、文本 hooks | nativeSendQuit → SDLMain 完成/join → nativeQuit，再检查 worker；正常及缺 destroy 测试通过 |
| Rockstar | 原生 profile、触摸/手柄，Escape 映射 Android Back；同线程暂停、从 DEX 核对无参销毁函数后关闭 | 真实 ELF 与生产会话通过；上游的 Social Club/影片等兼容限制保留，未验证真实 GTA |
| Unreal | UE4 profile 复用真实 NativeActivity/UE JNI 驱动，配置 Vulkan，解析 manifest 与分包 | 含 libUE4 的 Android ELF fixture 走完整打包路径，回调/输入/保存退出通过；真实 Unreal 游戏未验收 |
| NativeActivity | 库名/方向/alias、分包、真实 Java Application/ClassLoader/JNI→NDK 桥、触摸/键盘/手柄；同线程失败清理及 Java/原生双侧关闭 | DEX/ELF 和签名分包的生产会话回归通过。Egg 已安装自定义加载器并完成 PairIP JNI_OnLoad，但缺 Play 加密密钥/传输服务，未进入游戏原生入口；不能声称旧 PLT 初始化或真实游戏已通过 |
| Capacitor / Cordova / Ionic | 独立无 JIT 权限的 WebRunner，复用上游 WebAppRuntime 桥；APK 资源校验/受限提取、原生窗口/IME、返回、暂停定时器/动画/媒体和输入屏蔽 | 两种引擎的真实 WebKit fixture 通过 localStorage/IndexedDB 退出重开、清除后不复现；本地自定义 scheme 的 document.cookie 为空，不宣称 cookie 或 service worker 兼容 |
| Java 内嵌 WebView | 保留固定画布/透明合成和按存档 UUID；主程序请求关闭时先在 Java 桥存活期间交付受控保存事件并等待显式异步保存，再销毁 Android、卸载 WebKit、等待 cookie/网络回调，组合两侧回执 | 真实 DEX + 打包 NativeRunner 验证插件/UI 队列写入、localStorage/IndexedDB/最终 cookie/进程重开、暂停关闭、事件单次交付、旧 UUID/同包隔离及删除；插件异常、脚本/Promise 拒绝、超时、跨来源子 frame 与迟到桥接均拒绝成功回执。真实应用另验 |
| Minecraft / GameActivity | 既有独立 Runner、固定画布、鼠标修复、存储关闭保留 | 旧的真实样本证据仍有效，但本轮没有启动用户游戏 |
| Geode | 共用上游版本索引，Geometry Dash 每游戏开关、下载/取消/更新、Geode 4 内嵌资源和 5+ 独立资源；完整缓存可离线启动；原子安装、APK 版本/摘要和缓存 SHA 校验；独立 Cocos Runner 注入 | 离线缓存、Android ELF 构造函数/JNI、同大小更新、输入/暂停/关闭和真实打包会话通过；启用后加载失败会阻止启动，不静默关闭 Geode。真实 Geometry Dash/Geode 模组、实际网络下载和前台开关未验收 |
| 图形依赖 | 固定 MoltenVK 1.4.2 / SPIRV-Cross，并实际应用上游 zero-init-stride 补丁 | 缓存记录补丁 SHA，打包前拒绝旧缓存，包内附构建记录/补丁；针对随包 MoltenVK 的 workgroup 零初始化 shader 编译回归通过 |
| PS4（2.0 后新增） | 上游 Console ABI、JIT arena 和手柄快照已编入独立 ConsoleHostRuntime / MacConsoleProbe；沿用 Hardened Runtime 与现有 JIT 权限，增加停止和宿主线程回收检查 | 5 组后台测试通过，含真实 arm64 JIT 代码、ABI 拒绝、合并手柄、暂停释放、继续重发、断连及停止未确认；合成模块帧数恒为 0，不证明游戏渲染。真实核心及 probe 均未打包进 Product；资料库/独立 Runner、窗口和存档完成协议仍开放 |

## Web 存档协议

每个 `Saves/<id>/web-store.json` 保存独立 UUID，WebRunner 使用 macOS 14 的 `WKWebsiteDataStore(forIdentifier:)`。数据库由系统 WebKit 保管，不把其数据库文件复制为另一份游戏存档。关闭先发页面生命周期事件，完成脚本顺序屏障，停媒体、卸载文档，等待 cookie/data-record API 回调，再发 `web-storage-detached`。该回执明确为 `webkit-managed`，不是 native 的 `storage-closed/destroyed`，也不声称系统断电时的全局 fsync 保证。监督器核对 session、runtime、UUID 和进程回收。

用户清除存档时，先在同一个 WebRunner bundle 中删除该 UUID 的数据存储，成功才删除标识与资源缓存。失败保留标识；删除过程中禁止同应用重新 prepare。单独移除应用继续保留存档。测试验证进程重开和实际删除，而不只校验 JSON 回执。曾发现静态删除 API 在未初始化 WebKit 的辅助进程中崩溃，已增加独立非持久化 WebView 初始化，并通过删除/重建回归；未反复运行未修复版本。

Java 内嵌 WebView 使用 `Saves/<id>/java-web-store.json`，数据归 NativeRunner 的 WebKit bundle 所有。新存档使用独立 UUID；升级前已有 Android `data` 的存档沿用原来的包名 UUID，并记录 `legacyPackage`，避免换标识后失去旧数据。旧包级存储可能被其他资料库共用，因此清除这类存档只解除当前关联并删除 Android 数据，保留旧 WebKit 共享字节；下一次启动分配独立新 UUID。普通独立存档通过 NativeRunner 删除该 UUID，成功才移除存档目录，失败保留目录与标识。测试核对旧哈希的固定 UUID、进程重开与真正删除后的 store 枚举结果。

主程序停止会话或 guest 最后 Activity 请求 finish/finishAffinity 时，先保持 AppMain 与 JavaBridge 消息循环可用，取消普通对话框/导航/资源请求，保留已接受的插件请求，停止媒体和旧定时器/动画；再运行受控保存阶段。文档启动时安装的 capture gate 只允许该阶段的 `beforeunload`、`visibilitychange`、`pagehide`、`unload`，后续真实空白导航不重复交付。同步 Java 插件可在此阶段执行；应用通过事件上的 Husk 扩展 `event.waitUntil(promise)` 登记异步保存，宿主用 WebKit `callAsyncJavaScript` 等待它。插件已投递的即时 AppMain 消息排在 Activity 销毁前。每个 WebView 的媒体停止和保存阶段共用 6 秒上限，失败状态保留到最终关闭；没有延长监督器原来的 30 秒停止期限。监督器在第一个合法 `stopping` 事件就启动该期限，覆盖应用/窗口自行关闭；后续 heartbeat 不续期。

阶段完成后才停止 Android：等待 Activity、框架 worker、preferences 和 SQLite；WebView 销毁发起真实文档卸载，回收 scheme-handler 引用环，等待网络取消、cookie 写入及 data-record 回调。只有两侧完成，才写含 `web.saveStage=prepared` 的 `storage-closed`；未使用 WebKit 的会话仍显式写 `unused`。监督器继续核对启动、磁盘和事件中的 UUID。WebKit 存储仍为 `webkit-managed`，不是系统数据库 fsync 或断电持久性保证。

这是宿主生成的生命周期事件（`isTrusted=false`），`waitUntil` 是 Husk 扩展；未登记的任意异步任务、依赖真实浏览器 trusted unload 的代码及跨来源 child frame 尚未支持。同源子 frame 递归保存；无法读取的跨来源 frame 明确失败。保存阶段完成后仍调用 Java 插件、Java 插件抛错、脚本/登记的 Promise 拒绝和超时均不能获得成功回执，即使 Android 销毁本身成功。`macos-java-web-late-bridge` 保留这一反例。最后 Activity 的 `finish()` 与整栈 `finishAffinity()` 已通过可选宿主回调交接；先让已排队的 Activity 启动执行，再复查是否整个会话退出。非最后 Activity 继续返回结果/恢复父页面，交接后拒绝再次启动或重建 Activity。无宿主回调的驱动保留原路径；`Process.killProcess` 仍不能获得正常销毁回执。会话继续运行时直接 `WebView.destroy()` 的受控保存已接入：Java 普通视图 API 立即关闭，保存阶段仍保留原插件与资源事件；媒体/脚本上限 6 秒，JavaBridge → AppMain 排空回执另有 2 秒期限，缺失回执不能视为成功。host-stop 等待这些已从活动视图表移出的视图，失败状态一直保留。保存完成后去掉将来文档的注入脚本再导航到空白页，避免 AndroidX 插件在卸载页重启；原页面单次生命周期 gate 保留。同一 WebView 的 loadUrl/页面替换已接入受控保存；2026-10-25 又验证页面许可、同文档锚点、连续保存代际及 GET 历史重建，并拒绝已保存的非 GET 历史项自动重发。2026-10-26 已补导航保存途中 host-stop 接续原保存与取消待放行导航，保持原六秒期限；回环 HTTP 的存储/插件重开与请求次数有真 DEX 证据。Activity replacement/recreate 销毁前的更多顺序，以及真实 HTTP 应用和第三方插件链仍须另验。未注入保存脚本的加载中文档仍会失败，不能把时间经过当成已保存。通用 `Thread.interrupt0`/阻塞唤醒并未因此实现；框架线程池退出与 guest worker 检查继续保留。

## 后续开放项

1. Java 内嵌 WebView：受控卸载前保存阶段已在 2026-10-20 接入，最后 Activity/整栈主动关闭和直接 WebView.destroy 的逐视图保存已接入；2026-10-24 又补同一视图主文档导航前保存，Java `loadUrl` 的 localStorage/IndexedDB/插件重开与拒绝/超时 sticky 失败已有真 DEX 回归。2026-10-25 补导航许可、锚点、连续保存和已封闭 GET 历史页重建，非 GET 历史拒绝自动重发并保持当前页面可用。页面脚本直接 file URL 尚未单独验收。2026-10-26 又补回环 HTTP 保存重开、重定向/历史请求次数和导航保存/host-stop 交叠；停止等待原保存且不重置期限。下一步包括历史恢复检查与 host-stop 交叠、导航保存与逐视图 destroy 专门回归、实际 HTTP 应用/插件的持久化、Activity replacement/recreate 销毁前的更多顺序、加载中文档与跨来源 frame 的受控保存，以及未登记异步任务的明确策略；不能把合成生命周期或 fixture 当作真实应用验收。通用 Java Thread.interrupt/等待唤醒、macOS 14 实机、网络取消超时与 WebKit 进程异常恢复仍开放，保留 worker 检查和失败回执。
2. Geode：下载、配置、启动注入和存储关闭回归已进入 build 6。下一步使用独立存档验证真实 Geometry Dash、官方 Geode 发布包和模组，从设置开关、版本匹配下载到交互、保存重开；不要把自建 ELF 的通过当作这些外部程序已兼容。共享 GeodeUtils 的剪贴板、选文件/文件夹、openWebview、restartGame 仍继承上游的空实现/拒绝行为，需要实际使用证据后逐项适配。
3. 真实应用：按独立数据逐个验首帧、交互、保存重开和所需插件；实体手柄、前台 IME、全屏多显示器也需实际设备/窗口证据。禁止在没有相关修复时重复启动已知崩溃样本。
4. Egg：2026-10-18 已完成 Application/自定义 ClassLoader/provider/JNI/NativeActivity 桥、ContextImpl/LoadedApk 反射状态及 Android APK 安装路径映射。真实样本已记录 `Custom ClassLoader attached successfully`、`libpairipcore.so JNI_OnLoad -> 0x10006` 和成功打开 base.apk；最新阻塞为 `Encryption key not found in keystore`、绑定 `com.android.vending.securedatatransfer.IAntiTamperKeyTransferService` 失败。已出现游戏自带 Google Play 错误页，未进入游戏 ANativeActivity_onCreate，原先构造函数/PLT 的最终结果仍未知。最终 probe exit 0 与 Java 错误页正常关闭不能当作游戏通过。本地软件 AES/GCM 的 `setEntry(SecretKeyEntry, KeyProtection)`、用途/有效期/IV 检查和原子持久化已补齐，真实 DEX 跨进程回归通过；硬件包装密钥与真实 Play 下发服务仍缺。下一步核对合法安装的密钥下发及实际 Play Binder 环境，或完整 Play Android 对照环境；不得用假密钥/保护绕过/猜测地址补丁，不在缺少相关修复时重跑。详见 [Egg 启动调查与修复](2026-10-18_reverse-egg-startup-report.md)。
5. 三款游戏修复（2026-10-13）：跨 split/adaptive 图标解析、旧缓存升级、全 NativeRunner profile 的 Android 字体/CA 映射、有界 stderr 首尾保留和独立 supervisor.json 已实现。字体来自同一固定镜像，保留 CJK 和系统别名，旧配置的两个缺失名称在 lock 中记录兼容别名。实际资料库十款图标均已刷新，与隔离解码 PNG 一致，包含 Egg、War、Clash。
   - War Thunder：字体修复后成功生成三种 CJK 字体子集；随后补 `libvulkan.so.1` 映射和通用 NativeActivity 的 MoltenVK 配置。第二次探测的 RVA 0x5875dc4 空缓冲区崩溃进一步定位到 OpenSL 回调：宿主停止/清空操作没有等待正在读取的缓冲区和回调，游戏随后清空缓冲区。已修复排空/队列代际，补通用 NativeActivity 的 FMOD Java HLE。受控生命周期测试通过，第三次探测实际创建 Vulkan 设备/swapchain 并渲染 1280×720 的 Checking the data 加载页，5 项首帧/截图/失焦/暂停/恢复检查通过。
   - War 当前开放（2026-10-25 用户会话）：558F5F77/3BD9B1CE 的真实引擎日志均显示 Download complete、UPDATER_EVENT_FINISH，随后 Apple M1 Ultra / MoltenVK 1.4.2 创建 Vulkan 设备和 swapchain，命中 `vulkan: running on a blacklisted device` 并 exit 1；无 storage-closed。公开 Dagor Android 驱动的同文案路径调用 terminate_process(1)，具体 blacklist 条目仍需定位，不能据此声称 GPU 故障或绕过检查即可兼容。日志来自用户实际资料库 Logs 两会话与该游戏 logs/aces/debug0.clog、debug1.clog，仅只读分析，未重新运行或修改用户数据。10-13 的 F55D0587 曾停在 Checking the data 且自定义 DagorUpdater 未接通，现在只能作历史证据；当前不是该阻塞。仍需完成主菜单/玩法、正常关闭与存档重开。
   - Clash：日志修复后的单次探测输出 5,913,771 bytes，末尾仍保留 `exit(101)` 和 NativeRunner 实际退出 70。退出发生在原生库初始化期间；`JNI_OnLoad+0x12c4c` 是最近导出符号标注，不能当成已执行 JNI_OnLoad 的证据。静态原始 RVA 0x6207bc 为 exit(101) 调用，前置控制流经过 0x61a668；需要继续检查混淆初始化分支及其真实 OS/JNI 前置条件，禁止简单跳过 exit。
   - 日志/静态证据在 `build/logs/current-three-games-audit.json`、`current-icon-repair.log`、`current-war-thunder-repair/`、`current-war-thunder-audio-static.log`、`current-clash-repair/`、`current-egg-init-static.log`、`current-egg-init-relocations.log`、`current-clash-exit-static.log`。自动真实探测静音/不可见，存档位于独立输出目录；三款仍未通过完整运行验收。
6. Play：个人账号/passkey 仍被 Google 拒绝；只有本人真实登录成功且 Play 会话可用才通过。OBB 的 Play/XAPK 安装和原生读取已由 build 12 fixture 验证；真实网络 OBB/PAD、设备配置和已购交付仍待验收。当前同一 APK 版本增补/替换 OBB 被明确拒绝，保留原安装；下一步需让安装事务同时记录 APK 与资源代际，再接单独 OBB 导入，不能复用仅 APK 摘要的恢复判断。压缩包单条仍限 512 MiB（现有解包器上限），Play 流式下载总量限 4 GiB。
7. VM/P6：VM Minecraft 黑屏与持续 PCM 未通过；上游新增的 Android 删除/快照空间预检尚未映射到 Mac 独立 VM 数据管理，需先划清共享基础镜像与用户 overlay，再提供明确确认的删除入口并做隔离磁盘测试；QEMU/libssh/OpenSSL 许可、Android 对应源码和发行签名仍按发行门槛处理。
8. Hole.io（2026-10-13）：InputEvent.getDevice 的父类 JNI 查找与 Java Vulkan 合成已修复，最终 build 5 的后台真实游戏确认拖动、计分、正常黑色洞口以及暂停/恢复。证据在 `build/macos/TestResults/HoleCandidate/`，会话 E86FC7A5。仍需完成可见 AppKit 窗口鼠标拖动验收（CUA 详情导航 native pipe closed）、Unity 进程退出与 SharedPreferences/worker 关闭、保存重开和长期性能。UnityPlayerForActivityOrService 的销毁路径在 mProcessKillRequested 时调用 onUnityPlayerQuitted 后进入 UnityPlayer.kill → Process.killProcess；当前 host 如实保持失败状态。下一步核对该退出请求的真实时序与写入/worker 所有权，补覆盖该行为的 DEX fixture，再运行真实保存重开；不能忽略 killProcess 或直接发 storage-closed。Vulkan 目前同步读回到 Java 合成器，可进一步评估 GPU 共享纹理，但要保留 present 等待和独立 layer 所有权。
9. PS4：核心源码公开位于 [Leviidev/AetherPS4 的 husk 分支](https://github.com/Leviidev/AetherPS4/tree/d953592114581cf3e5bdb20229769ec2f69b2359)，已核对 macOS 模块入口。公开 [fex-snapshot](https://github.com/Leviidev/AetherPS4/tree/220ab1e6d5aec14e43428f97c75530fc0113ce08) 的 `FEXCore/include/FEXCore/Utils/AllocatorHooks.h` 没有核心 CMake 检测的 `SetJITHostHooks`，会关闭 `AETHER_FEX_HAS_JIT_HOST`；不能把退回自行分配 JIT 当作 Husk 宿主区域/上限已生效。上游脚本要求作者本地 `husk-fex` 分支，本次公开同名仓库接口返回 404，并非核心源码整体不可获取。
   - 下一步先固定公开核心、FEX 和子模块版本，取得或实现匹配的 host JIT hooks；FEX 与核心同时使用 `FEX_MAC_PHONE_PATH=1`，核心开启 `ENABLE_FEX_GUEST_CPU`、`ENABLE_SHADPS4_IOS_LIB`、`ENABLE_HUSK_MODULE`、`AETHER_MAC_PHONE_PATH`。在现有依赖缓存内验证 arm64 模块、单导出符号、依赖闭包和许可，不另建候选或降低权限约束。
   - 模块启动线程目前 detach，`shadps4_run_loop()` 返回后即报告 STOPPED，ABI v1 没有 worker join / 存档刷写回执。继续追到核心 `src/emulator.cpp:665–698`：RunLoop 创建周期写入游玩时长的 jthread，事件循环结束只更新游玩时长并关闭 Storage::DataBase，再调用 onRuntimeStopped；这段返回路径没有停止/join 该 jthread 或 guest workers。停止入口仅推送 SDL_EVENT_QUIT。需要补清楚各 worker 与游戏存档的所有权和完成信号，本轮 `husk_console_join()` 只回收宿主输入线程，不能据此发 native storage-closed。之后再接独立 ConsoleRunner、资料库导入/分发、固定画布与键鼠/手柄/暂停/退出，并验真实游戏保存重开。源码证据在 `build/logs/current-ps4-core-contract.log`、`current-ps4-fex-contract.log`，未运行真实 PS4 游戏。

检查入口：CMakeLists.txt、Models/NativeLaunch/SessionController、MacNativeDrivers、NativeRunner、WebRunner、WebApp.swift、build_macos_graphics.py；对照上游 TLReport.nativeEngine、TLUnityView.swift、AppWindows.swift、src/app/project.yml 和 Play。后续每日同步须同时交付平台适配、当前候选与相应验证，不能以 Git 祖先或旧测试替代。
