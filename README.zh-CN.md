# MikaShell

[English](README.md) | [简体中文](README.zh-CN.md)

**MikaShell** 是一个在 Wayland 桌面环境下使用 web 技术构建桌面组件的工具。灵感来自 [https://github.com/aylur/astal](Astal/Ags) 项目。

## 目录

* [特性](#特性)
* [模块](#模块)
* [开始](#开始)
  * [依赖](#依赖)
  * [启动](#启动)
  * [教程](#教程)
* [配置](#配置)

---

## 特性

你可以使用 html 或者任意的 web 前端框架来实现组件，可以实现诸如 bar, dock, launcher 等组件。

mika-shell 在后端实现了一系列与桌面交互的部分，例如'通知服务'，'系统托盘'等原生浏览器无法实现的部分，并将其接口暴露到前端。你只需要在 html 或者 js 代码中调用即可

---

### 模块

mika-shell 将模块暴露到 window.mikaShell 中，我还编写了 npm 包用于从前端调用模块以实现类型提示，但是该项目还在前期开发阶段，npm 包还没有发布，你可以使用仓库中的 build-npm.sh 脚本来构建 npm 包。

以下是目前已经实现或者部分实现的模块

| 模块        | 功能描述                             | 实现状态     |
|-------------|--------------------------------------|--------------|
| `apps`      | 获取系统安装应用列表，启动应用       | ✅ 已实现    |
| `dock`      | 显示应用图标，构建 Dock              | ✅ 已实现    |
| `icon`      | 获取系统中安装的图标                 | ✅ 已实现    |
| `layer/window` | 创建和控制 Layer 或窗口           | ✅ 已实现    |
| `libinput`  | 获取鼠标和键盘输入（需要权限）        | ✅ 已实现    |
| `monitor`   | 获取系统显示器信息                   | ✅ 已实现    |
| `notifd`    | 通知系统接口                         | ✅ 已实现    |
| `os`        | 获取系统信息、用户信息               | ✅ 已实现    |
| `tray`      | 构建系统托盘                         | ✅ 已实现    |
| `network`   | NetworkManager 相关接口              | ⚠️ 部分实现 |

#### Todo

* [ ]powerprofile
* [ ]bluetooth
* [ ]pam
* [ ]locksession
* [~]network
  * [ ]实现相关事件
* [ ]mpris
* [ ]battery
* [ ]cava
* [ ]wireplumber
* [ ]wayland

---

## 开始

### 依赖

你可以查看 [此处](https://github.com/HumXC/mika-shell/blob/db1586e803b8df7f093aacb772c419162adf8408/.github/workflows/build.yaml#L18C11-L18C13) 来获取 Ubuntu 环境下的依赖。一般来说只需要安装 lib 开头的包

---

### 启动

你可以从 [Release 页面](https://github.com/HumXC/mika-shell/releases/) 下载预编译的二进制文件，也可以自己编译
`mika-shell-debug` 是调试版本，可以看到更多的日志信息。

对于 Nix 用户， 可以使用 `nix run github:HumXC/mika-shell#packages.x86_64-linux.default -- daemon`

运行 `mika-shell daemon` 启动，第一次运行会在 `~/.config/mika-shell` 目录下生成初始配置文件。如果一切正常，你应该会看见顶部出现一个 bar。

---

### 教程

教程/Wiki 尚未准备好 ~~（还没开始写）~~ ，但是你可以看 [Example](https://github.com/HumXC/mika-shell/tree/main/example)!

---

## 配置

配置文件和资源文件默认存放在 `$HOME/.config/mika-shell/` 中，可以使用命令行 `-c` 或者环境变量 `MIKASHELL_CONFIG_DIR` 来更改。配置文件 `mika-shell.json` 存放在其中，文件夹中的其他文件是前端资源。

    ```json
    {
        "name": "Example",
        "description": "This is an example mika-shell configuration file",
        "pages": [
            // 在这里声明前端拥有的页面，name 由你决定，但是必须唯一。你可以使用 `mika-shell pages` 命令来查看当前的页面列表。
            // path 是前端页面的路径。
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
        // 在 startup 数组中声明的页面会在 mika-shell 启动时自动打开。
        "startup": ["bar", "bongocat"]
    }

    ```
