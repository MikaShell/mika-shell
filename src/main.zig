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
    const window = gtk.Window.new();
    const webview = webkit.WebView.new();
    const settings = webview.getSettings() orelse return error.FailedToGetSettings;
    settings.setHardwareAccelerationPolicy(webkit.HardwareAccelerationPolicy.Never);
    settings.setEnableDeveloperExtras(true);

    const manager = webview.getUserContentManager() orelse return error.FailedToGetUserContentManager;
    _ = manager.registerScriptMessageHandlerWithReply("mikami", null);

    manager.connect(.ScriptMessageWithReplyReceived, "mikami", &struct {
        fn f(_: *webkit.UserContentManager, v: *webkit.JSCValue, reply: *webkit.ScriptMessageReply, _: ?*anyopaque) callconv(.c) c_int {
            std.log.debug("Received message from JS: {s}  ", .{v.toString()});
            reply.value(v.getContext().newString("Hello from Zig!"));
            return 0;
        }
    }.f, null);
    webview.loadUri("http://localhost:6797/");
    window.setChild(webview.asWidget());
    window.present();
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
