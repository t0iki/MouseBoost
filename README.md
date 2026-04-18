# MouseBoost

A command-line tool for macOS that lets you set pointer speed per input device — including devices like Magic Mouse, where macOS provides no built-in per-device control.

It runs as a user-level daemon that hooks into the HID event stream and scales cursor movement for configured devices, without touching the global tracking speed.

## Requirements

- macOS 12 or later
- Swift 5.9+ toolchain (Xcode Command Line Tools)
- Accessibility permission (required for event tap)

## Build & Install

```bash
swift build -c release
# (optional) put it on PATH
ln -sf "$(pwd)/.build/release/mouseboost" ~/.local/bin/mouseboost
```

## Usage

### 1. List connected mice

```bash
mouseboost list
```

Find the Vendor ID and Product ID of the device you want to scale.

### 2. Configure per-device speed

```bash
mouseboost set --vendor-id 0x004C --product-id 0x0269 --speed 2.0
```

- `--speed 1.0` → native speed (no-op)
- `--speed 2.0` → twice as fast
- `--speed 0.5` → half as fast

Settings are persisted to `~/.config/mouseboost/config.json`.

```bash
mouseboost show           # show current config
mouseboost remove -v <vid> -p <pid>
```

### 3. Grant Accessibility permission

```bash
mouseboost daemon --request-permission
```

Then go to **System Settings → Privacy & Security → Accessibility** and turn on the `mouseboost` entry. If it is not listed, add the binary (use the absolute path from `which mouseboost` or the `.build/release/mouseboost` under the project).

### 4. Run the daemon

Foreground (for testing):

```bash
mouseboost daemon          # add -v for verbose logs on stderr
```

Auto-start at login (LaunchAgent):

```bash
mouseboost install         # register ~/Library/LaunchAgents/com.mouseboost.daemon.plist
mouseboost status          # check running state & recent log
mouseboost uninstall       # stop & remove
```

Logs are written to `~/Library/Logs/mouseboost.log`.

### Live reload

The daemon polls `~/.config/mouseboost/config.json` once per second. Running `mouseboost set` / `remove` takes effect within ~1 second without restarting the daemon.

## How it works

- `list` uses the public `IOHIDManager` API to enumerate HID mice.
- `daemon` installs a `CGEventTap` at `.cghidEventTap`. For each mouse move event:
  - Read the sender's IORegistry Entry ID from CGEvent field 87.
  - Resolve it to a Vendor/Product ID via `IOServiceGetMatchingService`.
  - If the device has a configured multiplier, call `CGWarpMouseCursorPosition` to warp the cursor by the extra amount `rawDelta × (speed − 1)` on top of the native movement. The net cursor movement becomes `rawDelta × speed`.

This approach works uniformly for traditional USB/Bluetooth mice and for multitouch devices like Magic Mouse, which do not honor HID-level pointer-acceleration properties.

## Limitations

- Scroll speed is not scaled (only cursor movement).
- Acceleration curve is not modified; we only rescale the resulting delta.
- Binary path is baked into the LaunchAgent plist at `install` time. If you move or clean `.build/`, run `mouseboost uninstall && mouseboost install` again, or copy the binary to a stable location (e.g., `/usr/local/bin`) and install from there.
