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
    watcher: glib.FdWatch(Server),
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
        self.watcher.deinit();
        self.s.deinit();
        self.allocator.free(self.path);
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
        std.fs.deleteFileAbsolute(self.path) catch {};
        const addr = try std.net.Address.initUnix(self.path);
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
    std.log.debug("IPC: Received request: {s}", .{r.type});
    const out = s.writer();
    if (eql(r.type, "open")) {
        _ = app.open(r.pageName.?) catch |err| switch (err) {
            error.PageNotFound => {
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
            error.PageNotFound => {
                try out.print("Can`t find page with name: {s}\n", .{r.pageName.?});
            },
            else => return err,
        };
    }
    if (eql(r.type, "list")) {
        var isFirstLine = true;
        for (app.webviews.items) |w| {
            const name = w.name;
            const title = mem.span(w.impl.getTitle());
            const id = w.id;
            const uri = mem.span(w.impl.getUri());
            const visible = w.container.as(gtk.Widget).getVisible();
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
            try out.print("    name: {s}\n", .{name});
            try out.print("    type: {s}\n", .{t});
            try out.print("    title: {s}\n", .{title});
            try out.print("    visible: {}\n", .{visible});
        }
    }
    if (eql(r.type, "show")) {
        const w = app.getWebview(r.id.?) catch {
            try out.print("Can`t find webview with id: {d}\n", .{r.id.?});
            return;
        };
        switch (w.type) {
            .None => {
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
        const w = app.getWebview(r.id.?) catch {
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
        const w = app.getWebview(r.id.?) catch {
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
