const libdbus = @import("libdbus.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = libdbus.Value;
const Error = libdbus.Error;
const Type = libdbus.Type;
pub const Bus = struct {
    const Self = @This();
    conn: *libdbus.Connection,
    err: Error,
    pub fn init(bus_type: libdbus.BusType) !Bus {
        const err = Error.init();
        return Bus{ .conn = try libdbus.Connection.get(bus_type, err), .err = err };
    }
    pub fn deinit(self: Self) void {
        self.err.deinit();
    }
    pub fn object(self: Self, allocator: Allocator, name: []const u8, path: []const u8, iface: []const u8) Object {
        return Object{
            .name = name,
            .path = path,
            .iface = iface,
            .conn = self.conn,
            .allocator = allocator,
            .err = Error.init(),
        };
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
pub const Object = struct {
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    conn: *libdbus.Connection,
    allocator: Allocator,
    err: Error,
    fn scall(self: Object, name: []const u8, path: []const u8, iface: []const u8, method: []const u8, args: []const Value) !Result {
        const request = libdbus.Message.newMethodCall(name, path, iface, method);
        defer request.deinit();
        const iter = try libdbus.MessageIter.init(self.allocator);
        defer iter.deinit();
        iter.fromAppend(request);
        for (args) |arg| {
            try iter.append(arg);
        }

        const response = try self.conn.sendWithReplyAndBlock(request, -1, self.err);
        return Result{
            .response = response,
            .iter = try libdbus.MessageIter.init(self.allocator),
        };
    }
    pub fn call(self: Object, name: []const u8, args: []const Value) !Result {
        return self.scall(self.name, self.path, self.iface, name, args);
    }
    pub fn get(self: Object, name: []const u8) !GetResult {
        const args = [_]Value{
            Value{ .string = self.iface },
            Value{ .string = name },
        };
        const resp = try self.scall(self.name, self.path, "org.freedesktop.DBus.Properties", "Get", &args);
        return .{ .result = resp };
    }
    pub fn set(self: Object, name: []const u8, value: Value) !void {
        const args = [_]Value{
            Value{ .string = self.iface },
            Value{ .string = name },
            Value{ .variant = &value },
        };
        const resp = try self.scall(self.name, self.path, "org.freedesktop.DBus.Properties", "Set", &args);
        defer resp.deinit();
    }
    pub fn getAll(self: Object) !GetAllResult {
        const args = [_]Value{
            Value{ .string = self.iface },
        };
        const resp = try self.scall(self.name, self.path, "org.freedesktop.DBus.Properties", "GetAll", &args);
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
};
const testing = std.testing;
const print = std.debug.print;
test "libdbus" {
    _ = libdbus;
}
test "call" {
    const allocator = testing.allocator;
    const bus = Bus.init(.Session) catch unreachable;
    defer bus.deinit();
    const proxy = bus.object(allocator, "com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
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
    const bus = Bus.init(.Session) catch unreachable;
    defer bus.deinit();
    const proxy = bus.object(allocator, "com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    const resp = proxy.get("Byte") catch unreachable;
    defer resp.deinit();
    const val = try resp.value();
    try testing.expectEqual(123, val.byte);
}

test "get-all" {
    const allocator = testing.allocator;
    const bus = Bus.init(.Session) catch unreachable;
    defer bus.deinit();
    const proxy = bus.object(allocator, "com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    const resp = proxy.getAll() catch unreachable;
    defer resp.deinit();
    try testing.expectEqual(123, resp.map.get("Byte").?.byte);
    try testing.expectEqual(-32768, resp.map.get("Int16").?.int16);
}

test "set" {
    const allocator = testing.allocator;
    const bus = Bus.init(.Session) catch unreachable;
    defer bus.deinit();
    const proxy = bus.object(allocator, "com.example.MikaShell", "/com/example/MikaShell", "com.example.TestService");
    try proxy.set("Boolean", .{ .boolean = true });
    try proxy.set("Boolean", .{ .boolean = false });
}
