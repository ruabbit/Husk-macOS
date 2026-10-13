# 上游功能与 macOS 接入现况

核对日期：2026-10-13（Asia/Shanghai）。上游 `f0bd526..8e79a47` 共 3 个提交、10 个路径，新增社区兼容性列表、报告及服务回退。本地 main 快进后真实合入 macOS，无文本冲突。运行时分发、共享 PlayAPI 与图形依赖构建无上游增量；同时补了 Java 手柄接线。

**本轮尚未交付当前候选或推送。** 38 项不依赖新包的 CTest 已通过，主 App 与 Runner 可编译；CUA 选择空闲 Husk 及 reset 重连仍报 `native pipe closed`，旧 Product PID 98251 仍在运行。已请求用户正常退出，未替换活动候选。完整默认测试中的 4 项包相关检查、最终 bundle 验证和单次重开仍待完成。昨日 `fcce001` 的 GitHub CI 已确认成功，不能替代本轮验证。

## 当前接入范围

| 功能 | 上游入口 | macOS 当前状态 | 开放缺口 |
| --- | --- | --- | --- |
| Java / Dalvik、Unity 6 | `TLReport.nativeEngine`、`husk.AppRunner`、共享 DVM | 10/12 已交付受控 Java 资源、独立 profile、32 分包、固定画布、触摸/键盘、IME、暂停与销毁。10/13 源码补 AppRunner 同线程手柄、设备枚举/热插拔、按钮/轴与焦点分发 | 新手柄真实 DEX 回归通过，打包会话尚待本轮更新；真实应用玩法/保存、前台 IME 与实体手柄仍待验收 |
| Cocos（无 FMOD）、SDL（无 DXVK）、Python、Flutter、libGDX、Java、React Native、.NET / Xamarin | 上游本轮将 SDL/Python/Flutter 也交给 Java | 资料库与 Runner 按上游相同条件分发至上述 Java 路径；旧导入从现有扫描报告补全元数据，旧 Unity 额外只读复扫一次识别 Unity 6 | 共同运行链路已接通，各引擎的插件、图形和真实应用兼容仍需各自验证，不能凭分类或通用 fixture 宣称可玩 |
| Unity 旧版 | `husk-tl-unity.c`、共享 loader/JNI/HLE | 保留独立 Runner、32 分包、键鼠/手柄、同线程暂停/销毁确认；Unity 6 不再误走此路径 | Subway Surf 年龄界面和拖动来自 10/10 证据；Fruit Ninja 黑屏，Hole.io 旧路径首帧崩溃，未将旧结果当成本候选通过；旧 Unity IME 未接 |
| NativeActivity | `b7480b6`、PR #82 的 Application 单例修复 | 10/11 已接入，当前保留 manifest 库名/方向/alias、32 分包、触摸/键盘/手柄和确认销毁 | Egg 原生构造函数未重定位 PLT 跳转尚未修复；未到 onCreate 或首帧。PR #82 在 10/13 再查仍 open / 未合并 |
| WebView / Web 应用 | 共享 `husk-tl-dvm-web.m` 与 Java Web 桥 | Java WebView 绑定 AppKit 固定画布与命中容器，避免后台测试创建上游 harness 的可见窗口；补 macOS 透明合成 | 独立 Web profile 未接。WebKit 持久化关闭无确认协议：使用过 website data store 的会话明确拒绝正常 storage-closed；不能把移除视图当成保存成功 |
| Cocos + FMOD、SDL + DXVK、Godot、Unreal、Rockstar、GameMaker | 各自共享 native driver | 尚无 macOS profile；UE4 JNI 仅为 NativeActivity 的链接依赖 | 逐个补编译/分发、生命周期/输入、关闭回执和样本验证；不能只扩大 playable |
| Minecraft / GameActivity | `husk-tl-gameactivity.c` | 既有独立 Runner 与 AppKit 输入修复保留，默认回归通过 | 历史指定样本通过不等于本轮重测或其他版本通过 |
| Store / Play 登录 | 共享 PlayAPI、`ca70a4b` 的 auth 参数 | 本轮共享 Play 目录无增量，保留 macOS 商店/下载/Keychain/分包导入；登录前邮箱步骤保持删除 | 个人账号/passkey 仍被 Google 拒绝；需本人实际验证且会话可用才能关闭。已购交付、OBB/PAD、设备配置仍待补 |
| 社区兼容性 | `183c56c`、`268c202`、`8e79a47`，共享 `CompatibilityStore` | 源码已接资料库/Store 的查询、缓存、回退和手动报告；注明上游 iPhone 结果，Mac 报告带实际系统、组件和代码摘要；游戏后询问默认关闭 | 客户端回归和线上 GET/231 条解码通过；当前 Product 尚未替换，前台交互与公共 POST 未验收，没有发送任何报告 |
| 图形依赖 | 共享 EGL 和 GLES；固定 ANGLE/MoltenVK | 本轮没有固定图形依赖构建/补丁增量；共享 EGL/GLES 更新已编入，保留 macOS 离屏提交与节流 | 更早的 iOS SPIRV-Cross 补丁仍未在 macOS 固定 MoltenVK 中验收 |

检查入口：`CMakeLists.txt` 的 NativeRuntime / JavaRuntimeResources / PackageMac，`Models.swift`、`LibraryRepository.swift`、`NativeLaunch.swift`、`SessionController.swift`、`NativeRunner/main.m` 与 `MacJavaRuntime.m`；对照上游 `TLReport.nativeEngine`、`TLUnityView.swift` 和 `src/app/project.yml`。本轮 iOS 工程新增无条件复制 Java 资源，macOS 的 PackageMac 本来逐次打包，并增加内容和来源校验。

## 2026-10-13 本地适配证据

主 App 复用上游 CompatibilityStore，UIKit / AppKit 条件编译。缓存失败保留旧记录；GET 遇 5xx 或连接失败回退到上游 Render 地址，4xx 保留服务器答复。报告 POST 不跨站自动重试，避免丢失响应后重复发布。图标缩为 128×128 PNG；报告类型可选择。macOS 仍使用上游 `ios` 字段名，但值与可见 notes 明确写 macOS，不伪装成 iPhone。开发候选以主 App、Runner 和 Java 资源内容摘要区分 build；只有用户点击发送才请求 POST。没有用社区状态限制启动，也没有恢复“试运行/已验证版本”分类。

手柄复用 `tl_pad_sink`，完整事件加入原输入队列，在 AppRunner 所属线程构造 KeyEvent / joystick MotionEvent；保留 device/source/时间及 48 轴槽。InputDevice 枚举 41–44，InputManager 按注册 Handler 通知热插拔。MotionEvent 复制和 PointerCoords 保留轴值，ViewGroup 将摇杆交给焦点视图。macOS 按控制器分配独立槽；断连释放对应设备，失焦释放全部设备，暂停/恢复清状态；销毁前的释放事件不再被 stop 队列清空吞掉。输入队列溢出明确失败，不丢 key-up 后继续运行。

真实 DEX 通过两设备按钮、摇杆/帽轴/扳机、事件复制、元数据、热插拔、回调线程、暂停期间输入屏蔽和按住按钮时正常关闭；检查点持久化与关闭失败规则保留。新打包会话用例已补断连、失焦和暂停验证，尚未运行。社区模拟协议覆盖缓存、回退、4xx/损坏数据、提示开关、Mac 报告字段/图标和 POST 不重发；线上 GET 由同一 Swift 客户端成功解码 231 条。默认 42 项中不依赖包的 38 项通过，另 4 项待原位打包。证据见 `build/logs/current-upstream-*`。

## 2026-10-12 Java 已交付基线

固定资源来源为上游 lineage-v2 的原始 `vda-v12.qcow2`，SHA-256 `a8dbaecc8fdcd682991b078d6bbb7df6972e459208634fa8dcbad24f17208d6a`。只读提取 ART/libcore、ICU、Conscrypt、tzdata 和 framework-res；不使用用户 VM 磁盘。JDK 21 / 固定 D8 编译当前仓库 Java 源码，打包 194 个资源文件及原始 NOTICE，逐项记录 SHA-256。源码/工具/资源任一不匹配则拒绝打包。源镜像缓存复用，临时原始磁盘与 APEX 提取文件已删除。

`tl_javaapp_stop` 等待 Activity/Service 销毁和 SharedPreferences 写入完成，join AppMain / GL / 音频混合器，关闭新建 guest worker 的入口并等待 Java/原生线程真正退出（包括 pthread_exit 和 TLS 析构），再检查 SQLite。未提交事务、残留线程、失败写入、异常销毁或 WebKit 未确认关闭不会被写成保存成功。现有 SessionController 仍要求 storage-closed 与进程回收两者都完成。

最终默认 **CTest 40/40**；包校验通过 **17 个 Mach-O** 的架构、签名、权限与依赖闭包，以及 **194 个 Java 资源**。新增真实 Dalvik boot、UTF-8/UTF-16/资源 ID/损坏 GLES manifest、正常/异常/写失败/残留线程/未提交 SQLite 生命周期、原生线程 TLS 关闭、打包 Runner 端到端会话；扩充 AppKit 输入法、真实 NSEvent 和旧资料库升级测试。生产会话验证触摸/键盘回调、失焦继续、暂停/恢复、最终 preferences 持久化、唯一 storage-closed 和进程回收。所有样本为独立测试数据，静音且无可见游戏窗口。

该次包证据为 `build/macos/bundle-verification.json`（当前仍是 10/12 的包）。日志 `current-upstream-*` 随每日执行复用，需按本页日期区分。只使用 `build/macos/Product/HuskMac.app`，保留 `HUSK_BUILD_VM=ON`。候选与提交状态见 [progress.md](progress.md)。`actionlint` 通过；[GitHub CI 38193490652](https://github.com/ruabbit/Husk-macOS/actions/runs/38193490652) 已确认 success，hardware 可选任务跳过。Android 组件对应源码与发行许可仍是 P6 开放项。

## 下一轮优先事项

1. 先完成 10/13 交付：确认空闲 Husk 正常退出后，在唯一 build/macos 运行默认构建/42 项 CTest/verify_macos_bundle.py。尤其跑新增打包 Java 手柄会话；通过后正常推送 main 与 codex/macos-p0，读回 SHA，CUA 单次重开 Product。源码手柄接线已完成，不要重复写一套；实体控制器与前台交互继续单独验收。
2. WebKit：明确 website data store 与用户存档的生命周期，建立可确认的持久化关闭；完成画布透明合成、缩放后点击和取消/销毁验证。当前使用过数据存储的会话按关闭未完成处理。
3. 真实 Unity 6 / SDL / Flutter：共同 Java 路径已具备生产 fixture 证据，后续在独立数据上逐个验证首帧、交互、保存重开；将具体缺失 API 和失败堆栈写回本表。Hole.io 旧路径的崩溃不能冒充新路径结果。
4. Egg：继续核对 DT_INIT / PLT 初始化，而非重复启动。已知 `libegginc.so` 构造函数 RVA `0x1621794` 调用 PLT `0x16413c0`，槽 `0x17636b8` 仍为 `0x1625d90`，缺少该槽的 ELF 重定位；当前仅证明初始化跳转失败，不能把 PairIP 存在当作根因。本轮 loader 增量是依赖符号搜索和 x18 SP 改写，没有证明已修复 Egg 的故障。详见 [findings.md](findings.md)。
5. 其余 native profiles 按上表逐个推进；Play 登录保留用户实测失败结论，不重复声称已有 auth 参数补丁解决了 Google 拒绝。

每日同步必须在同一轮完成可确定的平台编译、分发、窗口/输入、生命周期和验证，并更新当前候选；较大的未完成项继续保持开放、保存具体证据与下一步。Git 祖先或旧测试通过都不能替代这些验收。
