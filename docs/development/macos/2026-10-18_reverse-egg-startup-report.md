# Egg, Inc. 启动崩溃调查

2026-10-18，基于当前安装的 APK、已有真实会话日志和本仓库源码。此次只调查，没有启动游戏、修改 APK/存档、替换候选或修改运行时代码。

Egg 在 `libegginc.so` 的第一个原生构造函数中，通过未填好的 PLT/GOT 槽跳到未映射地址，触发 SIGSEGV。当前 NativeActivity 驱动省略 APK 的 Java Application 启动；进一步静态分析确认，游戏的前置 `ExecuteProgram` 需要由 PairIP `JNI_OnLoad` 建立的 JavaVM 和就绪状态。这个启动缺口是下一步修复重点。**无效跳转已经由真实日志确认；补齐启动流程能否使初始化成功，仍需受控验证，不能据此声称游戏已修复。**

## 样本与现场

| 项目 | 证据 |
| --- | --- |
| 游戏 | Egg, Inc.，`com.auxbrain.egginc`，versionCode `111359` |
| 包结构 | `base.apk` + 三个 split，`arm64-v8a`，7 个 DEX |
| Application | `com.pairip.vmencryption.KeyImportApplication` |
| 启动 Activity | `com.auxbrain.egginc.EggIncActivity`，继承 `android.app.NativeActivity` |
| 原生入口库 | manifest 的 `android.app.lib_name=egginc` |
| 游戏库 SHA-256 | `ae2713d5a13a632f6cf242b5b47dbc8b3854eaa21493a77119033a1e0269c83b` |
| PairIP 库 SHA-256 | `d0e8dac6f6223e94e267600eb8ffa7fc06bca79910ed82116cc857d0ce5ec865` |
| 真实失败会话 | `3468A3D8-88FF-43B6-9B12-4CDF84823C8D`，北京时间 2026-10-18 01:33:10 |
| 结果 | 启动约 0.625 秒后退出 139；`presentedFrames=0`、`audioFrames=0`、`storageClosed=false` |

四个 APK 的 SHA-256 均与资料库导入摘要一致，也与之前调查的样本一致。这能排除“本地文件后来变化”的解释，不等于独立验证了发布者原包。

此次开工时只有空闲 Husk 主程序，没有 Husk 的 NativeRunner/VMRunner 游戏会话。没有为重新取得相同崩溃而启动样本。

## 已确认的崩溃机制

现有真实日志记录：

```text
signal=0x000000000000000b
fault=0x0000000001625d90
pc=0x0000000001625d90
lr=0x00000070416257a8
x16=0x00000070017676b8
x17=0x0000000001625d90
```

对应原始 ELF 的控制流为：

1. `.init_array[0]` 的 RELATIVE 重定位指向 RVA `0x1621794`。
2. 该构造函数在 `0x16217a4` 执行 `bl 0x16413c0`。
3. PLT 项 `0x16413c0` 从 GOT 槽 `0x17636b8` 读取目标，然后执行 `br x17`。
4. 槽里仍是文件中的原始数值 `0x1625d90`。实际运行寄存器与该值一致，处理器跳到这个未映射的低地址，触发 SIGSEGV。

故障早于 `ANativeActivity_onCreate` 和首帧。此次证据定位于原生初始化，不支持把窗口分辨率、触摸、图形着色器或 Google Play 登录当作这次退出的直接原因。

重新读取当前 APK 的全部 **136,362 条**标准 RELA/JMPREL 记录，故障槽及其后两个槽 `0x17636c0`、`0x17636c8` 均没有对应重定位。ELF 也未声明 APS2 或 RELR 表。因而不能把问题简化为加载器漏执行了一条普通重定位，更不能仅给这个值加上装载基址就认定修复。

## 前置初始化的具体缺口

`libegginc.so` 的 `DT_INIT=0x17a0000`，在构造函数数组之前经 `0x1798000` 调用导入的 `ExecuteProgram`。该槽有正常的 JUMP_SLOT 重定位，符号由依赖库 `libpairipcore.so` 提供。

独立用 Xcode 的 `llvm-objdump` 核对原始 PairIP ELF 后，发现以下必要条件：

| 地址／入口 | 原始代码的行为 |
| --- | --- |
| `ExecuteProgram`，RVA `0x6bb94` | 获取线程 JNI 环境；环境为空则返回；随后检查初始化状态 |
| JNI 环境辅助函数 `0x6c3c8` | 读取全局 JavaVM `0x9cf80`，为空时返回 NULL；还检查已记录 PID，然后通过 JavaVM 的函数表获取环境 |
| `JNI_OnLoad`，RVA `0x8c3f4` | 在 `0x8c470` 保存传入的 JavaVM 到 `0x9cf80`，随后记录 PID |
| 就绪字节 `0x9ce5a` | 位于零初始化的 BSS；`ExecuteProgram` 在 `0x6bc0c` 检查其是否为 1，否则返回 |
| `JNI_OnLoad` 的 `0x8d444` | 在完成相关 JNI 查找后将该就绪字节置为 1 |

这些是原始代码的静态事实。本轮没有执行保护程序，也没有在游戏进程中读取该时刻的 JavaVM/就绪字节，因此“本次具体走了哪一条提前返回分支”仍须运行证据确认。

Husk 当前路径存在可直接从源码确认的缺口：

- [NativeActivity 驱动](../../../src/translation-layer-next/husk-tl-nativeactivity.c) 的 `na_load()` 只用 `tl_dexidx_open()` 建立 DEX 索引，创建合成的 `android/app/NativeActivity`，再调用 `start_generic()` 加载 `egginc`。它没有运行 `KeyImportApplication`、应用的 ClassLoader 或 `EggIncActivity` 的 Java 初始化。
- [JNI 加载器](../../../src/translation-layer-next/husk-tl-jni-hle.c) 的 `load_native_library()` 先执行 `tl_ld_init()`，之后才对显式请求的库查找 `JNI_OnLoad`。ELF 依赖加载只运行构造函数，不会提前替每个依赖执行 Java 的 `System.loadLibrary()`。真实失败日志只有 PairIP 的“7 constructors”完成记录，没有任何 `JNI_OnLoad` 完成记录。
- APK 的 `com.pairip.VMRunner.<clinit>` 明确执行 `System.loadLibrary("pairipcore")`；`KeyImportApplication` 的 `attachBaseContext()` 安装自定义类加载器、处理原 Application；`EggIncActivity.<clinit>` 加载 `egginc`。这些 Java 路径没有被当前原生驱动执行。完整的应用实际类加载顺序还需跟踪，不能仅靠类名推断全部流程。

因此，**“PairIP 的 ELF 已加载、构造函数已运行”不代表其 Java/JNI 初始化已经完成**。这解释了为什么现有的 NativeActivity 支持和库加载成功仍不足以启动该 APK。

目前的最强解释是：启动路径绕过所需 Java/JNI 阶段，前置初始化不能完成，第一条原生构造函数便使用仍未绑定的跳转槽。还没有证明补齐这个阶段就能完成全部受保护代码的初始化、渲染和存档；也没有证据说明这是许可证校验拒绝或封禁。

## 修复与验证顺序

1. 先建立不依赖真实游戏的 Java Application → ClassLoader／provider → 显式依赖 `System.loadLibrary`／`JNI_OnLoad` → 游戏库构造函数 → NativeActivity 生命周期回归。用初始化次序断言报告失败，避免用故意崩溃的样本当测试。
2. 复用 [AppRunner.java](../../../src/java-framework/src/husk/AppRunner.java) 的受控 Java 启动流程，补真实 Java NativeActivity 与 NDK 回调桥接。当前 [framework NativeActivity](../../../src/java-framework/gen-src/android/app/NativeActivity.java) 仅有签名和空回调；单独将游戏的 runtime 改成 `java` 不会自动补上 `ANativeActivity_onCreate`、窗口、输入或销毁。
3. 保留原有固定画布、手柄/触摸、同线程暂停和 `storage-closed` 协议，确保 Java 和原生两方都确认关闭。不要对所有 DT_NEEDED 库无条件抢跑 `JNI_OnLoad`；这不是 Android 显式 Java 加载的等价实现。
4. 相关回归通过后，在隔离数据、静音、无窗口模式下只做一次真实样本验证，记录 `JNI_OnLoad`、`DT_INIT` 前后状态、目标槽变化和首帧。若初始化仍失败，沿新的失败证据继续；不改 APK、不跳过保护、不猜地址补丁。

## 证据与复核

源码基线为 `a0700fe8ff0e2f648850c577d4d16cdbcd16ed52`，候选为 3.0.0 / build 9。源码、磁盘候选和用户会话是不同的证据层；此次没有重新构建或重新运行候选。

本机资料库根目录为 `$HOME/Library/Application Support/org.husk.HuskMac`。真实失败日志位于其 `Logs/3468A3D8-88FF-43B6-9B12-4CDF84823C8D/`，包括 `stderr.log`、`events.jsonl`、`supervisor.json`。

静态证据复用 `build/logs/`：

- `current-egg-startup-audit.json`：DEX 调用摘要、ELF 入口和已有失败会话。
- `current-egg-diagnosis.json`：本次重新核对的 APK/ELF 哈希、完整构造函数表、三个缺失重定位的槽、BSS 就绪状态布局。
- `current-egg-jni-init.log`：独立 LLVM 反汇编的故障构造函数、PLT、ExecuteProgram、JNI_OnLoad 及 JNI 环境获取函数。

复核可直接读取以上 JSON/日志；重新做二进制检查时，从资料库只读打开四个 APK，依据 PT_LOAD 将上述 RVA 映射到文件偏移，枚举 PT_DYNAMIC 的 DT_RELA/DT_JMPREL 和 `.init_array`。只在临时目录解出两份 ELF 供反汇编，结束后删除临时文件，无须启动游戏或额外保存 APK 副本。

后续修复、提交和 PR 仅在 `ruabbit/Husk-macOS` 完成。上游仍可只读核对和同步；上游 PR #118 已于 2026-10-18 按用户要求关闭，不再重开或更新。
