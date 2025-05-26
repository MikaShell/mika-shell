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
    _modules: *modules_.Modules,
    pub fn init(allocator: std.mem.Allocator, m: *modules_.Modules) !*Webview {
        const w = try allocator.create(Webview);
        w.* = .{
            ._webview = webkit.WebView.new(),
            ._webview_container = gtk.Window.new(),
            ._modules = m,
            .options = .{ .window = .{} },
            .type = .Window,
        };
        const settings = w._webview.getSettings() orelse return error.FailedToGetSettings;
        settings.setHardwareAccelerationPolicy(webkit.HardwareAccelerationPolicy.Never);
        settings.setEnableDeveloperExtras(true);
        const manager = w._webview.getUserContentManager() orelse return error.FailedToGetUserContentManager;
        _ = manager.registerScriptMessageHandlerWithReply("mikami", null);

        manager.connect(.ScriptMessageWithReplyReceived, "mikami", &struct {
            fn f(_: *webkit.UserContentManager, v: *webkit.JSCValue, reply: *webkit.ScriptMessageReply, data: ?*anyopaque) callconv(.c) c_int {
                const alc = std.heap.page_allocator;
                const wv: *Webview = @ptrCast(@alignCast(data));
                const request = std.json.parseFromSlice(std.json.Value, alc, v.toJson(0), .{}) catch unreachable;
                defer request.deinit();
                var result = modules_.Result.init(alc);
                defer result.deinit();

                // {
                //     "method": "test",
                //     "args": [...]
                // }

                const method = request.value.object.get("method");
                const origin_args = request.value.object.get("args");
                if (method == null or origin_args == null) {
                    reply.errorMessage("Invalid request");
                    return 0;
                }
                switch (method.?) {
                    .string => {},
                    else => {
                        reply.errorMessage("Invalid request method");
                        return 0;
                    },
                }
                switch (origin_args.?) {
                    .array => {},
                    else => {
                        reply.errorMessage("Invalid request args");
                        return 0;
                    },
                }
                var args = std.ArrayList(std.json.Value).init(alc);
                defer args.deinit();
                args.append(std.json.Value{ .integer = @intCast(wv._webview.getPageId()) }) catch unreachable;
                args.appendSlice(origin_args.?.array.items) catch unreachable;
                const value = modules_.Args{
                    .items = args.items,
                };
                wv._modules.call(method.?.string, value, &result) catch |err| {
                    const msg = std.fmt.allocPrint(alc, "Failed to call method {s}: {s}", .{ method.?.string, @errorName(err) }) catch unreachable;
                    defer alc.free(msg);
                    const msgZ = alc.dupeZ(u8, msg) catch unreachable;
                    defer alc.free(msgZ);
                    reply.errorMessage(msgZ);
                };
                std.log.debug("Received message from JS: [{d}] {s}  ", .{ wv._webview.getPageId(), v.toJson(0) });
                reply.value(result.toJSCValue(v.getContext()));
                return 0;
            }
        }.f, w);
        w._webview_container.setChild(w._webview.asWidget());
        return w;
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
const modules_ = @import("modules/modules.zig");
const mikami = @import("modules/mikami.zig");
pub const App = struct {
    modules: *modules_.Modules,
    webviews: std.ArrayList(*Webview),
    registerModules: std.ArrayList(*anyopaque),
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) *App {
        const app = allocator.create(App) catch unreachable;
        app.* = .{
            .modules = modules_.Modules.init(allocator),
            .webviews = std.ArrayList(*Webview).init(allocator),
            .registerModules = std.ArrayList(*anyopaque).init(allocator),
            .allocator = allocator,
        };
        const mikami_ = allocator.create(mikami.Mikami) catch unreachable;
        mikami_.* = mikami.Mikami{
            .app = app,
        };

        app.modules.register(mikami_, "mikami.open", &mikami.Mikami.open) catch unreachable;
        app.modules.register(mikami_, "mikami.show", &mikami.Mikami.show) catch unreachable;
        app.registerModules.append(mikami_) catch unreachable;
        return app;
    }
    pub fn deinit(self: *App) void {
        for (self.webviews.items) |webview| {
            webview.destroy();
        }
        self.webviews.deinit();
        for (self.registerModules) |m| {
            if (@hasDecl(m, "deinit")) {
                m.deinit();
            }
        }
    }
    pub fn createWebview(self: *App, uri: []const u8) u64 {
        const webview = Webview.init(self.allocator, self.modules) catch unreachable;
        webview._webview.loadUri(uri);
        self.webviews.append(webview) catch unreachable;
        return webview._webview.getPageId();
    }
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
