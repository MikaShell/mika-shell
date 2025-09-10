const libdbus = @import("libdbus.zig");
const std = @import("std");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;
const Message = libdbus.Message;
const Bus = @import("bus.zig").Bus;
const Errors = @import("bus.zig").Errors;
const Result = common.Result;
pub fn ResultGet(T: type) type {
    return struct {
        result: Result,
        value: T.Type,
        pub fn deinit(self: @This()) void {
            self.result.deinit();
        }
    };
}
pub const ResultGetAll = struct {
    result: Result,
    allocator: Allocator,
    map: *std.StringHashMap(Type.AnyVariant.Type),
    pub fn get(self: ResultGetAll, key: []const u8, ValueType: type) ?ValueType.Type {
        const val = self.map.get(key);
        if (val == null) return null;
        return val.?.as(ValueType);
    }
    pub fn deinit(self: ResultGetAll) void {
        self.result.deinit();
        self.map.deinit();
        self.allocator.destroy(self.map);
    }
};

pub const Object = struct {
    const Self = @This();
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    uniqueName: []const u8,
    allocator: Allocator,
    err: *Error,
    bus: *Bus,
    listeners: std.ArrayList(common.Listener),
    pub fn init(bus: *Bus, name: []const u8, path: []const u8, iface: []const u8) !*Self {
        const allocator = bus.allocator;
        bus.err.reset();
        const req = try common.call(allocator, bus.conn, bus.err, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", .{Type.String}, .{name});
        defer req.deinit();
        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);
        const err = try allocator.create(Error);
        errdefer allocator.destroy(err);
        err.init();
        obj.* = .{
            .bus = bus,
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .iface = try allocator.dupe(u8, iface),
            .uniqueName = try allocator.dupe(u8, req.next(Type.String)),
            .listeners = std.ArrayList(common.Listener){},
            .allocator = allocator,
            .err = err,
        };
        try bus.objects.append(allocator, obj);
        return obj;
    }
    pub fn deinit(self: *Self) void {
        {
            var i: usize = self.listeners.items.len;
            while (i > 0) {
                i -= 1;
                const listener = self.listeners.items[i];
                self.disconnect(listener.signal, listener.handler, listener.data) catch continue;
            }
        }
        self.err.deinit();
        self.allocator.destroy(self.err);
        self.listeners.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.free(self.iface);
        self.allocator.free(self.uniqueName);

        for (self.bus.objects.items, 0..) |obj, i| {
            if (obj == self) {
                _ = self.bus.objects.swapRemove(i);
                break;
            }
        }
        self.allocator.destroy(self);
    }
    fn callWithSelf(self: *Self, name: []const u8, path: []const u8, iface: []const u8, method: []const u8, comptime argsType: anytype, args: Type.getTupleTypes(argsType)) common.CallError!Result {
        self.err.reset();
        return common.call(
            self.allocator,
            self.bus.conn,
            self.err,
            name,
            path,
            iface,
            method,
            argsType,
            args,
        );
    }
    /// 调用一个 dbus 方法, 并返回结果
    ///
    /// argsType 和 resultType: 是方法的参数类型,接受一个 Tuple 描述方法调用的参数的类型
    ///
    /// args 是实际传入的参数,根据 argsType 决定传入的参数类型:
    /// ```
    /// {dbus.String, dbus.Int32, dbus.Array(dbus.String)}
    /// ```
    /// 根据上方的类型, args 应当与 argsType 匹配:
    /// ```
    /// .{ "hello", 123, &.{ "world", "foo" } }
    /// ```
    /// `const result = object.call(xxx);`
    /// 从 result.values 中获取返回值, resulr.value 会根据传入的 resulrType 进行类型转换.
    /// 使用完成后,必须调用 result.deinit() 释放资源
    pub fn call(self: *Object, name: []const u8, comptime argsType: anytype, args: Type.getTupleTypes(argsType)) common.CallError!Result {
        return self.callWithSelf(
            self.name,
            self.path,
            self.iface,
            name,
            argsType,
            args,
        );
    }
    /// 发送但不接收回复, 此函数不会返回 error.DBusError
    pub fn callN(self: *Object, name: []const u8, comptime argsType: anytype, args: Type.getTupleTypes(argsType)) common.CallNError!void {
        return common.callN(
            self.allocator,
            self.bus.conn,
            self.name,
            self.path,
            self.iface,
            name,
            argsType,
            args,
        );
    }
    /// 获取属性值
    pub fn get(self: *Object, name: []const u8, ResultTyep: type) !ResultGet(ResultTyep) {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Get",
            .{ Type.String, Type.String },
            .{ self.iface, name },
        );
        return .{ .result = resp, .value = resp.next(Type.AnyVariant).as(ResultTyep) };
    }
    pub fn getBasic(self: *Object, name: []const u8, ResultTyep: type) !ResultTyep.Type {
        switch (ResultTyep) {
            Type.Byte,
            Type.Boolean,
            Type.Int16,
            Type.Int32,
            Type.Int64,
            Type.UInt16,
            Type.UInt32,
            Type.UInt64,
            Type.Double,
            => {},
            else => {
                @panic("getBasic only support basic type");
            },
        }
        const resp = try self.get(name, ResultTyep);
        defer resp.deinit();
        return resp.value;
    }
    pub fn getAlloc(self: *Object, allocator: Allocator, name: []const u8, ResultTyep: type) !ResultTyep.Type {
        switch (ResultTyep) {
            Type.String,
            Type.ObjectPath,
            Type.Signature,
            Type.Array(Type.Byte),
            => {},
            else => {
                @panic("getAlloc only support string, objectpath, signature and byte array");
            },
        }
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Get",
            .{ Type.String, Type.String },
            .{ self.iface, name },
        );
        defer resp.deinit();
        return try allocator.dupe(u8, resp.next(Type.AnyVariant).as(ResultTyep));
    }
    /// 设置属性值
    pub fn set(self: *Object, name: []const u8, Value: type, value: Value.Type) !void {
        const Variant = Type.Variant(Value);
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "Set",
            .{ Type.String, Type.String, Variant },
            .{ self.iface, name, Variant.init(&value) },
        );
        defer resp.deinit();
    }
    /// 获取所有属性值
    pub fn getAll(self: *Object) (error{NoResult} || common.CallError)!ResultGetAll {
        const resp = try self.callWithSelf(
            self.name,
            self.path,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            .{Type.String},
            .{self.iface},
        );
        const HashMap = std.StringHashMap(Type.AnyVariant.Type);
        const map = try self.allocator.create(HashMap);
        map.* = HashMap.init(self.allocator);
        const dict = resp.next(Type.Dict(Type.String, Type.AnyVariant));
        for (dict) |entry| {
            try map.put(entry.key, entry.value);
        }
        return ResultGetAll{
            .allocator = self.allocator,
            .map = map,
            .result = resp,
        };
    }
    /// 调用 Ping 方法
    pub fn ping(self: *Object) bool {
        const r = self.callWithSelf(self.name, self.path, "org.freedesktop.DBus.Peer", "Ping", .{}, .{}) catch {
            return false;
        };
        defer r.deinit();
        return true;
    }
    /// 监听信号
    ///
    /// 在回调中无需释放 Event 中的 iter, iter 会在回调退出后自动释放
    pub fn connect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        if (self.listeners.items.len == 0) {
            if (!try self.bus.addFilter(.{ .type = .signal }, signalHandler, self)) {
                return error.AddFilterFailed;
            }
        }
        for (self.listeners.items) |listener| {
            if (std.mem.eql(u8, listener.signal, signal)) {
                return;
            }
        }

        try self.bus.addMatch(.{ .type = .signal, .sender = self.uniqueName, .interface = self.iface, .member = signal, .path = self.path });

        self.listeners.append(self.allocator, .{
            .signal = signal,
            .handler = @ptrCast(handler),
            .data = data,
        }) catch @panic("OOM");
    }
    pub fn disconnect(self: *Object, signal: []const u8, handler: *const fn (common.Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        for (self.listeners.items, 0..) |listener, i| {
            if (std.mem.eql(u8, listener.signal, signal) and listener.handler == handler and listener.data == data) {
                _ = self.listeners.swapRemove(i);
                if (self.listeners.items.len == 0) {
                    self.bus.removeFilter(.{ .type = .signal }, signalHandler, self);
                }
                for (self.listeners.items) |l| {
                    if (std.mem.eql(u8, l.signal, signal)) {
                        return;
                    }
                }
                self.bus.removeMatch(.{ .type = .signal, .sender = self.uniqueName, .interface = self.iface, .member = signal, .path = self.path }) catch {
                    return error.RemoveMatchFailed;
                };
                return;
            }
        }
        return error.SignalOrHandlerNotFound;
    }
};
fn signalHandler(data: ?*anyopaque, msg: *Message) void {
    const obj: *Object = @ptrCast(@alignCast(data));
    const sender: []const u8 = msg.getSender();
    const iface_ = msg.getInterface();
    const path_ = msg.getPath();
    const member_ = msg.getMember();
    if (iface_ == null) return;
    if (path_ == null) return;
    if (member_ == null) return;
    const iface = iface_.?;
    const path = path_.?;
    const member = member_.?;
    const destination = msg.getDestination();
    const eql = std.mem.eql;
    if (!eql(u8, iface, obj.iface)) return;
    if (!eql(u8, path, obj.path)) return;
    if (!(eql(u8, sender, obj.uniqueName) or std.mem.eql(u8, sender, obj.name))) return;
    var event = common.Event{
        .sender = sender,
        .iface = iface,
        .path = path,
        .member = member,
        .serial = msg.getSerial(),
        .destination = destination,
        .iter = libdbus.MessageIter.init(obj.allocator),
    };
    defer event.iter.deinit();
    for (obj.listeners.items) |listener| {
        if (!eql(u8, listener.signal, member)) continue;
        event.iter.reset();
        _ = event.iter.fromResult(msg);
        listener.handler(event, listener.data);
    }
}
const testing = std.testing;
const print = std.debug.print;
const withGLibLoop = @import("bus.zig").withGLibLoop;

test "ping" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try testing.expect(proxy.ping());
}

test "call" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.call("GetArrayString", .{}, .{});
    defer resp.deinit();
    const val = resp.next(Type.Array(Type.String));
    try testing.expectEqualStrings("foo", val[0]);
    try testing.expectEqualStrings("bar", val[1]);
    try testing.expectEqualStrings("baz", val[2]);
}

test "get" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = try proxy.get("Byte", Type.Byte);
    defer resp.deinit();
    try testing.expectEqual(123, resp.value);
}

test "get-all" {
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
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
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.set("Boolean", Type.Boolean, true);
    try proxy.set("Boolean", Type.Boolean, false);
}
fn test_on_signal1(event: common.Event, err_: ?*anyopaque) void {
    const err: *anyerror = @ptrCast(@alignCast(err_.?));
    const value = event.iter.getAll(.{ Type.String, Type.Int32 });
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
const utils = @import("utils.zig");
test "signal" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    var err: ?anyerror = null;
    try proxy.connect("Signal1", test_on_signal1, &err);
    utils.timeoutMainLoop(200);
    try testing.expect(err != null);
    try testing.expect(err.? == error.OK);
}
// 用于测试 NameOwnerChanged 信号是否正常工作, 需要手动测试
// test "signal-owner-changed" {
//     const allocator = testing.allocator;
//     const bus = Bus.init(allocator, .Session) catch unreachable;
//     defer bus.deinit();
//     var proxy = try bus.proxy("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher");
//     defer proxy.deinit();
//     utils.timeoutMainLoop(300);
// }
test "signal-disconnect" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.connect("Signal1", test_on_signal1, null);
    try proxy.disconnect("Signal1", test_on_signal1, null);
    try testing.expectError(error.SignalOrHandlerNotFound, proxy.disconnect("Signal1", test_on_signal1, null));
}
test "get-error" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    var proxy = try bus.proxy("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.callN("GetError", .{}, .{});
}
