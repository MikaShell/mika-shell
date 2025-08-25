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
const events = @import("events.zig");
pub const Modules = struct {
    const Registered = struct {
        ptr: *anyopaque,
        deinit: *const fn (*anyopaque, Allocator) void,
    };
    pub const EventGroup = struct {
        events: []const events.Events,
        data: ?*anyopaque,
        start: ?*const fn (?*anyopaque) anyerror!void,
        stop: ?*const fn (?*anyopaque) anyerror!void,
        onChanged: ?*const fn (?*anyopaque, events.ChangeState, events.Events) void,
    };
    allocator: std.mem.Allocator,
    table: std.StringHashMap(AnyEntry),
    ctx: Context,
    registered: std.ArrayList(Registered),
    eventGroups: std.ArrayList(EventGroup),

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
            .eventGroups = std.ArrayList(EventGroup).init(allocator),
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
        const functions = comptime blk: {
            const registry: Registry(Module_) = Module_.register();
            const table = registry.exports;
            var tb: [table.len]std.meta.Tuple(&.{ []const u8, Callable(*Module_) }) = undefined;
            for (table, 0..) |entry, i| {
                const name_ = name ++ "." ++ entry[0];
                tb[i] = .{ name_, entry[1] };
            }
            break :blk tb;
        };
        inline for (functions) |entry| {
            self.register(m, entry[0], entry[1]);
        }
        const events_ = comptime blk: {
            const registry: Registry(Module_) = Module_.register();
            break :blk registry.events;
        };
        if (events_.len > 0) {
            var start: ?*const fn (*Module_) anyerror!void = null;
            var stop: ?*const fn (*Module_) anyerror!void = null;
            var onChanged: ?*const fn (*Module_, events.ChangeState, events.Events) void = null;
            if (@hasDecl(Module_, "eventStart")) {
                start = &Module_.eventStart;
            }
            if (@hasDecl(Module_, "eventStop")) {
                stop = &Module_.eventStop;
            }
            if (@hasDecl(Module_, "eventOnChange")) {
                onChanged = &Module_.eventOnChange;
            }
            try self.eventGroups.append(.{
                .events = try self.allocator.dupe(events.Events, events_),
                .start = @ptrCast(start),
                .stop = @ptrCast(stop),
                .data = @ptrCast(m),
                .onChanged = @ptrCast(onChanged),
            });
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
        return .{
            .exports = &.{
                .{ "show", show },
                .{ "throw", throw },
                .{ "testArgs", testArgs },
            },
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
const jsc = @import("jsc");
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
    const ctx = jsc.Context.new();
    defer ctx.unref();
    const jsvalue = result.toJSCValue(ctx);
    defer jsvalue.unref();
    try std.testing.expectEqualStrings("\"Hello, world!\"", std.mem.span(jsvalue.toJson(0)));
    try std.testing.expectError(error.TestError, m.call("test.throw", value, &result));

    try m.call("test.testArgs", value, &result);
}
pub const Emitter = struct {
    const Self = @This();
    const Group = struct {
        count: u32,
        group: Modules.EventGroup,
        fn has(self: Group, event: events.Events) bool {
            for (self.group.events) |e| {
                if (e == event) return true;
            }
            return false;
        }
        fn addOne(self: *Group, event: events.Events) !void {
            self.count += 1;
            if (self.count == 1) {
                if (self.group.start) |start| {
                    try start(self.group.data);
                }
            }
            if (self.group.onChanged) |onChanged| {
                onChanged(self.group.data, .add, event);
            }
        }
        fn removeOne(self: *Group, event: events.Events) !void {
            self.count -= 1;
            if (self.group.onChanged) |onChanged| {
                onChanged(self.group.data, .remove, event);
            }
            if (self.count == 0) {
                if (self.group.stop) |stop| {
                    try stop(self.group.data);
                }
            }
        }
    };
    allocator: Allocator,
    app: *App,
    subscriber: std.AutoHashMap(events.Events, std.ArrayList(u64)),
    channel: *events.EventChannel,
    groups: []Group,
    pub fn init(app: *App, allocator: Allocator, channel: *events.EventChannel, eventGroups: []Modules.EventGroup) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        var groups = try allocator.alloc(Group, eventGroups.len);
        errdefer allocator.free(groups);
        for (eventGroups, 0..) |group, i| {
            groups[i] = .{ .count = 0, .group = group };
        }
        self.* = .{
            .allocator = allocator,
            .app = app,
            .subscriber = std.AutoHashMap(events.Events, std.ArrayList(u64)).init(allocator),
            .channel = channel,
            .groups = groups,
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        var it = self.subscriber.valueIterator();
        while (it.next()) |v| v.deinit();
        self.subscriber.deinit();
        self.allocator.free(self.groups);
        self.allocator.destroy(self);
    }
    pub fn subscribe(
        self: *Self,
        args: Args,
        event: events.Events,
    ) !void {
        blk: {
            for (self.groups) |*group| {
                if (!group.has(event)) continue;
                try group.addOne(event);
                break :blk;
            }
            return error.UnkownEvent;
        }
        const id = args.uInteger(0) catch unreachable;
        const list = try self.subscriber.getOrPut(event);
        if (!list.found_existing) {
            list.value_ptr.* = std.ArrayList(u64).init(self.allocator);
        }
        for (list.value_ptr.items) |id_| {
            if (id_ == id) return;
        }
        try list.value_ptr.append(id);
    }
    pub fn unsubscribeAll(self: *Self, id: u64) void {
        var it = self.subscriber.iterator();
        var removed = std.ArrayList(events.Events).init(self.allocator);
        defer removed.deinit();
        while (it.next()) |kv| {
            const list = kv.value_ptr;
            for (list.items, 0..) |item, i| {
                if (item == id) {
                    _ = list.swapRemove(i);
                    try removed.append(kv.key_ptr.*);
                    break;
                }
            }
            if (list.items.len == 0) {
                list.deinit();
                _ = self.subscriber.remove(kv.key_ptr.*);
                self.allocator.free(kv.key_ptr.*);
            }
        }
        for (removed.items) |event| {
            for (self.groups) |*group| {
                if (!group.has(event)) continue;
                try group.removeOne(event);
                break;
            }
            unreachable;
        }
    }
    pub fn unsubscribe(
        self: *Self,
        args: Args,
        event: events.Events,
    ) !void {
        const id = args.uInteger(0) catch unreachable;
        const list = self.subscriber.getPtr(event) orelse return error.NotSubscribed;
        blk: {
            for (list.items, 0..) |item, i| {
                if (item != id) continue;
                _ = list.swapRemove(i);
                if (list.items.len == 0) {
                    list.deinit();
                    const key = self.subscriber.getKey(event).?;
                    _ = self.subscriber.remove(key);
                }
                break :blk;
            }
            return error.NotSubscribed;
        }
        for (self.groups) |*group| {
            if (!group.has(event)) continue;
            try group.removeOne(event);
            return;
        }
        unreachable;
    }
    pub fn emit(self: *Self, event: events.Events, data: anytype) void {
        const list = self.subscriber.get(event) orelse return;
        const json = std.json.stringifyAlloc(self.allocator, .{ .event = @intFromEnum(event), .data = data }, .{}) catch unreachable;
        defer self.allocator.free(json);
        for (list.items) |id| {
            const json_ = self.allocator.dupe(u8, json) catch unreachable;
            self.channel.store(.{ .dist = id, .allocator = self.allocator, .data = json_ }) catch unreachable;
        }
    }
};
