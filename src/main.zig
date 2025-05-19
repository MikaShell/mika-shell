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

    const context = webkit.Context.getDefault();
    context.?.registerUriScheme("mikami", struct {
        fn f(req: ?*webkit.URISchemeRequest, _: *anyopaque) callconv(.C) void {
            std.log.debug("mikami scheme called: {s}", .{req.?.getUri()});
        }
    }.f, null, null);

    webview.loadHtml(@ptrCast(contents), "/");
    window.setChild(webview.asWidget());
    window.present();
    while (true) {
        _ = gtk.mainIteration();
    }
}
