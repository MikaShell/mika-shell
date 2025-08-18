const std = @import("std");
const gtk = @import("gtk");
const assets = @import("assets.zig");
const App = @import("app.zig").App;
const getConfigDir = @import("app.zig").getConfigDir;
const ipc = @import("ipc.zig");
const cli = @import("cli");
var config = struct {
    daemon: struct {
        config_dir: []const u8 = undefined,
        dev_server: ?[]const u8 = null,
    } = undefined,
    open: struct {
        pageName: []const u8 = undefined,
    } = undefined,
    show: struct {
        id: u64 = undefined,
        force: bool = false,
    } = undefined,
    hide: struct {
        id: u64 = undefined,
        force: bool = false,
    } = undefined,
    close: struct {
        id: u64 = undefined,
        force: bool = false,
    } = undefined,
}{};
fn cmdDaemon(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "daemon",
        .description = .{
            .one_line = "run mika-shell as a daemon",
        },
        .options = try r.allocOptions(&.{
            .{
                .long_name = "config-dir",
                .short_alias = 'c',
                .help = "directory to store configuration files, defaults to $XDG_CONFIG_HOME/mika-shell or $HOME/.config/mika-shell",
                // This was defined but never used. Consider using app.getConfigDir instead.
                .value_ref = r.mkRef(&config.daemon.config_dir),
                .envvar = "MIKASHELL_CONFIG_DIR",
            },
            .{
                .long_name = "dev-server",
                .short_alias = 'd',
                .help = "url to use for development, defaults to null",
                .value_ref = r.mkRef(&config.daemon.dev_server),
                .envvar = "MIKASHELL_DEV_SERVER",
            },
        }),
        .target = .{
            .action = .{ .exec = daemon },
        },
    };
}
fn cmdOpen(r: *cli.AppRunner) !cli.Command {
    defer allocator.free(config.open.pageName);
    return cli.Command{
        .name = "open",
        .description = .{
            .one_line = "Open a webview with the page name",
        },
        .target = .{
            .action = .{
                .exec = open,
                .positional_args = cli.PositionalArgs{
                    .required = try r.allocPositionalArgs(&.{
                        .{
                            .name = "page",
                            .help = "page name to open, defined in `mika-shell.json`, use `mika-shell pages` to list all pages",
                            .value_ref = r.mkRef(&config.open.pageName),
                        },
                    }),
                },
            },
        },
    };
}
fn cmdList(_: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "list",
        .description = .{
            .one_line = "list all open webviews",
        },
        .target = .{ .action = .{ .exec = list } },
    };
}
fn cmdPages(_: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "pages",
        .description = .{
            .one_line = "list all pages can be opened",
        },
        .target = .{ .action = .{ .exec = pages } },
    };
}
fn cmdAbout(_: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "about",
        .description = .{
            .one_line = "display details of the current configuration",
        },
        .target = .{ .action = .{ .exec = about } },
    };
}
fn cmdShow(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "show",
        .description = .{
            .one_line = "show the webview",
        },
        .options = try r.allocOptions(&.{.{
            .long_name = "force",
            .short_alias = 'f',
            .help = "force show the webview",
            .value_ref = r.mkRef(&config.show.force),
        }}),
        .target = .{
            .action = .{
                .exec = show,
                .positional_args = cli.PositionalArgs{
                    .required = try r.allocPositionalArgs(&.{
                        .{
                            .name = "ID",
                            .help = "ID of the webview to show",
                            .value_ref = r.mkRef(&config.show.id),
                        },
                    }),
                },
            },
        },
    };
}
fn cmdHide(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "hide",
        .description = .{
            .one_line = "hide the webview",
        },
        .options = try r.allocOptions(&.{.{
            .long_name = "force",
            .short_alias = 'f',
            .help = "force hide the webview",
            .value_ref = r.mkRef(&config.show.force),
        }}),
        .target = .{
            .action = .{
                .exec = hide,
                .positional_args = cli.PositionalArgs{
                    .required = try r.allocPositionalArgs(&.{
                        .{
                            .name = "ID",
                            .help = "ID of the webview to hide",
                            .value_ref = r.mkRef(&config.hide.id),
                        },
                    }),
                },
            },
        },
    };
}
fn cmdClose(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "close",
        .description = .{
            .one_line = "close the webview",
        },
        .options = try r.allocOptions(&.{.{
            .long_name = "force",
            .short_alias = 'f',
            .help = "force close the webview",
            .value_ref = r.mkRef(&config.close.force),
        }}),
        .target = .{
            .action = .{
                .exec = close,
                .positional_args = cli.PositionalArgs{
                    .required = try r.allocPositionalArgs(&.{
                        .{
                            .name = "ID",
                            .help = "ID of the webview to close",
                            .value_ref = r.mkRef(&config.close.id),
                        },
                    }),
                },
            },
        },
    };
}
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn run() !void {
    defer _ = gpa.deinit();
    var rr = try cli.AppRunner.init(allocator);
    const r = &rr;
    const cliApp = cli.App{
        .command = .{
            .name = "mika-shell",
            .target = .{
                .subcommands = try r.allocCommands(&.{
                    try cmdDaemon(r),
                    try cmdOpen(r),
                    try cmdList(r),
                    try cmdShow(r),
                    try cmdHide(r),
                    try cmdClose(r),
                    try cmdPages(r),
                    try cmdAbout(r),
                }),
            },
        },
        .version = "0.0.1",
        .author = "HumXC",
    };
    return r.run(&cliApp);
}
const wayland = @import("wayland");
const events = @import("events.zig");
pub fn daemon() !void {
    gtk.init();
    defer allocator.free(config.daemon.config_dir);
    defer if (config.daemon.dev_server) |ds| allocator.free(ds);
    const configDir = blk: {
        if (config.daemon.config_dir.len > 0) {
            const absPath = abs: {
                if (std.fs.path.isAbsolute(config.daemon.config_dir)) {
                    break :abs try allocator.dupe(u8, config.daemon.config_dir);
                }
                const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
                defer allocator.free(cwd);
                break :abs try std.fs.path.join(allocator, &.{ cwd, config.daemon.config_dir });
            };
            defer allocator.free(absPath);
            break :blk try std.fs.path.resolve(allocator, &.{absPath});
        } else {
            break :blk try getConfigDir(allocator);
        }
    };
    defer allocator.free(configDir);
    std.log.info("ConfigDir: {s}", .{configDir});
    blk: {
        if (config.daemon.dev_server != null) break :blk;
        var err: ?anyerror = null;
        if (std.fs.path.isAbsolute(configDir)) {
            std.fs.accessAbsolute(configDir, .{}) catch |e| {
                err = e;
            };
        } else {
            std.fs.cwd().access(configDir, .{}) catch |e| {
                err = e;
            };
        }
        if (err) |e| switch (e) {
            error.FileNotFound => {
                try @import("example").write(configDir);
            },
            else => return e,
        };
    }
    var eventChannel = try events.EventChannel.init();
    defer eventChannel.deinit();

    var assetsserver = try assets.Server.init(allocator, configDir, &eventChannel);
    defer {
        assetsserver.stop();
        assetsserver.deinit();
    }
    _ = try assetsserver.start();

    const app = try App.init(allocator, configDir, &eventChannel, config.daemon.dev_server);
    defer app.deinit();

    try wayland.init(allocator);
    const watch = try wayland.withGLib();
    defer watch.deinit();

    const ipcServer = try ipc.Server.init(allocator, app);
    defer ipcServer.deinit();
    try ipcServer.listen();

    while (true) {
        _ = glib.mainIteration();
    }
}
const glib = @import("glib");

fn open() !void {
    defer allocator.free(config.open.pageName);
    try ipc.request(.{
        .type = "open",
        .pageName = config.open.pageName,
    });
}
fn list() !void {
    try ipc.request(.{
        .type = "list",
    });
}
fn pages() !void {
    try ipc.request(.{
        .type = "pages",
    });
}
fn about() !void {
    try ipc.request(.{
        .type = "about",
    });
}
fn show() !void {
    try ipc.request(.{
        .type = "show",
        .id = config.show.id,
        .force = config.show.force,
    });
}
fn hide() !void {
    try ipc.request(.{
        .type = "hide",
        .id = config.hide.id,
        .force = config.hide.force,
    });
}
fn close() !void {
    try ipc.request(.{
        .type = "close",
        .id = config.close.id,
        .force = config.close.force,
    });
}
