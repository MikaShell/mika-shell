# MikaShell

[English](README.md) | [简体中文](README.zh-CN.md)

**MikaShell** is a tool for building desktop components using web technologies in a Wayland desktop environment. It is inspired by the [Astal/Ags project](https://github.com/aylur/astal).

## Table of Contents

- [MikaShell](#mikashell)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
    - [Modules](#modules)
      - [Todo](#todo)
  - [Getting Started](#getting-started)
    - [Dependencies](#dependencies)
    - [Launching](#launching)
    - [Tutorial](#tutorial)
  - [Configuration](#configuration)

---

## Features

You can create components such as bars, docks, and launchers using HTML or any web front-end framework.

MikaShell implements backend functionalities that handle desktop interactions, such as notifications, system tray, and other features that native browsers can't provide. These backend interfaces are exposed to the frontend, allowing you to call them directly in HTML or JavaScript.

---

### Modules

mika-shell exposes modules to `window.mikaShell`. You can install them via npm:

```bash
# The core module is required for type hinting, even if you don't install it directly.
npm install -D @mika-shell/core
# Some modules are implemented by mika-shell itself, such as Hyprland in the extra package.
npm install @mika-shell/extra
```

Below is a list of modules that are currently implemented or partially implemented:

| Module         | Description                                         | Status                   |
| -------------- | --------------------------------------------------- | ------------------------ |
| `apps`         | Get list of installed applications; launch them     | ✅ Implemented            |
| `dock`         | Display app icons; build a dock                     | ✅ Implemented            |
| `icon`         | Access installed system icons                       | ✅ Implemented            |
| `layer/window` | Create and control layers or windows                | ✅ Implemented            |
| `libinput`     | Capture mouse/keyboard input (requires permissions) | ✅ Implemented            |
| `monitor`      | Get information about connected monitors            | ✅ Implemented            |
| `notifd`       | Access notification system                          | ✅ Implemented            |
| `os`           | Get system and user information                     | ✅ Implemented            |
| `tray`         | Build a system tray                                 | ✅ Implemented            |
| `network`      | NetworkManager-related APIs                         | ⚠️ Partially Implemented |

#### Todo

- [ ] powerprofile
- [ ] bluetooth
- [ ] pam
- [ ] locksession
- [~] network
  - [ ] Event handling
- [ ] mpris
- [ ] battery
- [ ] cava
- [ ] wireplumber
- [ ] wayland

---

## Getting Started

### Dependencies

You can refer to [this section](https://github.com/MikaShell/mika-shell/blob/db1586e803b8df7f093aacb772c419162adf8408/.github/workflows/build.yaml#L18C11-L18C13) to see required packages for Ubuntu. In general, you only need to install packages starting with `lib`.

---

### Launching

You can download a prebuilt binary from the [Releases page](https://github.com/MikaShell/mika-shell/releases/), or build it from source.
The `mika-shell-debug` version provides more verbose logging for debugging purposes.

For Nix users, you can launch it with:

```bash
nix run github:MikaShell/mika-shell#packages.x86_64-linux.default -- daemon
```

Run `mika-shell daemon` to start the service. The first time it runs, it will generate default configuration files in `~/.config/mika-shell`.
If everything works properly, you should see a bar appear at the top of your screen.

---

### Tutorial

Please check out [Website](https://mikashell.github.io/) and [Example](https://github.com/MikaShell/mika-shell/tree/main/example)!

Additionally, here is my configuration that you can use directly or refer to: [Mikami](https://github.com/HumXC/mikami)

---

## Configuration

Configuration and resource files are stored by default in `$HOME/.config/mika-shell/`.
You can override this with the `-c` command line flag or the `MIKASHELL_CONFIG_DIR` environment variable.
The main configuration file is `mika-shell.json`, and other frontend resource files are located in the same directory.

```jsonc
{
    "name": "Example",
    "description": "This is an example mika-shell configuration file",
    "pages": [
        // Declare frontend pages here. The `name` must be unique.
        // You can check the current list of pages using the `mika-shell pages` command.
        // The `path` points to the frontend page.
        {
            "name": "index",
            "description": "This is the main page",
            "path": "/index.html" // or '/'
        },
        {
            "name": "tray",
            "path": "/#/tray"
        },
        {
            "name": "bongocat",
            "path": "/bongocat.html"
        }
    ],
    // Pages listed in the `startup` array will open automatically when MikaShell launches.
    "startup": ["bar", "bongocat"]
}
```
