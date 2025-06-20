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
    pub fn registerItem(self: *Self, _: Allocator, in: []const dbus.Value, _: []const dbus.Value) !void {
        try self.items.append(in[0].string);
        try self.emiter.emit("StatusNotifierItemRegistered", &.{in[0]});
    }
    pub fn registerHost(self: *Self, _: Allocator, in: []const dbus.Value, _: []const dbus.Value) !void {
        try self.hosts.append(in[0].string);
        try self.emiter.emit("StatusNotifierHostRegistered", &.{in[0]});
    }
    pub fn get(self: *Self, name: []const u8, alloc: Allocator) !dbus.Value {
        if (std.mem.eql(u8, name, "ProtocolVersion")) return dbus.Value{ .int32 = 0 };
        if (std.mem.eql(u8, name, "RegisteredStatusNotifierItems")) {
            var items = try alloc.alloc(dbus.Value, self.items.items.len);
            for (self.items.items, 0..) |item, i| {
                items[i] = dbus.Value{ .string = item };
            }
            return dbus.Value{ .array = .{ .items = items, .type = dbus.Type.string } };
        }
        if (std.mem.eql(u8, name, "IsStatusNotifierHostRegistered")) {
            return dbus.Value{ .boolean = self.hosts.items.len > 0 };
        }
        return error.UnknownProperty;
    }
    fn onNameOwnerChanged(e: dbus.Event, self_: ?*Self) void {
        const self = self_.?;
        const oldOwner = e.values.?[1].string;
        if (std.mem.eql(u8, oldOwner, "")) return;
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, oldOwner, item)) {
                _ = self.items.swapRemove(i);
                self.emiter.emit("StatusNotifierItemUnregistered", &.{dbus.Value{ .string = item }}) catch {};
                return;
            }
        }
        for (self.hosts.items, 0..) |host, i| {
            if (std.mem.eql(u8, oldOwner, host)) {
                _ = self.hosts.swapRemove(i);
                self.emiter.emit("StatusNotifierHostUnregistered", null) catch {};
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
        .instance = watcher,
        .emitter = &watcher.emiter,
        .getter = Watcher.get,
        .method = &.{
            dbus.Method(Watcher){
                .name = "RegisterStatusNotifierItem",
                .func = Watcher.registerItem,
                .args = &.{dbus.MethodArgs{ .name = "service", .direction = .in, .type = "s" }},
            },
            dbus.Method(Watcher){
                .name = "RegisterStatusNotifierHost",
                .func = Watcher.registerHost,
                .args = &.{dbus.MethodArgs{ .name = "service", .direction = .in, .type = "s" }},
            },
        },
        .property = &.{
            dbus.Property{
                .name = "ProtocolVersion",
                .type = "i",
                .access = .read,
            },
            dbus.Property{
                .name = "RegisteredStatusNotifierItems",
                .type = "as",
                .access = .read,
            },
            dbus.Property{
                .name = "IsStatusNotifierHostRegistered",
                .type = "b",
                .access = .read,
            },
        },
        .signal = &.{
            dbus.Signal{
                .name = "StatusNotifierItemRegistered",
                .args = &.{dbus.SignalArgs{ .name = "service", .type = "s" }},
            },
            dbus.Signal{
                .name = "StatusNotifierItemUnregistered",
                .args = &.{dbus.SignalArgs{ .name = "service", .type = "s" }},
            },
            dbus.Signal{
                .name = "StatusNotifierHostRegistered",
            },
            dbus.Signal{
                .name = "StatusNotifierHostUnregistered",
            },
        },
    });
    try service.connect("NameOwnerChanged", Watcher, Watcher.onNameOwnerChanged, watcher);
    test_main_loop(200);
}
