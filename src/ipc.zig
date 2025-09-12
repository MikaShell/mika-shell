const std = @import("std");
fn socketPath(allocator: mem.Allocator, port: u16) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "/tmp/mika-shell-{d}.sock", .{port});
}
const glib = @import("glib");
const mem = std.mem;
pub const Server = struct {
    allocator: mem.Allocator,
    s: std.net.Server,
    app: *App,
    watcher: c_uint,
    path: []const u8,
    pub fn init(allocator: mem.Allocator, app: *App, port: u16) !*Server {
        const self = try allocator.create(Server);
        self.* = .{
            .allocator = allocator,
            .s = undefined,
            .app = app,
            .watcher = undefined,
            .path = try socketPath(allocator, port),
        };
        return self;
    }
    pub fn deinit(self: *Server) void {
        _ = glib.Source.remove(self.watcher);
        self.s.deinit();
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    fn handleConnection(self: *Server) !void {
        const conn = try self.s.accept();
        const stream = conn.stream;
        defer stream.close();
        const alc = std.heap.page_allocator;

        var buf: [512]u8 = undefined;
        var reader = stream.reader(&buf);
        var r = &reader.file_reader.interface;
        const len = try r.takeInt(usize, .little);
        const payload = try r.readAlloc(alc, len);
        defer alc.free(payload);
        const req = try std.json.parseFromSlice(Request, alc, payload, .{});
        defer req.deinit();
        try handle(self.app, req.value, stream);
    }

    pub fn listen(self: *Server) !void {
        std.fs.deleteFileAbsolute(self.path) catch {};
        const addr = try std.net.Address.initUnix(self.path);
        const server = try addr.listen(.{});
        self.s = server;
        const ch = glib.IOChannel.unixNew(server.stream.handle);
        defer ch.unref();
        self.watcher = glib.ioAddWatch(ch, .{ .in = true }, &struct {
            fn f(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.c) c_int {
                const s: *Server = @ptrCast(@alignCast(data));
                s.handleConnection() catch |err| {
                    std.log.scoped(.ipc).err("Can not handle message, error: {t}", .{err});
                };
                return 1;
            }
        }.f, self);
    }
};
fn eql(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

pub const Request = struct {
    type: []const u8,
    pageName: ?[]const u8 = null,
    id: ?u64 = null,
    force: ?bool = null,
};

const app_ = @import("app.zig");
const gtk = @import("gtk");
const App = app_.App;
fn handle(app: *App, r: Request, s: std.net.Stream) !void {
    std.log.scoped(.ipc).debug("Received request: {s}", .{r.type});
    var buf: [512]u8 = undefined;
    var writer = s.writer(&buf);
    var out = &writer.file_writer.interface;
    if (eql(r.type, "alias")) {
        var result = std.ArrayList([]const u8){};
        defer {
            for (result.items) |item| app.allocator.free(item);
            result.deinit(app.allocator);
        }
        var it = app.config.alias.iterator();

        while (it.next()) |entry| {
            try result.append(app.allocator, try std.fmt.allocPrint(app.allocator, "{s} -> {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* }));
        }
        const lessThan = struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less;
        std.mem.sort([]const u8, result.items, {}, lessThan);
        for (result.items) |item| {
            try out.writeAll(item);
        }
    }
    if (eql(r.type, "open")) {
        _ = app.open(r.pageName.?) catch |err| switch (err) {
            error.AliasNotFound => {
                try out.print("Can`t find page with name: {s}\n", .{r.pageName.?});
            },
            else => return err,
        };
    }
    if (eql(r.type, "toggle")) {
        var i = app.webviews.items.len - 1;
        while (i >= 0) {
            const w = app.webviews.items[i];
            if (mem.eql(u8, w.name, r.pageName.?)) {
                app.closeRequest(w);
                return;
            }
            if (i == 0) break;
            i -= 1;
        }
        _ = app.open(r.pageName.?) catch |err| switch (err) {
            error.AliasNotFound => {
                try out.print("Can`t find page with name: {s}\n", .{r.pageName.?});
            },
            else => return err,
        };
    }
    if (eql(r.type, "list")) {
        var isFirstLine = true;
        for (app.webviews.items) |w| {
            const info = w.getInfo();
            if (!isFirstLine) {
                _ = try out.write("\n");
            }
            isFirstLine = false;
            try out.print("id: {d}\n", .{info.id});
            try out.print("    uri: {s}\n", .{info.uri});
            try out.print("    alias: {s}\n", .{info.alias});
            try out.print("    type: {s}\n", .{info.type});
            try out.print("    title: {s}\n", .{info.title});
            try out.print("    visible: {}\n", .{info.visible});
        }
    }
    if (eql(r.type, "show")) {
        const w = app.getWebviewWithId(r.id.?) catch {
            try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            return;
        };
        switch (w.container) {
            .none => {
                if (r.force.?) {
                    w.forceShow();
                } else {
                    try out.print("Can`t show this webview, This webview well not initialized yet.\n", .{});
                    try out.print("If you want to show this webview, please use `force` option.\n", .{});
                }
            },
            else => {
                app.showRequest(w);
            },
        }
    }
    if (eql(r.type, "hide")) {
        const w = app.getWebviewWithId(r.id.?) catch {
            try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            return;
        };
        if (r.force.?) {
            w.forceHide();
        } else {
            app.hideRequest(w);
        }
    }
    if (eql(r.type, "close")) {
        const w = app.getWebviewWithId(r.id.?) catch {
            try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            return;
        };
        if (r.force.?) {
            w.forceClose();
        } else {
            app.closeRequest(w);
        }
    }
}
pub fn request(req: Request, port: u16) !void {
    const allocator = std.heap.page_allocator;
    const path = try socketPath(allocator, port);
    defer allocator.free(path);
    const c = try std.net.connectUnixSocket(path);
    const alc = std.heap.page_allocator;
    const reqJSON = try std.json.Stringify.valueAlloc(alc, req, .{ .emit_null_optional_fields = false });
    defer alc.free(reqJSON);
    var buf: [512]u8 = undefined;
    var writer = c.writer(&buf);
    var w = &writer.interface;
    _ = try w.writeInt(usize, reqJSON.len, .little);
    try w.flush();
    _ = try w.writeAll(reqJSON);
    try w.flush();
    defer c.close();
    var stdout = std.fs.File.stdout();
    while (true) {
        const n = try c.read(&buf);
        if (n == 0) break;
        try stdout.writeAll(buf[0..n]);
    }
}

test "stringify and Request" {
    const req = Request{
        .type = "open",
    };
    const alc = std.heap.page_allocator;
    const reqJSON = try std.json.Stringify.valueAlloc(alc, req, .{ .emit_null_optional_fields = false });
    defer alc.free(reqJSON);
    std.debug.print("Request JSON: {s}\n", .{reqJSON});
}
