const std = @import("std");
const webkit = @import("webkit");
const gtk = @import("gtk");
const events = @import("events.zig");
pub const WebviewType = enum {
    None,
    Window,
    Layer,
};
pub const WindowOptions = struct {};
pub const LayerOptions = struct {};
pub const Webview = struct {
    const Info = struct {
        type: []const u8,
        id: u64,
        uri: []const u8,
    };
    allocator: std.mem.Allocator,
    type: WebviewType,
    options: union {
        window: WindowOptions,
        layer: LayerOptions,
    },
    impl: *webkit.WebView,
    container: *gtk.Window,
    _modules: *Modules,
    // FIXME: 鼠标在窗口中移动时会占用大量CPU资源
    pub fn init(allocator: std.mem.Allocator, m: *Modules) !*Webview {
        const w = try allocator.create(Webview);
        w.* = .{
            .allocator = allocator,
            .impl = webkit.WebView.new(),
            .container = gtk.Window.new(),
            ._modules = m,
            .options = .{ .window = .{} },
            .type = .None,
        };
        const settings = w.impl.getSettings() orelse return error.FailedToGetSettings;
        settings.setEnableDeveloperExtras(true);
        const manager = w.impl.getUserContentManager() orelse return error.FailedToGetUserContentManager;
        _ = manager.registerScriptMessageHandlerWithReply("mikaShell", null);
        manager.addScript(@embedFile("bindings.js"));
        manager.connect(.ScriptMessageWithReplyReceived, "mikaShell", &struct {
            fn f(_: *webkit.UserContentManager, v: *webkit.JSCValue, reply: *webkit.ScriptMessageReply, data: ?*anyopaque) callconv(.c) c_int {
                const alc = std.heap.page_allocator;
                const wv: *Webview = @ptrCast(@alignCast(data));
                const request = std.json.parseFromSlice(std.json.Value, alc, v.toJson(0), .{}) catch unreachable;
                defer request.deinit();
                var result = Result.init(alc);
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
                args.append(std.json.Value{ .integer = @intCast(wv.impl.getPageId()) }) catch unreachable;
                args.appendSlice(origin_args.?.array.items) catch unreachable;
                const value = Args{
                    .items = args.items,
                };
                std.log.debug("Received message from JS: [{d}] {s}  ", .{ wv.impl.getPageId(), v.toJson(0) });
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
        w.container.setChild(w.impl.asWidget());
        return w;
    }
    pub fn emitEvent(self: *Webview, name: []const u8, data: anytype) void {
        const alc = std.heap.page_allocator;
        const dataJson = std.json.stringifyAlloc(alc, data, .{}) catch unreachable;
        defer alc.free(dataJson);
        const js = std.fmt.allocPrint(alc, "window.dispatchEvent(new CustomEvent('mika-shell-event', {{ detail: {{ name: '{s}', data: {s} }} }}));", .{ name, dataJson }) catch unreachable;
        defer alc.free(js);
        self.impl.evaluateJavaScript(js);
    }
    pub fn getInfo(self: *Webview) Info {
        return Info{
            .type = switch (self.type) {
                .None => "none",
                .Window => "window",
                .Layer => "layer",
            },
            .id = self.impl.getPageId(),
            .uri = self.impl.getUri(),
        };
    }
    pub fn show(self: *Webview) void {
        self.container.present();
    }
    pub fn hide(self: *Webview) void {
        self.container.asWidget().hide();
    }
    pub fn close(self: *Webview) void {
        self.container.destroy();
        self.allocator.destroy(self);
    }
};
const dbus = @import("dbus");
const Modules = @import("modules/modules.zig").Modules;
const Result = @import("modules/modules.zig").Result;
const Args = @import("modules/modules.zig").Args;
const Mika = @import("modules/mika.zig").Mika;
const Layer = @import("modules/layer.zig").Layer;
const Window = @import("modules/window.zig").Window;
const Tray = @import("modules/tray.zig").Tray;
const Icon = @import("modules/icon.zig").Icon;
const OS = @import("modules/os.zig").OS;
const Apps = @import("modules/apps.zig").Apps;
pub const Error = error{
    WebviewNotExists,
};
pub const App = struct {
    modules: *Modules,
    webviews: std.ArrayList(*Webview),
    allocator: std.mem.Allocator,
    bus: *dbus.Bus,
    busWatcher: dbus.GLibWatch,
    mika: *Mika,
    window: *Window,
    layer: *Layer,
    tray: *Tray,
    icon: *Icon,
    os: *OS,
    apps: *Apps,
    pub fn init(allocator: std.mem.Allocator) *App {
        const app = allocator.create(App) catch unreachable;
        app.modules = Modules.init(allocator);
        app.webviews = std.ArrayList(*Webview).init(allocator);
        app.allocator = allocator;
        const bus = dbus.Bus.init(allocator, .Session) catch {
            @panic("can not connect to dbus");
        };
        app.bus = bus;
        app.busWatcher = dbus.withGLibLoop(bus) catch {
            @panic("can not watch dbus loop");
        };
        const mika = allocator.create(Mika) catch unreachable;
        const window = allocator.create(Window) catch unreachable;
        const layer = allocator.create(Layer) catch unreachable;
        const icon = allocator.create(Icon) catch unreachable;
        const os = allocator.create(OS) catch unreachable;
        const apps = allocator.create(Apps) catch unreachable;

        mika.* = Mika{ .app = app };
        window.* = Window{ .app = app };
        layer.* = Layer{ .app = app };
        icon.* = Icon{};
        os.* = OS{};
        apps.* = Apps{ .allocator = allocator };

        const tray = Tray.init(allocator, app, bus) catch unreachable;

        app.mika = mika;
        app.window = window;
        app.layer = layer;
        app.tray = tray;
        app.icon = icon;
        app.os = os;
        app.apps = apps;

        const modules = app.modules;

        modules.register(mika, "mika.open", Mika.open);

        modules.register(window, "window.init", Window.init);
        modules.register(window, "window.show", Window.show);
        modules.register(window, "window.hide", Window.hide);

        modules.register(layer, "layer.init", Layer.init);
        modules.register(layer, "layer.show", Layer.show);
        modules.register(layer, "layer.hide", Layer.hide);
        modules.register(layer, "layer.resetAnchor", Layer.resetAnchor);
        modules.register(layer, "layer.setAnchor", Layer.setAnchor);
        modules.register(layer, "layer.setLayer", Layer.setLayer);
        modules.register(layer, "layer.setKeyboardMode", Layer.setKeyboardMode);
        modules.register(layer, "layer.setNamespace", Layer.setNamespace);
        modules.register(layer, "layer.setMargin", Layer.setMargin);
        modules.register(layer, "layer.setExclusiveZone", Layer.setExclusiveZone);
        modules.register(layer, "layer.autoExclusiveZoneEnable", Layer.autoExclusiveZoneEnable);

        modules.register(tray, "tray.getItem", Tray.getItem);
        modules.register(tray, "tray.getItems", Tray.getItems);
        modules.register(tray, "tray.subscribe", Tray.subscribe);
        modules.register(tray, "tray.unsubscribe", Tray.unsubscribe);
        modules.register(tray, "tray.activate", Tray.activate);
        modules.register(tray, "tray.secondaryActivate", Tray.secondaryActivate);
        modules.register(tray, "tray.scroll", Tray.scroll);
        modules.register(tray, "tray.provideXdgActivationToken", Tray.provideXdgActivationToken);
        modules.register(tray, "tray.getMenu", Tray.getMenu);
        modules.register(tray, "tray.activateMenu", Tray.activateMenu);

        modules.register(icon, "icon.lookup", Icon.lookup);

        modules.register(os, "os.getEnv", OS.getEnv);

        modules.register(apps, "apps.list", Apps.list);
        modules.register(apps, "apps.activate", Apps.activate);
        return app;
    }
    pub fn deinit(self: *App) void {
        for (self.webviews.items) |webview| webview.close();
        self.busWatcher.deinit();

        self.webviews.deinit();
        self.modules.deinit();

        self.tray.deinit();
        self.bus.deinit();

        self.allocator.destroy(self.mika);
        self.allocator.destroy(self.window);
        self.allocator.destroy(self.layer);
        self.allocator.destroy(self.icon);
        self.allocator.destroy(self.os);
        self.allocator.destroy(self.apps);
        self.allocator.destroy(self);
    }
    pub fn open(self: *App, uri: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules) catch unreachable;
        webview.impl.loadUri(uri);
        self.webviews.append(webview) catch unreachable;
        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.free();
        cssProvider.loadFromString("window {background-color: transparent;}");
        webview.container.asWidget().getStyleContext().addCssProvider(cssProvider);

        webview.impl.asWidget().connect(.Destroy, &struct {
            fn f(widget: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const target: *webkit.WebView = @ptrCast(widget);
                const a: *App = @ptrCast(@alignCast(data));
                const targetID = target.getPageId();
                for (a.webviews.items, 0..a.webviews.items.len) |w, i| {
                    if (w.impl.getPageId() == targetID) {
                        _ = a.webviews.orderedRemove(i);
                        break;
                    }
                }
            }
        }.f, self);
        const info = webview.getInfo();
        self.emitEventIgnore(info.id, events.Mika.Open, info);
        return webview;
    }
    pub fn getWebview(self: *App, id: u64) ?*Webview {
        for (self.webviews.items) |webview| {
            if (webview.impl.getPageId() == id) {
                return webview;
            }
        }
        return null;
    }
    /// 发送事件，忽略指定 id 的 webview
    pub fn emitEventIgnore(self: *App, ignore: u64, name: []const u8, data: anytype) void {
        for (self.webviews.items) |webview| {
            if (webview.impl.getPageId() == ignore) {
                continue;
            }
            webview.emitEvent(name, data);
        }
    }
    /// 向所有 webview 发送事件
    pub fn emitEvent(self: *App, name: []const u8, data: anytype) void {
        for (self.webviews.items) |webview| {
            webview.emitEvent(name, data);
        }
    }
    pub fn show(self: *App, id: u64) !void {
        const webview = self.getWebview(id) orelse return Error.WebviewNotExists;
        webview.show();
        const info = webview.getInfo();
        self.emitEventIgnore(id, events.Mika.Show, info);
    }
    pub fn hide(self: *App, id: u64) !void {
        const webview = self.getWebview(id) orelse return Error.WebviewNotExists;
        webview.hide();
        const info = webview.getInfo();
        self.emitEventIgnore(id, events.Mika.Hide, info);
    }
    pub fn close(self: *App, id: u64) !void {
        const webview = self.getWebview(id) orelse return Error.WebviewNotExists;
        webview.close();
        const info = webview.getInfo();
        self.emitEventIgnore(id, events.Mika.Close, info);
    }
};
// 查找 $XDG_CONFIG_HOME/mika-shell $HOME/.config/mika-shell
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    var baseConfigDir: []const u8 = undefined;
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    const join = std.fs.path.join;
    if (env.get("XDG_CONFIG_HOME")) |xdg_config_home| {
        baseConfigDir = xdg_config_home;
    } else if (env.get("HOME")) |home| {
        baseConfigDir = try join(allocator, &.{ home, ".config" });
    } else {
        return error.NoConfigDir;
    }
    defer allocator.free(baseConfigDir);
    return try join(allocator, &.{ baseConfigDir, "mika-shell" });
}
