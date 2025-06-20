const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const Allocator = std.mem.Allocator;
const Value = libdbus.Value;
const Error = libdbus.Error;
const Type = libdbus.Type;
const Message = libdbus.Message;
const common = @import("common.zig");

pub const Service = struct {
    const Self = @This();
    const Interfaces = std.ArrayList(struct {
        path: []const u8,
        iface: Interface(anyopaque),
    });
    conn: *libdbus.Connection,
    uniqueName: []const u8,
    err: Error,
    allocator: Allocator,
    name: []const u8,
    interfaces: Interfaces,
    watch: glib.FdWatch(Self),
    machineId: []const u8,
    listeners: std.ArrayList(common.Listener),
    pub fn init(allocator: Allocator, bus_type: libdbus.BusType, flag: libdbus.Connection.NameFlag, name: []const u8) !*Service {
        var err = Error.init();
        const conn = try libdbus.Connection.get(bus_type, err);
        const service = try allocator.create(Self);
        errdefer allocator.destroy(service);
        errdefer err.deinit();
        errdefer conn.unref();
        try conn.addMatch("", err);
        errdefer conn.removeMatch("", err) catch err.reset();
        service.* = Self{
            .conn = conn,
            .uniqueName = conn.getUniqueName(),
            .err = err,
            .allocator = allocator,
            .name = name,
            .interfaces = Interfaces.init(allocator),
            .watch = try glib.FdWatch(Self).add(try conn.getUnixFd(), serviceHandler, service),
            .machineId = libdbus.getLocalMachineId(),
            .listeners = std.ArrayList(common.Listener).init(allocator),
        };
        const r = try conn.requestName(name, flag, err);
        switch (r) {
            .PrimaryOwner => {},
            .InQueue => return error.NameInQueue,
            .Exists => return error.NameExists,
            .AlreadyOwner => return error.NameAlreadyOwner,
        }

        return service;
    }
    pub fn deinit(self: *Self) void {
        self.conn.removeMatch("", self.err) catch self.err.reset();
        self.watch.deinit();
        _ = self.conn.releaseName(self.name, self.err) catch {};
        self.conn.unref();
        self.err.deinit();
        for (self.interfaces.items) |interface| {
            self.allocator.free(interface.iface.method);
        }
        self.listeners.deinit();
        self.interfaces.deinit();
        self.allocator.destroy(self);
    }
    pub fn publish(self: *Self, comptime T: type, path: []const u8, interface: Interface(T)) !void {
        for (interface.property) |prop| {
            if ((prop.access == .readwrite or prop.access == .read) and interface.getter == null) {
                @panic("Property has 'read' access but no getter function provided");
            }
            if ((prop.access == .readwrite or prop.access == .write) and interface.setter == null) {
                @panic("Property has 'write' access but no setter function provided");
            }
        }

        const methods = try self.allocator.alloc(Method(anyopaque), interface.method.len);
        for (interface.method, 0..) |method, i| {
            methods[i] = Method(anyopaque){
                .name = method.name,
                .args = method.args,
                .func = @ptrCast(method.func),
                .annotations = method.annotations,
            };
        }
        if (interface.emitter) |e| e.* = .{
            .conn = self.conn,
            .path = path,
            .signals = interface.signal,
            .iface = interface.name,
            .instance = @ptrCast(interface.instance),
            .getter = @ptrCast(interface.getter),
        };
        const itface = Interface(anyopaque){
            .instance = @ptrCast(interface.instance),
            .name = interface.name,
            .method = methods,
            .signal = interface.signal,
            .property = interface.property,
            .getter = @ptrCast(interface.getter),
            .setter = @ptrCast(interface.setter),
        };
        try self.interfaces.append(.{ .path = path, .iface = itface });
    }
    pub fn connect(self: *Service, signal: []const u8, comptime T: type, handler: *const fn (common.Event, ?*T) void, data: ?*T) !void {
        try self.listeners.append(.{ .signal = signal, .handler = @ptrCast(handler), .data = @ptrCast(data) });
    }
    pub fn disconnect(self: *Service, signal: []const u8, comptime T: type, handler: *const fn (common.Event, ?*T) void) !void {
        for (self.listeners.items, 0..) |listener, i| {
            const h: *const fn (common.Event, ?*anyopaque) void = @ptrCast(handler);
            if (std.mem.eql(u8, listener.signal, signal) and listener.handler == h) {
                _ = self.listeners.swapRemove(i);
                return;
            }
        }
        return error.SignalOrHandlerNotFound;
    }
};
// FIXME: 移除此处的 'catch unreachable'
fn serviceHandler(service: *Service) bool {
    if (!service.conn.readWrite(-1)) return false;
    defer _ = service.conn.dispatch();
    const msg = service.conn.popMessage();
    if (msg == null) return true;
    const m = msg.?;
    defer m.deinit();
    const type_ = m.getType();
    switch (type_) {
        .MethodCall => {},
        .Signal => {
            const sender = m.getSender();
            const iface = m.getInterface();
            const path = m.getPath();
            const member = m.getMember();
            const destination = m.getDestination();
            const iter = libdbus.MessageIter.init(service.allocator) catch unreachable;
            defer iter.deinit();
            var e = common.Event{
                .sender = sender,
                .iface = iface,
                .path = path,
                .member = member,
                .serial = m.getSerial(),
                .destination = destination,
                .values = null,
            };
            if (iter.fromResult(m)) {
                e.values = iter.getAll() catch unreachable;
            }
            for (service.listeners.items) |listener| {
                if (std.mem.eql(u8, listener.signal, member)) {
                    listener.handler(e, listener.data);
                }
            }
            return true;
        },
        else => return true,
    }
    const iface = m.getInterface();
    const path = m.getPath();
    const member = m.getMember();
    const destination = m.getDestination();
    if (destination != null and !std.mem.eql(u8, destination.?, service.uniqueName)) return true;

    const eql = std.mem.eql;
    // org.freedesktop.DBus.Introspectable/Introspect
    if (eql(u8, iface, "org.freedesktop.DBus.Introspectable") and eql(u8, member, "Introspect")) {
        const reply = Message.newMethodReturn(m);
        defer reply.deinit();
        const iter = libdbus.MessageIter.init(service.allocator) catch unreachable;
        defer iter.deinit();
        iter.fromAppend(reply);
        const alloc = std.heap.page_allocator;
        var xml = std.ArrayList(u8).initCapacity(alloc, 64) catch unreachable;
        defer xml.deinit();
        const writer = xml.writer();
        writer.writeAll(
            \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd"><node>
        ) catch unreachable;
        if (eql(u8, path, "/")) {
            for (service.interfaces.items) |interface| {
                const node = std.fmt.allocPrint(alloc, "<node name=\"{s}\"/>\n", .{interface.path}) catch unreachable;
                defer alloc.free(node);
                writer.writeAll(node) catch unreachable;
            }
        } else {
            for (service.interfaces.items) |interface| {
                if (!eql(u8, interface.path, path)) continue;
                introspect(interface.iface, writer) catch unreachable;
            }
        }
        writer.writeAll("</node>") catch unreachable;
        iter.append(.{ .string = xml.items }) catch unreachable;
        _ = service.conn.send(reply, null);
        service.conn.flush();
        return true;
    }
    // org.freedesktop.DBus.Peer/Ping
    if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "Ping")) {
        for (service.interfaces.items) |interface| {
            if (eql(u8, interface.path, path)) {
                const reply = Message.newMethodReturn(m);
                defer reply.deinit();
                _ = service.conn.send(reply, null);
                service.conn.flush();
                return true;
            }
        }
    }
    // org.freedesktop.DBus.Peer/GetMachineId
    if (eql(u8, iface, "org.freedesktop.DBus.Peer") and eql(u8, member, "GetMachineId")) {
        const reply = Message.newMethodReturn(m);
        defer reply.deinit();
        const iter = libdbus.MessageIter.init(service.allocator) catch unreachable;
        defer iter.deinit();
        iter.fromAppend(reply);
        iter.append(.{ .string = service.machineId }) catch unreachable;
        _ = service.conn.send(reply, null);
        service.conn.flush();
        return true;
    }
    // org.freedesktop.DBus.Properties/Get|Set|GetAll
    if (eql(u8, iface, "org.freedesktop.DBus.Properties")) {
        const iter = libdbus.MessageIter.init(service.allocator) catch unreachable;
        defer iter.deinit();
        _ = iter.fromResult(m);
        const vals = iter.getAll() catch unreachable;
        if (eql(u8, member, "GetAll")) {
            const iface_ = vals[0].string;
            const reply = Message.newMethodReturn(m);
            defer reply.deinit();
            iter.fromAppend(reply);
            var arena = std.heap.ArenaAllocator.init(service.allocator);
            defer arena.deinit();
            var result = std.ArrayList(Value).init(service.allocator);
            defer result.deinit();
            for (service.interfaces.items) |interface| {
                if (!eql(u8, interface.path, path)) continue;
                if (!eql(u8, interface.iface.name, iface_)) continue;
                for (interface.iface.property) |property| {
                    if (property.access == .read or property.access == .readwrite) {
                        const getter = interface.iface.getter.?;
                        const value = arena.allocator().create(Value) catch unreachable;
                        value.* = getter(interface.iface.instance, property.name, arena.allocator()) catch |err| {
                            const err_msg = std.fmt.allocPrint(arena.allocator(), "Failed to get property {s}: {s}", .{ property.name, @errorName(err) }) catch unreachable;
                            const e = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.Failed", err_msg);
                            defer e.deinit();
                            _ = service.conn.send(e, null);
                            service.conn.flush();
                            return true;
                        };
                        result.append(Value{ .string = property.name }) catch unreachable;
                        result.append(Value{ .variant = value }) catch unreachable;
                    }
                }
            }
            iter.append(Value{ .dict = .{
                .items = result.items,
                .signature = "{sv}",
            } }) catch unreachable;
            _ = service.conn.send(reply, null);
            service.conn.flush();
            return true;
        }
        if (eql(u8, member, "Get")) {
            const iface_ = vals[0].string;
            const name = vals[1].string;
            for (service.interfaces.items) |interface| {
                if (!eql(u8, interface.path, path)) continue;
                if (!eql(u8, interface.iface.name, iface_)) continue;
                has_property: {
                    for (interface.iface.property) |property| {
                        if (std.mem.eql(u8, property.name, name)) {
                            break :has_property;
                        }
                    }
                    const err = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.UnknownProperty", "Unknown property");
                    defer err.deinit();
                    _ = service.conn.send(err, null);
                    service.conn.flush();
                    return true;
                }
                const getter = interface.iface.getter.?;
                var arena = std.heap.ArenaAllocator.init(service.allocator);
                defer arena.deinit();
                const value = getter(interface.iface.instance, name, arena.allocator()) catch |err| {
                    const err_msg = std.fmt.allocPrint(arena.allocator(), "Failed to get property {s}: {s}", .{ name, @errorName(err) }) catch unreachable;
                    const e = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.Failed", err_msg);
                    defer e.deinit();
                    _ = service.conn.send(e, null);
                    service.conn.flush();
                    return true;
                };
                const reply = Message.newMethodReturn(m);
                defer reply.deinit();
                iter.fromAppend(reply);
                iter.append(value) catch unreachable;
                _ = service.conn.send(reply, null);
                service.conn.flush();
                return true;
            }
            const e = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
            defer e.deinit();
            _ = service.conn.send(e, null);
            service.conn.flush();
            return true;
        }
        if (eql(u8, member, "Set")) {
            const iface_ = vals[0].string;
            const name = vals[1].string;
            const value = vals[2].variant.*;
            for (service.interfaces.items) |interface| {
                if (!eql(u8, interface.path, path)) continue;
                if (!eql(u8, interface.iface.name, iface_)) continue;
                has_property: {
                    for (interface.iface.property) |property| {
                        if (std.mem.eql(u8, property.name, name)) {
                            break :has_property;
                        }
                    }
                    const err = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.UnknownProperty", "Unknown property");
                    defer err.deinit();
                    _ = service.conn.send(err, null);
                    service.conn.flush();
                    return true;
                }
                const setter = interface.iface.setter.?;
                setter(interface.iface.instance, name, value) catch |err| {
                    const err_msg = std.fmt.allocPrint(std.heap.page_allocator, "Failed to set property {s}: {s}", .{ name, @errorName(err) }) catch unreachable;
                    defer std.heap.page_allocator.free(err_msg);
                    const e = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.Failed", err_msg);
                    defer e.deinit();
                    _ = service.conn.send(e, null);
                    service.conn.flush();
                    return true;
                };
                const reply = Message.newMethodReturn(m);
                defer reply.deinit();

                _ = service.conn.send(reply, null);
                service.conn.flush();
                return true;
            }
            const e = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.UnknownInterface", "Unknown interface");
            defer e.deinit();
            _ = service.conn.send(e, null);
            service.conn.flush();
            return true;
        }
    }
    for (service.interfaces.items) |interface| {
        if (!eql(u8, interface.path, path)) continue;
        for (interface.iface.method) |method| {
            if (!eql(u8, method.name, member)) continue;
            const iter = libdbus.MessageIter.init(service.allocator) catch unreachable;
            defer iter.deinit();
            var in: []const Value = &.{};
            const out_len = blk: {
                var len: usize = 0;
                for (method.args) |arg| {
                    if (arg.direction == .out) len += 1;
                }
                break :blk len;
            };
            const out: []const Value = service.allocator.alloc(Value, out_len) catch unreachable;
            defer service.allocator.free(out);
            if (iter.fromResult(m)) {
                in = iter.getAll() catch unreachable;
            }
            var arena = std.heap.ArenaAllocator.init(service.allocator);
            defer arena.deinit();
            method.func(interface.iface.instance, arena.allocator(), in, out) catch |e| {
                const err = libdbus.Message.newError(m, "org.freedesktop.DBus.Error.Failed", @errorName(e));
                defer err.deinit();
                _ = service.conn.send(err, null);
                service.conn.flush();
                return true;
            };
            const reply = Message.newMethodReturn(m);
            defer reply.deinit();
            iter.fromAppend(reply);
            for (out) |value| {
                iter.append(value) catch unreachable;
            }
            _ = service.conn.send(reply, null);
            service.conn.flush();
            return true;
        }
    }
    return true;
}
pub const MethodArgs = struct {
    direction: enum { in, out },
    name: ?[]const u8 = null,
    type: []const u8,
    annotations: []const Annotation = &.{},
};
pub fn Method(comptime T: anytype) type {
    return struct {
        name: []const u8,
        args: []const MethodArgs = &.{},
        func: *const fn (self: *T, allocator: Allocator, in: []const Value, out: []const Value) anyerror!void,
        annotations: []const Annotation = &.{},
    };
}
pub const SignalArgs = struct {
    name: ?[]const u8 = null,
    type: []const u8,
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
    signals: []const Signal,
    instance: *anyopaque,
    getter: ?*const fn (instance: *anyopaque, name: []const u8, allocator: Allocator) Value,
    pub fn emit(self: Emitter, name: []const u8, args: ?[]const Value) !void {
        blk: {
            for (self.signals) |s| {
                if (std.mem.eql(u8, s.name, name)) break :blk;
            }
            return error.InvalidSignal;
        }
        const msg = libdbus.Message.newSignal(self.path, self.iface, name);
        defer msg.deinit();
        const allocator = std.heap.page_allocator;
        var iter: ?*libdbus.MessageIter = null;
        defer if (iter != null) iter.?.deinit();
        if (args != null) {
            iter = try libdbus.MessageIter.init(allocator);
            iter.?.fromAppend(msg);
            for (args.?) |arg| {
                try iter.?.append(arg);
            }
        }
        _ = self.conn.send(msg, null);
        self.conn.flush();
    }
    pub fn emitPropertiesChanged(self: Emitter, changed: []const []const u8, invalidated: []const []const u8) !void {
        if (self.getter == null) @panic("No getter function provided for PropertiesChanged signal. Please provide a getter function for the interface");
        const msg = libdbus.Message.newSignal(self.path, "org.freedesktop.DBus.Properties", "PropertiesChanged");
        defer msg.deinit();
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const iter = try libdbus.MessageIter.init(allocator);
        defer iter.deinit();
        iter.fromAppend(msg);
        try iter.append(.{ .string = self.iface });
        var changed_array = try std.ArrayList(Value).initCapacity(allocator, changed.len * 2);
        defer changed_array.deinit();
        for (changed) |name| {
            try changed_array.append(Value{ .string = name });
            const value = self.getter.?(self.instance, name, allocator);
            try changed_array.append(Value{ .variant = &value });
        }
        var invalidated_array = try std.ArrayList(Value).initCapacity(allocator, invalidated.len);
        for (invalidated) |name| {
            try invalidated_array.append(Value{ .string = name });
        }
        try iter.append(Value{ .dict = .{
            .items = changed_array.items,
            .signature = "{sv}",
        } });
        try iter.append(Value{ .array = .{
            .items = invalidated_array.items,
            .type = .string,
        } });
        _ = self.conn.send(msg, null);
        self.conn.flush();
    }
};
pub const Annotation = struct {
    name: []const u8,
    value: []const u8,
};
pub const Property = struct {
    name: []const u8,
    type: []const u8,
    annotations: []const Annotation = &.{},
    access: enum { read, write, readwrite },
};
pub fn Interface(comptime T: anytype) type {
    return struct {
        name: []const u8,
        instance: *T,
        emitter: ?*Emitter = null,
        getter: ?*const fn (self: *T, name: []const u8, allocator: Allocator) anyerror!Value = null,
        setter: ?*const fn (self: *T, name: []const u8, value: Value) anyerror!void = null,
        method: []const Method(T) = &.{},
        signal: []const Signal = &.{},
        property: []const Property = &.{},
        annotations: []const Annotation = &.{},
    };
}
fn introspect(interface: Interface(anyopaque), writer: std.ArrayList(u8).Writer) !void {
    const baseInterface = @embedFile("base-interface.xml");
    try writer.writeAll(baseInterface);
    try std.fmt.format(writer, "<interface name=\"{s}\">", .{interface.name});
    for (interface.method) |method| {
        try std.fmt.format(writer, "<method name=\"{s}\">", .{method.name});
        for (method.args) |arg| {
            if (arg.name) |name| {
                try std.fmt.format(writer, "<arg name=\"{s}\" direction=\"{s}\" type=\"{s}\"/>", .{
                    name,
                    @tagName(arg.direction),
                    arg.type,
                });
            } else {
                try std.fmt.format(writer, "<arg direction=\"{s}\" type=\"{s}\"/>", .{
                    @tagName(arg.direction),
                    arg.type,
                });
            }
        }
        try writer.writeAll("</method>");
    }
    for (interface.signal) |signal| {
        try std.fmt.format(writer, "<signal name=\"{s}\">", .{signal.name});
        for (signal.args) |arg| {
            if (arg.name) |name| {
                try std.fmt.format(writer, "<arg name=\"{s}\" type=\"{s}\"/>", .{
                    name,
                    arg.type,
                });
            } else {
                try std.fmt.format(writer, "<arg type=\"{s}\"/>", .{
                    arg.type,
                });
            }
        }
        try writer.writeAll("</signal>");
    }
    for (interface.property) |property| {
        try std.fmt.format(writer, "<property name=\"{s}\" type=\"{s}\" access=\"{s}\"/>", .{
            property.name,
            property.type,
            @tagName(property.access),
        });
    }
    try writer.writeAll("</interface>");
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
test "service" {
    const TestInterface = struct {
        emitter: Emitter = undefined,
        fn tests(self: *@This(), allocator: Allocator, in: []const Value, _: []const Value) !void {
            const str = try std.fmt.allocPrint(allocator, "test method called {any}\n", .{in});
            try self.emitter.emit("TestSignal", &.{.{ .string = "hello" }});
            print("test method called {any} {s}\n", .{ in, str });
        }
        fn get(_: *@This(), _: []const u8, _: Allocator) !Value {
            return Value{ .string = "test property value" };
        }
        fn set(self: *@This(), _: []const u8, value: Value) !void {
            print("test property set to {any}\n", .{value});
            try self.emitter.emitPropertiesChanged(&.{"TestProperty"}, &.{"TestProperty2"});
        }
    };
    var testInterface = TestInterface{};
    testInterface = TestInterface{};
    const allocator = testing.allocator;
    const service = try Service.init(allocator, .Session, .DoNotQueue, "com.example.MikaShellZ");
    defer service.deinit();
    test_main_loop(300);
}
