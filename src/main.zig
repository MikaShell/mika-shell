const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const assets = @import("assets.zig");
const app = @import("app.zig");
pub fn main() !void {
    gtk.init();
    var w = try app.Webview.init();
    w.show();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
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
