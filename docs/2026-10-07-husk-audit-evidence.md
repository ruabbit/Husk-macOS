# Husk 审计验证记录

日期：2026-10-07。对应[审计报告](/Users/tanmy/Projects/Husk-macOS/docs/2026-10-07-audit-Husk-report.md)与[迁移计划](/Users/tanmy/Projects/Husk-macOS/docs/2026-10-07-macos-migration-plan.md)。本文件保存必要的复现条件与结果；完整本地日志和生成的 fixtures 位于 ignored [audit 目录](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07)。

**版本与环境**

| 项目 | 值 |
| --- | --- |
| fork main | `5a7d2df9a568ccb93e3395270e430da649a85874` |
| upstream main | `82f33e858952f9fda3cf224e839f4385894e2d5b` |
| upstream topic | `756c8d0c9d81ffcf7e282cac98a69af1ff299522` |
| merge-base | `e768fdba45d81d99ee247c83f49a0ec5faf3df9a` |
| main 与 topic 独有提交数 | 86 / 4 |
| fork 与 upstream main 独有提交数 | 0 / 2 |
| 主机 | arm64，macOS 27.0（26A428） |
| Xcode / Apple clang | 27.0（27A266a）/ 21.0.0 |
| Android fixture 编译器 | Homebrew clang 23.1.2 |
| Android fixture linker / readelf / objdump | Android NDK 26.3.11579264 的 Darwin 工具，LLVM 17.0.2 |

只读取上游 refs 并导出 topic 测试源码，没有 checkout/merge/cherry-pick。确认两 main 的核心相同所用命令：

```sh
cd /Users/tanmy/Projects/Husk-macOS
git diff --quiet 5a7d2df9a568ccb93e3395270e430da649a85874 82f33e858952f9fda3cf224e839f4385894e2d5b -- src tools tests
git rev-list --left-right --count 82f33e858952f9fda3cf224e839f4385894e2d5b...756c8d0c9d81ffcf7e282cac98a69af1ff299522
```

第一个命令退出 0；第二个输出 `86 4`。完整计数见 [inventory.json](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/inventory.json)。

**源码与工程检查**

对 `src/translation-layer/*.c`、`src/translation-layer-next/*.c` 与该目录的 `.m` 文件逐个执行：

```text
/usr/bin/clang -fsyntax-only -std=gnu11 -Isrc/translation-layer -Isrc/translation-layer-next FILE
```

其中 `FILE` 是逐个枚举出的 translation unit；Objective-C 另加 `-fobjc-arc`。结果 51/51 通过，部分 warnings 保留在 [macos-c-syntax.json](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/macos-c-syntax.json)。此检查没有链接或执行，也没有把 iOS SwiftUI 编译成 macOS。

`xcodebuild -list -project src/app/Husk.xcodeproj` 成功，仅列出 Husk、HuskJITHelper。平台来自 `project.yml`/工程配置，均为 iOS；[原始输出](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/xcode-targets.log)。

**保留的失败与后续区分**

| 次序 | 命令/条件 | 原始结果 | 后续判断 |
| --- | --- | --- | --- |
| 1 | main 原样 `sh tests/translation-layer/run.sh`，本机 arm64 | planner 通过；scanner 链接缺 `_tl_find_stikdebug_prewarmed` | `husk-tl-probe.c` 的 arm64 分支依赖 loader；测试链接集未提供它 |
| 2 | topic 原样测试，fixtures 用 NDK clang 17 | planner 通过；scanner 的 `TLS seen` 断言失败 | 切换上游 clang 后 TLS 断言通过，属于 fixture 工具链假设 |
| 3 | topic/main scanner，fixtures 用上游 clang 23，readelf 23 | RELR 计数比较为 `(43, 10)` | readelf 23 改变输出格式，33 个 RELR 项不再命中测试正则 |
| 4 | fixtures 仍用上游 clang 23，固定 readelf/objdump/lld 17 | topic 41/41；main 经宿主 adapter 后 41/41 | ASan/UBSan scanner 检查通过；没有修改 parser 或断言 |
| 5 | `va-test.c + husk-tl-va.c` 独立链接 | 缺 `_tl_log_line` | 加入宿主日志函数后 6 项通过；这是显式适配后的结果 |

main scanner adapter 只表示本机测试进程没有 StikDebug 预热区；它没有伪造 JIT 成功，也没有运行 `husk_tl_run_checks(true)`：

```c
#include "husk-tl-internal.h"
#include <stdarg.h>
#include <stdio.h>

tl_dual_mapping *tl_find_stikdebug_prewarmed(void) { return NULL; }
void tl_log_line(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}
```

本地实际文件：[host-adapter.c](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/host-adapter.c)。编译 scanner 的命令：

```sh
cd /Users/tanmy/Projects/Husk-macOS
/usr/bin/clang -std=gnu11 -O2 -g -Wall -Wextra -Werror \
  -fsanitize=address,undefined -Isrc/translation-layer \
  tests/translation-layer/scan_cli.c \
  src/translation-layer/husk-tl-json.c src/translation-layer/husk-tl-zip.c \
  src/translation-layer/husk-tl-elf.c src/translation-layer/husk-tl-scan.c \
  src/translation-layer/husk-tl-probe.c \
  build/audit-2026-10-07/host-adapter.c -lz -lpthread \
  -o build/audit-2026-10-07/scanner-adapted
PATH="$PWD/build/audit-2026-10-07/fixture-tools:$PATH" \
  python3 tests/translation-layer/test_scan.py \
  build/audit-2026-10-07/main-pinned-fixtures \
  "$PWD/build/audit-2026-10-07/scanner-adapted"
```

本地 `fixture-tools` 是指向上表指定版本的 4 个工具的 symlink 目录，未改系统 PATH 或安装工具。跨机器复现应先提供这些版本；不要把 PATH 差异混入 parser 正确性结论。

日志：[main 原始失败](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/fork-main-host-tests.log)、[topic 首次结果](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/topic-host-tests.log)、[LLVM 23 输出差异](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/topic-llvm-tests.log)、[main 最终 scanner](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/main-adapted-scanner-final.log)、[topic 最终 scanner](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/topic-scanner-final.log)。

Linux qemu-user 设备探测没有在本轮执行；扫描器的 host 测试通过不代表手机寄存器/JIT 探测通过。

**其他既有测试**

```sh
cd /Users/tanmy/Projects/Husk-macOS
/usr/bin/clang -O2 -Wall -Wextra -Isrc/translation-layer \
  tools/prefs-test.c src/translation-layer/husk-tl-prefs.c \
  -o build/audit-2026-10-07/prefs
build/audit-2026-10-07/prefs
/usr/bin/clang -O2 -Wall -Wextra -Isrc/translation-layer \
  tools/blit-test.c src/translation-layer/husk-tl-blit.c -framework CoreGraphics \
  -o build/audit-2026-10-07/blit
build/audit-2026-10-07/blit
/usr/bin/clang -O2 -Isrc/translation-layer -Isrc/translation-layer-next \
  tools/va-test.c src/translation-layer-next/husk-tl-va.c \
  build/audit-2026-10-07/host-adapter.c -o build/audit-2026-10-07/va-adapted
build/audit-2026-10-07/va-adapted
/usr/bin/clang -O2 -Isrc/translation-layer \
  tools/pacer-test.c src/translation-layer/husk-tl-dex.c -Wl,-dead_strip \
  -o build/audit-2026-10-07/pacer
build/audit-2026-10-07/pacer
```

四个运行均 exit 0。pacer 仅链接所需函数，`-dead_strip` 不构成整个 DEX runtime 的链接验证。日志：[prefs](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/prefs.log)、[blit](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/blit.log)、[va](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/va-adapted.log)、[pacer](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/pacer.log)。

**JIT 发行配置实验**

使用当前未修改的 `husk-tl-xmem.c`，测试程序只分配 64 MiB 区域、写入 `mov w0, #42; ret`、刷新 icache 并执行。没有加载第三方 APK，也没有启动 GUI。测试核心：

```c
char error[256] = {0};
uint8_t *rx = NULL, *rw = NULL;
if (!tl_xmem_open(64u << 20, error, sizeof(error))) return 1;
if (!tl_xmem_alloc(16, &rx, &rw)) return 2;
const uint32_t code[2] = {0x52800540, 0xd65f03c0};
memcpy(rw, code, sizeof(code));
tl_xmem_flush(rx, sizeof(code));
int value = ((int (*)(void))rx)();
```

完整测试程序与命令分别保存在 [xmem-smoke.c](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/xmem-smoke.c)、[xmem-smoke.log](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/xmem-smoke.log)。先编译正常开发态二进制，再复制一份以 ad-hoc 身份签名，增加 `--options runtime` 和仅含 `com.apple.security.cs.allow-jit=true` 的 entitlement。

| 构建/运行配置 | 结果 |
| --- | --- |
| 普通开发态 | `returned=42 region_MiB=64`，exit 0 |
| ad-hoc Hardened Runtime + allow-jit | exit -9 / SIGKILL，无程序输出 |
| 后者 `codesign --verify --strict --verbose=2` | valid on disk；satisfies its Designated Requirement |
| 系统诊断 | `EXC_BAD_ACCESS`；`SIGKILL (Code Signature Invalid)`；`termination.namespace=CODESIGNING`；`code=2`；`indicator=Invalid Page` |

系统诊断指出故障页处于测试创建的 64 MiB RX shared-memory 区，另有相邻 RW alias。仅抽取异常/终止字段，见 [xmem-crash-excerpt.json](/Users/tanmy/Projects/Husk-macOS/build/audit-2026-10-07/xmem-crash-excerpt.json)。该证据说明**当前默认 allocator 在这个 Hardened Runtime 配置下不可用**，不证明所有 macOS JIT 方案都不可行，也不替代 Developer ID、公证与其他系统版本验证。
