const std = @import("std");
const gtk = @import("gtk");
const zglib = @import("zglib");
const webkit = @import("webkit");
const g = @import("gobject");
const jsc = @import("jsc");
const events = @import("events.zig");
const glib = @import("zglib");
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
    impl: *webkit.WebView,
    container: *gtk.Window,
    _modules: *Modules,
    // FIXME: 鼠标在窗口中移动时会占用大量CPU资源
    pub fn init(allocator: Allocator, m: *Modules, name: []const u8, backendPort: u16) !*Webview {
        const w = try allocator.create(Webview);
        idCount += 1;
        w.* = .{
            .id = @intCast(idCount),
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .impl = webkit.WebView.new(),
            .container = gtk.Window.new(),
            ._modules = m,
            .type = .None,
        };
        const settings = w.impl.getSettings();
        settings.setEnableDeveloperExtras(1);
        const manager = w.impl.getUserContentManager();
        _ = manager.registerScriptMessageHandlerWithReply("mikaShell", null);

        const bindingsScript = webkit.UserScript.new(@embedFile("bindings.js"), .all_frames, .start, null, null);
        defer bindingsScript.unref();
        manager.addScript(bindingsScript);
        const setPortJs = std.fmt.allocPrintZ(allocator, "window.mikaShell.backendPort = {d};", .{backendPort}) catch unreachable;
        defer allocator.free(setPortJs);
        const setPortScript = webkit.UserScript.new(setPortJs, .all_frames, .start, null, null);
        defer setPortScript.unref();
        manager.addScript(setPortScript);
        _ = g.signalConnectData(manager.as(g.Object), "script-message-with-reply-received::mikaShell", @ptrCast(&struct {
            fn f(_: *webkit.UserContentManager, v: *jsc.Value, reply: *webkit.ScriptMessageReply, data: ?*anyopaque) callconv(.c) c_int {
                const alc = std.heap.page_allocator;
                const wv: *Webview = @ptrCast(@alignCast(data));
                const jsonValue = v.toJson(0);
                defer glib.free(jsonValue);
                const request = std.json.parseFromSlice(std.json.Value, alc, std.mem.span(jsonValue), .{}) catch unreachable;
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
                    reply.returnErrorMessage("Invalid request");
                    return 0;
                }
                switch (method.?) {
                    .string => {},
                    else => {
                        reply.returnErrorMessage("Invalid request method");
                        return 0;
                    },
                }
                switch (origin_args.?) {
                    .array => {},
                    else => {
                        reply.returnErrorMessage("Invalid request args");
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
                    const msg = std.fmt.allocPrintZ(alc, "Failed to call method {s}: {s}", .{ method.?.string, @errorName(err) }) catch unreachable;
                    defer alc.free(msg);
                    reply.returnErrorMessage(msg);
                    return 0;
                };
                if (result.err) |msg| {
                    // TODO: 将 msg 的来源全部改成 [:0]const u8
                    const msg_ = alc.dupeZ(u8, msg) catch unreachable;
                    defer alc.free(msg_);
                    reply.returnErrorMessage(msg_);
                } else {
                    const val = result.toJSCValue(v.getContext());
                    defer val.unref();
                    reply.returnValue(val);
                }
                return 0;
            }
        }.f), w, null, .flags_default);
        w.container.setChild(w.impl.as(gtk.Widget));
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
            .uri = std.mem.span(self.impl.getUri()),
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
        const w = self.container.as(gtk.Widget);
        if (w.getVisible() == 1) {
            self.container.present();
        } else {
            w.show();
        }
    }
    pub fn forceHide(self: *Webview) void {
        self.container.as(gtk.Widget).hide();
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
    alias: std.StringHashMap([]const u8),
    startup: [][]const u8 = &.{},
    pub fn load(allocator: Allocator, configDir: []const u8, devServer: ?[]const u8) !*Config {
        const configJson = blk: {
            if (devServer) |ds| {
                const config_path = try std.fs.path.join(allocator, &.{ ds, "mika-shell.json" });
                defer allocator.free(config_path);
                var client = std.http.Client{ .allocator = allocator };
                defer client.deinit();
                var store = std.ArrayList(u8).init(allocator);
                errdefer store.deinit();
                const result = try client.fetch(.{
                    .location = .{ .url = config_path },
                    .response_storage = .{ .dynamic = &store },
                });
                if (result.status != .ok) {
                    return error.FailedToFetchConfig;
                }
                break :blk try store.toOwnedSlice();
            } else {
                const config_path = try std.fs.path.join(allocator, &.{ configDir, "mika-shell.json" });
                defer allocator.free(config_path);
                const file = try std.fs.openFileAbsolute(config_path, .{});
                defer file.close();
                break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
            }
        };
        defer allocator.free(configJson);
        const cfgJson = try std.json.parseFromSlice(std.json.Value, allocator, configJson, .{});
        defer cfgJson.deinit();
        const value = cfgJson.value.object;
        const cfg = try allocator.create(Config);
        errdefer allocator.destroy(cfg);
        cfg.alias = std.StringHashMap([]const u8).init(allocator);
        if (value.get("alias")) |alias_| {
            const alias__ = alias_.object;
            var it = alias__.iterator();
            while (it.next()) |kv| {
                const key = kv.key_ptr.*;
                const val = switch (kv.value_ptr.*) {
                    .string => |v| v,
                    else => {
                        @panic("invalid alias value type, expected string");
                    },
                };
                try cfg.alias.put(try allocator.dupe(u8, key), try allocator.dupe(u8, val));
            }
        }
        var startup = std.ArrayList([]const u8).init(allocator);
        if (value.get("startup")) |startup_| {
            const startup__ = startup_.array;
            for (startup__.items) |item| {
                switch (item) {
                    .string => |v| try startup.append(try allocator.dupe(u8, v)),
                    else => {
                        @panic("invalid startup value type, expected string");
                    },
                }
            }
        }
        cfg.startup = try startup.toOwnedSlice();

        return cfg;
    }
    pub fn deinit(self: *Config, allocator: Allocator) void {
        var it = self.alias.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.*);
        }
        self.alias.deinit();
        for (self.startup) |p| allocator.free(p);
        allocator.free(self.startup);
        allocator.destroy(self);
    }
};
pub const App = struct {
    modules: *Modules,
    mutex: std.Thread.Mutex,
    isQuit: bool,
    webviews: std.ArrayList(*Webview),
    allocator: Allocator,
    config: *Config,
    configDir: []const u8,
    sessionBus: *dbus.Bus,
    systemBus: *dbus.Bus,
    sessionBusWatcher: dbus.GLibWatch,
    systemBusWatcher: dbus.GLibWatch,
    emitter: *Emitter,
    devServer: ?[]const u8,
    server: []const u8,
    port: u16,
    pub fn init(allocator: Allocator, configDir: []const u8, eventChannel: *events.EventChannel, devServer: ?[]const u8, port: u16) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);
        app.config = Config.load(allocator, configDir, devServer) catch |err| {
            std.log.err("Failed to load config 'mika-shell.json' from {s}", .{if (devServer != null) devServer.? else configDir});
            return err;
        };
        errdefer app.config.deinit(allocator);
        app.server = try std.fmt.allocPrint(allocator, "http://localhost:{d}/", .{port});
        errdefer allocator.free(app.server);
        app.port = port;
        app.configDir = try std.fs.path.resolve(allocator, &.{configDir});
        app.mutex = std.Thread.Mutex{};
        app.webviews = std.ArrayList(*Webview).init(allocator);
        app.allocator = allocator;
        app.isQuit = false;
        app.devServer = if (devServer) |ds| try allocator.dupe(u8, ds) else null;
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
        if (self.devServer) |ds| self.allocator.free(ds);
        self.emitter.deinit();
        self.allocator.free(self.server);
        self.allocator.destroy(self);
    }
    pub fn open(self: *App, pageName: []const u8) !*Webview {
        const server = if (self.devServer) |ds| ds else self.server;
        const path = blk: {
            if (std.mem.startsWith(u8, pageName, "/")) {
                break :blk pageName;
            } else {
                if (self.config.alias.get(pageName)) |alias| break :blk alias;
                break :blk pageName;
            }
        };
        const url = std.fs.path.join(self.allocator, &.{ server, path }) catch unreachable;
        defer self.allocator.free(url);
        return self.openS(url, pageName);
    }
    fn openS(self: *App, uri: []const u8, name: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules, name, self.port) catch unreachable;
        const uri_ = self.allocator.dupeZ(u8, uri) catch unreachable;
        defer self.allocator.free(uri_);
        webview.impl.loadUri(uri_);
        self.mutex.lock();
        self.webviews.append(webview) catch unreachable;
        self.mutex.unlock();

        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.unref();
        cssProvider.loadFromString("window {background-color: transparent;}");
        const contianer = webview.container.as(gtk.Widget);
        contianer.getStyleContext().addProvider(cssProvider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        _ = g.signalConnectData(contianer.as(g.Object), "close-request", @ptrCast(&struct {
            fn f(w: *gtk.Window, data: ?*anyopaque) callconv(.c) c_int {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w.as(gtk.Widget));
                const id = wb.id;
                a.emitEvent2(wb, .mika_close_request, id);
                return 1;
            }
        }.f), self, null, .flags_default);

        _ = g.signalConnectData(contianer.as(g.Object), "destroy", @ptrCast(&struct {
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
        }.f), self, null, .flags_default);

        _ = g.signalConnectData(contianer.as(g.Object), "show", @ptrCast(&struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w);
                a.emitEvent2(null, .mika_show, wb.id);
            }
        }.f), self, null, .flags_default);
        _ = g.signalConnectData(contianer.as(g.Object), "hide", @ptrCast(&struct {
            fn f(w: *gtk.Widget, data: ?*anyopaque) callconv(.c) void {
                const a: *App = @ptrCast(@alignCast(data));
                const wb = a.getWebview2(w);
                a.emitEvent2(null, .mika_hide, wb.id);
            }
        }.f), self, null, .flags_default);
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
            if (webview.container.as(gtk.Widget) == widget or webview.impl.as(gtk.Widget) == widget) {
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
        const js = std.fmt.allocPrintZ(alc, "window.dispatchEvent(new CustomEvent('mika-shell-event', {{ detail: {{ event: {d}, data: {s} }} }}));", .{ @intFromEnum(event), dataJson }) catch unreachable;
        defer alc.free(js);
        if (dist) |w| {
            w.impl.evaluateJavascript(js, @intCast(js.len), null, null, null, null, null);
        } else {
            for (self.webviews.items) |w| {
                w.impl.evaluateJavascript(js, @intCast(js.len), null, null, null, null, null);
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
    return try std.fs.path.resolve(allocator, &.{ baseConfigDir, "mika-shell" });
}
