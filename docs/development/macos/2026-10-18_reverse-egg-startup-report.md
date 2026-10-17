# Egg, Inc. 启动崩溃调查

2026-10-18，基于当前安装的 APK、已有真实会话日志和本仓库源码。下文前半部分保留修改前的只读调查；当日获授权后的实现和真实复测见末尾“启动链路修复与复测”。

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


## 启动链路修复与复测

修复已进入 macOS 的 `nativeactivity` profile 和 3.0.0 / build 10。它先执行真实 Application、attachBaseContext、自定义 ClassLoader、providers 和 Java Activity，再由新的 framework NativeActivity 调用 NDK 入口。`Class.forName` 现在经过指定加载器；ContextImpl/LoadedApk 保留应用通过反射安装的加载器。UE4 的既有专用驱动保留。

NDK 回调在 Java 主线程执行，使用实际 Activity/JNIEnv/JavaVM；Surface、触摸、键盘、手柄、暂停、恢复、finish 和失败清理进入同一生命周期。正常关闭须同时满足 Java 销毁、原生 onDestroy、线程/SQLite 静止以及 WebKit 关闭回执，未完成原生销毁不能输出成功的 storage-closed。

实测暴露的另一处缺口是 APK 路径：宿主目录包含空格，而游戏从 `jar:file:...!/AndroidManifest.xml` 直接截取路径。原先的 `%20` 文件名打不开。Java 现在看到 `/data/app/<package>/base.apk` 与分包路径，I/O 仅将注册的精确路径映射回原文件；ClassLoader、DEX 和 JAR 资源使用同一映射。没有重命名、修改或复制用户 APK，也没有对普通文件路径做无条件 URL 解码。

验证分为三个层次：

| 层次 | 结果 |
| --- | --- |
| 真实 DEX + Android ELF 回归 | 显式 bootstrap JNI 先于依赖它的游戏库构造函数；自定义加载器/provider/Application/Activity 次序正确；触摸、键盘、手柄、同线程销毁、guest finish 及两种 onCreate 失败清理通过；缺 onDestroy 时拒绝成功回执 |
| 打包会话和默认回归 | 带 v3 签名的 base/split 集合通过实际资料库导入和 NativeRunner 启动；含空格的安装目录验证 APK 资源映射，暂停/恢复和最终 preferences 写入通过。默认 CTest **96/96，82.91 秒**；包检查 **18 个 arm64 Mach-O / 406 个 Java 资源** 通过 |
| 当前真实 Egg APK | 相关修复后用隔离数据、静音、无可见窗口复测。自定义 ClassLoader 成功安装；`libpairipcore.so JNI_OnLoad -> 0x10006`；Android 安装路径成功打开；随后因没有加密密钥而失败，未进入游戏 NativeActivity/原生渲染 |

真实样本的递进失败分别为：首次桥接缺 `ContextImpl.mPackageInfo`；补齐反射安装状态后缺可打开的 APK 资源路径；补齐 Android 安装路径后得到：

```text
Custom ClassLoader attached successfully.
jni: libpairipcore.so JNI_OnLoad -> 0x10006
java.lang.IllegalStateException: Failed to decrypt VM program.
caused by java/lang/IllegalStateException: Encryption key not found in keystore.
com.pairip.vmencryption.KeyImportException: Failed to bind to encryption key transfer service.
```

DEX 中 `KeyImportActiveClient.importEncryptionKey` 明确向 Play Store 包绑定 action `com.android.vending.securedatatransfer.IAntiTamperKeyTransferService`。本仓库 `husk.PlayStore.bind()` 仅提供 Age Signals，未实现这项服务，也没有完整 Play Store/密钥下发环境。当前 Store 下载功能、浏览器账号登录、游戏内 Binder 服务是不同链路；修好浏览器登录不能直接证明这项服务可用。

最终 probe 在 37.038 秒正常回收，日志为 `presented=1813 destroyed=1`，退出码 0。**这些帧属于 Java 错误页；它只证明这段 Java 生命周期关闭，不能作为游戏首帧、原生 onDestroy、存档重开或兼容性通过。** 正确启动路径没有再触发旧崩溃，但尚未到达原先故障的游戏库构造函数，因此其最终初始化结果仍未知。四个 APK 的复测前后摘要一致；用户存档和 Android 磁盘未改动。

本轮证据复用 `build/logs/`：

- `current-egg-ctest.log`、`current-egg-build.log`、`current-egg-bundle.json`：最终完整测试、构建与包校验。
- `current-egg-repair.log`、`current-egg-repair-result.json`：最终真实运行，JSON 明确 `gamePlayable=false`、`nativeActivityOnCreateReached=false`。
- `current-egg-missing-packageinfo.log`、`current-egg-resource-path.log`：相关修复前的两种不同失败；后者的 `current-egg-package-loader/frames/latest.png` 保存游戏自带 Google Play 错误页面。最终截图采样处于重绘中，不能当作完整画面验收。
- `current-egg-vmrunner-path.json`、`current-egg-key-service.json`：资源 URL 截取与实际绑定服务的 DEX 证据。

下一步是核对合法 Play 安装所需的密钥下发、Android KeyStore 持久化和 Binder 服务环境，或在有完整 Play 环境的隔离 Android VM 中验证同一版本；不得通过返回假密钥、跳过保护、修改 APK 或补猜测的 PLT 地址来关闭此问题。在相关环境尚未接通前，不重复运行这个样本。
