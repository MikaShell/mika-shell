const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var app = try gtk.Application.init(allocator, "com.github.HumXC.mikami");
    defer app.deinit();
    app.onActivate = struct {
        fn f(app_: *gtk.Application) void {
            const url = "https://www.google.com";
            _ = webkit.createWebview(app_, url);
        }
    }.f;
    const state = app.run();
    std.log.info("Application exited with code {d}", .{state});
}
