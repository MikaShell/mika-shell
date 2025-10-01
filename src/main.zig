const cli = @import("cli.zig");
const std = @import("std");
pub fn main() !void {
    return cli.run();
}

pub const std_options: std.Options = .{
    .log_level = switch (@import("builtin").mode) {
        .Debug => .debug,
        .ReleaseSafe,
        .ReleaseFast,
        .ReleaseSmall,
        => .info,
    },
    .logFn = logFn,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(std.options.log_level)) return;
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const reset = "\x1b[0m";

    const prefix = switch (level) {
        .debug => blue,
        .info => green,
        .err => red,
        .warn => yellow,
    } ++ "[" ++ comptime level.asText() ++ "]" ++ reset ++ " " ++ scope_prefix;

    var buf: [64]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

test {
    _ = @import("events.zig");
    _ = @import("utils.zig");
    _ = @import("lib/tray.zig");
    _ = @import("lib/notifd.zig");
    _ = @import("lib/network.zig");
    _ = @import("modules/apps.zig");
    _ = @import("modules/icon.zig");
    _ = @import("modules/layer.zig");
    _ = @import("modules/os.zig");
    _ = @import("modules/tray.zig");
    _ = @import("modules/window.zig");
}
