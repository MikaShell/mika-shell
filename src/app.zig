const std = @import("std");
const webkit = @import("webkit");
const gtk = @import("gtk");
pub const WebviewType = enum {
    None,
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
            .type = .None,
        };
        const settings = w._webview.getSettings() orelse return error.FailedToGetSettings;
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
                std.log.debug("Received message from JS: [{d}] {s}  ", .{ wv._webview.getPageId(), v.toJson(0) });
                wv._modules.call(method.?.string, value, &result) catch |err| {
                    const msg = std.fmt.allocPrint(alc, "Failed to call method {s}: {s}", .{ method.?.string, @errorName(err) }) catch unreachable;
                    defer alc.free(msg);
                    reply.errorMessage(msg);
                    return 0;
                };
                reply.value(result.toJSCValue(v.getContext()));
                return 0;
            }
        }.f, w);
        w._webview_container.setChild(w._webview.asWidget());
        return w;
    }
    pub fn emitEvent(self: *Webview, name: []const u8, data: anytype) void {
        const alc = std.heap.page_allocator;
        const dataJson = std.json.stringifyAlloc(alc, data, .{}) catch unreachable;
        defer alc.free(dataJson);
        const js = std.fmt.allocPrint(alc, "window.dispatchEvent(new CustomEvent('{s}', {{ detail: {s} }}));", .{ name, dataJson }) catch unreachable;
        defer alc.free(js);
        self._webview.evaluateJavaScript(js);
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
const mikami_ = @import("modules/mikami.zig");
const layer_ = @import("modules/layer.zig");
const window_ = @import("modules/window.zig");

pub const App = struct {
    modules: *modules_.Modules,
    webviews: std.ArrayList(*Webview),
    allocator: std.mem.Allocator,

    mikami: *mikami_.Mikami,
    window: *window_.Window,
    layer: *layer_.Layer,
    pub fn init(allocator: std.mem.Allocator) *App {
        const app = allocator.create(App) catch unreachable;
        app.* = .{
            .modules = modules_.Modules.init(allocator),
            .webviews = std.ArrayList(*Webview).init(allocator),
            .allocator = allocator,
            .mikami = undefined,
            .window = undefined,
            .layer = undefined,
        };
        const mikami = allocator.create(mikami_.Mikami) catch unreachable;
        const window = allocator.create(window_.Window) catch unreachable;
        const layer = allocator.create(layer_.Layer) catch unreachable;
        mikami.* = mikami_.Mikami{ .app = app };
        window.* = window_.Window{ .app = app };
        layer.* = layer_.Layer{ .app = app };

        app.mikami = mikami;
        app.window = window;
        app.layer = layer;

        app.modules.register(mikami, "mikami.open", &mikami_.Mikami.open) catch unreachable;

        app.modules.register(window, "window.init", &window_.Window.init) catch unreachable;
        app.modules.register(window, "window.show", &window_.Window.show) catch unreachable;
        app.modules.register(window, "window.hide", &window_.Window.hide) catch unreachable;

        app.modules.register(layer, "layer.init", &layer_.Layer.init) catch unreachable;
        app.modules.register(layer, "layer.show", &layer_.Layer.show) catch unreachable;
        app.modules.register(layer, "layer.hide", &layer_.Layer.hide) catch unreachable;
        app.modules.register(layer, "layer.resetAnchor", &layer_.Layer.resetAnchor) catch unreachable;
        app.modules.register(layer, "layer.setAnchor", &layer_.Layer.setAnchor) catch unreachable;
        app.modules.register(layer, "layer.setLayer", &layer_.Layer.setLayer) catch unreachable;
        app.modules.register(layer, "layer.setKeyboardMode", &layer_.Layer.setKeyboardMode) catch unreachable;
        app.modules.register(layer, "layer.setNamespace", &layer_.Layer.setNamespace) catch unreachable;
        app.modules.register(layer, "layer.setMargin", &layer_.Layer.setMargin) catch unreachable;
        app.modules.register(layer, "layer.setExclusiveZone", &layer_.Layer.setExclusiveZone) catch unreachable;
        app.modules.register(layer, "layer.autoExclusiveZoneEnable", &layer_.Layer.autoExclusiveZoneEnable) catch unreachable;

        return app;
    }
    pub fn deinit(self: *App) void {
        for (self.webviews.items) |webview| {
            webview.destroy();
        }
        self.webviews.deinit();
        self.modules.deinit();

        self.allocator.destroy(self.mikami);
        self.allocator.destroy(self.window);
        self.allocator.destroy(self.layer);
        self.allocator.destroy(self);
    }
    pub fn createWebview(self: *App, uri: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules) catch unreachable;
        webview._webview.loadUri(uri);
        self.webviews.append(webview) catch unreachable;
        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.free();
        cssProvider.loadFromString("window {background-color: transparent;}");
        webview._webview_container.asWidget().getStyleContext().addCssProvider(cssProvider);

        webview._webview.asWidget().connect(.Destroy, &struct {
            fn f(widget: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const target: *webkit.WebView = @ptrCast(widget);
                const a: *App = @ptrCast(@alignCast(data));
                const targetID = target.getPageId();
                for (a.webviews.items, 0..a.webviews.items.len) |w, i| {
                    if (w._webview.getPageId() == targetID) {
                        _ = a.webviews.orderedRemove(i);
                        break;
                    }
                }
            }
        }.f, self);

        return webview;
    }
    pub fn getWebview(self: *App, id: u64) ?*Webview {
        for (self.webviews.items) |webview| {
            if (webview._webview.getPageId() == id) {
                return webview;
            }
        }
        return null;
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
