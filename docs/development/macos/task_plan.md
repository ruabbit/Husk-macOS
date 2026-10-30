# Husk macOS 迁移实施

## 当前执行：2026-10-30 Unity / JIT-less 增量

- [x] 起点 11586e3 干净，origin 无新增；前轮 CI 40824326328 success，空闲 Product/PID 74471 经 CUA 正常退出。无本项目 Runner/VM/构建，其他项目 UTM 保持。
- [x] upstream ee85db6..645c22a 共 13 提交/23 路径普通合并，再合回 macOS ec0ed02；Compatibility/bionic mmap/Unity 三处语义冲突已处理。
- [x] 对照上游功能审计，补 Mac 维护/排队回执、静态签名页映射与 LuaJIT 能力判断、Unity/ES3.1/Java framework 回归。
- [x] 推进 AOT 转换取消及旧 Unity/Minecraft 后台会话专门验证；具体未通过边界保留。
- [x] 唯一 build/macos build 24，针对性 27/27、默认 182/182（355.67 秒）、18 Mach-O/406 Java 资源/两语言各 776 条通过；CUA 单次启动 PID 7565，核对 11 应用/图标并返回首页。
- [ ] 提交/推送两分支、远端读回、CI、来源锁与每日续跑记录收尾。
- [ ] 真实 JNA/Lua/游戏存档、转换中进程丢失、WebView 顺序交叠/第三方插件、实体设备/Play/VM/P6 继续开放。


## 当前执行：2026-10-29 JIT-less Runner 接入

- [x] 核对干净 84eaea8、build 22/CI 40615007325 success 与实际进程；空闲 Product/PID 70008 经 CUA 正常退出，无本项目 Runner/VM。
- [x] origin 无外来提交；upstream a06a74d..ee85db6 共 13 提交/25 路径。普通合并 main=5258ed8、macOS=1b4acff；loader 冲突保留 ELF 地址分类并接入 AOT data_view/waddr。
- [x] 接入共享 AOT 转换/本地签名、每游戏 opt-in 与独立 Runner 分发、禁止静默回退、缓存验证；保留默认模式/窗口/输入/暂停/关闭。
- [x] 真 ELF/DEX 与八条 AOT 打包会话、Java 暖缓存/偏好和 SQLite 重开；唯一 build 23 默认 176/176（336.09 秒）、18 Mach-O/406 Java 资源/两语言各 771 条通过；共享 iOS 仅语法证据。
- [x] CUA 单次启动 Product/PID 74471；AX/截图核对原图标/TabView/11 应用及默认关闭的 JIT-less 选项，返回首页。
- [x] 来源锁/parity/progress 已更新；源码 3398744 与 main 5258ed8 正常推送并读回。CI 40824326328 success（45 hosted 核心回归、51.90 秒及 P0 memory/core，hardware skipped）；每日续跑提示经工具更新到 build 23/AOT/具体开放项，原时间与线程/约束保持并精确读回。
- [ ] 既有 WebView 顺序交叠/第三方插件、真实游戏/实体设备/Play/VM/P6 继续开放。


## 当前执行：2026-10-28 Play 详情与导航

- [x] 核对干净工作区、实际候选/Runner/VM/构建，退出空闲 build 21；前轮 CI 40434410977 success 已复核。
- [x] 先 fetch origin（无外来提交）再 fetch upstream；9519faf..a06a74d 共 7 提交/26 路径，main=e3b08b8、macOS merge=3e5e8c3。HuskLogo 修改/删除冲突按上游恢复原标志的意图解决。
- [x] Mac 恢复标签导航、原图标、首页头像菜单与设置账号入口；共享账号/兼容性主域迁移。Play 富文本、元数据、独立截图浏览已接线；新增受控协议/布局回归与实验性 ELF 转换工具布局检查。
- [x] 唯一 build/macos 构建 build 22；针对性 6/6、默认 166/166（275 秒）、18 Mach-O/406 Java 资源/两语言各 766 条与 iOS 共享语法通过。
- [x] CUA 单次启动准确 Product/PID 70008，核对原图标/标签导航/11 应用/头像菜单及设置账号入口，已返回首页。
- [x] 来源锁/parity 已更新；main e3b08b8、适配源码 59bacda 已正常推送并读回。CI 40615007325 success，43 hosted 核心回归（46.56 秒）及 P0 memory/core 通过，hardware skipped；最终文档与续跑提示据此收尾。
- [ ] 继续既有 WebView 顺序交叠/真实 HTTP 插件、实体设备/真实账号、Play/VM/P6；实验性 ELF 工具不代表重定位/代码改写或 Runner 新引擎已完成。



## 当前执行：2026-10-27 上游 3.1 接入

- [x] 从干净 1c9cafe 核对分支、远端、build 20/CI 成功记录与进程；首次 SSH fetch 连接关闭，重试成功。origin 无新增；upstream 新增 27 提交/66 路径。
- [x] 普通合并 upstream/main=9519faf 到 main，再合回 macOS；两次无冲突，已正常推送并读回。
- [x] 逐项落实 Godot Kotlin 共用文件句柄、V8/压缩堆/运行时修复、APK manifest 主包排序、Java 键盘/布局及共享语言；15 项针对性后台回归通过。
- [x] 接入 3.1 的 Mac 侧栏/首页/资料库/商店/导入与共享账号、游玩计时；中英文资源、离线账号协议与打包语言传递通过，保留 AppKit/Runner/关闭协议与已删除分类。
- [x] 退出空闲候选后，唯一 build/macos 完整构建；最终默认 164/164（256.95 秒）、18 Mach-O/406 Java 资源及中英文资源通过。CUA 单次启动 build 21/PID 13975，首页 11 应用、图标/侧栏和账号页验证后回到首页。
- [x] 来源锁/parity/交付记录与每日提示更新；源码 fb1e7b0 与 main 99169de 已推送、远端 SHA 读回。CI 40434410977 completed/success，41 hosted 核心回归及 P0 memory/core 通过；保持 codex/macos-p0。
- [ ] 继续 WebView 历史恢复/host-stop、导航/destroy、Activity replacement/recreate、加载中/跨源和真实 HTTP 第三方插件回归；保留失败证据与已有实现，不重复迁移已交付路径。
- [ ] 完成剩余动态文案/帮助诊断翻译及可见中文界面验收；真实账号/Keychain 服务、Godot/Cocos/Flutter 等真实应用、实体 IME/手柄和 Play/VM/P6 保持开放。

## 当前执行：2026-10-26 HTTP WebView 与停止交叠

- [x] 工作区干净，origin/upstream fetch 无新增；最新 build 19 与 CI 40150135195 success 已复核。无本项目 Runner/VM/构建，其他项目 UTM 保留。
- [x] 复核上游与 macOS 接线；隔离 HTTP DEX 重定向、cookie/插件持久化、导航与 host-stop 交叠五项通过，停止等待原保存且不延长期限。
- [x] 更新 War Thunder 当前证据：更新器完成后 Vulkan 黑名单主动 exit 1；未重跑游戏或修改用户存档。
- [x] 唯一 build/macos 的 build 20 完整构建、默认 CTest 155/155 与包检查通过；CUA 单次启动 PID 98822，首页 11 应用与图标确认。
- [x] 源码 97de762 已正常推送，两分支远端 SHA 已读回；CI 40253576983 completed/success（36 hosted 核心回归，48.98 秒，P0 memory/core 通过），来源锁与最终记录已更新，保持 codex/macos-p0。
- [ ] 后续继续历史恢复检查/host-stop 交叠和真实 HTTP/第三方插件。导航与逐视图 destroy 专门回归、Activity replacement/recreate、加载中/跨源与实体设备/真实游戏验收保持开放。

## 当前执行：2026-10-25 导航许可与文档保存边界

- [x] 核对干净工作区、远端、祖先及 build 18 交付；origin/upstream 均无新增，main=2c3af7a，macOS=72f272a。
- [x] 核对平台运行链路；补导航许可先于保存、同文档锚点及连续导航保存的隔离，保留加载中/跨源/真实应用开放项。
- [x] 用真实 DEX/WebKit 验证拦截、允许导航、锚点、连续保存及失败；在唯一 build/macos 构建、默认 CTest、包检查。
- [x] 单次启动 Product/build 19，PID 99255；路径、AX/截图确认 11 个应用；源码 963975e 已推送，main/macOS 两分支远端 SHA 已读回。
- [x] 本批 CI 40150135195 completed/success；来源锁与交付文档记录最终验证，随本次文档提交正常推送并复核远端 SHA。

## 当前执行：2026-10-24 同一 WebView 导航前保存

- [x] 复核工作区、远端、来源锁与运行进程；origin/upstream 均无新增，Husk 本项目为空闲。
- [x] 为同一 WebView 的主文档导航、reload/back/forward 和后续 `loadUrl` 接入一次性保存交接；保留 host-stop、Activity 替换、跨来源与加载中文档的边界。页面脚本直接 file URL 没有单独登记为通过。
- [x] 在真实 Java DEX fixture 中验证成功导航保存、localStorage/IndexedDB 重开和拒绝/超时的 sticky 失败。
- [x] 在唯一 `build/macos` 完成构建、针对性回归、默认 CTest、包检查和一次 Product 重启。
- [x] 更新来源锁、parity、progress/findings，提交并推送 `origin/main` 与 `origin/codex/macos-p0`，读回远端 SHA；源码 `6d16dda` 与本轮交付文档已完成。

## 当前执行：2026-10-23 上游 bundle 与宿主环境

- [x] 干净 eebd248 起步，无 Husk/Runner/本项目构建，其他项目 UTM 保留；origin 两条分支无新增。
- [x] upstream 2df074b..3b87cbc 两提交/10 路径已普通合并至 main=2c3af7a，再合回 macOS=ef287c0；无冲突。
- [x] Mac IOKit 电源、Java/原生一致的语言/时区/设备属性、ZIP64/deflate 有界流式导入已接入；补 guest stdout 与控制事件隔离。
- [x] 最终代码默认 CTest 141/141（201.91 秒）、18 Mach-O/406 Java 资源包检查；唯一 build/macos/build 17，VM=ON 与缓存保留。
- [x] CUA 单次启动当前 Product/PID 25881；完整路径、AX/截图确认原有 11 个应用。
- [x] 正常原子推送 main=2c3af7a 与 macOS 源码 aa2cdbf，远端 SHA 读回一致。
- [x] 本批 CI 39884106041 completed/success：构建/包检查、36 项 hosted 核心回归（42.59 秒）和 P0 memory/core 通过。
- [x] 来源/进度更新，每日提示精确读回；原聊天、每天 09:00、仅写自有仓库、空闲自动退出与所有原有约束保留。

## 当前执行：2026-10-22 单个 WebView 销毁前保存

- [x] 从干净 15c8f1b 开始，两个远端 fetch 无新增；upstream 2df074b 已是 main/macOS 祖先、来源锁一致，无冲突或外来提交。初始 index.lock 为已消失的临时刷新锁。
- [x] 核对空闲 Product PID 18451 与 CUA 主窗口的 11 个应用，无本项目游戏/VM/构建；其他项目 UTM 保留。
- [x] 补 direct WebView.destroy 的独立保存、Java bridge/UI 排空与最终关闭协调；保留逐 Activity/导航及跨来源开放项。
- [x] 真 DEX 后台验证保存重开、重复销毁、其他视图继续、保存拒绝/超时、host-stop 交叠及 AndroidX listener；默认 137/137（190.34 秒）、34 项 WebView 与包检查通过。
- [x] 原位更新唯一 build/macos/build 16，CUA 单次启动 PID 52520，主窗口 AX/截图确认 11 个应用。
- [x] 代码 54910cc 已正常推送、两条远端 SHA 读回一致；每日提示更新并精确读回，保持原聊天/每天 09:00/空闲自动退出及全部边界。
- [x] CI 39705343544 completed/success：构建、包检查、34 项 hosted 核心回归（43.44 秒）和 P0 memory/core 通过；仅补交交付记录，不重复构建/重启。

## 当前执行：2026-10-21 应用主动关闭前保存

- [x] 干净 f40ae23 起步，地址/分支正确，无其他 Git 操作或本项目构建/游戏/VM；空闲 Product PID 67505，CUA 主窗口显示 11 个应用。
- [x] 依次 fetch origin/upstream，均无变化；upstream 2df074b、main cc99757、macOS f40ae23，远端无分歧。
- [x] 为应用最后 Activity 的 finish/finishAffinity 增加宿主保存交接，保留 Activity 切换与无宿主模式、销毁失败/存储回执检查。
- [x] 真实 DEX + 打包 Runner 回归覆盖 guest finish、重复请求、保存/销毁失败及 Activity 替换；默认 127/127、24 项 WebView 与包检查通过。
- [x] CUA 正常退出空闲 Husk，唯一 build/macos 原位更新 build 15、单次启动 PID 18451，主窗口 AX/截图确认 11 个应用。
- [x] 代码 c549924 已推送、远端读回一致，CI 39541085280 success；交付记录/来源锁已更新，每日任务保持 09:00 和原有约束。

## 当前执行：2026-10-20 WebView 卸载前保存

- [x] 从干净的 4b1d5b5 开始，远端地址正确，无其他合并/构建/游戏/VM；只有空闲 Product build 13 PID 39849。
- [x] fetch origin/upstream，双方均无新提交；upstream/main 仍为 2df074b，祖先与来源锁一致。
- [x] 补 Java 内嵌 WebView 的受控卸载前保存，在 Java 桥仍可用时交付生命周期并排空，保留失败判定与关闭回执。
- [x] 新增 8 项真实 WebKit/DEX 后台回归，验证单次事件、插件写入保存重开和失败场景；默认 115/115、包检查与 iOS 共享文件语法检查通过。
- [x] 原位更新唯一候选 build 14，单次重开 PID 67505，主窗口 AX/截图显示原有 11 个应用；更新对齐与来源记录。
- [x] ee26f7f 已正常推送并读回远端 SHA；CI 39371120881 success。每日任务已更新并核对保持每日 09:00 与全部约束。

旧顺序先 Android destroy 再真实空白导航，WebKit 在卸载时压掉 prompt，插件无法保存。本轮加入独立保存阶段，仍保留 late-bridge 的失败检查。沿用 docs/development/macos 中的计划文件，不在仓库根新增笔记。

## 当前执行：2026-10-19 上游运行时与文件选择器

- [x] 核对干净工作区、两远端和运行会话；origin 无新增提交，仅空闲 Product build 12 PID 13331。
- [x] fetch 确认 cedb01e..2df074b 共 4 提交 / 29 路径，普通合并到本地 main，再合回 macOS。
- [x] 解决 LoadedApk/AppRunner/ContextImpl 重叠，保留自定义加载器、NativeActivity 与存储关闭协议。
- [x] 接入 macOS 原生文件选择器，核对 .NET/基础运行时增量并补后台回归；57 个独立目标编译、84/84 源码测试（42.29 秒）和 5 个共享文件 iOS 语法检查通过。
- [x] 默认 CTest 107/107（72.19 秒）、18 Mach-O / 406 Java 资源包检查；唯一候选 build 13 原位更新并单次重开，主窗口 AX/截图通过。
- [x] 每日任务保存用户新授权：核对无游戏/VM后自行退出空闲 Husk，正常退出失败可强退，不再请求用户 ⌘Q；保持每天 09:00。
- [x] 更新交付来源与功能记录；代码 ee5d553 与 main cc99757 已原子推送并读回；CI 39185361624 构建、包检查、33 项 hosted 核心测试及 P0 memory/core 全部 success。

CUA 早期读取超时及 native pipe closed 已不再阻塞交付。用户明确授权空闲 Husk 自动强退；实际继续时旧进程已经退出，无需发送信号。build 13 全构建和全部默认测试通过，CUA 单次启动 Product PID 39849，原有 11 个应用可见。没有启动用户游戏/VM或触碰用户存档。

## 当前执行：2026-10-18 上游 3.0 发布同步

- [x] 工作区干净，远程地址正确，origin 两分支无外来提交；仅空闲 Husk PID 7656。上一轮 b9caa81 CI success。
- [x] fetch 后确认 a3407fc..cedb01e 共 64 个提交，正式 3.0 tag=cffaf8b；已普通合并到本地 main。
- [x] 按语义解决 macOS 合并的 7 个冲突文件，保留加载器混合页、Java 自定义加载器和生命周期修复。
- [x] 核对并接入本轮 Unity IME、48 APK、Godot/Java/图形与 Store 下载/OBB；核对 UI/报告/PS4 的平台差异。
- [x] 用独立后台回归覆盖新增行为，完整 CTest 和包检查通过后更新唯一候选并单次重开。
- [x] 更新来源锁、功能对齐与交付记录；代码 70c2764 与 main 308793d 已原子推送并读回 SHA，保留 codex/macos-p0。

本轮无用户游戏/VM运行，未启动已知失败游戏。103/103 默认测试、包检查和单次候选重开已完成；首页截图/选择通过，详情页 CUA native pipe closed。原方案文件标题匹配的一次补丁未命中，未修改文件；已按实际标题补入本节。较大平台缺口继续保留开放状态，不用合并祖先或旧测试替代功能验收。

## 当前执行：2026-10-13 三款游戏图标与启动修复

- [x] 核对干净工作区、唯一候选和空闲 Husk；恢复三款 APK/用户日志的只读诊断证据。
- [x] 跨 split 解析并合成 adaptive 图标，刷新已有图标缓存；像素/方向及旧索引、设置、存档保留回归通过。
- [x] 从固定依赖来源打包 Android 系统字体与配置，在所有 NativeRunner profile 中接入路径映射；实际全字体名读取通过。
- [x] 保留有界诊断尾部与独立监督器退出记录；9 MiB fixture 和真实 Clash 输出饱和后的最终错误均保留。
- [x] 修复 OpenSL 停止/清空返回后仍访问缓冲区及回调的竞态；补通用 NativeActivity 的 FMOD Java 接口注册，并把 Vulkan 帧纳入状态计数。
- [x] 针对性回归及隔离样本验证：War 已实际渲染 1280×720 加载页，失焦继续、暂停/恢复通过；Clash 留下退出 101 的证据；Egg 静态核对 ExecuteProgram。
- [ ] 剩余运行兼容：War 数据检查/自定义 Java updater 与正常关闭回执、Clash 原生初始化 exit(101)、Egg 初始化/PLT。下一步和证据保存在 upstream-parity.md，均未标为完整可玩。
- [x] 默认 CTest 66/66、18 Mach-O / 406 运行资源包验证、唯一候选原位更新；最终主窗口截图确认三款图标正常。
- [x] 修复提交 9eb9970 已正常推送并读回远端 SHA；CI 38386696549 已启动，尚未完成。三款完整运行验收保持开放。

诊断基线：Egg 的图标在 density split；War/Clash 的 icon.data 是 ImageIO 无法解码的 adaptive XML。War 在读取 `/system/fonts/%s` 时失败，候选缺少系统字体。Egg 仍在原生构造函数跳到未重定位 PLT。Clash 的 stderr 被前 4 MiB 截断，尚无完整终止证据。原始证据为 `build/logs/current-three-games-audit.json`，修复前候选为 2.0.0/build 3。

## 当前执行：2026-10-13 Husk 2.0 与手柄交付

- [x] 核对工作区、origin/upstream 和实际会话；上游 main=8e79a47，包含 2.0=e02ac68，真实合并 5866498。
- [x] 接入 2.0 首页/资料库/Store/帮助、外观/圣诞装饰、窗口控制、全屏偏好、快捷方式和下载面板。
- [x] 完成共享社区兼容性查询/缓存/回退，Mac 报告带真实来源；没有发送公共报告。
- [x] Java 手柄的按钮/轴、设备/热插拔、断连/失焦/暂停/停止释放，真实 DEX 与打包会话通过。
- [x] 六条新增原生引擎路径接通共享驱动、资料库、Runner、输入、暂停与可确认的销毁/存储关闭；正常及失败路径经过真实 ELF fixture 验证。
- [x] 独立 WebRunner 接入 Capacitor/Cordova；真实 WebKit 持久化、重开、清除与暂停/恢复测试通过，回执区分 WebKit 所有权。
- [x] MoltenVK 实际应用上游 SPIRV-Cross 补丁，随包源记录与实际 compute shader 回归通过。
- [x] 唯一 build/macos 原位构建 2.0.0/build 3，保留 VM=ON；默认 CTest 61/61，18 Mach-O / 194 Java 资源校验通过。
- [x] 旧候选由用户正常退出；CUA 单次打开新 Product，PID 68836、首页初始 AX 与商店截图已核对。
- [ ] 资料库详情/帮助/前台输入等可见验收：CUA 再次 native pipe closed。没有重复启动或假称完整 GUI 通过。
- [x] 代码 dfd7f6f 已正常推送，读回确认 main=8e79a47 与 macOS 分支=dfd7f6f；新的 CI 38374832136 已运行，记录时尚在执行。后续仅补文档交付记录。

本轮的代码/后台/包验证已完成，剩余真实应用和旧迁移缺口按 [upstream-parity.md](upstream-parity.md) 保持开放。不得用 fixture 或编译通过替代完整游戏兼容；也不得将 Java WebView 与独立 WebRunner 的存储语义混为一谈。

## 当前执行：2026-10-12 上游与 Java 运行链路

- [x] 核对干净工作树、远端、Git 操作与进程；origin 两分支无新增提交，Husk/Runner 已退出。
- [x] fetch 上游 `8a9dc1b..f0bd526`，70 个提交、139 个路径；main 快进，macOS 无文本冲突合并，代码提交 `fcce001`。
- [x] 复核自动合并保留的 macOS 修复，编译当前共享运行时代码。
- [x] 固定 Java 资源和工具来源，构建本仓库 framework DEX，接入唯一候选与包校验。
- [x] 实现并验证 Java 启动、触摸/键盘、暂停/销毁和存储回执；实际 DEX 与生产会话通过后接入分发。
- [x] 默认 CTest 40/40、17 Mach-O / 194 Java 资源校验，更新来源锁和功能对齐。
- [x] 代码提交 `fcce001`，正常推送两分支并读回远端 SHA；main 为 `f0bd526`。
- [x] 通过 CUA 单次启动 Product，确认 PID 98251 和首次主窗口；未重复运行已知失败游戏。
- [ ] CUA 在初次主窗口后再次断开；加载后的资料列表/详情页可见验收仍待补。

新增上游把 SDL（DXVK 除外）、Python、Flutter 交给 Java；与 Unity 6 共用的资源与生命周期是本轮重点。Egg 仍未到 onCreate，不复跑。Play 个人账号拒绝仍是开放问题。

## 当前执行：NativeActivity / Egg, Inc.（2026-10-11）

用户授权接入上游 NativeActivity，要求后续同步同时完成对应 macOS 适配。复用现有驱动、AppKit 固定画布和独立 Runner；保留正常关闭存储协议。

- [x] 确认 Egg 的四个 APK、arm64 ABI、NativeActivity 扫描结果及 macOS 分发缺口；上游 `b7480b6` 已在本分支。
- [x] 编入驱动，补齐同一活动线程上的启动、暂停、销毁和 join；接入分包、包名、方向、键鼠/手柄。
- [x] 采用 PR #82 的共享 Application JNI 修复，增加生命周期、异常清理和真实宿主事件对象回归。
- [x] 独立数据、静音、后台探测 Egg；定位到原生构造函数中的未重定位 PLT 跳转，保存失败证据，未记为可玩。
- [x] 在唯一 `build/macos` 编译独立目标；27 项不依赖新包的 CTest 通过。
- [x] 回收用户已退出但残留的空闲 Husk，在原位打包；默认 29 项 CTest 和 17 个 Mach-O 包校验通过。
- [x] 单次重开 Product，核对新 PID 314 和可执行路径。
- [ ] CUA 连接恢复后核对前台 Egg 详情页入口；当前 AX 读取仍断开，不重复启动已知失败样本。
- [x] 更新功能对齐检查、开发记录和原每日任务，要求同轮完成平台适配与验证。
- [x] 保存源码、完整候选回归和 Egg 失败证据；提交与推送 SHA 在本轮最终交付中核对。

当前候选已更新并单次重开。用户确认退出后的空闲残留主进程已回收，未绕过打包进程保护。CUA 的 AX 连接仍断开，仅前台可见检查待补；Egg 原生初始化失败继续作为开放兼容问题。

当前优先级更新（2026-10-11）：已合入上游 `8a9dc1b` 的 75 个新提交，并将新增共享 Dalvik/NDK 等模块编入 macOS，默认 CTest 25/25 与包校验通过。旧 Unity 启动链路保持；新版 Unity 6 已被上游转至 Java 路径，macOS 尚缺受控资源打包、Java profile、关闭确认和实机交互验证。本轮已更新并重开候选，继续 [上游功能接入现况](upstream-parity.md) 中的具体接线步骤。个人 Google Play 登录仍失败。以下 P0–P6 表格是历史记录，不代表当前功能对齐。

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
