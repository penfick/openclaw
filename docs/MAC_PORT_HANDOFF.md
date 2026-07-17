# Mac 端改造交接文档

> 本文档由 **Windows 端 `openclaw-windows-node`（C# / WinUI 托盘客户端 fork）** 的改动整理而来，供 **Mac 端 Claude** 参照，把同样的产品行为在 macOS 客户端上实现。
>
> 你不需要照搬 Windows 实现；目标是**产品行为与体验对齐**，技术细节按 macOS 平台惯用法做。
>
> 产品显示名：**TClaw**。底层协议/CLI/路径大量仍叫 `openclaw`（兼容考虑，见下）。

---

## 0. 阅读顺序与总原则

先读这一节，再读后面四块（安装简化 / 卸载 / 品牌图标 / 多语言），最后看 §6 任务清单开工。

| 总原则                                | 说明                                                                                                                         |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **客户端编排，尽量不改 gateway 源码** | 安装/卸载/精简步骤主要在 Companion 侧；gateway CLI（`openclaw`）只当工具调用。精简安装不需要改 openclaw 上游。               |
| **安装只做「能跑 + 能连」**           | 模型 / 渠道 / skills 等业务配置，装完再在 App 里做，不在安装阶段拦人。                                                       |
| **品牌与协议分离**                    | UI 显示 TClaw；`openclaw://` scheme、`~/.openclaw` 目录、CLI 名先不动，避免破坏与 gateway / 现有用户的兼容。                 |
| **跟系统语言**                        | 主 UI + 安装向导默认跟随操作系统首选语言；保留一个环境变量/配置覆盖用于调试。                                                |
| **跨平台一致**                        | gateway 配置路径 `~/.openclaw/openclaw.json`、端口 `18789`、配对协议等，Mac 与 Windows 保持一致，便于同一 gateway 服务多端。 |

### 平台映射速查（贯穿全文）

| 关注点           | Windows（已做）                                          | macOS（你要做）                                                                   |
| ---------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 后台常驻 gateway | 计划任务（Scheduled Task）+ WinExe launcher              | `launchd` LaunchAgent（`~/Library/LaunchAgents/*.plist`）                         |
| 启动 gateway     | `OpenClaw.GatewayLauncher.exe`（无控制台）               | 直接 exec 二进制/脚本，launchd 不挂可见 Terminal                                  |
| 卸载服务         | 删计划任务 + 杀进程 + 删 `gateway.cmd`                   | `launchctl bootout` + 删 plist + 杀进程                                           |
| 离线 runtime     | `vendor/cli`（node.exe + openclaw 包）                   | 打包 node + openclaw，或嵌入 runtime，支持内网安装                                |
| 应用数据目录     | `%APPDATA%\OpenClawTray` / `%LOCALAPPDATA%\OpenClawTray` | `~/Library/Application Support/OpenClawTray`（建议同名）                          |
| gateway 配置     | `%USERPROFILE%\.openclaw\openclaw.json`                  | `~/.openclaw/openclaw.json`（**同名**）                                           |
| 本地化资源       | `.resw` + `x:Uid` + `LocalizationHelper`                 | `.xcstrings` / `Localizable.strings` + `String(localized:)` / `NSLocalizedString` |
| 安装器           | Inno Setup（`installer.iss`）                            | `.dmg` / `pkg` / 独立 `install.sh`                                                |
| 自启             | 注册表 Run / 计划任务 `TClaw`                            | 登录项（Login Items）/ LaunchAgent                                                |

---

## 1. 安装简化（Setup 流水线）

### 背景

用户反馈「gateway 安装步骤太多」。Windows 把 native 安装从十多步精简到用户可见 ~4 步，并默认跳过 openclaw 的交互式 wizard（模型/渠道/skills 那一长串）。

### Windows 做了什么（参考）

- **默认配置**
  - `InstallKind = Native`（本机进程 + 后台服务，不装 Linux 容器）
  - `SkipWizard = true`（跳过 openclaw 交互 wizard）
  - `CleanBeforeRun = false`（首次安装不清旧状态；修复/重装再开）
- **流水线过滤**：去掉容器创建/配置/锁定/保活等步骤；`SkipWizard` 时去掉 `RunGatewayWizardStep`。保留：装 CLI → 写最小配置 → 注册后台服务 → 启动 + 健康检查 → 本机配对 → 端到端校验。
- **用户可见进度 ~4 步**：
  1. Check system / 检查系统
  2. Install runtime / 安装运行时
  3. Start local gateway / 启动本地网关
  4. Connect this PC / 连接本机
- **Soft-fail**：bootstrap token（QR）mint 失败不整条失败，回退用共享 gateway token 做本机配对。
- **安装包只装客户端 + 离线 CLI；gateway 在 App 内 Setup 向导里装**，不是安装器单独一步。

### Mac 要达到的产品行为

1. 首次启动 → 精简本机安装向导，**可见 3–5 步**，不要让用户在安装阶段配模型/渠道。
2. gateway 配置直接写 `~/.openclaw/openclaw.json`（mode=local、port=18789、bind=loopback、auth.token=随机生成、device-pair publicUrl=`http://127.0.0.1:18789`），尽量少调 `openclaw config set`。
3. 注册 **LaunchAgent** 启动 gateway（`RunAtLoad`、`KeepAlive` 可选），日志写文件，**不要弹 Terminal 窗口**。
4. 健康检查：HTTP `GET http://127.0.0.1:18789/`，接受 200/401/403，超时 ~90s，2s 轮询。
5. 本机 app 与 gateway 配对（operator，必要时 node），写好 App 侧连接信息（URL + token + device identity）。
6. 默认 `SkipWizard`；如需完整 wizard，保留一个「高级 / Advanced」入口或 env 开关。

### 关键决策（务必遵守）

- **不改 openclaw gateway 仓库**也能精简：Companion 决定调不调 wizard、写哪些默认配置。
- 安装阶段失败要可回滚（删已注册的 LaunchAgent、清半个配置）。
- 端口、bind、token 等默认值与 Windows 一致，便于多端共用同一 gateway。

### 落地建议（Swift / SwiftUI）

- Setup 向导用 `Sheet` / 独立 `Window`，分阶段 `enum SetupStage`。
- 进度用 `ProgressView` + 步骤列表；后台任务用 `Task` + `AsyncSequence`。
- 写 plist：`~/Library/LaunchAgents/<id>.plist`，`Label`/`ProgramArguments`/`RunAtLoad`/`StandardOutPath`/`StandardErrorPath`。
- 启动：`launchctl bootstrap gui/$UID ~/Library/LaunchAgents/<id>.plist`（或 `launchctl load`）。
- 权限（摄像头/麦克风/屏幕录制/通知）按需引导到「系统设置」对应面板。

### 验收

- [ ] 全新用户从安装包到「已连接本地 gateway」≤ ~5 个可见步骤
- [ ] 无可见 Terminal / 控制台
- [ ] `lsof -i :18789` 有 gateway 监听
- [ ] `~/Library/LaunchAgents/` 有对应 plist 且 `launchctl list` 可见
- [ ] 重启后 gateway 自动起来（若启用自启）

---

## 2. 卸载清理（gateway 卸干净）

### 背景

旧卸载偏容器（Windows 是 WSL）；native 后台服务 / 进程常残留。要求 **本机服务 + 残留进程 + 数据**都能清。

### Windows 做了什么（参考）

新增 `NativeGatewayCleanup`，顺序 best-effort：

1. `openclaw gateway stop`
2. `openclaw gateway uninstall`
3. 停并删除后台服务（计划任务 `OpenClaw Gateway`）
4. 杀 launcher / gateway 宿主进程
5. 杀监听 gateway 端口（18789）的 node/launcher
6. 删生成的启动脚本（`gateway.cmd`）

接入点：

- `--uninstall` 卸载前/后都跑 cleanup
- 安装服务步骤的 rollback 走完整 cleanup
- 清 setup-managed 本地 gateway 注册记录（保留外部/远程 gateway）
- Inno 卸载脚本：**先清 native，再清容器发行版**

**默认不删**：整个 `~/.openclaw`（workspace/skills 可能还要）；外部/SSH gateway 记录保留。彻底清理作为可选手动步骤。

### Mac 要达到的产品行为

卸载时（App 卸载 + 独立清理脚本两条路都要有）：

1. `openclaw gateway stop` / `openclaw gateway uninstall`（best-effort）
2. `launchctl bootout` / 删 `~/Library/LaunchAgents/*.plist`（gateway + App 自启）
3. 杀 gateway 进程、杀监听 18789 的 node
4. 清 App 数据：`~/Library/Application Support/OpenClawTray`、日志、缓存、登录项
5. **可选 / 确认后**：删 `~/.openclaw`（含配置/token/workspace）
6. 保留外部/远程 gateway 记录

### 给别人电脑「卸干净」的检查清单（Mac 版）

- `launchctl list | grep -i openclaw` 应无输出
- `~/Library/LaunchAgents/` 下无相关 plist
- `lsof -i :18789` 无监听
- `~/.openclaw`、`~/Library/Application Support/OpenClawTray` 已删（或已备份改名）
- 登录项里无 TClaw/OpenClaw
- `openclaw` 命令是否还要保留（看是否一并卸 CLI）

### 独立清理脚本建议

提供 `uninstall-gateway.sh`（bash），逻辑同上，可被 pkg 卸载后脚本调用，也可手动跑。幂等、best-effort、失败只告警不中断。

### 验收

- [ ] 卸载后 `launchctl list` 无 gateway
- [ ] 18789 无监听
- [ ] App 数据目录可清
- [ ] 重装可从零成功（无残留冲突）

---

## 3. 品牌 / Logo 图标

### 目标

产品显示名 **TClaw**，图标用自定义 logo（替换原「龙虾」Fluent Emoji 风格图）。

### Windows 做了什么（参考）

- 替换图标族（**文件名尽量不动，少改代码**）：app icon、安装向导主图、标题栏图标、包图标（Store/Splash/Square 等），全部由源图 `111.png` 用脚本生成多尺寸。
- 显示名 TClaw：窗口标题、托盘品牌、设置 App name、包 DisplayName、Product/AssemblyTitle。
- 多语言资源里用户可见的 `OpenClaw Windows Companion` 等 → `TClaw`。
- 安装器产品名 `MyAppName = "TClaw"`，`SetupIconFile` 指向新 ico。

### 故意没动（兼容，Mac 同样建议保留）

- 内部命名空间 / 类型名（`OpenClaw.*`）
- 数据目录名（`OpenClawTray`）
- 协议 scheme（`openclaw://`）
- gateway 服务名 / CLI 名（仍可能是 `openclaw`）
- 配置目录（`~/.openclaw`）

> 协议是否迁到 `tclaw://`：Windows 未全迁（仅 OA OAuth 回调用过 `tclaw://`）。Mac 建议先保持 `openclaw://` 兼容，迁称单独立项。

### Mac 要做的

1. App bundle 图标：`AppIcon.appiconset` 全尺寸（16–1024，含 `@2x/@3x`）。
2. 安装 dmg/pkg 图标与 app 图标一致。
3. `Info.plist`：`CFBundleName` / `CFBundleDisplayName` → `TClaw`；`CFBundleIdentifier` 视情况。
4. UI 内品牌文案：窗口标题、菜单栏、关于面板、设置页 App name → TClaw。
5. 安装向导主图 / 占位图用新 logo。
6. **安装包图标注意缓存**：Mac 一般无此问题，但分发时建议用稳定新文件名避免历史预览缓存。

### 验收

- [ ] Finder / Dock / 启动台 / 菜单栏均显示 TClaw 图标与名称
- [ ] 关于面板、设置页品牌一致
- [ ] 安装器图标为新 logo

---

## 4. 多语言 / 汉化

### 现状与问题（Windows）

- 主 App 用资源文件 + `x:Uid` + `LocalizationHelper`，**跟系统显示语言**；调试可设 `OPENCLAW_LANGUAGE`。
- 问题 A：Setup 安装向导大量**硬编码英文**，没走资源。
- 问题 B：中文资源键齐全，但**大量 value 仍是英文**（漏译）。
- 问题 C：openclaw CLI wizard 题目在 gateway 侧；默认 `SkipWizard` 可避开。

### Windows 做了什么（参考）

- **A. Setup 向导本地化**：新增 `SetupLocalizer`，跟 `CurrentUICulture` + `OPENCLAW_LANGUAGE`，内置 en / zh-CN / zh-TW 字典；Welcome / Capabilities / Progress / Permissions / Complete / Wizard 外壳全走本地化。
- **B. 主界面漏译补中文**：频道空状态、状态徽标（未配置/已连接等）、各渠道 tagline、实例页标题/副标题、诊断页（分享诊断、创建诊断包、打开文件夹等）；硬编码串改为 `LocalizationHelper.GetString/Format`。

### Mac 要做的

1. 用 **String Catalog（`.xcstrings`）** 或 `Localizable.strings`，`String(localized:)` / SwiftUI `Text("key")`。
2. **跟系统首选语言**（`Locale.current`）；提供 env 或 `UserDefaults` 覆盖便于测试（如 `OPENCLAW_LANGUAGE=zh-CN`）。
3. Setup 向导**单独**一套本地化表（或共用 App 表），避免硬编码英文。
4. 至少覆盖中文（简 + 繁）+ 英文；其它语言可后补。
5. CLI wizard 默认跳过（与 Windows 一致），减少 gateway 英文题暴露。

### Mac 优先本地化的文案面

1. 首次安装向导（能跑 + 能连的全过程）
2. 卸载 / 清理提示
3. 连接失败 / 未配置空状态
4. 安装完成页
5. 设置里常见项（自启、主题、关于）
6. 品牌名 TClaw

### 验收

- [ ] 系统设为简体中文时，Setup 全程与主要空状态为中文
- [ ] 英文系统仍正常英文
- [ ] `OPENCLAW_LANGUAGE` 可强制覆盖（调试）

---

## 5. 端到端用户路径（产品行为对齐）

```
安装包安装客户端（含 runtime / 离线 CLI）
  → 首次启动 Setup
      → 检查环境
      → 装 openclaw runtime
      → 写最小 gateway 配置 + 注册后台服务 + 启动 + health
      → 本机 app 配对
      → 权限（可选）→ 完成
  → App 内再配模型 / 渠道 / skills
卸载
  → 停服务 + 删后台任务 + 清本机配对状态
  → 可选：清 ~/.openclaw 与 App 数据
```

Mac 与 Windows 的产品路径应一致；只是后台机制 = launchd，本地化 = String Catalog。

---

## 6. Mac 改造任务清单（按优先级）

### P0（产品一致，必做）

1. 显示名 / 图标全面 TClaw（App + 安装器 + 关于面板）。
2. Setup 默认：**本机 gateway，最小步骤，Skip 交互 wizard**。
3. 进度 UI 粗粒度 3–5 步，文案中英（跟系统语言）。
4. 卸载：launchd + gateway 进程 + 端口 + App 数据路径清理脚本（App 卸载 + 独立脚本两条路）。
5. gateway 配置默认值与 Windows 一致（port 18789、loopback、token、device-pair publicUrl）。

### P1

6. 主界面空状态 / 诊断 / 频道类英文漏译补中文。
7. 安装失败 soft-fail（token mint 等不阻断本机配对）。
8. 离线 / 内网安装路径（若 Mac 包也要内网可用）。
9. 健康检查 + 自启（launchd `RunAtLoad`）。

### P2 / 平台差异

10. 无「控制台窗口」问题（Mac 用 launchd 即可，不要挂 Terminal）。
11. 容器化网关（WSL 等）全部 N/A，不用做。
12. 协议是否从 `openclaw://` 迁到 `tclaw://`：**先保持兼容**，迁称单独立项。

### 不要做（除非单独立项）

- 为汉化去改 openclaw gateway 上游 CLI wizard 全文。
- 重命名所有内部类型 / 目录为 TClaw（成本高、同步上游难）。

---

## 7. 关键默认值（跨平台一致）

| 项                                | 值                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------ |
| gateway 端口                      | `18789`                                                                        |
| bind                              | `loopback`（127.0.0.1）                                                        |
| auth.mode                         | `token`（安装时随机生成）                                                      |
| reload.mode                       | `hot`                                                                          |
| 配置文件                          | `~/.openclaw/openclaw.json`                                                    |
| App 数据目录                      | `~/Library/Application Support/OpenClawTray`（与 Windows 同名 `OpenClawTray`） |
| 本地 URL                          | `ws://localhost:18789`                                                         |
| device-pair publicUrl（loopback） | `http://127.0.0.1:18789`                                                       |
| 调试语言覆盖 env                  | `OPENCLAW_LANGUAGE`（值如 `zh-CN`/`zh-TW`/`en`）                               |

---

## 8. 给 Mac 端 Claude 的一句话指令

> 在 **不改 openclaw gateway 核心** 的前提下，让 macOS 客户端实现与 Windows 端一致的产品行为：①最短本机安装（能跑 + 能连，跳过交互 wizard）；②彻底卸载后台服务与残留；③TClaw 品牌与图标；④Setup + 主界面跟随系统语言的中文化。Windows 用「计划任务 + WinExe launcher + SetupLocalizer + resw」；Mac 用「launchd + String Catalog/xcstrings + 等价卸载脚本」，默认值与路径按本文 §7 保持跨平台一致。

---

## 9. 参考实现位置（Windows 仓库，仅供 Mac 端查阅思路）

> Mac 端不需要这些文件能编译，只需对照「做了什么 / 为什么」。

- 安装简化
  - `src/OpenClaw.SetupEngine/default-config.json`（默认 Native / SkipWizard / 不 CleanBeforeRun）
  - `src/OpenClaw.SetupEngine/SetupPipeline.cs`（`BuildStepsFor` 过滤）
  - `src/OpenClaw.SetupEngine/SetupSteps.cs`（native 配置直写、服务安装、mint soft-fail）
  - `src/OpenClaw.SetupEngine.UI/Pages/ProgressPage.xaml(.cs)`（4 阶段 UI）
- 卸载
  - `src/OpenClaw.SetupEngine/NativeGatewayCleanup.cs`
  - `src/OpenClaw.SetupEngine/Program.cs`（uninstall 编排）
  - `scripts/Uninstall-LocalGateway.ps1`（先 native 再容器）
- 品牌 / 图标
  - `src/OpenClaw.Tray.WinUI/Assets/**`
  - `installer.iss`（`SetupIconFile`、产品名）
  - 各 `Strings/*/Resources.resw` 品牌串
- 多语言
  - `src/OpenClaw.SetupEngine.UI/SetupLocalizer.cs`
  - `src/OpenClaw.SetupEngine.UI/Pages/*.xaml(.cs)`
  - `src/OpenClaw.Tray.WinUI/Strings/zh-cn|zh-tw|en-us/.../Resources.resw`
  - `docs/LOCALIZATION.md`（原设计：跟系统语言）

---

_文档结束。Mac 端按 §6 任务清单推进即可；有平台冲突时以「产品行为对齐 + 跨平台默认值一致」为准。_
