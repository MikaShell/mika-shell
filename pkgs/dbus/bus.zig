const libdbus = @import("libdbus.zig");
const std = @import("std");
const glib = @import("glib");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const Error = libdbus.Error;
const Type = libdbus.Types;
const Message = libdbus.Message;
const object = @import("object.zig");
const service = @import("service.zig");
const DBusError = libdbus.DBusError;
/// 仅包含 error.DBusError 和 error.OutOfMemory
pub const Errors = error{
    DBusError,
    OutOfMemory,
};
pub fn readWrite(bus: *Bus, timeout_milliseconds: i32) bool {
    return bus.conn.readWrite(timeout_milliseconds);
}
pub fn dispatch(bus: *Bus) libdbus.DispatchStatus {
    return bus.conn.dispatch();
}
pub const GLibWatch = glib.FdWatch(Bus);
pub fn withGLibLoop(bus: *Bus) !GLibWatch {
    return try GLibWatch.add(try bus.conn.getUnixFd(), struct {
        fn cb(b: *Bus) bool {
            if (!b.conn.readWrite(-1)) return false;
            while (b.conn.dispatch() != .Complete) {}
            return true;
        }
    }.cb, bus);
}
pub const MatchRule = struct {
    type: ?enum {
        signal,
        method_call,
        method_return,
        @"error",
    } = null,
    sender: ?[]const u8 = null,
    interface: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    member: ?[]const u8 = null,
    path: ?[]const u8 = null,
    path_namespace: ?[]const u8 = null,
    arg: []?[]const u8 = &.{},
    arg_path: []?[]const u8 = &.{},
    fn toString(self: MatchRule, allocator: Allocator) Allocator.Error![]const u8 {
        var str = std.ArrayList(u8).init(allocator);
        defer str.deinit();
        const writer = str.writer();
        const format = std.fmt.format;
        if (self.type) |t| {
            try format(writer, "type='{s}',", .{@tagName(t)});
        }
        if (self.sender) |s| {
            try format(writer, "sender='{s}',", .{s});
        }
        if (self.interface) |i| {
            try format(writer, "interface='{s}',", .{i});
        }
        if (self.destination) |d| {
            try format(writer, "destination='{s}',", .{d});
        }
        if (self.member) |m| {
            try format(writer, "member='{s}',", .{m});
        }
        if (self.path) |p| {
            try format(writer, "path='{s}',", .{p});
        }
        if (self.path_namespace) |n| {
            try format(writer, "path_namespace='{s}',", .{n});
        }
        for (self.arg, 0..) |a, i| {
            if (a == null) continue;
            try format(writer, "arg{d}='{s}',", .{ i, a.? });
        }
        for (self.arg_path, 0..) |ap, i| {
            if (ap == null) continue;
            try format(writer, "arg{d}_path='{s}',", .{ i, ap.? });
        }
        _ = str.pop();
        try str.append('\x00');
        return (try str.toOwnedSlice());
    }
    fn eql(a: MatchRule, b: MatchRule) bool {
        if (a.type != b.type) return false;
        const eqls = std.mem.eql;
        if (a.sender != null and b.sender != null and !eqls(u8, a.sender.?, b.sender.?)) return false;
        if (a.interface != null and b.interface != null and !eqls(u8, a.interface.?, b.interface.?)) return false;
        if (a.destination != null and b.destination != null and !eqls(u8, a.destination.?, b.destination.?)) return false;
        if (a.member != null and b.member != null and !eqls(u8, a.member.?, b.member.?)) return false;
        if (a.path != null and b.path != null and !eqls(u8, a.path.?, b.path.?)) return false;
        if (a.path_namespace != null and b.path_namespace != null and !eqls(u8, a.path_namespace.?, b.path_namespace.?)) return false;
        if (a.arg.len != b.arg.len) return false;
        if (a.arg_path.len != b.arg_path.len) return false;
        for (a.arg, 0..) |a_arg, i| {
            if (a_arg == null and b.arg[i] == null) continue;
            if (a_arg == null or b.arg[i] == null) return false;
            if (!eqls(u8, a_arg.?, b.arg[i].?)) return false;
        }
        for (a.arg_path, 0..) |a_arg_path, i| {
            if (a_arg_path == null and b.arg_path[i] == null) continue;
            if (a_arg_path == null or b.arg_path[i] == null) return false;
            if (!eqls(u8, a_arg_path.?, b.arg_path[i].?)) return false;
        }
        return true;
    }
};
pub const Filter = *const fn (data: ?*anyopaque, msg: *Message) void;
const FilterWrapper = struct {
    rule: MatchRule,
    filter: Filter,
    data: ?*anyopaque,
    fn call(_: ?*libdbus.Connection, msg: ?*libdbus.Message, self: ?*anyopaque) callconv(.c) libdbus.HandlerResult {
        const wrapper: *FilterWrapper = @ptrCast(@alignCast(self));
        if (msg == null) return .NotYetHandled;
        const m = msg.?;
        const rule = wrapper.rule;
        const type_ = m.getType();
        const sender = m.getSender();
        const iface = m.getInterface();
        const path = m.getPath();
        const member = m.getMember();
        const eql = std.mem.eql;
        if (rule.type != null and !eql(u8, @tagName(type_), @tagName(rule.type.?))) return .NotYetHandled;
        if (rule.sender != null and !eql(u8, sender, rule.sender.?)) return .NotYetHandled;
        if (rule.interface != null) {
            if (iface == null) return .NotYetHandled;
            if (!eql(u8, iface.?, rule.interface.?)) return .NotYetHandled;
        }
        if (rule.member != null) {
            if (member == null) return .NotYetHandled;
            if (!eql(u8, member.?, rule.member.?)) return .NotYetHandled;
        }
        if (rule.path != null) {
            if (path == null) return .NotYetHandled;
            if (!eql(u8, path.?, rule.path.?)) return .NotYetHandled;
        }
        if (rule.path_namespace != null) {
            if (path == null) return .NotYetHandled;
            if (!eql(u8, path.?, rule.path_namespace.?)) return .NotYetHandled;
        }
        var iter: ?*libdbus.MessageIter = null;
        defer if (iter) |i| i.deinit();
        const allocator = std.heap.page_allocator;
        if (rule.arg.len > 0 or rule.arg_path.len > 0) {
            iter = libdbus.MessageIter.init(allocator);
        }
        for (rule.arg) |a| {
            if (a == null) {
                iter.?.skip();
                continue;
            }
            const t: Type.Tags = iter.?.getArgType();
            var str: ?[]const u8 = null;
            defer if (str) |s| allocator.free(s);
            switch (t) {
                .byte,
                .int16,
                .uint16,
                .int32,
                .uint32,
                .int64,
                .uint64,
                .unix_fd,
                => {
                    const d = iter.?.next(Type.Int64) orelse return .NotYetHandled;
                    str = std.fmt.allocPrint(allocator, "{}", .{d}) catch @panic("OOM");
                },
                .double => {
                    const f = iter.?.next(Type.Double) orelse return .NotYetHandled;
                    str = std.fmt.allocPrint(allocator, "{}", .{f}) catch @panic("OOM");
                },
                .boolean => {
                    const b = iter.?.next(Type.Boolean) orelse return .NotYetHandled;
                    str = std.fmt.allocPrint(allocator, "{}", .{b}) catch @panic("OOM");
                },
                .string, .object_path, .signature => {
                    const s = iter.?.next(Type.String) orelse return .NotYetHandled;
                    str = allocator.dupe(u8, s) catch @panic("OOM");
                },
                else => return .NotYetHandled,
            }
            if (!std.mem.eql(u8, a.?, str.?)) return .NotYetHandled;
        }
        for (rule.arg_path) |a| {
            if (a == null) {
                iter.?.skip();
                continue;
            }
            const t: Type.Tags = iter.?.getArgType();
            var str: ?[]const u8 = null;
            defer if (str) |s| allocator.free(s);
            switch (t) {
                .object_path,
                => {
                    const s = iter.?.next(Type.String) orelse return .NotYetHandled;
                    str = allocator.dupe(u8, s) catch @panic("OOM");
                },
                else => return .NotYetHandled,
            }
            if (!std.mem.startsWith(u8, str.?, a.?)) return .NotYetHandled;
        }
        wrapper.filter(wrapper.data, msg.?);
        return .NotYetHandled;
    }
};
pub const Bus = struct {
    const Self = @This();
    conn: *libdbus.Connection,
    uniqueName: []const u8,
    err: Error,
    allocator: Allocator,
    dbus: *object.Object,
    filters: std.ArrayList(*FilterWrapper),
    objects: std.ArrayList(*object.Object),
    /// 获取 bus
    ///
    /// 底层使用 libdbus 的 `dbus_bus_get_private()` 函数获取 bus 连接.
    /// 在调用 Bus 的函数时,如果捕获到 `dbus.DBusError` 错误,可以从 err 字段中获取错误信息,
    pub fn init(allocator: Allocator, bus_type: libdbus.BusType) !*Bus {
        var err = Error.init();
        const conn = try libdbus.Connection.get(bus_type, err);
        const bus = try allocator.create(Self);
        errdefer allocator.destroy(bus);
        errdefer err.deinit();
        errdefer conn.close();
        bus.* = Bus{
            .conn = conn,
            .uniqueName = conn.getUniqueName(),
            .err = err,
            .allocator = allocator,
            .dbus = undefined,
            .objects = std.ArrayList(*object.Object).init(allocator),
            .filters = std.ArrayList(*FilterWrapper).init(allocator),
        };
        bus.dbus = try common.freedesktopDBus(bus);
        bus.dbus.connect("NameOwnerChanged", struct {
            fn f(e: common.Event, data: ?*anyopaque) void {
                const bus_: *Self = @ptrCast(@alignCast(data));
                const values = e.iter.getAll(.{ Type.String, Type.String, Type.String }) catch unreachable;
                const oldOwner = values[1];
                const newOwner = values[2];
                const isNewService = std.mem.eql(u8, oldOwner, "");
                for (bus_.objects.items) |obj| {
                    if (std.mem.eql(u8, obj.uniqueName, "")) {
                        if (isNewService) {
                            const resp = bus_.dbus.call("GetNameOwner", .{Type.String}, .{obj.name}, .{Type.String}) catch {
                                continue;
                            };
                            defer resp.deinit();
                            const uniqueName = resp.values.?[0];
                            const uniqueName_ = obj.allocator.dupeZ(u8, uniqueName) catch @panic("OOM");
                            if (std.mem.eql(u8, uniqueName_, newOwner)) {
                                obj.uniqueName = uniqueName_;
                                break;
                            } else {
                                obj.allocator.free(uniqueName_);
                            }
                        }
                    } else if (std.mem.eql(u8, obj.uniqueName, oldOwner)) {
                        const old = obj.uniqueName;
                        obj.uniqueName = obj.allocator.dupeZ(u8, newOwner) catch @panic("OOM");
                        obj.allocator.free(old);
                    }
                }
            }
        }.f, bus) catch {
            bus.replaceError(&bus.dbus.err);
            return error.DBusError;
        };
        return bus;
    }
    fn replaceError(self: *Self, err: *Error) void {
        const old = self.err.ptr;
        self.err.ptr = err.ptr;
        err.ptr = old;
    }
    pub fn deinit(self: *Self) void {
        for (self.objects.items) |item| {
            item.deinit();
        }
        for (self.filters.items) |item| {
            self.conn.removeFilter(@ptrCast(&FilterWrapper.call), item);
            self.allocator.destroy(item);
        }
        self.filters.deinit();
        self.objects.deinit();
        self.conn.close();
        self.err.deinit();
        self.allocator.destroy(self);
    }
    /// 获取指定名称的代理
    ///
    /// 获得一个 dbus.Object 实例,该实例代表一个 dbus 服务.
    /// 如果你需要调用某个 dbus 服务的接口,你应该使用该函数获取对应的 dbus.Object 实例.
    pub fn proxy(self: *Self, name: []const u8, path: []const u8, iface: []const u8) !*object.Object {
        const req = try object.baseCall(self.allocator, self.conn, self.err, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", .{Type.String}, .{name}, .{Type.String});
        defer req.deinit();
        const obj = try self.allocator.create(object.Object);
        errdefer self.allocator.destroy(obj);
        obj.* = .{
            .bus = self,
            .name = try self.allocator.dupeZ(u8, name),
            .path = try self.allocator.dupeZ(u8, path),
            .iface = try self.allocator.dupeZ(u8, iface),
            .uniqueName = try self.allocator.dupeZ(u8, req.values.?[0]),
            .err = Error.init(),
            .listeners = std.ArrayList(common.Listener).init(self.allocator),
            .allocator = self.allocator,
        };
        try self.objects.append(obj);
        return obj;
    }
    pub const OwnerError = error{
        NameInQueue,
        NameExists,
        NameAlreadyOwner,
    } || Errors;
    /// 获取名称并返回一个 service.Service 实例.
    /// 如果你需要发布某个 dbus 服务,你应该使用该函数
    pub fn owner(self: *Self, name: []const u8, flag: libdbus.Connection.NameFlag) OwnerError!*service.Service {
        const allocator = self.allocator;
        const s = try allocator.create(service.Service);
        errdefer allocator.destroy(s);
        s.* = service.Service{
            .allocator = allocator,
            .bus = self,
            .name = name,
            .interfaces = std.ArrayList(service.Service.Interface_).init(allocator),
            .machineId = undefined,
            .uniqueName = undefined,
            .err = undefined,
        };

        var err = Error.init();
        errdefer err.deinit();

        s.uniqueName = self.conn.getUniqueName();
        s.err = err;
        s.machineId = libdbus.getLocalMachineId();

        const r = try self.conn.requestName(name, flag, err);
        switch (r) {
            .PrimaryOwner => {},
            .InQueue => return error.NameInQueue,
            .Exists => return error.NameExists,
            .AlreadyOwner => return error.NameAlreadyOwner,
        }
        return s;
    }
    /// 向 bus 添加过滤器, 过滤器会在收到 dbus 消息时调用.
    ///
    /// 注意,此处的 rule 仅用于对 dbus 消息进行过滤, 并不会向 dbus 发送 AddMatch 请求.
    /// 你需要调用 `addMatch()` 方法来向 dbus 发送 AddMatch 请求.
    pub fn addFilter(self: *Self, rule: MatchRule, filter: Filter, data: ?*anyopaque) Allocator.Error!bool {
        const wrapper = try self.allocator.create(FilterWrapper);
        errdefer self.allocator.destroy(wrapper);
        wrapper.* = FilterWrapper{
            .rule = rule,
            .filter = filter,
            .data = data,
        };
        if (self.conn.addFilter(@ptrCast(&FilterWrapper.call), wrapper, null)) {
            try self.filters.append(wrapper);
            return true;
        } else {
            self.allocator.destroy(wrapper);
            return false;
        }
    }
    pub fn removeFilter(self: *Self, rule: MatchRule, filter: Filter, data: ?*anyopaque) void {
        for (self.filters.items, 0..) |wrapper, i| {
            if (wrapper.filter == filter and wrapper.data == data and wrapper.rule.eql(rule)) {
                self.conn.removeFilter(@ptrCast(&FilterWrapper.call), wrapper);
                _ = self.filters.swapRemove(i);
                self.allocator.destroy(wrapper);
                return;
            }
        }
    }
    pub fn addMatch(self: *Self, rule: MatchRule) Errors!void {
        const match = try rule.toString(self.allocator);
        defer self.allocator.free(match);
        try self.conn.addMatch(match, self.err);
    }
    pub fn removeMatch(self: *Self, rule: MatchRule) Errors!void {
        const match = try rule.toString(self.allocator);
        defer self.allocator.free(match);
        try self.conn.removeMatch(match, self.err);
    }
};
