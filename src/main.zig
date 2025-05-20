const gtk = @import("gtk");
const webkit = @import("webkit");
const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
pub fn main() !void {
    gtk.init();
    const window = gtk.Window.new();
    const webview = webkit.WebView.new();
    const settings = webview.getSettings() orelse return error.FailedToGetSettings;
    settings.setHardwareAccelerationPolicy(webkit.HardwareAccelerationPolicy.Never);
    settings.setEnableDeveloperExtras(true);
    const file = try std.fs.cwd().openFile("index.html", .{});
    const contents = try file.readToEndAllocOptions(std.heap.page_allocator, std.math.maxInt(usize), null, 1, 0);

    const manager = webview.getUserContentManager() orelse return error.FailedToGetUserContentManager;
    _ = manager.registerScriptMessageHandlerWithReply("mikami", null);

    manager.connect(.ScriptMessageWithReplyReceived, "mikami", &struct {
        fn f(_: *webkit.UserContentManager, v: *webkit.JSCValue, reply: *webkit.ScriptMessageReply, _: ?*anyopaque) callconv(.c) c_int {
            std.log.debug("Received message from JS: {s}  ", .{v.toString()});
            reply.value(v.getContext().newString("Hello from Zig!"));
            return 0;
        }
    }.f, null);
    webview.loadHtml(@ptrCast(contents), "/");
    window.setChild(webview.asWidget());
    window.present();
    while (true) {
        _ = gtk.mainIteration();
    }
}
