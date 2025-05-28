const std = @import("std");
const gtk = @import("gtk");
const SOCKET_PATH = "/tmp/mikami.sock";
pub const Server = struct {
    allocator: std.mem.Allocator,
    s: std.net.Server,
    app: *app_.App,
    pub fn init(allocator: std.mem.Allocator, app: *app_.App) !*Server {
        const self = try allocator.create(Server);
        self.* = .{
            .allocator = allocator,
            .s = undefined,
            .app = app,
        };
        return self;
    }
    pub fn deinit(self: *Server) void {
        self.s.deinit();
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
        var gerr: ?*gtk.GError = null;
        const gSocket = gtk.GSocket.newFromFd(server.stream.handle, @ptrCast(&gerr));
        if (gerr) |e| {
            e.free();
        }
        const source = gSocket.createSource();
        defer source.unref();
        source.setCallback(&struct {
            fn f(_: ?*anyopaque, _: ?*anyopaque, s_: ?*anyopaque) callconv(.c) c_int {
                const ss: *Server = @ptrCast(@alignCast(s_.?));
                ss.handleConnection() catch |err| {
                    std.debug.print("Can not handle message, error: {s}", .{@errorName(err)});
                };
                return 1;
            }
        }.f, @ptrCast(self));
        source.attach();
    }
};
fn isType(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const Request = struct {
    type: []const u8,
    uri: []const u8 = undefined,
    id: u64 = undefined,
    force: bool = false,
};

const app_ = @import("app.zig");
fn handle(app: *app_.App, r: Request, s: std.net.Stream) !void {
    std.log.debug("IPC: Received request: {s}", .{r.type});
    if (isType(r.type, "open")) {
        _ = app.createWebview(r.uri);
    }
    const out = s.writer();
    if (isType(r.type, "list")) {
        var isFirstLine = true;
        for (app.webviews.items) |w| {
            const title = w._webview.getTitle();
            const id = w._webview.getPageId();
            const uri = w._webview.getUri();
            const visible = w._webview_container.asWidget().getVisible();
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
        for (app.webviews.items) |w| {
            if (w._webview.getPageId() == r.id) {
                switch (w.type) {
                    .None => {
                        if (r.force) {
                            w._webview_container.present();
                        } else {
                            try out.print("Can`t show this webview, This webview well not initialized yet.\n", .{});
                            try out.print("If you want to show this webview, please use `force` option.\n", .{});
                        }
                    },
                    .Layer => {
                        w._webview_container.asWidget().show();
                    },
                    .Window => {
                        w._webview_container.present();
                    },
                }
                break;
            }
        }
    }
    if (isType(r.type, "hide")) {
        for (app.webviews.items) |w| {
            if (w._webview.getPageId() == r.id) {
                w.hide();
            }
        }
    }
}
pub fn request(req: Request) !void {
    const c = try std.net.connectUnixSocket(SOCKET_PATH);
    const alc = std.heap.page_allocator;
    const reqJSON = try std.json.stringifyAlloc(alc, req, .{});
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
