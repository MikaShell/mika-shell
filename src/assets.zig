const httpz = @import("httpz");
const std = @import("std");
const Allocator = std.mem.Allocator;
const RouteData = struct {
    assetsDir: []const u8,
};
const fs = std.fs;
pub const Server = struct {
    allocator: Allocator,
    _server: httpz.Server(void),
    routerData: RouteData,
    thread: std.Thread,
    pub fn init(allocator: Allocator, assetsDir: []const u8) !*Server {
        const server = try allocator.create(Server);
        errdefer allocator.destroy(server);
        server.allocator = allocator;

        const ownedAssetsDir = try allocator.dupe(u8, assetsDir);
        server.routerData.assetsDir = ownedAssetsDir;
        server._server = try httpz.Server(void).init(allocator, .{ .port = 6797 }, {});

        return server;
    }
    pub fn start(self: *Server) !void {
        const router = try self._server.router(.{});
        router.get("/*", fileServer, .{ .data = &self.routerData });
        self.thread = try self._server.listenInNewThread();
    }
    pub fn stop(self: *Server) void {
        self._server.stop();
        self.thread.join();
    }
    pub fn deinit(self: *Server) void {
        self._server.deinit();
        self.allocator.free(self.routerData.assetsDir);
        self.allocator.destroy(self);
    }
};
fn fileServer(req: *httpz.Request, res: *httpz.Response) !void {
    const route_data: *const RouteData = @ptrCast(@alignCast(req.route_data));
    const allocator = std.heap.page_allocator;
    const path = req.url.path;
    // TODO: 剔除路径防止注入
    var fileName = path;
    if (std.mem.endsWith(u8, path, "/")) {
        fileName = try std.fs.path.join(allocator, &[_][]const u8{ path, "index.html" });
    }
    const filePath = try std.fs.path.join(allocator, &[_][]const u8{ route_data.assetsDir, fileName });
    defer allocator.free(filePath);
    std.log.debug("req: {s} {s}", .{ path, fileName });

    const f = std.fs.openFileAbsolute(filePath, .{ .mode = .read_only }) catch |err| switch (err) {
        fs.File.OpenError.IsDir, fs.File.OpenError.FileNotFound => {
            res.status = 404;
            res.body = "Not Found";
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
