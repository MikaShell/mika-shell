const libdbus = @import("libdbus.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;
const Message = libdbus.Message;
const MessageIter = libdbus.MessageIter;
const common = @import("common.zig");
const Bus = @import("bus.zig").Bus;
pub const Service = struct {
    const Self = @This();
    const Method_ = struct {
        name: []const u8,
        func: MethodFunc(anyopaque),
    };
    const Property_ = struct {
        name: []const u8,
        signature: []const u8,
        access: PropertyAccess,
    };
    pub const Interface_ = struct {
        path: []const u8,
        name: []const u8,
        instance: *anyopaque,
        introspectXML: []const u8,
        getter: ?Getter(anyopaque),
        setter: ?Setter(anyopaque),
        method: []const Method_ = &.{},
        property: []const Property_ = &.{},
    };
    bus: *Bus,
    uniqueName: []const u8,
    err: *Error,
    allocator: Allocator,
    interfaces: std.ArrayList(Interface_),
    machineId: []const u8,
    /// do not use directly, use `dbus.Bus.publish` instead
    pub fn init(bus: *Bus) Allocator.Error!*Self {
        const allocator = bus.allocator;
        const s = try allocator.create(Self);
        errdefer allocator.destroy(s);
        s.* = Self{
            .allocator = allocator,
            .bus = bus,
            .interfaces = std.ArrayList(Interface_){},
            .machineId = undefined,
            .uniqueName = undefined,
            .err = undefined,
        };

        const err = try allocator.create(Error);
        errdefer allocator.destroy(err);
        err.init();
        errdefer err.deinit();
        s.uniqueName = bus.conn.getUniqueName();
        s.err = err;
        s.machineId = libdbus.getLocalMachineId();
        return s;
    }
    pub fn deinit(self: *Self) void {
        self.err.deinit();
        self.allocator.destroy(self.err);
        for (self.interfaces.items) |interface| {
            unpublish(self, interface.path, interface.name);
        }
        self.interfaces.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    fn getNodes(self: *Self, allocator: Allocator) [][]const u8 {
        var map = std.StringHashMap(void).init(allocator);
        defer map.deinit();
        for (self.interfaces.items) |item| {
            map.put(item.path, {}) catch unreachable;
        }
        var nodes = std.ArrayList([]const u8){};
        defer nodes.deinit(allocator);
        var it = map.iterator();
        while (it.next()) |entry| {
            nodes.append(allocator, entry.key_ptr.*) catch unreachable;
        }
        return nodes.toOwnedSlice(allocator) catch unreachable;
    }
};

pub fn publish(
    self: *Service,
    comptime T: type,
    comptime path: []const u8,
    comptime interface: Interface(T),
    instance: *T,
    emitter: ?*Emitter,
) !void {
    for (self.interfaces.items) |item| {
        if (std.mem.eql(u8, item.path, path) and std.mem.eql(u8, item.name, interface.name)) {
            return error.InterfaceAlreadyPublished;
        }
    }
    inline for (interface.property) |prop| {
        if ((prop.access == .readwrite or prop.access == .read) and interface.getter == null) {
            @compileError("property has 'read' access but no getter function provided");
        }
        if ((prop.access == .readwrite or prop.access == .write) and interface.setter == null) {
            @compileError("property has 'write' access but no setter function provided");
        }
    }
    const methods = try self.allocator.alloc(Service.Method_, interface.method.len);
    inline for (interface.method, 0..) |method, i| {
        methods[i] = .{
            .name = method.name,
            .func = @ptrCast(method.func),
        };
    }
    const properties = try self.allocator.alloc(Service.Property_, interface.property.len);
    inline for (interface.property, 0..) |prop, i| {
        properties[i] = .{
            .name = prop.name,
            .access = prop.access,
            .signature = Type.signature(prop.type),
        };
    }
    if (emitter) |e| e.* = .{
        .conn = self.bus.conn,
        .path = path,
        .iface = interface.name,
        .instance = @ptrCast(instance),
        .getter = @ptrCast(interface.getter),
        .property = properties,
    };
    const interface_ = Service.Interface_{
        .name = interface.name,
        .path = path,
        .instance = instance,
        .introspectXML = makeIntrospect(T, interface),
        .getter = @ptrCast(interface.getter),
        .setter = @ptrCast(interface.setter),
        .method = methods,
        .property = properties,
    };
    try self.interfaces.append(self.allocator, interface_);
    if (!(try self.bus.addFilter(.{ .type = .method_call }, serviceHandler, self))) {
        return error.CouldNotAddFilter;
    }
    try self.bus.addMatch(.{
        .type = .method_call,
        .interface = interface.name,
        .path = path,
    });
    const added = Message.newSignal("/", "org.freedesktop.DBus.ObjectManager", "InterfacesAdded");
    defer {
        _ = self.bus.conn.send(added, null);
        self.bus.conn.flush();
    }
    const iter = MessageIter.init(self.allocator);
    defer iter.deinit();
    iter.fromAppend(added);
    try iter.append(Type.ObjectPath, path);
    var iface_dict = try iter.openDict(Type.String, Type.Dict(Type.String, Type.AnyVariant));
    defer iface_dict.close();
    try iface_dict.appendKey(interface.name);
    var callError: RequstError = .{};
    try appendAllProperties(iface_dict.currentEntry.?, interface_, self.allocator, &callError);
    if (callError.name != null and callError.message != null) {
        std.log.scoped(.dbus).err("Failed to get properties: {s}: {s}", .{ callError.name.?, callError.message.? });
        return error.FailedToPublish;
    }
    iface_dict.closeCurrentEntry();
}
pub fn unpublish(self: *Service, path: []const u8, interface: []const u8) void {
    for (self.interfaces.items, 0..) |item, i| {
        if (!(std.mem.eql(u8, item.path, path) and std.mem.eql(u8, item.name, interface))) continue;
        self.allocator.free(item.method);
        self.allocator.free(item.property);
        _ = self.interfaces.swapRemove(i);
        const removed = Message.newSignal("/", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved");
        defer {
            _ = self.bus.conn.send(removed, null);
            self.bus.conn.flush();
        }
        const iter = MessageIter.init(self.allocator);
        defer iter.deinit();
        iter.fromAppend(removed);
        iter.append(Type.ObjectPath, path) catch unreachable;
        iter.append(Type.Array(Type.String), &.{interface}) catch unreachable;
        return;
    }
    @panic("interface not found");
}
fn appendAllProperties(iter: *MessageIter, interface: Service.Interface_, allocator: Allocator, err: *RequstError) !void {
    var dict = try iter.openDict(Type.String, Type.AnyVariant);
    defer dict.close();
    for (interface.property) |prop| {
        if (prop.access == .read or prop.access == .readwrite) {
            try dict.appendKey(prop.name);
            defer dict.closeCurrentEntry();
            appendWithGetter(
                dict.currentEntry.?,
                interface.getter.?,
                interface.instance,
                prop.name,
                prop.signature,
                allocator,
                err,
            ) catch |e| {
                const err_msg = std.fmt.allocPrintSentinel(allocator, "Failed to get property {s}: {t}", .{ prop.name, e }, 0) catch unreachable;
                err.set("org.freedesktop.DBus.Error.Failed", err_msg);
                return;
            };
        }
    }
}
fn appendWithGetter(iter: *MessageIter, getter: Getter(anyopaque), instance: *anyopaque, name: []const u8, signature: []const u8, allocator: Allocator, err: *RequstError) !void {
    const variant = try iter.openContainerS(.variant, signature);
    try getter(instance, name, allocator, variant, err);
    try iter.closeContainer(variant);
    variant.deinit();
}

pub const Context = struct {
    const Self = @This();
    pub const Async = struct {
        ctx: *Context,
        pub fn finish(self: Async) !void {
            defer self.ctx.deinit();
            try self.ctx.reply();
        }
    };
    conn: *libdbus.Connection,
    msg: *Message,
    sender: []const u8,
    _gpa: Allocator, // dont use _gpa, use arena
    arena: Allocator,

    _reply: *Message,
    _in: ?*MessageIter = null,
    _out: ?*MessageIter = null,
    _async: bool = false,

    _errName: ?[]const u8 = null,
    _errMessage: ?[]const u8 = null,

    fn init(conn: *libdbus.Connection, msg: *Message, gpa: Allocator) *Self {
        const self = gpa.create(Self) catch unreachable;
        const arena = gpa.create(std.heap.ArenaAllocator) catch unreachable;
        arena.* = .init(gpa);

        self.* = .{
            .conn = conn,
            .msg = msg,
            .sender = msg.getSender(),
            ._gpa = gpa,
            .arena = arena.allocator(),
            ._reply = msg.newMethodReturn(),
        };

        return self;
    }
    fn deinit(self: *Self) void {
        if (self._in) |in| in.deinit();
        if (self._out) |out| out.deinit();
        if (self._errName) |name| self._gpa.free(name);
        if (self._errMessage) |message| self._gpa.free(message);
        self._reply.unref();

        const arena: *std.heap.ArenaAllocator = @ptrCast(@alignCast(self.arena.ptr));
        arena.deinit();

        self._gpa.destroy(arena);
        self._gpa.destroy(self);
    }
    pub fn errors(self: *Self, name: [:0]const u8, message: [:0]const u8) void {
        self._errName = self._gpa.dupe(u8, name) catch unreachable;
        self._errMessage = self._gpa.dupe(u8, message) catch unreachable;
    }
    pub fn getInput(self: *Self) ?*MessageIter {
        if (self._in == null) {
            const iter = MessageIter.init(self._gpa);
            if (iter.fromResult(self.msg)) {
                self._in = iter;
            } else {
                return null;
            }
        }
        return self._in;
    }
    pub fn getOutput(self: *Self) *MessageIter {
        if (self._out == null) {
            const iter = MessageIter.init(self._gpa);
            iter.fromAppend(self._reply);
            self._out = iter;
        }
        return self._out.?;
    }
    pub fn async(self: *Self) Async {
        self._async = true;
        return .{ .ctx = self };
    }
    fn hasError(self: *Self) bool {
        return self._errName != null and self._errMessage != null;
    }
    fn reply(self: *Self) !void {
        if (self.hasError()) {
            const e = libdbus.Message.newError(self.msg, self._errName.?, self._errMessage.?);
            defer e.unref();
            _ = self.conn.send(e, null);
            self.conn.flush();
            return;
        }
        _ = self.conn.send(self._reply, null);
        self.conn.flush();
    }
};
fn serviceHandler(data: ?*anyopaque, msg: *Message) libdbus.HandlerResult {
    const service: *Service = @ptrCast(@alignCast(data));
    const iface_ = msg.getInterface();
    const path_ = msg.getPath();
    const member_ = msg.getMember();
    if (iface_ == null) return .notYetHandled;
    if (path_ == null) return .notYetHandled;
    if (member_ == null) return .notYetHandled;
    const iface = iface_.?;
    const path = path_.?;
    const member = member_.?;
    const destination = msg.getDestination();
    if (destination == null) return .notYetHandled;
    const eql = std.mem.eql;
    blk: {
        if ((eql(u8, destination.?, service.uniqueName))) break :blk;
        for (service.bus.ownerNames.items) |name| {
            if (eql(u8, name, destination.?)) break :blk;
        }
        return .notYetHandled;
    }

    const gpa = service.allocator;

    const conn = service.bus.conn;

    const ctx = Context.init(conn, msg, gpa);

    handler: {
        // org.freedesktop.DBus.Introspectable/Introspect
        if (eql(u8, iface, "org.freedesktop.DBus.Introspectable") and eql(u8, member, "Introspect")) {
            const iter = ctx.getOutput();
            const alloc = std.heap.page_allocator;
            var xml = std.Io.Writer.Allocating.init(alloc);
            defer xml.deinit();
            var writer = &xml.writer;
            writer.writeAll(
                \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd"><node>
            ) catch unreachable;
            if (eql(u8, path, "/")) {
                writer.writeAll(
                    \\<interface name="org.freedesktop.DBus.ObjectManager">
                    \\    <method name="GetManagedObjects">
                    \\        <arg name="objpath_interfaces_and_properties" type="a{oa{sa{sv}}}" direction="out"/>
                    \\    </method>
                    \\    <signal name="InterfacesAdded">
                    \\        <arg name="objpath" type="o"/>
                    \\        <arg name="interfaces_and_properties" type="a{sa{sv}}"/>
                    \\    </signal>
                    \\    <signal name="InterfacesRemoved">
                    \\        <arg name="objpath" type="o"/>
                    \\        <arg name="interfaces" type="as"/>
                    \\    </signal>
                    \\</interface>
                ) catch unreachable;
                for (service.interfaces.items) |interface| {
                    const node = std.fmt.allocPrint(alloc, "<node name=\"{s}\"/>\n", .{interface.path}) catch unreachable;
                    defer alloc.free(node);
                    writer.writeAll(node) catch unreachable;
                }
            } else {
                for (service.interfaces.items) |interface| {
                    if (!eql(u8, interface.path, path)) continue;
                    writer.writeAll(interface.introspectXML) catch unreachable;
                }
            }
            writer.writeAll("</node>") catch unreachable;
            iter.append(Type.String, xml.written()) catch unreachable;
            break :handler;
        }
        // org.freedesktop.DBus.Peer/Ping
        if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "Ping")) {
            for (service.interfaces.items) |interface| {
                if (eql(u8, interface.path, path)) {
                    break;
                }
            }
            ctx.errors("org.freedesktop.DBus.Error.NotSupported", "Ping is not supported");
            break :handler;
        }
        // org.freedesktop.DBus.Peer/GetMachineId
        if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "GetMachineId")) {
            const iter = ctx.getOutput();
            iter.append(Type.String, service.machineId) catch unreachable;
            break :handler;
        }
        // org.freedesktop.DBus.Properties/Get|Set|GetAll
        if (eql(u8, iface, "org.freedesktop.DBus.Properties")) {
            const iter = ctx.getInput() orelse {
                ctx.errors("org.freedesktop.DBus.Error.InvalidArgs", "Invalid arguments");
                break :handler;
            };
            var resultError: RequstError = .{};
            const iface__ = iter.next(Type.String).?;
            var arena = std.heap.ArenaAllocator.init(service.allocator);
            defer arena.deinit();
            if (eql(u8, member, "GetAll")) {
                for (service.interfaces.items) |interface| {
                    if (!eql(u8, interface.path, path)) continue;
                    if (!eql(u8, interface.name, iface__)) continue;
                    const output = ctx.getOutput();
                    appendAllProperties(
                        output,
                        interface,
                        arena.allocator(),
                        &resultError,
                    ) catch unreachable;
                    if (resultError.name != null and resultError.message != null) {
                        ctx.errors(resultError.name.?, resultError.message.?);
                    }
                    break :handler;
                }
                ctx.errors("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
                break :handler;
            }
            const name = iter.next(Type.String).?;
            var op: enum { get, set } = undefined;
            if (eql(u8, member, "Get")) {
                op = .get;
            } else if (eql(u8, member, "Set")) {
                op = .set;
            } else {
                ctx.errors("org.freedesktop.DBus.Error.InvalidArgs", "Invalid arguments");
                break :handler;
            }

            for (service.interfaces.items) |interface| {
                if (!eql(u8, interface.path, path)) continue;
                if (!eql(u8, interface.name, iface__)) continue;
                const property_: ?Service.Property_ = blk: {
                    for (interface.property) |property| {
                        if (std.mem.eql(u8, property.name, name)) {
                            if (property.access == .readwrite) break;
                            if ((eql(u8, member, "Get") and property.access != .read) or (eql(u8, member, "Set") and property.access != .write)) {
                                ctx.errors("org.freedesktop.DBus.Error.AccessDenied", "Property is not readable");
                                break :handler;
                            }
                            break :blk property;
                        }
                    }
                    ctx.errors("org.freedesktop.DBus.Error.UnknownProperty", "Unknown property");
                    break :handler;
                };
                const property = property_.?;
                switch (op) {
                    .get => {
                        const getter = interface.getter.?;
                        const out = ctx.getOutput();
                        appendWithGetter(
                            out,
                            getter,
                            interface.instance,
                            name,
                            property.signature,
                            arena.allocator(),
                            &resultError,
                        ) catch |err| {
                            const err_msg = std.fmt.allocPrintSentinel(arena.allocator(), "Failed to get property {s}: {t}", .{ name, err }, 0) catch unreachable;
                            ctx.errors("org.freedesktop.DBus.Error.Failed", err_msg);
                            break :handler;
                        };
                        if (resultError.name != null and resultError.message != null) {
                            ctx.errors(resultError.name.?, resultError.message.?);
                        }
                        break :handler;
                    },
                    .set => {
                        var value = iter.next(Type.AnyVariant).?;
                        if (!eql(u8, property.signature, value.iter.getSignature())) {
                            ctx.errors("org.freedesktop.DBus.Error.InvalidArgs", "Invalid arguments");
                            break :handler;
                        }
                        const setter = interface.setter.?;
                        setter(interface.instance, name, value, &resultError) catch |err| {
                            const err_msg = std.fmt.allocPrintSentinel(arena.allocator(), "Failed to set property {s}: {t}", .{ name, err }, 0) catch unreachable;
                            ctx.errors("org.freedesktop.DBus.Error.Failed", err_msg);
                            break :handler;
                        };
                        if (resultError.name != null and resultError.message != null) {
                            ctx.errors(resultError.name.?, resultError.message.?);
                        }
                        break :handler;
                    },
                }
            }
            ctx.errors("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
            break :handler;
        }
        // org.freedesktop.DBus.ObjectManager/GetManagedObjects
        if (eql(u8, iface, "org.freedesktop.DBus.ObjectManager") and eql(u8, member, "GetManagedObjects") and eql(u8, "/", path)) {
            const iter = ctx.getOutput();
            var resultError: RequstError = .{};
            var node_dict = iter.openDict(Type.ObjectPath, Type.Dict(Type.String, Type.Dict(Type.String, Type.AnyVariant))) catch unreachable;
            defer node_dict.close();
            var arena = std.heap.ArenaAllocator.init(service.allocator);
            defer arena.deinit();
            const allocator = arena.allocator();
            const nodes = service.getNodes(allocator);
            defer allocator.free(nodes);
            for (nodes) |node| {
                node_dict.appendKey(node) catch unreachable;
                defer node_dict.closeCurrentEntry();
                var iface_dict = node_dict.openDict(Type.String, Type.Dict(Type.String, Type.AnyVariant)) catch unreachable;
                defer iface_dict.close();
                for (service.interfaces.items) |interface| {
                    if (!eql(u8, interface.path, node)) continue;
                    iface_dict.appendKey(interface.name) catch unreachable;
                    defer iface_dict.closeCurrentEntry();
                    appendAllProperties(
                        iface_dict.currentEntry.?,
                        interface,
                        arena.allocator(),
                        &resultError,
                    ) catch unreachable;

                    if (resultError.name != null and resultError.message != null) {
                        ctx.errors(resultError.name.?, resultError.message.?);
                        break :handler;
                    }
                }
            }
            break :handler;
        }
        for (service.interfaces.items) |interface| {
            if (!eql(u8, interface.path, path)) continue;
            for (interface.method) |method| {
                if (!eql(u8, method.name, member)) continue;

                method.func(interface.instance, ctx) catch |e| {
                    ctx.errors("org.freedesktop.DBus.Error.Failed", @errorName(e));
                    break :handler;
                };
                break :handler;
            }
            ctx.errors("org.freedesktop.DBus.Error.UnknownMethod", "Unknown method");
            break :handler;
        }
        ctx.errors("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
        break :handler;
    }

    if (!ctx._async) {
        ctx.reply() catch |err| {
            std.log.scoped(.dbus).err("Failed to send reply: {t}. interface: {s}, path: {s}, member: {s}, destination: {s}", .{ err, iface, path, member, destination orelse "?" });
        };
        ctx.deinit();
    }
    return .handled;
}
pub const MethodArgs = struct {
    direction: enum { in, out },
    name: ?[]const u8 = null,
    type: type,
    annotations: []const Annotation = &.{},
};
pub fn MethodFunc(T: type) type {
    return *const fn (self: *T, ctx: *Context) anyerror!void;
}
pub fn Method(T: type) type {
    return struct {
        name: []const u8,
        args: []const MethodArgs = &.{},
        annotations: []const Annotation = &.{},
        func: MethodFunc(T),
    };
}
pub const SignalArgs = struct {
    name: ?[]const u8 = null,
    type: type,
    annotations: []const Annotation = &.{},
};
pub const Signal = struct {
    name: []const u8,
    args: []const SignalArgs = &.{},
    annotations: []const Annotation = &.{},
};
pub const Emitter = struct {
    conn: *libdbus.Connection,
    path: []const u8,
    iface: []const u8,
    instance: *anyopaque,
    property: []const Service.Property_ = &.{},
    getter: ?Getter(anyopaque) = null,

    pub fn emit(self: Emitter, name: []const u8, comptime Args: anytype, args: ?Type.getTupleTypes(Args)) void {
        const msg = libdbus.Message.newSignal(self.path, self.iface, name);
        defer msg.unref();
        if (args != null) {
            const iter = libdbus.MessageIter.init(std.heap.page_allocator);
            defer iter.deinit();
            iter.fromAppend(msg);
            inline for (args.?, 0..) |arg, i| {
                iter.append(Args[i], arg) catch |err| {
                    std.log.err("Failed to emit signal: {s} error: {any}", .{ name, err });
                    return;
                };
            }
        }
        _ = self.conn.send(msg, null);
        self.conn.flush();
    }
    pub fn emitPropertiesChanged(self: Emitter, changed: []const []const u8, invalidated: []const []const u8) void {
        if (self.getter == null) @panic("No getter function provided for PropertiesChanged signal. Please provide a getter function for the interface");
        var err: ?anyerror = null;
        defer if (err) |e| std.log.err("Failed to emit PropertiesChanged signal, error: {any}", .{e});
        const msg = libdbus.Message.newSignal(self.path, "org.freedesktop.DBus.Properties", "PropertiesChanged");
        defer msg.unref();
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const iter = libdbus.MessageIter.init(allocator);
        defer iter.deinit();
        iter.fromAppend(msg);
        iter.append(Type.String, self.iface) catch |e| {
            err = e;
            return;
        };
        const Dict = Type.Dict(Type.String, Type.AnyVariant);
        const array = iter.openContainer(Dict) catch |e| {
            err = e;
            return;
        };
        defer array.deinit();
        var callError: RequstError = .{};
        for (changed) |name| {
            const signature: []const u8 = blk: {
                for (self.property) |prop| {
                    if (std.mem.eql(u8, prop.name, name)) {
                        if (prop.access == .write) {
                            @panic(std.fmt.allocPrint(std.heap.page_allocator, "cannot emit PropertiesChanged signal, property \"{s}\" is write-only", .{name}) catch unreachable);
                        }
                        break :blk prop.signature;
                    }
                }
                @panic(std.fmt.allocPrint(std.heap.page_allocator, "cannot emit PropertiesChanged signal, property \"{s}\" not found", .{name}) catch unreachable);
            };
            const entry = array.openContainer(Dict) catch |e| {
                err = e;
                return;
            };
            defer array.closeContainer(entry) catch unreachable;
            defer entry.deinit();
            entry.append(Type.String, name) catch |e| {
                err = e;
                return;
            };
            const getter = self.getter.?;
            const variant = entry.openContainerS(.variant, signature) catch unreachable;
            defer variant.deinit();
            getter(self.instance, name, arena.allocator(), variant, &callError) catch |e| {
                err = e;
                return;
            };
            if (callError.name != null and callError.message != null) {
                @panic(std.fmt.allocPrint(std.heap.page_allocator, "cannot emit PropertiesChanged signal, error: {s}: {s}", .{ callError.name.?, callError.message.? }) catch unreachable);
            }
            entry.closeContainer(variant) catch |e| {
                err = e;
                return;
            };
        }
        iter.closeContainer(array) catch |e| {
            err = e;
            return;
        };
        iter.append(Type.Array(Type.String), invalidated) catch |e| {
            err = e;
            return;
        };
        _ = self.conn.send(msg, null);
        self.conn.flush();
    }
};
pub const Annotation = struct {
    name: []const u8,
    value: []const u8,
};
pub const PropertyAccess = enum {
    read,
    write,
    readwrite,
};
pub const Property = struct {
    name: []const u8,
    type: type,
    annotations: []const Annotation = &.{},
    access: PropertyAccess,
};
pub fn Getter(T: type) type {
    return *const fn (instance: *T, name: []const u8, allocator: Allocator, out: *MessageIter, err: *RequstError) anyerror!void;
}
pub fn Setter(T: type) type {
    return *const fn (instance: *T, name: []const u8, value: Type.AnyVariant.Type, err: *RequstError) anyerror!void;
}
pub fn Interface(comptime T: type) type {
    return struct {
        name: []const u8,
        getter: ?Getter(T) = null,
        setter: ?Setter(T) = null,
        method: []const Method(T) = &.{},
        signal: []const Signal = &.{},
        property: []const Property = &.{},
        annotations: []const Annotation = &.{},
    };
}
inline fn makeIntrospect(comptime T: type, comptime introspect: Interface(T)) []const u8 {
    const baseInterface = @embedFile("base-interface.xml");
    comptime var result: []const u8 = baseInterface ++ "\n";
    comptime {
        result = result ++ std.fmt.comptimePrint("<interface name=\"{s}\">\n", .{introspect.name});
        for (introspect.method) |method| {
            result = result ++ std.fmt.comptimePrint("    <method name=\"{s}\">\n", .{method.name});
            for (method.args) |arg| {
                if (arg.name) |name| {
                    result = result ++ std.fmt.comptimePrint("        <arg name=\"{s}\" direction=\"{t}\" type=\"{s}\"/>\n", .{
                        name,
                        arg.direction,
                        Type.signature(arg.type),
                    });
                } else {
                    result = result ++ std.fmt.comptimePrint("        <arg direction=\"{t}\" type=\"{s}\"/>\n", .{
                        arg.direction,
                        Type.signature(arg.type),
                    });
                }
            }
            result = result ++ "    </method>\n";
        }
        for (introspect.signal) |signal| {
            result = result ++ std.fmt.comptimePrint("    <signal name=\"{s}\">\n", .{signal.name});
            for (signal.args) |arg| {
                if (arg.name) |name| {
                    result = result ++ std.fmt.comptimePrint("        <arg name=\"{s}\" type=\"{s}\"/>\n", .{
                        name,
                        Type.signature(arg.type),
                    });
                } else {
                    result = result ++ std.fmt.comptimePrint("        <arg type=\"{s}\"/>\n", .{
                        Type.signature(arg.type),
                    });
                }
            }
            result = result ++ "    </signal>\n";
        }
        for (introspect.property) |property| {
            result = result ++ std.fmt.comptimePrint("    <property name=\"{s}\" type=\"{s}\" access=\"{t}\"/>\n", .{
                property.name,
                Type.signature(property.type),
                property.access,
            });
        }
        for (introspect.annotations) |annotation| {
            result = result ++ std.fmt.comptimePrint("    <annotation name=\"{s}\" value=\"{s}\"/>\n", .{
                annotation.name,
                annotation.value,
            });
        }
        result = result ++ "</interface>";
    }
    return result;
}
const testing = std.testing;
const print = std.debug.print;

pub const RequstError = struct {
    name: ?[:0]const u8 = null,
    message: ?[:0]const u8 = null,
    pub fn set(self: *@This(), name: [:0]const u8, message: [:0]const u8) void {
        self.name = name;
        self.message = message;
    }
};
const withGLibLoop = @import("bus.zig").withGLibLoop;
// TODO: 编写自动测试用例
test "service" {
    const TestInterface = struct {
        emitter: Emitter = undefined,
        fn tests(self: *@This(), ctx: *Context) !void {
            const str = try std.fmt.allocPrint(ctx.arena, "test method called {s}", .{ctx.getInput().?.next(Type.String).?});
            self.emitter.emit("TestSignal", .{Type.String}, .{"hello"});
            print("test method called {s}\n", .{str});
            ctx.errors("org.freedesktop.DBus.Error.Failed", "test error");
        }
        fn get(_: *@This(), _: []const u8, _: Allocator, out: *MessageIter, _: *RequstError) !void {
            try out.append(Type.String, "test property value");
        }
        fn set(self: *@This(), _: []const u8, value: Type.AnyVariant.Type, _: *RequstError) !void {
            print("test property set to {any}\n", .{value.as(Type.Int32)});
            self.emitter.emitPropertiesChanged(&.{"TestProperty"}, &.{"TestProperty2"});
        }
    };
    var testInterface = TestInterface{};
    const allocator = testing.allocator;
    const bus = try Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try withGLibLoop(bus);
    defer watch.deinit();
    try bus.requestName("com.example.MikaShellZ", .DoNotQueue);
    const service = try Service.init(bus);
    defer service.deinit();
    try publish(service, TestInterface, "/TestService", Interface(TestInterface){
        .name = "com.example.MikaShellZ",
        .getter = TestInterface.get,
        .setter = TestInterface.set,
        .method = &.{
            Method(TestInterface){
                .name = "tests",
                .args = &.{
                    MethodArgs{
                        .name = "arg1",
                        .type = Type.String,
                        .direction = .in,
                    },
                },
                .func = &TestInterface.tests,
            },
        },
        .property = &.{
            Property{
                .name = "TestProperty",
                .type = Type.String,
                .access = .read,
            },
            Property{
                .name = "TestProperty2",
                .type = Type.Int32,
                .access = .write,
            },
        },
    }, &testInterface, &testInterface.emitter);
    @import("utils.zig").timeoutMainLoop(200);
}
