# Husk macOS P1–P3 实施与验收

> 后续状态（2026-10-08）：本报告和配套 JSON 保留验收当时的版本、机器路径与提交状态。全部已有工作现已保存为本地检查点 `9573597`；后续修复见 [审查修复报告](2026-10-08-macos-review-report.md)。本地提交未推送。

2026-10-08。原生工程、资料库与第一款自建 ELF 游戏已实现，本地构建、功能回归及后台稳定性验收通过，达到 P3 内部可运行原型。远程 CI、完整前台交互及实体外设等门槛仍按下文保留为待验收项。本轮授权截至 P3，P4–P6 未开始。

开发产物：[HuskMac.app](../build/macos/Product/HuskMac.app)。构建与使用见[原生 macOS 指南](macos.md)。工作保留在 `codex/macos-p0`，基线 `82f33e858952f9fda3cf224e839f4385894e2d5b`；原 `main` 仍为 `5a7d2df9a568ccb93e3395270e430da649a85874`。全部为本地未提交改动，未推送、发布或使用用户的签名证书。

[验收结果快照](2026-10-08-macos-p1-p3-results.json) 包含最终二进制 SHA-256、实现文件 hash、31 项检查名、20 次会话、两份持续运行候选的完整采样和日志摘要。长测与最终候选分开记录，269 个实现文件已与干净源码导出逐项核对。

**已交付范围**

| 阶段 | 实现 | 验收状态 |
| --- | --- | --- |
| P1 | CMake 的 HuskMac、NativeRunner、SharedCore、SharedLibrary、NativeRuntime；固定图形源码；打包、最小权限分工及 CI 定义 | 主工作区及独立干净源码导出重建通过；签名、架构和动态路径检查通过；远程 CI 尚未运行 |
| P2 | SwiftUI 资料库、搜索、导入/拖放、图标、游戏设置、系统菜单与 Settings 场景；受管数据及存档 | 自动化服务闭环通过；一次真实主窗口“添加示例游戏”操作已落盘；完整前台视觉、拖放及菜单操作仍待验收 |
| P3 | 两个 Orbit 样本通过实际 ELF loader 执行；独立 AppKit 游戏进程；ANGLE/Metal、输入、PCM、暂停与保存协议 | 31 项端到端检查及 20 次后台会话通过；持续运行结果见下文 |

P3 使用仓库自建 **Orbit Garden** 和 **Orbit Garden · Dusk**。玩法、GLES 绘制、PCM 合成和存档逻辑位于交叉编译得到的 Android arm64 ELF 中，由 `husk-tl-ld` 真正加载执行。宿主只提供小型 fixture ABI 和允许的 GL 导入。这些包不是可安装到普通 Android 设备的商店游戏，也不证明 Unity、Unreal、NativeActivity、GameActivity、DEX/JNI 等既有引擎已完成 macOS 移植。

**模块与数据边界**

| 模块 | 当前职责 |
| --- | --- |
| [CMakeLists.txt](../CMakeLists.txt) | macOS arm64 编译目标、依赖路径、资源、打包及 CTest |
| [SharedCore](../src/macos/SharedCore) | 复用原 ZIP、ELF scanner、JSON、prefs、blit；补充 bundle 条目列举和提取 |
| [SharedLibrary](../src/macos/SharedLibrary) | Foundation 资料库服务、原元数据/rank 模型、原子索引与 Swift Process 会话监督器 |
| [HuskMac.swift](../src/macos/HuskMac/HuskMac.swift) | 原生 SwiftUI 导航、详情、导入、图标、设置与退出联动 |
| [NativeRunner](../src/macos/NativeRunner) | AppKit/CAMetalLayer、键鼠/GameController、AudioQueue、ELF fixture ABI、存档及协议 |
| [fixture](../tests/macos/fixture) | 自建游戏源码；移动、收集八颗星星、障碍、分数、完成轮数与音频 |

每次游戏启动创建独立进程。主界面只发送命令并接收有 session UUID、PID、协议版本和严格序号的事件。旧会话不能改写新状态；暂停确认发生在停止 guest 更新之后；正常结束必须先有原子存档确认，再有终态事件和操作系统回收。输出读取与错误日志有限制；失联会触发停止期限和子进程回收。Runner 同时独立监视父进程消失。

资料位于 `~/Library/Application Support/org.husk.HuskMac`。APK 复制到 `Games/<id>`；bundle 中的 APK 提取到导入暂存目录。支持最多四个 APK 的 XAPK/APKM/APKS，stored/deflate 均有覆盖。哈希去重、索引原子替换和进程间文件锁避免普通重复导入与覆盖。损坏索引、损坏或不可读取存档会明确报错并保留原文件。

`Saves/<id>` 独立于游戏副本。“移除游戏”保留存档，同一身份重新导入可继续；“清除存档”是单独确认操作。运行中禁止这两项破坏操作。不同版本不自动覆盖旧版本。普通 APK 仍可扫描入库，只有 guest ELF 的 SHA-256 与随附可信清单匹配的 Orbit 样本可以执行。

**依赖、签名和构建**

| 项目 | 固定来源 / 实际验证 |
| --- | --- |
| ANGLE | WebKit `f488eac0e00cee453b7ca9f24c42f585df236e97`，macOS 源码构建；Metal 后端实际绘制 |
| MoltenVK | v1.4.2 / `db66022459ffb663aa2b50f6b018bc2e124f5edf`，macOS 源码构建；实际创建 Vulkan instance、枚举 Metal 设备 |
| 产物 | 约 13.3 MB；主 App、Runner、ANGLE、MoltenVK 均为 macOS arm64；最低版本字段不高于 14.0 |
| 主 App | ad-hoc Hardened Runtime，entitlement 为空 |
| 本地开发 Runner | `allow-unsigned-executable-memory` 和 `disable-library-validation` |
| 同 Team ID Runner 模板 | 仅 `allow-unsigned-executable-memory`；未用真实证书验收 |

图形依赖在 [macos.lock.json](../dependencies/macos.lock.json) 固定提交，缓存同时记录二进制 SHA-256。Bundle 带许可证、ANGLE 下游 notices 和 MoltenVK ExternalRevisions。动态库解析只指向系统或 bundle，未带 StikJIT、iOS pairing、QEMU guest 或开发者 Steam/Homebrew 运行依赖。

发现 ad-hoc Hardened Runtime Runner 加载 ad-hoc ANGLE 时因缺少匹配 Team ID 被系统拒绝，故把 `disable-library-validation` 限定在开发模板；这是实际失败后的必要例外。正式签名模板与开发模板分开，打包器不会自动选择证书。Developer ID、公证、安装更新和完整发行许可审查仍在 P6。

Swift 构建曾遗漏最低系统 target，产物出现 `minos 27.0`；已显式设置 `arm64-apple-macosx14.0` 并通过 Mach-O 字段核验。这个字段不等于 macOS 14 实机兼容结论。CMake 的中间 app 曾夹带 Swift `.d` 文件导致严格签名失败；最终 `Product` 目录只收集需要的文件，并从嵌入组件向外签名。

最终源码导出包含 325 个非 ignored 文件，位于 `build/macos-p3-clean-source`；独立构建在 `build/macos-p3-clean`，只复用已按提交和 SHA-256 校验的图形缓存。全部实现文件与导出清单一致，重建及 5/5 CTest 通过。这证明本机干净源码/构建目录可复现，不代表另一台无开发环境的 Mac 已验收，也不承诺逐字节可重复二进制。

[CI 配置](../.github/workflows/macos.yml) 固定 action commit，托管 `xcode-27` arm64 job 执行构建、核心与签名检查。真实 Metal/AudioQueue、会话和 30 分钟运行只在显式选择的物理 `husk-metal` runner 执行。Context7 返回的 GitHub runner-images 文档确认该标签当前为 preview；本地未推送，因此远程 CI 门槛仍是待验收项。

**功能与稳定性证据**

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 正式工程 CTest | 5/5 组通过 | [最终日志](../build/macos-final-tests.log) |
| 资料库/会话端到端 | 31/31，通过同一份最终产物 | [latest.json](../build/macos/TestResults/latest.json) |
| 干净源码重建 | 构建、签名、5/5 组（含 31 项）通过 | [重建日志](../build/macos-p3-clean-build.log) |
| 最终产物平台/签名/rpath | 四个 Mach-O 全部通过 | [bundle-verification.json](../build/macos/bundle-verification.json) |
| 反复启动/换游戏 | 20/20 次；每次运行 60 帧、保存并确认 PID 已消失 | [cycles result](../build/macos/Cycles-final-20261008/result.json) |
| P0 既有回归 | 当前默认后台 30/30；未运行 GUI/主动故障选项 | [P0 日志](../build/macos-p0-final.log) |
| 30 分钟持续渲染 | 1,800.07 秒通过，107,860 帧，约 59.9 fps；RSS 采样 25.5–30.4 MiB；正常保存/回收 | [长测结果](../build/macos-soak-submitted-20261008/run/result.json) |
| 最终候选持续检查 | 300.05 秒通过，17,974 帧，约 59.9 fps；RSS 采样 30.4–30.5 MiB；正常保存/回收 | [最终候选结果](../build/macos-final-candidate/run/result.json) |

31 项端到端包括导入/图标/压缩 bundle/去重、损坏与不支持输入、伪造 fixture 拒绝、重启持久化、设置字段合并、真实 guest 键盘/手柄/鼠标输入路径、完成游戏目标、非零 PCM、暂停清键、焦点丢失清输入、保存顺序、移除再导入恢复、换游戏、子进程意外退出后恢复、存档损坏/读取失败以及隐藏 AppKit/CAMetalLayer 绘制。

音频宿主测试创建真正 AudioQueue，输出增益固定为零，确认设备 callback 消费 PCM；guest 同时产出非零采样和可检查 WAV。手柄测试向与 GameController 相同的输入处理路径注入值。它们分别证明音频管线与输入路径，未验证耳听质量或实体控制器。

运行隔离采用受控 `_exit(74)` 验证意外进程结束和恢复，不产生 abort 崩溃报告。SIGSEGV/abort 型故障隔离证据仅来自历史 P0，不标作本轮重跑。默认测试无可见窗口、无扬声器输出，只有一个不显示也不激活的 AppKit 窗口用于 CAMetalLayer 路径；未处理用户之前的系统崩溃提示。

稳定性测试发现的实质问题是 ANGLE Metal pbuffer `swap` 不提交 command buffer，导致未提交 GPU 命令积累；首次 121 秒 RSS 达约 431 MiB。增加 autoreleasepool 后仍增长。核对锁定源码 `OffscreenSurfaceMtl::swap` 后，在离屏 present 中增加 `glFinish()`；可见窗口仍走正常 EGL swap。失败采样保留在 `build/macos-soak-20261008` 和 `build/macos-soak-fixed-20261008`。修复后完整 30 分钟采样为 25.5–30.4 MiB，未再出现持续增长，结束后正常保存并回收 PID 21208。

长测使用修复离屏提交后的冻结候选，其后又增加隐藏窗口验证及最终 UI/存档边界修复，因此其 NativeRunner SHA-256 与最终产品不同。最终产品另有 5 分钟冻结候选检查，56 个普通文件均与该冻结候选相同；不能把早期候选的 30 分钟记录写成最终每个字节均已运行 30 分钟。候选清单及最终产物 hash 已随结果快照保留。

实际 ANGLE 输出已检查，并保存为可审阅文件：[初始画面](macos-evidence/orbit-initial.png)、[隐藏 AppKit 窗口绘制](macos-evidence/orbit-native-window.png)、[Dusk](macos-evidence/orbit-dusk.png)。它们是游戏渲染证据，不是主资料库窗口截图。NSHostingView 离屏导出无法正确呈现 AppKit 材质的尝试已舍弃，相关临时 target 已删除。

**尚未通过的验收与下一阶段**

完整前台 UI 操作与视觉验收尚未完成。一次正常主窗口在后台启动，并点击“添加示例游戏”后实际索引已有两项；随后 CUA native pipe 断开，主进程继续存活，DiagnosticReports 未出现新的 HuskMac/NativeRunner 报告。遵守用户要求，没有通过重开窗口循环排查，也没有关闭其现有窗口。

实体手柄热插拔、可听音质、音频设备切换、全屏、多显示器/倍率、睡眠唤醒、最低 macOS 版本和另一台干净 Mac 仍需对应实际验收。当前固定 640×400 画布及 letterbox 输入路径已测试，但不能据此宣称所有桌面行为都已通过。独立进程提供生命周期和故障隔离，不提供文件系统/网络安全沙箱。

P4 应按原计划逐类接入已有引擎，选择合法固定样本和明确完成条件；首先拆除 fixture 专用宿主边界所需的 bionic/JNI、资源与引擎生命周期适配。P5 保留 QEMU/guest/VMRunner 工作，P6 承接发行及跨机器验收。README 已把 iOS 支持列表与 macOS 当前能力区分开。
