# 苹果电脑投影开关 (Mac Projector Switch)

[简体中文](README.md)

A small native macOS menu bar app that enables or disables **one selected projector** with **Option+P**, while leaving your other screens connected. Keep the cable plugged in and bring the projector back when you need it.

## Getting started

1. Download the Apple silicon app from [Releases](https://github.com/fang775019070-rgb/mac-projector-switch/releases), or build it from source below.
2. Open `苹果电脑投影开关.app`. Click its projector icon in the menu bar.
3. Use **选择投影仪…** (Select projector) to select the external device you want to control. The public build contains no device preset.
4. Press **Option+P** to toggle that device. **启用投影仪 / 停用投影仪** are the Enable / Disable menu actions.
5. Use **快捷键** (Shortcut) to select Option+Command+P, Control+Option+P or Control+Shift+P instead.
6. **退出并恢复投影仪** (Quit and restore projector) enables the disabled target before quitting.

The app reserves its chosen shortcut while running. Option+P may normally enter a character or trigger an app/input-method action on your keyboard layout; select an alternative if needed. Command+P remains available for printing.

The app is local-only, has no downloaded dependencies, and does not need administrator privileges. Settings and runtime diagnostics remain in `~/Library/Application Support/ProjectorSwitch/`. It controls display output, not the projector's physical power switch.

Release builds are ad-hoc signed and are not Apple Developer ID signed or notarized. macOS may report that the developer cannot be verified. Building locally is another option; this app does not require disabling system security protections.

## Requirements and limitations

- Builds target Apple silicon (arm64), with a minimum deployment target of macOS 13.
- Hardware-tested on an Apple silicon Mac with macOS. Other OS versions, Intel Macs and non-native display connections have not been validated.
- Real display disconnection uses private macOS APIs. OS updates can change or remove them; unavailable APIs produce an error.
- The main display, the last usable display, and a projector serving as the mirror source for another screen cannot be disabled through this app.
- macOS may re-enable the projector after wake or reconnection. Press the shortcut again; the app does not continuously poll or force the disconnected state.
- The system can move projector windows to other screens. Their window positions are not automatically restored.
- Login startup is not configured automatically. Add the app in System Settings → General → Login Items if you want it to start when you log in.

If restoration fails, try **恢复投影仪** (Restore projector), then reconnect the cable. Logging out or restarting clears the session-scoped disconnection configuration.

## Build

Use a Mac with Apple's Command Line Tools installed. No Xcode project or SwiftPM dependencies are needed.

```sh
git clone https://github.com/fang775019070-rgb/mac-projector-switch.git
cd mac-projector-switch
zsh build.sh
open "dist/苹果电脑投影开关.app"
```

The build script uses the system Swift compiler and ad-hoc signs the app. An optional first argument selects another output path.

## Tests

```sh
zsh test.sh
```

This runs 18 model and persistence checks, including target identification, refusal of unsafe display changes and detection of changes to other screens. It does not touch physical displays. GitHub Actions runs these checks and builds the app on macOS.

In a logged-in desktop session, after quitting programs that reserve Option+P:

```sh
zsh test.sh --shortcut
```

This also checks native shortcut registration, internal callback dispatch and held-key suppression. It does not generate desktop keyboard input or switch displays. Hardware testing and actual keyboard use remain separate. Automated menu UI validation is incomplete.

## Command-line interface

The app's executable also accepts `--diagnose`, `--status`, `--toggle`, `--enable` and `--disable`:

```sh
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --diagnose
"dist/苹果电脑投影开关.app/Contents/MacOS/ProjectorSwitch" --toggle
```

Select a target in the menu before issuing switch commands. `--status` reads the last saved runtime record, which may be stale after the app exits. See the [Chinese guide](README.md#命令行入口) and [implementation notes](IMPLEMENTATION.md) for details.

## Contributing

Open an [issue](https://github.com/fang775019070-rgb/mac-projector-switch/issues) or pull request. Include the macOS version, Mac chip, connection method and reproduction steps. Remove device UUIDs, serial numbers and personal information before sharing diagnostic output.

Run `zsh test.sh` and `zsh build.sh` after changes, and update related documentation. For display-control changes, also validate on hardware with a usable recovery screen available.

Licensed under the [MIT License](LICENSE). References consulted for the private interface behavior are listed in [IMPLEMENTATION.md](IMPLEMENTATION.md).
