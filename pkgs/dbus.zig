const c = @cImport({
    @cInclude("dbus/dbus.h");
    @cInclude("dbus.h");
});
usingnamespace @cImport({
    @cInclude("dbus.h");
    @cInclude("dbus/dbus.h");
});
pub const Error = extern struct {
    ptr: *c.DBusError,
    extern fn dbus_error_is_set(@"error": *const c.DBusError) c.dbus_bool_t;
    extern fn dbus_error_new() *c.DBusError;
    extern fn dbus_error_destroy(err: *c.DBusError) void;
    extern fn dbus_error_get_name(err: *c.DBusError) [*c]const u8;
    extern fn dbus_error_get_message(err: *c.DBusError) [*c]const u8;
    pub fn init() Error {
        return .{ .ptr = dbus_error_new() };
    }
    pub fn deinit(err: Error) void {
        dbus_error_destroy(err.ptr);
    }
    pub fn name(err: Error) ?[]const u8 {
        const name_ = dbus_error_get_name(err.ptr);
        if (name_ == null) return null;
        return std.mem.sliceTo(name_, 0);
    }
    pub fn message(err: Error) ?[]const u8 {
        const msg = dbus_error_get_message(err.ptr);
        if (msg == null) return null;
        return std.mem.sliceTo(msg, 0);
    }
    pub fn isSet(err: Error) bool {
        return dbus_error_is_set(err.ptr) != 0;
    }
};
pub const BusType = enum(c_uint) {
    Session,
    System,
    Starter,
};
pub const Connection = extern struct {
    const Self = @This();
    extern fn dbus_bus_get(@"type": BusType, @"error": ?*c.DBusError) *Connection;
    extern fn dbus_connection_send_with_reply_and_block(connection: *Connection, message: *Message, timeout_milliseconds: c_int, @"error": ?*c.DBusError) ?*Message;
    // extern fn dbus_connection_send(connection:  * Connection, message:  * Message, client_serial: [*c]dbus_uint32_t) dbus_bool_t;
    // extern fn dbus_connection_send_with_reply(connection:  * Connection, message:  * Message, pending_return: [*c]?*DBusPendingCall, timeout_milliseconds: c_int) dbus_bool_t;
    pub fn get(bus_type: BusType, err: Error) !*Connection {
        const conn = dbus_bus_get(bus_type, err.ptr);
        if (err.isSet()) return error.HasError;
        return conn;
    }
    pub fn sendWithReplyAndBlock(self: *Self, message: *Message, timeout_milliseconds: i32, err: Error) !*Message {
        const reply = dbus_connection_send_with_reply_and_block(self, message, @intCast(timeout_milliseconds), err.ptr);
        if (err.isSet()) return error.HasError;
        return reply.?;
    }
};

pub const MessageType = enum(c_int) {
    Invalid,
    MethodCall,
    MethodReturn,
    Error,
    Signal,
};
pub const Message = extern struct {
    extern fn dbus_message_new(message_type: c_int) *Message;
    extern fn dbus_message_new_method_call(bus_name: [*c]const u8, path: [*c]const u8, iface: [*c]const u8, method: [*c]const u8) ?*Message;
    extern fn dbus_message_new_method_return(method_call: *Message) *Message;
    extern fn dbus_message_new_signal(path: [*c]const u8, iface: [*c]const u8, name: [*c]const u8) *Message;
    extern fn dbus_message_new_error(reply_to: *Message, error_name: [*c]const u8, error_message: [*c]const u8) *Message;
    extern fn dbus_message_copy(message: *const Message) *Message;
    extern fn dbus_message_ref(message: *Message) *Message;
    extern fn dbus_message_unref(message: *Message) void;
    extern fn dbus_message_iter_init(message: ?*Message, iter: *c.DBusMessageIter) c.dbus_bool_t;
    pub fn new(message_type: MessageType) *Message {
        return dbus_message_new(message_type);
    }
    pub fn newMethodCall(bus_name: []const u8, path: []const u8, iface: []const u8, method: []const u8) *Message {
        return dbus_message_new_method_call(bus_name.ptr, path.ptr, iface.ptr, method.ptr).?;
    }
    pub fn newMethodReturn(method_call: *Message) *Message {
        return dbus_message_new_method_return(method_call);
    }
    pub fn newSignal(path: []const u8, iface: []const u8, name: []const u8) *Message {
        return dbus_message_new_signal(path.ptr, iface.ptr, name.ptr);
    }
    pub fn newError(reply_to: *Message, error_name: []const u8, error_message: []const u8) *Message {
        return dbus_message_new_error(reply_to, error_name.ptr, error_message.ptr);
    }
    pub fn copy(message: *const Message) *Message {
        return dbus_message_copy(message);
    }
    pub fn ref(message: *Message) *Message {
        return dbus_message_ref(message);
    }
    pub fn deinit(message: *Message) void {
        dbus_message_unref(message);
    }
    // getIter 返回的 MessaegIter 需要调用 MessageIter.deinit() 释放
    pub fn getIter(message: *Message, allocator: std.mem.Allocator) !?*MessageIter {
        const i = try MessageIter.init(allocator);
        if (dbus_message_iter_init(message, &i.wrapper) == 0) {
            i.deinit();
            return null;
        }
        return i;
    }
};

pub const ArgType = enum(c_int) {
    INVALID = c.DBUS_TYPE_INVALID,
    BYTE = c.DBUS_TYPE_BYTE,
    BOOLEAN = c.DBUS_TYPE_BOOLEAN,
    INT16 = c.DBUS_TYPE_INT16,
    UINT16 = c.DBUS_TYPE_UINT16,
    INT32 = c.DBUS_TYPE_INT32,
    UINT32 = c.DBUS_TYPE_UINT32,
    INT64 = c.DBUS_TYPE_INT64,
    UINT64 = c.DBUS_TYPE_UINT64,
    DOUBLE = c.DBUS_TYPE_DOUBLE,
    STRING = c.DBUS_TYPE_STRING,
    OBJECT_PATH = c.DBUS_TYPE_OBJECT_PATH,
    SIGNATURE = c.DBUS_TYPE_SIGNATURE,
    UNIX_FD = c.DBUS_TYPE_UNIX_FD,
    ARRAY = c.DBUS_TYPE_ARRAY,
    VARIANT = c.DBUS_TYPE_VARIANT,
    STRUCT = c.DBUS_TYPE_STRUCT,
    DICT_ENTRY = c.DBUS_TYPE_DICT_ENTRY,
};

pub const Dict = struct {
    const Self = @This();
    items: []Variant,
    pub const KeyType = enum {
        byte,
        boolean,
        int16,
        uint16,
        int32,
        uint32,
        int64,
        uint64,
        double,
        string,
        object_path,
        signature,
    };
    pub const ValueType = enum {
        byte,
        boolean,
        int16,
        uint16,
        int32,
        uint32,
        int64,
        uint64,
        double,
        string,
        object_path,
        signature,
        unix_fd,
        array,
        variant,
        @"struct",
        dict,
    };

    fn KeyTypeOf(comptime t: KeyType) type {
        return switch (t) {
            .byte => u8,
            .boolean => bool,
            .int16 => i16,
            .uint16 => u16,
            .int32 => i32,
            .uint32 => u32,
            .int64 => i64,
            .uint64 => u64,
            .double => f64,
            .string => []const u8,
            .object_path => []const u8,
            .signature => []const u8,
        };
    }
    fn ValueTypeOf(comptime t: ValueType) type {
        return switch (t) {
            .byte => u8,
            .boolean => bool,
            .int16 => i16,
            .uint16 => u16,
            .int32 => i32,
            .uint32 => u32,
            .int64 => i64,
            .uint64 => u64,
            .double => f64,
            .string => []const u8,
            .object_path => []const u8,
            .signature => []const u8,
            .unix_fd => i32,
            .array => []Variant,
            .variant => *Variant,
            .@"struct" => []Variant,
            .dict => Dict,
        };
    }
    pub fn HashMap(comptime Key: KeyType, comptime Value: ValueType) type {
        if (KeyTypeOf(Key) == []const u8) {
            return std.StringHashMap(ValueTypeOf(Value));
        }
        return std.AutoHashMap(KeyTypeOf(Key), ValueTypeOf(Value));
    }
    pub fn load(self: Self, comptime Key: KeyType, comptime Value: ValueType, hashmap: *HashMap(Key, Value)) !void {
        const items = self.items;
        var i: usize = 0;
        while (i < items.len) {
            const key = switch (Key) {
                .byte => items[i].byte,
                .boolean => items[i].boolean,
                .int16 => items[i].int16,
                .uint16 => items[i].uint16,
                .int32 => items[i].int32,
                .uint32 => items[i].uint32,
                .int64 => items[i].int64,
                .uint64 => items[i].uint64,
                .double => items[i].double,
                .string => items[i].string,
                .object_path => items[i].object_path,
                .signature => items[i].signature,
            };
            const value = switch (Value) {
                .byte => items[i + 1].byte,
                .boolean => items[i + 1].boolean,
                .int16 => items[i + 1].int16,
                .uint16 => items[i + 1].uint16,
                .int32 => items[i + 1].int32,
                .uint32 => items[i + 1].uint32,
                .int64 => items[i + 1].int64,
                .uint64 => items[i + 1].uint64,
                .double => items[i + 1].double,
                .string => items[i + 1].string,
                .object_path => items[i + 1].object_path,
                .signature => items[i + 1].signature,
                .unix_fd => items[i + 1].unix_fd,
                .array => items[i + 1].array,
                .variant => items[i + 1].variant,
                .@"struct" => items[i + 1].@"struct",
                .dict => items[i + 1].dict,
            };
            try hashmap.put(key, value);
            i += 2;
        }
    }
};
pub const Variant = union(enum) {
    byte: u8,
    boolean: bool,
    int16: i16,
    uint16: u16,
    int32: i32,
    uint32: u32,
    int64: i64,
    uint64: u64,
    double: f64,
    string: []const u8,
    object_path: []const u8,
    signature: []const u8,
    unix_fd: i32,
    array: []Variant,
    variant: *Variant,
    @"struct": []Variant,
    dict: Dict,
};
// 对于从 MessageIter 中获取的值，无需调用者手动 free, 在调用 MessageIter.deinit() 时自动释放所有资源
pub const MessageIter = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    wrapper: c.DBusMessageIter = undefined,
    extern fn dbus_message_iter_init_closed(iter: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_has_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_get_signature(iter: *c.DBusMessageIter) [*c]u8;
    extern fn dbus_message_iter_get_arg_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_element_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_recurse(iter: *c.DBusMessageIter, sub: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_get_basic(iter: *c.DBusMessageIter, value: ?*anyopaque) void;
    extern fn dbus_message_iter_get_element_count(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_array_len(iter: *c.DBusMessageIter) c_int;
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        const arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        self.* = Self{
            .allocator = allocator,
            .arena = arena.allocator(),
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self.arena.ptr));
        arena.deinit();
        self.allocator.destroy(arena);
        self.allocator.destroy(self);
    }
    pub fn next(self: *Self) !?Variant {
        var value: Variant = undefined;
        switch (self.getArgType()) {
            .INVALID => {
                return null;
            },
            .BYTE => {
                var byte: u8 = undefined;
                self.getBasic(&byte);
                value = Variant{ .byte = byte };
            },
            .BOOLEAN => {
                var boolean: bool = undefined;
                self.getBasic(&boolean);
                value = Variant{ .boolean = boolean };
            },
            .INT16 => {
                var int16: i16 = undefined;
                self.getBasic(&int16);
                value = Variant{ .int16 = int16 };
            },
            .UINT16 => {
                var uint16: u16 = undefined;
                self.getBasic(&uint16);
                value = Variant{ .uint16 = uint16 };
            },
            .INT32 => {
                var int32: i32 = undefined;
                self.getBasic(&int32);
                value = Variant{ .int32 = int32 };
            },
            .UINT32 => {
                var uint32: u32 = undefined;
                self.getBasic(&uint32);
                value = Variant{ .uint32 = uint32 };
            },
            .INT64 => {
                var int64: i64 = undefined;
                self.getBasic(&int64);
                value = Variant{ .int64 = int64 };
            },
            .UINT64 => {
                var uint64: u64 = undefined;
                self.getBasic(&uint64);
                value = Variant{ .uint64 = uint64 };
            },
            .DOUBLE => {
                var double: f64 = undefined;
                self.getBasic(&double);
                value = Variant{ .double = double };
            },
            .STRING => {
                var strPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&strPtr));
                const str = std.mem.sliceTo(strPtr, 0);
                value = Variant{ .string = str };
            },
            .OBJECT_PATH => {
                var objPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&objPtr));
                const obj = std.mem.sliceTo(objPtr, 0);
                value = Variant{ .object_path = obj };
            },
            .SIGNATURE => {
                var sigPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&sigPtr));
                const sig = std.mem.sliceTo(sigPtr, 0);
                value = Variant{ .signature = sig };
            },
            .UNIX_FD => {
                var fd: i32 = undefined;
                self.getBasic(&fd);
                value = Variant{ .unix_fd = fd };
            },
            .ARRAY => {
                const isDict = blk: {
                    const sig = self.getSignature();
                    break :blk std.mem.startsWith(u8, sig, "a{") and std.mem.endsWith(u8, sig, "}");
                };
                if (isDict) {
                    var sub = try MessageIter.init(self.allocator);
                    defer sub.deinit();
                    dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                    const array = try self.arena.alloc(Variant, self.getElementCount() * 2);
                    var i: usize = 0;
                    while (try sub.next()) |entry| {
                        array[i] = entry.@"struct"[0];
                        array[i + 1] = entry.@"struct"[1];
                        i += 2;
                    }
                    value = Variant{ .dict = Dict{ .items = array } };
                } else {
                    var sub = try MessageIter.init(self.allocator);
                    defer sub.deinit();
                    dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                    const array = try self.arena.alloc(Variant, self.getElementCount());
                    for (array) |*item| {
                        item.* = (try sub.next()).?;
                    }
                    value = Variant{ .array = array };
                }
            },
            .STRUCT => {
                var sub = try MessageIter.init(self.allocator);
                defer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                var stuList = std.ArrayList(Variant).init(self.arena);
                defer stuList.deinit();
                while (try sub.next()) |v| {
                    try stuList.append(v);
                }
                value = Variant{ .@"struct" = try stuList.toOwnedSlice() };
            },
            .VARIANT => {
                var sub = try MessageIter.init(self.arena);
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const result = try self.arena.create(Variant);
                result.* = (try sub.next()).?;
                value = Variant{ .variant = result };
            },
            .DICT_ENTRY => {
                var sub = try MessageIter.init(self.allocator);
                defer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const array = try self.arena.alloc(Variant, 2);
                array[0] = (try sub.next()).?;
                array[1] = (try sub.next()).?;
                value = Variant{ .@"struct" = array };
            },
        }
        _ = dbus_message_iter_next(&self.wrapper);
        return value;
    }
    fn getArgType(self: *Self) ArgType {
        return @enumFromInt(dbus_message_iter_get_arg_type(&self.wrapper));
    }
    fn getElementType(self: *Self) ArgType {
        return @enumFromInt(dbus_message_iter_get_element_type(&self.wrapper));
    }
    fn getSignature(self: *Self) []const u8 {
        const sig = dbus_message_iter_get_signature(&self.wrapper).?;
        return std.mem.sliceTo(sig, 0);
    }
    fn getBasic(self: *Self, pointer: *anyopaque) void {
        dbus_message_iter_get_basic(&self.wrapper, pointer);
    }
    fn getElementCount(self: *Self) usize {
        return @intCast(dbus_message_iter_get_element_count(&self.wrapper));
    }
    fn getArrayLen(self: *Self) i32 {
        return @intCast(dbus_message_iter_get_array_len(&self.wrapper));
    }
    fn recurse(self: *Self, sub: *MessageIter) void {
        dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
    }
};
const std = @import("std");
const print = std.debug.print;
const testing = std.testing;
fn test_method_call(name: []const u8) *Message {
    return Message.newMethodCall(
        "com.example.DBusService",
        "/com/example/DBusService",
        "com.example.DBusService",
        name,
    );
}
test "method-call-result" {
    const err = Error.init();
    defer err.deinit();
    const conn = Connection.get(.Session, err) catch {
        std.debug.print("Error: {s}\n", .{err.message().?});
        return;
    };
    const baseCases = [_]struct { name: []const u8, result: Variant }{
        .{
            .name = "GetByte",
            .result = Variant{ .byte = 123 },
        },
        .{
            .name = "GetBoolean",
            .result = Variant{ .boolean = true },
        },
        .{
            .name = "GetInt16",
            .result = Variant{ .int16 = -32768 },
        },
        .{
            .name = "GetUInt16",
            .result = Variant{ .uint16 = 65535 },
        },
        .{
            .name = "GetInt32",
            .result = Variant{ .int32 = -2147483648 },
        },
        .{
            .name = "GetUInt32",
            .result = Variant{ .uint32 = 4294967295 },
        },
        .{
            .name = "GetInt64",
            .result = Variant{ .int64 = -9223372036854775808 },
        },
        .{
            .name = "GetUInt64",
            .result = Variant{ .uint64 = 18446744073709551615 },
        },
        .{
            .name = "GetDouble",
            .result = Variant{ .double = 3.141592653589793 },
        },
    };
    const strCases = [_]struct { name: []const u8, result: []const u8 }{
        .{
            .name = "GetObjectPath",
            .result = "/com/example/DBusObject",
        },
        .{
            .name = "GetSignature",
            .result = "as",
        },
        .{
            .name = "GetString",
            .result = "Hello from DBus Service!",
        },
    };

    var msg: *Message = undefined;
    var reply: *Message = undefined;
    for (baseCases) |case| {
        msg = test_method_call(case.name);
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        defer msg.deinit();
        defer reply.deinit();
        const args = (try reply.getIter(testing.allocator)).?;
        defer args.deinit();
        const result = try args.next();
        try testing.expectEqual(case.result, result);
    }

    for (strCases) |case| {
        msg = test_method_call(case.name);
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        defer msg.deinit();
        defer reply.deinit();
        const args = (try reply.getIter(testing.allocator)).?;
        defer args.deinit();
        const result = (try args.next()).?;
        var str: []const u8 = undefined;
        switch (result) {
            .object_path => |p| str = p,
            .signature => |s| str = s,
            .string => |s| str = s,
            else => unreachable,
        }
        try testing.expectEqualStrings(case.result, str);
    }

    var args: *MessageIter = undefined;
    var result: Variant = undefined;
    // GetArrayString
    {
        msg = test_method_call("GetArrayString");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        args = (try reply.getIter(testing.allocator)).?;
        defer msg.deinit();
        defer reply.deinit();
        defer args.deinit();
        result = (try args.next()).?;
        try testing.expectEqualStrings("foo", result.array[0].string);
        try testing.expectEqualStrings("bar", result.array[1].string);
        try testing.expectEqualStrings("baz", result.array[2].string);
    }
    // GetStruct
    {
        msg = test_method_call("GetStruct");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        args = (try reply.getIter(testing.allocator)).?;
        defer msg.deinit();
        defer reply.deinit();
        defer args.deinit();
        result = (try args.next()).?;
        try testing.expectEqual(result.@"struct"[0].int64, -1234567890);
        try testing.expectEqual(result.@"struct"[1].boolean, true);
    }
    // GetVariant
    {
        msg = test_method_call("GetVariant");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        args = (try reply.getIter(testing.allocator)).?;
        defer msg.deinit();
        defer reply.deinit();
        defer args.deinit();
        result = (try args.next()).?.variant.*;
        try testing.expectEqual(result, Variant{ .int32 = 123 });
    }
    // GetNothing
    {
        msg = test_method_call("GetNothing");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        defer msg.deinit();
        defer reply.deinit();
        try testing.expectEqual(null, try reply.getIter(testing.allocator));
    }
    // GetDict1
    {
        msg = test_method_call("GetDict1");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        args = (try reply.getIter(testing.allocator)).?;
        defer msg.deinit();
        defer reply.deinit();
        defer args.deinit();
        result = (try args.next()).?;
        var map = Dict.HashMap(.string, .int32).init(testing.allocator);
        defer map.deinit();
        try result.dict.load(.string, .int32, &map);
        try testing.expectEqual(1, map.get("key1"));
        try testing.expectEqual(2, map.get("key2"));
        try testing.expectEqual(3, map.get("key3"));
    }
    // GetDict2
    {
        msg = test_method_call("GetDict2");
        reply = conn.sendWithReplyAndBlock(msg, -1, err) catch unreachable;
        args = (try reply.getIter(testing.allocator)).?;
        defer msg.deinit();
        defer reply.deinit();
        defer args.deinit();
        result = (try args.next()).?;
        var map = Dict.HashMap(.int32, .int32).init(testing.allocator);
        defer map.deinit();
        try result.dict.load(.int32, .int32, &map);
        try testing.expectEqual(1, map.get(1));
        try testing.expectEqual(2, map.get(2));
        try testing.expectEqual(3, map.get(3));
    }
}
