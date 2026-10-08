# P4：Minecraft 的原生 macOS 运行闭环

日期：2026-10-08。分支 `codex/macos-p0`，基线 `82f33e858952f9fda3cf224e839f4385894e2d5b`，本地修改尚未提交或推送。

用户指定的 Minecraft APK 已接入正式 NativeRunner 和资料库会话管理。当前交付范围是这一精确样本的本地 Creative 世界：导入、启动、图形、输入、静音真实音频、Activity 暂停/恢复、正常保存及重开。P4 原计划的其他引擎仍需要各自的样本；P5 VM 与 P6 发行工作没有开始。

机器可读结果、候选哈希及采样见 [P4 结果快照](/Users/tanmy/Projects/Husk-macOS/docs/2026-10-08-macos-p4-results.json)。构建和测试命令见 [macOS 指南](/Users/tanmy/Projects/Husk-macOS/docs/macos.md)。

## 样本与候选

| 项目 | 值 |
| --- | --- |
| APK | `minecraft-1.26.52.3-arm64-v8a.apk`，1,048,027,974 字节 |
| 包/版本 | `com.mojang.minecraftpe` / `1.26.52.3` / versionCode `982605203` |
| 架构/目标 SDK | arm64-v8a / 36；APK 内有 10 个原生库 |
| APK SHA-256 | `83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95` |
| libminecraftpe.so SHA-256 | `53c4a86a8f3dbd7f0d48e440f8607d63c55100aeb364c80d19afefa8097e233a` |
| 验证机器 | Apple M1 Ultra，arm64，macOS 27.0 / 26A428 |
| 最终 Runner SHA-256 | `ff984b5d1dae1c772150ca1bc128ace76e24258743be0ff976fa20becc942ca9` |
| 构建来源 | 281 个实现文件哈希冻结；343 文件独立源码导出；最终 bundle 56 个普通文件清单 |
| 签名 | 本地 ad-hoc Hardened Runtime；主 App 无 entitlement；未做 Developer ID / 公证 |

APK 原文件最终复核 hash 一致。样本由用户提供，其官方/未修改来源未被本轮鉴定。APK、解包库和游戏数据保存在 ignored `build/macos-p4`，不随 Husk 打包。资料库准备阶段与 Runner 启动阶段都检查 APK 全文件 hash；另一份同名或同版本 APK 需要单独验收。

产物为 [HuskMac.app](/Users/tanmy/Projects/Husk-macOS/build/macos/Product/HuskMac.app)。本轮没有替换正在运行的旧主界面实例，也没有把测试数据写入日常 Application Support 资料库。

## 实现内容

- 正式 Runner 以运行配置分派 Orbit / Minecraft。Minecraft 链接 GameActivity、bionic、JNI、DEX 索引、GLES/ANGLE、FMOD/AAudio 及宿主 AudioQueue；游戏自己的 arm64 ELF 在独立子进程执行。
- GameActivity 通过异步队列接收暂停、恢复和销毁。关闭加载中的世界时等待 `onPause/onStop`、surface 销毁及 `terminateNativeCode`，再发送 `storage-closed`，由监督器确认终态和 OS 进程回收。世界数据由 Minecraft 自身数据库保存，host checkpoint 仅是关闭回执。
- 增加真实鼠标按钮、相对鼠标、键盘映射、虚拟手柄与清键路径。前台鼠标捕获由窗口焦点、应用激活和游戏请求共同控制；后台与隐藏窗口模式不会隐藏或锁定系统鼠标。
- 原生 `NSTextInputClient` 维护 UTF-16 选择与组合区；补齐 GameTextInput 的 UTF-8 ByteBuffer/CharBuffer 桥接、State 字符串引用生命周期，并将提交文本转给 Minecraft 的 textbox JNI。真实游戏字段已验证中文输入与保留原内容的追加编辑。
- AAudio 允许 FMOD 创建无 data callback 的输出配置探测流；播放仍由 callback 驱动。修复 callback STOP 后的状态发布与重启回收。无 callback 的阻塞播放仍明确返回不支持。
- 补齐 Android `frexpl/ldexpl` 的 binary128 ABI，避免把 Darwin 的不同 long double ABI 直接套用；覆盖精度、次正规数、边界和舍入。
- 离屏 EGL 每帧提交 GPU 工作并限速，避免 Metal 命令持续累积。主 UI 启动等待改为 95 秒，切换/退出等待改为 35 秒，与 Minecraft 监督器的 90/30 秒门槛配合。

输入自动化调用同一原生文本对象和游戏输入桥接。它证明该路径的游戏行为；没有代替实体鼠标、系统输入法候选窗或实体手柄的前台验收。

## 实际运行证据

| 验收项 | 结果与证据 |
| --- | --- |
| 导入及启动 | 指定 APK 经 SharedLibrary 导入，正式 SessionController 启动正式 Runner；GameActivity 与 ANGLE/Metal 初始化并进入主菜单 |
| 世界 | session01 创建 Creative 世界；最终 Runner 在 session11 重新进入并操作 |
| 键鼠/控制器 | 世界内 W 移动、相对鼠标转向、虚拟手柄移动/转向；鼠标点击菜单；模拟失焦使 heldKeys 从 1 变为 0 |
| Unicode 文本 | 真实字段显示 `Husk P4 世界`，再次打开后追加 ` OK` 得到 `Husk P4 世界 OK`；不是只做替换整串的测试 |
| Activity 生命周期 | session11 连续 20 次暂停/恢复；暂停后的帧/PCM 冻结，恢复后增长，所有 FMOD mixerResume 诊断返回 0 |
| 非零音频恢复 | 20 次循环后回到世界并移动，PCM 增加 240,640 帧、非零样本增加 472,882；AudioQueue 实际工作，输出增益为 0 |
| 世界持续运行 | 600.17 秒，35,920 帧，平均 59.85 fps；RSS 1,784.25–1,823.23 MiB；每 5 秒采样 |
| 正常关闭与保存 | session11 直接由宿主请求停止，收到 storage-closed → exited，PID 消失；保存后世界文件清单和 hash 已留存 |
| 存档重开 | session12 使用相同候选和资料目录，世界名称、位置与视角恢复；再次正常关闭 |
| 隐藏原生 surface | session14 建立真正的 CAMetalLayer / EGL window surface，EGL_SUCCESS；60 秒控制期后正常退出，共 7,177 次 swap 计数。非零 PCM 增长；窗口未显示。未作前台视觉验收 |
| 非正常退出与后续恢复 | 复制资料上的 session13 用 `_exit(74)` 受控退出，监督器按预期报告 failed 并回收 PID；session14 使用同一复制资料成功启动和正常关闭。9 个世界文件在失败前后和恢复后逐文件 hash 一致，主测试世界未改变 |
| 桌面影响 | 验收 status 中 windowVisible/cursorCaptured 均为 false；未主动激活窗口，未播放声音，未用 abort 或崩溃信号；未操作原有系统提示 |

20 次循环测试的是 Activity 生命周期。Minecraft 在宿主恢复后保留自己的游戏内暂停菜单，需要点击 **Resume Game** 才继续世界模拟。第一段带菜单停留的采样保留在 `session11/lifecycle-result.json`，没有用于上表世界时长。正式世界持续运行数据来自 `session11/world-soak/lifecycle-result.json`，开始前和结束后均检查游戏画面。

世界帧率来自 1280×720 离屏测试，并且宿主设置了 60 Hz 上限；它不是前台显示器、不同图形设置或其他硬件的性能承诺。RSS 仅描述此次观察窗口，不能据此宣称所有游戏内容均无泄漏。

文字追加后的实际游戏字段：

![Minecraft Unicode 编辑](/Users/tanmy/Projects/Husk-macOS/docs/macos-evidence/minecraft-p4-text.png)

世界持续运行结束与重开的画面分别保留为 [关闭前](/Users/tanmy/Projects/Husk-macOS/docs/macos-evidence/minecraft-p4-world-before-close.png) 和 [重开后](/Users/tanmy/Projects/Husk-macOS/docs/macos-evidence/minecraft-p4-world-restored.png)。

## 回归与复现

最终源码的 9/9 CTest 通过，包括 Android JNI 文本、macOS 文本输入、binary128、AAudio 生命周期、三个共享核心组、输入/Vulkan 宿主，以及含 31 项检查的资料库/会话集成组。P0 默认后台回归 30/30 通过。

独立源码目录 `build/macos-p4-clean-source` 在 `build/macos-p4-final-clean` 重建，依赖来自经过 SHA-256 校验的固定缓存。最初干净构建及主 UI 等待修正后的重建均为 9/9。最后只修正了 Minecraft 测试驱动，使隐藏窗口验收不启用会强制离屏的帧诊断；该驱动在两个构建目录均重新编译。Runner 字节始终保持上表 SHA-256。

最终 bundle 的签名、entitlement、macOS arm64、最低系统字段、rpath、全部动态依赖位置检查通过；281 实现文件与导出的源码一致，56 bundle 文件与冻结清单一致。构建目标为 macOS 14.0，但实际只在上述 macOS 27 机器验证。远程 CI 没有运行。

主要本地证据：

- `build/macos-p4/final-candidate/`：源码、bundle 清单和一致性核对。
- `build/macos-p4/final-ctest.log`、`final-clean-build-test.log`、`final-clean-ui-build-test.log`：回归与独立构建。
- `build/macos-p4/final-bundle-verification.json`、`p0-regression.log`：签名/依赖及 P0 回归。
- `build/macos-p4/session11/`：文本/输入画面、20 次循环、世界持续运行、正常关闭及世界文件快照。
- `build/macos-p4/session12/`：同一世界重新打开、再次正常关闭。
- `build/macos-p4/session13/`、`session14/` 和 `recovery-world-integrity.json`：受控退出、真实隐藏 surface、进程回收及世界文件不变。

仓库中的 results.json 保存整理后的结果及 hash，不收入 APK、本地账号/设备标识或完整 guest 网络日志。原始本地日志保留诊断失败与限制；早期候选的时长没有合并到最终 Runner 的结果中。

## P4 兼容矩阵及剩余边界

| 路径 | macOS 状态 | 本轮依据 |
| --- | --- | --- |
| Orbit fixture ABI | 已验证 | P3 证据及本轮 31 项回归 |
| GameActivity / Minecraft | 精确样本的本地世界路径已验证 | 本报告；其他版本/hash 没有自动放行 |
| DEX / 任意 Java 应用 | 未验证/未承诺支持 | DEX 索引与特定 JNI 模拟不等于完整 ART |
| Unity | 待独立样本和正式 Runner 验收 | 保留上游代码，未宣称 macOS 支持 |
| Cocos | 待独立样本和正式 Runner 验收 | 同上 |
| SDL / 通用 NativeActivity | 待独立样本和正式 Runner 验收 | 同上 |
| Unreal / Vulkan | 待实际游戏样本 | MoltenVK 设备枚举只证明宿主基础能力 |
| Rockstar | 待独立样本和正式 Runner 验收 | 保留上游代码，未宣称 macOS 支持 |
| QEMU / HVF | P5 未实施 | 本轮不使用 VM |

日志仍有未实现的 PlayGames、Xbox ECDSA、TTS 等 Java 方法，XAL 的空引用错误，遥测 SQLite 打开失败，以及可选 Choreographer/媒体解码动态符号缺失。它们没有阻断本轮本地世界流程，但也没有被伪装成成功。Xbox 登录、Realms、Marketplace、联机、语音朗读、媒体解码和第三方内容不在当前通过范围。没有登录账号；游戏会自行进行后台服务/遥测请求，本轮没有建立网络沙箱，也没有做断网可用性认证。

原生前台焦点/鼠标捕获、操作系统输入法候选窗口、实体手柄与热插拔、可听音质、音频设备切换、动态分辨率、全屏/多屏、系统休眠恢复、最低 macOS、另一台 Mac、Developer ID、公证及发行许可仍是单独验收项。当前渲染逻辑使用固定 1280×720 并随窗口等比缩放；不能将隐藏 surface 的提交记录写成这些场景已通过。
