const std = @import("std");
const webkit = @import("webkit");

pub const Value = std.json.Parsed(std.json.Value);
pub const Result = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    pub fn init(allocator: std.mem.Allocator) Result {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    pub fn deinit(self: *Result) void {
        self.buffer.deinit();
    }
    pub fn commit(self: *Result, value: anytype) !void {
        try std.json.stringify(value, .{}, self.buffer.writer());
    }
    pub fn toJSCValue(self: *Result, ctx: *webkit.JSCContext) *webkit.JSCValue {
        if (self.buffer.items.len == 0) return ctx.newUndefined();
        const str = self.allocator.dupeZ(u8, self.buffer.items) catch unreachable;
        defer self.allocator.free(str);
        return ctx.newFromJson(str);
    }
};
