const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const Allocator = std.mem.Allocator;
const Value = libdbus.Value;
const Error = libdbus.Error;
const Type = libdbus.Type;
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
        const err = Error.init();
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
            fn f(e: Event, data: ?*anyopaque) void {
                const bus_: *Self = @ptrCast(@alignCast(data));
                const values = e.values.?;
                const oldOwner = values[1].string;
                const newOwner = values[2].string;
                const isNewService = std.mem.eql(u8, oldOwner, "");

                for (bus_.objects.items) |obj| {
                    if (std.mem.eql(u8, obj.uniqueName, "")) {
                        if (isNewService) {
                            const req = bus_.dbus.call("GetNameOwner", &[_]Value{Value{ .string = obj.name }}) catch {
                                bus_.dbus.err.reset();
                                continue;
                            };
                            defer req.deinit();
                            const owner = req.first() catch unreachable;
                            const owner_ = obj.allocator.dupe(u8, owner.string) catch @panic("OOM");
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
        return bus;
    }
    pub fn deinit(self: *Self) void {
        self.conn.unref();
        self.err.deinit();
        for (0..self.objects.items.len - 1) |i| {
            self.objects.items[i].deinit();
        }
        if (self.watch) |w| w.deinit();
        self.dbus.deinit();
        self.objects.deinit();
        self.allocator.destroy(self);
    }
    pub fn object(self: *Self, name: []const u8, path: []const u8, iface: []const u8) !*Object {
        const req = try scall(
            self.allocator,
            self.conn,
            self.err,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetNameOwner",
            &[_]Value{Value{ .string = name }},
        );
        defer req.deinit();
        const uniqueName = (try req.first()).string;
        const obj = try self.allocator.create(Object);
        errdefer self.allocator.destroy(obj);
        obj.* = Object{
            .name = name,
            .path = path,
            .iface = iface,
            .bus = self,
            .allocator = self.allocator,
            .err = Error.init(),
            .listeners = std.ArrayList(Listener).init(self.allocator),
            .uniqueName = try self.allocator.dupe(u8, uniqueName),
        };
        try self.objects.append(obj);
        return obj;
    }
};
pub const Result = struct {
    response: *libdbus.Message,
    iter: *libdbus.MessageIter,
    pub fn first(self: Result) !Value {
        const vs = try self.mustValues();
        if (vs.len < 1) {
            return error.NoValue;
        }
        return vs[0];
    }
    pub fn values(self: Result) !?[]Value {
        if (!self.iter.fromResult(self.response)) return null;
        return try self.iter.getAll();
    }
    pub fn mustValues(self: Result) ![]Value {
        return (try self.values()).?;
    }
    pub fn deinit(self: Result) void {
        self.response.deinit();
        self.iter.deinit();
    }
};
pub const GetResult = struct {
    result: Result,
    pub fn value(self: GetResult) !Value {
        const v = try self.result.first();
        return v.variant.*;
    }
    pub fn deinit(self: GetResult) void {
        self.result.deinit();
    }
};
pub const GetAllResult = struct {
    result: Result,
    allocator: Allocator,
    map: *std.StringHashMap(*const Value),
    pub fn deinit(self: GetAllResult) void {
        self.result.deinit();
        self.map.deinit();
        self.allocator.destroy(self.map);
    }
};
const Listener = struct {
    signal: []const u8,
    handler: *const fn (Event, ?*anyopaque) void,
    data: ?*anyopaque,
};
fn scall(
    allocator: Allocator,
    conn: *libdbus.Connection,
    err: Error,
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    method: []const u8,
    args: ?[]const Value,
) !Result {
    const request = libdbus.Message.newMethodCall(name, path, iface, method);
    defer request.deinit();
    const iter = try libdbus.MessageIter.init(allocator);
    defer iter.reset();
    errdefer iter.deinit();
    iter.fromAppend(request);
    if (args != null) {
        for (args.?) |arg| {
            try iter.append(arg);
        }
    }
    const response = try conn.sendWithReplyAndBlock(request, -1, err);
    return Result{
        .response = response,
        .iter = iter,
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
    listeners: std.ArrayList(Listener),
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
    fn sscall(self: *Self, name: []const u8, path: []const u8, iface: []const u8, method: []const u8, args: ?[]const Value) !Result {
        return scall(self.allocator, self.bus.conn, self.err, name, path, iface, method, args);
    }
    pub fn call(self: *Object, name: []const u8, args: ?[]const Value) !Result {
        return self.sscall(
            self.name,
            self.path,
            self.iface,
            name,
            args,
        );
    }
    pub fn callN(self: *Object, name: []const u8, args: ?[]const Value) !void {
        const request = libdbus.Message.newMethodCall(self.name, self.path, self.iface, name);
        defer request.deinit();
        const iter = try libdbus.MessageIter.init(self.allocator);
        defer iter.deinit();
        iter.fromAppend(request);
        if (args != null) {
            for (args.?) |arg| {
                try iter.append(arg);
            }
        }
        if (!self.bus.conn.send(request, null)) {
            return error.SendFailed;
        }
    }
    pub fn get(self: *Object, name: []const u8) !GetResult {
        const args = [_]Value{
            Value{ .string = self.iface },
            Value{ .string = name },
        };
        const resp = try self.sscall(self.name, self.path, "org.freedesktop.DBus.Properties", "Get", &args);
        return .{ .result = resp };
    }
    pub fn set(self: *Object, name: []const u8, value: Value) !void {
        const args = [_]Value{
            Value{ .string = self.iface },
            Value{ .string = name },
            Value{ .variant = &value },
        };
        const resp = try self.sscall(self.name, self.path, "org.freedesktop.DBus.Properties", "Set", &args);
        defer resp.deinit();
    }
    pub fn getAll(self: *Object) !GetAllResult {
        const args = [_]Value{
            Value{ .string = self.iface },
        };
        const resp = try self.sscall(self.name, self.path, "org.freedesktop.DBus.Properties", "GetAll", &args);
        const HashMap = libdbus.Dict.HashMap(.string, .variant);
        const map = try self.allocator.create(HashMap);
        map.* = HashMap.init(self.allocator);

        const first = try resp.first();
        try first.dict.dump(.string, .variant, map);

        return GetAllResult{
            .allocator = self.allocator,
            .map = map,
            .result = resp,
        };
    }
    pub fn connect(self: *Object, signal: []const u8, handler: fn (Event, ?*anyopaque) void, data: ?*anyopaque) !void {
        if (self.bus.watch == null) {
            try self.bus.conn.addMatch("type='signal'", self.err);
            self.bus.watch = try glib.FdWatch(Bus).add(try self.bus.conn.getUnixFd(), signalHandler, self.bus);
        }
        try self.listeners.append(.{ .signal = signal, .handler = handler, .data = data });
    }
    pub fn disconnect(self: *Object, signal: []const u8, handler: fn (Event, ?*anyopaque) void) !void {
        for (self.listeners.items, 0..) |listener, i| {
            if (std.mem.eql(u8, listener.signal, signal) and listener.handler == handler) {
                _ = self.listeners.swapRemove(i);
                if (self.listeners.items.len == 0 and self.bus.watch != null) {
                    try self.bus.conn.removeMatch("type='signal'", self.err);
                    self.bus.watch.?.deinit();
                    self.bus.watch = null;
                }
                return;
            }
        }
        return error.SignalOrHandlerNotFound;
    }
};
pub const Event = struct {
    sender: []const u8,
    iface: []const u8,
    path: []const u8,
    member: []const u8,
    serial: u32,
    destination: ?[]const u8,
    values: ?[]Value,
};
fn signalHandler(bus: *Bus) bool {
    if (!bus.conn.readWrite(-1)) return false;
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
        var event = Event{
            .sender = sender,
            .iface = iface,
            .path = path,
            .member = member,
            .serial = m.getSerial(),
            .destination = destination,
            .values = null,
        };
        var iter: ?*libdbus.MessageIter = null;
        defer if (iter) |i| i.deinit();
        for (proxy.listeners.items) |listener| {
            if (std.mem.eql(u8, listener.signal, member)) {
                if (iter == null) {
                    iter = libdbus.MessageIter.init(proxy.allocator) catch unreachable;
                    if (iter.?.fromResult(m)) {
                        event.values = iter.?.getAll() catch unreachable;
                    }
                }
                listener.handler(event, listener.data);
            }
        }
    }

    return true;
}

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
    const resp = try proxy.call("GetArrayString", &.{});
    defer resp.deinit();
    const val = try resp.first();
    try testing.expectEqual(Type.string, val.array.type);
    try testing.expectEqualStrings("foo", val.array.items[0].string);
    try testing.expectEqualStrings("bar", val.array.items[1].string);
    try testing.expectEqualStrings("baz", val.array.items[2].string);
}

test "get" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = proxy.get("Byte") catch unreachable;
    defer resp.deinit();
    const val = try resp.value();
    try testing.expectEqual(123, val.byte);
}

test "get-all" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    const resp = proxy.getAll() catch unreachable;
    defer resp.deinit();
    try testing.expectEqual(123, resp.map.get("Byte").?.byte);
    try testing.expectEqual(-32768, resp.map.get("Int16").?.int16);
}

test "set" {
    const allocator = testing.allocator;
    const bus = Bus.init(allocator, .Session) catch unreachable;
    defer bus.deinit();
    var proxy = try bus.object("com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    defer proxy.deinit();
    try proxy.set("Boolean", .{ .boolean = true });
    try proxy.set("Boolean", .{ .boolean = false });
}
fn test_on_signal1(event: Event, err_: ?*anyopaque) void {
    const err: *anyerror = @ptrCast(@alignCast(err_.?));
    const value = event.values.?;
    err.* = error.OK;
    testing.expectEqualStrings("TestSignal", value[0].string) catch |er| {
        err.* = er;
        return;
    };
    testing.expectEqual(78787, value[1].int32) catch |er| {
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
    try proxy.callN("GetError", null);
}
