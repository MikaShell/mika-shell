const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const Watcher = struct {
    const Self = @This();
    allocator: Allocator,
    emiter: dbus.Emitter,
    items: std.ArrayList([]const u8),
    hosts: std.ArrayList([]const u8),
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .items = std.ArrayList([]const u8).init(allocator),
            .hosts = std.ArrayList([]const u8).init(allocator),
            .emiter = undefined,
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.hosts.deinit();
        self.allocator.destroy(self);
    }
    pub fn registerItem(self: *Self, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.CallError) !void {
        const item = try in.next(dbus.String);
        try self.items.append(item);
        self.emiter.emit("StatusNotifierItemRegistered", .{dbus.String}, .{item});
    }
    pub fn registerHost(self: *Self, _: Allocator, in: *dbus.MessageIter, _: *dbus.MessageIter, _: *dbus.CallError) !void {
        const host = try in.next(dbus.String);
        try self.hosts.append(host);
        self.emiter.emit("StatusNotifierHostRegistered", .{}, null);
    }
    fn get(self: *Self, name: []const u8, _: Allocator, out: *dbus.MessageIter, _: *dbus.CallError) !void {
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
    fn onNameOwnerChanged(e: dbus.Event, self_: ?*Self) void {
        const self = self_.?;
        _ = e.iter.next(dbus.String) catch unreachable;
        const oldOwner = e.iter.next(dbus.String) catch unreachable;
        if (std.mem.eql(u8, oldOwner, "")) return;
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, oldOwner, item)) {
                _ = self.items.swapRemove(i);
                self.emiter.emit("StatusNotifierItemUnregistered", .{dbus.String}, .{item});
                return;
            }
        }
        for (self.hosts.items, 0..) |host, i| {
            if (std.mem.eql(u8, oldOwner, host)) {
                _ = self.hosts.swapRemove(i);
                self.emiter.emit("StatusNotifierHostUnregistered", .{}, null);
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
test "tray" {
    const allocator = std.testing.allocator;
    const service = try dbus.Service.init(allocator, .Session, .ReplaceExisting, "org.kde.StatusNotifierWatcher");
    defer service.deinit();
    const watcher = try Watcher.init(allocator);
    defer watcher.deinit();
    try service.publish(Watcher, "/StatusNotifierWatcher", dbus.Interface(Watcher){
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
    }, watcher, &watcher.emiter);
    try service.connect("NameOwnerChanged", Watcher, Watcher.onNameOwnerChanged, watcher);
    test_main_loop(200);
}
