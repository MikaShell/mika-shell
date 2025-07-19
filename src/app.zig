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
    allocator: Allocator,
    name: []const u8,
    type: WebviewType,
    options: union {
        window: WindowOptions,
        layer: LayerOptions,
    },
    impl: *webkit.WebView,
    container: *gtk.Window,
    _modules: *Modules,
    // FIXME: 鼠标在窗口中移动时会占用大量CPU资源
    pub fn init(allocator: Allocator, m: *Modules, name: []const u8) !*Webview {
        const w = try allocator.create(Webview);
        w.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
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
                wv._modules.call(method.?.string, value, &result) catch |err| blk: {
                    if (result.err != null) break :blk;
                    const msg = std.fmt.allocPrint(alc, "Failed to call method {s}: {s}", .{ method.?.string, @errorName(err) }) catch unreachable;
                    defer alc.free(msg);
                    reply.errorMessage(msg);
                    return 0;
                };
                if (result.err) |msg| {
                    reply.errorMessage(msg);
                } else {
                    reply.value(result.toJSCValue(v.getContext()));
                }
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
    pub fn close(self: *Webview) void {
        const id = self.impl.getPageId();
        self.emitEvent(events.Mika.tryClose, id);
    }
    pub fn show(self: *Webview) void {
        if (self.container.asWidget().getVisible()) {
            self.forceShow();
            return;
        }
        const id = self.impl.getPageId();
        self.emitEvent(events.Mika.tryShow, id);
    }
    pub fn hide(self: *Webview) void {
        if (!self.container.asWidget().getVisible()) return;
        const id = self.impl.getPageId();
        self.emitEvent(events.Mika.tryHide, id);
    }
    pub fn forceClose(self: *Webview) void {
        self.allocator.free(self.name);
        self.container.destroy();
        self.allocator.destroy(self);
    }
    pub fn forceShow(self: *Webview) void {
        // 对于 Layer 类型的 Webview, 在不可见的情况下使用 present() 可能会导致窗口大小异常
        // 所以先判断是否可见再调用 present()
        if (self.container.asWidget().getVisible()) {
            self.container.present();
        } else {
            self.container.asWidget().show();
        }
    }
    pub fn forceHide(self: *Webview) void {
        self.container.asWidget().hide();
    }
};
const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
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
const Monitor = @import("modules/monitor.zig").Monitor;
const Notifd = @import("modules/notifd.zig").Notifd;
const Network = @import("modules/network.zig").Network;
pub const Error = error{
    WebviewNotExists,
};
pub const Config = struct {
    const Page = struct {
        name: []const u8,
        path: []const u8,
        description: ?[]const u8 = null,
    };
    name: []const u8,
    description: ?[]const u8 = null,
    pages: []Page = &.{},
    startup: [][]const u8 = &.{},
    pub fn load(allocator: Allocator, configDir: []const u8) !Config {
        const config_path = try std.fs.path.join(allocator, &.{ configDir, "mika-shell.json" });
        defer allocator.free(config_path);
        const file = try std.fs.openFileAbsolute(config_path, .{});
        defer file.close();
        const configJson = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(configJson);
        const cfgJson = try std.json.parseFromSlice(Config, allocator, configJson, .{});
        defer cfgJson.deinit();
        var cfg: Config = undefined;
        cfg.name = try allocator.dupe(u8, cfgJson.value.name);
        cfg.description = if (cfgJson.value.description) |desc| try allocator.dupe(u8, desc) else null;
        cfg.pages = try allocator.alloc(Page, cfgJson.value.pages.len);
        for (cfg.pages, 0..) |*page, i| {
            const page_ = cfgJson.value.pages[i];
            page.* = Page{
                .name = try allocator.dupe(u8, page_.name),
                .path = try allocator.dupe(u8, page_.path),
                .description = if (page_.description) |desc| try allocator.dupe(u8, desc) else null,
            };
        }

        cfg.startup = try allocator.alloc([]const u8, cfgJson.value.startup.len);
        for (cfg.startup, 0..) |*p, i| {
            const s = cfgJson.value.startup[i];
            p.* = try allocator.dupe(u8, s);
        }
        return cfg;
    }
    pub fn deinit(self: Config, allocator: Allocator) void {
        for (self.pages) |page| {
            allocator.free(page.name);
            allocator.free(page.path);
            if (page.description) |desc| allocator.free(desc);
        }
        allocator.free(self.pages);
        if (self.description) |desc| allocator.free(desc);
        for (self.startup) |p| allocator.free(p);
        allocator.free(self.startup);
        allocator.free(self.name);
    }
};
pub const App = struct {
    modules: *Modules,
    webviews: std.ArrayList(*Webview),
    allocator: Allocator,
    config: Config,
    sessionBus: *dbus.Bus,
    systemBus: *dbus.Bus,
    sessionBusWatcher: dbus.GLibWatch,
    systemBusWatcher: dbus.GLibWatch,
    mika: *Mika,
    window: *Window,
    layer: *Layer,
    tray: *Tray,
    icon: *Icon,
    os: *OS,
    apps: *Apps,
    monitor: *Monitor,
    notifd: *Notifd,
    network: *Network,
    pub fn init(allocator: Allocator, configDir: []const u8) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);
        app.config = try Config.load(allocator, configDir);
        errdefer app.config.deinit(allocator);
        app.modules = Modules.init(allocator);
        app.webviews = std.ArrayList(*Webview).init(allocator);
        app.allocator = allocator;
        const sessionBus = dbus.Bus.init(allocator, .Session) catch {
            @panic("can not connect to session dbus");
        };
        const systemBus = dbus.Bus.init(allocator, .System) catch {
            @panic("can not connect to system dbus");
        };
        app.sessionBus = sessionBus;
        app.systemBus = systemBus;
        app.sessionBusWatcher = dbus.withGLibLoop(sessionBus) catch {
            @panic("can not watch session dbus loop");
        };
        app.systemBusWatcher = dbus.withGLibLoop(systemBus) catch {
            @panic("can not watch system dbus loop");
        };

        const mika = try allocator.create(Mika);
        const window = try allocator.create(Window);
        const layer = try allocator.create(Layer);
        const icon = try allocator.create(Icon);
        const os = try allocator.create(OS);
        const apps = try allocator.create(Apps);
        const monitor = try allocator.create(Monitor);

        mika.* = Mika{ .app = app };
        window.* = Window{ .app = app };
        layer.* = Layer{ .app = app };
        icon.* = Icon{};
        os.* = OS{ .allocator = allocator };
        apps.* = Apps{ .allocator = allocator };
        monitor.* = Monitor{ .allocator = allocator };

        const tray = try Tray.init(allocator, app, sessionBus);
        const notifd = try Notifd.init(allocator, app, sessionBus);
        const network = try Network.init(allocator, systemBus);

        app.mika = mika;
        app.window = window;
        app.layer = layer;
        app.tray = tray;
        app.icon = icon;
        app.os = os;
        app.apps = apps;
        app.monitor = monitor;
        app.notifd = notifd;
        app.network = network;

        const modules = app.modules;

        modules.register(mika, "mika.open", Mika.open);
        modules.register(mika, "mika.close", Mika.close);
        modules.register(mika, "mika.show", Mika.show);
        modules.register(mika, "mika.hide", Mika.hide);
        modules.register(mika, "mika.forceClose", Mika.forceClose);
        modules.register(mika, "mika.forceShow", Mika.forceShow);
        modules.register(mika, "mika.forceHide", Mika.forceHide);

        modules.register(window, "window.init", Window.init);
        modules.register(window, "window.show", Window.show);
        modules.register(window, "window.hide", Window.hide);
        modules.register(window, "window.getId", Window.getId);
        modules.register(window, "window.openDevTools", Window.openDevTools);
        modules.register(window, "window.setTitle", Window.setTitle);

        modules.register(layer, "layer.init", Layer.init);
        modules.register(layer, "layer.getId", Layer.getId);
        modules.register(layer, "layer.show", Layer.show);
        modules.register(layer, "layer.hide", Layer.hide);
        modules.register(layer, "layer.close", Layer.close);
        modules.register(layer, "lsyer.openDevTools", Layer.openDevTools);
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
        modules.register(os, "os.getSystemInfo", OS.getSystemInfo);
        modules.register(os, "os.getUserInfo", OS.getUserInfo);
        modules.register(os, "os.exec", OS.exec);

        modules.register(apps, "apps.list", Apps.list);
        modules.register(apps, "apps.activate", Apps.activate);

        modules.register(monitor, "monitor.list", Monitor.list);

        modules.register(notifd, "notifd.subscribe", Notifd.subscribe);
        modules.register(notifd, "notifd.unsubscribe", Notifd.unsubscribe);
        modules.register(notifd, "notifd.get", Notifd.get);
        modules.register(notifd, "notifd.dismiss", Notifd.dismiss);
        modules.register(notifd, "notifd.activate", Notifd.activate);
        modules.register(notifd, "notifd.getAll", Notifd.getAll);
        modules.register(notifd, "notifd.setDontDisturb", Notifd.setDontDisturb);

        modules.register(network, "network.getDevices", Network.getDevices);
        modules.register(network, "network.getState", Network.getState);
        modules.register(network, "network.isEnabled", Network.isEnabled);
        modules.register(network, "network.enable", Network.enable);
        modules.register(network, "network.disable", Network.disable);
        modules.register(network, "network.getConnections", Network.getConnections);
        modules.register(network, "network.getPrimaryConnection", Network.getPrimaryConnection);
        modules.register(network, "network.getActiveConnections", Network.getActiveConnections);
        modules.register(network, "network.getWirelessPsk", Network.getWirelessPsk);
        modules.register(network, "network.activateConnection", Network.activateConnection);
        modules.register(network, "network.deactivateConnection", Network.deactivateConnection);
        modules.register(network, "network.checkConnectivity", Network.checkConnectivity);
        modules.register(network, "network.getWirelessAccessPoints", Network.getWirelessAccessPoints);
        modules.register(network, "network.getWirelessActiveAccessPoint", Network.getWirelessActiveAccessPoint);
        modules.register(network, "network.wirelessRequestScan", Network.wirelessRequestScan);

        for (app.config.startup) |startup| {
            _ = try app.open(startup);
        }
        return app;
    }
    pub fn deinit(self: *App) void {
        for (self.webviews.items) |webview| webview.close();
        self.sessionBusWatcher.deinit();
        self.systemBusWatcher.deinit();

        self.webviews.deinit();
        self.modules.deinit();

        self.tray.deinit();
        self.notifd.deinit();
        self.network.deinit();

        self.sessionBus.deinit();
        self.systemBus.deinit();

        self.apps.deinit();

        self.config.deinit(self.allocator);

        self.allocator.destroy(self.mika);
        self.allocator.destroy(self.window);
        self.allocator.destroy(self.layer);
        self.allocator.destroy(self.icon);
        self.allocator.destroy(self.os);
        self.allocator.destroy(self.apps);
        self.allocator.destroy(self.monitor);
        self.allocator.destroy(self);
    }
    pub fn open(self: *App, pageName: []const u8) !*Webview {
        for (self.config.pages) |page| {
            if (std.mem.eql(u8, page.name, pageName)) {
                const uri = std.fs.path.join(self.allocator, &.{ "http://localhost:6797", page.path }) catch unreachable;
                return self.openS(uri, pageName);
            }
        }
        return error.PageNotFound;
    }
    fn openS(self: *App, uri: []const u8, name: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules, name) catch unreachable;
        webview.impl.loadUri(uri);
        self.webviews.append(webview) catch unreachable;
        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.free();
        cssProvider.loadFromString("window {background-color: transparent;}");
        webview.container.asWidget().getStyleContext().addCssProvider(cssProvider);
        webview.container.connect(.closeRequest, struct {
            fn f(w: *gtk.Window, data: ?*anyopaque) callconv(.c) c_int {
                const wb = w.asWidget().getFirstChild().?.as(webkit.WebView);
                const a: *App = @ptrCast(@alignCast(data));
                const targetID = wb.getPageId();
                const target = a.getWebview(targetID) catch unreachable;
                target.emitEvent(events.Mika.tryClose, targetID);
                return 1;
            }
        }.f, self);
        webview.impl.asWidget().connect(.destroy, &struct {
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
                a.emitEvent(events.Mika.close, targetID);
            }
        }.f, self);
        webview.container.asWidget().connect(.show, struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const wb = w.getFirstChild().?.as(webkit.WebView);
                const a: *App = @ptrCast(@alignCast(data));
                const targetID = wb.getPageId();
                const target = a.getWebview(targetID) catch unreachable;
                target.emitEvent(events.Mika.show, targetID);
            }
        }.f, self);
        webview.container.asWidget().connect(.hide, struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const wb = w.getFirstChild().?.as(webkit.WebView);
                const a: *App = @ptrCast(@alignCast(data));
                const targetID = wb.getPageId();
                const target = a.getWebview(targetID) catch unreachable;
                target.emitEvent(events.Mika.hide, targetID);
            }
        }.f, self);
        const info = webview.getInfo();
        self.emitEventIgnore(info.id, events.Mika.open, info);
        return webview;
    }
    pub fn getWebview(self: *App, id: u64) !*Webview {
        for (self.webviews.items) |webview| {
            if (webview.impl.getPageId() == id) {
                return webview;
            }
        }
        return Error.WebviewNotExists;
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
};
// 查找 $XDG_CONFIG_HOME/mika-shell $HOME/.config/mika-shell
pub fn getConfigDir(allocator: Allocator) ![]const u8 {
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
