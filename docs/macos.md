# 原生 macOS 开发版

当前候选为 **Husk 2.0.0 / build 8**，已合入上游 2.0（e02ac68）及 main 的后续更新（4c03823，iOS build 120）。首页、资料库、Store、内置帮助、圣诞装饰和窗口控制已适配 macOS。下载进度位于 Store 面板；应用详情支持下次启动全屏和导出启动快捷方式。

运行入口包含 Orbit、Minecraft、Unity、NativeActivity、Java / Unity 6，以及新增 Cocos + FMOD、Godot、GameMaker、SDL + DXVK、Unreal、Rockstar 和 Capacitor/Cordova。原生游戏在独立 NativeRunner 执行；Web 应用使用独立 WebRunner 复用上游桥接。手柄进入 Java AppRunner 的同线程输入队列，支持设备/轴/按钮和断连、失焦、暂停释放。旧导入按当前组件重新判定，无需重新下载，保留原有设置和存档。

这些入口具备构建和后台 fixture 证据，不能替代每款真实应用的兼容验收。Java 内嵌 WebView 的存储/关闭/清除及 Geode 配置已接入，真实插件和游戏仍需逐个验证。销毁时迟到的 Java 插件调用、个人 Play 登录、PS4 产品链路和 VM/P6 仍有明确开放项。当前候选测试、推送与前台状态见 [开发记录](development/macos/progress.md)，逐项接入和证据见 [上游现况](development/macos/upstream-parity.md)，来源见 [同步锁](../dependencies/upstream.lock.json)。

## 构建与运行

需要 Apple Silicon Mac、完整 Xcode、CMake 3.28+、Ninja、Python 3.11+，以及可交叉编译 Android arm64 ELF 的 LLVM clang / ld.lld。Java 资源准备另需 JDK 21、Android SDK build-tools 36.0.0、一个 Android SDK platform（回归 fixture 使用）、qemu-img 和 e2fsprogs/debugfs。当前验证环境为 macOS 27、Xcode 27、Apple clang 21、LLVM clang 23.1.2 和 NDK 26.3 的 lld 17。

| 组件 | 最低系统声明 | 验收状态 |
| --- | --- | --- |
| 主 App、原生 NativeRunner 及图形库 | macOS 14.0 编译目标 | 本机 macOS 27 已测；14.0 和另一台 Mac 未测 |
| 可选 Android VMRunner | 由实际依赖闭包计算；当前为 macOS 27.0.0 | 实验功能；P5 游戏与持续音频未通过，默认不打包 |

两个组件有独立系统要求。主 App 读取 helper 的 `LSMinimumSystemVersion`；系统不足时显示原因并禁用 VM 启动，原生游戏入口仍可使用。最低系统与另一台 Mac 的实机验收属于 P6。

```sh
./scripts/build_macos.sh
```

当前候选统一构建到 `build/macos`，后续构建直接覆盖这个目录。交付入口为 `build/macos/Product/HuskMac.app`。Git 提交负责版本回退，`build/logs` 保存构建日志和验收结果；按日期、阶段生成的旧编译目录及源码导出副本已清理。`build/macos-deps` 和 `build/macos-vm-deps` 各保留一套固定依赖缓存。

首次构建还会下载约 2 GB 的固定 Lineage 来源镜像，只读提取约 96 MB 的 Java 资源，临时 raw/system/APEX 文件自动清理。已有原始来源缓存或 `HUSK_JAVA_IMAGE` 可直接复用；不能指定日常 VM 磁盘。Java 缓存为 `build/macos/JavaRuntime`，只保留一套，资源或源码修改会重新校验/构建 DEX。`HUSK_JDK`、`HUSK_D8`、`ANDROID_SDK_ROOT` 可指定工具；D8 的 SHA-256 必须匹配来源锁。构建会拒绝替换正在运行的候选，请先正常退出空闲 Husk。

首次构建下载并编译固定提交的 ANGLE 和 MoltenVK，后续校验缓存的提交记录、二进制及上游 SPIRV-Cross 补丁 SHA-256；不匹配会拒绝旧缓存。构建依赖在 `third_party/build/macos`；缓存产物在 `build/macos-deps`；不会改动 iOS 的构建目录。LLVM/NDK 只用于构建，产物不会链接 Homebrew 库。可通过 `ELF_CC`、`ELF_LD` 指定交叉工具，通过 `HUSK_BUILD_JOBS` 调整并行数。

打开 `build/macos/Product/HuskMac.app`。在资料库点击“添加示例游戏”，选择游戏并点击“开始游戏”。游戏使用独立 AppKit 窗口；关闭该窗口或使用“结束游戏”会先保存，再退出 Runner。主 App 退出也会等待同一保存协议。

主 App 与 NativeRunner、WebRunner、VMRunner 共用上游默认 Husk 图标。构建时从 `src/app/Husk/Assets.xcassets/AppIcon.appiconset/Icon-Default.png` 生成含普通及 Retina 尺寸的 `Husk.icns`，打包到各自的 Resources；上游图标更新会自动触发重新生成。包检查同时核对图标声明、资源与签名。

Orbit Garden 的目标是收集八颗星星并避开横穿中线的红色障碍。方向键/WASD 移动；按住鼠标移动到目标；手柄左摇杆和方向键移动。P/Esc 暂停，R 或手柄 A 开始新一轮。得分在左上，已完成轮数在右上。

## 导入与资料

支持 APK 及包含最多 32 个 APK 的 XAPK/APKM/APKS，也接受商店交付的完整 APK 集合。分包按 manifest 识别 base、包名、版本、split 名称和依赖，不按下载文件名猜测。分包集合必须有一致且有效的 APK v2/v3 签名。bundle 内 APK 可为 stored 或 deflate 条目，重复文件名、损坏目录、不支持的压缩方式、过大文件会明确报错。默认复制到受管目录后再扫描入库，不改变原文件。重复导入同一内容不会产生第二份记录。

资料位于 `~/Library/Application Support/org.husk.HuskMac`：

| 路径 | 用途 |
| --- | --- |
| `library.json` | 版本化索引、游戏设置及上次游玩时间 |
| `Games/<id>` | APK 副本、图标、扫描报告和导入元数据 |
| `Saves/<id>/checkpoint.json` | 与游戏文件分开的存档 |
| `Saves/<id>/data` | 原生/Java 引擎管理的游戏数据和设置；其 checkpoint 记录正常关闭回执 |
| `Saves/<id>/web-store.json`、`web-assets` | 独立 Web 应用的 WebKit 数据库 UUID 和提取资源缓存；实际网页数据库由系统 WebKit 保管 |
| `Saves/<id>/java-web-store.json` | Java 内嵌 WebView 的独立 UUID；旧存档记录原包级关联，实际数据库仍归 WebKit 管理 |
| `Logs/<session UUID>` | Runner 状态事件及独立 stderr |
| `Staging`、`Trash` | 导入/移除事务暂存；不包含原始用户文件 |

“移除游戏”保留存档；同一包重新导入后恢复使用。“清除存档”是详情页中的独立操作，并有确认。运行中的游戏禁止删除和清除存档。损坏索引或存档保留原文件并报告错误。同包、同签名且版本号更高的更新会原子替换游戏文件，保留应用身份、设置、上次游玩时间和存档。降级、签名不一致、损坏下载以及运行中的应用更新会被拒绝。安装事务日志用于恢复在文件替换和索引提交之间中断的更新。旧版单 APK 导入仍可读取；不能验证旧签名的安装不会被自动覆盖。

普通 APK 可入库和扫描。原生启动范围是 ELF hash 与随附清单匹配的 Orbit fixture，以及上游已接入引擎的 arm64 APK 集合、Java profile 接受的 DEX / arm64 应用，以及包含完整资源的 Capacitor/Cordova Web 应用。P4 验收样本的 SHA-256 为 `83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95`，该值仅保留在测试与验收记录中，不参与产品分类。资料库准备阶段与 Runner 都核对导入时整个 APK 集合的 hash，Runner 还独立复扫引擎和 ABI。无法识别或未接入的引擎保持不可启动状态。Minecraft、Unity 和 NativeActivity 分包均传入同一原生加载器；游戏文件不随 Husk 分发，扫描成功并不代表完整兼容。

## Unity 运行

Unity 根据 launcher Activity 的 manifest 方向选择固定画布：横屏 1280×720、竖屏 720×1280；窗口缩放和输入换算共用同一图层变换。鼠标左键点击/拖动映射触摸，键盘按键和手柄交给引擎。`⌘P` 暂停/继续，`⌘Q` 或关闭窗口等待 nativeDone 与线程结束后退出。默认失焦继续，失焦释放输入。Unity 软键盘/IME 尚未接入。

2026-10-10 在真实 Play 安装的 Subway Surf 中确认竖屏年龄界面和滑块拖动，并通过暂停、恢复、正常关闭回执与进程回收。当时 Fruit Ninja 的 20 秒检查为黑屏，Hole.io 在首帧前失败；这是早期 Unity driver 的历史记录。后续 Hole.io 已转 Java / Unity 6 路径并在 build 5 验证真实拖动和黑色洞口，正常销毁/保存重开仍开放；最新逐项证据见 [上游现况](development/macos/upstream-parity.md)。游戏检查均静音、无窗口，使用独立测试数据，不代替完整玩法和实体输入设备验收。

需要复查现有资料库的 Unity APK 时，显式运行下列后台入口。它只读 APK，将游戏数据写到指定测试目录；`GAME_ID` 来自资料库索引，输出目录必须位于日常资料库之外。

```sh
build/macos/MacUnitySession build/macos/Product/HuskMac.app \
  "$HOME/Library/Application Support/org.husk.HuskMac" GAME_ID \
  build/macos/TestResults/UnityReal --seconds 20
```

## Java / Unity 6 运行

资料库和 Runner 复用上游引擎分发规则：Unity 6、无 FMOD 的 Cocos、无 DXVK 的 SDL、Python、Flutter、libGDX 和普通 Java 等进入独立 Java Runner。旧 Unity 导入会只读复扫，避免新版本继续走旧 JNI driver；列出资料库不重写索引、设置或存档。纯 Java 不要求带有 arm64 原生库；只带其他 CPU 原生库的 APK 仍不支持。

已接入固定画布、鼠标触摸、键盘和 IME 提交桥接，失焦默认继续；暂停等 Activity 回调完成，退出等 AppMain/GL/混合器及 guest workers 回收、preferences 写入和 SQLite 正常关闭，再发 storage-closed。未提交事务、异常销毁、残留线程及未确认的 WebKit 关闭会报告失败，保留现有数据。Java 手柄后台真实 DEX 回归已通过，实体手柄和前台 IME 尚需验收。内嵌 WebView 使用独立存档 UUID，等待真实文档卸载、网络/cookie 回调和框架 worker 退出，组合回执分别记录 Android 销毁与 WebKit 托管；未使用 WebKit 时显式标记 unused。WebKit 管理实际数据库，回执不是全局 fsync 承诺。独立 WebRunner 的持久化路径也已接入。

默认回归使用真实编译 DEX 的独立 Activity，经正式资料库/SessionController/打包 Runner 验证首帧、触摸/键盘/手柄回调、失焦、暂停/恢复、最终 preferences 和回收。新增 WebView 回归验证 localStorage、IndexedDB、最终 cookie、进程重开、同包多资料库隔离与清除存档，拒绝 Android 销毁失败、UUID 改变或销毁后的 Java 插件调用。旧存档沿用原包级 WebKit UUID；清除后启用独立 UUID，旧共享字节保留以保护其他资料库的关联。详见 [Web 存档协议](development/macos/upstream-parity.md#web-存档协议)。这些结果不是 Unity 6、Flutter 或其他真实应用的兼容结论。

## NativeActivity 运行

通用 NativeActivity 驱动复用上游实现，launcher 的 `android.app.lib_name` 决定入口库；未指定时搜索导出 `ANativeActivity_onCreate` 的库。manifest 元数据按真实 XML 层级选择，支持 Activity alias 和固定横竖画布。触摸、键盘和手柄通过 NDK 输入队列交给 guest；所有生命周期回调在同一活动线程执行。正常关闭等待窗口、输入队列和 Activity 的销毁回调返回，并 join 线程后才写 `storage-closed`；缺少销毁回调或启动异常按失败处理。软键盘/IME 和实体手柄尚未验收。

2026-10-11 的 Egg, Inc. 隔离后台探测失败：libegginc.so 在原生构造函数中调用未重定位的 PLT 槽，尚未进入 `ANativeActivity_onCreate` 或提交首帧。当前不能视为 Egg 已可玩。共享 JNI 已采用上游开放 [PR #82](https://github.com/Leviidev/Husk/pull/82) 的 Application 单例修复，该 PR 不能解决所有原生初始化问题。精确证据与后续工作见 [接入现况](development/macos/upstream-parity.md)。

## Google Play

资料库工具栏的“Google Play”打开原生 macOS 商店窗口，可使用访客账号或 Google 账号搜索、查看详情、下载和更新应用。下载完成后自动校验并加入资料库，无需手工打包分包。下载显示进度，可以取消；失败可重试，临时下载和失败导入不会保留半套安装。启动入口仍使用资料库现有的原生/Android 运行组件。

个人账号及 passkey 登录尚未通过：2026-10-10 用户实测进入 Google 的 `/v3/signin/rejected` 页面，提示“此浏览器或应用可能不安全”。Husk 同时误报为登录连接中断。Chrome 能打开、传输层测试通过，都不能证明 Google 接受该登录方案。

点击“登录 Google 账号”直接进入 Google 页面，Husk 不再额外索要邮箱；账号邮箱取自 Google 交换登录结果的响应。有 Chrome 时使用独立窗口、权限为 0700 的临时资料目录及私有调试管道，没有网络调试端口。完成、拒绝、取消、超时或退出 Husk 时关闭本次登录进程并清理临时目录。Husk 只取此临时登录中的 Google `oauth_token`，不读取日常浏览器资料。现在每轮轮询检查 Google 拒绝页面，拒绝后结束本次尝试并显示实际原因，不继续等待十分钟或提供原样重试。

无 Chrome 时保留临时 WebKit 登录页，同样处理 Google 拒绝。此页面不支持 Google passkey，也不能保证 Google 接受密码登录。[Google 官方说明](https://support.google.com/accounts/answer/7675428)可能阻止受软件控制的浏览器及嵌入式登录；[Apple 文档](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)要求普通 WKWebView 的 passkey 配置网站关联域名。因此当前 Chrome 路径和 WebKit 路径均不应标注为已支持个人账号登录。

后续登录方案还缺少可用的 Play 凭据回传机制。[桌面 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)使用注册的客户端、系统浏览器及应用回调；它不能直接替换现有的 Android `EmbeddedSetup → oauth_token → /auth` 流程。Husk 请求的 `googleplay` scope 不在[公开 scope 列表](https://developers.google.com/identity/protocols/oauth2/scopes)中，公开的 `androidpublisher` 面向开发者管理应用，不能据此实现用户下载其他发行者的应用。尚未验证受支持的替代路径，不要求用户反复尝试被拒绝的窗口。

Play 会话只存入 `org.husk.HuskMac.play` 钥匙串项，不存入 UserDefaults，不写入日志；退出登录清除该项。HTTP 401 会刷新令牌并重试一次，搜索和详情错误会显示。退出登录或较新的搜索发起后，旧请求不能覆盖新状态。

免费应用走免费授权流程；付费应用只请求该账号已经拥有的交付，不发起购买。访客不能下载付费应用。当前设备配置仍沿用上游 Pixel 8 / Android 15。后续设备设置应一起管理 fingerprint、build ID、型号、SDK、ABI 和显示配置，并在切换配置时重新注册设备及刷新会话；仅修改 fingerprint 不代表取得设备认证或 Play Integrity。

本地支持 base、ABI、语言、密度和随交付清单返回的安装时资源 APK，最多 32 个，总大小不超过 4 GB。OBB 扩展文件会明确拒绝而不会静默遗漏；按需 Play Asset Delivery、签名密钥轮换链、Google 服务运行环境与已购 Minecraft 交付尚未验收。APK 签名校验支持 v2/v3 的 RSA PKCS#1、RSA-PSS 和 ECDSA（SHA-256/512）；签名连续性不等于确认首次下载的发布者身份。

2026-10-10 已通过一次真实匿名 Play 搜索、Google 计算器详情、两 APK 下载、签名校验与临时资料库导入。测试没有登录用户账号，也没有安装或启动 Android guest。默认回归包含独立 OpenSSL 签名的 APK 集合、同签名升级/拒绝降级、签名和包名不一致、损坏下载、取消清理、过期刷新、旧请求竞态、安装中断恢复和 VM 安装事务。所有测试使用临时数据。

显式联网验证不属于默认 CTest，可按需运行：

```sh
build/macos/MacPlayTests --live build/macos/TestResults
```

## Minecraft 样本

通过资料库的导入入口选择指定 APK，选中 Minecraft 后启动。世界和设置保存在受管资料目录中，原始 APK 保持不变。输入使用 WASD/方向键、鼠标按钮及相对移动、GameController 和原生文本输入桥接。运行窗口失焦、暂停或停止会释放按键、鼠标和手柄状态；`⌘P` 控制宿主暂停/继续，关闭窗口走 Android Activity 的正常销毁流程。游戏内 Esc 仍交给 Minecraft。

新导入游戏默认关闭“游戏窗口失去焦点时暂停”。已有资料库保留各游戏的选择，可在详情页切换，运行中的会话立即收到新策略；关闭选项不会自动恢复一个已经暂停的游戏，需按 `⌘P` 继续。

Minecraft 初始内容区域为 960×540 点，内部渲染保持 1280×720 像素。调整窗口时完整画面等比缩放、居中，非 16:9 窗口会出现对称黑边；鼠标位置按同一图层变换换算。当前没有随窗口动态改变游戏渲染分辨率。固定画布的父图层只改变位置和缩放，避免 ANGLE 按窗口或 Retina 尺寸重置游戏缓冲区。

本轮验收使用独立的 `build/macos-p4/library`，没有把约 1 GB 的样本或测试世界加入用户日常资料库。测试覆盖本地 Creative 世界。Xbox 登录、Realms、Marketplace、联机及第三方内容没有验收；实际系统输入法候选窗、前台鼠标捕获和实体手柄仍需前台/设备验证。具体通过项与边界以 P4 报告为准。

## 构建边界与签名

`CMakeLists.txt` 定义 `HuskMac`、`NativeRunner`、`WebRunner`、`SharedCore`、`SharedLibrary` 和 `NativeRuntime`。主界面复用 Foundation 元数据解析、ZIP/ELF 扫描、prefs/blit；执行内存和游戏 guest 只在 Runner 内。每次启动创建新进程，避免尝试在同一地址空间卸载引擎全局状态。

图形依赖锁定在 `dependencies/macos.lock.json`。ANGLE 和 MoltenVK 放在主 App 的 `Contents/Frameworks`，Runner 放在 `Contents/Helpers`；许可证及 MoltenVK 下游修订记录放在 `Contents/Resources/Notices`。

本地默认采用 ad-hoc Hardened Runtime：主 App **没有 entitlement**；Runner 的开发配置有 `allow-unsigned-executable-memory` 和 `disable-library-validation`。后一项仅用于无 Team ID 的本地 Runner 加载随附 ANGLE，已通过实际失败日志确认必要性。`NativeRunner.entitlements` 是同一 Team ID 正式签名的候选，只含执行内存项；打包器只有显式收到签名 identity 才选择它。没有自动选择用户证书，也没有执行 Developer ID 签名、公证或发布。

独立进程负责生命周期和崩溃隔离，不是文件系统或网络沙箱。Minecraft 路径只提供该样本需要的 Android 兼容接口，不等于完整 Android 环境。其余引擎仍需独立样本。macOS 的许可证边界、实际依赖与发行阻塞项见 [许可证说明](01-licensing.md#macos-distribution-status-updated-2026-10-13)；当前开发产物没有通过 P6 发行门槛。

## 可选 Android VM 候选

P5 已实现独立 VMRunner，但完整验收仍未通过。TCG/HVF 的 Android 冷启动、基本交互、网络、Minecraft 安装、正常关机与磁盘重开已有本机证据；Minecraft 在 VM 内黑屏，持续音频也未通过。完整情况见 [P5 报告](2026-10-08-macos-p5-report.md)。

当前 VM 依赖要求 **macOS 27**。除上述原生工具链外，还需要 Git、Meson、pkg-config，以及 `dependencies/macos-vm.lock.json` 中固定版本的 GLib、pixman、slirp。打包器把动态依赖闭包嵌入 helper，并将所有 Mach-O 最低版本中的最大值写入 helper 的 Info.plist，运行时不依赖 Homebrew 安装。签名验证同时检查声明与闭包一致。默认构建不启用 VM。

```sh
python3 scripts/build_macos_vm.py
./scripts/build_macos.sh -DHUSK_BUILD_VM=ON
python3 scripts/prepare_macos_guest.py --destination "$PWD/build/macos-p5/my-android"
```

guest 准备脚本下载约 2 GB 的固定系统盘，并从校验过的 Husk 0.9.0 IPA 提取三份冷启动种子；不安装或运行 IPA。已有目标目录会被拒绝，避免覆盖数据。缓存可以用 `--cache` 指定。目标目录须保留 `guest.json`、两个磁盘、UEFI vars 和固件，路径不能包含逗号。

打开 P5 候选后，在 Android 菜单中选择该目录并启动。首次进入仍有 LineageOS 设置流程。资料库的“在 Android 中安装并运行”支持完整 APK 集合。宿主和 VMRunner 校验每个文件，guest 校验传输后的 hash；所有文件写入同一个 Package Manager 安装会话，全部成功后 commit，失败则 abandon 并清理临时文件。这条多分包协议已通过模拟 bridge 回归，尚未重新启动真实 Android guest 验收。VM 内的数据在 guest 的 `userdata.qcow2` 中，独立于翻译层的 `Saves`。默认 TCG + virgl；HVF 尚未切换为产品默认。软件图形未通过当前 guest 验收。

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

P4 增加 AAudio 探测流/回调 STOP 后重启、Android binary128 数学 ABI、JNI UTF-8 文本状态及原生组合文本/UTF-16/字素删除测试。0.2.0 增加旧资料库能力升级、设置/存档保留、实验版本完整性及 Runner 独立入口检查。审查修复新增 VM 控制器进程回归：终止后延迟事件、两条输出的 EOF 顺序、错误保留、读管道超时及同对象重开，并覆盖系统要求判断。TL-only 为 13 组，启用 VM 后为 14 组。VM 控制器回归只启动有限时长的 CLI fixture；默认测试不启动 Android 或 Minecraft。

窗口回归 `macos-render-surface` 使用真实 ANGLE/CAMetalLayer，在隐藏窗口中检查 1280×720 和 640×400 两种画布、初始尺寸、宽/高窗口及模拟 1×/2× backing scale，共 24 个组合。检查项包含实际 EGL 缓冲区尺寸、四角像素、图层居中和鼠标映射。资料库集成回归另行覆盖默认失焦继续运行、运行中更改策略、显式暂停与清除输入。隐藏窗口测试不替代可见窗口、全屏和多显示器验收。

鼠标回归 `macos-native-mouse` 用原生 NSEvent 对象调用正式 GameView 响应方法，记录 Android 输入边界，检查点击、组合按钮、拖动、滚轮、失焦清键及黑边处理。窗口保持隐藏，不向系统投递鼠标事件。旧代码在普通点击中读取 `scrollingDeltaY` 会抛出 AppKit 异常；恢复该错误的反向检查已确认测试在首次点击失败。此前坐标换算与隐藏渲染检查没有覆盖这条路径。

2026-10-09 的可见窗口验证使用用户已启动的 Minecraft：实际鼠标打开 Settings、切换 Keyboard & Mouse，放大窗口后切换 Accessibility、返回主菜单，再恢复窗口尺寸。此项验证覆盖菜单点击和缩放后的命中；世界内视角捕获、实体手柄及多显示器仍不在本次结论内。现场日志和截图保存在 `build/logs/current-mouse`，详细边界见 [开发记录](development/macos/progress.md)。

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
