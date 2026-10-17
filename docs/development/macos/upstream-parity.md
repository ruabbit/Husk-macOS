# 上游功能与 macOS 接入现况

核对日期：2026-10-17（Asia/Shanghai）。upstream/main 从 **4c03823** 到 **a3407fc**，11 个提交、19 个路径；源码版本号已改为 **3.0.0**，远端尚无 3.0 tag，最新发布标签仍为 **2.0 = e02ac68**。origin 两分支没有外来新提交；上游先普通合并到 fork main **fa9aa3f**，再合回 macOS，无文本冲突。

本轮共享 loader 的运行时/应用库隔离、Java 配置密度及框架图像回退、TextView 递归修复、Picture/RenderNode/绘图缓存释放，已编入 macOS NativeRunner 和重新构建的 framework DEX。新增 7 项回归验证 APK/解包库、两种加载顺序、真实 Conscrypt 与应用 libcrypto 共存及 Java 绘图/资源行为。上游共享 JIT 分区和 TrollStore/JIT 提示属于 iOS；macOS 保留独立 NativeRunner/VMRunner 与权限模型。P0 classic harness 因新增 tl_jit_reserve_bottom 漏链接的问题已复现并修正，真实 ELF 执行通过。

**3.0.0 / build 9** 在唯一 `build/macos` 原位构建，VM=ON；默认 **CTest 90/90（70.58 秒）**，包内 **18 个 Mach-O / 406 个 Java 资源** 校验通过。CUA 单次打开当前候选，主窗口显示原有 10 个应用，Product PID **53326** 已核对。源码 **c24f0ca** 和 main **fa9aa3f** 已正常原子推送并读回一致；[CI 38990038463](https://github.com/ruabbit/Husk-macOS/actions/runs/38990038463) 已完成并成功，构建/包检查、26 项 hosted 核心测试和 P0 memory/core 通过，hardware job 跳过。详见 [progress.md](progress.md)。旧的 2.0/手柄/Geode/窗口/Store/图形接线均已复核；不能将此次版本更新写成 PS4、真实游戏或 Play 登录验收。

fork [PR #1](https://github.com/ruabbit/Husk-macOS/pull/1) 已合并；[上游 PR #118](https://github.com/Leviidev/Husk/pull/118) 于 2026-10-18 按用户要求关闭，未合并。自该日起，修复、适配、提交与 PR 只在 `ruabbit/Husk-macOS` 完成；上游继续只读核对和同步，不新建、重开或更新上游 PR/issue，也不发表评论，除非用户重新明确授权。PR #82 上次接口返回 404，已采用的单例修复保留。

## 3.0 本轮变更

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
| Java / Dalvik / Unity 6 | 受控 boot class path、固定 Android 资源、源码构建 framework DEX、32 分包、触摸/键盘/IME/手柄、暂停/销毁和 worker/SQLite 检查；InputEvent 父类 getDevice；随包 Vulkan 与 Java/TextureView 合成 | 生产 fixture、真实 DEX、打包会话通过；Hole.io 已取得真实拖动和黑色洞口证据，关闭/保存重开仍未通过；其他游戏逐个验证 |
| Cocos 无 FMOD、SDL 无 DXVK、Python、Flutter、libGDX、Java、React Native、.NET | 与上游 TLReport.nativeEngine 一致，进入 Java profile | 不因为分类命中就声称插件或真实游戏兼容 |
| Unity 旧版 | 已有独立驱动、固定画布、输入和确认销毁保留 | 旧 Unity IME 仍未接；旧样本黑屏/崩溃不被本轮 fixture 结果覆盖 |
| Cocos + FMOD | 编入共享驱动、JNI 和文本栅格化；原生 profile、触摸/按键/手柄、IME hooks、GL 线程暂停和关闭 | 真实 ELF/ANGLE 与生产会话通过。Cocos 没有 renderer destroy，按其 Android nativeOnPause 保存，再 join/检查 worker；FMOD 线程残留会明确失败 |
| Godot / GameMaker | 编入共享驱动，资料库/Runner 分发，方向与固定画布、触摸/按键、同线程暂停；Godot ondestroy / GameMaker Exit 后关闭 | 真实 ELF 与生产会话通过；缺少 destroy 拒绝回执，暂停失败不会被后续成功销毁覆盖；真实游戏和插件另验 |
| SDL + DXVK | launcher Activity 与分包传递、MoltenVK 配置、SDL/UI 线程生命周期、触摸/按键/手柄、文本 hooks | nativeSendQuit → SDLMain 完成/join → nativeQuit，再检查 worker；正常及缺 destroy 测试通过 |
| Rockstar | 原生 profile、触摸/手柄，Escape 映射 Android Back；同线程暂停、从 DEX 核对无参销毁函数后关闭 | 真实 ELF 与生产会话通过；上游的 Social Club/影片等兼容限制保留，未验证真实 GTA |
| Unreal | UE4 profile 复用真实 NativeActivity/UE JNI 驱动，配置 Vulkan，解析 manifest 与分包 | 含 libUE4 的 Android ELF fixture 走完整打包路径，回调/输入/保存退出通过；真实 Unreal 游戏未验收 |
| NativeActivity | 既有库名/方向/alias、分包、触摸/键盘/手柄与关闭协议保留 | Egg 仍在 libegginc.so 构造函数的未重定位 PLT 跳转失败；没有重复运行未修复样本。PR #82 单例修复已本地采用；本次 PR/issue 接口均返回 404，无法确认远端当前状态 |
| Capacitor / Cordova / Ionic | 独立无 JIT 权限的 WebRunner，复用上游 WebAppRuntime 桥；APK 资源校验/受限提取、原生窗口/IME、返回、暂停定时器/动画/媒体和输入屏蔽 | 两种引擎的真实 WebKit fixture 通过 localStorage/IndexedDB 退出重开、清除后不复现；本地自定义 scheme 的 document.cookie 为空，不宣称 cookie 或 service worker 兼容 |
| Java 内嵌 WebView | 保留固定画布/透明合成/Java Web 桥；按存档绑定 WebKit UUID，完整卸载文档与回收 IO/桥接 worker，等待 cookie 写入与 WebKit 回调，组合 Android 销毁和 WebKit 托管回执 | 真实 DEX + 打包 NativeRunner 验证 localStorage/IndexedDB/最终 cookie/进程重开、旧 UUID 关联、同包隔离、删除/失败保留；Android 销毁失败、标识改变、卸载时迟到 Java 插件调用均拒绝成功回执。真实应用另验 |
| Minecraft / GameActivity | 既有独立 Runner、固定画布、鼠标修复、存储关闭保留 | 旧的真实样本证据仍有效，但本轮没有启动用户游戏 |
| Geode | 共用上游版本索引，Geometry Dash 每游戏开关、下载/取消/更新、Geode 4 内嵌资源和 5+ 独立资源；完整缓存可离线启动；原子安装、APK 版本/摘要和缓存 SHA 校验；独立 Cocos Runner 注入 | 离线缓存、Android ELF 构造函数/JNI、同大小更新、输入/暂停/关闭和真实打包会话通过；启用后加载失败会阻止启动，不静默关闭 Geode。真实 Geometry Dash/Geode 模组、实际网络下载和前台开关未验收 |
| 图形依赖 | 固定 MoltenVK 1.4.2 / SPIRV-Cross，并实际应用上游 zero-init-stride 补丁 | 缓存记录补丁 SHA，打包前拒绝旧缓存，包内附构建记录/补丁；针对随包 MoltenVK 的 workgroup 零初始化 shader 编译回归通过 |
| PS4（2.0 后新增） | 上游 Console ABI、JIT arena 和手柄快照已编入独立 ConsoleHostRuntime / MacConsoleProbe；沿用 Hardened Runtime 与现有 JIT 权限，增加停止和宿主线程回收检查 | 5 组后台测试通过，含真实 arm64 JIT 代码、ABI 拒绝、合并手柄、暂停释放、继续重发、断连及停止未确认；合成模块帧数恒为 0，不证明游戏渲染。真实核心及 probe 均未打包进 Product；资料库/独立 Runner、窗口和存档完成协议仍开放 |

## Web 存档协议

每个 `Saves/<id>/web-store.json` 保存独立 UUID，WebRunner 使用 macOS 14 的 `WKWebsiteDataStore(forIdentifier:)`。数据库由系统 WebKit 保管，不把其数据库文件复制为另一份游戏存档。关闭先发页面生命周期事件，完成脚本顺序屏障，停媒体、卸载文档，等待 cookie/data-record API 回调，再发 `web-storage-detached`。该回执明确为 `webkit-managed`，不是 native 的 `storage-closed/destroyed`，也不声称系统断电时的全局 fsync 保证。监督器核对 session、runtime、UUID 和进程回收。

用户清除存档时，先在同一个 WebRunner bundle 中删除该 UUID 的数据存储，成功才删除标识与资源缓存。失败保留标识；删除过程中禁止同应用重新 prepare。单独移除应用继续保留存档。测试验证进程重开和实际删除，而不只校验 JSON 回执。曾发现静态删除 API 在未初始化 WebKit 的辅助进程中崩溃，已增加独立非持久化 WebView 初始化，并通过删除/重建回归；未反复运行未修复版本。

Java 内嵌 WebView 使用 `Saves/<id>/java-web-store.json`，数据归 NativeRunner 的 WebKit bundle 所有。新存档使用独立 UUID；升级前已有 Android `data` 的存档沿用原来的包名 UUID，并记录 `legacyPackage`，避免换标识后失去旧数据。旧包级存储可能被其他资料库共用，因此清除这类存档只解除当前关联并删除 Android 数据，保留旧 WebKit 共享字节；下一次启动分配独立新 UUID。普通独立存档通过 NativeRunner 删除该 UUID，成功才移除存档目录，失败保留目录与标识。测试核对旧哈希的固定 UUID、进程重开与真正删除后的 store 枚举结果。

Java 关闭先等待 Activity/框架 worker/preferences/SQLite，WebView 自身销毁同时开始异步文档卸载：结清待回复对话框/导航/资源请求，停止媒体，通过真实空白导航触发一次 pagehide，释放 WKWebView 的 scheme-handler 引用环，等待网络取消完成及 cookie 写入，再读取 cookie/data records。只有 Android 销毁与 WebKit 两部分都完成，才写带 `web` 子回执的 `storage-closed`；未使用 WebKit 的会话显式写 `unused`。监督器核对启动时、磁盘上及事件中的 UUID。WebKit 部分仍是 `webkit-managed`，不是数据库 fsync 或断电持久性承诺。

真实 JavaScript 插件在运行时可写入 preferences，但销毁后 pagehide 再调用插件仍不支持：WebKit 会压掉卸载期间的 prompt，因此共享 JS 桥在调用前明确报告拒绝，避免丢失保存调用却返回成功。`macos-java-web-late-bridge` 单独确认 Android 已成功销毁，再拒绝组合回执。上游通用 `Thread.interrupt0` 仍为空；本轮只让框架自己的 WebView 线程池采用有界空闲等待，并从 SharedPreferences 串行 writer 内发起 shutdown，等待真实退出，没有宣称任意 guest worker 的中断已实现。

## 后续开放项

1. Java 内嵌 WebView：基础存储/关闭/删除已完成上述 build 8 接入与 fixture 验证。下一步以真实应用验证插件、HTTP 页面和完整保存重开。2026-10-17 复核确认：WebKit 会在真实卸载时压掉 prompt，因此仅将现有 tl_web_close_for_host 提前到 tl_javaapp_stop 之前仍不能支持 pagehide 的同步 Java 桥。需要先设计受控的卸载前保存阶段，保持 AppMain/bridge 消息循环可用，保证页面生命周期只交付一次、停止新导航/普通任务、排空已接收的插件任务，然后销毁 Android、回收 WebKit 并组合回执。现有失败检查不能删除；该实现继续开放。通用 Java Thread.interrupt/等待唤醒语义仍开放，不能取消 guest worker 检查或仅延长超时。macOS 14 实机、网络取消超时和系统 WebKit 异常恢复也尚未实测。
2. Geode：下载、配置、启动注入和存储关闭回归已进入 build 6。下一步使用独立存档验证真实 Geometry Dash、官方 Geode 发布包和模组，从设置开关、版本匹配下载到交互、保存重开；不要把自建 ELF 的通过当作这些外部程序已兼容。共享 GeodeUtils 的剪贴板、选文件/文件夹、openWebview、restartGame 仍继承上游的空实现/拒绝行为，需要实际使用证据后逐项适配。
3. 真实应用：按独立数据逐个验首帧、交互、保存重开和所需插件；实体手柄、前台 IME、全屏多显示器也需实际设备/窗口证据。禁止在没有相关修复时重复启动已知崩溃样本。
4. Egg：2026-10-18 已有真实会话仍在约 0.625 秒后退出 139；第一个构造函数 RVA 0x1621794 调用 PLT 0x16413c0，槽 0x17636b8 仍为原始 0x1625d90。重新核对 136,362 条 RELA/JMPREL，无该槽及后续两个槽的重定位，未声明 APS2/RELR。DT_INIT 经正常重定位的 ExecuteProgram 导入初始化；进一步静态核对确认 ExecuteProgram 需要 JNI 环境和就绪状态，而 JavaVM 及就绪字节在 PairIP JNI_OnLoad 中建立。NativeActivity 目前只建 DEX 索引和合成 Activity，未运行自定义 Application/类加载器，失败日志无 JNI_OnLoad 完成。下一步先补有明确初始化顺序的 Java Application/NativeActivity bridge 与 fixture，再受控验证 ExecuteProgram 前后和首帧；直接切 Java profile 仍不成立，因为 framework NativeActivity 是签名 stub。此次未重跑游戏、未改 APK/存档，修复仍开放。详见 [Egg 启动调查](2026-10-18_reverse-egg-startup-report.md)。
5. 三款游戏修复（2026-10-13）：跨 split/adaptive 图标解析、旧缓存升级、全 NativeRunner profile 的 Android 字体/CA 映射、有界 stderr 首尾保留和独立 supervisor.json 已实现。字体来自同一固定镜像，保留 CJK 和系统别名，旧配置的两个缺失名称在 lock 中记录兼容别名。实际资料库十款图标均已刷新，与隔离解码 PNG 一致，包含 Egg、War、Clash。
   - War Thunder：字体修复后成功生成三种 CJK 字体子集；随后补 `libvulkan.so.1` 映射和通用 NativeActivity 的 MoltenVK 配置。第二次探测的 RVA 0x5875dc4 空缓冲区崩溃进一步定位到 OpenSL 回调：宿主停止/清空操作没有等待正在读取的缓冲区和回调，游戏随后清空缓冲区。已修复排空/队列代际，补通用 NativeActivity 的 FMOD Java HLE。受控生命周期测试通过，第三次探测实际创建 Vulkan 设备/swapchain 并渲染 1280×720 的 Checking the data 加载页，5 项首帧/截图/失焦/暂停/恢复检查通过。
   - War 仍开放：20 秒观察没有进入主菜单，自定义 DagorUpdater 的 getFreeDiskSpace/isInstanceCreated 等方法仍返回未实现结果，需要接真实 Java 启动/更新器路径。停止后进程 exit 0，但没有 storage-closed，仍按失败处理；须追踪原生销毁末尾的进程退出与生命周期确认，不能把 exit 0 或 application destroyed 文本当成存档成功。最新会话 F55D0587，实测截图 `current-war-thunder-repair/frame.png`，解码引擎日志 `current-war-thunder-repair-engine-latest.log`。此次没有证明完整玩法或保存重开。
   - Clash：日志修复后的单次探测输出 5,913,771 bytes，末尾仍保留 `exit(101)` 和 NativeRunner 实际退出 70。退出发生在原生库初始化期间；`JNI_OnLoad+0x12c4c` 是最近导出符号标注，不能当成已执行 JNI_OnLoad 的证据。静态原始 RVA 0x6207bc 为 exit(101) 调用，前置控制流经过 0x61a668；需要继续检查混淆初始化分支及其真实 OS/JNI 前置条件，禁止简单跳过 exit。
   - 日志/静态证据在 `build/logs/current-three-games-audit.json`、`current-icon-repair.log`、`current-war-thunder-repair/`、`current-war-thunder-audio-static.log`、`current-clash-repair/`、`current-egg-init-static.log`、`current-egg-init-relocations.log`、`current-clash-exit-static.log`。自动真实探测静音/不可见，存档位于独立输出目录；三款仍未通过完整运行验收。
6. Play：个人账号/passkey 仍被 Google 拒绝；只有本人真实登录成功且 Play 会话可用才通过。OBB/PAD、设备配置和已购交付验收仍开放。
7. VM/P6：VM Minecraft 黑屏与持续 PCM 未通过；QEMU/libssh/OpenSSL 许可、Android 对应源码和发行签名仍按发行门槛处理。
8. Hole.io（2026-10-13）：InputEvent.getDevice 的父类 JNI 查找与 Java Vulkan 合成已修复，最终 build 5 的后台真实游戏确认拖动、计分、正常黑色洞口以及暂停/恢复。证据在 `build/macos/TestResults/HoleCandidate/`，会话 E86FC7A5。仍需完成可见 AppKit 窗口鼠标拖动验收（CUA 详情导航 native pipe closed）、Unity 进程退出与 SharedPreferences/worker 关闭、保存重开和长期性能。UnityPlayerForActivityOrService 的销毁路径在 mProcessKillRequested 时调用 onUnityPlayerQuitted 后进入 UnityPlayer.kill → Process.killProcess；当前 host 如实保持失败状态。下一步核对该退出请求的真实时序与写入/worker 所有权，补覆盖该行为的 DEX fixture，再运行真实保存重开；不能忽略 killProcess 或直接发 storage-closed。Vulkan 目前同步读回到 Java 合成器，可进一步评估 GPU 共享纹理，但要保留 present 等待和独立 layer 所有权。
9. PS4：核心源码公开位于 [Leviidev/AetherPS4 的 husk 分支](https://github.com/Leviidev/AetherPS4/tree/d953592114581cf3e5bdb20229769ec2f69b2359)，已核对 macOS 模块入口。公开 [fex-snapshot](https://github.com/Leviidev/AetherPS4/tree/220ab1e6d5aec14e43428f97c75530fc0113ce08) 的 `FEXCore/include/FEXCore/Utils/AllocatorHooks.h` 没有核心 CMake 检测的 `SetJITHostHooks`，会关闭 `AETHER_FEX_HAS_JIT_HOST`；不能把退回自行分配 JIT 当作 Husk 宿主区域/上限已生效。上游脚本要求作者本地 `husk-fex` 分支，本次公开同名仓库接口返回 404，并非核心源码整体不可获取。
   - 下一步先固定公开核心、FEX 和子模块版本，取得或实现匹配的 host JIT hooks；FEX 与核心同时使用 `FEX_MAC_PHONE_PATH=1`，核心开启 `ENABLE_FEX_GUEST_CPU`、`ENABLE_SHADPS4_IOS_LIB`、`ENABLE_HUSK_MODULE`、`AETHER_MAC_PHONE_PATH`。在现有依赖缓存内验证 arm64 模块、单导出符号、依赖闭包和许可，不另建候选或降低权限约束。
   - 模块启动线程目前 detach，`shadps4_run_loop()` 返回后即报告 STOPPED，ABI v1 没有 worker join / 存档刷写回执。继续追到核心 `src/emulator.cpp:665–698`：RunLoop 创建周期写入游玩时长的 jthread，事件循环结束只更新游玩时长并关闭 Storage::DataBase，再调用 onRuntimeStopped；这段返回路径没有停止/join 该 jthread 或 guest workers。停止入口仅推送 SDL_EVENT_QUIT。需要补清楚各 worker 与游戏存档的所有权和完成信号，本轮 `husk_console_join()` 只回收宿主输入线程，不能据此发 native storage-closed。之后再接独立 ConsoleRunner、资料库导入/分发、固定画布与键鼠/手柄/暂停/退出，并验真实游戏保存重开。源码证据在 `build/logs/current-ps4-core-contract.log`、`current-ps4-fex-contract.log`，未运行真实 PS4 游戏。

检查入口：CMakeLists.txt、Models/NativeLaunch/SessionController、MacNativeDrivers、NativeRunner、WebRunner、WebApp.swift、build_macos_graphics.py；对照上游 TLReport.nativeEngine、TLUnityView.swift、AppWindows.swift、src/app/project.yml 和 Play。后续每日同步须同时交付平台适配、当前候选与相应验证，不能以 Git 祖先或旧测试替代。
