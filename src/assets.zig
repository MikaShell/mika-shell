const httpz = @import("httpz");
const ws = httpz.websocket;
const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const glib = @import("glib");
const Handler = struct {
    allocator: Allocator,
    assetsDir: []const u8,
    pub const WebsocketHandler = struct {
        pub const Context = struct {
            conn: *ws.Conn,
            unixSock: std.net.Stream,
        };
        ctx: *Context,
        watch: glib.FdWatch(Context),
        pub fn init(conn: *ws.Conn, path: []const u8) !WebsocketHandler {
            // TODO: 剔除路径防止注入
            const sock = try std.net.connectUnixSocket(path);
            errdefer sock.close();
            const ctx = try std.heap.page_allocator.create(Context);
            ctx.* = .{
                .conn = conn,
                .unixSock = sock,
            };
            return .{
                .ctx = ctx,
                .watch = try glib.FdWatch(Context).add(sock.handle, onUnixSockMessage, ctx),
            };
        }
        // BUG: 在使用 hyprland 的 socket2 时,观察到一些消息会被读取 3 次
        fn onUnixSockMessage(ctx: *Context) bool {
            var buf: [512]u8 = undefined;
            const n = ctx.unixSock.read(&buf) catch {
                _ = ctx.conn.close(.{ .code = 1011, .reason = "Internal Server Error" }) catch {};
                return false;
            };
            if (n == 0) {
                _ = ctx.conn.close(.{ .code = 1000, .reason = "EOF" }) catch {};
                return false;
            }
            ctx.conn.write(buf[0..n]) catch {
                _ = ctx.conn.close(.{ .code = 1011, .reason = "Internal Server Error" }) catch {};
                return false;
            };
            return true;
        }
        pub fn close(h: *WebsocketHandler) void {
            h.watch.deinit();
            h.ctx.unixSock.close();
            std.heap.page_allocator.destroy(h.ctx);
        }
        pub fn clientMessage(self: *WebsocketHandler, data: []const u8) !void {
            _ = try self.ctx.unixSock.write(data);
        }
    };
};
pub const Server = struct {
    allocator: Allocator,
    server: httpz.Server(*Handler),
    thread: std.Thread,
    handler: *Handler,
    // TODO: 增加验证机制
    pub fn init(allocator: Allocator, assetsDir: []const u8) !*Server {
        const server = try allocator.create(Server);
        errdefer allocator.destroy(server);
        server.handler = try allocator.create(Handler);
        server.allocator = allocator;
        server.handler.allocator = allocator;

        const ownedAssetsDir = try allocator.dupe(u8, assetsDir);
        server.handler.assetsDir = ownedAssetsDir;
        server.server = try httpz.Server(*Handler).init(allocator, .{ .port = 6797 }, server.handler);

        return server;
    }
    pub fn start(self: *Server) !void {
        const router = try self.server.router(.{});
        router.get("/*", handler, .{});
        self.thread = try self.server.listenInNewThread();
    }
    pub fn stop(self: *Server) void {
        self.server.stop();
        self.thread.join();
    }
    pub fn deinit(self: *Server) void {
        self.server.deinit();
        self.allocator.free(self.handler.assetsDir);
        self.allocator.destroy(self.handler);
        self.allocator.destroy(self);
    }
};
fn handler(h: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    if (req.header("upgrade")) |upgrade| {
        if (std.ascii.eqlIgnoreCase(upgrade, "websocket")) {
            if ((try httpz.upgradeWebsocket(Handler.WebsocketHandler, req, res, req.url.path)) == false) {
                res.status = 400;
                res.body = "invalid websocket handshake";
            }
            return;
        }
    }
    return fileServer(h, req, res);
}

fn fileServer(h: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const allocator = h.allocator;
    const path = req.url.path;
    // TODO: 剔除路径防止注入
    var fileName = path;
    if (std.mem.endsWith(u8, path, "/")) {
        fileName = try std.fs.path.join(allocator, &[_][]const u8{ path, "index.html" });
    }
    const filePath = try std.fs.path.join(allocator, &[_][]const u8{ h.assetsDir, fileName });
    defer allocator.free(filePath);
    std.log.debug("req: {s} {s}", .{ path, fileName });

    const f = std.fs.openFileAbsolute(filePath, .{ .mode = .read_only }) catch |err| switch (err) {
        fs.File.OpenError.IsDir, fs.File.OpenError.FileNotFound => {
            res.status = 404;
            res.body = @embedFile("404.html");
            return;
        },
        else => return err,
    };
    res.content_type = httpz.ContentType.forFile(filePath);
    defer f.close();
    const buf = try f.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(buf);
    try res.writer().writeAll(buf);
}
