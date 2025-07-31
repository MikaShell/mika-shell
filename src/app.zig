const std = @import("std");
const webkit = @import("webkit");
const gtk = @import("gtk");
const events = @import("events.zig");
pub const WebviewType = enum {
    None,
    Window,
    Layer,
};
pub const WindowOptions = @import("./modules/window.zig").Options;
pub const LayerOptions = @import("./modules/layer.zig").Options;
var idCount: u32 = 99;
pub const Webview = struct {
    const Info = struct {
        type: []const u8,
        id: u64,
        uri: []const u8,
    };
    id: u64,
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
        idCount += 1;
        w.* = .{
            .id = @intCast(idCount),
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .impl = webkit.WebView.new(),
            .container = gtk.Window.new(),
            ._modules = m,
            .options = undefined,
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
                args.append(std.json.Value{ .integer = @intCast(wv.id) }) catch unreachable;
                args.appendSlice(origin_args.?.array.items) catch unreachable;
                const value = Args{
                    .items = args.items,
                };
                std.log.scoped(.webview).debug("Received message from JS: [{d}] {s}", .{ wv.id, v.toJson(0) });
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
    pub fn getInfo(self: *Webview) Info {
        return Info{
            .type = switch (self.type) {
                .None => "none",
                .Window => "window",
                .Layer => "layer",
            },
            .id = self.id,
            .uri = self.impl.getUri(),
        };
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
const Modules = @import("modules.zig").Modules;
const Emitter = @import("modules.zig").Emitter;
const Result = @import("modules/modules.zig").Result;
const Args = @import("modules/modules.zig").Args;
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
    mutex: std.Thread.Mutex,
    isQuit: bool = false,
    webviews: std.ArrayList(*Webview),
    allocator: Allocator,
    config: Config,
    configDir: []const u8,
    sessionBus: *dbus.Bus,
    systemBus: *dbus.Bus,
    sessionBusWatcher: dbus.GLibWatch,
    systemBusWatcher: dbus.GLibWatch,
    emitter: *Emitter,
    pub fn init(allocator: Allocator, configDir: []const u8, eventChannel: *events.EventChannel) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);
        app.config = try Config.load(allocator, configDir);
        errdefer app.config.deinit(allocator);
        app.configDir = try std.fs.path.resolve(allocator, &.{configDir});
        app.mutex = std.Thread.Mutex{};
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

        app.modules = Modules.init(allocator, app, systemBus, sessionBus);

        const modules = app.modules;

        try modules.mount(@import("modules/mika.zig").Mika, "mika");
        try modules.mount(@import("modules/window.zig").Window, "window");
        try modules.mount(@import("modules/layer.zig").Layer, "layer");
        try modules.mount(@import("modules/tray.zig").Tray, "tray");
        try modules.mount(@import("modules/icon.zig").Icon, "icon");
        try modules.mount(@import("modules/os.zig").OS, "os");
        try modules.mount(@import("modules/apps.zig").Apps, "apps");
        try modules.mount(@import("modules/monitor.zig").Monitor, "monitor");
        try modules.mount(@import("modules/notifd.zig").Notifd, "notifd");
        try modules.mount(@import("modules/network.zig").Network, "network");
        try modules.mount(@import("modules/dock.zig").Dock, "dock");
        try modules.mount(@import("modules/libinput.zig").Libinput, "libinput");

        app.emitter = try Emitter.init(app, allocator, eventChannel, modules.eventGroups.items);

        for (app.config.startup) |startup| {
            _ = try app.open(startup);
        }
        return app;
    }
    pub fn deinit(self: *App) void {
        self.isQuit = true;
        self.sessionBusWatcher.deinit();
        self.systemBusWatcher.deinit();
        for (self.webviews.items) |webview| {
            webview.forceClose();
        }
        self.webviews.deinit();
        self.modules.deinit();
        self.sessionBus.deinit();
        self.systemBus.deinit();

        self.config.deinit(self.allocator);
        self.allocator.free(self.configDir);
        self.allocator.destroy(self);
    }
    pub fn open(self: *App, pageName: []const u8) !*Webview {
        for (self.config.pages) |page| {
            if (std.mem.eql(u8, page.name, pageName)) {
                const uri = std.fs.path.join(self.allocator, &.{ "http://localhost:6797", page.path }) catch unreachable;
                defer self.allocator.free(uri);
                return self.openS(uri, pageName);
            }
        }
        return error.PageNotFound;
    }
    fn openS(self: *App, uri: []const u8, name: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules, name) catch unreachable;
        webview.impl.loadUri(uri);
        self.mutex.lock();
        self.webviews.append(webview) catch unreachable;
        self.mutex.unlock();
        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.free();
        cssProvider.loadFromString("window {background-color: transparent;}");
        webview.container.asWidget().getStyleContext().addCssProvider(cssProvider);
        webview.container.connect(.closeRequest, struct {
            fn f(w: *gtk.Window, data: ?*anyopaque) callconv(.c) c_int {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w.asWidget());
                const id = wb.id;
                a.emitEvent2(wb, .mika_close_request, id);
                return 1;
            }
        }.f, self);
        webview.container.asWidget().connect(.destroy, &struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const a: *App = @ptrCast(@alignCast(data));
                if (a.isQuit) return;
                const id = a.getWebview2(w).id;
                a.mutex.lock();
                defer a.mutex.unlock();
                for (a.webviews.items, 0..a.webviews.items.len) |w_, i| {
                    if (w_.id == id) {
                        _ = a.webviews.orderedRemove(i);
                        a.emitEvent2(null, .mika_close, id);
                        break;
                    }
                }
            }
        }.f, self);
        webview.container.asWidget().connect(.show, struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w);
                a.emitEvent2(null, .mika_show, wb.id);
            }
        }.f, self);
        webview.container.asWidget().connect(.hide, struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w);
                a.emitEvent2(null, .mika_hide, wb.id);
            }
        }.f, self);
        const info = webview.getInfo();
        self.emitEvent(.mika_open, info);
        return webview;
    }
    pub fn getWebview(self: *App, id: u64) !*Webview {
        for (self.webviews.items) |webview| {
            if (webview.id == id) {
                return webview;
            }
        }
        return Error.WebviewNotExists;
    }
    fn getWebview2(self: *App, widget: *gtk.Widget) *Webview {
        for (self.webviews.items) |webview| {
            if (webview.container.asWidget() == widget or webview.impl.asWidget() == widget) {
                return webview;
            }
        }
        unreachable;
    }
    pub fn emitEvent(self: *App, event: events.Events, data: anytype) void {
        self.emitter.emit(event, data);
    }
    pub fn emitEvent2(self: *App, dist: ?*Webview, event: events.Events, data: anytype) void {
        const alc = std.heap.page_allocator;
        const dataJson = std.json.stringifyAlloc(alc, data, .{}) catch unreachable;
        defer alc.free(dataJson);
        const js = std.fmt.allocPrint(alc, "window.dispatchEvent(new CustomEvent('mika-shell-event', {{ detail: {{ event: {d}, data: {s} }} }}));", .{ @intFromEnum(event), dataJson }) catch unreachable;
        defer alc.free(js);
        if (dist) |w| {
            w.impl.evaluateJavaScript(js);
        } else {
            for (self.webviews.items) |w| {
                w.impl.evaluateJavaScript(js);
            }
        }
    }
    pub fn showRequest(self: *App, w: *Webview) void {
        self.emitEvent2(w, .mika_show_request, w.id);
    }
    pub fn hideRequest(self: *App, w: *Webview) void {
        self.emitEvent2(w, .mika_hide_request, w.id);
    }
    pub fn closeRequest(self: *App, w: *Webview) void {
        self.emitEvent2(w, .mika_close_request, w.id);
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
