const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;
const Message = libdbus.Message;

pub const Bus = struct {
    const Self = @This();
    conn: *libdbus.Connection,
    uniqueName: []const u8,
    err: Error,
    allocator: Allocator,
    dbus: *Object,
    objects: std.ArrayList(*Object),
    watch: ?glib.FdWatch(Self) = null,
    pub fn init(allocator: Allocator, bus_type: libdbus.BusType) !*Bus {
        var err = Error.init();
        const conn = try libdbus.Connection.get(bus_type, err);
        const bus = try allocator.create(Self);
        errdefer allocator.destroy(bus);
        errdefer err.deinit();
        errdefer conn.unref();
        bus.* = Bus{
            .conn = conn,
            .uniqueName = conn.getUniqueName(),
            .err = err,
            .allocator = allocator,
            .dbus = undefined,
            .objects = std.ArrayList(*Object).init(allocator),
        };
        bus.dbus = try bus.object("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
        try bus.dbus.connect("NameOwnerChanged", struct {
            fn f(e: common.Event, data: ?*anyopaque) void {
                const bus_: *Self = @ptrCast(@alignCast(data));
                const values = e.iter.getAll(.{ Type.String, Type.String, Type.String }) catch unreachable;
                const oldOwner = values[1];
                const newOwner = values[2];
                const isNewService = std.mem.eql(u8, oldOwner, "");

                for (bus_.objects.items) |obj| {
                    if (std.mem.eql(u8, obj.uniqueName, "")) {
                        if (isNewService) {
                            const resp = bus_.dbus.call("GetNameOwner", .{Type.String}, .{obj.name}, .{Type.String}) catch {
                                bus_.dbus.err.reset();
                                continue;
                            };
                            defer resp.deinit();
                            const owner = resp.values.?[0];
                            const owner_ = obj.allocator.dupe(u8, owner) catch @panic("OOM");
                            if (std.mem.eql(u8, owner_, newOwner)) {
                                obj.uniqueName = owner_;
                                break;
                            } else {
                                obj.allocator.free(owner_);
                            }
                        }
                    } else if (std.mem.eql(u8, obj.uniqueName, oldOwner)) {
                        const old = obj.uniqueName;
                        obj.uniqueName = obj.allocator.dupe(u8, newOwner) catch @panic("OOM");
                        obj.allocator.free(old);
                    }
                }
            }
        }.f, bus);
        try bus.conn.addMatch("type='signal'", err);
        errdefer bus.conn.removeMatch("type='signal'", err) catch err.reset();
        bus.watch = try glib.FdWatch(Bus).add(try bus.conn.getUnixFd(), signalHandler, bus);
        return bus;
    }
    fn signalHandler(bus: *Bus) bool {
        if (!bus.conn.readWrite(-1)) return false;
        defer _ = bus.conn.dispatch();
        if (bus.objects.items.len == 0) return true;
        const msg = bus.conn.popMessage();
        if (msg == null) return true;
        const m = msg.?;
        defer m.deinit();
        const type_ = m.getType();
        const sender = m.getSender();
        const iface = m.getInterface();
        const path = m.getPath();
        const member = m.getMember();
        const destination = m.getDestination();
        if (type_ != .Signal) return true;
        for (bus.objects.items) |proxy| {
            if (destination != null or (destination != null and !std.mem.eql(u8, destination.?, proxy.uniqueName))) continue;
            if (!std.mem.eql(u8, sender, proxy.name) and !std.mem.eql(u8, sender, proxy.uniqueName)) continue;
            if (!std.mem.eql(u8, iface, proxy.iface)) continue;
            if (!std.mem.eql(u8, path, proxy.path)) continue;
            var event = common.Event{
                .sender = sender,
                .iface = iface,
                .path = path,
                .member = member,
                .serial = m.getSerial(),
                .destination = destination,
                .iter = libdbus.MessageIter.init(proxy.allocator) catch unreachable,
            };
            defer event.iter.deinit();
            for (proxy.listeners.items) |listener| {
                if (std.mem.eql(u8, listener.signal, member)) {
                    event.iter.reset();
                    _ = event.iter.fromResult(m);
                    listener.handler(event, listener.data);
                }
            }
        }

        return true;
    }
    pub fn deinit(self: *Self) void {
        self.conn.unref();
        self.err.deinit();
        for (0..self.objects.items.len) |i| {
            self.objects.items[i].deinit();
        }
        if (self.watch) |w| w.deinit();
        self.objects.deinit();
        self.allocator.destroy(self);
    }
    pub fn object(self: *Self, name: []const u8, path: []const u8, iface: []const u8) !*Object {
        const req = try baseCall(self.allocator, self.conn, self.err, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", .{Type.String}, .{name}, .{Type.String});
        defer req.deinit();
        const uniqueName = req.values.?[0];
        const obj = try self.allocator.create(Object);
        errdefer self.allocator.destroy(obj);
        obj.* = Object{
            .name = name,
            .path = path,
            .iface = iface,
            .bus = self,
            .allocator = self.allocator,
            .err = Error.init(),
            .listeners = std.ArrayList(common.Listener).init(self.allocator),
            .uniqueName = try self.allocator.dupe(u8, uniqueName),
        };
        try self.objects.append(obj);
        return obj;
    }
};

pub fn Result(T: type) type {
    return struct {
        response: *libdbus.Message,
        iter: *libdbus.MessageIter,
        values: ?T,
        pub fn deinit(self: @This()) void {
            self.response.deinit();
            self.iter.deinit();
        }
    };
}
pub fn GetResult(T: type) type {
    return struct {
        result: Result(std.meta.Tuple(&.{Type.Variant.Type})),
        value: T,
        pub fn deinit(self: @This()) void {
            self.result.deinit();
        }
    };
}
pub const GetAllResult = struct {
    result: Result(Type.getTupleTypes(.{Type.Dict(Type.String, Type.Variant)})),
    allocator: Allocator,
    map: *std.StringHashMap(Type.Variant.Type),
    pub fn get(self: GetAllResult, key: []const u8, ValueType: type) ?ValueType.Type {
        const val = self.map.get(key);
        if (val == null) return null;
        return val.?.get(ValueType) catch return null;
    }
    pub fn deinit(self: GetAllResult) void {
        self.result.deinit();
        self.map.deinit();
        self.allocator.destroy(self.map);
    }
};
fn baseCall(
    allocator: Allocator,
    conn: *libdbus.Connection,
    err: Error,
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    method: []const u8,
    comptime argsType: anytype,
    args: ?Type.getTupleTypes(argsType),
    comptime resultType: anytype,
) !Result(Type.getTupleTypes(resultType)) {
    const args_info = @typeInfo(@TypeOf(argsType));
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("expected a tuple, found " ++ @typeName(@TypeOf(argsType)));
    }
    const request = libdbus.Message.newMethodCall(name, path, iface, method);
    defer request.deinit();
    const iter = try libdbus.MessageIter.init(allocator);
    errdefer iter.deinit();
    iter.fromAppend(request);
    if (args != null) {
        inline for (args.?, 0..) |arg, i| {
            try iter.append(argsType[i], arg);
        }
    }
    const response = try conn.sendWithReplyAndBlock(request, -1, err);
    const hasResult = iter.fromResult(response);
    return .{
        .response = response,
        .iter = iter,
        .values = if (hasResult) try iter.getAll(resultType) else null,
    };
}

pub const Object = struct {
    const Self = @This();
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    uniqueName: []const u8,
    bus: *Bus,
    allocator: Allocator,
    err: Error,
    listeners: std.ArrayList(common.Listener),
    pub fn deinit(self: *Self) void {
        self.err.deinit();
        self.listeners.deinit();
        self.allocator.free(self.uniqueName);
        for (self.bus.objects.items, 0..) |obj, i| {
            if (obj == self) {
                // FIXME: 考虑线程安全
                _ = self.bus.objects.swapRemove(i);
                break;
            }
        }
        self.allocator.destroy(self);
    }
    fn callWithSelf(self: *Self, name: []const u8, path: []const u8, iface: []const u8, method: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType), comptime resultType: anytype) !Result(Type.getTupleTypes(resultType)) {
        return baseCall(
            self.allocator,
            self.bus.conn,
            self.err,
            name,
            path,
            iface,
            method,
            argsType,
            args,
            resultType,
        );
    }
    pub fn call(self: *Object, name: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType), comptime resultType: anytype) !Result(Type.getTupleTypes(resultType)) {
        return self.callWithSelf(
            self.name,
            self.path,
            self.iface,
            name,
            argsType,
            args,
            resultType,
        );
    }
    // 发送但不接收回复
    pub fn callN(self: *Object, name: []const u8, comptime argsType: anytype, args: ?Type.getTupleTypes(argsType)) !void {
        const request = libdbus.Message.newMethodCall(self.name, self.path, self.iface, name);
        defer request.deinit();
        const iter = try libdbus.MessageIter.init(self.allocator);
        defer iter.deinit();
        iter.fromAppend(request);
        if (args != null) {
            for (args.?, 0..) |arg, i| {
                try iter.append(argsType[i], arg);
            }
        }
        if (!self.bus.conn.send(request, null)) {
            return error.SendFailed;
        }
    }
    pub fn get(self: *Object, name: []const u8, ResultTyep: type) !GetResult(ResultTyep.Type) {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Get",
            .{ Type.String, Type.String },
            .{ self.iface, name },
            .{Type.Variant},
        );
        return .{ .result = resp, .value = try resp.values.?[0].get(ResultTyep) };
    }
    pub fn set(self: *Object, name: []const u8, Value: type, value: Value.Type) !void {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Set",
            .{ Type.String, Type.String, Type.Variant },
            .{ self.iface, name, Type.Variant.init(Value, value) },
            .{},
        );
        defer resp.deinit();
    }
    pub fn getAll(self: *Object) !GetAllResult {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            .{Type.String},
            .{self.iface},
            .{Type.Dict(Type.String, Type.Variant)},
        );
        const HashMap = std.StringHashMap(Type.Variant.Type);
        const map = try self.allocator.create(HashMap);
        map.* = HashMap.init(self.allocator);
        const dict = resp.values.?[0];
        for (dict) |entry| {
            try map.put(entry.key, entry.value);
        }
        return GetAllResult{
            .allocator = self.allocator,
            .map = map,
            .result = resp,
        };
    }
    pub fn connect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        try self.listeners.append(.{
            .signal = signal,
            .handler = @ptrCast(handler),
            .data = data,
        });
    }
    pub fn disconnect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void) !void {
        for (self.listeners.items, 0..) |listener, i| {
            if (std.mem.eql(u8, listener.signal, signal) and listener.handler == handler) {
                _ = self.listeners.swapRemove(i);
                return;
            }
        }
        return error.SignalOrHandlerNotFound;
    }
};

const testing = std.testing;
const print = std.debug.print;
fn test_main_loop(timeout_ms: u32) void {
    const loop = glib.c.g_main_loop_new(null, 0);
    _ = glib.c.g_timeout_add(timeout_ms, &struct {
        fn timeout(loop_: ?*anyopaque) callconv(.c) c_int {
            const loop__: *glib.c.GMainLoop = @ptrCast(@alignCast(loop_));
            glib.c.g_main_loop_quit(loop__);
            return 0;
        }
    }.timeout, loop);
    glib.c.g_main_loop_run(loop);
}
test "call" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.call("GetArrayString", .{}, null, .{Type.Array(Type.String)});
    defer resp.deinit();
    const val = resp.values.?[0];
    try testing.expectEqualStrings("foo", val[0]);
    try testing.expectEqualStrings("bar", val[1]);
    try testing.expectEqualStrings("baz", val[2]);
}

test "get" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.get("Byte", Type.Byte);
    defer resp.deinit();
    try testing.expectEqual(123, resp.value);
}

test "get-all" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.getAll();
    defer resp.deinit();
    try testing.expectEqual(123, resp.get("Byte", Type.Byte).?);
    try testing.expectEqual(-32768, resp.get("Int16", Type.Int16).?);
}

test "set" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.set("Boolean", Type.Boolean, true);
    try proxy.set("Boolean", Type.Boolean, false);
}
fn test_on_signal1(event: common.Event, err_: ?*anyopaque) void {
    const err: *anyerror = @ptrCast(@alignCast(err_.?));
    const value = event.iter.getAll(.{ Type.String, Type.Int32 }) catch unreachable;
    err.* = error.OK;
    testing.expectEqualStrings("TestSignal", value[0]) catch |er| {
        err.* = er;
        return;
    };
    testing.expectEqual(78787, value[1]) catch |er| {
        err.* = er;
        return;
    };
}
test "signal" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    var err: ?anyerror = null;
    try proxy.connect("Signal1", test_on_signal1, &err);
    test_main_loop(200);
    try testing.expect(err != null);
    try testing.expect(err.? == error.OK);
}
// 用于测试 NameOwnerChanged 信号是否正常工作, 需要手动测试
// test "signal-owner-changed" {
//     const allocator = testing.allocator;
//     const bus = Bus.init(allocator, .Session) catch unreachable;
//     defer bus.deinit();
//     var proxy = try bus.object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher");
//     defer proxy.deinit();
//     test_main_loop(300);
// }
test "signal-disconnect" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.connect("Signal1", test_on_signal1, null);
    try proxy.disconnect("Signal1", test_on_signal1);
    try testing.expectError(error.SignalOrHandlerNotFound, proxy.disconnect("Signal1", test_on_signal1));
}
test "get-error" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.callN("GetError", .{}, null);
}
