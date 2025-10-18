const libdbus = @import("libdbus.zig");
pub const Event = struct {
    sender: []const u8,
    iface: []const u8,
    path: []const u8,
    member: []const u8,
    serial: u32,
    destination: ?[]const u8,
    iter: *libdbus.MessageIter,
};
pub const Listener = struct {
    signal: []const u8,
    handler: *const fn (Event, ?*anyopaque) void,
    data: ?*anyopaque,
};
const object = @import("object.zig");
pub fn freedesktopDBus(bus: *@import("bus.zig").Bus) !*object.Object {
    return try bus.proxy("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
}
const Allocator = @import("std").mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;

pub const CallNError = error{SendFailed} || Allocator.Error || libdbus.MessageIter.IterError;
/// 发送但不接收回复, 也不会收到 error.DBusError
pub fn callN(
    allocator: Allocator,
    conn: *libdbus.Connection,
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    method: []const u8,
    comptime argsType: anytype,
    args: ?Type.getTupleTypes(argsType),
) CallNError!void {
    var name_c: ?[:0]const u8 = null;
    defer if (name_c) |n| allocator.free(n);
    var path_c: ?[:0]const u8 = null;
    defer if (path_c) |p| allocator.free(p);
    var iface_c: ?[:0]const u8 = null;
    defer if (iface_c) |i| allocator.free(i);
    var method_c: ?[:0]const u8 = null;
    defer if (method_c) |m| allocator.free(m);
    if (!isCStr(name)) name_c = try allocator.dupeZ(u8, name);
    if (!isCStr(path)) path_c = try allocator.dupeZ(u8, path);
    if (!isCStr(iface)) iface_c = try allocator.dupeZ(u8, iface);
    if (!isCStr(method)) method_c = try allocator.dupeZ(u8, method);

    const request = libdbus.Message.newMethodCall(
        name_c orelse name,
        path_c orelse path,
        iface_c orelse iface,
        method_c orelse method,
    );
    defer request.unref();
    const iter = libdbus.MessageIter.init(allocator);
    defer iter.deinit();
    iter.fromAppend(request);
    if (args != null) {
        inline for (args.?, 0..) |arg, i| {
            try iter.append(argsType[i], arg);
        }
    }
    if (!conn.send(request, null)) {
        return error.SendFailed;
    }
}
pub const Result = struct {
    response: *libdbus.Message,
    iter: *libdbus.MessageIter,
    hasResult: bool,
    pub fn deinit(self: @This()) void {
        self.response.unref();
        self.iter.deinit();
    }
    pub fn as(self: @This(), comptime T: anytype) Type.getTupleTypes(T) {
        if (!self.hasResult) @panic("no result");
        return self.iter.getAll(T);
    }
    pub fn next(self: @This(), comptime T: type) T.Type {
        if (!self.hasResult) @panic("no result");
        return self.iter.next(T).?;
    }
};

const std = @import("std");
pub const CallError = libdbus.Errors || libdbus.MessageIter.IterError;
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
///
/// example:
/// ```
/// const result = try call(
///     allocator,
///     conn,
///     err,
///     "org.freedesktop.DBus",
///     "/",
///     "org.freedesktop.DBus",
///     "ListNames",
///    .{},
///     null,
///    .{dbus.Array(dbus.String)},
/// );
/// defer result.deinit();
/// ```
/// 在 result 中可以获取返回值, resulr.value 会根据传入的 resulrType 进行类型转换.
/// 在上面的调用中,result.value的类型是 `[][]const u8`
pub fn call(
    allocator: Allocator,
    conn: *libdbus.Connection,
    err: *Error,
    name: []const u8,
    path: []const u8,
    iface: []const u8,
    method: []const u8,
    comptime argsType: anytype,
    args: Type.getTupleTypes(argsType),
) CallError!Result {
    const args_info = @typeInfo(@TypeOf(argsType));
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("expected a tuple, found " ++ @typeName(@TypeOf(argsType)));
    }
    var name_c: ?[:0]const u8 = null;
    defer if (name_c) |n| allocator.free(n);
    var path_c: ?[:0]const u8 = null;
    defer if (path_c) |p| allocator.free(p);
    var iface_c: ?[:0]const u8 = null;
    defer if (iface_c) |i| allocator.free(i);
    var method_c: ?[:0]const u8 = null;
    defer if (method_c) |m| allocator.free(m);
    if (!isCStr(name)) name_c = try allocator.dupeZ(u8, name);
    if (!isCStr(path)) path_c = try allocator.dupeZ(u8, path);
    if (!isCStr(iface)) iface_c = try allocator.dupeZ(u8, iface);
    if (!isCStr(method)) method_c = try allocator.dupeZ(u8, method);

    const request = libdbus.Message.newMethodCall(
        name_c orelse name,
        path_c orelse path,
        iface_c orelse iface,
        method_c orelse method,
    );
    defer request.unref();
    const iter = libdbus.MessageIter.init(allocator);
    errdefer iter.deinit();
    iter.fromAppend(request);
    inline for (args, 0..) |arg, i| {
        try iter.append(argsType[i], arg);
    }
    const response = try conn.sendWithReplyAndBlock(request, -1, err);
    return .{ .response = response, .iter = iter, .hasResult = iter.fromResult(response) };
}

pub fn isCStr(slice: []const u8) bool {
    if (slice.len == 0) return false;
    const ptr = slice.ptr;
    return @as([*]const u8, @ptrCast(ptr))[slice.len] == 0;
}
