const c = @cImport({
    @cInclude("dbus/dbus.h");
    @cInclude("dbus.h");
});
usingnamespace @cImport({
    @cInclude("dbus.h");
    @cInclude("dbus/dbus.h");
});
const std = @import("std");
const Allocator = std.mem.Allocator;
/// `Error` 是一个 `DBusError` 的容器，内部包含一个指向 `c.DBusError` 的指针。
/// 该结构体可以安全地被复制，但是只能被使用一次。
/// 每当错误被设置 (`Error.isSet() == true`), 你必须调用 `Error.reset()` 才能使 `Error` 再次可用。
/// 不再使用时必须调用 `Error.deinit()` 释放内存。
///
/// English:
/// `Error` is a container of `DBusError` pointer. It can be safely copied, but can only be used once.
/// When an error is set (`Error.isSet() == true`), you must call `Error.reset()` to make `Error` available again.
/// When no longer needed, you must call `Error.deinit()` to release memory.
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
    pub fn reset(err: *Error) void {
        err.deinit();
        err.ptr = dbus_error_new();
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
pub const HandlerResult = enum(c_int) {
    Handled = c.DBUS_HANDLER_RESULT_HANDLED,
    NotYetHandled = c.DBUS_HANDLER_RESULT_NOT_YET_HANDLED,
    NeedMemory = c.DBUS_HANDLER_RESULT_NEED_MEMORY,
};

pub const DispatchStatus = enum(c_int) {
    DataRemains = c.DBUS_DISPATCH_DATA_REMAINS,
    Complete = c.DBUS_DISPATCH_COMPLETE,
    NeedMemory = c.DBUS_DISPATCH_NEED_MEMORY,
};

extern fn dbus_get_local_machine_id() [*c]u8;
pub fn getLocalMachineId() []const u8 {
    const id = dbus_get_local_machine_id();
    if (id == null) return "";
    return std.mem.sliceTo(id, 0);
}

pub const MessageHandler = *const fn (*Connection, ?*Message, ?*anyopaque) HandlerResult;
pub const FreeFunction = *const fn (?*anyopaque) void;
pub const Connection = extern struct {
    const Self = @This();
    pub const Rule = struct {};
    extern fn dbus_bus_get(@"type": BusType, @"error": ?*c.DBusError) *Connection;
    extern fn dbus_connection_send_with_reply_and_block(connection: *Connection, message: *Message, timeout_milliseconds: c_int, @"error": ?*c.DBusError) ?*Message;
    extern fn dbus_bus_add_match(connection: *Connection, rule: [*c]const u8, @"error": ?*c.DBusError) void;
    extern fn dbus_bus_remove_match(connection: *Connection, rule: [*c]const u8, @"error": ?*c.DBusError) void;
    extern fn dbus_connection_flush(connection: *Connection) void;
    extern fn dbus_connection_close(connection: *Connection) void;
    extern fn dbus_connection_read_write(connection: *Connection, timeout_milliseconds: c_int) c.dbus_bool_t;
    extern fn dbus_connection_pop_message(connection: *Connection) ?*Message;
    extern fn dbus_connection_add_filter(connection: *Connection, function: c.DBusHandleMessageFunction, user_data: ?*anyopaque, free_data_function: c.DBusFreeFunction) c.dbus_bool_t;
    extern fn dbus_connection_remove_filter(connection: *Connection, function: c.DBusHandleMessageFunction, user_data: ?*anyopaque) void;
    extern fn dbus_connection_dispatch(connection: *Connection) c.DBusDispatchStatus;
    extern fn dbus_connection_get_unix_fd(connection: *Connection, fd: [*c]c_int) c.dbus_bool_t;
    extern fn dbus_bus_get_unique_name(connection: *Connection) [*c]const u8;
    extern fn dbus_connection_unref(connection: *Connection) void;
    extern fn dbus_connection_send(connection: *Connection, message: ?*Message, client_serial: ?*c_uint) c.dbus_bool_t;
    extern fn dbus_bus_request_name(connection: *Connection, name: [*c]const u8, flags: c_uint, @"error": ?*c.DBusError) c_int;
    extern fn dbus_bus_release_name(connection: *Connection, name: [*c]const u8, @"error": ?*c.DBusError) c_int;

    pub fn get(bus_type: BusType, err: Error) !*Connection {
        const conn = dbus_bus_get(bus_type, err.ptr);
        if (err.isSet()) return error.DBusError;
        return conn;
    }
    pub fn unref(self: *Self) void {
        dbus_connection_unref(self);
    }
    pub fn sendWithReplyAndBlock(self: *Self, message: *Message, timeout_milliseconds: i32, err: Error) !*Message {
        const reply = dbus_connection_send_with_reply_and_block(self, message, @intCast(timeout_milliseconds), err.ptr);
        if (err.isSet()) return error.DBusError;
        return reply.?;
    }
    pub fn send(self: *Self, message: *Message, client_serial: ?*c_uint) bool {
        return dbus_connection_send(self, message, client_serial) != 0;
    }
    pub fn addMatch(self: *Self, rule: []const u8, err: Error) !void {
        dbus_bus_add_match(self, rule.ptr, err.ptr);
        if (err.isSet()) return error.DBusError;
    }
    pub fn removeMatch(self: *Self, rule: []const u8, err: Error) !void {
        dbus_bus_remove_match(self, rule.ptr, err.ptr);
        if (err.isSet()) return error.DBusError;
    }
    pub fn flush(self: *Self) void {
        dbus_connection_flush(self);
    }
    pub fn close(self: *Self) void {
        dbus_connection_close(self);
    }
    pub fn readWrite(self: *Self, timeout_milliseconds: i32) bool {
        return dbus_connection_read_write(self, @intCast(timeout_milliseconds)) != 0;
    }
    pub fn popMessage(self: *Self) ?*Message {
        return dbus_connection_pop_message(self);
    }
    pub fn dispatch(self: *Self) DispatchStatus {
        return @enumFromInt(dbus_connection_dispatch(self));
    }
    pub fn getUnixFd(self: *Self) !i32 {
        var fd: i32 = undefined;
        if (dbus_connection_get_unix_fd(self, @ptrCast(&fd)) == 0) return error.FieldToGetUnixFd;
        return fd;
    }
    pub fn getUniqueName(self: *Self) []const u8 {
        return std.mem.sliceTo(dbus_bus_get_unique_name(self), 0);
    }
    pub const NameFlag = enum(c_int) {
        AllowReplacement = c.DBUS_NAME_FLAG_ALLOW_REPLACEMENT,
        ReplaceExisting = c.DBUS_NAME_FLAG_REPLACE_EXISTING,
        DoNotQueue = c.DBUS_NAME_FLAG_DO_NOT_QUEUE,
    };
    pub const RequestNameReply = enum(c_int) {
        PrimaryOwner = c.DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER,
        InQueue = c.DBUS_REQUEST_NAME_REPLY_IN_QUEUE,
        Exists = c.DBUS_REQUEST_NAME_REPLY_EXISTS,
        AlreadyOwner = c.DBUS_REQUEST_NAME_REPLY_ALREADY_OWNER,
    };
    pub const ReleaseNameReply = enum(c_int) {
        Released = c.DBUS_RELEASE_NAME_REPLY_RELEASED,
        NonExistent = c.DBUS_RELEASE_NAME_REPLY_NON_EXISTENT,
        NotOwner = c.DBUS_RELEASE_NAME_REPLY_NOT_OWNER,
    };
    pub fn requestName(self: *Self, name: []const u8, flags: NameFlag, err: Error) !RequestNameReply {
        const r = dbus_bus_request_name(self, name.ptr, @intCast(@intFromEnum(flags)), err.ptr);
        if (err.isSet()) return error.DBusError;
        return @enumFromInt(r);
    }
    pub fn releaseName(self: *Self, name: []const u8, err: Error) !ReleaseNameReply {
        const r = dbus_bus_release_name(self, name.ptr, err.ptr);
        if (err.isSet()) return error.DBusError;
        return @enumFromInt(r);
    }
};

pub const Message = extern struct {
    pub const MType = enum(c_int) {
        Invalid,
        MethodCall,
        MethodReturn,
        Error,
        Signal,
    };
    extern fn dbus_message_new(message_type: c_int) *Message;
    extern fn dbus_message_new_method_call(bus_name: [*c]const u8, path: [*c]const u8, iface: [*c]const u8, method: [*c]const u8) ?*Message;
    extern fn dbus_message_new_method_return(method_call: *Message) *Message;
    extern fn dbus_message_new_signal(path: [*c]const u8, iface: [*c]const u8, name: [*c]const u8) *Message;
    extern fn dbus_message_new_error(reply_to: *Message, error_name: [*c]const u8, error_message: [*c]const u8) *Message;
    extern fn dbus_message_copy(message: *const Message) *Message;
    extern fn dbus_message_ref(message: *Message) *Message;
    extern fn dbus_message_unref(message: *Message) void;
    extern fn dbus_message_get_type(message: *Message) c_int;
    extern fn dbus_message_get_path(message: *Message) [*c]const u8;
    extern fn dbus_message_get_interface(message: *Message) [*c]const u8;
    extern fn dbus_message_get_member(message: *Message) [*c]const u8;
    extern fn dbus_message_get_destination(message: *Message) [*c]const u8;
    extern fn dbus_message_get_sender(message: *Message) [*c]const u8;
    extern fn dbus_message_get_signature(message: *Message) [*c]const u8;
    extern fn dbus_message_get_no_reply(message: *Message) c.dbus_bool_t;
    extern fn dbus_message_get_serial(message: *Message) c_uint;
    extern fn dbus_message_get_reply_serial(message: *Message) c_uint;
    pub fn new(message_type: MType) *Message {
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
    pub fn getType(message: *Message) MType {
        return @enumFromInt(dbus_message_get_type(message));
    }
    pub fn getPath(message: *Message) []const u8 {
        const path = dbus_message_get_path(message);
        if (path == null) unreachable;
        return std.mem.sliceTo(path, 0);
    }
    pub fn getInterface(message: *Message) []const u8 {
        const iface = dbus_message_get_interface(message);
        if (iface == null) unreachable;
        return std.mem.sliceTo(iface, 0);
    }
    pub fn getMember(message: *Message) []const u8 {
        const member = dbus_message_get_member(message);
        if (member == null) unreachable;
        return std.mem.sliceTo(member, 0);
    }
    pub fn getDestination(message: *Message) ?[]const u8 {
        const dest = dbus_message_get_destination(message);
        if (dest == null) return null;
        return std.mem.sliceTo(dest, 0);
    }
    pub fn getSender(message: *Message) []const u8 {
        const sender = dbus_message_get_sender(message);
        if (sender == null) unreachable;
        return std.mem.sliceTo(sender, 0);
    }
    pub fn getSignature(message: *Message) []const u8 {
        const sig = dbus_message_get_signature(message);
        if (sig == null) unreachable;
        return std.mem.sliceTo(sig, 0);
    }
    pub fn getNoReply(message: *Message) bool {
        return dbus_message_get_no_reply(message) != 0;
    }
    pub fn getSerial(message: *Message) u32 {
        return @intCast(dbus_message_get_serial(message));
    }
    pub fn getReplySerial(message: *Message) u32 {
        return @intCast(dbus_message_get_reply_serial(message));
    }
};
extern fn dbus_message_type_from_string(type_str: [*c]const u8) c_int;
extern fn dbus_message_type_to_string(@"type": c_int) [*c]const u8;
const Type_ = enum(c_int) {
    invalid = c.DBUS_TYPE_INVALID,
    byte = c.DBUS_TYPE_BYTE,
    boolean = c.DBUS_TYPE_BOOLEAN,
    int16 = c.DBUS_TYPE_INT16,
    uint16 = c.DBUS_TYPE_UINT16,
    int32 = c.DBUS_TYPE_INT32,
    uint32 = c.DBUS_TYPE_UINT32,
    int64 = c.DBUS_TYPE_INT64,
    uint64 = c.DBUS_TYPE_UINT64,
    double = c.DBUS_TYPE_DOUBLE,
    string = c.DBUS_TYPE_STRING,
    object_path = c.DBUS_TYPE_OBJECT_PATH,
    signature = c.DBUS_TYPE_SIGNATURE,
    unix_fd = c.DBUS_TYPE_UNIX_FD,
    array = c.DBUS_TYPE_ARRAY,
    variant = c.DBUS_TYPE_VARIANT,
    @"struct" = c.DBUS_TYPE_STRUCT,
    dict = c.DBUS_TYPE_DICT_ENTRY,
    pub fn fromString(type_str: []const u8) Type_ {
        return @enumFromInt(dbus_message_type_from_string(type_str.ptr));
    }
    pub fn asString(t: Type_) []const u8 {
        return switch (t) {
            .invalid => "\x00",
            .byte => "y",
            .boolean => "b",
            .int16 => "n",
            .uint16 => "q",
            .int32 => "i",
            .uint32 => "u",
            .int64 => "x",
            .uint64 => "t",
            .double => "d",
            .string => "s",
            .object_path => "o",
            .signature => "g",
            .unix_fd => "h",
            .array => "a",
            .variant => "v",
            .@"struct" => "r",
            .dict => "e",
        };
    }
    pub fn asInt(t: Type_) c_int {
        return @intFromEnum(t);
    }
    pub fn FromType(t: type) Type_ {
        return switch (t) {
            u8 => .byte,
            bool => .boolean,
            i16 => .int16,
            u16 => .uint16,
            i32 => .int32,
            u32 => .uint32,
            i64 => .int64,
            u64 => .uint64,
            f64 => .double,
            []const u8, []u8 => .string,
            []const Value, []Value => .array,
            *const Value, *Value => .variant,
            else => @compileError("unsupported type: " ++ @typeName(t)),
        };
    }
};
pub const Type = Type_;
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
    array: struct {
        type: Type_,
        items: []const Value,
    },
    variant: *const Value,
    @"struct": []const Value,
    dict: Dict,
    pub fn Type(v: Value) type {
        return Value.TypeWithDBusType(v.DBusType());
    }
    pub fn DBusType(v: Value) Type_ {
        return switch (v) {
            .byte => .byte,
            .boolean => .boolean,
            .int16 => .int16,
            .uint16 => .uint16,
            .int32 => .int32,
            .uint32 => .uint32,
            .int64 => .int64,
            .uint64 => .uint64,
            .double => .double,
            .string => .string,
            .object_path => .object_path,
            .signature => .signature,
            .unix_fd => .unix_fd,
            .array => .array,
            .variant => .variant,
            .@"struct" => .@"struct",
            .dict => .dict,
        };
    }
    pub fn TypeWithDBusType(t: Type_) type {
        return switch (t) {
            .invalid => @compileError("unsupported type: " ++ @tagName(t)),
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
            .array => []const Value,
            .variant => *const Value,
            .@"struct" => []const Value,
            .dict => Dict,
        };
    }
};

pub const Dict = struct {
    const Self = @This();
    items: []Value,
    // TODO
    key_type: Type = undefined,
    value_type: Type = undefined,
    signature: []const u8,
    fn KeyTypeOf(comptime t: Type) type {
        return switch (t) {
            .byte,
            .boolean,
            .int16,
            .uint16,
            .int32,
            .uint32,
            .int64,
            .uint64,
            .double,
            .string,
            .object_path,
            .signature,
            => Value.TypeWithDBusType(t),
            else => @compileError("unsupported key type: " ++ @tagName(t)),
        };
    }
    fn ValueTypeOf(comptime t: Type) type {
        return switch (t) {
            .invalid => @compileError("unsupported key type: " ++ @tagName(t)),
            else => Value.TypeWithDBusType(t),
        };
    }
    pub fn HashMap(comptime key: Type, comptime value: Type) type {
        if (KeyTypeOf(key) == []const u8) {
            return std.StringHashMap(ValueTypeOf(value));
        }
        return std.AutoHashMap(KeyTypeOf(key), ValueTypeOf(value));
    }
    pub fn dump(self: Self, comptime key: Type, comptime value: Type, hashmap: *HashMap(key, value)) !void {
        const items = self.items;
        var i: usize = 0;
        while (i < items.len) {
            const k = switch (key) {
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
                else => unreachable,
            };
            const v = switch (value) {
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
                else => unreachable,
            };
            try hashmap.put(k, v);
            i += 2;
        }
    }
    pub fn init(allocator: Allocator, comptime valueType: Type, value: anytype) !Self {
        var list = std.ArrayList(Value).init(allocator);
        defer list.deinit();
        const typeInfo = @typeInfo(@TypeOf(value));
        if (typeInfo != .@"struct") {
            @compileError("expected struct argument, found " ++ @typeName(@TypeOf(value)));
        }
        if (typeInfo == .@"struct" and typeInfo.@"struct".is_tuple) {
            @compileError("expected struct argument, found tuple");
        }
        inline for (typeInfo.@"struct".fields) |field| {
            try list.append(.{ .string = field.name });
            if (@TypeOf(@field(value, field.name)) == Value) {
                try list.append(@field(value, field.name));
            } else {
                const val: Value = switch (valueType) {
                    .byte => .{ .byte = @field(value, field.name) },
                    .boolean => .{ .boolean = @field(value, field.name) },
                    .int16 => .{ .int16 = @field(value, field.name) },
                    .uint16 => .{ .uint16 = @field(value, field.name) },
                    .int32 => .{ .int32 = @field(value, field.name) },
                    .uint32 => .{ .uint32 = @field(value, field.name) },
                    .int64 => .{ .int64 = @field(value, field.name) },
                    .uint64 => .{ .uint64 = @field(value, field.name) },
                    .double => .{ .double = @field(value, field.name) },
                    .string => .{ .string = @field(value, field.name) },
                    .object_path => .{ .object_path = @field(value, field.name) },
                    .signature => .{ .signature = @field(value, field.name) },
                    .unix_fd => .{ .unix_fd = @field(value, field.name) },
                    .array => .{ .array = @field(value, field.name) },
                    .variant => .{ .variant = @field(value, field.name) },
                    .@"struct" => .{ .@"struct" = @field(value, field.name) },
                    .dict => .{ .dict = @field(value, field.name) },
                    else => @compileError("unsupported key type: " ++ @tagName(Value)),
                };
                try list.append(val);
            }
        }
        const sig = try std.fmt.allocPrint(allocator, "{{s{s}}}", .{valueType.asString()});
        return Self{
            .items = try list.toOwnedSlice(),
            .signature = sig,
        };
    }
    // 此函数仅在使用 Dict.init 初始化的实例上调用
    pub fn deinit(dict: Self, allocator: Allocator) void {
        allocator.free(dict.items);
        allocator.free(dict.signature);
    }
};

// 对于从 MessageIter 中获取的值，无需调用者手动 free, 在调用 MessageIter.deinit() 时自动释放所有资源
pub const MessageIter = struct {
    const Self = @This();
    allocator: Allocator,
    arena: Allocator,
    wrapper: c.DBusMessageIter = undefined,
    extern fn dbus_message_iter_init_closed(iter: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_init_append(message: *Message, iter: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_init(message: *Message, iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_has_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_next(iter: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_get_signature(iter: *c.DBusMessageIter) [*c]u8;
    extern fn dbus_message_iter_get_arg_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_element_type(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_recurse(iter: *c.DBusMessageIter, sub: *c.DBusMessageIter) void;
    extern fn dbus_message_iter_get_basic(iter: *c.DBusMessageIter, value: ?*anyopaque) void;
    extern fn dbus_message_iter_get_element_count(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_get_array_len(iter: *c.DBusMessageIter) c_int;
    extern fn dbus_message_iter_append_basic(iter: *c.DBusMessageIter, @"type": c_int, value: ?*const anyopaque) c.dbus_bool_t;
    extern fn dbus_message_iter_append_fixed_array(iter: *c.DBusMessageIter, element_type: c_int, value: ?*const anyopaque, n_elements: c_int) c.dbus_bool_t;
    extern fn dbus_message_iter_open_container(iter: *c.DBusMessageIter, @"type": c_int, contained_signature: [*c]const u8, sub: *c.DBusMessageIter) c.dbus_bool_t;
    extern fn dbus_message_iter_close_container(iter: *c.DBusMessageIter, sub: *c.DBusMessageIter) c.dbus_bool_t;

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        const arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        self.* = Self{
            .allocator = allocator,
            .arena = arena.allocator(),
        };
        dbus_message_iter_init_closed(&self.wrapper);
        return self;
    }
    pub fn reset(self: *Self) void {
        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self.arena.ptr));
        _ = arena.reset(.free_all);
        dbus_message_iter_init_closed(&self.wrapper);
    }
    pub fn fromResult(self: *Self, message: *Message) bool {
        self.reset();
        if (dbus_message_iter_init(message, &self.wrapper) == 0) {
            return false;
        }
        return true;
    }

    pub fn fromAppend(self: *Self, message: *Message) void {
        dbus_message_iter_init_append(message, &self.wrapper);
    }
    /// Only dict and array need signature
    pub fn append(self: *Self, value: Value) !void {
        var ok: c_uint = 1;
        switch (value) {
            .byte => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.byte.asInt(),
                &value.byte,
            ),
            .boolean => {
                const v: c_int = @intCast(@intFromBool(value.boolean));
                ok = dbus_message_iter_append_basic(
                    &self.wrapper,
                    Type.boolean.asInt(),
                    &v,
                );
            },
            .int16 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.int16.asInt(),
                &value.int16,
            ),
            .uint16 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.uint16.asInt(),
                &value.uint16,
            ),
            .int32 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.int32.asInt(),
                &value.int32,
            ),
            .uint32 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.uint32.asInt(),
                &value.uint32,
            ),
            .int64 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.int64.asInt(),
                &value.int64,
            ),
            .uint64 => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.uint64.asInt(),
                &value.uint64,
            ),
            .double => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.double.asInt(),
                &value.double,
            ),
            .string => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.string.asInt(),
                @ptrCast(&value.string.ptr),
            ),
            .object_path => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.object_path.asInt(),
                @ptrCast(&value.object_path.ptr),
            ),
            .signature => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.signature.asInt(),
                @ptrCast(&value.signature.ptr),
            ),
            .unix_fd => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                Type.unix_fd.asInt(),
                &value.unix_fd,
            ),
            .array => {
                const sub = try self.openContainer(.array, value.array.type);
                defer sub.deinit();
                for (value.array.items) |item| {
                    try sub.append(item);
                }
                try self.closeContainer(sub);
            },
            .variant => {
                const sub = try self.openContainer(.variant, value.variant.DBusType());
                defer sub.deinit();
                try sub.append(value.variant.*);
                try self.closeContainer(sub);
            },
            .@"struct" => {
                const sub = try self.openContainer(.@"struct", null);
                defer sub.deinit();
                for (value.@"struct") |item| {
                    try sub.append(item);
                }
                try self.closeContainer(sub);
            },
            .dict => {
                const sub = try self.openContainerS(.array, value.dict.signature);
                defer sub.deinit();
                var i: usize = 0;
                while (i < value.dict.items.len) {
                    const key = value.dict.items[i];
                    const val = value.dict.items[i + 1];
                    const item = try sub.openContainer(.dict, null);
                    defer item.deinit();
                    errdefer _ = sub.closeContainer(item) catch {};
                    try item.append(key);
                    try item.append(val);
                    try sub.closeContainer(item);
                    i += 2;
                }
                try self.closeContainer(sub);
            },
        }

        if (ok == 0) {
            return error.AppendFailed;
        }
    }
    fn openContainer(self: *Self, t: Type, elementType: ?Type) !*MessageIter {
        return self.openContainerS(t, if (elementType) |et| et.asString() else null);
    }
    fn openContainerS(self: *Self, t: Type, elementType: ?[]const u8) !*MessageIter {
        const sub = try MessageIter.init(self.allocator);
        const r = dbus_message_iter_open_container(
            &self.wrapper,
            t.asInt(),
            if (elementType) |et| et.ptr else null,
            &sub.wrapper,
        );
        if (r == 0) {
            return error.OpenContainerFailed;
        }
        return sub;
    }
    fn closeContainer(self: *Self, sub: *MessageIter) !void {
        if (dbus_message_iter_close_container(&self.wrapper, &sub.wrapper) == 0) {
            return error.CloseContainerFailed;
        }
    }
    pub fn deinit(self: *Self) void {
        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self.arena.ptr));
        arena.deinit();
        self.allocator.destroy(arena);
        self.allocator.destroy(self);
    }
    pub fn next(self: *Self) !?Value {
        var value: Value = undefined;
        switch (self.getArgType()) {
            .invalid => {
                return null;
            },
            .byte => {
                var byte: u8 = undefined;
                self.getBasic(&byte);
                value = Value{ .byte = byte };
            },
            .boolean => {
                var boolean: bool = undefined;
                self.getBasic(&boolean);
                value = Value{ .boolean = boolean };
            },
            .int16 => {
                var int16: i16 = undefined;
                self.getBasic(&int16);
                value = Value{ .int16 = int16 };
            },
            .uint16 => {
                var uint16: u16 = undefined;
                self.getBasic(&uint16);
                value = Value{ .uint16 = uint16 };
            },
            .int32 => {
                var int32: i32 = undefined;
                self.getBasic(&int32);
                value = Value{ .int32 = int32 };
            },
            .uint32 => {
                var uint32: u32 = undefined;
                self.getBasic(&uint32);
                value = Value{ .uint32 = uint32 };
            },
            .int64 => {
                var int64: i64 = undefined;
                self.getBasic(&int64);
                value = Value{ .int64 = int64 };
            },
            .uint64 => {
                var uint64: u64 = undefined;
                self.getBasic(&uint64);
                value = Value{ .uint64 = uint64 };
            },
            .double => {
                var double: f64 = undefined;
                self.getBasic(&double);
                value = Value{ .double = double };
            },
            .string => {
                var strPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&strPtr));
                const str = std.mem.sliceTo(strPtr, 0);
                value = Value{ .string = str };
            },
            .object_path => {
                var objPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&objPtr));
                const obj = std.mem.sliceTo(objPtr, 0);
                value = Value{ .object_path = obj };
            },
            .signature => {
                var sigPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&sigPtr));
                const sig = std.mem.sliceTo(sigPtr, 0);
                value = Value{ .signature = sig };
            },
            .unix_fd => {
                var fd: i32 = undefined;
                self.getBasic(&fd);
                value = Value{ .unix_fd = fd };
            },
            .array => {
                const isDict = blk: {
                    const sig = self.getSignature();
                    break :blk std.mem.startsWith(u8, sig, "a{") and std.mem.endsWith(u8, sig, "}");
                };
                if (isDict) {
                    var sub = try MessageIter.init(self.arena);
                    errdefer sub.deinit();
                    dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                    const array = try self.arena.alloc(Value, self.getElementCount() * 2);
                    var i: usize = 0;
                    while (try sub.next()) |entry| {
                        array[i] = entry.@"struct"[0];
                        array[i + 1] = entry.@"struct"[1];
                        i += 2;
                    }
                    value = Value{ .dict = Dict{ .items = array, .signature = self.getSignature()[2..] } };
                } else {
                    var sub = try MessageIter.init(self.arena);
                    errdefer sub.deinit();
                    dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                    const array = try self.arena.alloc(Value, self.getElementCount());
                    for (array) |*item| {
                        item.* = (try sub.next()).?;
                    }
                    value = Value{ .array = .{
                        .type = self.getElementType(),
                        .items = array,
                    } };
                }
            },
            .@"struct" => {
                var sub = try MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                var stuList = std.ArrayList(Value).init(self.arena);
                defer stuList.deinit();
                while (try sub.next()) |v| {
                    try stuList.append(v);
                }
                value = Value{ .@"struct" = try stuList.toOwnedSlice() };
            },
            .variant => {
                var sub = try MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const result = try self.arena.create(Value);
                result.* = (try sub.next()).?;
                value = Value{ .variant = result };
            },
            .dict => {
                var sub = try MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const array = try self.arena.alloc(Value, 2);
                array[0] = (try sub.next()).?;
                array[1] = (try sub.next()).?;
                value = Value{ .@"struct" = array };
            },
        }
        _ = dbus_message_iter_next(&self.wrapper);
        return value;
    }
    pub fn getAll(self: *Self) ![]Value {
        var result = std.ArrayList(Value).init(self.arena);
        defer result.deinit();
        while (try self.next()) |v| {
            try result.append(v);
        }
        return result.toOwnedSlice();
    }
    fn getArgType(self: *Self) Type {
        return @enumFromInt(dbus_message_iter_get_arg_type(&self.wrapper));
    }
    fn getElementType(self: *Self) Type {
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
const print = std.debug.print;
const testing = std.testing;
comptime {
    std.testing.refAllDecls(@This());
}
fn test_method_call(name: []const u8) *Message {
    return Message.newMethodCall(
        "com.example.MikaShell",
        "/com/example/MikaShell",
        "com.example.TestService",
        name,
    );
}
test "method-call-result" {
    var err = Error.init();
    defer err.deinit();
    const conn = Connection.get(.Session, err) catch {
        std.debug.print("Can not get session bus connection, did you run dbus service script? error: {s}\n", .{err.message().?});
        return;
    };
    const baseCases = [_]struct { name: []const u8, result: Value }{
        .{
            .name = "GetByte",
            .result = Value{ .byte = 123 },
        },
        .{
            .name = "GetBoolean",
            .result = Value{ .boolean = true },
        },
        .{
            .name = "GetInt16",
            .result = Value{ .int16 = -32768 },
        },
        .{
            .name = "GetUInt16",
            .result = Value{ .uint16 = 65535 },
        },
        .{
            .name = "GetInt32",
            .result = Value{ .int32 = -2147483648 },
        },
        .{
            .name = "GetUInt32",
            .result = Value{ .uint32 = 4294967295 },
        },
        .{
            .name = "GetInt64",
            .result = Value{ .int64 = -9223372036854775808 },
        },
        .{
            .name = "GetUInt64",
            .result = Value{ .uint64 = 18446744073709551615 },
        },
        .{
            .name = "GetDouble",
            .result = Value{ .double = 3.141592653589793 },
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

    var request: *Message = undefined;
    var response: *Message = undefined;
    const iter = try MessageIter.init(testing.allocator);
    defer iter.deinit();
    for (baseCases) |case| {
        request = test_method_call(case.name);
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = try iter.next();
        try testing.expectEqual(case.result, result);
    }

    for (strCases) |case| {
        request = test_method_call(case.name);
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?;
        var str: []const u8 = undefined;
        switch (result) {
            .object_path => |p| str = p,
            .signature => |s| str = s,
            .string => |s| str = s,
            else => unreachable,
        }
        try testing.expectEqualStrings(case.result, str);
    }
    var result: Value = undefined;
    // GetArrayString
    {
        request = test_method_call("GetArrayString");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.next()).?;
        try testing.expectEqual(Type.string, result.array.type);
        try testing.expectEqualStrings("foo", result.array.items[0].string);
        try testing.expectEqualStrings("bar", result.array.items[1].string);
        try testing.expectEqualStrings("baz", result.array.items[2].string);
    }
    // GetArrayVariant
    {
        request = test_method_call("GetArrayVariant");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.next()).?;
        try testing.expectEqual(Type.variant, result.array.type);
        try testing.expectEqualStrings("foo", result.array.items[0].variant.*.string);
        try testing.expectEqual(123, result.array.items[1].variant.*.int32);
        try testing.expectEqual(true, result.array.items[2].variant.*.boolean);
    }
    // GetStruct
    {
        request = test_method_call("GetStruct");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.next()).?;
        try testing.expectEqual(result.@"struct"[0].int64, -1234567890);
        try testing.expectEqual(result.@"struct"[1].boolean, true);
    }
    // GetVariant
    {
        request = test_method_call("GetVariant");
        _ = iter.fromResult(request);
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.next()).?.variant.*;
        try testing.expectEqual(result, Value{ .int32 = 123 });
    }
    // GetNothing
    {
        request = test_method_call("GetNothing");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(false, iter.fromResult(response));
    }
    // GetDict1
    {
        request = test_method_call("GetDict1");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.next()).?;
        var map = Dict.HashMap(.string, .int32).init(testing.allocator);
        defer map.deinit();
        try result.dict.dump(.string, .int32, &map);
        try testing.expectEqual(1, map.get("key1"));
        try testing.expectEqual(2, map.get("key2"));
        try testing.expectEqual(3, map.get("key3"));
    }
    // GetDict2
    {
        request = test_method_call("GetDict2");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.getAll())[0];
        var map = Dict.HashMap(.int32, .int32).init(testing.allocator);
        defer map.deinit();
        try result.dict.dump(.int32, .int32, &map);
        try testing.expectEqual(1, map.get(1));
        try testing.expectEqual(2, map.get(2));
        try testing.expectEqual(3, map.get(3));
    }
    // GetDict3
    {
        request = test_method_call("GetDict3");
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        try testing.expectEqual(true, iter.fromResult(response));
        defer request.deinit();
        defer response.deinit();
        result = (try iter.getAll())[0];
        var map = Dict.HashMap(.string, .variant).init(testing.allocator);
        defer map.deinit();
        try result.dict.dump(.string, .variant, &map);
        try testing.expectEqual(489, map.get("home").?.int32);
        try testing.expectEqualStrings("foo", map.get("name").?.string);
    }
    // GetError
    {
        request = test_method_call("GetError");
        defer request.deinit();
        _ = conn.sendWithReplyAndBlock(request, -1, err) catch {};
        defer err.reset();
        try testing.expectEqualStrings("ATestError", err.message().?);
        try testing.expectEqual(true, conn.send(request, null));
    }
}
test "method-call-with-args" {
    const err = Error.init();
    defer err.deinit();
    const conn = Connection.get(.Session, err) catch {
        std.debug.print("Can not get session bus connection, did you run dbus service script? error: {s}\n", .{err.message().?});
        return;
    };
    var request: *Message = undefined;
    var response: *Message = undefined;
    const iter = try MessageIter.init(testing.allocator);
    defer iter.deinit();
    // CallAdd
    {
        request = test_method_call("CallAdd");
        iter.fromAppend(request);
        try iter.append(.{ .int32 = 1 });
        try iter.append(.{ .int32 = 2 });
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?.int32;
        try testing.expectEqual(3, result);
    }
    // CallWithStringArray
    {
        request = test_method_call("CallWithStringArray");
        iter.fromAppend(request);
        try iter.append(.{ .array = .{
            .type = .string,
            .items = &.{
                .{ .string = "Hello" },
                .{ .string = "World" },
            },
        } });
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?.string;
        try testing.expectEqualStrings("Hello World", result);
    }
    // CallWithVariant
    {
        request = test_method_call("CallWithVariant");
        iter.fromAppend(request);
        try iter.append(.{ .variant = &.{ .int32 = 114514 } });
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?.boolean;
        try testing.expectEqual(true, result);
    }
    // CallWithStruct
    {
        request = test_method_call("CallWithStruct");
        iter.fromAppend(request);
        try iter.append(.{ .@"struct" = &.{
            .{ .string = "foo" },
            .{ .int32 = 123 },
            .{ .boolean = true },
        } });
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?.boolean;
        try testing.expectEqual(true, result);
    }
    // CallWithDict
    {
        request = test_method_call("CallWithDict");
        iter.fromAppend(request);
        const dict = try Dict.init(testing.allocator, .string, .{
            .name = Value{ .string = "foo" },
            .home = "bar",
        });
        defer dict.deinit(testing.allocator);
        try iter.append(.{ .dict = dict });
        response = conn.sendWithReplyAndBlock(request, -1, err) catch unreachable;
        defer request.deinit();
        defer response.deinit();
        try testing.expectEqual(true, iter.fromResult(response));
        const result = (try iter.next()).?.boolean;
        try testing.expectEqual(true, result);
    }
}
