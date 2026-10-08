# 原生 macOS 开发版

当前实现包含 P1–P3 的原生构建、资料库、自建 **Orbit Garden / Dusk** 游戏，以及 P4 的 **Minecraft 1.26.52.3 arm64** 样本路径。Minecraft 使用真实 Android ELF、bionic/JNI 适配、GameActivity、ANGLE/Metal 和 AudioQueue。0.2.0 起，其他识别为 Minecraft 的 arm64 单 APK 也可从 GUI 试运行；完整验证过的样本与实验版本分别标示。旧资料库记录按当前运行组件重新判定，保留原有设置和存档。

上游 main 已同步到 `75dc21f82c1fd748867ad4d4b5dfb0e981c2d468` 的源码，保留 macOS 的 JIT、生命周期、输入、音频与隔离实现。详情见 [GUI / 上游同步报告](2026-10-08-upstream-sync-report.md)。上游新增 Godot、Geode、Unity 与 iOS Store 的源码，不代表这些入口都已接入 macOS GUI。

本地验收、候选来源及待验收项见 [P1–P3 实施报告](2026-10-08-macos-p1-p3-report.md) 和 [P4 Minecraft 报告](2026-10-08-macos-p4-report.md)。完整 DEX/ART、Unity、Unreal、Cocos、SDL、通用 NativeActivity 和 Rockstar 游戏还没有各自的 macOS 样本验收。

## 构建与运行

需要 Apple Silicon Mac、完整 Xcode、CMake 3.28+、Ninja、Python 3，以及可交叉编译 Android arm64 ELF 的 LLVM clang / ld.lld。当前验证环境为 macOS 27、Xcode 27、Apple clang 21、LLVM clang 23.1.2 和 NDK 26.3 的 lld 17。

| 组件 | 最低系统声明 | 验收状态 |
| --- | --- | --- |
| 主 App、原生 NativeRunner 及图形库 | macOS 14.0 编译目标 | 本机 macOS 27 已测；14.0 和另一台 Mac 未测 |
| 可选 Android VMRunner | 由实际依赖闭包计算；当前为 macOS 27.0.0 | 实验功能；P5 游戏与持续音频未通过，默认不打包 |

两个组件有独立系统要求。主 App 读取 helper 的 `LSMinimumSystemVersion`；系统不足时显示原因并禁用 VM 启动，原生游戏入口仍可使用。最低系统与另一台 Mac 的实机验收属于 P6。

```sh
./scripts/build_macos.sh
```

当前候选统一构建到 `build/macos`，后续构建直接覆盖这个目录。交付入口为 `build/macos/Product/HuskMac.app`。Git 提交负责版本回退，`build/logs` 保存构建日志和验收结果；按日期、阶段生成的旧编译目录及源码导出副本已清理。`build/macos-deps` 和 `build/macos-vm-deps` 各保留一套固定依赖缓存。

首次构建下载并编译固定提交的 ANGLE 和 MoltenVK，后续校验缓存的提交记录及二进制 SHA-256。构建依赖在 `third_party/build/macos`；缓存产物在 `build/macos-deps`；不会改动 iOS 的构建目录。LLVM/NDK 只用于构建，产物不会链接 Homebrew 库。可通过 `ELF_CC`、`ELF_LD` 指定交叉工具，通过 `HUSK_BUILD_JOBS` 调整并行数。

打开 `build/macos/Product/HuskMac.app`。在资料库点击“添加示例游戏”，选择游戏并点击“开始游戏”。游戏使用独立 AppKit 窗口；关闭该窗口或使用“结束游戏”会先保存，再退出 Runner。主 App 退出也会等待同一保存协议。

Orbit Garden 的目标是收集八颗星星并避开横穿中线的红色障碍。方向键/WASD 移动；按住鼠标移动到目标；手柄左摇杆和方向键移动。P/Esc 暂停，R 或手柄 A 开始新一轮。得分在左上，已完成轮数在右上。

## 导入与资料

支持 APK 及包含最多四个 APK 的 XAPK/APKM/APKS。bundle 内 APK 可为 stored 或 deflate 条目，重复文件名、损坏目录、不支持的压缩方式、过大文件会明确报错。默认复制到受管目录后再扫描入库，不改变原文件。重复导入同一内容不会产生第二份记录。

资料位于 `~/Library/Application Support/org.husk.HuskMac`：

| 路径 | 用途 |
| --- | --- |
| `library.json` | 版本化索引、游戏设置及上次游玩时间 |
| `Games/<id>` | APK 副本、图标、扫描报告和导入元数据 |
| `Saves/<id>/checkpoint.json` | 与游戏文件分开的存档 |
| `Saves/<id>/data` | Minecraft 管理的世界数据库及设置；其 checkpoint 只记录正常关闭回执 |
| `Logs/<session UUID>` | Runner 状态事件及独立 stderr |
| `Staging`、`Trash` | 导入/移除事务暂存；不包含原始用户文件 |

“移除游戏”保留存档；同一包重新导入后恢复使用。“清除存档”是详情页中的独立操作，并有确认。运行中的游戏禁止删除和清除存档。损坏索引或存档保留原文件并报告错误。当前版本不自动覆盖同包的另一版本：先移除旧版本，再导入新版本。

普通 APK 可入库和扫描。原生启动范围是 ELF hash 与随附清单匹配的 Orbit fixture，以及扫描识别为 Minecraft 的 arm64 单 APK。P4 完整验证样本的 SHA-256 为 `83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95`；其他版本显示“可试运行”。资料库准备阶段与 Runner 都核对导入时的完整 APK hash，Runner 还独立复扫引擎和 ABI。无法识别或未接入的引擎、Minecraft 分包均保持明确的不可启动状态。游戏文件不随 Husk 分发；扫描成功并不代表完整兼容。

## Minecraft 样本

通过资料库的导入入口选择指定 APK，选中 Minecraft 后启动。世界和设置保存在受管资料目录中，原始 APK 保持不变。输入使用 WASD/方向键、鼠标按钮及相对移动、GameController 和原生文本输入桥接。运行窗口失焦、暂停或停止会释放按键、鼠标和手柄状态；`⌘P` 控制宿主暂停/继续，关闭窗口走 Android Activity 的正常销毁流程。游戏内 Esc 仍交给 Minecraft。

新导入游戏默认关闭“游戏窗口失去焦点时暂停”。已有资料库保留各游戏的选择，可在详情页切换，运行中的会话立即收到新策略；关闭选项不会自动恢复一个已经暂停的游戏，需按 `⌘P` 继续。

Minecraft 初始内容区域为 960×540 点，内部渲染保持 1280×720 像素。调整窗口时完整画面等比缩放、居中，非 16:9 窗口会出现对称黑边；鼠标位置按同一图层变换换算。当前没有随窗口动态改变游戏渲染分辨率。固定画布的父图层只改变位置和缩放，避免 ANGLE 按窗口或 Retina 尺寸重置游戏缓冲区。

本轮验收使用独立的 `build/macos-p4/library`，没有把约 1 GB 的样本或测试世界加入用户日常资料库。测试覆盖本地 Creative 世界。Xbox 登录、Realms、Marketplace、联机及第三方内容没有验收；实际系统输入法候选窗、前台鼠标捕获和实体手柄仍需前台/设备验证。具体通过项与边界以 P4 报告为准。

## 构建边界与签名

`CMakeLists.txt` 定义 `HuskMac`、`NativeRunner`、`SharedCore`、`SharedLibrary` 和 `NativeRuntime`。主界面复用 Foundation 元数据解析、ZIP/ELF 扫描、prefs/blit；执行内存和游戏 guest 只在 Runner 内。每次启动创建新进程，避免尝试在同一地址空间卸载引擎全局状态。

图形依赖锁定在 `dependencies/macos.lock.json`。ANGLE 和 MoltenVK 放在主 App 的 `Contents/Frameworks`，Runner 放在 `Contents/Helpers`；许可证及 MoltenVK 下游修订记录放在 `Contents/Resources/Notices`。

本地默认采用 ad-hoc Hardened Runtime：主 App **没有 entitlement**；Runner 的开发配置有 `allow-unsigned-executable-memory` 和 `disable-library-validation`。后一项仅用于无 Team ID 的本地 Runner 加载随附 ANGLE，已通过实际失败日志确认必要性。`NativeRunner.entitlements` 是同一 Team ID 正式签名的候选，只含执行内存项；打包器只有显式收到签名 identity 才选择它。没有自动选择用户证书，也没有执行 Developer ID 签名、公证或发布。

独立进程负责生命周期和崩溃隔离，不是文件系统或网络沙箱。Minecraft 路径只提供该样本需要的 Android 兼容接口，不等于完整 Android 环境。其余引擎仍需独立样本。macOS 的许可证边界、实际依赖与发行阻塞项见 [许可证说明](01-licensing.md#macos-distribution-status-2026-10-08)；当前开发产物没有通过 P6 发行门槛。

## 可选 Android VM 候选

P5 已实现独立 VMRunner，但完整验收仍未通过。TCG/HVF 的 Android 冷启动、基本交互、网络、Minecraft 安装、正常关机与磁盘重开已有本机证据；Minecraft 在 VM 内黑屏，持续音频也未通过。完整情况见 [P5 报告](2026-10-08-macos-p5-report.md)。

当前 VM 依赖要求 **macOS 27**。除上述原生工具链外，还需要 Git、Meson、pkg-config，以及 `dependencies/macos-vm.lock.json` 中固定版本的 GLib、pixman、slirp。打包器把动态依赖闭包嵌入 helper，并将所有 Mach-O 最低版本中的最大值写入 helper 的 Info.plist，运行时不依赖 Homebrew 安装。签名验证同时检查声明与闭包一致。默认构建不启用 VM。

```sh
python3 scripts/build_macos_vm.py
./scripts/build_macos.sh -DHUSK_BUILD_VM=ON
python3 scripts/prepare_macos_guest.py --destination "$PWD/build/macos-p5/my-android"
```

guest 准备脚本下载约 2 GB 的固定系统盘，并从校验过的 Husk 0.9.0 IPA 提取三份冷启动种子；不安装或运行 IPA。已有目标目录会被拒绝，避免覆盖数据。缓存可以用 `--cache` 指定。目标目录须保留 `guest.json`、两个磁盘、UEFI vars 和固件，路径不能包含逗号。

打开 P5 候选后，在 Android 菜单中选择该目录并启动。首次进入仍有 LineageOS 设置流程。资料库的“在 Android 中安装并运行”安装单个 APK；split bundle 尚不支持。VM 内的数据在 guest 的 `userdata.qcow2` 中，独立于翻译层的 `Saves`。默认 TCG + virgl；HVF 尚未切换为产品默认。软件图形未通过当前 guest 验收。

内存快照保存/恢复均明确禁用，关闭后再次启动是磁盘冷启动。关闭菜单和主 App 退出会等待 guest 关机；超时会报告非正常关闭，不能把 timeout 视为保存成功。`last-fingerprint.json` 记录每次运行的实际配置，`run.lock` 防止同一目录被两个 helper 同时打开。

显式后台验收通过正式 Swift 控制器，始终不显示窗口、保持静音，输出目录必须尚不存在：

```sh
build/macos/MacVMSession \
  build/macos/Product/HuskMac.app \
  build/macos-p5/my-android build/macos-p5/my-session --seconds 600 tcg
```

将 JSON 行追加到输出目录的 `control.jsonl` 可发送 `screenshot`、`pause`、`resume`、`shutdown`；`reopen` 验证同一个控制器关闭后重开。仅这个显式 automation 入口开放 guest `shell`。`responses.jsonl` 保存操作结果，`sessions/<UUID>` 保存每次 helper 的配置和原始事件，`result.json` 检查终态及原 PID 是否消失。正常 CTest 不启动 Android，也不下载或执行用户 APK。

## 验证

```sh
./scripts/test_macos.sh
```

默认只运行后台测试。主端到端测试使用无窗口模式，并用一个不显示、不激活的 AppKit 窗口检查真实 CAMetalLayer 路径。AudioQueue 验证将输出增益设为零，不会播放测试声音。失败隔离采用受控子进程 `_exit(74)`；不会主动 `abort()` 或生成系统崩溃提示。

测试包括资料库导入/去重/重启/设置/删除规则、损坏文件、伪造 fixture 拒绝、实际 ELF 游戏输入与目标完成、ANGLE 帧捕获、非零 PCM、暂停清键、存档恢复、换游戏和子进程失败后的恢复。`verify_macos_bundle.py` 核对签名、entitlement、macOS arm64、最低版本字段、rpath 和全部动态依赖位置。现有 P0 的入口仍为 `scripts/test_macos_p0.sh`；默认不显示窗口、不注入崩溃。

P4 增加 AAudio 探测流/回调 STOP 后重启、Android binary128 数学 ABI、JNI UTF-8 文本状态及原生组合文本/UTF-16/字素删除测试。0.2.0 增加旧资料库能力升级、设置/存档保留、实验版本完整性及 Runner 独立入口检查。审查修复新增 VM 控制器进程回归：终止后延迟事件、两条输出的 EOF 顺序、错误保留、读管道超时及同对象重开，并覆盖系统要求判断。TL-only 为 12 组，启用 VM 后为 13 组。VM 控制器回归只启动有限时长的 CLI fixture；默认测试不启动 Android 或 Minecraft。

窗口回归 `macos-render-surface` 使用真实 ANGLE/CAMetalLayer，在隐藏窗口中检查 1280×720 和 640×400 两种画布、初始尺寸、宽/高窗口及模拟 1×/2× backing scale，共 24 个组合。检查项包含实际 EGL 缓冲区尺寸、四角像素、图层居中和鼠标映射。资料库集成回归另行覆盖默认失焦继续运行、运行中更改策略、显式暂停与清除输入。隐藏窗口测试不替代可见窗口、全屏和多显示器验收。

较长验证是显式命令，均不创建可见窗口：

```sh
build/macos/MacCycles build/macos/Product/HuskMac.app build/macos/Cycles 20
build/macos/MacSoak build/macos/Product/HuskMac.app build/macos/Soak 1800
```

每次验收应使用新的输出目录。Soak 持续渲染并记录帧数和 RSS，结束时等待保存确认和 OS 子进程回收。离屏 ANGLE pbuffer 的 swap 不提交 Metal 命令，宿主必须显式完成每帧 GPU 工作；否则内存持续增长。此问题已由持续运行测试暴露并修复。

Minecraft 是显式选择的独立验收入口。先把 `MINECRAFT_APK` 环境变量设为你自己的完整 arm64 APK 路径，输出目录须为新目录：

```sh
build/macos/MacMinecraftSession \
  build/macos/Product/HuskMac.app \
  "$MINECRAFT_APK" \
  build/macos-p4/library build/macos-p4/new-session --seconds 1800
```

该命令静音并离屏运行，通过 `control.jsonl` 接收输入。用 `python3 tests/macos/control_game.py build/macos-p4/new-session capture main.png` 获取游戏自己渲染的画面，按画面确认菜单和世界状态。进入世界后可执行 `python3 tests/macos/lifecycle_game.py build/macos-p4/new-session --cycles 20 --seconds 0` 检查生命周期。Minecraft 在宿主恢复后保留自己的暂停菜单；点击 **Resume Game** 并再次确认世界画面后，另行采样 `--cycles 0 --seconds 600`，避免把菜单停留计为世界运行。该脚本会覆盖同目录的 `lifecycle-result.json`，分段验证前应保留已有结果。

结束时发送 `python3 tests/macos/control_game.py build/macos-p4/new-session stop`，检查 `result.json` 的正常退出、存储关闭回执及 PID 回收。`--hidden-window` 仅建立不显示、不激活的 AppKit/CAMetalLayer 窗口，用来单独检查实际窗口 surface；仍不捕获系统鼠标。此模式关闭会强制离屏的帧截图诊断，使用事件及 EGL surface 日志检查，不能用 capture 获取 PNG。

**CI 配置未验证，远程运行尚未发生。** [工作流](../.github/workflows/macos.yml) 使用稳定的 GitHub 托管 Apple Silicon `macos-26`，定义构建、核心测试、无图形 VM 控制器回归和签名自检。旧 `xcode-27` 在 [GitHub 官方 runner 列表](https://github.com/actions/runner-images#available-images) 中确实是公开 arm64 预览标签；本次改用稳定镜像以减少预览环境变动。

Metal/AudioQueue/完整运行及 30 分钟测试单列在显式选择的物理 `husk-metal` runner。该自托管标签需要仓库维护者注册，本轮未验证其存在。`.github/actionlint.yaml` 仅声明 lint 可接受这个自定义标签，不负责创建 runner。本地 lint、构建通过不能替代远程 CI；当前修改仅提交在本地。

实施工作笔记保存在 [docs/development/macos](development/macos/task_plan.md)，历史结果快照保留当时的源码、机器路径和提交状态。产品说明以本指南为准；本轮逐项处理结果见 [审查修复报告](2026-10-08-macos-review-report.md)。

实体手柄热插拔、可听音质、音频设备切换、全屏/多显示器和完整前台交互仍需实际设备验收。一次主窗口导入操作有本地记录，但随后原生 UI 自动化连接中断；离屏 SwiftUI 材质导出也不作为视觉通过证据。
