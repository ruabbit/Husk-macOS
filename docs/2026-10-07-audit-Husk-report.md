# Husk 两分支审计与 macOS 迁移现况

审计日期：2026-10-07，Asia/Shanghai。结论：**以最新上游 main 为迁移基线，保留自研翻译层和 QEMU 两条能力线，新增原生 macOS App 与独立运行进程。先解决发行态 JIT，再扩大界面迁移。**

Husk 已有可复用的 Android ARM64 加载器、运行时桥接和 macOS 测试工具，但目前没有原生 macOS App target。本次没有修改产品源码、合并分支、运行真实 APK 或启动虚拟机。仓库文档和截图中的游戏表现属于上游记录；下文单独列出本次实际验证结果。

配套文件：[迁移计划](2026-10-07-macos-migration-plan.md)、[验证证据与复现说明](2026-10-07-husk-audit-evidence.md)。

**分支范围与推荐基线**

fork 的 origin 实际只暴露 main；上游 Leviidev/Husk 有下面两个分支。本次按上游两分支审计，并核对 fork 与上游的差异。所有结论固定在以下提交，后续上游变化不自动纳入。

| 对象 | 提交 | 审计判断 |
| --- | --- | --- |
| ruabbit/Husk-macOS:main | `5a7d2df9a568ccb93e3395270e430da649a85874` | 当前工作区；版本 0.8.1、build 31；审计开始时干净 |
| Leviidev/Husk:main | `82f33e858952f9fda3cf224e839f4385894e2d5b` | 推荐迁移起点；fork 落后 2 个提交，无独有提交 |
| Leviidev/Husk:claude/epic-hypatia-2hsqfv | `756c8d0c9d81ffcf7e282cac98a69af1ff299522` | 早期翻译层实验及 iOS CI 分支，不是 macOS 分支 |
| 上游两分支共同祖先 | `e768fdba45d81d99ee247c83f49a0ec5faf3df9a` | main / 实验分支各有 86 / 4 个独有提交 |

fork 到上游 main 的 `src/`、`tools/`、`tests/` 完全相同。两个新提交修改 README、截图名称，并在 `scripts/ci_build.sh` 补上 MoltenVK 构建。源码审计和本地测试因此同时适用于这两个 main 快照。

实验分支的 4 个独有提交是：`28a3dcc` 初始翻译层、`9681b31` IPA/翻译层 CI、`f403458` PyYAML 安装、`756c8d0` region.c 补丁路径修复。当前 main 已有远超初始扫描器的实现，补丁路径也已采用更严格的 `--batch --forward` 写法。适合借鉴的是 CI 的依赖缓存和宿主测试思路；直接搬入旧工作流会遗漏 main 新增的 MoltenVK、Rust pairing 等步骤。

| 源码量口径 | fork / 上游 main | 实验分支 |
| --- | ---: | ---: |
| `src/app` 原创源码文件 / 物理行 | 47 / 16,261 | 28 / 11,713 |
| `src/ios-jit` 文件 / 物理行 | 13 / 2,652 | 13 / 2,600 |
| `src/translation-layer` 文件 / 物理行 | 19 / 11,844 | 7 / 2,519 |
| `src/translation-layer-next` 文件 / 物理行 | 58 / 18,707 | 0 |
| `tools` 源码文件 / 物理行 | 19 / 4,299 | 0 |

统计包含 `.c/.h/.m/.S/.swift/.metal/.rs` 的空行和注释，排除 vendored Frameworks；它用于判断体量，不代表已逐行形式验证。`translation-layer` 与 `translation-layer-next` 是同时编入 main 的源码目录，不能当作两个 Git 分支或二选一实现。

**现在实际有什么**

| 层次 | 当前实现与边界 | 迁移处置 |
| --- | --- | --- |
| App 与资料库 | SwiftUI 页面、APK 导入、扫描、图标、每游戏设置、发现源、文件与日志；Swift 文件中 18/39 显式 import UIKit | 保留数据和业务规则，重建桌面呈现及平台服务；18/39 只是显式导入下限 |
| 基础翻译层 | ZIP/ELF 扫描、资源表、DEX 解释器、Java framework shim、软件 framebuffer、偏好存储、早期 ELF loader | 扫描与数据格式优先共享；classic loader/DEX 的应用特例需独立维护 |
| 原生运行时 | ARM64 ELF linker、重定位、bionic ABI、JNI/HLE、TLS/x18/syscall 适配、GLES/Vulkan/audio/input 桥接 | 主要复用价值所在；重点改宿主内存和生命周期 |
| 引擎驱动 | Unity IL2CPP、Cocos、GameActivity、SDL、Unreal/NativeActivity、Rockstar 启动入口 | 按引擎逐个验收，检测出引擎不等于任意同引擎 APK 兼容 |
| VM 模式 | UTM QEMU 10.0.12 dylib、TCG、virtio GPU/virgl、ANGLE、音频环形缓冲、snapshot/balloon、guest 文件/命令桥 | 独立 macOS 构建和运行进程；保留 TCG 基线，再试 HVF |
| macOS 先行代码 | `tools/unity-window.m` 已有 NSView/CAMetalLayer/鼠标；其他 tools 有离屏和引擎验证入口 | 是原型参考；路径、资源、退出与分发均需产品化 |
| 工程与发行 | Xcode 仅 Husk iOS App + HuskJITHelper iOS extension；IPA 脚本和 iOS entitlement | 新增 macOS targets、依赖产物、签名/公证与安装验收 |

重要依据：[project.yml](../src/app/project.yml:31)、[运行时路由](../src/app/Husk/TranslationLayer.swift:45)、[原生运行时接口](../src/translation-layer-next/husk-tl-unity-app.h:4)、[Mac 窗口原型](../tools/unity-window.m:25)。

基础 DEX 路径仍有对特定游戏类/方法的调用，例如 [husk-tl-load.c](../src/translation-layer/husk-tl-load.c:1882) 的初始化和启动逻辑。它不是已经完整移植的 ART/Android framework。旧的 `docs/04-translation-layer.md` 又停留在“尚不能运行 App”的早期设计，因此既不能照搬旧文档估计现况，也不能从几个引擎入口推导出通用 Android 兼容性。

**必须进入迁移计划的问题**

| 优先级 | 发现与证据 | 对迁移的影响 |
| --- | --- | --- |
| P0 | 当前 macOS xmem 用普通匿名内存、`mach_vm_remap` 和 RX alias。本次自测开发态返回 42；Hardened Runtime + `allow-jit` 下签名校验通过，但执行时被系统以 `CODESIGNING / Invalid Page` 终止 | 仅换 UI 或加 entitlement 不足以形成可发行 App；首先确定发行态内存布局与写入协议 |
| P0 | 原生引擎状态是全局单例，启动用 IDLE 原子比较；接口明确引擎不能卸载，UI 明确要求退出 Husk 才能换游戏 | 引入每次运行一个 Runner 进程，解决正常切换、崩溃隔离、线程/内存回收 |
| P0 | 当前没有 macOS target；所需 build/、QEMU 源码树、guest 资源均未预置 | 先建立可复现的 macOS 构建，不能把 51 个 C 文件可解析当作 App 可构建 |
| P1 | `HuskApp` 使用 UIApplicationDelegate/屏幕方向；6 个文件含 UIViewRepresentable；渲染层依赖 UITouch、UIScreen 和 UIApplication 通知 | 原生 AppKit/SwiftUI 宿主、输入、焦点、窗口缩放与屏幕倍率需要明确适配 |
| P1 | native runtime 和 QEMU 的视图、状态、音频、信号处理器在同一进程；一些失败/退出只终结线程 | 主 UI 不能承担不可卸载引擎的生命周期；Runner 必须有停止超时、存档确认和异常回收 |
| P1 | `HuskAudio`/`TLUnityView` 使用 AVAudioSession；本机音频核心已有 AudioQueue/AVAudioEngine 基础 | 复用 PCM/混音层，替换会话与设备切换逻辑，补静音/休眠/耳机热插拔验收 |
| P1 | 数据广泛写入 `.documentDirectory`；guest manifest、镜像地址仍指向 Leviidev/Husk release | macOS 应统一 Application Support 路径与数据版本，避免把用户 Documents 当作 iOS 私有容器；发行源需显式配置 |
| P1 | `BundleUnpacker` 仅支持 bundle 内 stored APK，拒绝压缩 APK 和 Zip64；native API 只接收主 APK + 最多 3 个额外 APK | 在兼容性说明和导入错误中保留真实边界；优先覆盖已有支持格式，不承诺所有 split bundle |
| P1 | ANGLE 脚本跟随 WebKit 默认分支；Mac harness 默认依赖原开发者 Steam/本机 Homebrew 路径 | 固定源码版本、检查下载摘要、构建并内嵌 macOS 依赖，消除开发机路径 |
| P1 | QEMU 参数固定 TCG，macOS validation 显式禁用 HVF/OpenGL/virgl；现有 snapshot 绑定 CPU/RAM/vCPU/图形配置 | HVF 是独立验证项；迁移初期冷启动，自建机器描述及快照，不能复用 iOS 内存快照作为默认路径 |
| P1 | main 无 GitHub workflow；原始测试入口在本机有缺符号和工具链输出依赖 | 建立 macOS 专用测试和签名 JIT 检查，保留 Linux parser 检查；不要直接把旧 CI 标为可用 |
| P1 | 旧许可文档依据 QEMU GPLv2 同进程限制，但后续 App 又加入 Apache-2.0 的 MoltenVK | 重新盘点组合、源码提供与 notices；拆进程是架构选择，不能单独作为许可结论 |

P0 指会阻断可发行原生产品的事项；P1 指进入相应里程碑前必须处理的事项，不是漏洞严重性评级。

可复核位置：[xmem macOS 分支](../src/translation-layer-next/husk-tl-xmem.c:139)、[单例启动](../src/translation-layer-next/husk-tl-unity-app.c:307)、[换游戏限制](../src/app/Husk/TLUnityView.swift:572)、[classic loader 的固定偏移回退](../src/translation-layer/husk-tl-load.c:519)、[资料目录](../src/app/Husk/TranslationLayer.swift:20)、[VM 加速参数](../src/app/Husk/QemuRunner.swift:1050)。固定偏移/指令猜测只属于 iOS 旧 JIT 回退，macOS adapter 应从接口层隔离，不继续依赖它。

**本次验证结果**

环境：Apple Silicon arm64，macOS 27.0（26A428），Xcode 27.0（27A266a），Apple clang 21.0.0。测试在本地独立进程和 ignored `build/audit-2026-10-07/` 内完成。

| 检查 | 结果 | 证据边界 |
| --- | --- | --- |
| Git refs、共同祖先、差异与源码清单 | 完成 | 固定提交，非未来分支状态 |
| Xcode 工程读取 | 成功，2 个 iOS targets | 未进行完整 App 编译 |
| 两翻译层 C/Objective-C 语法检查 | 51/51 通过 | 不覆盖全量链接、Swift UI 或执行 |
| 两分支 page planner | 各 9 项通过 | 4 KiB/16 KiB 布局与输入拒绝 |
| 两分支 scanner | 最终各 41/41 通过，带 ASan/UBSan | main 需要宿主空 prewarm adapter；工具链已选择兼容输出；原始 run.sh 未被改成全绿 |
| SharedPreferences | 通过 | 默认值、类型、读写往返及损坏文件处理 |
| blit | 通过 | 200 次绘制、100 次填充与 CoreGraphics 比对，最大通道差 0；裁剪/拼缝检查通过 |
| ARM64 variadic adapter | 6 项通过 | 增加宿主日志 adapter 后执行；不是完整 Android ABI 认证 |
| frame pacer | 通过 | 1/5/12 ms 负载约 59.9 fps，25 ms 负载 40 fps；停顿后未冲刺 |
| xmem 自建两指令测试 | 开发态通过；Hardened Runtime + allow-jit 失败 | 失败经系统 crash report 确认；未使用 Developer ID，未做公证 |

第一次 scanner 失败分别揭示了两个测试假设：NDK clang 默认生成的 TLS 形式与 fixture 断言不一致；LLVM 23 的 RELR 展示不再逐项含 `R_AARCH64_*`，原测试正则因此少计。选定上游 clang 23.1.2 与 lld/readelf/objdump 17.0.2 后，两分支 41 项均通过。迁移时应修复测试宿主和固定工具链，不把这些现象误报为 parser 回归。

没有验证：真实游戏、GUI 首帧/音频/输入、完整 QEMU 构建、Android guest 启动、HVF、快照恢复、低版本 macOS、Intel Mac、安装/更新、公证。它们已进入迁移计划的独立验收门槛。

**外部文档核对**

通过 Context7 查询了 [Apple JIT 移植要求](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon)、[NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)、[SwiftUI App](https://developer.apple.com/documentation/swiftui/app)、[QEMU 加速器参数](https://github.com/qemu/qemu/blob/master/docs/system/qemu-manpage.rst)、[MoltenVK 构建](https://github.com/KhronosGroup/MoltenVK/blob/main/README.md)及[动态库集成](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md)。当前文档用于指导目标方案，不替代仓库固定版本兼容性测试。

许可事实另按固定版本核对：[UTM QEMU v10.0.12-utm LICENSE](https://github.com/utmapp/qemu/blob/v10.0.12-utm/LICENSE)、[MoltenVK v1.4.2 LICENSE](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/LICENSE)。本报告记录代码及分发组合的矛盾，未将其扩展为完整法律审查。
