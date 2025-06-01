const std = @import("std");
const gtk = @import("gtk");
const assets = @import("assets.zig");
const app = @import("app.zig");
const ipc = @import("ipc.zig");
const cli = @import("zig-cli");
var config = struct {
    open: struct {
        uri: []const u8 = undefined,
    } = undefined,
    show: struct {
        id: u64 = undefined,
        force: bool = false,
    } = undefined,
    hide: struct {
        id: u64 = undefined,
    } = undefined,
    close: struct {
        id: u64 = undefined,
    } = undefined,
}{};
fn cmdDaemon(_: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "daemon",
        .description = .{
            .one_line = "run mikami as a daemon",
        },
        .target = .{
            .action = .{ .exec = daemon },
        },
    };
}
fn cmdOpen(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "open",
        .description = .{
            .one_line = "open a webview with a URI",
        },
        .target = .{
            .action = .{
                .exec = open,
                .positional_args = cli.PositionalArgs{
                    .required = try r.allocPositionalArgs(&.{
                        .{
                            .name = "URI",
                            .help = "URI to open",
                            .value_ref = r.mkRef(&config.open.uri),
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
pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var rr = try cli.AppRunner.init(allocator);
    const r = &rr;
    defer {
        allocator.free(config.open.uri);
    }
    const cliApp = cli.App{
        .command = .{
            .name = "mikami",
            .target = .{
                .subcommands = try r.allocCommands(&.{
                    try cmdDaemon(r),
                    try cmdOpen(r),
                    try cmdList(r),
                    try cmdShow(r),
                    try cmdHide(r),
                    try cmdClose(r),
                }),
            },
        },
        .version = "0.0.1",
        .author = "HumXC",
    };
    return r.run(&cliApp);
}

pub fn daemon() !void {
    gtk.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const app_ = app.App.init(allocator);
    defer app_.deinit();

    _ = app_.open("http://localhost:6797/");

    const baseConfigDir = try app.getConfigDir(allocator);
    std.log.debug("ConfigDir: {s}", .{baseConfigDir});
    var assetsserver = try assets.Server.init(allocator, baseConfigDir);
    defer {
        assetsserver.stop();
        assetsserver.deinit();
    }

    _ = try assetsserver.start();

    const ipcServer = try ipc.Server.init(allocator, app_);
    defer ipcServer.deinit();
    try ipcServer.listen();

    while (true) {
        _ = gtk.mainIteration();
    }
}
fn open() !void {
    try ipc.request(.{
        .type = "open",
        .uri = config.open.uri,
    });
}
fn list() !void {
    try ipc.request(.{
        .type = "list",
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
    });
}
fn close() !void {
    try ipc.request(.{
        .type = "close",
        .id = config.close.id,
    });
}
