const std = @import("std");
const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const Context = modules.Context;
const Registry = modules.Registry;
const Allocator = std.mem.Allocator;
const gtk = @import("gtk");
pub const Monitor = struct {
    const Self = @This();
    allocator: Allocator,

    pub fn init(ctx: Context) !*Self {
        const self = try ctx.allocator.create(Self);
        self.allocator = ctx.allocator;
        return self;
    }
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn register() Registry(Self) {
        return &.{
            .{ "list", list },
        };
    }
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        const allocator = self.allocator;
        const monitors = try gtk.Monitor.get(allocator);
        defer allocator.free(monitors);
        defer for (monitors) |monitor| monitor.deinit(allocator);
        result.commit(monitors);
    }
};
