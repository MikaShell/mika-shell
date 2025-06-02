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
    pub fn get(bus_type: BusType, err: Error) ?*Connection {
        return dbus_bus_get(bus_type, err.ptr);
    }
    pub fn sendWithReplyAndBlock(self: *Self, message: *Message, timeout_milliseconds: i32, err: Error) ?*Message {
        return dbus_connection_send_with_reply_and_block(self, message, @intCast(timeout_milliseconds), err.ptr);
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
    pub fn new(message_type: MessageType) *Message {
        return dbus_message_new(message_type);
    }
    pub fn newMethodCall(bus_name: []const u8, path: []const u8, iface: []const u8, method: []const u8) ?*Message {
        return dbus_message_new_method_call(bus_name.ptr, path.ptr, iface.ptr, method.ptr);
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
    pub fn unref(message: *Message) void {
        dbus_message_unref(message);
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
// pkgs/dbus.zig:117:19: error: union 'dbus.Value' depends on itself
// pub const Value = union(enum) {
pub const Value = union(enum) {
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
    array: *MessageIter,
    // variant: *Value,
    // @"struct": []*Value,2
    // dict_entry: []*Value,
};

pub const MessageIter = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    wrapper: c.DBusMessageIter = undefined,
    extern fn dbus_message_iter_init_closed(iter: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_init(message: ?*Message, iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_has_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_get_signature(iter: *c.DBusMessageIter) [*c]u8;
    extern fn dbus_message_iter_get_arg_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_element_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_recurse(iter: *c.DBusMessageIter, sub: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_get_basic(iter: *c.DBusMessageIter, value: ?*anyopaque) void;
    extern fn dbus_message_iter_get_element_count(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_array_len(iter: *c.DBusMessageIter) c_int;
    pub fn init(allocator: std.mem.Allocator) *Self {
        const self = allocator.create(Self) catch unreachable;
        self.* = Self{
            .allocator = allocator,
        };
        return self;
    }
    pub fn fromMessage(self: *Self, message: *Message) !void {
        if (dbus_message_iter_init(message, &self.wrapper) == 0) {
            return error.InvalidMessage;
        }
    }
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
    // pub fn hasNext(self: *Self) bool {
    //     return dbus_message_iter_has_next(&self.wrapper) != 0;
    // }
    // pub fn next(self: *Self) bool {
    //     return dbus_message_iter_next(&self.wrapper) != 0;
    // }
    pub fn next(self: *Self) ?Value {
        var value: Value = undefined;
        switch (self.getArgType()) {
            else => {
                return null;
            },
            .INVALID => {
                return null;
            },
            .BYTE => {
                var byte: u8 = undefined;
                self.getBasic(&byte);
                value = Value{ .byte = byte };
            },
            .BOOLEAN => {
                var boolean: bool = undefined;
                self.getBasic(&boolean);
                value = Value{ .boolean = boolean };
            },
            .INT16 => {
                var int16: i16 = undefined;
                self.getBasic(&int16);
                value = Value{ .int16 = int16 };
            },
            .UINT16 => {
                var uint16: u16 = undefined;
                self.getBasic(&uint16);
                value = Value{ .uint16 = uint16 };
            },
            .INT32 => {
                var int32: i32 = undefined;
                self.getBasic(&int32);
                value = Value{ .int32 = int32 };
            },
            .UINT32 => {
                var uint32: u32 = undefined;
                self.getBasic(&uint32);
                value = Value{ .uint32 = uint32 };
            },
            .INT64 => {
                var int64: i64 = undefined;
                self.getBasic(&int64);
                value = Value{ .int64 = int64 };
            },
            .UINT64 => {
                var uint64: u64 = undefined;
                self.getBasic(&uint64);
                value = Value{ .uint64 = uint64 };
            },
            .DOUBLE => {
                var double: f64 = undefined;
                self.getBasic(&double);
                value = Value{ .double = double };
            },
            .STRING => {
                var strPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&strPtr));
                const str = std.mem.sliceTo(strPtr, 0);
                value = Value{ .string = str };
            },
            .OBJECT_PATH => {
                var objPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&objPtr));
                const obj = std.mem.sliceTo(objPtr, 0);
                value = Value{ .object_path = obj };
            },
            .SIGNATURE => {
                var sigPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&sigPtr));
                const sig = std.mem.sliceTo(sigPtr, 0);
                value = Value{ .signature = sig };
            },
            .UNIX_FD => {
                var fd: i32 = undefined;
                self.getBasic(&fd);
                value = Value{ .unix_fd = fd };
            },
            .ARRAY => {
                const sub = MessageIter.init(self.allocator);
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                value = Value{ .array = sub };
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
    fn getSignature(self: *Self) ?[]const u8 {
        const sig = dbus_message_iter_get_signature(&self.wrapper);
        if (sig == null) return null;
        return std.mem.sliceTo(sig, 0);
    }
    fn getBasic(self: *Self, pointer: *anyopaque) void {
        dbus_message_iter_get_basic(&self.wrapper, pointer);
    }
    fn getElementCount(self: *Self) i32 {
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
test "dbus" {
    //    DBusConnection* conn;
    // DBusMessage* msg;
    // DBusMessage* reply;
    // DBusMessageIter args;
    // DBusMessageIter array_iter;
    // char* name;
    const err = Error.init();
    defer err.deinit();
    const conn = Connection.get(.Session, err);
    if (err.isSet()) {
        std.debug.print("Error: {s}\n", .{err.message().?});
        return;
    }
    const msg = Message.newMethodCall(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "ListNames",
    ) orelse return;
    defer msg.unref();

    const reply = conn.?.sendWithReplyAndBlock(msg, -1, err) orelse return;
    if (err.isSet()) {
        std.debug.print("Error: {s}\n", .{err.message().?});
        return;
    }
    defer reply.unref();
    const allocator = std.heap.page_allocator;
    var args = MessageIter.init(allocator);
    try args.fromMessage(reply);
    defer args.deinit();
    const list = args.next().?.array;
    defer list.deinit();
    while (list.next()) |value| {
        switch (value) {
            .string => |str| {
                print("{s}  \n", .{str});
            },
            else => {},
        }
    }
}
const print = std.debug.print;
