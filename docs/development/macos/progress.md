# 审计进度

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
