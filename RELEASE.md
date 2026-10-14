## 苹果电脑投影开关（Mac Projector Switch）

首个公开试用版。按 Option+P 单独启用或停用指定投影仪，其他屏幕继续使用。

### 下载和使用

- 下载 `MacProjectorSwitch-v1.2.0-arm64.zip`，解压后打开“苹果电脑投影开关.app”。
- 首次启动请在菜单栏的“选择投影仪”中选择自己的设备。
- 快捷键可改为 Option+Command+P、Control+Option+P 或 Control+Shift+P。
- 下载包由 GitHub Actions 从公开源码构建，附带 SHA256 校验文件。

### 验证与兼容性

Apple silicon / macOS 的投影仪停用、恢复实测通过；18 项模型与设置测试通过，GitHub 自动构建检查通过。

本版面向 Apple 芯片 Mac，采用本地签名，尚未进行 Apple 开发者签名和公证。显示切换使用 macOS 非公开接口，系统升级后可能需要适配。完整使用和恢复方法见 README。

## English

Mac Projector Switch is a native macOS menu bar utility that toggles one selected projector with Option+P while keeping the other screens connected. This public preview is for Apple silicon Macs. Select your own projector on first launch.

The downloads are built from the public source by GitHub Actions. A SHA256 checksum file is included. The app is ad-hoc signed, not Developer ID signed or notarized. Hardware validation covered Apple silicon with macOS. Model tests and the GitHub build check passed. Private display APIs may change after system updates. Read README.en.md for build instructions, limitations and recovery steps.

MIT License.
