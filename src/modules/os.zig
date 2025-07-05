const modules = @import("modules.zig");
const Args = modules.Args;
const Result = modules.Result;
const App = @import("../app.zig").App;
const std = @import("std");
pub const OS = struct {
    const Self = @This();
    pub fn getEnv(_: *Self, args: Args, result: *Result) !void {
        const key = try args.string(1);
        const allocator = std.heap.page_allocator;
        const value = try std.process.getEnvVarOwned(allocator, key);
        defer allocator.free(value);
        _ = try result.commit(value);
    }
};
