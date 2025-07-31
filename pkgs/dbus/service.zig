const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
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
            .interfaces = std.ArrayList(Interface_).init(allocator),
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
        self.interfaces.deinit();
        self.allocator.destroy(self);
    }
    fn getNodes(self: *Self, allocator: Allocator) [][]const u8 {
        var map = std.StringHashMap(void).init(allocator);
        for (self.interfaces.items) |item| {
            map.put(item.path, {}) catch unreachable;
        }
        var nodes = std.ArrayList([]const u8).init(allocator);
        defer nodes.deinit();
        var it = map.iterator();
        while (it.next()) |entry| {
            nodes.append(entry.key_ptr.*) catch unreachable;
        }
        return nodes.toOwnedSlice() catch unreachable;
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
    try self.interfaces.append(interface_);
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
    var callError: RequstError = undefined;
    try appendAllProperties(iface_dict.currentEntry.?, interface_, self.allocator, &callError);
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
                const err_msg = std.fmt.allocPrint(allocator, "Failed to get property {s}: {s}", .{ prop.name, @errorName(e) }) catch unreachable;
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
fn returnError(conn: *libdbus.Connection, message: *libdbus.Message, err: RequstError) void {
    const e = libdbus.Message.newError(message, err.name, err.message);
    defer e.deinit();
    _ = conn.send(e, null);
    conn.flush();
}
fn serviceHandler(data: ?*anyopaque, msg: *Message) void {
    const service: *Service = @ptrCast(@alignCast(data));
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
    if (destination == null) return;
    const eql = std.mem.eql;
    blk: {
        if ((eql(u8, destination.?, service.uniqueName))) break :blk;
        for (service.bus.ownerNames.items) |name| {
            if (eql(u8, name, destination.?)) break :blk;
        }
        return;
    }

    const conn = service.bus.conn;
    const reply = Message.newMethodReturn(msg);
    defer reply.deinit();
    var callError: RequstError = undefined;
    callError.isSet = false;
    const iter = libdbus.MessageIter.init(service.allocator);
    defer iter.deinit();
    handler: {
        // org.freedesktop.DBus.Introspectable/Introspect
        if (eql(u8, iface, "org.freedesktop.DBus.Introspectable") and eql(u8, member, "Introspect")) {
            iter.fromAppend(reply);
            const alloc = std.heap.page_allocator;
            var xml = std.ArrayList(u8).initCapacity(alloc, 64) catch unreachable;
            defer xml.deinit();
            const writer = xml.writer();
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
                var nodes = std.ArrayList([]const u8).init(alloc);
                defer nodes.deinit();
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
            iter.append(Type.String, xml.items) catch unreachable;
            break :handler;
        }
        // org.freedesktop.DBus.Peer/Ping
        if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "Ping")) {
            for (service.interfaces.items) |interface| {
                if (eql(u8, interface.path, path)) {
                    break;
                }
            }
            callError.set("org.freedesktop.DBus.Error.NotSupported", "Ping is not supported");
            break :handler;
        }
        // org.freedesktop.DBus.Peer/GetMachineId
        if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "GetMachineId")) {
            iter.fromAppend(reply);
            iter.append(Type.String, service.machineId) catch unreachable;
            break :handler;
        }
        // org.freedesktop.DBus.Properties/Get|Set|GetAll
        if (eql(u8, iface, "org.freedesktop.DBus.Properties")) {
            _ = iter.fromResult(msg);
            const iface__ = iter.next(Type.String).?;
            var arena = std.heap.ArenaAllocator.init(service.allocator);
            defer arena.deinit();
            if (eql(u8, member, "GetAll")) {
                for (service.interfaces.items) |interface| {
                    if (!eql(u8, interface.path, path)) continue;
                    if (!eql(u8, interface.name, iface__)) continue;
                    iter.fromAppend(reply);
                    appendAllProperties(
                        iter,
                        interface,
                        arena.allocator(),
                        &callError,
                    ) catch unreachable;
                    if (callError.isSet) {
                        returnError(conn, msg, callError);
                        break :handler;
                    }
                    break :handler;
                }
                callError.set("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
                break :handler;
            }
            const name = iter.next(Type.String).?;
            var op: enum { get, set } = undefined;
            if (eql(u8, member, "Get")) {
                op = .get;
            } else if (eql(u8, member, "Set")) {
                op = .set;
            } else {
                callError.set("org.freedesktop.DBus.Error.InvalidArgs", "Invalid arguments");
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
                                callError.set("org.freedesktop.DBus.Error.AccessDenied", "Property is not readable");
                                break :handler;
                            }
                            break :blk property;
                        }
                    }
                    callError.set("org.freedesktop.DBus.Error.UnknownProperty", "Unknown property");
                    break :handler;
                };
                const property = property_.?;
                switch (op) {
                    .get => {
                        const getter = interface.getter.?;
                        const out = libdbus.MessageIter.init(service.allocator);
                        defer out.deinit();
                        out.fromAppend(reply);
                        appendWithGetter(
                            out,
                            getter,
                            interface.instance,
                            name,
                            property.signature,
                            arena.allocator(),
                            &callError,
                        ) catch |err| {
                            const err_msg = std.fmt.allocPrint(arena.allocator(), "Failed to get property {s}: {s}", .{ name, @errorName(err) }) catch unreachable;
                            callError.set("org.freedesktop.DBus.Error.Failed", err_msg);
                            break :handler;
                        };
                        break :handler;
                    },
                    .set => {
                        var value = iter.next(Type.AnyVariant).?;
                        if (!eql(u8, property.signature, value.iter.getSignature())) {
                            callError.set("org.freedesktop.DBus.Error.InvalidArgs", "Invalid arguments");
                            break :handler;
                        }
                        const setter = interface.setter.?;
                        setter(interface.instance, name, value, &callError) catch |err| {
                            const err_msg = std.fmt.allocPrint(arena.allocator(), "Failed to set property {s}: {s}", .{ name, @errorName(err) }) catch unreachable;
                            callError.set("org.freedesktop.DBus.Error.Failed", err_msg);
                            break :handler;
                        };
                        break :handler;
                    },
                }
            }
            callError.set("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
            break :handler;
        }
        // org.freedesktop.DBus.ObjectManager/GetManagedObjects
        if (eql(u8, iface, "org.freedesktop.DBus.ObjectManager") and eql(u8, member, "GetManagedObjects") and eql(u8, "/", path)) {
            iter.fromAppend(reply);
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
                        &callError,
                    ) catch unreachable;
                    if (callError.isSet) {
                        returnError(conn, msg, callError);
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
                const in = libdbus.MessageIter.init(service.allocator);
                const out = libdbus.MessageIter.init(service.allocator);
                defer in.deinit();
                defer out.deinit();
                _ = in.fromResult(msg);
                out.fromAppend(reply);
                var arena = std.heap.ArenaAllocator.init(service.allocator);
                defer arena.deinit();
                method.func(interface.instance, msg.getSender(), arena.allocator(), in, out, &callError) catch |e| {
                    callError.set("org.freedesktop.DBus.Error.Failed", @errorName(e));
                    break :handler;
                };
                break :handler;
            }
            callError.set("org.freedesktop.DBus.Error.UnknownMethod", "Unknown method");
            break :handler;
        }
        callError.set("org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
        break :handler;
    }
    if (callError.isSet) {
        returnError(conn, msg, callError);
        return;
    }
    _ = conn.send(reply, null);
    conn.flush();
    return;
}
pub const MethodArgs = struct {
    direction: enum { in, out },
    name: ?[]const u8 = null,
    type: type,
    annotations: []const Annotation = &.{},
};
pub fn MethodFunc(T: type) type {
    return *const fn (self: *T, sender: []const u8, allocator: Allocator, in: *MessageIter, out: *MessageIter, err: *RequstError) anyerror!void;
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
        defer msg.deinit();
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
        defer msg.deinit();
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
        var callError: RequstError = undefined;
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
            if (callError.isSet) {
                @panic(std.fmt.allocPrint(std.heap.page_allocator, "cannot emit PropertiesChanged signal, error: {s}: {s}", .{ callError.name, callError.message }) catch unreachable);
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
fn makeIntrospect(comptime T: type, comptime introspect: Interface(T)) []const u8 {
    const baseInterface = @embedFile("base-interface.xml");
    comptime var result: []const u8 = baseInterface ++ "\n";
    comptime {
        result = result ++ std.fmt.comptimePrint("<interface name=\"{s}\">\n", .{introspect.name});
        for (introspect.method) |method| {
            result = result ++ std.fmt.comptimePrint("    <method name=\"{s}\">\n", .{method.name});
            for (method.args) |arg| {
                if (arg.name) |name| {
                    result = result ++ std.fmt.comptimePrint("        <arg name=\"{s}\" direction=\"{s}\" type=\"{s}\"/>\n", .{
                        name,
                        @tagName(arg.direction),
                        Type.signature(arg.type),
                    });
                } else {
                    result = result ++ std.fmt.comptimePrint("        <arg direction=\"{s}\" type=\"{s}\"/>\n", .{
                        @tagName(arg.direction),
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
            result = result ++ std.fmt.comptimePrint("    <property name=\"{s}\" type=\"{s}\" access=\"{s}\"/>\n", .{
                property.name,
                Type.signature(property.type),
                @tagName(property.access),
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
    isSet: bool,
    name: []const u8,
    message: []const u8,
    pub fn set(self: *@This(), name: []const u8, message: []const u8) void {
        self.name = name;
        self.message = message;
        self.isSet = true;
    }
};
const withGLibLoop = @import("bus.zig").withGLibLoop;
// TODO: 编写自动测试用例
test "service" {
    const TestInterface = struct {
        emitter: Emitter = undefined,
        fn tests(self: *@This(), _: []const u8, allocator: Allocator, in: *MessageIter, _: *MessageIter, err: *RequstError) !void {
            const str = try std.fmt.allocPrint(allocator, "test method called {s}", .{in.next(Type.String).?});
            self.emitter.emit("TestSignal", .{Type.String}, .{"hello"});
            print("test method called {s}\n", .{str});
            err.set("org.freedesktop.DBus.Error.Failed", "test error");
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
    glib.timeoutMainLoop(200);
}
