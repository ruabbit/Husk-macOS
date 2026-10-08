# 审计发现

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
