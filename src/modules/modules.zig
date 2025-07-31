const std = @import("std");
/// 放心地在 Modules 回调中使用 try xxx(n), xxx是参数类型, n是参数的位置
///
/// 如果参数不符合预期,则会返回 error.InvalidArgs, 可以直接将此错误返回给前端
pub const Args = struct {
    items: []std.json.Value,
    fn verifyIndex(self: Args, index: usize) !void {
        if (index >= self.items.len) return error.InvalidArgs;
    }
    pub fn value(self: Args, index: usize) !std.json.Value {
        try self.verifyIndex(index);
        return self.items[index];
    }
    pub fn @"bool"(self: Args, index: usize) !bool {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .bool => |b| return b,
            else => return error.InvalidArgs,
        }
    }
    pub fn integer(self: Args, index: usize) !i64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .integer => |i| return i,
            else => return error.InvalidArgs,
        }
    }
    pub fn uInteger(self: Args, index: usize) !u64 {
        const i = try self.integer(index);
        if (i < 0) return error.InvalidArgs;
        return @intCast(i);
    }
    pub fn float(self: Args, index: usize) !f64 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .float => |f| return f,
            else => return error.InvalidArgs,
        }
    }
    pub fn string(self: Args, index: usize) ![]const u8 {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .string => |s| return s,
            else => return error.InvalidArgs,
        }
    }
    pub fn array(self: Args, index: usize) !std.json.Array {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .array => |a| return a,
            else => return error.InvalidArgs,
        }
    }
    pub fn object(self: Args, index: usize) !std.json.ObjectMap {
        try self.verifyIndex(index);
        switch (self.items[index]) {
            .object => |o| return o,
            else => return error.InvalidArgs,
        }
    }
};

pub const Result = struct {
    allocator: std.mem.Allocator,
    buffer: ?std.ArrayList(u8) = null,
    err: ?[]const u8 = null,
    pub fn init(allocator: std.mem.Allocator) Result {
        return .{
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *Result) void {
        if (self.buffer) |b| b.deinit();
        if (self.err) |e| self.allocator.free(e);
    }
    pub fn commit(self: *Result, value: anytype) void {
        if (self.buffer != null) @panic("commit twice");
        self.buffer = std.ArrayList(u8).init(self.allocator);
        std.json.stringify(value, .{}, self.buffer.?.writer()) catch @panic("OOM");
    }
    /// 总是返回一个 error.HasError, 切勿捕获该错误, 应该直接返回给 Webview 处理
    pub fn errors(self: *Result, comptime fmt: []const u8, args: anytype) anyerror {
        self.err = std.fmt.allocPrint(self.allocator, fmt, args) catch @panic("OOM");
        return error.HasError;
    }
    pub fn toJSCValue(self: *Result, ctx: *webkit.JSCContext) *webkit.JSCValue {
        if (self.err != null) @panic("error message is not null, cannot convert to JSCValue");
        if (self.buffer == null) return ctx.newUndefined();
        const str = self.allocator.dupeZ(u8, self.buffer.?.items) catch @panic("OOM");
        defer self.allocator.free(str);
        return ctx.newFromJson(str);
    }
};

pub fn Callable(comptime T: type) type {
    return *const fn (self: T, args: Args, result: *Result) anyerror!void;
}
const App = @import("../app.zig").App;
pub const Context = struct {
    allocator: std.mem.Allocator,
    app: *App,
    systemBus: *dbus.Bus,
    sessionBus: *dbus.Bus,
};
pub fn Registry(T: type) type {
    return struct {
        exports: []const std.meta.Tuple(&.{ []const u8, Callable(*T) }) = &.{},
        events: []const events.Events = &.{},
    };
}
const webkit = @import("webkit");
const dbus = @import("dbus");
const events = @import("../events.zig");
