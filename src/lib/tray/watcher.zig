const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const Interface = dbus.Interface(Watcher){
    .name = "org.kde.StatusNotifierWatcher",
    .getter = Watcher.get,
    .method = &.{
        dbus.Method(Watcher){
            .name = "RegisterStatusNotifierItem",
            .func = Watcher.registerItem,
            .args = &.{dbus.MethodArgs{ .name = "service", .direction = .in, .type = dbus.String }},
        },
        dbus.Method(Watcher){
            .name = "RegisterStatusNotifierHost",
            .func = Watcher.registerHost,
            .args = &.{dbus.MethodArgs{ .name = "service", .direction = .in, .type = dbus.String }},
        },
    },
    .property = &.{
        dbus.Property{
            .name = "ProtocolVersion",
            .type = dbus.Int32,
            .access = .read,
        },
        dbus.Property{
            .name = "RegisteredStatusNotifierItems",
            .type = dbus.Array(dbus.String),
            .access = .read,
        },
        dbus.Property{
            .name = "IsStatusNotifierHostRegistered",
            .type = dbus.Boolean,
            .access = .read,
        },
    },
    .signal = &.{
        dbus.Signal{
            .name = "StatusNotifierItemRegistered",
            .args = &.{dbus.SignalArgs{ .name = "service", .type = dbus.String }},
        },
        dbus.Signal{
            .name = "StatusNotifierItemUnregistered",
            .args = &.{dbus.SignalArgs{ .name = "service", .type = dbus.String }},
        },
        dbus.Signal{
            .name = "StatusNotifierHostRegistered",
        },
        dbus.Signal{
            .name = "StatusNotifierHostUnregistered",
        },
    },
};
pub const Watcher = struct {
    const Self = @This();
    allocator: Allocator,
    emiter: dbus.Emitter,
    items: std.ArrayList([]const u8),
    hosts: std.ArrayList([]const u8),
    bus: *dbus.Bus,

    pub fn init(allocator: Allocator, bus: *dbus.Bus) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.* = Self{
            .allocator = allocator,
            .items = std.ArrayList([]const u8).init(allocator),
            .hosts = std.ArrayList([]const u8).init(allocator),
            .bus = bus,
            .emiter = undefined,
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        _ = self.bus.releaseName("org.kde.StatusNotifierWatcher") catch {};
        _ = self.bus.dbus.disconnect("NameOwnerChanged", Watcher.onNameOwnerChanged, self) catch {};
        self.bus.unpublish("/StatusNotifierWatcher", Interface.name);
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        for (self.hosts.items) |host| {
            self.allocator.free(host);
        }
        self.items.deinit();
        self.hosts.deinit();
        self.allocator.destroy(self);
    }
    pub fn publish(self: *Self) !void {
        try self.bus.requestName("org.kde.StatusNotifierWatcher", .DoNotQueue);
        try self.bus.publish(Watcher, "/StatusNotifierWatcher", Interface, self, &self.emiter);
        try self.bus.dbus.connect("NameOwnerChanged", Watcher.onNameOwnerChanged, self);
    }
    fn registerItem(self: *Self, sender: []const u8, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.RequstError) !void {
        const service = in.next(dbus.String).?;
        var busName: []const u8 = service;
        var path: []const u8 = "/StatusNotifierItem";
        if (service[0] == '/') {
            path = service;
            busName = sender;
        }
        const item = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ busName, path });
        try self.items.append(item);
        self.emiter.emit("StatusNotifierItemRegistered", .{dbus.String}, .{item});
    }
    fn registerHost(self: *Self, _: []const u8, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.RequstError) !void {
        const host = in.next(dbus.String).?;
        try self.hosts.append(try self.allocator.dupe(u8, host));
        self.emiter.emit("StatusNotifierHostRegistered", .{}, null);
    }
    fn get(self: *Self, name: []const u8, _: Allocator, out: *dbus.MessageIter, _: *dbus.RequstError) !void {
        if (std.mem.eql(u8, name, "ProtocolVersion")) {
            try out.append(dbus.Int32, 0);
            return;
        }
        if (std.mem.eql(u8, name, "RegisteredStatusNotifierItems")) {
            try out.append(dbus.Array(dbus.String), self.items.items);
            return;
        }
        if (std.mem.eql(u8, name, "IsStatusNotifierHostRegistered")) {
            try out.append(dbus.Boolean, self.hosts.items.len > 0);
            return;
        }
        return error.UnknownProperty;
    }
    fn onNameOwnerChanged(e: dbus.Event, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        _ = e.iter.next(dbus.String).?;
        const oldOwner = e.iter.next(dbus.String).?;
        if (std.mem.eql(u8, oldOwner, "")) return;
        for (self.items.items, 0..) |item, i| {
            if (std.mem.startsWith(u8, item, oldOwner)) {
                _ = self.items.swapRemove(i);
                self.emiter.emit("StatusNotifierItemUnregistered", .{dbus.String}, .{item});
                self.allocator.free(item);
                return;
            }
        }
        for (self.hosts.items, 0..) |host, i| {
            if (std.mem.startsWith(u8, host, oldOwner)) {
                _ = self.hosts.swapRemove(i);
                self.emiter.emit("StatusNotifierHostUnregistered", .{}, null);
                self.allocator.free(host);
                return;
            }
        }
    }
};
const WatcherInterface = dbus.Interface(Watcher);
const glib = @import("glib");
const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
test "tray-watcher" {
    const allocator = std.testing.allocator;
    const bus = try dbus.Bus.init(allocator, .Session);
    defer bus.deinit();
    const watch = try dbus.withGLibLoop(bus);
    defer watch.deinit();
    const watcher = try Watcher.init(allocator, bus);
    defer watcher.deinit();
    watcher.publish() catch |err| {
        print("src/lib/tray/watcher.zig: Cannot init Watcher: {any}\n", .{err});
        return;
    };
    glib.timeoutMainLoop(200);
}
