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
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ switch (scope) {
        .my_project, .nice_library, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

test {
    _ = @import("modules.zig");
    _ = @import("lib/tray.zig");
    _ = @import("lib/notifd.zig");
    _ = @import("lib/network.zig");
    _ = @import("modules/modules.zig");
    _ = @import("modules/apps.zig");
    _ = @import("modules/icon.zig");
    _ = @import("modules/layer.zig");
    _ = @import("modules/os.zig");
    _ = @import("modules/tray.zig");
    _ = @import("modules/window.zig");
}
