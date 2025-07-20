const std = @import("std");
const common = @import("./modules/modules.zig");
const Args = common.Args;
const Result = common.Result;
const Callable = common.Callable;
const Context = common.Context;
const Registry = common.Registry;
pub fn Entry(comptime T: type) type {
    return struct {
        self: T,
        call: Callable(T),
    };
}
const AnyEntry = Entry(*anyopaque);
const App = @import("app.zig").App;
pub const Modules = struct {
    const Registered = struct {
        ptr: *anyopaque,
        deinit: *const fn (*anyopaque, Allocator) void,
    };
    allocator: std.mem.Allocator,
    table: std.StringHashMap(AnyEntry),
    ctx: Context,
    registered: std.ArrayList(Registered),
    pub fn init(allocator: std.mem.Allocator, app: *App, systemBus: *dbus.Bus, sessionBus: *dbus.Bus) *Modules {
        const m = allocator.create(Modules) catch unreachable;
        m.* = .{
            .table = std.StringHashMap(AnyEntry).init(allocator),
            .allocator = allocator,
            .ctx = .{
                .allocator = allocator,
                .app = app,
                .systemBus = systemBus,
                .sessionBus = sessionBus,
            },
            .registered = std.ArrayList(Registered).init(allocator),
        };
        return m;
    }
    pub fn deinit(self: *Modules) void {
        self.table.deinit();
        for (self.registered.items) |module| {
            module.deinit(module.ptr, self.allocator);
        }
        self.registered.deinit();
        self.allocator.destroy(self);
    }
    pub fn call(self: *Modules, name: []const u8, args: Args, result: *Result) !void {
        const entry = self.table.get(name) orelse {
            return error.FunctionNotFound;
        };
        return entry.call(entry.self, args, result);
    }
    pub fn mount(self: *Modules, comptime Module_: type, comptime name: []const u8) !void {
        const m = try Module_.init(self.ctx);
        try self.registered.append(.{
            .ptr = m,
            .deinit = @ptrCast(&Module_.deinit),
        });
        const table = comptime blk: {
            const table = Module_.register();
            var tb: [table.len]std.meta.Tuple(&.{ []const u8, Callable(*Module_) }) = undefined;
            for (table, 0..) |entry, i| {
                const name_ = name ++ "." ++ entry[0];
                tb[i] = .{ name_, entry[1] };
            }
            break :blk tb;
        };
        inline for (table) |entry| {
            self.register(m, entry[0], entry[1]);
        }
    }
    fn register(
        self: *Modules,
        module: anytype,
        comptime name: []const u8,
        comptime function: Callable(@TypeOf(module)),
    ) void {
        const wrap: Callable(*anyopaque) = comptime blk: {
            const wrapper = struct {
                fn wrap(self_: *anyopaque, args: Args, result: *Result) !void {
                    return function(@ptrCast(@alignCast(self_)), args, result);
                }
            };
            break :blk &wrapper.wrap;
        };
        const entry = AnyEntry{
            .self = module,
            .call = wrap,
        };
        if (self.table.contains(name)) {
            @panic("function already registered");
        }
        self.table.put(name, entry) catch unreachable;
    }
};
const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const TestModule = struct {
    pub fn init(ctx: Context) !*@This() {
        const m = try ctx.allocator.create(@This());
        return m;
    }
    pub fn register() Registry(@This()) {
        return &.{
            .{ "show", show },
            .{ "throw", throw },
            .{ "testArgs", testArgs },
        };
    }
    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.destroy(self);
    }
    pub fn show(_: *TestModule, _: Args, result: *Result) !void {
        result.commit("Hello, world!");
    }
    pub fn throw(_: *TestModule, _: Args, _: *Result) !void {
        return error.TestError;
    }
    pub fn testArgs(_: *TestModule, args: Args, _: *Result) !void {
        _ = try args.integer(0);
        _ = try args.bool(1);
        _ = try args.string(2);
        _ = try args.array(3);
        _ = try args.object(4);
    }
};
const webkit = @import("webkit");

test "register and call" {
    const allocator = std.testing.allocator;
    var m = Modules.init(allocator, undefined, undefined, undefined);
    defer m.deinit();
    try m.mount(TestModule, "test");

    const jsonStr =
        \\{
        \\    "args": [
        \\        2,
        \\        true,
        \\        "hello",
        \\        [3,4,5],
        \\        {"foo":"bar"}
        \\    ]
        \\}
    ;
    const v = try std.json.parseFromSlice(std.json.Value, allocator, jsonStr, .{});
    defer v.deinit();
    const value = Args{ .items = v.value.object.get("args").?.array.items };
    var result = Result.init(allocator);
    defer result.deinit();
    try m.call("test.show", value, &result);
    try std.testing.expectEqualStrings("\"Hello, world!\"", result.buffer.?.items);
    const ctx = webkit.JSCContext.new();
    const jsvalue = result.toJSCValue(ctx);
    try std.testing.expectEqualStrings("\"Hello, world!\"", jsvalue.toJson(0));
    try std.testing.expectError(error.TestError, m.call("test.throw", value, &result));

    try m.call("test.testArgs", value, &result);
}
