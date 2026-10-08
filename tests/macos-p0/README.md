# macOS P0 验证入口

本目录使用仓库自建 ARM64 ELF 验证可执行内存、真实 loader 和 Runner。需要 Apple Silicon Mac、完整 Xcode、Python 3.9+、支持 Android target 的 upstream LLVM clang 与 lld。默认在后台运行，不创建窗口、不激活 AppKit、不注入崩溃，也不下载依赖或加载外部 APK。

在仓库根目录执行：

```sh
./scripts/test_macos_p0.sh
```

默认运行 memory、runner 和 core 三组。Runner 在 Foundation run loop 中执行相同 ELF 和控制协议，默认做 2 次后台启停。可见窗口和故障注入都需要额外参数；用户正在使用桌面时保持默认模式。

```sh
./scripts/test_macos_p0.sh --suite memory
./scripts/test_macos_p0.sh --suite runner
./scripts/test_macos_p0.sh --suite core
./scripts/test_macos_p0.sh --build-only
python3 src/macos-p0/session.py --seconds 20
```

最后一条命令也是后台模式。确实需要人工检查时，使用 `python3 src/macos-p0/session.py --show-window --seconds 20` 显示一个窗口；Command-P 暂停/恢复，Command-Q 或关闭窗口会保存合成 checkpoint 并退出。

`--gui` 显式启用窗口/焦点/菜单检查，默认循环次数为 1；`--cycles N` 显式选择压力次数。`--faults` 单独启用 deliberate abort、SIGKILL、MAP_JIT 非法写入及父进程故障测试，系统可能弹出崩溃报告。不能同时使用 `--gui` 和 `--faults`。这些参数供独立测试环境使用，不作为用户日常桌面上的默认验收。预期信号退出只能证明故障用例符合断言，不能代表桌面没有受到影响。

脚本用 `xcrun` 选择 host clang/SDK，优先使用本机 Homebrew LLVM clang，lld 从 PATH 或已安装 Android NDK 查找。可通过 `HOST_CC`、`ELF_CC`、`ELF_LD`、`ELF_READELF`、`ELF_OBJDUMP` 指定已有工具的绝对路径。没有合适工具时直接报错，不自动安装。验证环境为 Apple clang 21、upstream clang 23.1.2、NDK lld/readelf/objdump 17.0.2；scanner 原有文本格式 oracle 在 LLVM 23 readelf 下有已记录的不兼容，因此默认使用 lld 同目录的 readelf/objdump。

所有构建、签名和运行产物都写入忽略目录 `build/macos-p0`：

| 文件 | 用途 |
| --- | --- |
| `environment.json` / `commands.json` | 工具版本、Git 基线、实际构建/签名命令与诊断 |
| `source-manifest.json` / `fixtures.json` | 编译输入摘要、ELF 摘要、页布局、动态段类型 |
| `results.json` / 各项 `.log` | 最近一次所选 suite 的结果；完整验收使用默认 all |
| `test-selection.json` | 本次是否启用了窗口、故障及压力次数，避免误读证据范围 |
| `interactive-results.json` / `interactive-source-manifest.json` | 修改默认策略之前的 39 组交互/故障测试快照；仅作为历史证据，不自动重跑 |
| `sessions/<UUID>/` | 每次 Runner 的 JSON 事件、进程结果、stderr、合成 checkpoint |
| `Husk P0 Runner.app` | 本机 ad-hoc 签名、启用 Hardened Runtime 的 arm64 原型 |
| `runner-dependencies.txt` | 原型实际动态链接依赖，只允许系统库与 framework |

`fixture.c` 的全局变量、volatile 构造函数/指针及显式 LL/SC 原子操作避免测试被优化掉，`x18.S` 直接覆盖 ADR、ADRP、x18 与代码指针。构建还断言 4 KiB fixture 确实存在代码/可写数据共用 16 KiB host page，三种 relocation 编码确实进入动态段。

`loader-test.c` 链接真实 `husk-tl-ld`。`host-adapter.c` 只提供日志和一个有确定返回值的 `p0_import`，不冒充完整 bionic/JNI 环境；线程由 macOS harness 创建，再调用真实 guest 指令。`classic-test.c` 直接包含 classic 实现，验证其静态 ELF 核心；不启动 NativeActivity/DEX。`probe-adapter.c` 仅供 scanner，返回“本机没有 iOS StikDebug 预热区域”。

Runner 的 guest 工作负载是合成计数器，checkpoint 只证明存档确认协议及文件提交顺序。图形引擎、真实游戏存档、音频、游戏输入、DEX/VM、Developer ID、公证和最低系统实测都不属于本入口的通过含义。详细决策与结果见 [P0 报告](/Users/tanmy/Projects/Husk-macOS/docs/2026-10-07-macos-p0-report.md)。
