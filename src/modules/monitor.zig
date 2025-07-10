const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const std = @import("std");
const Allocator = std.mem.Allocator;
const gtk = @import("gtk");
pub const Monitor = struct {
    const Self = @This();
    allocator: Allocator,
    pub fn list(self: *Self, _: Args, result: *Result) !void {
        const allocator = self.allocator;
        const monitors = try gtk.Monitor.get(allocator);
        defer allocator.free(monitors);
        defer for (monitors) |monitor| monitor.deinit(allocator);
        result.commit(monitors);
    }
};
