# 苹果电脑投影开关（Mac Projector Switch）

[English guide](README.en.md)

一个轻量的 macOS 菜单栏工具。按 **Option + P（⌥P）**，只启用或停用你选定的投影仪，连接线可以一直插着。

适合同时连接电脑内置屏幕、桌面显示器和投影仪的场景。工具按设备身份识别目标，检查其他屏幕的状态，并保留它们的排列。公开版不预设任何人的设备标识。

## 使用

1. 从 [Releases](https://github.com/fang775019070-rgb/mac-projector-switch/releases) 下载 Apple 芯片版本，解压后打开“苹果电脑投影开关.app”；也可以按下方方法自行构建。
2. 点击菜单栏的投影仪图标，在“选择投影仪”中选择要控制的设备。
3. 按 **⌥P** 切换投影仪；菜单里也有“启用投影仪”和“停用投影仪”。
4. 可以将快捷键改为 **⌥⌘P、⌃⌥P 或 ⌃⇧P**。
5. “退出并恢复投影仪”会先恢复已停用的目标设备，再退出工具。

工具运行期间会占用所选快捷键。默认的 ⌥P 不占用 ⌘P 的打印功能，但可能影响部分键盘布局的字符输入；有冲突时可在菜单中换一组。

这是本地应用，不联网，没有下载依赖，也不需要管理员权限。它控制电脑的显示输出，不控制投影仪的物理电源。设置只保存在本机的 `~/Library/Application Support/ProjectorSwitch/` 中。

发布包采用本地签名，尚未取得 Apple 开发者签名和公证。macOS 可能提示无法验证开发者；可以选择自行构建。应用不会要求关闭系统安全保护。

## 系统要求与限制

- 为 Apple 芯片 Mac（arm64）构建，最低部署目标为 macOS 13。
- 实际硬件测试：Apple silicon Mac、macOS；其他系统版本和连接方式尚未逐一验证。
- 显示停用功能使用 macOS 非公开接口，系统升级后可能需要适配。工具在缺少接口时会报错。
- 投影仪如果是主显示器、是其他屏幕的镜像来源，或是唯一可用屏幕，工具会拒绝停用并说明原因。
- 睡眠唤醒、重新插线后，系统可能重新启用投影仪。按快捷键即可再次停用，工具不会持续轮询或强制重新停用。
- 停用后，投影仪上的窗口可能被系统移动到其他屏幕；本工具不自动还原窗口位置。
- 不自动设置登录时启动。需要时可在系统设置 → 通用 → 登录项中自行添加。

如果恢复失败，先尝试菜单中的“恢复投影仪”，然后重新连接投影仪。注销或重启会清除本次登录会话中的停用配置。

## 从源码构建

需要 macOS 和 Apple Command Line Tools。没有 Xcode 工程、SwiftPM 包或第三方依赖。

```sh
git clone https://github.com/fang775019070-rgb/mac-projector-switch.git
cd mac-projector-switch
zsh build.sh
open "dist/苹果电脑投影开关.app"
```

也可以指定输出位置：

```sh
zsh build.sh "/absolute/path/苹果电脑投影开关.app"
```

构建脚本使用系统 Swift 编译器，并对生成的 app 做本地签名。运行应用前请关闭其他副本，避免快捷键重复注册。

## 验证

```sh
zsh test.sh
```

默认执行 18 项设备识别、误操作保护、布局检查和设置保存测试，不访问或切换真实显示器。GitHub Actions 会在 macOS 上运行这些测试并构建 app。

在已登录的 macOS 桌面会话中，可以额外检查快捷键注册及内部事件回调：

```sh
# 先退出占用 Option+P 的程序，包括苹果电脑投影开关
zsh test.sh --shortcut
```

这项检查不会切换显示器，也不能替代实际按键和硬件测试。原始硬件测试验证了三屏环境中投影仪单独停用和恢复、其他屏幕状态和排列保持一致；菜单界面的自动检查尚未完成。

## 命令行入口

app 中的同一个程序提供只读诊断和切换命令：

```sh
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --diagnose
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --status
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --toggle
```

`--status` 读取最近一次 app 运行状态，可能在 app 退出后保留旧记录。切换命令需要先在菜单中绑定投影仪。`--enable` 和 `--disable` 分别启用、停用目标。

```sh
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --set-shortcut option
```

该命令保存快捷键设置，重启 app 后生效。有效选项为 `option`、`command-option`、`control-option` 和 `control-shift`。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `DisplayModel.swift` | 设备身份、切换前置条件、其他屏幕状态检查 |
| `DisplayService.swift` | 系统显示接口、配置事务、排列保留、失败恢复 |
| `ProjectorController.swift` | 目标绑定、切换和恢复协调 |
| `GlobalShortcut.swift` | 全局快捷键与长按重复保护 |
| `SettingsStore.swift` | 本机设置的原子保存 |
| `AppDelegate.swift` | 菜单栏和状态反馈 |
| `RuntimeDiagnostics.swift` | 本机运行状态记录 |
| `main.swift` | app 和命令行入口 |

## 贡献与许可证

欢迎提交 [Issue](https://github.com/fang775019070-rgb/mac-projector-switch/issues) 或 Pull Request。请描述 macOS 版本、Mac 芯片、连接方式、复现步骤，以及其他屏幕是否受到影响；避免公开设备 UUID、序列号或未脱敏的诊断输出。

修改后请运行 `zsh test.sh` 和 `zsh build.sh`，并同步更新相关说明。涉及显示切换时，请在有可用恢复屏幕的桌面环境中做硬件验证。

项目使用 [MIT License](LICENSE)。非公开接口的参考资料和设计说明见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。

---

**English:** A native Swift menu bar app for toggling one selected projector with **Option+P** while keeping other displays connected. Apple silicon only. The public build contains no device preset; select your projector on first launch. Build with `zsh build.sh`, test with `zsh test.sh`. Uses private macOS display APIs, so compatibility can change after system updates. MIT licensed.
