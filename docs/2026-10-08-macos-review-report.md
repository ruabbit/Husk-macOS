# macOS 审查问题处理

日期：2026-10-08。分支 `codex/macos-p0`。已有全部迁移与上游同步工作保存为检查点 `9573597`，运行时修复保存为 `fd9c470`。本轮只创建本地提交，没有推送或发布。**代码和文档问题已处理；P5 Minecraft 黑屏 / ANR、持续 PCM，以及 P6 发行许可仍是未通过项。**

新候选在 `build/macos-review-20261008/Product/HuskMac.app`。它与此前候选使用不同目录；日常 GUI 仍运行此前的 `macos-upstream-20261008` 候选，本轮没有启动或替换前台窗口。

## 八项问题的处理结果

| 审查项 | 核对结果与处理 | 当前边界 |
| --- | --- | --- |
| 全部工作未提交 | `9573597` 保存 237 个文件的完整现况；随后单独提交修复，保留可 review 的差异。检查点前扫描未发现 APK、磁盘、私钥或构建产物混入候选集 | 检查点提供本地回退点；不能补出此前每个阶段的真实提交历史，也不是远程备份 |
| Minecraft 单哈希限制 | 上一轮已允许扫描识别为 Minecraft 的 arm64 单 APK。本轮移除 runtime 中按样本 hash 放行的兼容分支，删除 SharedCore 的 C 哈希函数；`CompatibilityEvidence.minecraftP4SHA256` 只控制已验证标记 | 导入时的完整性 hash 与 Runner 独立复扫仍强制执行；可试运行不代表所有 Minecraft 版本兼容 |
| P5 状态与系统要求 | 保留 P5 未通过状态；Android 菜单显式标为实验。打包器根据 helper 和全部 dylib 的 Mach-O 最低系统版本写入 Info.plist，UI 与启动检查读取同一值 | 主 App / NativeRunner 编译目标 14.0；当前 VM 闭包为 27.0.0。没有伪造降低依赖要求，14.0 实机仍未测 |
| CI 标签与未运行 | 从 GitHub 官方 runner-images 列表确认 `xcode-27` 是公开 arm64 预览标签；常规 job 改为稳定 `macos-26`，更新缓存键，加入无图形 VM 控制器回归；actionlint 通过 | 远程 CI 未验证；`husk-metal` 是需自行注册的可选物理 runner，尚未核实其存在 |
| macOS 许可证缺口 | [许可证说明](01-licensing.md#macos-distribution-status-2026-10-08) 增加进程边界、真实依赖闭包、对应源码/notice/修改与再链接义务；旧 iOS 结论标为历史背景 | 发现 QEMU → libssh → OpenSSL 3 的额外组合问题；完整 notices 和对应源码包也不齐，P6 不能放行 |
| 仓库卫生 | 根目录三份笔记迁入 `docs/development/macos`；指南使用相对链接和 `MINECRAFT_APK` 参数。P0 Runner 迁入 `tests/macos-p0/harness`，更新监督器根目录、编译、测试和文档路径 | 保留 P0 的底层合成回归；它不进入产品包。历史 JSON 的机器路径、hash 和当时未提交状态原样保留，并在报告头部解释 |
| Orbit 文案误用于 Minecraft | 核对当前详情页按 runtime 区分描述与按键；此问题已在上一轮修复。本轮没有重复改写这部分实现 | 没有把 CUA 断线状态下的编译检查宣称为前台视觉验收 |
| VM 退出竞态 | 用“子进程回收 + stdout EOF + stderr EOF”判定终态，取消固定 0.3 秒后关闭读取器的做法；保留最后一条 storage-closed、stderr 和首个错误 | 继承输出管道迟迟不关闭时，2 秒后停止读取并明确报告日志不完整；旧会话事件不能影响重开后的状态 |

## 验证

| 检查 | 本轮结果 | 证据 |
| --- | --- | --- |
| 新目录 Release / VM-enabled 构建 | 通过 | `build/review-20261008/configure.log`、`build.log` |
| CTest | 12/12 通过，16.21 秒 | `build/review-20261008/ctest.log` |
| VMController 进程回归 | 延迟 650 ms 的最后事件、stdout/stderr 不同 EOF 顺序、缺失回执、残缺消息、失败事件后 clean、非零退出、有限管道超时、同对象重开均通过；另测系统版本含 patch、缺失/损坏元数据、启动前拒绝 | `tests/macos/VMControllerTests.swift`、`VMExitFixture.m`；CTest 原始日志 |
| 资料库升级与完整性 | 8 项通过，包含仅有样本 hash 不能赋予运行能力、其他 Minecraft hash 可试运行、伪造引擎仍被真实 helper 拒绝 | `tests/macos/LibraryCompatibility.swift`；CTest 原始日志 |
| 签名、架构、rpath、权限、系统字段 | 17 个 Mach-O 均通过；主 App 14.0，VM 闭包及声明 27.0.0 | `build/review-20261008/bundle.json` |
| P0 移动后的完整默认回归 | 30/30 通过；`gui=false`、`faults=false`、后台 2 cycles | `build/review-20261008/p0.log`、`build/macos-p0/results.json` |
| 工作流 lint | actionlint 1.7.12 通过 | `build/review-20261008/actionlint.log`；自托管标签在 `.github/actionlint.yaml` 声明 |

本轮没有启动 Android VM 或用户 APK，没有重放 P4/P5 游戏验收。Minecraft 的实际世界证据仍属于此前报告中的精确候选；新增进程 fixture 只验证宿主协议和资源回收。所有测试无可见窗口、无声音、无主动崩溃信号；测试后只保留此前日常 GUI，没有测试 Runner 遗留。

机器可读结果和关键源码 / 产物摘要见 [审查结果快照](2026-10-08-macos-review-results.json)。原始日志在忽略的 `build/` 中，不作为新源码提交。历史 P0–P5 JSON 没有因这次提交而改写其当时的 `uncommitted` 值。

## 复查

已有固定依赖可复用；从仓库根目录执行：

```sh
cmake -S . -B build/macos-review-20261008 -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DHUSK_BUILD_VM=ON
cmake --build build/macos-review-20261008 -j 6
ctest --test-dir build/macos-review-20261008 --output-on-failure
python3 scripts/verify_macos_bundle.py \
  build/macos-review-20261008/Product/HuskMac.app
./scripts/test_macos_p0.sh
actionlint .github/workflows/macos.yml
```

没有预建图形/VM 依赖时，先按 [构建指南](macos.md) 准备。无需 VM 的开发者使用默认 `HUSK_BUILD_VM=OFF`；VMController 的有限 CLI 回归仍会编译和执行。

P5 下一验收门槛仍是查明 guest 侧 Minecraft 黑屏 / GameActivity ANR 并证明持续 PCM；P6 还要解决许可组合、提供完整对应源码与 notices、实际跑远程 CI，并完成最低系统、另一台 Mac、Developer ID、公证及前台设备验收。文档和本轮宿主测试通过不替代这些结果。
