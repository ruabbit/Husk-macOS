# 审计发现

## 2026-10-23 上游 bundle 与宿主环境

- 最终代码默认 CTest 141/141（201.91 秒）、18 Mach-O/406 Java 资源包检查通过，CUA 单次启动唯一 build 17/PID 25881，AX/截图确认原有 11 个应用。新增功能与运行链路已验证；源码 aa2cdbf 与 main 2c3af7a 已推送并读回；CI 39884106041 completed/success，36 项 hosted 核心回归（42.59 秒）、构建/包检查和 P0 memory/core 通过。
- NativeRunner.event 和 guest Java/native 输出原先共用 fd 1。新增真 DEX 的 println 导致监督器拒绝协议；临时改 Android Log 仅用于定位，最终恢复原始输出并修复实际通道：控制事件使用 CLOEXEC 独立 writer，guest stdout 转入既有有界诊断。最终复验包含 JSON 形状日志、onDestroy 最后输出与单次 storage-closed；协议校验未放宽。
- Java 默认时区首轮得到 GMT/native Asia/Shanghai；补 user.timezone 无效。官方 Android libcore TimeZone.getDefaultRef 使用 RuntimeHooks supplier，再回退 /etc/timezone。现由 AppRunner 在 Application/provider 之前安装真实 supplier 并清缓存，保留 guest setDefault/清除覆盖。Java 默认 locale 由共享宿主属性初始化；中文 zh-Hans-CN/法文 fr-FR 仅用进程参数，不改系统偏好。
- 本机 IOKit 快照是无内部电池桌面（packed=16844132，present=false），Asia/Shanghai / en-US。充电/放电/暂停充电/满电/0%/坏容量/UPS 排除有字典 fixture；MacBook 物理插拔尚未验收。Context7 IOKit 索引不足，补查本机 SDK 的 IOPowerSources.h/IOPSKeys.h 所有权和容量定义。
- macOS 导入实际调用 SharedCore/Archive.c 与共享 tl_zip，原已支持 Zip64/deflate/OBB，但 deflate 分配整个输出。本轮改 64 KiB 流式写入和 CRC/完整长度/流结尾验证，保留单条 512 MiB/总量 4 GiB/50,000 条限制；失败只清理自己创建的文件。真实共享导入器验强制 Zip64 APK/OBB、库重开、多块不可压缩输入和 local data descriptor；没有真实大包/认证网络交付结论。
- 首轮新增目标漏链接 MacDiagnostics 已补。失败日志保留：build-first、targeted-first、env-recheck、env-fixed；中途 17/17（15.84 秒）及输出隔离前默认 141/141（212.82 秒）不代替最终代码验证。最终 stdio/streaming 2/2（3.22 秒）后完整默认通过。5 个共享 C/Objective-C 文件 iOS 27 SDK/deployment 15 语法通过，只有命令行重复宏警告，不是完整 iOS 构建或真机证据。
- upstream 5158e09、3b87cbc 共 2 提交/10 路径，origin 无外来提交；普通合并无冲突。引擎分类/TLUnityView/project.yml、CMake、资料库/Runner 输入暂停关闭、Store/登录、图形固定依赖核对没有其他增量。GitHub 当前无法解析 PR #82，不推断合并状态；前轮 CI 39705343544 仍 completed/success。

## 2026-10-22 单个 WebView 销毁

- 最终默认 137/137（190.34 秒），其中 34 项 WebView（97.65 秒）；CUA 单次启动 build 16/PID 52520，AX/截图确认 11 个应用。54910cc 已推送并读回远端，CI 39705343544 completed/success，构建/包检查、34 项 hosted 核心回归（43.44 秒）和 P0 memory/core 通过。每日任务已更新，精确 prompt/时间/线程读回一致；最初断言误用了旧句式“禁止在没有相关修复时重复启动”，实际原文“没有相关修复时不重复启动这些失败样本”完整保留，未改变规则。

- 修正空白页插件重启后，listener 成功/失败、无替代视图和既有 late-bridge 4/4（12.25 秒）。build 16 的包检查为 18 arm64 Mach-O、406 Java 资源。共享 Web host 在 iOS 27 SDK / iOS 15 deployment target 语法检查通过，仅有既有 javaScriptEnabled 弃用警告；不代表 iOS 完整构建或真机验收。

- AndroidX 回归首轮 8/9，实际 listener 与 ReplyProxy/存储已执行，但关闭空白文档再次注入插件启动脚本，触发迟到 bridge 检查。现仅在保存完成、即将加载 teardown 空白页时移除未来 userScripts；原文档已有的生命周期 gate 保留，未关闭迟到调用检查。首次日志保留为 current-upstream-view-final.log。

- 复查 AndroidX WebMessageListener 原先在 mDestroyed 后跳过已接受回调并吞异常。现在等待 AppMain 真实投递、保持保存期间 ReplyProxy 可回页；异常明确回 JavaScript/native 错误，不再静默成功。Context7 AndroidX 文档确认该回调必须在 UI 线程、replyProxy 用于回页；测试携带边界接口形状并运行实际 DEX/反射分发，不等于真实第三方插件验收。

- 首轮针对性 6/7，通过 direct/重复销毁、暂停、Promise/插件拒绝及超时；stop-race 在新视图尚未注入文档时立即关闭，按现有策略返回 JS 保存异常，没有虚报成功。保存首次日志。调整该用例先确认新页面 ready，同时明确断言旧页面异步保存仍进行中，再验证 host-stop 汇合；未注入/加载中的文档可靠保存仍不在通过范围。

- 两远端无新增；macOS=15c8f1b、main=cc99757、upstream=2df074b。旧候选 build 15，空闲 PID 18451；CUA 看到首页 11 个应用，其他项目 UTM 不属于 Husk 会话。
- 当前 WebView.destroy 立即移除 Java sViews，native W_destroy 直接 retire_view/closeForHost；页面保存插件此时成为 orphan，未走逐视图准备。
- 拟保留销毁中 Java 对象的桥接能力，异步保存后通过 AppMain 回执排空已接受的 bridge/UI 工作，再脱离 WebKit。全局 stop 必须等待这些视图且保存失败保持 sticky；不能仅延迟 WKWebView 释放。
- Context7 官方 WebKit 文档确认 callAsyncJavaScript 等待 thenable 成功/拒绝，nil frame 是 main frame；本轮继续用既有有期限保存阶段，不宣称普通 unload 自动等待异步工作。

## 2026-10-21 主动 finish 与宿主关闭顺序

- 两远端没有新增，工作区干净，前轮 build 14 与 CI 已交付。存在其他项目 UTM/QEMU 进程，未触碰；本项目只有空闲 Husk。
- AppRunner.finish 当前先 finishNow（会销毁 Activity/WebView），空栈后才 finishHost；NativeRunner 到 TL_JAVA_STOPPING 才获知 guest 退出，已经错过 WebView 保存阶段。需要在最后 Activity 销毁前交给宿主，保持 AppMain/桥接可用，宿主保存完成后仍通过原 phase 10 完成销毁。
- 保留 finish(); startActivity(...) 的既有行为：最后 Activity 的判断必须在已排队启动完成后复查；非最后 Activity 关闭不应结束整个 Runner。iOS/无宿主配置继续走原本生命周期；Process.killProcess 不属于正常 finish，仍失败。
- 新增 opt-in request_finish 回调，由 AppMain 在最后 Activity 销毁前交给 Mac 主线程；旧配置 NULL 仍走 guest 销毁。交接后不再接受新的 Activity 启动/重建，Web 保存插件与已接受 UI 写入仍能排空，后续沿用 phase 10 和原有双侧销毁确认。
- SessionController 过去只在主程序 stop() 时启动 30 秒退出期限，guest/window 自行停止即使持续 heartbeat 也可能永久等待。现改为收到首个合法 stopping 事件即启动同一期限，后续事件不延期；真实子进程测试 30.36 秒被正常 SIGTERM 回收，无存储成功回执。
- 首轮针对性 12/13 通过。暂停用例在 paused 状态发送 evaluate，而正式诊断协议只接受 running，故测试超时；不是保存阶段失败。已改为真实 Activity.onPause 发起 finish，保持协议约束。首次编译的测试 Task.sleep 未处理 throws 已修正，未改变产品 API。
- 暂停、双 Activity finishAffinity 与关闭阶段再次启动的 3 项复核全过。首轮默认 125/127，唯一失败是两个既有 Vulkan compositor；该测试二进制仍为 10-19、共享 Vulkan 源码和依赖 pin 未变。系统日志记录 Metal Internal Error (00000206) 与 5 秒 GPU timeout。隔离使用 CPU semaphore style=3 和默认 style=1（关闭错误隐藏）的诊断均通过，随后不带覆盖环境的原始四项 Vulkan 顺序回归 4/4 通过。未改变图形代码/配置/断言，未终止其他项目进程；只能记录本轮瞬时 GPU 执行失败，不能宣称底层根因已修复。保留首次完整日志与系统日志后重跑默认套件。
- 只读查询一度假定头文件 husk-tl-javaapp.h，实际为 husk-tl-dvm-javaapp.h，已按 rg 结果修正，没有修改不存在文件。

- 最终原配置默认 127/127（143.77 秒），24 项 WebView（63.07 秒）与包检查通过；CUA 单次启动 build 15/PID 18451，AX/截图确认原有 11 个应用。c549924 已推送并核对远端，CI 39541085280 completed/success，34 项 hosted 核心回归（42.14 秒）、构建/包检查与 P0 memory/core 通过。

## 2026-10-20 WebView 卸载前保存

- 两远端 fetch 无变化，upstream/main=2df074b，main=cc99757，macOS=4b1d5b5；工作区初始干净，无进行中的 Git 操作或构建，仅空闲 Husk PID 39849。
- 当前 NativeRunner 先 tl_javaapp_stop，再 tl_web_close_for_host；WebKit 真实 unload 压掉 prompt，已记录的 late-bridge 回归如实拒绝组合存储回执。新阶段必须先保留 AppMain/JavaBridge，再销毁，不能以 WebKit 独立 detach 代替 Android 完成。
- Context7 WebKit 官方文档确认 callAsyncJavaScript 会等待返回 Promise 的解析/拒绝，nil frame 指向主 frame。应用的普通异步页面任务没有自动完成保证；生命周期阶段需要明确边界、超时与拒绝路径。
- 初次查找假定 javaapp 为 .c、fixture 为 WebActivity.java，实际文件名需以 rg --files 为准；该只读查询没有修改源码。

- 首轮 11 项 WebView 回归全部通过；复核后把媒体停止提前、按顶层 JSON 错误字段判定插件失败，并补暂停关闭/Promise 拒绝；最终默认 115/115，其中 WebView 13/13。真实 Java UI 消息在输入轮询前排队，phase 10 改为向同一 Handler 投递销毁，避免越过已经接受的插件 UI 写入。
- Context7 同时确认 setAllMediaPlaybackSuspended 的 completion 在媒体暂停状态完成后执行，页面不能自行恢复。该步骤与保存脚本共用 6 秒期限；超时仍销毁资源但拒绝成功存储回执。事件是合成的、waitUntil 为 Husk 扩展；跨来源 frame、未登记异步任务、guest 主动销毁与实际 HTTP 应用仍有验收缺口。
- CUA 退出后再次观察得到新空闲 PID 55410，精确路径和无 Runner/VM 复核后已自动 SIGTERM。最终单次 getApp 超时但启动了 PID 67505，复查该进程后通过旧绑定只读 AX/截图成功；不能把超时当成“未启动”而重复启动。

## 2026-10-19 上游运行时与文件选择器

- 上游 4 提交 / 29 路径，main 本地普通 merge=cc99757；macOS 三处 Java 冲突与此前 Egg 启动桥重叠。自动合并还留下重复 mPackageInfo/mClassLoader，现统一到 LoadedApk.self() 并保留 attachBaseContext 后采用加载器。
- 文件选择器回调原来没有 macOS 接线；已补 NSOpenPanel、所选文件隔离复制、只读 grants、并发请求拒绝和销毁前取消/排空。Context7 AppKit 文档确认 sheet completion 与多选 URLs；未知 MIME 在系统中生成动态 UTType，需要显式回退 item。
- 新 .NET 映射代码的固定表满后失去记录，且部分 unmap 会释放整个 host span；动态记录与拒绝不支持的部分释放已通过 96 映射回归。Mono 的 .text 数据必须排除 syscall/ADRP 改写，真实 ELF fixture 已验证。
- 首轮测试错误：Objective-C 宏未包住带逗号表达式，改可变参数宏；同步 fixture 过早返回首个选择结果，使“重叠请求”实际变成先后请求，现等待第二请求取消后再送首个结果。修复后的 5 项回归及追加 4 项复验通过。早期正则误包含 build 12 的 macos-java-nativeactivity-session，其通过不计为新候选证据。
- CUA 首次 getApp 超时重置，重连 native pipe closed，没有取得绑定；后续按键尝试返回变量未定义，未向应用发送退出。用户纠正退出流程并明确授权：无游戏/VM时自行正常退出或强制退出空闲 Husk，不再要求用户操作。继续时旧 PID 13331 已消失；原位打包 build 13 后 CUA 单次启动 PID 39849，主窗口 AX/截图成功，107/107 默认测试和包检查通过。每日任务已更新并读回新规则；没有对不存在的进程发送信号，也没有触碰其他项目 UTM。

## 2026-10-13 三款游戏修复与剩余阻塞

- 图标根因在 macOS 导入器：只从 base 读取资源，且把 binary adaptive XML 当图像存储。新实现跨 split 解析、合成 PNG 并按版本刷新旧缓存；真实 Egg、War、Clash 图标已解码并目视检查。刷新不重写资料库索引、名称、偏好或存档。
- War 的字体错误不是存档损坏。固定 Android 系统资源此前未随 macOS 打包；补齐后，真实游戏已从 NotoSansCJK-Regular.ttc 成功生成三份字体子集。继续发现 `.so.1` Vulkan 库名和通用 NativeActivity 的 MoltenVK 配置缺口，修复后实际 VkInstance、Android surface、M1 Ultra 设备初始化通过。
- War 第二次探测的崩溃位于 OpenSL 回调 RVA 0x5875ca0，RVA 0x5875dc4 用已清空的缓冲区调用 memcpy。静态清理路径先 SetPlayState(STOPPED)/Clear，再释放并清空两份缓冲区；宿主旧实现直接返回，后台仍可回调。修复停止/清空的排空与队列代际，同时补 NativeActivity 的 FMOD Java 接口注册。受控回归覆盖阻塞中的宿主读取、正在执行的回调、Clear 后重新入队、恢复及回调自身停止。第三次针对性探测不再发生该崩溃，实际渲染 1280×720 加载画面，失焦继续、暂停/恢复通过。
- War 尚未完成运行验收：20 秒内仍显示 Checking the data，日志中的自定义 DagorUpdater Java 方法未实现；停止后进程以 0 退出，但没有 storage-closed/终态回执，监督器如实判失败。后续须接真实 updater Java 路径和可确认的正常关闭，不能伪造方法返回值或存储确认。`current-war-thunder-repair/frame.png` 为实测画面。
- Clash 原本只保存前 4 MiB 日志，实际这次输出 5,913,771 bytes。新的轮转机制留下初始化尾部的 `exit(101)`、实际监督器退出 70、storageClosed=false。静态调用 RVA 0x6207bc，前置分支经过 0x61a668。`JNI_OnLoad+0x12c4c` 仅是最近导出符号，库还没打印 initialized；不要误称已通过 JNI 初始化。
- Egg 的 DT_INIT 通过 0x1798000 的 JUMP_SLOT 调用 ExecuteProgram，再进入仍未重定位的 PLT；当前 NativeActivity 合成对象没有跑自定义 Application 的 Java 初始化。两条证据尚未建立完整因果；未改地址、未跳过初始化、未再次启动 Egg。Java framework 的 NativeActivity 仍是空壳，直接改 runtime 标签不能修复。
- 自动真实探测均静音、无可见窗口，写入独立数据目录。对应字体、Vulkan、音频修复后各探测 War 一次，日志修复后探测 Clash 一次；没有无变更重复启动。资料库原 437 文件基线中 435 个一致（含 APK、索引及其余保存内容）；War 的错误时间标记消失、last_debug 更新，时间对应 18:23 主界面会话 7F02AF51，区别于 18:14 已结束的后台探测。该会话 headless=false，有独立监督器记录；没有擅自还原这两份日志文件。实际十款图标缓存均与隔离解析 PNG 一致。

## 2026-10-13 Husk 2.0、运行链路与交付

- 本轮 Git 增量 f0bd526..8e79a47 只有社区相关 3 提交，但上游 2.0 和多个引擎此前已进入 Git 祖先，macOS 未完整编入/分发。此次按真实功能对齐补齐；祖先完整不能证明平台功能完整。
- 上游 AppWindows.swift 自身同时只有一个引擎窗口；macOS 保留真实独立 AppKit 窗口及单会话，不套用 iOS 模拟窗口。圣诞装饰复用共享 Holiday，减少动态效果时关闭飘雪，图层不拦截点击。
- Java 手柄此前缺少 InputDevice 枚举、MotionEvent 轴/设备复制和 ViewGroup 通用移动事件焦点分发。现在通过同一 AppRunner 队列、真实 DEX 和打包会话验证，不只接一个 host sink。
- 原生共享引擎的暂停/停止需平台适配：GL 回调同线程、worker join、真实销毁函数以及 sticky 失败。Godot/GM/SDL/GTA 缺销毁入口时必须失败；Cocos 没有 renderer destroy，采用 Android nativeOnPause 保存后 join/检查 worker。六个打包 profile 的 fixture 通过不代表真实商业游戏兼容。
- WebKit 在没有初始化主 RunLoop 的新 helper 中调用静态 store 删除 API 曾崩溃；先建立临时非持久化 WebView 后删除成功。每个 save 持有稳定 UUID，数据由 WebKit 保管；document detach/API callback 不能等同全局磁盘 fsync，因此新回执明确为 webkit-managed。localStorage/IndexedDB 重开/删除验证通过，自定义 scheme 的 document.cookie 为空。
- 隐藏 WebKit 页定时器被节流；测试先看到实际 tick，再检查暂停和恢复，不能用固定 10 ms 前台假设导致误报。旧失败测试 4 个 fixture store 已清理。
- 上游 SPIRV-Cross 补丁此前未进入 macOS 图形构建。现固定 checkout、实际打补丁、哈希验证缓存并随包附源码修改；实际包内 MoltenVK 的初始化 workgroup compute shader 编译通过。
- Context7 本轮后续查询达到月度配额，Apple/WebKit API 以官方资料和本机 SDK 头文件核对；没有把失败的文档查询写成成功。
- 用户正常退出后完整构建/打包成功，61/61 默认回归、18 个 Mach-O 和 194 个 Java 资源通过。CUA 单次启动读到新首页和商店截图，后续恢复 native pipe closed，资料库详情等可见验收未完成。当前候选与历史 PID 98251 已不是同一实例。
- Geode 下载/配置 UI 和 Java 内嵌 WebView 的混合存储关闭仍未完成；真实手柄/引擎、Egg、Play、VM/P6 按证据继续开放。详见 upstream-parity.md，不将“2.0 源码合并”写成“全部游戏兼容”。

## 2026-10-12 Java / Unity 6

- 上游将 Unity 6、SDL（DXVK 除外）、Python、Flutter 等交给 Java，缺口在 macOS 的受控 boot 资源、框架编译和 Runner 接线。当前已复用上游真实实现接入；未重写引擎或只加白名单。
- `tl_manifest_gles` 原定义在 SDL driver 导致 Java host 链接失败。共享模块拆分后，GLES manifest 编码/资源 ID/损坏边界回归通过。
- 原 `tl_javaapp_set_paused` 无回调完成确认；原 AppMain/GL 为 detached 常驻线程。已补状态回执、同线程销毁、显式 join，preferences 失败传递、SQLite 完整事务检查和真实 DEX/生产会话验证。
- 在线程入口函数返回前递减计数不能证明 TLS 析构结束。现在 Java 与 bionic worker 保留 Mach thread send right，等待 kernel thread 终止，并在关闭阶段禁止新建 worker；pthread_exit / TLS 延迟和残留 worker 测试均通过。
- 旧资料库 Hole.io 等记录仍写 Unity (IL2CPP)；仅用新规则判断旧 engine 字符串会再次漏接。旧 Unity 索引先只读复扫并按 digest 缓存，测试确认不写原索引。没有再次运行 Hole.io。
- WebView 的视图移除不能证明 WebKit 数据进程完成持久化。macOS host 使用过 website data store 时拒绝正常关闭回执；这保持为明确缺口，下一步不能仅删除此检查。
- 控制库共用的 Android 组件来自固定、未使用过的原始 qcow2；本轮只读提取后清理临时磁盘，原用户数据未参与依赖准备。资源哈希和原始 NOTICE 不替代发行对应源码审核。
- 最终 40/40 默认回归与包验证通过，当前 App 单次启动，但随后 CUA 通道又断开。真实引擎、前台 IME/画布和实体控制器仍不能用后台 fixture 结果代替。

## 2026-10-11 NativeActivity 与 Egg, Inc.

- 上游通用 NativeActivity 入口来自 `b7480b6c11a7bac9bb97cd93f277f3bebcbc21cc`，早已是当前分支祖先；此前缺口是 macOS 未编入和分发。共享驱动原有暂停从宿主直接发回调、没有 stop/join，不能直接套用 macOS 的正常关闭回执。现已让所有 NDK 回调在同一活动线程执行，并在销毁返回、线程回收后确认关闭。依据 [NDK 回调契约](https://developer.android.com/ndk/reference/struct/a-native-activity-callbacks)，窗口销毁回调必须等 guest 不再访问窗口后返回。
- [PR #82](https://github.com/Leviidev/Husk/pull/82) 在核对时仍开放，head 为 `e304785404971b088eb0703b3aca3916aba44bcd`。采用其中的 ActivityThread 类和 currentApplication 静态 HLE，返回与 Activity.getApplication 相同的对象；该 PR 的 iPadOS 报告不是 Egg 或 macOS 的验证结果。
- Egg 的 manifest launcher 是 `com.auxbrain.egginc.EggIncActivity`，`android.app.lib_name=egginc`，应用类为 `com.pairip.vmencryption.KeyImportApplication`，竖屏。base 加三个分包已交给真实加载器；主库在 arm64 split。启动元数据解析增加 XML 层级，避免选中其他组件或 application 的同名 metadata。
- 单次隔离探测的 PC/fault 为 `0x1625d90`，LR 为 `0x70416257a8`。libegginc.so 的首个 init-array 构造函数 RVA `0x1621794` 在 `0x16217a4` 调用 PLT `0x16413c0`；该 PLT 从槽 `0x17636b8` 读出的仍是原始解析器地址 `0x1625d90`。静态核对 DT_RELA、DT_JMPREL 没有该槽的重定位；此 ELF 未声明 Android APS2 或 RELR。DT_INIT 为 `0x17a0000`，PairIP 依赖在崩溃前已完成构造函数。当前仅能证明未重定位跳转发生于原生初始化，不能将保护组件的存在当作因果证明。
- Egg 尚未进入 ANativeActivity_onCreate、没有首帧。下一步应核对 DT_INIT 与动态符号/PLT 初始化契约以及上游 loader 的相关修复；保留原 APK，不跳过初始化或猜测地址补丁。没有相关修复时不重复运行这一失败样本。实现回归通过和 GUI 入口开放均不能代替游戏运行验证。
- 当前 Product 已原地更新，默认 29 项回归及 17 个 Mach-O 包校验通过。用户确认退出后仍残留旧 PID，核对空闲线程、无 Runner/VM/网络句柄后发送 SIGTERM 回收，再通过真实打包保护。新候选仅启动一次，PID/路径已核对；CUA 的 AX 连接仍失败，前台可见检查未完成，见 [progress.md](progress.md)。

## 2026-10-08 审查修复

审查核对：哈希白名单与 Orbit 文案已在上一轮修复，本轮去掉样本哈希对 runtime 判断的最后一个兼容分支。xcode-27 是 GitHub 官方 arm64 预览标签，本轮 CI 改为稳定 macos-26，远程仍未验证。VM 依赖实际要求27.0.0，已用打包元数据贯通 UI/启动/校验。实际闭包发现 QEMU → libssh → OpenSSL 3；macOS 许可文档明确该组合和缺失 notices/对应源码阻塞发行。

## 当前实施（2026-10-08）

- P4 最新状态：指定 Minecraft 的正式 NativeRunner/SessionController 后台闭环已完成。最终 Runner 通过 20 次 Activity 恢复及 600.17 秒世界运行（59.85 fps，RSS 1,784–1,823 MiB），正常保存重开和复制资料的受控退出后恢复均通过；隐藏原生 CAMetalLayer 已独立验证。FMOD 恢复失败（51/28）的根因是适配层拒绝无回调的 AAudio 配置探测流，现已修复。其他引擎和前台/设备功能仍按报告保留未验证状态。本文下方更早 P4 记录为当时状态。
- 宿主恢复与游戏内 Resume Game 是两层状态。Activity 恢复可恢复图形及 PCM，但 Minecraft 保留自己的暂停菜单；必须点击 Resume Game 并确认实际世界画面后才统计世界持续运行。菜单闲置降帧不应冒充世界性能数据。
- 运行日志仍显示未实现的 Xbox ECDSA/PlayGames/TTS 方法、XAL 空引用、遥测 SQLite 错误及可选 Choreographer/媒体解码符号缺失。它们没有阻断本轮本地世界流程，但 Xbox/联机/媒体功能不能宣称通过；游戏自己的后台网络访问也不等于经过网络隔离。

- P4 已为指定 Minecraft 1.26.52.3 编译完整 GameActivity/bionic/JNI/音频运行库和独立离屏诊断程序；原生产 Runner 目前仍走 fixture ABI。共享 EGL 路径与 P3 MacGraphics 是两个实现，须单独修复离屏提交/节流，不能沿用 P3 测试结论。
- P1–P3 已进入可运行原型：CMake 原生工程、SwiftUI 资料库、独立 AppKit Runner，以及两个自建 Orbit arm64 ELF 样本。后文最初审计中的“当前”均指 2026-10-07 的基线，不代表实施后的状态。
- 资料库复用 ZIP/ELF scanner 和 Foundation 元数据模型；新版 loader 执行 guest 的玩法、GLES 绘制及 PCM 合成。fixture ABI 是显式限制的第一条路径，完整 bionic/JNI、DEX 和商业游戏引擎仍属 P4。
- ANGLE/WebKit 固定 f488eac0e00cee453b7ca9f24c42f585df236e97，MoltenVK v1.4.2 固定 db66022459ffb663aa2b50f6b018bc2e124f5edf。按源码提交及产物 SHA-256 校验缓存，运行依赖仅位于签名 bundle 或系统目录。
- 本地 ad-hoc Runner 加载 ad-hoc ANGLE 会遇到 Hardened Runtime Team ID 校验拒绝，因此开发模板额外需要 disable-library-validation。同 Team ID 候选模板仅 unsigned-executable-memory；主界面无任何 entitlement。实际 Developer ID 签名及公证未验证。
- 持续测试发现 ANGLE Metal pbuffer swap 不提交 GPU 命令，约两分钟内 RSS 达数百 MB。单加 autoreleasepool 无效；离屏 present 显式 glFinish 后内存恢复稳定。可见 CAMetalLayer 仍走正常 EGL swap。保留失败采样及修复后独立候选记录。
- 最终本地回归 5/5 组，包含 31 项端到端、静音真实 AudioQueue、MoltenVK 实际 Metal 设备枚举；20 次后台会话全部保存/回收；P0 默认 30/30。325 文件干净源码导出重建同样通过。持续运行最终结果另见交付报告。
- 30 分钟修复候选完成 107,860 帧，平均 59.92 fps，RSS 25.5–30.4 MiB；最终字节一致的冻结候选另有 5 分钟/59.90 fps/RSS 30.4–30.5 MiB 通过结果。两者均正常保存并回收；没有把旧候选时长移用到最终产物。
- 一次后台主窗口导入已产生两条真实资料记录；随后 CUA native pipe 断开，没有观察到 Husk 崩溃。未继续重开窗口；完整前台 UI、实体手柄、可听音质、多屏/休眠、最低系统、另一台 Mac 和远程 CI 尚待对应验收。

## 原始审计基线（2026-10-07）

- 仓库为 ruabbit/Husk-macOS，GitHub 确认为 Leviidev/Husk 的 fork。
- 初始工作区干净，当前 main = origin/main = 5a7d2df9a568ccb93e3395270e430da649a85874。
- 本地仅 main；git ls-remote --heads origin 也仅返回 main。
- src/translation-layer 与 src/translation-layer-next 是两个源码目录，不应未经核对称为两个 Git 分支。
- 项目包含 iOS SwiftUI 壳、QEMU 桥接、自研翻译层、macOS 命令行/窗口测试工具；已有 macOS 验证脚本不代表原生 App 已经完成。
- docs/00-architecture.md 与 docs/04-translation-layer.md 描述早期阶段；README 和近期提交记录已描述更多游戏执行能力，必须以当前源码为准。
- 上游实时分支：main=82f33e858952f9fda3cf224e839f4385894e2d5b；claude/epic-hypatia-2hsqfv=756c8d0c9d81ffcf7e282cac98a69af1ff299522；merge-base=e768fdba45d81d99ee247c83f49a0ec5faf3df9a。
- fork main 比 upstream/main 落后 2 个提交且无独有提交；上游两个分支各有 86/4 个独有提交。topic 分支并非 macOS 移植分支；独有提交涉及早期翻译层与 iOS CI、PyYAML、patch 路径修正。
- fork 到 upstream/main 的产品 src 无差异；变化为 README、截图命名及 ci_build.sh 加入 MoltenVK 构建。
- project.yml 仅有 iOS application 和 iOS app-extension target；build_macos_validation.sh 明确标记 fixture，且关闭 HVF、OpenGL、virglrenderer。
- 主机 arm64，Xcode 27.0 (27A266a)；当前未找到 build/、third_party/build/、guests/。
- Apple Context7 文档确认原生 macOS 可用 SwiftUI + NSViewRepresentable；Hardened Runtime 的 allow-jit 配合 MAP_JIT 有单区域限制。需审核现有 allocator，而不是仅删除 StikJIT UI。
- 原生运行时由全局状态持有，husk-tl-unity-app.h 明确引擎不可卸载；TLUnityView.swift 要求退出 Husk 后才能换游戏。macOS 应先验证独立 Runner 进程及退出/存档协议。
- husk-tl-xmem.c 的 macOS 分支使用 mach_vm_remap + mprotect RX，缺少发行签名/Hardened Runtime 的验证；classic loader 又可逐库 MAP_JIT。开发态 CLI 成功无法代替发行态可执行内存验收。
- tools/unity-window.m 已使用 NSView/CAMetalLayer 和鼠标输入，但 ANGLE 默认路径指向原开发者 Steam 目录；它是可用的原型参考，不是可分发产品。
- scripts/build_angle_ios.sh 克隆 WebKit 默认分支且无 commit pin；MoltenVK 固定 v1.4.2 但仅构建 iOS。
- QemuRunner.swift 仍显式使用 TCG；macOS validation script 禁用 HVF。HVF 需要独立验证 CPU/guest/snapshot 组合，不能直接继承 iOS 内存快照。
- 当前两套翻译层共有 51 个 C/Objective-C translation unit，均通过 macOS clang -fsyntax-only；这只证明语法/SDK 可见性，不证明链接或运行。
- 两分支的 page planner 均通过；main 原始 run.sh 在 macOS 链接 scanner 时缺 tl_find_stikdebug_prewarmed；topic 的 scanner 在首次 NDK clang fixture 下 TLS 断言失败，正在用上游 LLVM 区分工具链差异。
- prefs 和 blit 既有测试已通过；va-test.c 独立链接缺日志函数，需测试宿主适配。所有适配仅放在 ignored build/audit-2026-10-07。
- Xcode 读取项目成功，仅列出 Husk 和 HuskJITHelper；无 macOS application target。
- import UIKit 的 Swift 文件有 18/39；另有未直接 import UIKit 但使用 UI 类型的文件，因此该比率不是全部平台耦合覆盖率。
- JIT 隔离自测：原始 husk-tl-xmem.c 分配 64 MiB、写入两条 ARM64 指令，开发态返回 42；同一程序 ad-hoc 签名并启用 Hardened Runtime + allow-jit 后 SIGKILL。codesign --verify --strict 通过，系统 crash report 为 CODESIGNING / Invalid Page，故不是普通磁盘签名损坏。仅测试自建指令，未加载 APK。
- scanner 最终两分支均 41/41 通过（main 使用无 StikDebug 的宿主适配器）；前两次失败分别源于 NDK clang 的 TLS fixture 行为和 LLVM 23 readelf 的 RELR 输出变化。固定上游 clang 23 + lld/readelf/objdump 17 后通过，原始失败仍保留。
- va 6 项通过（只补宿主日志适配）；pacer 通过，1/5/12 ms 工作量为约 59.9 fps，25 ms 为 40 fps，停顿后无追帧冲刺。
- 未运行完整 iOS/原生 macOS App、真实 APK、QEMU guest、HVF 或 Developer ID notarization；没有现成依赖与 guest 产物。
- 固定版本官方 LICENSE 已核对：utmapp/qemu v10.0.12-utm 整体 GPLv2；MoltenVK v1.4.2 Apache-2.0。现有 licensing 文档未覆盖后续同进程 MoltenVK 组合，发行许可结论需重审，进程拆分本身不等于合规结论。

最终结论与分阶段计划分别在 docs/2026-10-07-audit-Husk-report.md 和 docs/2026-10-07-macos-migration-plan.md；复现条件与失败边界在 docs/2026-10-07-husk-audit-evidence.md。本轮仅交付审计/规划，尚无可发行的 macOS App。

## P0 实施发现

- 用户随后授权执行 P0；分支 `codex/macos-p0` 从 `82f33e8` 建立，原 `main` 保留。
- 相同合成指令程序改用 Hardened Runtime + 仅 `allow-unsigned-executable-memory` 后返回 42；同时添加 `allow-jit` 也通过。证据在 `build/macos-p0/initial-matrix.json`。这是 ad-hoc 签名的候选结论，仍需 ELF、线程及 Runner 验证，不代表 Developer ID/公证通过。
- 完整内存矩阵已验证：无 entitlement 和仅 allow-jit 的双映射执行均 SIGKILL；unsigned-memory 单项和双项通过。标准 MAP_JIT 代码返回 42，但执行态对其数据区的 guest store 触发 SIGBUS。这支持保留现有双映射并把权限限制在 Runner。
- 自建 ELF 暴露真实缺陷：4 KiB ELF 的代码/数据共用 16 KiB host page 时，RELATIVE 构造函数指针被错误放入 RW 地址；ADR/ADRP 改写也按 host page 误判代码地址。已按代码范围及 ARM64 4 KiB 指令页修复，RELA/RELR/APS2、构造函数、函数指针、TLS、x18、4 线程全部通过。
- classic 的 16 KiB fixture（含第二库）在本机 allow-jit 下通过；4 KiB 混合页原先在构造函数 SIGBUS，已改为分配前明确拒绝。TLS 原本就被拒绝。macOS 原生 ELF 默认采用新版 loader，classic 保留用于现有路径与后续 DEX 迁移，不宣称两者能力相同。
- P0 AppKit Runner 已运行真实合成 ELF；Python 监督器验证 session ID/事件序号、pause ack、checkpoint/退出先后、崩溃后重启、SIGTERM/SIGKILL 超时回收、父进程死亡独立 watchdog、20 次启停无残留。checkpoint 是合成计数器，不能当作真实游戏存档证明。
- 已通过原生 UI 自动化观察窗口，并实际按 Command-P 暂停/恢复、点击菜单退出。会话 c29310be-e00b-4f32-a5a4-0fa62da1f270 的日志确认 menu-quit、checkpoint、exit 0；退出后 AX 查询超时是窗口已关闭，已用进程和日志核对。
- 统一故障测试暴露 AppKit crash restoration prompt 阻塞 didFinishLaunching。对受控 PID 做 sample、并用原生 AX 观察确认原因；使用进程内 ApplePersistenceIgnoreState、非恢复窗口及禁用登录自动重启解决。首轮误用 NSApplePersistenceIgnoreState 无效，已改为正确键并重跑通过；没有删除恢复数据或写全局 defaults。
- 用户指出可见窗口循环与崩溃弹窗影响日常使用。已停止可见测试，检查无残留 Runner；四条最新 NativeRunner crash 均来自主动 abort。最新 PID 57384 与测试结果一致。系统通知程序被电脑控制工具禁止访问，无法替用户点 Ignore，不通过其他途径规避该限制。
- 将 Runner/监督器默认改为不创建 NSApplication/NSWindow 的后台模式；入口默认不运行故障注入，压力次数降至 2。可见窗口、故障注入、压力次数均显式选择。历史 39 组全部通过结果单独保留，当前默认验收不把未重跑 GUI 当成已覆盖。

## P5 当前调查

- QEMU 固定上游 UTM 10.0.12；GPU 参考 epoxy bf985874、virgl 482f9d8b，与现存 ANGLE 的接口需要重新实测。系统 Homebrew QEMU 11.1.2 有 HVF/TCG 但无 virgl GL 设备，不能替代匹配构建。
- guest release lineage-v2 / vda-v12.qcow2；冷启动还需 64 MiB raw firmware、64 MiB qcow2 EFI vars、16 GiB qcow2 blank userdata。桥接端口 guest 5599，为 shell 权限。新宿主应使用会话隔离的 loopback 端口。
- VM 快照不得自动复用 iOS 版本；音频迁移 blocker 不能为了快照删除。

## P5 最终本轮边界

- 实现具备独立 VMRunner / VMController、固定依赖与 guest、双端 APK hash、QMP 生命周期和冷启动数据闭环。主 App 无 entitlement，VM helper 当前依赖 floor 为 macOS 27。
- 修复的关机挂起是主线程 atexit 等待 QEMU BQL；正确 API 返回值、释放锁并在 QEMU 线程退出后，正式 Swift 控制器的 HVF 重开及 TCG 关闭均能回收 PID。原始两个 cleanup 后挂起的进程最终 -9，不能视为干净退出。
- 仍阻塞：Minecraft 在 VM 内黑屏，后续焦点/生命周期造成 guest ANR；持续 guest PCM 未流入宿主。权限选择、TCG/HVF、AAudio policy 试验未修复；根因未确定。原 APK 未改动。
- 样本在 P4 翻译层可玩并不证明 P5 VM 可玩。完整证据、候选和后续门槛见 docs/2026-10-08-macos-p5-report.md。

## GUI 与上游同步（2026-10-08）

- upstream main 从 82f33e8 到 75dc21f，共 27 个提交、117 个路径变化；topic 未更新。已做逐文件三方整合，保留 macOS 修改与 iOS 条件分支。新增 Godot/Geode/Store 源码并不等于 macOS 已接入。没有 VM/QEMU/guest 变更能够直接解释或修复 P5 黑屏。
- 实际用户导入为 minecraft-mod_menu_1.26.52.3-mcpelife.apk，digest bceb3203…，libminecraftpe.so 与 P4 APK 不同；FMOD/libc++/MediaDecoders 相同。两个原始 APK 没有修改。
- 新的 LibraryGame 能力为计算属性，旧 unavailableReason 不再决定执行；既支持老版本资料库又避免以后引擎更新仍被旧缓存禁止。实验 Minecraft 仍需完整 APK hash 与独立 Runner engine/ABI 验证。
- 当前最终候选 11/11 CTest、P0 30/30、4 个合并 C 文件 iOS 条件编译及嵌套签名/依赖闭包通过。用户 APK 已实际渲染菜单、列出隔离复制的 P4 世界，继续做世界和退出检查。

- 最终交付的实际日常记录已按当前组件可试运行，无需 index 数据迁移或重导；旧索引原字节保留。新候选只启动一次且保持运行。完整证据和边界见 docs/2026-10-08-upstream-sync-report.md 与 results.json。

## 原生窗口尺寸契约（2026-10-09）

- ANGLE `WindowSurfaceMtl::calcExpectedDrawableSize` 使用 `bounds.size × contentsScale`，`initialize` 会为传入的 CAMetalLayer 开启宽高 autoresizing，`checkIfLayerResized` 会在获取 drawable 时重设缓冲区。仅反复写 `drawableSize` 无法固定 guest 分辨率。
- `MacRenderView` 让 Metal 图层及其直接父图层始终保持 guest 像素 bounds，父图层通过 transform 显示在 AppKit 内容区域中。由此避免渲染线程与主线程竞争同一 layer.bounds，也无需给现有 GameActivity/JNI 增加不完整的 resize 协议。
- 默认失焦暂停为本地移植新增，旧配置将 true 持久化；仅更改 Swift 默认值不会改变已有游戏。本轮保留其他游戏选择，单独更改用户当前 Minecraft；默认值、持久化兼容及运行中策略分别验证。

## 原生鼠标事件（2026-10-09）

- 旧 GameView 对所有普通鼠标事件读取 `scrollingDeltaY`。本机 NSEvent 在左键按下时抛出 `NSInternalInconsistencyException: Invalid message sent to event`，调用尚未进入 `tl_ga_mouse`。后台捕获异常的小测试与正式响应方法的反向回归均复现；不能因 Runner 没有进程崩溃就认定没有输入异常。
- Apple 的 [`pressedMouseButtons` 文档](https://developer.apple.com/documentation/appkit/nsevent/pressedmousebuttons)明确表示它读取调用时的全局状态，与事件队列无关。排队的按下事件可能读到已松开的状态；现在按被接纳的 down/up 维护按钮，失焦清除，黑边内开始的按压不进入游戏。
- 原生 NSEvent 工厂即使指定 right/other 类型，也会默认生成 buttonNumber 0。回归测试需在私有 CGEvent 副本上指定按钮；所有对象仅直接交给隐藏 GameView，不向系统投递。隐藏 NSWindow 的 sendEvent 没有触发 responder，不能把该测试夹具失败当成产品复现。
- 当前回归直接覆盖正式 GameView 到 Android 输入边界；真实菜单操作另由 CUA 与用户手动点击验证。计数器、坐标换算和画面渲染本身都不证明可见点击可用。
