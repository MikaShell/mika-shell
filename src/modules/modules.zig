const std = @import("std");
const common = @import("common.zig");
pub fn Callable(comptime T: type) type {
    return *const fn (self: T, args: *const common.Value, result: *common.Result) anyerror!void;
}
pub fn Entry(comptime T: type) type {
    return struct {
        self: T,
        call: Callable(T),
    };
}
const AnyEntry = Entry(*anyopaque);
pub const Modules = struct {
    table: std.StringHashMap(AnyEntry),
    pub fn init(allocator: std.mem.Allocator) Modules {
        return Modules{
            .table = std.StringHashMap(AnyEntry).init(allocator),
        };
    }
    pub fn deinit(self: *Modules) void {
        self.table.deinit();
    }
    pub fn call(self: *Modules, name: []const u8, args: *const common.Value, result: *common.Result) !void {
        const entry = self.table.get(name) orelse {
            return error.FunctionNotFound;
        };
        return entry.call(entry.self, args, result);
    }
    pub fn register(
        self: *Modules,
        module: anytype,
        name: []const u8,
        comptime function: Callable(@TypeOf(module)),
    ) !void {
        const wrap: Callable(*anyopaque) = comptime blk: {
            const wrapper = struct {
                fn wrap(self_: *anyopaque, args: *const common.Value, result: *common.Result) !void {
                    return function(@ptrCast(self_), args, result);
                }
            };
            break :blk &wrapper.wrap;
        };
        const entry = AnyEntry{
            .self = module,
            .call = wrap,
        };
        if (self.table.contains(name)) {
            return error.FunctionAlreadyRegistered;
        }
        self.table.put(name, entry) catch unreachable;
    }
};
const TestModule = struct {
    pub fn show(_: *TestModule, _: *const common.Value, result: *common.Result) !void {
        try result.commit("Hello, world!");
    }
    pub fn throw(_: *TestModule, _: *const common.Value, _: *common.Result) !void {
        return error.TestError;
    }
};
const webkit = @import("webkit");

test "register and call" {
    const allocator = std.testing.allocator;
    var m = Modules.init(allocator);
    defer m.deinit();
    var testModule = TestModule{};
    const t = &testModule;
    try m.register(t, "show", &TestModule.show);
    try m.register(t, "throw", &TestModule.throw);
    try std.testing.expectError(error.FunctionAlreadyRegistered, m.register(t, "show", &TestModule.show));

    const args = try std.json.parseFromSlice(std.json.Value, allocator, "[]", .{});
    defer args.deinit();
    var result = common.Result.init(allocator);
    defer result.deinit();

    try m.call("show", &args, &result);
    try std.testing.expectEqualStrings("\"Hello, world!\"", result.buffer.items);
    const ctx = webkit.JSCContext.new();
    const jsvalue = result.toJSCValue(ctx);
    try std.testing.expectEqualStrings("\"Hello, world!\"", jsvalue.toJson(0));

    try std.testing.expectError(error.TestError, m.call("throw", &args, &result));
}
