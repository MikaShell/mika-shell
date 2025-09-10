const httpz = @import("httpz");
const ws = httpz.websocket;
const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const glib = @import("glib");
const events = @import("events.zig");
const Handler = struct {
    allocator: Allocator,
    assetsDir: []const u8,
    eventManager: *EventManager,
    pub const WebsocketHandler = union(enum) {
        const Self = @This();
        const Context = union(enum) {
            proxy: std.meta.Tuple(&.{[]const u8}),
            event: std.meta.Tuple(&.{ *EventManager, u64 }),
        };
        event: EventHandler,
        proxy: ProxyHandler,
        pub fn init(conn: *ws.Conn, ctx: Context) !Self {
            switch (ctx) {
                .proxy => |p| return .{
                    .proxy = try ProxyHandler.init(conn, p[0]),
                },
                .event => |e| return .{
                    .event = try EventHandler.init(conn, e[0], e[1]),
                },
            }
        }
        pub fn clientMessage(self: *Self, data: []const u8) !void {
            switch (self.*) {
                .event => |*h| try h.clientMessage(data),
                .proxy => |*h| try h.clientMessage(data),
            }
        }
        pub fn close(self: *Self) void {
            switch (self.*) {
                .event => |*h| h.close(),
                .proxy => |*h| h.close(),
            }
        }
    };
    fn upgradeWebsocket(_: *Handler, req: *httpz.Request, res: *httpz.Response, ctx: WebsocketHandler.Context) void {
        const result = httpz.upgradeWebsocket(WebsocketHandler, req, res, ctx) catch |err| {
            res.status = 400;
            res.body = std.fmt.allocPrint(req.arena, "Failed to upgrade websocket: {t}", .{err}) catch unreachable;
            return;
        };
        if (!result) {
            res.status = 400;
            res.body = "Failed to upgrade websocket";
            return;
        }
    }
};
pub const ProxyHandler = struct {
    pub const Context = struct {
        conn: *ws.Conn,
        unixSock: std.net.Stream,
        watch: c_uint,
    };
    ctx: *Context,
    pub fn init(conn: *ws.Conn, path: []const u8) !ProxyHandler {
        // TODO: 剔除路径防止注入
        const sock = try std.net.connectUnixSocket(path);
        errdefer sock.close();
        const ctx = try std.heap.page_allocator.create(Context);
        errdefer std.heap.page_allocator.destroy(ctx);
        const ch = glib.IOChannel.unixNew(sock.handle);
        defer ch.unref();
        ctx.* = .{
            .conn = conn,
            .unixSock = sock,
            .watch = glib.ioAddWatch(ch, .{ .in = true }, onUnixSockMessage, ctx),
        };

        return .{ .ctx = ctx };
    }
    fn onUnixSockMessage(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.c) c_int {
        const ctx: *Context = @ptrCast(@alignCast(data));
        var buf: [512]u8 = undefined;
        const n = ctx.unixSock.read(&buf) catch {
            _ = ctx.conn.close(.{ .code = 1011, .reason = "Internal Server Error" }) catch {};
            ctx.watch = 0;
            return 0;
        };
        if (n == 0) {
            _ = ctx.conn.close(.{ .code = 1000, .reason = "EOF" }) catch {};
            ctx.watch = 0;
            return 0;
        }
        ctx.conn.write(buf[0..n]) catch {
            _ = ctx.conn.close(.{ .code = 1011, .reason = "Internal Server Error" }) catch {};
            ctx.watch = 0;
            return 0;
        };
        return 1;
    }
    pub fn close(h: *ProxyHandler) void {
        if (h.ctx.watch != 0) _ = glib.Source.remove(h.ctx.watch);
        h.ctx.unixSock.close();
        std.heap.page_allocator.destroy(h.ctx);
    }
    pub fn clientMessage(self: *ProxyHandler, data: []const u8) !void {
        _ = try self.ctx.unixSock.write(data);
    }
};
pub const EventHandler = struct {
    manager: *EventManager,
    id: u64,
    pub fn init(conn: *ws.Conn, manager: *EventManager, id: u64) !EventHandler {
        try manager.add(id, conn);
        return .{
            .manager = manager,
            .id = id,
        };
    }
    pub fn close(h: *EventHandler) void {
        h.manager.remove(h.id);
    }
    pub fn clientMessage(_: *EventHandler, _: []const u8) !void {}
};
const EventManager = struct {
    const Self = @This();
    allocator: Allocator,
    channel: *events.EventChannel,
    watch: c_uint,
    sockets: std.AutoHashMap(u64, *ws.Conn),
    pub fn add(self: *Self, id: u64, conn: *ws.Conn) !void {
        if (self.sockets.contains(id)) {
            return error.SocketExists;
        }
        self.sockets.put(id, conn) catch return error.FailedToAddSocket;
    }
    pub fn remove(self: *Self, id: u64) void {
        _ = self.sockets.remove(id);
    }
    pub fn init(allocator: Allocator, channel: *events.EventChannel) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.channel = channel;
        const ch = glib.IOChannel.unixNew(channel.out);
        defer ch.unref();
        self.watch = glib.ioAddWatch(ch, .{ .in = true }, onEvent, self);
        self.allocator = allocator;
        self.sockets = std.AutoHashMap(u64, *ws.Conn).init(allocator);
        return self;
    }
    pub fn deinit(self: *Self) void {
        _ = glib.Source.remove(self.watch);
        self.sockets.deinit();
        self.allocator.destroy(self);
    }
    fn onEvent(_: *glib.IOChannel, _: glib.IOCondition, data: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(data));
        const es: []events.Event = self.channel.load();
        for (es) |*e| {
            defer e.deinit();
            const dist = self.sockets.get(e.dist) orelse continue;
            dist.write(e.data) catch unreachable;
        }
        return 1;
    }
};
const log = std.log.scoped(.assets);
pub const Server = struct {
    const Self = @This();
    allocator: Allocator,
    server: httpz.Server(*Handler),
    thread: std.Thread,
    handler: *Handler,
    // TODO: 增加验证机制
    pub fn init(allocator: Allocator, assetsDir: []const u8, eventChannel: *events.EventChannel, port: u16) !*Server {
        const server = try allocator.create(Server);
        errdefer allocator.destroy(server);
        server.handler = try allocator.create(Handler);
        server.allocator = allocator;
        server.handler.allocator = allocator;
        const ownedAssetsDir = try allocator.dupe(u8, assetsDir);
        server.handler.assetsDir = ownedAssetsDir;
        server.handler.eventManager = try EventManager.init(allocator, eventChannel);
        errdefer server.handler.eventManager.deinit();
        server.server = try httpz.Server(*Handler).init(allocator, .{ .port = port }, server.handler);
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
        self.handler.eventManager.deinit();
        self.allocator.free(self.handler.assetsDir);
        self.allocator.destroy(self.handler);
        self.allocator.destroy(self);
    }
};
fn handler(h: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    if (req.header("upgrade")) |upgrade| {
        if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) return;
        const query = try req.query();
        if (query.get("event")) |id| {
            const id_ = std.fmt.parseInt(u64, id, 10) catch {
                res.status = 400;
                res.body = "invalid event id";
                return;
            };
            log.debug("Websocket connect to event: {}", .{id_});
            h.upgradeWebsocket(req, res, .{ .event = .{ h.eventManager, id_ } });
        } else {
            const path = req.url.path[1..];
            log.debug("Websocket connect to proxy: {s}", .{path});
            h.upgradeWebsocket(req, res, .{ .proxy = .{path} });
        }
        return;
    }
    res.status = 400;
    res.body = "invalid request";
    return;
}
