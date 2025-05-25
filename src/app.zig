const std = @import("std");
const webkit = @import("webkit");
const gtk = @import("gtk");
pub const WebviewType = enum {
    Window,
    Layer,
};
pub const WindowOptions = struct {};
pub const LayerOptions = struct {};
pub const Webview = struct {
    type: WebviewType,
    options: union {
        window: WindowOptions,
        layer: LayerOptions,
    },
    _webview: *webkit.WebView,
    _webview_container: *gtk.Window,
    pub fn init() !Webview {
        const window = gtk.Window.new();
        const webview = webkit.WebView.new();
        const settings = webview.getSettings() orelse return error.FailedToGetSettings;
        settings.setHardwareAccelerationPolicy(webkit.HardwareAccelerationPolicy.Never);
        settings.setEnableDeveloperExtras(true);

        const manager = webview.getUserContentManager() orelse return error.FailedToGetUserContentManager;
        _ = manager.registerScriptMessageHandlerWithReply("mikami", null);

        manager.connect(.ScriptMessageWithReplyReceived, "mikami", &struct {
            fn f(_: *webkit.UserContentManager, v: *webkit.JSCValue, reply: *webkit.ScriptMessageReply, data: ?*anyopaque) callconv(.c) c_int {
                const webview_: *webkit.WebView = @ptrCast(@alignCast(data));
                std.log.debug("Received message from JS: [{d}] {s}  ", .{ webview_.getPageId(), v.toString() });
                reply.value(v.getContext().newString("Hello from Zig!"));
                return 0;
            }
        }.f, webview);
        webview.loadUri("http://localhost:6797/");
        window.setChild(webview.asWidget());
        return .{
            ._webview = webview,
            ._webview_container = window,
            .options = .{ .window = .{} },
            .type = .Window,
        };
    }
    // pub fn makeWindow(self: *Webview, options: WindowOptions) void {}
    // pub fn makeLayer(self: *Webview, options: LayerOptions) void {}
    pub fn show(self: *Webview) void {
        self._webview_container.present();
    }
    pub fn hide(self: *Webview) void {
        self._webview_container.asWidget().hide();
    }
    pub fn destroy(self: *Webview) void {
        self._webview_container.destroy();
    }
};
pub const App = struct {
    webviews: std.ArrayList(*Webview),
    // pub fn createWebview(self: *App, uri: []const u8) !*Webview {}
};
// 查找 $XDG_CONFIG_HOME/mikami $HOME/.config/mikami
pub fn getConfigDir(allocator: std.mem.Allocator) ![]u8 {
    var baseConfigDir: [*:0]u8 = undefined;
    for (std.os.environ) |env| {
        if (std.mem.startsWith(u8, std.mem.sliceTo(env, 0), "XDG_CONFIG_HOME=")) {
            baseConfigDir = env[15..];
            break;
        } else if (std.mem.startsWith(u8, std.mem.sliceTo(env, 0), "HOME=")) {
            baseConfigDir = env[5..];
            break;
        }
    }
    return try std.fs.path.join(allocator, &[_][]const u8{ std.mem.sliceTo(baseConfigDir, 0), "mikami" });
}
