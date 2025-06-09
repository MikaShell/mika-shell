const std = @import("std");
const gtk = @import("gtk");
const SOCKET_PATH = "/tmp/mikami.sock";
const glib = @import("glib");
pub const Server = struct {
    allocator: std.mem.Allocator,
    s: std.net.Server,
    app: *app_.App,
    watcher: glib.FdWatch(Server),
    pub fn init(allocator: std.mem.Allocator, app: *app_.App) !*Server {
        const self = try allocator.create(Server);
        self.* = .{
            .allocator = allocator,
            .s = undefined,
            .app = app,
            .watcher = undefined,
        };
        return self;
    }
    pub fn deinit(self: *Server) void {
        self.s.deinit();
        self.watcher.deinit();
        self.allocator.destroy(self);
    }

    fn handleConnection(self: *Server) !void {
        const conn = try self.s.accept();
        const stream = conn.stream;
        defer stream.close();
        const alc = std.heap.page_allocator;
        const len = try stream.reader().readInt(usize, .little);
        var limitedReader = std.io.limitedReader(stream.reader(), len);
        var reader = std.json.reader(alc, limitedReader.reader());
        defer reader.deinit();
        const req = try std.json.parseFromTokenSource(Request, alc, &reader, .{});
        defer req.deinit();
        try handle(self.app, req.value, stream);
    }

    pub fn listen(self: *Server) !void {
        std.fs.deleteFileAbsolute(SOCKET_PATH) catch {};
        const addr = try std.net.Address.initUnix(SOCKET_PATH);
        const server = try addr.listen(.{});
        self.s = server;
        self.watcher = try glib.FdWatch(Server).add(server.stream.handle, &struct {
            fn f(s: *Server) bool {
                s.handleConnection() catch |err| {
                    std.debug.print("Can not handle message, error: {s}", .{@errorName(err)});
                };
                return true;
            }
        }.f, self);
    }
};
fn isType(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const Request = struct {
    type: []const u8,
    uri: ?[]const u8 = null,
    id: ?u64 = null,
    force: ?bool = null,
};

const app_ = @import("app.zig");
fn handle(app: *app_.App, r: Request, s: std.net.Stream) !void {
    std.log.debug("IPC: Received request: {s}", .{r.type});
    if (isType(r.type, "open")) {
        _ = app.open(r.uri.?);
    }
    const out = s.writer();
    if (isType(r.type, "list")) {
        var isFirstLine = true;
        for (app.webviews.items) |w| {
            const title = w.impl.getTitle();
            const id = w.impl.getPageId();
            const uri = w.impl.getUri();
            const visible = w.container.asWidget().getVisible();
            const t = switch (w.type) {
                .None => "none",
                .Layer => "layer",
                .Window => "window",
            };
            if (!isFirstLine) {
                _ = try out.write("\n");
            }
            isFirstLine = false;
            try out.print("id: {d}\n", .{id});
            try out.print("    uri: {s}\n", .{uri});
            try out.print("    type: {s}\n", .{t});
            try out.print("    title: {s}\n", .{title});
            try out.print("    visible: {}\n", .{visible});
        }
    }
    if (isType(r.type, "show")) {
        const webview = app.getWebview(r.id.?);
        if (webview) |w| {
            switch (w.type) {
                .None => {
                    if (r.force.?) {
                        try app.show(r.id.?);
                    } else {
                        try out.print("Can`t show this webview, This webview well not initialized yet.\n", .{});
                        try out.print("If you want to show this webview, please use `force` option.\n", .{});
                    }
                },
                else => {
                    try app.show(r.id.?);
                },
            }
        } else {
            try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
        }
    }
    if (isType(r.type, "hide")) {
        app.hide(r.id.?) catch |err| {
            if (err == app_.Error.WebviewNotExists) {
                try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            } else {
                return err;
            }
        };
    }
    if (isType(r.type, "close")) {
        app.close(r.id.?) catch |err| {
            if (err == app_.Error.WebviewNotExists) {
                try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            } else {
                return err;
            }
        };
    }
}
pub fn request(req: Request) !void {
    const c = try std.net.connectUnixSocket(SOCKET_PATH);
    const alc = std.heap.page_allocator;
    const reqJSON = try std.json.stringifyAlloc(alc, req, .{ .emit_null_optional_fields = false });
    defer alc.free(reqJSON);
    _ = try c.writer().writeInt(usize, reqJSON.len, .little);
    _ = try c.writer().writeAll(reqJSON);
    defer c.close();
    var buf: [512]u8 = undefined;
    var fifo = std.fifo.LinearFifo(u8, .Slice).init(buf[0..]);
    defer fifo.deinit();
    const stdout = std.io.getStdOut();
    try fifo.pump(c.reader(), stdout.writer());
}

test "stringify and Request" {
    const req = Request{
        .type = "open",
    };
    const alc = std.heap.page_allocator;
    const reqJSON = try std.json.stringifyAlloc(alc, req, .{ .emit_null_optional_fields = false });
    defer alc.free(reqJSON);
    std.debug.print("Request JSON: {s}\n", .{reqJSON});
}
