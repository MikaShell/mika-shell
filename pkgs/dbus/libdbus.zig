const c = @cImport({
    @cInclude("dbus/dbus.h");
    @cInclude("dbus.h");
});

const std = @import("std");
pub const Types = @import("types.zig");
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
    pub fn addFilter(self: *Self, handler_function: c.DBusHandleMessageFunction, user_data: ?*anyopaque, free_data_function: c.DBusFreeFunction) bool {
        return dbus_connection_add_filter(self, handler_function, user_data, free_data_function) != 0;
    }
    pub fn removeFilter(self: *Self, handler_function: c.DBusHandleMessageFunction, user_data: ?*anyopaque) void {
        dbus_connection_remove_filter(self, handler_function, user_data);
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
        invalid,
        method_call,
        method_return,
        @"error",
        signal,
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
    pub fn getPath(message: *Message) ?[]const u8 {
        const path = dbus_message_get_path(message);
        if (path == null) return null;
        return std.mem.sliceTo(path, 0);
    }
    pub fn getInterface(message: *Message) ?[]const u8 {
        const iface = dbus_message_get_interface(message);
        if (iface == null) return null;
        return std.mem.sliceTo(iface, 0);
    }
    pub fn getMember(message: *Message) ?[]const u8 {
        const member = dbus_message_get_member(message);
        if (member == null) return null;
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

pub fn ArrayIter(ElementType: type) type {
    return struct {
        const Self = @This();
        parent: *MessageIter,
        iter: *MessageIter,
        pub fn init(parent: *MessageIter) !Self {
            return Self{
                .parent = parent,
                .iter = try parent.openContainer(ElementType.tag),
            };
        }
        pub fn append(self: Self, value: ElementType.Type) !void {
            try self.iter.append(ElementType, value);
        }
        pub fn close(self: Self) void {
            self.parent.closeContainer(self.iter) catch unreachable;
            self.iter.deinit();
        }
    };
}

pub const StructIter = struct {
    const Self = @This();
    parent: *MessageIter,
    iter: *MessageIter,
    pub fn init(parent: *MessageIter) !Self {
        return Self{
            .parent = parent,
            .iter = try parent.openContainer(.@"struct", null),
        };
    }
    pub fn append(self: Self, comptime T: type, value: T.Type) !void {
        try self.iter.append(T, value);
    }
    pub fn close(self: Self) void {
        self.parent.closeContainer(self.iter) catch unreachable;
        self.iter.deinit();
    }
};
pub fn VariantIter(T: type) type {
    return struct {
        const Self = @This();
        parent: *MessageIter,
        iter: *MessageIter,
        pub fn init(parent: *MessageIter) !Self {
            return Self{
                .parent = parent,
                .iter = try parent.openContainer(.variant, Types.signature(T)),
            };
        }
        pub fn store(self: Self, value: T.Type) !void {
            try self.iter.append(T, value);
            self.parent.closeContainer(self.iter) catch unreachable;
            self.iter.deinit();
        }
    };
}
pub fn DictIter(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Dict = Types.Dict(K, V);
        parent: *MessageIter,
        iter: *MessageIter,
        currentEntry: ?*MessageIter = null,
        pub fn init(parent: *MessageIter) !Self {
            return Self{
                .parent = parent,
                .iter = try parent.openContainerS(.array, Types.signature(Dict)[1..]),
            };
        }
        pub fn append(self: *Self, key: K.Type, value: V.Type) !void {
            try self.appendKey(key);
            try self.appendValue(value);
        }
        pub fn appendKey(self: *Self, key: K.Type) !void {
            if (self.currentEntry != null) @panic("current entry has not appended a value");
            const entry = try self.iter.openContainer(.dict, null);
            errdefer entry.deinit();
            try entry.append(K, key);
            self.currentEntry = entry;
        }
        pub fn appendValue(self: *Self, value: V.Type) !void {
            self.needAppendKey();
            const entry = self.currentEntry.?;
            defer self.closeCurrentEntry();
            defer entry.deinit();
            try entry.append(V, value);
        }
        fn needAppendKey(self: *Self) void {
            if (self.currentEntry == null) @panic("current entry need to append a key");
        }
        pub fn closeCurrentEntry(self: *Self) void {
            self.needAppendKey();
            const entry = self.currentEntry.?;
            self.iter.closeContainer(entry) catch unreachable;
            entry.deinit();
            self.currentEntry = null;
        }
        pub fn openDict(self: *Self, Key: type, Value: type) !DictIter(Key, Value) {
            self.needAppendKey();
            const dict = try self.currentEntry.?.openDict(Key, Value);
            return dict;
        }
        pub fn openArray(self: *Self, Element: type) !ArrayIter(Element) {
            self.needAppendKey();
            return try self.currentEntry.?.openArray(Element);
        }
        pub fn openVariant(self: *Self, Value: type) !VariantIter(Value) {
            self.needAppendKey();
            return try self.currentEntry.?.openVariant(Value);
        }
        pub fn openStruct(self: *Self) !StructIter {
            self.needAppendKey();
            return try self.currentEntry.?.openStruct();
        }
        pub fn close(self: Self) void {
            self.parent.closeContainer(self.iter) catch unreachable;
            self.iter.deinit();
        }
    };
}

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

    pub fn init(allocator: Allocator) *Self {
        const self = allocator.create(Self) catch @panic("OOM");
        errdefer allocator.destroy(self);
        const arena = allocator.create(std.heap.ArenaAllocator) catch @panic("OOM");
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
    pub fn append(self: *Self, comptime T: type, value: T.Type) !void {
        var ok: c_uint = 1;
        switch (T.tag) {
            .byte,
            .int16,
            .uint16,
            .int32,
            .uint32,
            .int64,
            .uint64,
            .double,
            .unix_fd,
            => ok = dbus_message_iter_append_basic(
                &self.wrapper,
                @intFromEnum(T.tag),
                &value,
            ),
            .boolean => {
                const v: c_int = @intCast(@intFromBool(value));
                ok = dbus_message_iter_append_basic(
                    &self.wrapper,
                    @intFromEnum(T.tag),
                    &v,
                );
            },
            .string, .signature, .object_path => {
                ok = dbus_message_iter_append_basic(
                    &self.wrapper,
                    @intFromEnum(T.tag),
                    @ptrCast(&value.ptr),
                );
            },
            .array => {
                const sub = try self.openContainer(.array, @enumFromInt(@intFromEnum(T.ArrayElement.tag)));
                defer sub.deinit();
                for (value) |item| {
                    try sub.append(T.ArrayElement, item);
                }
                try self.closeContainer(sub);
            },
            .variant => {
                try value.store(value, self);
            },
            .@"struct" => {
                const sub = try self.openContainer(.@"struct", null);
                defer sub.deinit();
                inline for (value, 0..) |item, i| {
                    try sub.append(T.StructFields[i], item);
                }
                try self.closeContainer(sub);
            },
            .dict => {
                const sub = try self.openContainerS(.array, Types.signature(T)[1..]);
                defer sub.deinit();
                for (value) |v| {
                    const item = try sub.openContainer(.dict, null);
                    defer item.deinit();
                    errdefer _ = sub.closeContainer(item) catch {};
                    try item.append(T.DictKey, v.key);
                    try item.append(T.DictValue, v.value);
                    try sub.closeContainer(item);
                }
                try self.closeContainer(sub);
            },
            else => unreachable,
        }
        if (ok == 0) {
            return error.AppendFailed;
        }
    }
    pub fn openArray(self: *Self, ElementType: type) !ArrayIter(ElementType) {
        return try ArrayIter(ElementType).init(self);
    }
    pub fn openStruct(self: *Self) !StructIter {
        return try StructIter.init(self);
    }
    pub fn openDict(self: *Self, KeyType: type, ValueType: type) !DictIter(KeyType, ValueType) {
        return try DictIter(KeyType, ValueType).init(self);
    }
    pub fn openVariant(self: *Self, comptime T: type) !VariantIter(T) {
        return try VariantIter(T).init(self);
    }
    pub fn appendDictEntry(self: *Self, comptime Key: type, comptime Value: type, key: Key.Type, value: Value.Type) !void {
        const sub = try self.openContainer(.dict, null);
        defer sub.deinit();
        try sub.append(Key, key);
        try sub.append(Value, value);
        try self.closeContainer(sub);
    }
    pub fn openContainer(self: *Self, t: Types.Tags, elementType: ?Types.Tags) !*MessageIter {
        return self.openContainerS(t, if (elementType) |et| et.asString() else null);
    }
    pub fn openContainerS(self: *Self, t: Types.Tags, elementType: ?[]const u8) !*MessageIter {
        const sub = MessageIter.init(self.allocator);
        var sig: ?[:0]const u8 = null;
        defer if (sig) |s| self.allocator.free(s);
        if (elementType) |et| {
            sig = try self.allocator.dupeZ(u8, et);
        }
        const r = dbus_message_iter_open_container(
            &self.wrapper,
            t.asInt(),
            if (sig) |s| s.ptr else null,
            &sub.wrapper,
        );
        if (r == 0) {
            return error.OpenContainerFailed;
        }
        return sub;
    }
    pub fn closeContainer(self: *Self, sub: *MessageIter) !void {
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
    pub fn skip(self: *Self) void {
        _ = dbus_message_iter_next(&self.wrapper);
    }
    pub fn next(self: *Self, comptime T: type) ?T.Type {
        if (T.tag == .invalid) {
            @compileError("invalid type is not allowed");
        }
        if (self.getArgType() != T.tag) {
            if (self.getArgType() != .array and T.tag != .dict) {
                if (self.getArgType() != .dict and T.tag != .@"struct") {
                    std.log.err("miss match type: {any} {any}\n", .{ self.getArgType(), T.tag });
                    @panic("miss match type");
                }
            }
        }
        switch (T.tag) {
            .invalid => return null,
            .byte,
            .int16,
            .uint16,
            .int32,
            .uint32,
            .int64,
            .uint64,
            .double,
            .unix_fd,
            => {
                var v: T.Type = undefined;
                self.getBasic(&v);
                _ = dbus_message_iter_next(&self.wrapper);
                return v;
            },
            .boolean => {
                var v: c_int = undefined;
                self.getBasic(&v);
                _ = dbus_message_iter_next(&self.wrapper);
                return v == 1;
            },
            .string,
            .signature,
            .object_path,
            => {
                var strPtr: [*c]const u8 = undefined;
                self.getBasic(@ptrCast(&strPtr));
                _ = dbus_message_iter_next(&self.wrapper);
                return std.mem.sliceTo(strPtr, 0);
            },
            .variant => {
                var sub = MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                var result: T.Type = undefined;
                result.tag = @enumFromInt(@intFromEnum(sub.getArgType()));
                result.iter = sub;
                _ = dbus_message_iter_next(&self.wrapper);
                return result;
            },
            .array => {
                var sub = MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const array = self.arena.alloc(T.ArrayElement.Type, self.getElementCount()) catch @panic("OOM");
                for (array) |*item| {
                    item.* = sub.next(T.ArrayElement).?;
                }
                _ = dbus_message_iter_next(&self.wrapper);
                return array;
            },
            .dict => {
                var sub = MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                const info = @typeInfo(T.Type);
                const EntryType = info.pointer.child;
                const entrys = self.arena.alloc(EntryType, self.getElementCount()) catch @panic("OOM");
                for (entrys) |*entry| {
                    const e = sub.next(Types.Struct(.{ T.DictKey, T.DictValue })).?;
                    entry.* = EntryType{
                        .key = e[0],
                        .value = e[1],
                    };
                }
                _ = dbus_message_iter_next(&self.wrapper);
                return entrys;
            },
            .@"struct" => {
                var sub = MessageIter.init(self.arena);
                errdefer sub.deinit();
                dbus_message_iter_recurse(&self.wrapper, &sub.wrapper);
                var result: T.Type = undefined;
                inline for (T.StructFields, 0..) |Field, i| {
                    result[i] = sub.next(Field).?;
                }
                _ = dbus_message_iter_next(&self.wrapper);
                return result;
            },
        }
    }

    pub fn getAll(self: *Self, t: anytype) !Types.getTupleTypes(t) {
        const Result = Types.getTupleTypes(t);
        var result: Result = undefined;
        inline for (t, 0..) |T, i| {
            result[i] = self.next(T).?;
        }
        return result;
    }
    pub fn getArgType(self: *Self) Types.Tags {
        return @enumFromInt(dbus_message_iter_get_arg_type(&self.wrapper));
    }
    fn getElementType(self: *Self) Types.Tags {
        return @enumFromInt(dbus_message_iter_get_element_type(&self.wrapper));
    }
    pub fn getSignature(self: *Self) []const u8 {
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
    defer conn.unref();
    const iter = MessageIter.init(testing.allocator);
    defer iter.deinit();
    var helper = struct {
        conn: *Connection,
        iter: *MessageIter,
        err: Error,
        req: ?*Message = null,
        res: ?*Message = null,
        fn call(self: *@This(), name: []const u8, comptime T: type) T.Type {
            self.deinit();
            self.req = test_method_call(name);
            self.res = self.conn.sendWithReplyAndBlock(self.req.?, -1, self.err) catch unreachable;
            if (!self.iter.fromResult(self.res.?)) unreachable;
            return self.iter.next(T).?;
        }
        fn deinit(self: *@This()) void {
            if (self.req) |req| req.deinit();
            if (self.res) |res| res.deinit();
            self.res = null;
            self.req = null;
        }
    }{
        .conn = conn,
        .err = err,
        .iter = iter,
    };
    defer helper.deinit();

    try testing.expectEqual(
        123,
        helper.call("GetByte", Types.Byte),
    );
    try testing.expectEqual(
        true,
        helper.call("GetBoolean", Types.Boolean),
    );
    try testing.expectEqual(
        -32768,
        helper.call("GetInt16", Types.Int16),
    );
    try testing.expectEqual(
        65535,
        helper.call("GetUInt16", Types.UInt16),
    );
    try testing.expectEqual(
        -2147483648,
        helper.call("GetInt32", Types.Int32),
    );
    try testing.expectEqual(
        4294967295,
        helper.call("GetUInt32", Types.UInt32),
    );
    try testing.expectEqual(
        -9223372036854775808,
        helper.call("GetInt64", Types.Int64),
    );
    try testing.expectEqual(
        18446744073709551615,
        helper.call("GetUInt64", Types.UInt64),
    );
    try testing.expectEqual(
        3.141592653589793,
        helper.call("GetDouble", Types.Double),
    );
    try testing.expectEqualStrings(
        "Hello from DBus Service!",
        helper.call("GetString", Types.String),
    );
    try testing.expectEqualStrings(
        "/com/example/DBusObject",
        helper.call("GetObjectPath", Types.ObjectPath),
    );
    try testing.expectEqualStrings(
        "as",
        helper.call("GetSignature", Types.Signature),
    );
    // GetNothing
    {
        const req = test_method_call("GetNothing");
        const res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(false, iter.fromResult(res));
    }
    // GetArrayString
    {
        const r = helper.call("GetArrayString", Types.Array(Types.String));
        try testing.expectEqualStrings("foo", r[0]);
        try testing.expectEqualStrings("bar", r[1]);
        try testing.expectEqualStrings("baz", r[2]);
    }
    // GetStruct
    {
        const r = helper.call("GetStruct", Types.Struct(.{ Types.Int64, Types.Boolean }));
        try testing.expectEqual(r[0], -1234567890);
        try testing.expectEqual(r[1], true);
    }
    // GetVariant
    {
        const r = helper.call("GetVariant", Types.Variant);
        try testing.expectEqual(Types.Tags.int32, r.tag);
        try testing.expectEqual(123, try r.get(Types.Int32));
    }
    // GetArrayVariant
    {
        const r = helper.call("GetArrayVariant", Types.Array(Types.Variant));
        try testing.expectEqualStrings("foo", try r[0].get(Types.String));
        try testing.expectEqual(123, try r[1].get(Types.Int32));
        try testing.expectEqual(true, try r[2].get(Types.Boolean));
    }
    // GetDict1
    {
        const r = helper.call("GetDict1", Types.Dict(Types.String, Types.Int32));
        try testing.expectEqualStrings("key1", r[0].key);
        try testing.expectEqualStrings("key2", r[1].key);
        try testing.expectEqualStrings("key3", r[2].key);

        try testing.expectEqual(2, r[1].value);
        try testing.expectEqual(1, r[0].value);
        try testing.expectEqual(2, r[1].value);
        try testing.expectEqual(3, r[2].value);
    }

    // GetDict2
    {
        const r = helper.call("GetDict2", Types.Dict(Types.Int32, Types.Int32));
        try testing.expectEqual(1, r[0].key);
        try testing.expectEqual(2, r[1].key);
        try testing.expectEqual(3, r[2].key);
        try testing.expectEqual(1, r[0].value);
        try testing.expectEqual(2, r[1].value);
        try testing.expectEqual(3, r[2].value);
    }

    // GetDict2
    {
        const r = helper.call("GetDict2", Types.Dict(Types.Int32, Types.Int32));
        try testing.expectEqual(1, r[0].key);
        try testing.expectEqual(2, r[1].key);
        try testing.expectEqual(3, r[2].key);
        try testing.expectEqual(1, r[0].value);
        try testing.expectEqual(2, r[1].value);
        try testing.expectEqual(3, r[2].value);
    }
    // GetDict3
    {
        const r = helper.call("GetDict3", Types.Dict(Types.String, Types.Variant));
        try testing.expectEqualStrings("name", r[0].key);
        try testing.expectEqualStrings("home", r[1].key);
        try testing.expectEqual(Types.Tags.string, r[0].value.tag);
        try testing.expectEqual(Types.Tags.int32, r[1].value.tag);
        try testing.expectEqualStrings("foo", try r[0].value.get(Types.String));
        try testing.expectEqual(489, try r[1].value.get(Types.Int32));
    }
    // GetDict3
    {
        const req = test_method_call("GetDict3");
        const res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const r = (try iter.getAll(.{Types.Dict(Types.String, Types.Variant)}))[0];
        try testing.expectEqualStrings("name", r[0].key);
        try testing.expectEqualStrings("home", r[1].key);
        try testing.expectEqual(Types.Tags.string, r[0].value.tag);
        try testing.expectEqual(Types.Tags.int32, r[1].value.tag);
        try testing.expectEqualStrings("foo", try r[0].value.get(Types.String));
        try testing.expectEqual(489, try r[1].value.get(Types.Int32));
    }
    // GetError
    {
        const req = test_method_call("GetError");
        defer req.deinit();
        _ = conn.sendWithReplyAndBlock(req, -1, err) catch {};
        defer err.reset();
        try testing.expectEqualStrings("ATestError", err.message().?);
        try testing.expectEqual(true, conn.send(req, null));
    }
}

test "method-call-with-args" {
    const err = Error.init();
    defer err.deinit();
    const conn = Connection.get(.Session, err) catch {
        std.debug.print("Can not get session bus connection, did you run dbus service script? error: {s}\n", .{err.message().?});
        return;
    };
    var req: *Message = undefined;
    var res: *Message = undefined;
    const iter = MessageIter.init(testing.allocator);
    defer iter.deinit();
    // CallAdd
    {
        req = test_method_call("CallAdd");
        iter.fromAppend(req);
        try iter.append(Types.Int32, 1);
        try iter.append(Types.Int32, 2);
        res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const result = iter.next(Types.Int32).?;
        try testing.expectEqual(3, result);
    }
    // CallWithStringArray
    {
        req = test_method_call("CallWithStringArray");
        iter.fromAppend(req);
        try iter.append(Types.Array(Types.String), &.{
            "Hello",
            "World",
        });
        res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const result = iter.next(Types.String).?;
        try testing.expectEqualStrings("Hello World", result);
    }
    // CallWithVariant
    {
        req = test_method_call("CallWithVariant");
        iter.fromAppend(req);

        try iter.append(Types.Variant, Types.Variant.init(Types.Int32, 114514));
        res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const result = iter.next(Types.Boolean).?;
        try testing.expectEqual(true, result);
    }
    // CallWithStruct
    {
        req = test_method_call("CallWithStruct");
        iter.fromAppend(req);
        try iter.append(
            Types.Struct(.{ Types.String, Types.Int32, Types.Boolean }),
            .{ "foo", 123, true },
        );
        res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const result = iter.next(Types.Boolean).?;
        try testing.expectEqual(true, result);
    }
    // CallWithDict
    {
        req = test_method_call("CallWithDict");
        iter.fromAppend(req);
        try iter.append(Types.Dict(Types.String, Types.String), &.{
            .{ .key = "name", .value = "foo" },
            .{ .key = "home", .value = "bar" },
        });
        res = conn.sendWithReplyAndBlock(req, -1, err) catch unreachable;
        defer req.deinit();
        defer res.deinit();
        try testing.expectEqual(true, iter.fromResult(res));
        const result = iter.next(Types.Boolean).?;
        try testing.expectEqual(true, result);
    }
}
