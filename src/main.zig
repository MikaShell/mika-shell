const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
const assets = @import("assets.zig");
const app = @import("app.zig");
const layershell = @import("layershell");
pub fn main() !void {
    gtk.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const app_ = app.App.init(allocator);
    _ = app_.createWebview("http://localhost:6797/");
    const baseConfigDir = try app.getConfigDir(allocator);
    std.log.debug("ConfigDir: {s}", .{baseConfigDir});
    var server = try assets.Server.init(allocator, baseConfigDir);
    defer {
        server.stop();
        server.deinit();
    }

    _ = try server.start();
    while (true) {
        _ = gtk.mainIteration();
    }
}
