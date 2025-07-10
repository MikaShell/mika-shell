const dbus = @import("dbus");
const Allocator = std.mem.Allocator;
const Item = @import("item.zig").Item;
pub const ItemState = enum {
    added,
    removed,
    changed,
};
pub const Host = struct {
    const Self = @This();
    const Listener = struct {
        func: *const fn (host: *Self, state: ItemState, services: []const u8, data: ?*anyopaque) void,
        data: ?*anyopaque,
    };
    listeners: std.ArrayList(Listener),
    watcher: ?*dbus.Object,
    items: std.ArrayList(*Item),
    allocator: Allocator,
    bus: *dbus.Bus,
    dbus: *dbus.Object,
    pub fn init(allocator: Allocator, bus: *dbus.Bus) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        self.bus = bus;
        self.items = std.ArrayList(*Item).init(allocator);
        self.listeners = std.ArrayList(Listener).init(allocator);
        const watcher = bus.proxy(
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
        ) catch {
            return error.FailedToConnectToStatusNotifierWatcher;
        };
        if (!watcher.ping()) {
            return error.FailedToPingStatusNotifierWatcher;
        }
        self.watcher = watcher;
        const registerResult = watcher.call("RegisterStatusNotifierHost", .{dbus.String}, .{bus.uniqueName}, .{}) catch {
            return error.FailedToRegisterStatusNotifierHost;
        };
        defer registerResult.deinit();
        const allItems = watcher.get("RegisteredStatusNotifierItems", dbus.Array(dbus.String)) catch {
            return error.FailedToGetRegisteredStatusNotifierItems;
        };
        defer allItems.deinit();
        for (allItems.value) |name| {
            const item = try Item.init(allocator, bus, name);
            try item.addListener(onItemUpdated, self);
            try self.items.append(item);
        }
        watcher.connect("StatusNotifierItemRegistered", onStatusNotifierItemRegistered, self) catch |e| {
            if (e != dbus.DBusError) return e;
            return error.FailedToConnectToStatusNotifierItemRegistered;
        };
        watcher.connect("StatusNotifierItemUnregistered", onStatusNotifierItemUnregistered, self) catch |e| {
            if (e != dbus.DBusError) return e;
            return error.FailedToConnectToStatusNotifierItemUnregistered;
        };
        self.dbus = dbus.freedesktopDBus(bus) catch {
            return error.FailedToConnectToDBus;
        };
        self.dbus.connect("NameLost", onItemNameLost, self) catch {
            return error.FailedToConnectToNameLost;
        };
        return self;
    }
    fn onItemUpdated(item: *Item, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        self.triggerListeners(.changed, item.data.service);
    }
    pub fn addListener(self: *Self, func: *const fn (host: *Self, state: ItemState, services: []const u8, data: ?*anyopaque) void, data: ?*anyopaque) !void {
        try self.listeners.append(.{ .func = func, .data = data });
    }
    pub fn removeListener(self: *Self, func: *const fn (host: *Self, state: ItemState, services: []const u8, data: ?*anyopaque) void, data: ?*anyopaque) void {
        for (self.listeners.items, 0..) |listener, i| {
            if (listener.func == func and listener.data == data) {
                self.listeners.swapRemove(i);
                return;
            }
        }
    }
    fn triggerListeners(self: *Self, state: ItemState, services: []const u8) void {
        for (self.listeners.items) |listener| {
            listener.func(self, state, services, listener.data);
        }
    }
    fn onItemNameLost(e: dbus.Event, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const lostName = e.iter.next(dbus.String).?;
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.owner, lostName)) {
                triggerListeners(self, .removed, item.data.service);
                self.items.swapRemove(i).deinit();
                break;
            }
        }
    }
    fn onStatusNotifierItemRegistered(e: dbus.Event, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const service = e.iter.next(dbus.String).?;
        const item = Item.init(self.allocator, self.bus, service) catch {
            std.log.err("failed to create item: {s}", .{service});
            return;
        };
        item.addListener(onItemUpdated, self) catch unreachable;
        self.items.append(item) catch unreachable;
        triggerListeners(self, .added, service);
    }
    fn onStatusNotifierItemUnregistered(e: dbus.Event, data: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(data));
        const service = e.iter.next(dbus.String).?;
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.data.service, service)) {
                triggerListeners(self, .removed, service);
                self.items.swapRemove(i).deinit();
                break;
            }
        }
    }
    pub fn deinit(self: *Self) void {
        self.dbus.deinit();
        for (self.items.items) |item| {
            item.deinit();
        }
        self.items.deinit();
        if (self.watcher) |w| {
            blk: {
                const r = w.call("UnregisterStatusNotifierHost", .{dbus.String}, .{self.bus.uniqueName}, .{}) catch {
                    break :blk;
                };
                r.deinit();
            }
            w.deinit();
        }
        self.listeners.deinit();
        self.allocator.destroy(self);
    }
};

const glib = @import("glib");
const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
// test "tray-host" {
//     const allocator = testing.allocator;
//     const bus = try dbus.Bus.init(allocator, .Session);
//     defer bus.deinit();
//     const watcher = try dbus.withGLibLoop(bus);
//     defer watcher.deinit();
//     const host = try Host.init(allocator, bus);
//     defer host.deinit();
//     try host.addListener(struct {
//         fn f(_: *Host, state: ItemState, services: []const u8, _: ?*anyopaque) void {
//             print("state: {}, services: {s}\n", .{ state, services });
//         }
//     }.f, null);
//     glib.timeoutMainLoop(10_000);
// }
