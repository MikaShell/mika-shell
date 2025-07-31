const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;
const gtk = @import("gtk");
pub const Monitor = struct {
    const Self = @This();
    allocator: Allocator,
    app: *App,
    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        self.app = ctx.app;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return .{
            .exports = &.{
                .{ "list", list },
                .{ "get", get },
            },
        };
    }
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        const allocator = self.allocator;
        const monitors = try gtk.Monitor.list(allocator);
        defer allocator.free(monitors);
        defer for (monitors) |monitor| monitor.deinit(allocator);
        result.commit(monitors);
    }
    pub fn get(self: *Self, args: Args, result: *Result) !void {
        const id = args.uInteger(0) catch unreachable;
        const w = try self.app.getWebview(id);
        const monitor = try w.container.getMonitor(self.allocator);
        defer monitor.deinit(self.allocator);
        result.commit(monitor);
    }
};
