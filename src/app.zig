const std = @import("std");
const gtk = @import("gtk");
const glib = @import("glib");
const webkit = @import("webkit");
const g = @import("gobject");
const jsc = @import("jsc");
const events = @import("events.zig");
pub const WebviewType = enum {
    none,
    window,
    layer,
    popover,
};
pub const WindowOptions = @import("./modules/window.zig").Options;
pub const LayerOptions = @import("./modules/layer.zig").Options;
pub const Webview = struct {
    pub const Info = struct {
        type: []const u8,
        id: u64,
        uri: []const u8,
        alias: []const u8,
        visible: bool,
        title: []const u8,
    };
    id: u64,
    allocator: Allocator,
    name: []const u8,
    impl: *webkit.WebView,
    container: union(enum) {
        none: void,
        window: *gtk.Window,
        layer: @import("layershell").Layer,
        popover: *gtk.Popover,
        fn destroy(self: @This()) void {
            switch (self) {
                .none => {},
                .window => |w| w.destroy(),
                .layer => |l| l.inner.destroy(),
                .popover => |p| {
                    p.as(gtk.Widget).unparent();
                },
            }
        }
        fn show(self: @This()) void {
            switch (self) {
                .none => {},
                .window => |w| w.present(),
                .layer => |l| {
                    if (l.inner.as(gtk.Widget).getVisible() == 1) {
                        l.inner.present();
                    } else {
                        l.inner.as(gtk.Widget).show();
                    }
                },
                .popover => |p| {
                    p.popup();
                    p.present();
                },
            }
        }
        fn hide(self: @This()) void {
            switch (self) {
                .none => {},
                .window => |w| w.as(gtk.Widget).hide(),
                .layer => |l| l.inner.as(gtk.Widget).hide(),
                .popover => |p| p.popdown(),
            }
        }
    },
    _modules: *Modules,
    // FIXME: 鼠标在窗口中移动时会占用大量CPU资源
    pub fn init(allocator: Allocator, m: *Modules, name: []const u8, backendPort: u16, configDir: []const u8) !*Webview {
        const w = try allocator.create(Webview);
        w.* = .{
            .id = undefined,
            .impl = undefined,
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .container = .{ .none = {} },
            ._modules = m,
        };
        _ = configDir;
        // TODO: 设置存储路径之后 localStorage 不同步
        // const dataDir = try std.fs.path.joinZ(allocator, &.{ configDir, "webview_data" });
        // defer allocator.free(dataDir);
        // const cacheDir = try std.fs.path.joinZ(allocator, &.{ configDir, "webview_cache" });
        // defer allocator.free(cacheDir);
        // const networkSession = webkit.NetworkSession.getDefault();
        // w.impl = g.ext.cast(webkit.WebView, g.Object.new(
        //     webkit.WebView.getGObjectType(),
        //     "network-session",
        //     networkSession,
        //     @as(?[*:0]const u8, null),
        // )).?;
        w.impl = webkit.WebView.new();
        w.id = w.impl.getPageId();
        w.impl.getSettings().setDefaultCharset("utf-8");

        const settings = w.impl.getSettings();
        settings.setEnableDeveloperExtras(1);
        const manager = w.impl.getUserContentManager();
        _ = manager.registerScriptMessageHandlerWithReply("mikaShell", null);

        const setPropJs = std.fmt.allocPrintSentinel(allocator, "window.mikaShell = {{backendPort: {d}, id: {d}}};", .{ backendPort, w.id }, 0) catch unreachable;
        defer allocator.free(setPropJs);
        const setPortScript = webkit.UserScript.new(setPropJs, .all_frames, .start, null, null);
        defer setPortScript.unref();
        manager.addScript(setPortScript);

        const bindingsScript = webkit.UserScript.new(@embedFile("bindings.js"), .all_frames, .start, null, null);
        defer bindingsScript.unref();
        manager.addScript(bindingsScript);

        _ = g.signalConnectData(manager.as(g.Object), "script-message-with-reply-received::mikaShell", @ptrCast(&struct {
            fn f(_: *webkit.UserContentManager, v: *jsc.Value, reply: *webkit.ScriptMessageReply, wv: *Webview) callconv(.c) c_int {
                const alc = wv.allocator;

                // {
                //     "method": "test",
                //     "args": [...]
                // }

                if (v.isObject() != 1) {
                    reply.returnErrorMessage("Invalid request");
                    return 0;
                }
                const method = v.objectGetProperty("method");
                if (method.isUndefined() == 1 or method.isNull() == 1) {
                    reply.returnErrorMessage("Invalid request method");
                    return 0;
                }
                const methodStr = method.toString();
                defer glib.free(methodStr);
                const method_ = std.mem.span(methodStr);
                const args = v.objectGetProperty("args");
                defer args.unref();
                if (args.isArray() != 1) {
                    reply.returnErrorMessage("Invalid request args");
                    return 0;
                }
                const ctx = CallContext.init(alc, wv.id, method_, args, reply) catch |e| {
                    const msg = std.fmt.allocPrintSentinel(alc, "Failed to parse args: {t}", .{e}, 0) catch unreachable;
                    defer alc.free(msg);
                    reply.returnErrorMessage(msg);
                    return 0;
                };
                defer ctx.deinit();
                std.log.scoped(.webview).debug("Received message from JS: [{d}] {s}", .{ wv.id, v.toJson(0) });
                wv._modules.call(method_, ctx) catch |err| {
                    std.log.scoped(.webview).err("Failed to call method {s}: {t}", .{ method_, err });
                    if (ctx.reply != null) {
                        ctx.errors("Failed to call method {s}: {t}", .{ method_, err });
                    }
                    return 0;
                };
                // 不为 null 表示没有被回复或者被作为 async 调用
                if (ctx.reply != null) {
                    const result = jsc.Value.newUndefined(ctx.ctx);
                    defer result.unref();
                    reply.returnValue(result);
                    return 0;
                }
                return 0;
            }
        }.f), w, null, .flags_default);
        return w;
    }
    pub fn getInfo(self: *Webview) Info {
        return Info{
            .type = @tagName(self.container),
            .id = self.id,
            .uri = std.mem.span(self.impl.getUri()),
            .alias = self.name,
            .visible = switch (self.container) {
                .none => false,
                .window => |w| w.as(gtk.Widget).getVisible() == 1,
                .layer => |l| l.inner.as(gtk.Widget).getVisible() == 1,
                .popover => |p| p.as(gtk.Widget).getVisible() == 1,
            },
            .title = if (@as([*c]const u8, @ptrCast(self.impl.getTitle()))) |title| std.mem.span(title) else "",
        };
    }
    pub fn forceClose(self: *Webview) void {
        self.allocator.free(self.name);
        self.container.destroy();
        self.allocator.destroy(self); // BUG: double free?
    }
    pub fn forceShow(self: *Webview) void {
        // 对于 Layer 类型的 Webview, 在不可见的情况下使用 present() 可能会导致窗口大小异常
        // 所以先判断是否可见再调用 present()
        self.container.show();
    }
    pub fn forceHide(self: *Webview) void {
        self.container.hide();
    }
};
const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const Modules = @import("modules/root.zig").Modules;
const Emitter = @import("modules/root.zig").Emitter;
const CallContext = @import("modules/root.zig").Context;
pub const Error = error{
    WebviewNotExists,
};
pub const Config = struct {
    // host: url e.g. "dev_server": "http://localhost:5000"
    dev: std.StringHashMap([]const u8),
    // name: path e.g. "bar": "/bar.html"
    alias: std.StringHashMap([]const u8),
    startup: [][]const u8 = &.{},
    pub fn load(allocator: Allocator, configDir: []const u8) !*Config {
        const configJson = blk: {
            const config_path = try std.fs.path.join(allocator, &.{ configDir, "config.json" });
            defer allocator.free(config_path);
            const file = try std.fs.openFileAbsolute(config_path, .{});
            defer file.close();
            break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
        };
        defer allocator.free(configJson);
        const cfgJson = try std.json.parseFromSlice(std.json.Value, allocator, configJson, .{});
        defer cfgJson.deinit();
        const value = cfgJson.value.object;
        const cfg = try allocator.create(Config);
        errdefer allocator.destroy(cfg);

        // load dev object
        {
            cfg.dev = std.StringHashMap([]const u8).init(allocator);
            errdefer {
                var it = cfg.dev.iterator();
                while (it.next()) |kv| {
                    allocator.free(kv.key_ptr.*);
                    allocator.free(kv.value_ptr.*);
                }
                cfg.dev.deinit();
            }
            if (value.get("dev")) |dev_| {
                const dev__ = dev_.object;
                var it = dev__.iterator();
                while (it.next()) |kv| {
                    const key = kv.key_ptr.*;
                    const val = switch (kv.value_ptr.*) {
                        .string => |v| v,
                        else => {
                            @panic("invalid dev value type, expected string");
                        },
                    };
                    try cfg.dev.put(try allocator.dupe(u8, key), try allocator.dupe(u8, val));
                }
            }
        }
        errdefer {
            var it = cfg.dev.iterator();
            while (it.next()) |kv| {
                allocator.free(kv.key_ptr.*);
                allocator.free(kv.value_ptr.*);
            }
            cfg.dev.deinit();
        }
        // load alias object
        {
            cfg.alias = std.StringHashMap([]const u8).init(allocator);
            errdefer {
                var it = cfg.alias.iterator();
                while (it.next()) |kv| {
                    allocator.free(kv.key_ptr.*);
                    allocator.free(kv.value_ptr.*);
                }
                cfg.alias.deinit();
            }
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
                    if (key[0] == '/') {
                        std.log.err("alias key should not start with '/', key: {s}", .{key});
                        return error.InvalidAliasJson;
                    }
                    if (val[0] != '/') {
                        std.log.err("alias value should start with '/', value: {s}", .{val});
                        return error.InvalidAliasJson;
                    }
                    try cfg.alias.put(try allocator.dupe(u8, key), try allocator.dupe(u8, val));
                }
            }
            // list config dir
            var dir = try std.fs.openDirAbsolute(configDir, .{ .iterate = true });
            defer dir.close();
            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .directory) continue;
                if (std.mem.eql(u8, "webview_data", entry.name)) continue;
                if (std.mem.eql(u8, "webview_cache", entry.name)) continue;
                const sub_path = try std.fs.path.join(allocator, &.{ configDir, entry.name, "alias.json" });
                defer allocator.free(sub_path);
                const sub_alias = dir.openFile(sub_path, .{}) catch |err| {
                    if (err == error.FileNotFound) {
                        std.log.info("No alias.json in {s}/{s}, skip", .{ configDir, entry.name });
                        continue;
                    }
                    std.log.err("Failed to open alias.json in {s}: {t}", .{ configDir, err });
                    return error.FailedLoadConfig;
                };
                defer sub_alias.close();

                var buf: [1024]u8 = undefined;
                var reader = sub_alias.reader(&buf);
                parseAliasJson(allocator, &reader.interface, entry.name, &cfg.alias) catch return error.InvalidAliasJson;
            }
            // list dev serrver
            var dev_it = cfg.dev.iterator();
            while (dev_it.next()) |kv| {
                const key = kv.key_ptr.*;
                const val = kv.value_ptr.*;
                const alias_path = try std.fs.path.join(allocator, &.{ val, "alias.json" });
                defer allocator.free(alias_path);
                var client = std.http.Client{ .allocator = allocator };
                defer client.deinit();
                var result = std.Io.Writer.Allocating.init(allocator);
                defer result.deinit();
                const res = client.fetch(.{
                    .location = .{ .url = alias_path },
                    .response_writer = &result.writer,
                }) catch |err| {
                    std.log.err("Failed to fetch alias.json: {s}: {t}", .{ alias_path, err });
                    return error.FailedLoadConfig;
                };
                if (res.status != .ok) {
                    std.log.err("Failed to fetch alias.json: {s}: {t}", .{ alias_path, res.status });
                    return error.FailedLoadConfig;
                }
                var reader = std.Io.Reader.fixed(result.written());
                parseAliasJson(allocator, &reader, key, &cfg.alias) catch {
                    std.log.warn("Failed to parse alias.json in {s} ({s}), skip", .{ key, val });
                };
            }
        }
        errdefer {
            var it = cfg.alias.iterator();
            while (it.next()) |kv| {
                allocator.free(kv.key_ptr.*);
                allocator.free(kv.value_ptr.*);
            }
            cfg.alias.deinit();
        }
        var startup = std.ArrayList([]const u8){};
        errdefer startup.deinit(allocator);
        if (value.get("startup")) |startup_| {
            const startup__ = startup_.array;
            for (startup__.items) |item| {
                switch (item) {
                    .string => |v| try startup.append(allocator, try allocator.dupe(u8, v)),
                    else => {
                        @panic("invalid startup value type, expected string");
                    },
                }
            }
        }
        cfg.startup = try startup.toOwnedSlice(allocator);

        return cfg;
    }
    pub fn deinit(self: *Config, allocator: Allocator) void {
        var it = self.alias.iterator();
        while (it.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.*);
        }
        self.alias.deinit();
        var it2 = self.dev.iterator();
        while (it2.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            allocator.free(kv.value_ptr.*);
        }
        self.dev.deinit();
        for (self.startup) |p| allocator.free(p);
        allocator.free(self.startup);
        allocator.destroy(self);
    }
};
fn parseAliasJson(allocator: Allocator, reader: anytype, dir: []const u8, dist: *std.StringHashMap([]const u8)) !void {
    var reader_ = std.json.Reader.init(allocator, reader);
    defer reader_.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const sub_alias_json = std.json.Value.jsonParse(arena.allocator(), &reader_, .{ .max_value_len = 1024 * 1024 * 1024 }) catch |err| {
        std.log.err("Failed to parse alias.json in {s}: {t}", .{ dir, err });
        return err;
    };
    switch (sub_alias_json) {
        .object => {},
        else => {
            std.log.err("Invalid alias.json in {s}: expected object", .{dir});
            return error.InvalidAliasJson;
        },
    }
    const obj = sub_alias_json.object;

    var it = obj.iterator();
    while (it.next()) |kv| {
        const key = kv.key_ptr.*;
        const val = switch (kv.value_ptr.*) {
            .string => |v| v,
            else => {
                std.log.err("invalid alias value type '{t}', expected string", .{kv.value_ptr.*});
                return error.InvalidAliasJson;
            },
        };
        if (key[0] == '/') {
            std.log.err("Invalid alias.json in '{s}': key should not start with /, got '{s}'", .{ dir, key });
            return error.InvalidAliasJson;
        }
        const key_ = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ dir, key });
        const val_ = try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ dir, if (val[0] == '/') val[1..] else val });
        try dist.put(key_, val_);
    }
}
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
    server: []const u8,
    port: u16,
    pub fn init(allocator: Allocator, option: struct {
        configDir: []const u8,
        eventChannel: *events.EventChannel,
        port: u16,
    }) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);
        app.config = Config.load(allocator, option.configDir) catch |err| {
            std.log.err("Failed to load config 'config.json' from {s}", .{option.configDir});
            return err;
        };
        errdefer app.config.deinit(allocator);
        app.server = try std.fmt.allocPrint(allocator, "http://localhost:{d}/", .{option.port});
        errdefer allocator.free(app.server);
        app.port = option.port;
        app.configDir = try std.fs.path.resolve(allocator, &.{option.configDir});
        app.mutex = std.Thread.Mutex{};
        app.webviews = std.ArrayList(*Webview){};
        app.allocator = allocator;
        app.isQuit = false;
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

        app.modules = Modules.init(allocator, .{
            .app = app,
            .sessionBus = sessionBus,
            .systemBus = systemBus,
        });

        const modules = app.modules;

        try modules.mount(@import("modules/mika.zig").Mika, "mika");
        try modules.mount(@import("modules/window.zig").Window, "window");
        try modules.mount(@import("modules/layer.zig").Layer, "layer");
        try modules.mount(@import("modules/popover.zig").Popover, "popover");
        try modules.mount(@import("modules/tray.zig").Tray, "tray");
        try modules.mount(@import("modules/icon.zig").Icon, "icon");
        try modules.mount(@import("modules/os.zig").OS, "os");
        try modules.mount(@import("modules/apps.zig").Apps, "apps");
        try modules.mount(@import("modules/monitor.zig").Monitor, "monitor");
        try modules.mount(@import("modules/notifd.zig").Notifd, "notifd");
        try modules.mount(@import("modules/network.zig").Network, "network");
        try modules.mount(@import("modules/dock.zig").Dock, "dock");
        try modules.mount(@import("modules/libinput.zig").Libinput, "libinput");

        app.emitter = try Emitter.init(app, allocator, option.eventChannel, modules.eventGroups.items);

        const context = webkit.WebContext.getDefault();

        context.registerUriScheme("mika-shell", struct {
            fn cb(request: *webkit.URISchemeRequest, data: ?*anyopaque) callconv(.c) void {
                const app_inner: *App = @ptrCast(@alignCast(data));
                const gio = @import("gio");
                const returnError = struct {
                    fn f(a: *App, r: *webkit.URISchemeRequest, comptime fmt: []const u8, args: anytype) void {
                        const msg = std.fmt.allocPrintSentinel(a.allocator, fmt, args, 0) catch unreachable;
                        defer a.allocator.free(msg);
                        const e = glib.Error.new(webkit.NetworkError.quark(), @intFromEnum(webkit.NetworkError.failed), msg);
                        defer e.free();
                        const w = a.getWebviewWithId(r.getWebView().getPageId()) catch unreachable;
                        w.forceShow();
                        r.finishError(e);
                    }
                }.f;
                const uri = std.Uri.parse(std.mem.span(request.getUri())) catch {
                    returnError(app_inner, request, "Invalid URI: {s}", .{std.mem.span(request.getUri())});
                    return;
                };
                const alloc = app_inner.allocator;
                const dir = app_inner.configDir;

                const host = uri.host.?.percent_encoded;
                const path = uri.path.percent_encoded;

                var it = app_inner.config.dev.iterator();
                while (it.next()) |kv| {
                    const key = kv.key_ptr.*;
                    const val = kv.value_ptr.*;
                    if (!std.mem.eql(u8, key, host)) continue;
                    const query = std.mem.span(request.getUri())[uri.scheme.len + 3 + host.len ..];
                    const url = std.fs.path.joinZ(alloc, &.{ val, query }) catch unreachable;
                    defer alloc.free(url);
                    var client = std.http.Client{ .allocator = alloc };
                    defer client.deinit();
                    var result = std.Io.Writer.Allocating.init(alloc);
                    defer result.deinit();
                    const uri_ = std.Uri.parse(url) catch {
                        returnError(app_inner, request, "Invalid URL: {s}", .{url});
                        return;
                    };
                    var req = client.request(.GET, uri_, .{}) catch |err| {
                        returnError(app_inner, request, "Failed to request {s}: {t}", .{ url, err });
                        return;
                    };
                    defer req.deinit();
                    req.sendBodiless() catch |err| {
                        returnError(app_inner, request, "Failed to request {s}: {t}", .{ url, err });
                        return;
                    };
                    var redirect_buffer: [8 * 1024]u8 = undefined;
                    var response = req.receiveHead(&redirect_buffer) catch |err| {
                        returnError(app_inner, request, "Failed to receive head of {s}: {t}", .{ url, err });
                        return;
                    };
                    if (response.head.status != .ok) {
                        returnError(app_inner, request, "Failed to request {s}: {t}", .{ url, response.head.status });
                        return;
                    }
                    const content_type = alloc.dupeZ(u8, response.head.content_type orelse "application/octet-stream") catch unreachable;
                    defer alloc.free(content_type);

                    var writer = std.Io.Writer.Allocating.init(alloc);
                    defer writer.deinit();

                    _ = response.reader(&redirect_buffer).streamRemaining(&writer.writer) catch unreachable;

                    const size = writer.written().len;
                    const payload = glib.malloc(@intCast(size));
                    const payload_ptr: [*]u8 = @ptrCast(payload);
                    @memcpy(payload_ptr[0..size], writer.written());
                    const stream = gio.MemoryInputStream.newFromData(payload_ptr, @intCast(size), struct {
                        fn free(data_: ?*anyopaque) callconv(.c) void {
                            glib.free(data_);
                        }
                    }.free);
                    defer stream.unref();
                    request.finish(stream.as(gio.InputStream), @intCast(size), content_type.ptr);
                    return;
                }
                const file_path = std.fs.path.joinZ(alloc, &.{ dir, host, path, if (std.mem.endsWith(u8, path, "/")) "index.html" else "" }) catch unreachable;
                defer alloc.free(file_path);
                const f = std.fs.openFileAbsolute(file_path, .{}) catch |err| {
                    returnError(app_inner, request, "Failed to open file: {s}: {t}", .{ file_path, err });
                    return;
                };
                defer f.close();
                var pos = f.getEndPos() catch |err| {
                    returnError(app_inner, request, "Failed to get file size: {s}: {t}", .{ file_path, err });
                    return;
                };
                const size: isize = @intCast(pos);
                const payload = glib.malloc(pos);
                const payload_ptr: [*]u8 = @ptrCast(payload);
                pos = 0; // now, pos is used as offset of payload_ptr
                var buf: [512 * 1024]u8 = undefined;
                while (true) {
                    const n = f.read(&buf) catch |err| {
                        returnError(app_inner, request, "Failed to read file: {s}: {t}", .{ file_path, err });
                        return;
                    };
                    if (n == 0) break;
                    @memcpy(payload_ptr[pos .. pos + n], buf[0..n]);
                    pos += n;
                }

                const content_type = gio.contentTypeGuess(file_path.ptr, payload_ptr, 256, null);
                defer glib.free(content_type);

                const stream = gio.MemoryInputStream.newFromData(@ptrCast(payload_ptr), size, struct {
                    fn free(data_: ?*anyopaque) callconv(.c) void {
                        glib.free(data_);
                    }
                }.free);
                defer stream.unref();
                request.finish(stream.as(gio.InputStream), size, content_type);
            }
        }.cb, app, null);

        // add css for popover
        const cssProvider = gtk.CssProvider.new();
        defer cssProvider.unref();
        cssProvider.loadFromString(".mika-shell-popover > contents {background-color: transparent; border: none; padding: 0; margin: 0; border-radius: 0;}");
        gtk.StyleContext.addProviderForDisplay(@import("gdk").Display.getDefault().?, cssProvider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        for (app.config.startup) |startup| {
            _ = try app.open(startup);
        }
        return app;
    }
    fn sortPopoverFirst(_: void, a: *Webview, b: *Webview) bool {
        if (a.container == .popover and b.container != .popover) {
            return true;
        }
        if (a.container != .popover and b.container == .popover) {
            return false;
        }
        return a.id > b.id;
    }

    pub fn deinit(self: *App) void {
        self.isQuit = true;
        self.sessionBusWatcher.deinit();
        self.systemBusWatcher.deinit();
        std.mem.sort(*Webview, self.webviews.items, {}, sortPopoverFirst);
        for (self.webviews.items) |webview| {
            webview.forceClose();
        }
        self.webviews.deinit(self.allocator);
        self.modules.deinit();
        self.sessionBus.deinit();
        self.systemBus.deinit();
        self.config.deinit(self.allocator);
        self.allocator.free(self.configDir);
        self.emitter.deinit();
        self.allocator.free(self.server);
        self.allocator.destroy(self);
    }
    pub fn open(self: *App, pageName: []const u8) !*Webview {
        const path = blk: {
            if (std.mem.startsWith(u8, pageName, "/")) {
                break :blk pageName;
            } else {
                if (self.config.alias.get(pageName)) |alias| break :blk alias;
                return error.AliasNotFound;
            }
        };
        const uri = std.fs.path.joinZ(self.allocator, &.{ "mika-shell://", path }) catch unreachable;
        defer self.allocator.free(uri);
        return self.openS(uri, pageName);
    }
    /// 初始化 webview 的 contianer, 为其绑定事件
    pub fn setupContianer(self: *App, webview: *Webview, contianer: enum { popover, window, layer }) void {
        switch (contianer) {
            .window, .layer => {
                const window = gtk.Window.new();
                webview.container = if (contianer == .window) .{ .window = window } else .{ .layer = @import("layershell").Layer.init(window) };
                const widget = window.as(gtk.Widget);
                window.setChild(webview.impl.as(gtk.Widget));
                const cssProvider = gtk.CssProvider.new();
                defer cssProvider.unref();
                cssProvider.loadFromString("window {background-color: transparent;}");
                widget.getStyleContext().addProvider(cssProvider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

                _ = g.signalConnectData(window.as(g.Object), "close-request", @ptrCast(&struct {
                    fn f(o: *g.Object, app_inner: *App) callconv(.c) c_int {
                        const wb: *Webview = app_inner.getWebviewWithWidget(g.ext.cast(gtk.Widget, o).?);
                        app_inner.emitEventUseJS(wb, .mika_close_request, wb.id);
                        return 1;
                    }
                }.f), self, null, .flags_default);
            },
            .popover => {
                const popover = gtk.Popover.new();
                const widget = popover.as(gtk.Widget);

                widget.addCssClass("mika-shell-popover");
                popover.setHasArrow(0);
                popover.setAutohide(0);
                popover.setMnemonicsVisible(0);

                webview.container = .{ .popover = popover };
                popover.setChild(webview.impl.as(gtk.Widget));
            },
        }
        const obj = switch (webview.container) {
            .none => unreachable,
            .window => |w| w.as(g.Object),
            .layer => |l| l.inner.as(g.Object),
            .popover => |p| p.as(g.Object),
        };

        // `destroy` signal is connected in other places, and we need to make sure this callback is the last one to be called.
        _ = g.signalConnectData(obj, "destroy", @ptrCast(&struct {
            fn f(o: *g.Object, app_inner: *App) callconv(.c) void {
                if (app_inner.isQuit) return;
                const wb: *Webview = app_inner.getWebviewWithWidget(g.ext.cast(gtk.Widget, o).?);
                const id = wb.id;
                app_inner.mutex.lock();
                defer app_inner.mutex.unlock();
                for (app_inner.webviews.items, 0..app_inner.webviews.items.len) |w_, i| {
                    if (w_.id == id) {
                        _ = app_inner.webviews.orderedRemove(i);
                        app_inner.emitEventUseJS(null, .mika_close, id);
                        break;
                    }
                }
            }
        }.f), self, null, .flags_after);

        _ = g.signalConnectData(obj, "show", @ptrCast(&struct {
            fn f(o: *g.Object, app_inner: *App) callconv(.c) void {
                const wb: *Webview = app_inner.getWebviewWithWidget(g.ext.cast(gtk.Widget, o).?);
                app_inner.emitEventUseJS(null, .mika_show, wb.id);
            }
        }.f), self, null, .flags_default);

        _ = g.signalConnectData(obj, "hide", @ptrCast(&struct {
            fn f(o: *g.Object, app_inner: *App) callconv(.c) void {
                const wb: *Webview = app_inner.getWebviewWithWidget(g.ext.cast(gtk.Widget, o).?);
                app_inner.emitEventUseJS(null, .mika_hide, wb.id);
            }
        }.f), self, null, .flags_default);
    }
    fn openS(self: *App, uri: [:0]const u8, name: []const u8) *Webview {
        const webview = Webview.init(self.allocator, self.modules, name, self.port, self.configDir) catch unreachable;
        webview.impl.loadUri(uri);
        self.mutex.lock();
        self.webviews.append(self.allocator, webview) catch unreachable;
        self.mutex.unlock();
        const info = webview.getInfo();
        self.emitEventUseSocket(.mika_open, info);

        return webview;
    }
    pub fn getWebviewWithId(self: *App, id: u64) !*Webview {
        for (self.webviews.items) |webview| {
            if (webview.id == id) {
                return webview;
            }
        }
        return Error.WebviewNotExists;
    }
    pub fn getWebviewWithWidget(self: *App, widget: *gtk.Widget) *Webview {
        for (self.webviews.items) |webview| {
            if (webview.impl.as(gtk.Widget) == widget) return webview;
            switch (webview.container) {
                .none => {},
                .window => |w| {
                    if (w.as(gtk.Widget) == widget) return webview;
                },
                .layer => |l| {
                    if (l.inner.as(gtk.Widget) == widget) return webview;
                },
                .popover => |p| {
                    if (p.as(gtk.Widget) == widget) return webview;
                },
            }
        }
        unreachable;
    }
    pub fn emitEventUseSocket(self: *App, event: events.Events, data: anytype) void {
        self.emitter.emit(event, data);
    }
    pub fn emitEventUseJS(self: *App, dist: ?*Webview, event: events.Events, data: anytype) void {
        const alc = std.heap.page_allocator;
        const dataJson = std.json.Stringify.valueAlloc(alc, data, .{}) catch unreachable;
        defer alc.free(dataJson);
        const js = std.fmt.allocPrintSentinel(alc, "window.dispatchEvent(new CustomEvent('mika-shell-event', {{ detail: {{ event: {d}, data: {s} }} }}));", .{ @intFromEnum(event), dataJson }, 0) catch unreachable;
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
        self.emitEventUseJS(w, .mika_show_request, w.id);
    }
    pub fn hideRequest(self: *App, w: *Webview) void {
        self.emitEventUseJS(w, .mika_hide_request, w.id);
    }
    pub fn closeRequest(self: *App, w: *Webview) void {
        self.emitEventUseJS(w, .mika_close_request, w.id);
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
