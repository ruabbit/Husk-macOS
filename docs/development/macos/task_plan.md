# Husk macOS 迁移实施

当前优先级更新（2026-10-11）：已合入上游 `8a9dc1b` 的 75 个新提交，并将新增共享 Dalvik/NDK 等模块编入 macOS，默认 CTest 25/25 与包校验通过。旧 Unity 启动链路保持；新版 Unity 6 已被上游转至 Java 路径，macOS 尚缺受控资源打包、Java profile、关闭确认和实机交互验证。CUA 断开导致旧主程序尚未正常重启，先完成这一候选更新尾项，再继续 [上游功能接入现况](upstream-parity.md) 中的具体接线步骤。个人 Google Play 登录仍失败。以下 P0–P6 表格是历史记录，不代表当前功能对齐。

日期：2026-10-08。八项审查问题的代码修复与文档核对已完成；已有迁移工作保存为 `9573597`，VM / Minecraft 修复保存为 `fd9c470`。P5 的 Minecraft 黑屏、ANR 和持续音频仍未通过，P6 尚未验收。本文后面的阶段表是历史记录。

用户追加构建约束：统一复用 `build/macos`，直接覆盖当前候选；停止保存多个阶段/日期构建和源码导出副本。版本回退使用 Git，日志保存在 `build/logs`；游戏存档与 Android 磁盘保留原位。已移除 10 个旧 CMake 目录、4 份源码导出以及旧候选和依赖中间产物（约 2.38 GiB）。当前 VM-enabled 候选已在同一目录全新构建，12/12 后台 CTest 与 17 个 Mach-O 的签名/闭包检查通过；662 个受保护数据文件未改变。

2026-10-09 窗口与点击修复：固定画布缩放/居中、16:9 初始窗口和默认关闭失焦暂停已实现。随后用户发现真实点击无响应；已定位普通鼠标事件读取滚轮专用属性抛出异常，修复后在用户打开的 Minecraft 中验证 Settings、设置页切换和调整窗口后的命中。当前 14/14 后台回归与 17 个 Mach-O 签名/闭包检查通过，仍复用唯一候选。内部渲染保持 1280×720；世界内视角捕获、全屏、多显示器及 VM/P6 验收仍待完成。

## 审查修复

| 工作 | 状态 | 证据 |
| --- | --- | --- |
| 保存所有未提交迁移工作 | complete | 本地检查点 `9573597`，237 文件 |
| VM 退出竞态、系统要求、Minecraft 样本哈希 | complete | `fd9c470`；12/12 CTest，17 个 Mach-O 签名与闭包核验 |
| CI 标签与仓库卫生 | complete（本地） | 稳定 macos-26；actionlint 通过；P0 harness 迁入 tests 后 30/30 |
| macOS 许可证说明 | complete（审计文档） | QEMU → libssh → OpenSSL 3、缺失 notices/对应源码列为发行阻塞 |
| 审查记录、最终提交 | complete（本地） | [审查报告](../../2026-10-08-macos-review-report.md) 与结果快照；源文件/文档链接检查通过，所有修复纳入本地提交 |

## GUI / 上游同步交付

| 工作 | 状态 | 验收 |
| --- | --- | --- |
| 核对旧 GUI、实际资料库与 upstream | complete | 原 UI PID 15359；真实用户 APK 与 P4 样本不同；27 个 upstream 提交已审计 |
| 同步适用的上游变更、修正能力判断与文案 | complete | 117 路径三方整合；旧资料库动态能力；Minecraft 实验入口与独立完整性检查 |
| 实际 APK 与回归验证 | complete（本机后台） | 11/11 + P0 30/30；实际用户 APK 世界/移动/两次恢复/60 秒/保存退出通过；原 P4 样本世界加载/退出通过 |
| 更新用户 GUI 与交付记录 | complete（进程/能力核对） | 0.2.0 PID 13772 单次后台启动；日常 Minecraft playable=true；原 index/设置/APK 不变。CUA pipe 断开，GUI AX/截图未验收 |


| P5 当前工作 | 状态 | 验收 |
| --- | --- | --- |
| VM 依赖、guest 来源及冷启动配置 | complete（本地） | 固定来源/hash；脚本与 notices；367 文件独立源码重建；首次设置体验待补齐 |
| 独立 VMRunner 与原生宿主 | complete（基础实现） | 主 App 无 entitlement；Metal/键鼠/静音 AudioQueue；正式 Swift 控制器正常关机/同对象重开通过 |
| Android 冷启动及安装 Minecraft | partial，游戏验收阻塞 | TCG/HVF 冷启动、安装/HTTPS 通过；Minecraft 黑屏，后续有 guest ANR；持续 PCM 未通过 |
| 数据/网络/恢复及回归 | complete（已测范围） | 关机/重开、安装与文件持久化、qcow2 检查；VM 10/10、TL-only 9/9；快照显式禁用，发行/设备项未测 |
| P5 交付记录 | complete（阶段未通过） | P5 report/results、构建指南、失败证据已保存；候选可复查；P4 产物/哈希保留 |

| P4 当前工作 | 状态 | 验收 |
| --- | --- | --- |
| 样本与已有 GameActivity 路径核对 | complete | APK/ELF hash、manifest、依赖与现有 JNI 适配差异；原文件不变 |
| 正式 Native Runner 接入 Minecraft | complete（集成） | 实际 loader/JNI/图形/输入/音频；AAudio 配置探测与文本桥接已修复 |
| 真实游戏交互与数据闭环 | complete（指定样本/后台） | 中文追加、键鼠/虚拟手柄、20 次 Activity 恢复、600.17 秒世界运行、保存重开、隐藏 CAMetalLayer、受控退出后重启均通过 |
| 回归及 P4 兼容矩阵/报告 | complete（本地） | 9/9 CTest、31 项集成、P0 30/30；343 文件独立源码重建；281 实现文件及 56 产物文件一致性通过；其他引擎明确未验证 |

| 当前实施 | 状态 | 验收 |
| --- | --- | --- |
| P1：正式原生工程、共享核心、固定图形依赖、签名及 CI | complete（本地） | 325 文件干净源码导出重建及 5/5 组通过；macOS arm64/签名/rpath 通过；CI 配置未验证，远程运行待首次推送 |
| P2：SwiftUI 资料库、导入扫描、图标/设置与持久化 | complete（内部原型） | 31 项端到端检查包含导入、重启、设置、数据保留及错误；主界面无 entitlement；完整前台视觉/拖放验收尚未完成 |
| P3：自建可玩 ELF 游戏与原生运行闭环 | complete（后台验收） | 真正 ELF/GLES/PCM、输入、暂停/恢复、存档与隔离通过；20 次后台生命周期通过；修复候选 30 分钟与最终候选 5 分钟均保存/回收通过；前台/实体外设验收边界见报告 |

执行约束：不点系统崩溃提示；测试默认无窗口、无声音、无主动崩溃；不反复抢焦点。复用已有证据，只有新增变更/缺口触发相应复测。用户在 P4 后要求继续推进；当前执行 P5，P6 发行仍留待单独推进。

P5 交付：[P5 VM 报告](../../2026-10-08-macos-p5-report.md) 与 [结果快照](../../2026-10-08-macos-p5-results.json)。P5 尚未通过，后续先解决 VM 中游戏启动和持续音频，P6 未开始。

此前交付：[P4 Minecraft 报告](../../2026-10-08-macos-p4-report.md)、[P4 结果快照](../../2026-10-08-macos-p4-results.json)、[P1–P3 报告](../../2026-10-08-macos-p1-p3-report.md)、[构建指南](../../macos.md)。本轮指定 Minecraft 样本的后台闭环已完成；原计划的其他引擎、完整前台/设备验收、远程 CI 和发行门槛仍待对应验证。

| P0 工作 | 状态 | 验收 |
| --- | --- | --- |
| 固定上游 main 基线，建立 P0 分支 | complete | codex/macos-p0，起点 82f33e8 |
| JIT 权限矩阵与内存契约 | complete | 四组 ad-hoc Hardened Runtime 权限矩阵；双映射仅需 unsigned-memory；MAP_JIT 常量执行及执行态数据写入对照已验证 |
| 自建 ELF fixture / 两条 loader | complete | 新版通过全局数据、三种重定位、TLS/x18、四线程、4/16 KiB；修复混合页代码地址；classic 16 KiB 通过并明确拒绝混合页/TLS |
| 原生 Runner 生命周期与窗口原型 | complete | AppKit 窗口/菜单、暂停、checkpoint、故障/超时/父进程退出和 20 次回收通过；原生 UI 手动操作也已核验 |
| 回归、决策记录、依赖许可清单 | complete | 历史 39 组、当前后台 30 组通过；报告、复现说明、许可清单及 P1 交接已完成 |

| 阶段 | 状态 | 产出 |
| --- | --- | --- |
| 1. 核对仓库、分支和历史 | complete | 已锁定 fork main 及上游两分支 |
| 2. 审计 UI、运行时、依赖、构建和测试 | complete | 架构、平台耦合、分发和测试缺口已核对 |
| 3. 执行可行的本地基线验证 | complete | 保留原始失败、适配通过结果及发行态 JIT 失败证据 |
| 4. 编写分阶段迁移计划 | complete | 已写入原生架构、P0–P6、优先级和验收门槛 |
| 5. 检查报告与交付 | complete | 三份文档、链接检查、Mermaid 渲染及工作区核对完成 |

P0 约束：main 分支保留；不下载游戏或启动未知 APK；仅使用仓库自建 fixture；测试权限只授予测试子进程，不调整系统安全设置；区分 ad-hoc Hardened Runtime、Developer ID、公证与实机图形证据。

用户追加约束：禁止继续反复启动/激活可见窗口影响桌面。默认测试改为无窗口后台模式，故障注入与可见测试均需显式选择。本轮后续仅做后台验证；此前主动 abort 造成的系统弹窗已如实记录。

比较范围：上游 main 与 claude/epic-hypatia-2hsqfv，同时核对 fork main 的落后差异；已向用户发出可选澄清。

错误/限制：未发现 .gitmodules（普通文件读取返回不存在）；main 无 .github/workflows，通配符读取失败，已改为 git tree 检查；无已记录的 Husk 项目记忆；此前的 handoff 文档不是本轮工作指令。

测试问题：main scanner 缺 tl_find_stikdebug_prewarmed 链接符号；topic 首轮 fixture 的 TLS 断言受 NDK clang 默认行为影响，改用上游 LLVM 验证；va 独立宿主缺 tl_log_line。原始失败记录保留，不改产品代码来掩盖。

后续诊断：LLVM 23 readelf 改变 RELR 展示，测试正则少计；固定 readelf 17 后 scanner 通过。Hardened Runtime JIT 自测按预期暴露 CODESIGNING Invalid Page，已作为迁移首要门槛。完整 App 与游戏/VM 验收留在迁移阶段。

文档验证：Mermaid 首次渲染缺指定版本 chrome-headless-shell；改用已安装 Chrome 的临时 PUPPETEER_EXECUTABLE_PATH 后成功，未安装依赖。三份文档的本地链接/行号和代码围栏检查通过。产品代码、脚本、测试和 README 与初始状态无差异。

此前审计/P0 完成后的历史交接已由本页顶部 P1–P4 状态更新取代。P0 的可见测试已停止；当前默认入口只在后台运行。用户明确不需要处理系统崩溃提示。
