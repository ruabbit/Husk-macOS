# 上游功能与 macOS 接入现况

核对日期：2026-10-12（Asia/Shanghai）。fetch 后上游 `main` 从 `8a9dc1b` 前进到 `f0bd526cdf15356cac1d272cfebe6a5ea11ef6fa`，共 70 个提交、139 个路径。fork main 快进后真实合入 macOS，无文本冲突；保留已有 AppKit 窗口、固定画布、鼠标处理、默认失焦继续、独立 Runner 与存储关闭约束。源码历史、平台接入、具体应用兼容分别验收。

## 当前接入范围

| 功能 | 上游入口 | macOS 当前状态 | 开放缺口 |
| --- | --- | --- | --- |
| Java / Dalvik、Unity 6 | `TLReport.nativeEngine`、`husk.AppRunner`、共享 DVM | 已打包固定 boot class path、framework-res 与源码构建 DEX；新增独立 `--runtime java`，32 分包、manifest 方向、固定画布、触摸/键盘、IME 桥接、暂停和销毁回执 | 本轮真实 DEX fixture 的生产会话已通过；Unity 6 等真实应用的首帧/玩法/保存尚未验收；Java 手柄事件桥与前台 IME 待补 |
| Cocos（无 FMOD）、SDL（无 DXVK）、Python、Flutter、libGDX、Java、React Native、.NET / Xamarin | 上游本轮将 SDL/Python/Flutter 也交给 Java | 资料库与 Runner 按上游相同条件分发至上述 Java 路径；旧导入从现有扫描报告补全元数据，旧 Unity 额外只读复扫一次识别 Unity 6 | 共同运行链路已接通，各引擎的插件、图形和真实应用兼容仍需各自验证，不能凭分类或通用 fixture 宣称可玩 |
| Unity 旧版 | `husk-tl-unity.c`、共享 loader/JNI/HLE | 保留独立 Runner、32 分包、键鼠/手柄、同线程暂停/销毁确认；Unity 6 不再误走此路径 | Subway Surf 年龄界面和拖动来自 10/10 证据；Fruit Ninja 黑屏，Hole.io 旧路径首帧崩溃，未将旧结果当成本候选通过；旧 Unity IME 未接 |
| NativeActivity | `b7480b6`、PR #82 的 Application 单例修复 | 10/11 已接入，当前保留 manifest 库名/方向/alias、32 分包、触摸/键盘/手柄和确认销毁 | Egg 原生构造函数未重定位 PLT 跳转尚未修复；未到 onCreate 或首帧。PR #82 在 10/12 再查仍 open / 未合并 |
| WebView / Web 应用 | 共享 `husk-tl-dvm-web.m` 与 Java Web 桥 | Java WebView 绑定 AppKit 固定画布与命中容器，避免后台测试创建上游 harness 的可见窗口；补 macOS 透明合成 | 独立 Web profile 未接。WebKit 持久化关闭无确认协议：使用过 website data store 的会话明确拒绝正常 storage-closed；不能把移除视图当成保存成功 |
| Cocos + FMOD、SDL + DXVK、Godot、Unreal、Rockstar、GameMaker | 各自共享 native driver | 尚无 macOS profile；UE4 JNI 仅为 NativeActivity 的链接依赖 | 逐个补编译/分发、生命周期/输入、关闭回执和样本验证；不能只扩大 playable |
| Minecraft / GameActivity | `husk-tl-gameactivity.c` | 既有独立 Runner 与 AppKit 输入修复保留，默认回归通过 | 历史指定样本通过不等于本轮重测或其他版本通过 |
| Store / Play 登录 | 共享 PlayAPI、`ca70a4b` 的 auth 参数 | 本轮共享 Play 目录无增量，保留 macOS 商店/下载/Keychain/分包导入；登录前邮箱步骤保持删除 | 个人账号/passkey 仍被 Google 拒绝；需本人实际验证且会话可用才能关闭。已购交付、OBB/PAD、设备配置仍待补 |
| 图形依赖 | 共享 EGL 和 GLES；固定 ANGLE/MoltenVK | 本轮没有固定图形依赖构建/补丁增量；共享 EGL/GLES 更新已编入，保留 macOS 离屏提交与节流 | 更早的 iOS SPIRV-Cross 补丁仍未在 macOS 固定 MoltenVK 中验收 |

检查入口：`CMakeLists.txt` 的 NativeRuntime / JavaRuntimeResources / PackageMac，`Models.swift`、`LibraryRepository.swift`、`NativeLaunch.swift`、`SessionController.swift`、`NativeRunner/main.m` 与 `MacJavaRuntime.m`；对照上游 `TLReport.nativeEngine`、`TLUnityView.swift` 和 `src/app/project.yml`。本轮 iOS 工程新增无条件复制 Java 资源，macOS 的 PackageMac 本来逐次打包，并增加内容和来源校验。

## 本轮 Java 交付证据

固定资源来源为上游 lineage-v2 的原始 `vda-v12.qcow2`，SHA-256 `a8dbaecc8fdcd682991b078d6bbb7df6972e459208634fa8dcbad24f17208d6a`。只读提取 ART/libcore、ICU、Conscrypt、tzdata 和 framework-res；不使用用户 VM 磁盘。JDK 21 / 固定 D8 编译当前仓库 Java 源码，打包 194 个资源文件及原始 NOTICE，逐项记录 SHA-256。源码/工具/资源任一不匹配则拒绝打包。源镜像缓存复用，临时原始磁盘与 APEX 提取文件已删除。

`tl_javaapp_stop` 等待 Activity/Service 销毁和 SharedPreferences 写入完成，join AppMain / GL / 音频混合器，关闭新建 guest worker 的入口并等待 Java/原生线程真正退出（包括 pthread_exit 和 TLS 析构），再检查 SQLite。未提交事务、残留线程、失败写入、异常销毁或 WebKit 未确认关闭不会被写成保存成功。现有 SessionController 仍要求 storage-closed 与进程回收两者都完成。

最终默认 **CTest 40/40**；包校验通过 **17 个 Mach-O** 的架构、签名、权限与依赖闭包，以及 **194 个 Java 资源**。新增真实 Dalvik boot、UTF-8/UTF-16/资源 ID/损坏 GLES manifest、正常/异常/写失败/残留线程/未提交 SQLite 生命周期、原生线程 TLS 关闭、打包 Runner 端到端会话；扩充 AppKit 输入法、真实 NSEvent 和旧资料库升级测试。生产会话验证触摸/键盘回调、失焦继续、暂停/恢复、最终 preferences 持久化、唯一 storage-closed 和进程回收。所有样本为独立测试数据，静音且无可见游戏窗口。

日志复用 `build/logs/current-upstream-build.log`、`current-upstream-ctest.log`、`current-upstream-bundle.log`；包证据为 `build/macos/bundle-verification.json`。当前候选只在 `build/macos/Product/HuskMac.app` 原地覆盖，保留现有 `HUSK_BUILD_VM=ON` 配置。候选重开/远端提交状态见 [progress.md](progress.md)。`actionlint` 通过；新 CI 资源准备配置的 GitHub 执行仍需真实结果，不能记作通过。Android 组件对应源码与发行许可仍是 P6 开放项。

## 下一轮优先事项

1. Java 手柄：接 `tl_pad_sink` 到 AppRunner 所属线程的 KeyEvent / joystick MotionEvent，保留设备/轴信息；用真实 DEX 回调、断连/失焦释放和暂停期间输入验证。不能将宿主计数器当作输入成功。
2. WebKit：明确 website data store 与用户存档的生命周期，建立可确认的持久化关闭；完成画布透明合成、缩放后点击和取消/销毁验证。当前使用过数据存储的会话按关闭未完成处理。
3. 真实 Unity 6 / SDL / Flutter：共同 Java 路径已具备生产 fixture 证据，后续在独立数据上逐个验证首帧、交互、保存重开；将具体缺失 API 和失败堆栈写回本表。Hole.io 旧路径的崩溃不能冒充新路径结果。
4. Egg：继续核对 DT_INIT / PLT 初始化，而非重复启动。已知 `libegginc.so` 构造函数 RVA `0x1621794` 调用 PLT `0x16413c0`，槽 `0x17636b8` 仍为 `0x1625d90`，缺少该槽的 ELF 重定位；当前仅证明初始化跳转失败，不能把 PairIP 存在当作根因。本轮 loader 增量是依赖符号搜索和 x18 SP 改写，没有证明已修复 Egg 的故障。详见 [findings.md](findings.md)。
5. 其余 native profiles 按上表逐个推进；Play 登录保留用户实测失败结论，不重复声称已有 auth 参数补丁解决了 Google 拒绝。

每日同步必须在同一轮完成可确定的平台编译、分发、窗口/输入、生命周期和验证，并更新当前候选；较大的未完成项继续保持开放、保存具体证据与下一步。Git 祖先或旧测试通过都不能替代这些验收。
